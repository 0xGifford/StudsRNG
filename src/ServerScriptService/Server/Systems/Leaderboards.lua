--[[

Leaderboards
ModuleScript
/ServerScriptService/Server/Systems/Leaderboards

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Global top lists (Config.Leaderboards): total Clacks earned, enemies
-- defeated and rarest roll. Every Refresh seconds each online player's
-- scores are saved to an OrderedDataStore and the top lists read back, then
-- sent to every client ("Leaderboards" event) for the Leaderboard-tagged
-- parts (Controllers/LeaderboardBoards).
--
-- Clacks and Rarest can outgrow an OrderedDataStore integer, so they're
-- stored as round(log10(x) × 1e6) and decoded on the way out. When
-- DataStores aren't reachable (Studio without API access) the boards show
-- the players in this server instead.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local Rolls = require(Systems.Rolls)

local Leaderboards = {}

local Settings = Config.Leaderboards
local LOG_SCALE = 1e6

type Entry = { Rank: number, Name: string, UserId: number, Value: number }
type BoardDef = { id: string, log: boolean, value: (data: any) -> number }

local BOARDS: { BoardDef } = {
	{ id = "Clacks", log = true, value = function(data) return data.LifetimeClacks or 0 end },
	{ id = "Enemies", log = false, value = function(data) return data.EnemiesDefeated or 0 end },
	{ id = "Rarest", log = true, value = function(data) return data.BestRoll or 0 end },
}

local stores: { [string]: OrderedDataStore } = {}
local written: { [Player]: { [string]: number } } = {} -- last value saved per board
local names: { [number]: string } = {}
local latest: { [string]: { Entry } } = {}

local function encode(board: BoardDef, value: number): number
	if not board.log then return math.floor(value) end
	return if value >= 1 then math.floor(math.log10(value) * LOG_SCALE + 0.5) else 0
end

local function decode(board: BoardDef, stored: number): number
	if not board.log then return stored end
	return 10 ^ (stored / LOG_SCALE)
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then return cached end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		names[userId] = online.DisplayName
		return online.DisplayName
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	local result = if ok and typeof(name) == "string" then name else `Player {userId}`
	names[userId] = result
	return result
end

local function savePlayer(player: Player)
	local data = PlayerData.get(player)
	if not data then return end
	local last = written[player] or {}
	written[player] = last
	for _, board in BOARDS do
		local store = stores[board.id]
		local value = encode(board, board.value(data))
		if store and value > 0 and last[board.id] ~= value then
			local ok = pcall(store.SetAsync, store, tostring(player.UserId), value)
			if ok then
				last[board.id] = value
			end
		end
	end
end

local function save()
	for _, player in Players:GetPlayers() do
		savePlayer(player)
	end
end

-- This server's players, ranked: the fallback without DataStores.
local function localBoard(board: BoardDef): { Entry }
	local rows = {}
	for _, player in Players:GetPlayers() do
		local data = PlayerData.get(player)
		if data then
			table.insert(rows, { player = player, value = board.value(data) })
		end
	end
	table.sort(rows, function(a, b)
		return a.value > b.value
	end)
	local entries: { Entry } = {}
	for rank, row in rows do
		if row.value > 0 then
			table.insert(entries, { Rank = rank, Name = row.player.DisplayName, UserId = row.player.UserId, Value = row.value })
		end
	end
	return entries
end

local function read(board: BoardDef): { Entry }
	local store = stores[board.id]
	if not store then return localBoard(board) end
	local ok, pages = pcall(store.GetSortedAsync, store, false, Settings.Size)
	if not ok or not pages then return localBoard(board) end
	local entries: { Entry } = {}
	for rank, item in (pages :: DataStorePages):GetCurrentPage() do
		local userId = tonumber(item.key)
		if userId then
			table.insert(entries, { Rank = rank, Name = nameOf(userId), UserId = userId, Value = decode(board, item.value) })
		end
	end
	return entries
end

local function refresh()
	save()
	for _, board in BOARDS do
		latest[board.id] = read(board)
	end
	Net.fireAll("Leaderboards", latest)
end

-- The rarest roll so far (Rolls.Rolled): odds of stud × variant.
local function onRolled(player: Player, results: { any })
	local data = PlayerData.get(player)
	if not data then return end
	local best = data.BestRoll or 0
	for _, result in results do
		if result.OneIn > best then
			best = result.OneIn
		end
	end
	if best ~= data.BestRoll then
		data.BestRoll = best
		StateSync.push(player, "BestRoll", best)
	end
end

function Leaderboards.init()
	for _, board in BOARDS do
		local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, Settings.Stores[board.id])
		if ok and store then
			stores[board.id] = store
		end
	end
	Rolls.Rolled:Connect(onRolled)
	-- Joiners get the current boards straight away.
	PlayerData.Loaded:Connect(function(player)
		if next(latest) then
			Net.fire(player, "Leaderboards", latest)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		savePlayer(player) -- scores since the last refresh
		written[player] = nil
	end)
end

function Leaderboards.start()
	task.wait(10) -- let the first players load
	while true do
		local ok, err = pcall(refresh)
		if not ok then
			warn(`[Leaderboards] {err}`)
		end
		task.wait(Settings.Refresh)
	end
end

return Leaderboards
