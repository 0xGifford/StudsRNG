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
-- Every server handler goes through a per-player token-bucket rate limit and
-- a pcall, and always answers with a Response table ({ Ok = bool, ... }).

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
}

-- Server → client (RemoteEvent).
local EVENTS = {
	"StatePatch",
	"Announce",
	"Notify", -- { Text: string, Color: Color3?, Results: { RollResult }? }
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
	end)
end

export type Limit = { Rate: number, Burst: number }

-- handler receives the player plus RAW, UNVALIDATED arguments.
function Net.handle(name: string, limit: Limit, handler: (Player, ...any) -> Response)
	local remote = getRemote(name) :: RemoteFunction
	remote.OnServerInvoke = function(player: Player, ...: any): Response
		if not allow(player, name, limit.Rate, limit.Burst) then
			return { Ok = false, Error = "RateLimited" }
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
