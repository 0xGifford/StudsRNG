--[[

Leaderboards
ModuleScript
/ServerScriptService/Server/Systems/Leaderboards

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Global top lists (Config.Leaderboards): total Clacks earned, enemies
-- defeated and rarest roll, plus two weekly boards (Clacks earned and
-- enemies defeated this week) that start empty every Monday 00:00 UTC.
-- Every Refresh seconds each online player's scores are saved to an
-- OrderedDataStore and the top lists read back, then sent to every client
-- ("Leaderboards" event) for the Leaderboard-tagged parts
-- (Controllers/LeaderboardBoards).
--
-- Weekly boards use a new store each week (Stores name .. "_W" .. week).
-- When a player who played last week joins, last week's boards are read
-- (once per server) and their best rank pays Config.Leaderboards
-- WeeklyRewards.
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
local ZoneRotation = require(Shared.ZoneRotation)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local Rolls = require(Systems.Rolls)
local Economy = require(Systems.Economy)
local Combat = require(Systems.Combat)
local RewardService = require(Systems.RewardService)

local Leaderboards = {}

local Settings = Config.Leaderboards
local LOG_SCALE = 1e6

type Entry = { Rank: number, Name: string, UserId: number, Value: number }
type BoardDef = { id: string, log: boolean, weekly: boolean?, value: (data: any) -> number }

local function thisWeek(): number
	return ZoneRotation.week(os.time())
end

-- This week's scores (zero once the week has rolled over).
local function weekly(data: any): { Week: number, Clacks: number, Enemies: number }
	local stats = data.WeeklyStats
	if typeof(stats) ~= "table" or stats.Week ~= thisWeek() then
		return { Week = thisWeek(), Clacks = 0, Enemies = 0 }
	end
	return stats
end

local BOARDS: { BoardDef } = {
	{ id = "Clacks", log = true, value = function(data) return data.LifetimeClacks or 0 end },
	{ id = "Enemies", log = false, value = function(data) return data.EnemiesDefeated or 0 end },
	{ id = "Rarest", log = true, value = function(data) return data.BestRoll or 0 end },
	{ id = "WeeklyClacks", log = true, weekly = true, value = function(data) return weekly(data).Clacks end },
	{ id = "WeeklyEnemies", log = false, weekly = true, value = function(data) return weekly(data).Enemies end },
}

local stores: { [string]: OrderedDataStore } = {}
local weeklyStores: { [string]: OrderedDataStore } = {} -- [id .. "_W" .. week]
local storesReachable = false
local written: { [Player]: { [string]: number } } = {} -- last value saved per board (weekly: per week)
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

-- A board's store: weekly boards get this week's (or `week`'s).
local function storeFor(board: BoardDef, week: number?): OrderedDataStore?
	if not board.weekly then return stores[board.id] end
	if not storesReachable then return nil end
	local name = `{Settings.Stores[board.id]}_W{week or thisWeek()}`
	local cached = weeklyStores[name]
	if cached then return cached end
	local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, name)
	if ok and store then
		weeklyStores[name] = store
		return store
	end
	return nil
end

local function savePlayer(player: Player)
	local data = PlayerData.get(player)
	if not data then return end
	local last = written[player] or {}
	written[player] = last
	for _, board in BOARDS do
		local store = storeFor(board)
		local value = encode(board, board.value(data))
		local slot = if board.weekly then `{board.id}_W{thisWeek()}` else board.id
		if store and value > 0 and last[slot] ~= value then
			local ok = pcall(store.SetAsync, store, tostring(player.UserId), value)
			if ok then
				last[slot] = value
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
	local store = storeFor(board)
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

--------------------------------------------------------------------------
-- Weekly scores and last week's rewards
--------------------------------------------------------------------------

local function addWeekly(player: Player, field: string, amount: number)
	local data = PlayerData.get(player)
	if not data or amount <= 0 or amount ~= amount then return end
	local stats = weekly(data)
	stats[field] += amount
	data.WeeklyStats = stats
end

-- Last week's ranks, read once per server: [week] = { [userId] = best rank }.
local lastWeekRanks: { [number]: { [number]: number } } = {}
local reading: { [number]: boolean } = {}

local function ranksFor(week: number): { [number]: number }?
	local cached = lastWeekRanks[week]
	if cached then return cached end
	while reading[week] do
		task.wait(0.5)
	end
	if lastWeekRanks[week] then return lastWeekRanks[week] end
	reading[week] = true
	local ranks: { [number]: number } = {}
	local ok = true
	for _, board in BOARDS do
		if board.weekly then
			local store = storeFor(board, week)
			local success, pages = false, nil
			if store then
				success, pages = pcall(store.GetSortedAsync, store, false, Settings.Size)
			end
			if success and pages then
				for rank, item in (pages :: DataStorePages):GetCurrentPage() do
					local userId = tonumber(item.key)
					if userId then
						ranks[userId] = math.min(ranks[userId] or math.huge, rank)
					end
				end
			else
				ok = false
			end
		end
	end
	reading[week] = nil
	if not ok then return nil end
	lastWeekRanks[week] = ranks
	return ranks
end

-- scoredWeek: the week of the scores saved at join (read before this
-- session's own presses replace them with this week's).
local function payLastWeek(player: Player, scoredWeek: number?)
	local data = PlayerData.get(player)
	if not data or not storesReachable then return end
	local last = thisWeek() - 1
	if (data.WeeklyPaid or 0) >= last then return end
	-- Only players who scored last week can have placed (or whose check
	-- failed last time: WeeklyPending).
	if scoredWeek ~= last and data.WeeklyPending ~= last then
		data.WeeklyPaid = last
		return
	end
	local ranks = ranksFor(last)
	if not ranks or player.Parent ~= Players then
		data.WeeklyPending = last -- the boards couldn't be read: try again next join
		return
	end
	data.WeeklyPaid = last
	data.WeeklyPending = nil
	local rank = ranks[player.UserId]
	if not rank then return end
	for _, tier in Settings.WeeklyRewards do
		if rank <= tier.Rank then
			local given = RewardService.grant(player, tier.Reward)
			Net.fire(player, "Notify", {
				Kind = "WeeklyRank",
				Rank = rank,
				Title = tier.Title,
				Reward = given,
				Text = `Last week you placed #{rank} on the weekly leaderboard!`,
				Color = Color3.fromRGB(255, 205, 60),
			})
			break
		end
	end
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
		if not board.weekly then
			local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, Settings.Stores[board.id])
			if ok and store then
				stores[board.id] = store
				storesReachable = true
			end
		end
	end
	Rolls.Rolled:Connect(onRolled)
	Economy.Earned:Connect(function(player, _presses, gained)
		addWeekly(player, "Clacks", gained)
	end)
	Combat.Defeated:Connect(function(player)
		addWeekly(player, "Enemies", 1)
	end)
	-- Joiners get the current boards straight away, and last week's prize.
	PlayerData.Loaded:Connect(function(player, data)
		if next(latest) then
			Net.fire(player, "Leaderboards", latest)
		end
		local stats = data.WeeklyStats
		local scoredWeek = if typeof(stats) == "table" then stats.Week else nil
		task.delay(12, function()
			if player.Parent == Players then
				local ok, err = pcall(payLastWeek, player, scoredWeek)
				if not ok then
					warn(`[Leaderboards] weekly reward: {err}`)
				end
			end
		end)
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
