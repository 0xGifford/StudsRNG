--!strict
-- Single responsibility: points bookkeeping. Creates each player's
-- KeyCapperData/Points IntValue, loads/saves it via DataStore, and applies
-- the batched deltas the client reports over PointsRemote.
--
-- We trust the client's delta here — there is no server-side proof a key was
-- actually pressed, only a clamp against an obviously spoofed value (see
-- Config.POINTS_MAX_PER_BATCH). Good enough for a prototype scoreboard, not
-- for anything competitive.
--
-- RunContext = Server: lives under ReplicatedStorage.KeyCapper alongside
-- Client, same reason Client gives for living there instead of somewhere
-- under ServerScriptService.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

-- This script's own folder (Points): where its sibling PointsRemote lives.
-- KeyCapperFolder is one level up — the installed root — where Config and
-- Settings live.
local PointsFolder = script.Parent
local KeyCapperFolder = PointsFolder.Parent
local Config = require(KeyCapperFolder:WaitForChild("Config"))
local Settings = require(KeyCapperFolder:WaitForChild("Settings"))

local remote = PointsFolder:WaitForChild("PointsRemote") :: RemoteEvent

-- GetDataStore itself throws if API access to Studio/DataStores is disabled
-- (Game Settings > Security, or datastores simply unavailable in this
-- context) — a pcall here keeps the rest of the script (HUD, remote, points
-- in-session) working with in-memory-only points instead of erroring out
-- before a single connection is even set up.
local storeOk, store = pcall(function()
	return DataStoreService:GetDataStore(Config.POINTS_DATASTORE)
end)
if not storeOk then
	warn("[KeyCapper] DataStore unavailable, points will not persist across sessions:", store)
	store = nil
end

-- Which players actually got a Points value built, so PlayerRemoving and
-- BindToClose know who to save without re-checking Settings — a mid-session
-- toggle flip must not lose data for a player already being tracked.
local tracked: { [Player]: IntValue } = {}

local function loadPoints(player: Player): number
	if not store then return 0 end
	local ok, result = pcall(function()
		return store:GetAsync(tostring(player.UserId))
	end)
	if ok and typeof(result) == "number" then
		return result
	end
	return 0
end

local function savePoints(player: Player, points: IntValue)
	if not store then return end
	local ok, err = pcall(function()
		store:SetAsync(tostring(player.UserId), points.Value)
	end)
	if not ok then
		warn("[KeyCapper] failed to save points for", player.Name, ":", err)
	end
end

local function onPlayerAdded(player: Player)
	-- Checked once, at join: a toggle flipped mid-session shouldn't yank the
	-- value out from under players already tracked (see `tracked` above).
	if not Settings.GetValue("PointsEnabled") then return end

	local folder = Instance.new("Folder")
	folder.Name = Config.POINTS_DATA_FOLDER
	folder.Parent = player

	local points = Instance.new("IntValue")
	points.Name = Config.POINTS_VALUE_NAME
	points.Value = loadPoints(player)
	points.Parent = folder

	tracked[player] = points
end

local function onPlayerRemoving(player: Player)
	local points = tracked[player]
	if not points then return end
	tracked[player] = nil
	savePoints(player, points)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

remote.OnServerEvent:Connect(function(player: Player, delta: any)
	if not Settings.GetValue("PointsEnabled") then return end
	local points = tracked[player]
	if not points then return end
	if typeof(delta) ~= "number" then return end

	delta = math.floor(delta)
	if delta <= 0 then return end
	delta = math.min(delta, Config.POINTS_MAX_PER_BATCH)

	points.Value += delta
end)

-- Best-effort: Studio's own shutdown budget is short, this is a courtesy
-- save on top of the per-player one in PlayerRemoving, not a replacement.
game:BindToClose(function()
	for player, points in pairs(tracked) do
		savePoints(player, points)
	end
end)
