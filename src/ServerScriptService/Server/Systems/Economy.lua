--[[ 

Economy
ModuleScript
/ServerScriptService/Server/Systems/Economy

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Owns Clacks, the roll meter and banked free rolls. Earns from
-- PressTracker (server-detected presses only) and exposes spend functions
-- for Rolls and, later, shops/upgrades.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local Inventory = require(Systems.Inventory)
local PressTracker = require(Systems.PressTracker)

local Economy = {}

local leaderValues: { [Player]: NumberValue } = {}

local function updateLeaderstat(player: Player, clacks: number)
	local value = leaderValues[player]
	if value then
		value.Value = math.floor(clacks)
	end
end

local function pushClacks(player: Player, data: any)
	StateSync.push(player, "Clacks", data.Clacks)
	StateSync.push(player, "LifetimeClacks", data.LifetimeClacks)
	updateLeaderstat(player, data.Clacks)
end

local function pushRolls(player: Player, data: any)
	StateSync.push(player, "FreeRolls", data.FreeRolls)
	StateSync.push(player, "RollMeter", data.RollMeter)
end

--------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------

function Economy.addClacks(player: Player, amount: number)
	local data = PlayerData.get(player)
	if not data or amount ~= amount or amount <= 0 or amount == math.huge then return end
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

function Economy.addFreeRolls(player: Player, amount: number)
	local data = PlayerData.get(player)
	if not data or amount <= 0 then return end
	data.FreeRolls = math.min(data.FreeRolls + math.floor(amount), Config.Economy.MaxBankedFreeRolls)
	pushRolls(player, data)
end

function Economy.spendFreeRolls(player: Player, amount: number): boolean
	local data = PlayerData.get(player)
	if not data or data.FreeRolls < amount then return false end
	data.FreeRolls -= amount
	pushRolls(player, data)
	return true
end

--------------------------------------------------------------------------
-- Earning
--------------------------------------------------------------------------

local function onPressed(player: Player, count: number, valueSum: number)
	local data = PlayerData.get(player)
	if not data then return end

	local stats = Inventory.getStats(player)
	local gain = valueSum * stats.ClackMultiplier
	data.Clacks += gain
	data.LifetimeClacks += gain
	data.TotalPresses += count
	pushClacks(player, data)

	-- The meter keeps filling while the bank is full but doesn't pay out,
	-- so the next free roll is ready the moment one is spent.
	local perRoll = Config.Economy.PressesPerFreeRoll
	data.RollMeter += count
	while data.RollMeter >= perRoll and data.FreeRolls < Config.Economy.MaxBankedFreeRolls do
		data.RollMeter -= perRoll
		data.FreeRolls += 1
	end
	data.RollMeter = math.min(data.RollMeter, perRoll)
	pushRolls(player, data)
end

function Economy.init()
	PressTracker.Pressed:Connect(onPressed)

	PlayerData.Loaded:Connect(function(player, data)
		local leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		local clacks = Instance.new("NumberValue")
		clacks.Name = "Clacks"
		clacks.Value = math.floor(data.Clacks)
		clacks.Parent = leaderstats
		leaderstats.Parent = player
		leaderValues[player] = clacks
	end)

	Players.PlayerRemoving:Connect(function(player)
		leaderValues[player] = nil
	end)
end

-- When a free roll is spent while the meter sat full, pay it out now.
function Economy.settleMeter(player: Player)
	local data = PlayerData.get(player)
	if not data then return end
	local perRoll = Config.Economy.PressesPerFreeRoll
	if data.RollMeter >= perRoll and data.FreeRolls < Config.Economy.MaxBankedFreeRolls then
		data.RollMeter -= perRoll
		data.FreeRolls += 1
		pushRolls(player, data)
	end
end

return Economy
