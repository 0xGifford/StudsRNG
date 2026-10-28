--[[ 

PlayerData
ModuleScript
/ServerScriptService/Server/Systems/PlayerData

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The only module that touches persistence. Wraps ProfileStore: session
-- locking, retries and BindToClose are handled by the library.
-- Gameplay systems read/write PlayerData.get(player) (the in-memory table)
-- and never call DataStores themselves.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)

-- Point this at your ProfileStore module.
local ProfileStore = require(ServerScriptService:WaitForChild("Packages"):WaitForChild("ProfileStore")) :: any

type PlayerData = Types.PlayerData

local CURRENT_VERSION = 1

local TEMPLATE: PlayerData = {
	Version = CURRENT_VERSION,
	Clacks = 0,
	LifetimeClacks = 0,
	TotalPresses = 0,
	FreeRolls = 0,
	RollMeter = 0,
	TotalRolls = 0,
	Studs = {},
	Equipped = {},
	Index = {},
	AutoDelete = {},
	UnlockedWorlds = { Office = true },
	Rebirths = 0,
	Upgrades = {},
	LuckyRolls = 0,
	Boosts = {},
	Spins = 0,
	Daily = { Streak = 0, LastDay = -1 },
	SeenUpdate = "",
	PurchaseIds = {},
}

-- [fromVersion] = function(data) ... end. Runs on load until Version is current.
local MIGRATIONS: { [number]: (any) -> () } = {}

local PlayerData = {}

-- Fires once a player's profile is loaded and ready.
PlayerData.Loaded = Signal.new() :: Signal.Signal<Player, PlayerData>

local profiles: { [Player]: any } = {}
local store: any = nil

local function migrate(data: any)
	if typeof(data.Version) ~= "number" then
		data.Version = CURRENT_VERSION
	end
	while data.Version < CURRENT_VERSION do
		local step = MIGRATIONS[data.Version]
		if step then
			step(data)
		end
		data.Version += 1
	end
end

-- Defensive cleanup: drops any saved key that no longer maps to a real stud
-- (e.g. a stud removed from Studs.luau) so nothing downstream sees it.
local function sanitize(data: any)
	local RollLogic = require(Shared.Util.RollLogic)
	local Upgrades = require(Shared.Upgrades)
	local Zones = require(Shared.Zones)

	for id, level in data.Upgrades do
		local def = Upgrades.ById[id]
		if not def or typeof(level) ~= "number" or level <= 0 then
			data.Upgrades[id] = nil
		else
			data.Upgrades[id] = math.min(math.floor(level), def.MaxLevel)
		end
	end

	for id in data.UnlockedWorlds do
		if not Zones.ById[id] then
			data.UnlockedWorlds[id] = nil
		end
	end
	data.UnlockedWorlds[Zones.Default] = true

	for id, seconds in data.Boosts do
		if not Config.Boosts[id] or typeof(seconds) ~= "number" or seconds <= 0 then
			data.Boosts[id] = nil
		end
	end

	for key, count in data.Studs do
		if not RollLogic.decodeKey(key) or typeof(count) ~= "number" or count <= 0 then
			data.Studs[key] = nil
		else
			data.Studs[key] = math.floor(count)
		end
	end

	local equipped = {}
	local used: { [string]: number } = {}
	for _, key in data.Equipped do
		local owned = data.Studs[key] or 0
		if (used[key] or 0) < owned and #equipped < Config.Inventory.MaxSlots then
			used[key] = (used[key] or 0) + 1
			table.insert(equipped, key)
		end
	end
	data.Equipped = equipped
end

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		-- Load failed or was cancelled. Never let them play on a blank
		-- profile: its next save would overwrite their real data.
		if player.Parent == Players then
			player:Kick("Your data couldn't load. Please rejoin in a moment.")
		end
		return
	end

	profile:AddUserId(player.UserId) -- GDPR
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent == Players then
			player:Kick("Your session was opened elsewhere. Please rejoin.")
		end
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	migrate(profile.Data)
	sanitize(profile.Data)

	profiles[player] = profile
	PlayerData.Loaded:Fire(player, profile.Data)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		profile:EndSession()
	end
end

function PlayerData.init()
	local newStore = ProfileStore.New(Config.Data.StoreName, TEMPLATE)
	if Config.Data.UseMockInStudio and RunService:IsStudio() then
		newStore = newStore.Mock
	end
	store = newStore

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

function PlayerData.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

-- The ProfileStore profile (receipt handling needs Save / LastSavedData).
function PlayerData.getProfile(player: Player): any
	return profiles[player]
end

-- The live, in-memory data table, or nil if not loaded (or already released).
function PlayerData.get(player: Player): PlayerData?
	local profile = profiles[player]
	return profile and profile.Data or nil
end

-- Yields until loaded, the player leaves, or timeout. Returns nil on failure.
function PlayerData.waitFor(player: Player, timeout: number?): PlayerData?
	local deadline = os.clock() + (timeout or 20)
	while player.Parent == Players and os.clock() < deadline do
		local data = PlayerData.get(player)
		if data then
			return data
		end
		task.wait(0.1)
	end
	return PlayerData.get(player)
end

-- Studio/dev only: reset a player's data to the template in place.
function PlayerData.reset(player: Player)
	local profile = profiles[player]
	if not profile then return end
	local data: any = profile.Data
	for key in data do
		data[key] = nil
	end
	for key, value in TEMPLATE :: any do
		data[key] = if typeof(value) == "table" then table.clone(value :: any) else value
	end
end

return PlayerData
