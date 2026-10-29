--[[ 

Net
ModuleScript
/ReplicatedStorage/Shared/Net

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The one place remotes are named, created and wrapped.
--   Server: Net.setup() once at boot, then Net.handle / Net.fire / Net.fireAll.
--   Client: Net.invoke / Net.on (waits for the server-created folder).
--
-- Every server handler goes through a per-player token-bucket rate limit, a
-- payload guard (only a few nil / boolean / finite number / short string
-- arguments: no handler takes tables or Instances) and a pcall, and always
-- answers with a Response table ({ Ok = bool, ... }). Rejected calls are
-- strikes: a client that keeps flooding gets a warning in the log, then is
-- kicked.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(script.Parent.Types)

type Response = Types.Response

local FOLDER_NAME = "Remotes"

-- Client → server, answered (RemoteFunction).
local FUNCTIONS = {
	"GetSnapshot",
	"Roll",
	"Equip",
	"Unequip",
	"EquipBest",
	"UnequipAll",
	"Fuse",
	"Delete",
	"SetAutoDelete",
	"BuyUpgrade",
	"BuyZone",
	"TeleportZone",
	"Rebirth",
	"ClaimDaily",
	"ClaimPlaytime",
	"SpinWheel",
	"MarkUpdateSeen",
	"MarkIntroSeen",
	"AdvanceTutorial",
	"ClaimQuest",
	"ClaimIndexTab",
	"StopFight",
	"SetTitle",
	"ClaimPass",
}

-- Server → client (RemoteEvent).
local EVENTS = {
	"StatePatch",
	"Announce",
	"Notify", -- { Text: string, Color: Color3?, Results: { RollResult }? }
	"Drop", -- { RollResult }: a boss dropped a stud for you (Systems/Drops)
	"Leaderboards", -- { [board]: { { Rank, Name, UserId, Value } } } (Systems/Leaderboards)
	"ZoneBoss", -- { Phase: "Warning"|"Spawn"|"Board"|"Result"|"Defeated"|"Escaped", ... } (Systems/Combat)
}

local Net = {}

local folder: Folder? = nil

local function getFolder(): Folder
	if folder then return folder end
	if RunService:IsServer() then
		error("Net.setup() must run before any other Net call on the server")
	end
	local found = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	folder = found
	return found
end

local function getRemote(name: string): Instance
	return getFolder():WaitForChild(name)
end

--------------------------------------------------------------------------
-- Server
--------------------------------------------------------------------------

type Bucket = { tokens: number, last: number }
local buckets: { [Player]: { [string]: Bucket } } = {}

-- Payload guard (exploiters can send anything).
local MAX_ARGS = 4
local MAX_STRING = 64

local function safeArgs(...: any): boolean
	local count = select("#", ...)
	if count > MAX_ARGS then return false end
	for i = 1, count do
		local value = select(i, ...)
		local kind = typeof(value)
		if kind == "string" then
			if #value > MAX_STRING then return false end
		elseif kind == "number" then
			if value ~= value or value == math.huge or value == -math.huge then return false end
		elseif kind ~= "boolean" and kind ~= "nil" then
			return false
		end
	end
	return true
end

-- Strikes: rejected calls per player in a rolling window. Real clients are
-- throttled by the UI and almost never hit these numbers.
local STRIKE_WINDOW = 60
local STRIKE_WARN = 40
local STRIKE_KICK = 200
type Strikes = { count: number, since: number, warned: boolean }
local strikes: { [Player]: Strikes } = {}

local function strike(player: Player, name: string, reason: string)
	local now = os.clock()
	local existing = strikes[player]
	local record: Strikes = if existing and now - existing.since <= STRIKE_WINDOW then existing else { count = 0, since = now, warned = false }
	strikes[player] = record
	record.count += 1
	if record.count >= STRIKE_KICK then
		warn(`[Net] kicking {player.Name} ({player.UserId}): {record.count} rejected calls in {STRIKE_WINDOW}s (last: {name}, {reason})`)
		player:Kick("Too many requests. Please rejoin.")
	elseif record.count >= STRIKE_WARN and not record.warned then
		record.warned = true
		warn(`[Net] {player.Name} ({player.UserId}) is flooding remotes: {record.count} rejected (last: {name}, {reason})`)
	end
end

local function allow(player: Player, key: string, rate: number, burst: number): boolean
	local now = os.clock()
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local bucket = playerBuckets[key]
	if not bucket then
		bucket = { tokens = burst, last = now }
		playerBuckets[key] = bucket
	end
	bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.last) * rate)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function Net.setup()
	assert(RunService:IsServer(), "Net.setup is server-only")
	if folder then return end

	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then existing:Destroy() end

	local newFolder = Instance.new("Folder")
	newFolder.Name = FOLDER_NAME
	for _, name in FUNCTIONS do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = newFolder
	end
	for _, name in EVENTS do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = newFolder
	end
	newFolder.Parent = ReplicatedStorage
	folder = newFolder

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
		strikes[player] = nil
	end)
end

export type Limit = { Rate: number, Burst: number }

-- handler receives the player plus RAW, UNVALIDATED arguments.
function Net.handle(name: string, limit: Limit, handler: (Player, ...any) -> Response)
	local remote = getRemote(name) :: RemoteFunction
	remote.OnServerInvoke = function(player: Player, ...: any): Response
		if not allow(player, name, limit.Rate, limit.Burst) then
			strike(player, name, "rate limit")
			return { Ok = false, Error = "RateLimited" }
		end
		if not safeArgs(...) then
			strike(player, name, "bad payload")
			return { Ok = false, Error = "InvalidArgs" }
		end
		local ok, result = pcall(handler, player, ...)
		if not ok then
			warn(`[Net] {name} handler errored for {player.Name}: {result}`)
			return { Ok = false, Error = "ServerError" }
		end
		if typeof(result) ~= "table" then
			return { Ok = false, Error = "ServerError" }
		end
		return result
	end
end

function Net.fire(player: Player, name: string, ...: any)
	(getRemote(name) :: RemoteEvent):FireClient(player, ...)
end

function Net.fireAll(name: string, ...: any)
	(getRemote(name) :: RemoteEvent):FireAllClients(...)
end

--------------------------------------------------------------------------
-- Client
--------------------------------------------------------------------------

function Net.invoke(name: string, ...: any): Response
	local remote = getRemote(name) :: RemoteFunction
	local ok, result = pcall(remote.InvokeServer, remote, ...)
	if not ok or typeof(result) ~= "table" then
		return { Ok = false, Error = "NetworkError" }
	end
	return result
end

function Net.on(name: string, fn: (...any) -> ()): RBXScriptConnection
	return (getRemote(name) :: RemoteEvent).OnClientEvent:Connect(fn)
end

return Net
