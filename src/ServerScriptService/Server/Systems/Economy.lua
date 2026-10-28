--[[

Economy
ModuleScript
/ServerScriptService/Server/Systems/Economy

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Owns Clacks, the roll meter and banked free rolls. Earns from
-- PressTracker (server-detected presses only, in owned zones) and exposes
-- grant/spend functions for rolls, shops, upgrades, zones and rewards.
--
-- Press combo: presses in quick succession build a Clacks bonus
-- (Config.Combo), pushed to the client as "Combo" = { Count, Bonus }.
-- Offline earnings: Clacks for time away, granted on join (Config.Offline).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local RewardDefs = require(Shared.Rewards)
local Signal = require(Shared.Util.Signal)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local Modifiers = require(Systems.Modifiers)
local PressTracker = require(Systems.PressTracker)

local Economy = {}

-- (player, presses, clacksGained) after every counted press sample
Economy.Earned = Signal.new() :: Signal.Signal<Player, number, number>

type Combo = { count: number, last: number }
local combos: { [Player]: Combo } = {}

local rng = Random.new()
local leaderValues: { [Player]: { Clacks: NumberValue, Rebirths: IntValue } } = {}

local function isAmount(amount: number): boolean
	return amount == amount and amount > 0 and amount ~= math.huge
end

local function pushClacks(player: Player, data: any)
	StateSync.push(player, "Clacks", data.Clacks)
	StateSync.push(player, "LifetimeClacks", data.LifetimeClacks)
	local values = leaderValues[player]
	if values then
		values.Clacks.Value = math.floor(data.Clacks)
	end
end

local function pushRolls(player: Player, data: any)
	StateSync.push(player, "FreeRolls", data.FreeRolls)
	StateSync.push(player, "RollMeter", data.RollMeter)
end

--------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------

-- Grants Clacks (presses, packs, rewards). No cap.
function Economy.addClacks(player: Player, amount: number)
	local data = PlayerData.get(player)
	if not data or not isAmount(amount) then return end
	data.Clacks += amount
	data.LifetimeClacks += amount
	pushClacks(player, data)
end

function Economy.spendClacks(player: Player, amount: number): boolean
	local data = PlayerData.get(player)
	if not data or amount ~= amount or amount < 0 then return false end
	if data.Clacks < amount then return false end
	data.Clacks -= amount
	pushClacks(player, data)
	return true
end

-- Sets Clacks outright (rebirth reset, dev tools).
function Economy.setClacks(player: Player, amount: number)
	local data = PlayerData.get(player)
	if not data or amount ~= amount or amount < 0 then return end
	data.Clacks = amount
	pushClacks(player, data)
end

-- Banks free rolls. Meter refunds respect the bank size; rewards and
-- purchases pass uncapped = true so nothing is lost to a full bank.
function Economy.addFreeRolls(player: Player, amount: number, uncapped: boolean?)
	local data = PlayerData.get(player)
	if not data or not isAmount(amount) then return end
	local total = data.FreeRolls + math.floor(amount)
	if not uncapped then
		total = math.min(total, math.max(data.FreeRolls, Modifiers.get(player).MaxBankedFreeRolls))
	end
	data.FreeRolls = total
	pushRolls(player, data)
end

function Economy.spendFreeRolls(player: Player, amount: number): boolean
	local data = PlayerData.get(player)
	if not data or data.FreeRolls < amount then return false end
	data.FreeRolls -= amount
	pushRolls(player, data)
	return true
end

function Economy.refreshLeaderstats(player: Player)
	local data = PlayerData.get(player)
	local values = leaderValues[player]
	if data and values then
		values.Clacks.Value = math.floor(data.Clacks)
		values.Rebirths.Value = data.Rebirths
	end
end

-- Keys only pay out in zones the player owns (keys with no zone always pay).
function Economy.ownsZone(player: Player, zoneId: string?): boolean
	if zoneId == nil then return true end
	local data = PlayerData.get(player)
	return data ~= nil and data.UnlockedWorlds[zoneId] == true
end

--------------------------------------------------------------------------
-- Earning
--------------------------------------------------------------------------

local function onPressed(player: Player, count: number, valueSum: number)
	local data = PlayerData.get(player)
	if not data then return end

	local stats = Modifiers.get(player)

	-- Lucky Keys: each press independently may pay double.
	local bonus = 0
	if stats.CritChance > 0 then
		local perPress = valueSum / count
		for _ = 1, count do
			if rng:NextNumber() < stats.CritChance then
				bonus += perPress
			end
		end
	end

	-- Combo: keep the streak alive by pressing within the window.
	local now = os.clock()
	local combo = combos[player]
	if not combo or now - combo.last > Config.Combo.Window then
		combo = { count = 0, last = now }
		combos[player] = combo
	end
	combo.count += count
	combo.last = now
	local comboBonus = math.min(combo.count * Config.Combo.Step, Config.Combo.Max)
	StateSync.push(player, "Combo", { Count = combo.count, Bonus = comboBonus })

	local gain = (valueSum + bonus) * stats.ClackMultiplier * (1 + comboBonus)
	data.Clacks += gain
	data.LifetimeClacks += gain
	data.TotalPresses += count
	pushClacks(player, data)

	-- The meter keeps filling while the bank is full but doesn't pay out,
	-- so the next free roll is ready the moment one is spent.
	local perRoll = stats.PressesPerFreeRoll
	data.RollMeter += count
	while data.RollMeter >= perRoll and data.FreeRolls < stats.MaxBankedFreeRolls do
		data.RollMeter -= perRoll
		data.FreeRolls += 1
	end
	data.RollMeter = math.min(data.RollMeter, perRoll)
	pushRolls(player, data)
	Economy.Earned:Fire(player, count, gain)
end

local function grantOffline(player: Player, data: any, lastSeen: number)
	local now = os.time()
	local away = now - lastSeen
	data.LastOnline = now
	if away < Config.Offline.MinAway then return end
	local seconds = math.min(away, Config.Offline.MaxSeconds)
	local amount = math.floor(seconds * Config.Offline.ClacksPerSecond * RewardDefs.scale(data))
	if amount <= 0 then return end
	Economy.addClacks(player, amount)
	Net.fire(player, "Notify", {
		Kind = "Welcome",
		Text = "Welcome back! Clacks earned while you were away",
		Amount = amount,
		Seconds = seconds,
		Color = Color3.fromRGB(255, 230, 90),
	})
end

-- When a free roll is spent while the meter sat full, pay it out now.
function Economy.settleMeter(player: Player)
	local data = PlayerData.get(player)
	if not data then return end
	local stats = Modifiers.get(player)
	local perRoll = stats.PressesPerFreeRoll
	if data.RollMeter >= perRoll and data.FreeRolls < stats.MaxBankedFreeRolls then
		data.RollMeter -= perRoll
		data.FreeRolls += 1
		pushRolls(player, data)
	end
end

function Economy.init()
	PressTracker.Pressed:Connect(onPressed)
	PressTracker.setFilter(Economy.ownsZone)

	PlayerData.Loaded:Connect(function(player, data)
		local leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		local clacks = Instance.new("NumberValue")
		clacks.Name = "Clacks"
		clacks.Value = math.floor(data.Clacks)
		clacks.Parent = leaderstats
		local rebirths = Instance.new("IntValue")
		rebirths.Name = "Rebirths"
		rebirths.Value = data.Rebirths
		rebirths.Parent = leaderstats
		leaderstats.Parent = player
		leaderValues[player] = { Clacks = clacks, Rebirths = rebirths }

		-- Wait a moment so the client is listening for the welcome popup.
		local lastSeen = data.LastOnline or 0
		data.LastOnline = os.time()
		if lastSeen > 0 then
			task.delay(6, function()
				if player.Parent == Players and PlayerData.get(player) == data then
					grantOffline(player, data, lastSeen)
				end
			end)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local data = PlayerData.get(player)
		if data then
			data.LastOnline = os.time()
		end
		leaderValues[player] = nil
		combos[player] = nil
	end)
end

-- Keeps LastOnline fresh: PlayerRemoving can run after the profile is gone.
function Economy.start()
	while true do
		task.wait(60)
		local now = os.time()
		for _, player in Players:GetPlayers() do
			local data = PlayerData.get(player)
			if data then
				data.LastOnline = now
			end
		end
	end
end

return Economy

