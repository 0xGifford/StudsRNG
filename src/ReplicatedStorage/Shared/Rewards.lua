--[[

Rewards
ModuleScript
/ReplicatedStorage/Shared/Rewards

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Daily streak, session playtime rewards and the jackpot wheel.
--
-- Clacks amounts are scaled by Rewards.scale(data) so they stay worth
-- claiming as the player progresses (rebirths and the best owned zone).
-- Wheel Weight is relative: chance = Weight / sum of all weights. The wheel
-- shows these percentages to players (paid random items must show odds).

local Shared = script.Parent
local Config = require(Shared.Config)
local Zones = require(Shared.Zones)
local Types = require(Shared.Types)

type Reward = Types.Reward

export type PlaytimeReward = { At: number, Kind: string, Amount: number, Boost: string?, Minutes: number? }
export type WheelPrize = { Title: string, Weight: number, Kind: string, Amount: number, Boost: string?, Minutes: number? }

local daily: { Reward } = {
	{ Kind = "Clacks", Amount = 1_000 },
	{ Kind = "FreeRolls", Amount = 10 },
	{ Kind = "Boost", Amount = 1, Boost = "Luck", Minutes = 10 },
	{ Kind = "Spins", Amount = 1 },
	{ Kind = "Clacks", Amount = 10_000 },
	{ Kind = "Boost", Amount = 1, Boost = "Clacks", Minutes = 15 },
	{ Kind = "Luck", Amount = 1 },
}

-- At: minutes of playtime THIS session. "Leaving Resets Progress!"
local playtime: { PlaytimeReward } = {
	{ At = 1, Kind = "Clacks", Amount = 500 },
	{ At = 3, Kind = "FreeRolls", Amount = 5 },
	{ At = 5, Kind = "Boost", Amount = 1, Boost = "Luck", Minutes = 5 },
	{ At = 8, Kind = "Clacks", Amount = 2_500 },
	{ At = 12, Kind = "Spins", Amount = 1 },
	{ At = 16, Kind = "FreeRolls", Amount = 10 },
	{ At = 20, Kind = "Boost", Amount = 1, Boost = "Speed", Minutes = 5 },
	{ At = 25, Kind = "Clacks", Amount = 10_000 },
	{ At = 30, Kind = "Boost", Amount = 1, Boost = "UltraLuck", Minutes = 5 },
	{ At = 40, Kind = "Spins", Amount = 2 },
	{ At = 50, Kind = "Boost", Amount = 1, Boost = "Clacks", Minutes = 10 },
	{ At = 60, Kind = "Clacks", Amount = 50_000 },
}

-- Wheel segments 1-8 match the numbered folders under Menu.Canva.Wheel.Main.Wheel.
local wheel: { WheelPrize } = {
	{ Title = "Clacks", Kind = "Clacks", Amount = 5_000, Weight = 33 },
	{ Title = "5 Rolls", Kind = "FreeRolls", Amount = 5, Weight = 20 },
	{ Title = "Luck Boost", Kind = "Boost", Amount = 1, Boost = "Luck", Minutes = 5, Weight = 15 },
	{ Title = "x2 Clacks", Kind = "Boost", Amount = 1, Boost = "Clacks", Minutes = 5, Weight = 12 },
	{ Title = "Fast Rolls", Kind = "Boost", Amount = 1, Boost = "Speed", Minutes = 5, Weight = 10 },
	{ Title = "Ultra Luck", Kind = "Boost", Amount = 1, Boost = "UltraLuck", Minutes = 5, Weight = 7 },
	{ Title = "+1 Luck", Kind = "Luck", Amount = 1, Weight = 2 },
	{ Title = "JACKPOT", Kind = "MegaRoll", Amount = 1000, Weight = 1 },
}

local Rewards = {
	Daily = daily,
	Playtime = playtime,
	Wheel = wheel,
	DaySeconds = 24 * 60 * 60,
}

-- Clacks multiplier for reward amounts: rebirths and best zone.
function Rewards.scale(data: any): number
	local rebirths = if typeof(data.Rebirths) == "number" then data.Rebirths else 0
	local unlocked = if typeof(data.UnlockedWorlds) == "table" then data.UnlockedWorlds else {}
	return (1 + rebirths * Config.Rebirth.ClacksPerRebirth) * Zones.bestMultiplier(unlocked)
end

function Rewards.wheelTotalWeight(): number
	local total = 0
	for _, prize in wheel do
		total += prize.Weight
	end
	return total
end

-- UTC day number (days since the Unix epoch).
function Rewards.dayNumber(unixTime: number): number
	return math.floor(unixTime / Rewards.DaySeconds)
end

-- Daily state for `today`: whether the player can claim, and which day of
-- the 7-day cycle that claim (or the last one) is.
function Rewards.dailyState(state: any, today: number): (boolean, number)
	local streak = if typeof(state) == "table" and typeof(state.Streak) == "number" then state.Streak else 0
	local lastDay = if typeof(state) == "table" and typeof(state.LastDay) == "number" then state.LastDay else -1
	if lastDay >= today then
		return false, math.max(streak, 1)
	end
	if lastDay == today - 1 and streak > 0 then
		return true, streak % #daily + 1
	end
	return true, 1
end

return Rewards
