--[[

Rewards
ModuleScript
/ReplicatedStorage/Shared/Rewards

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Daily streak, session playtime rewards and the jackpot wheel.
--
-- The daily streak is a 7-day calendar (Day 7: a jackpot bundle). Every
-- full week kept in a row adds WeekBonus to the Clacks and roll rewards, up
-- to MaxWeeks weeks (Rewards.dailyReward); missing a day resets both.
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
	{ Kind = "Bundle", Amount = 1, Items = {
		{ Kind = "MegaRoll", Amount = 250 },
		{ Kind = "Luck", Amount = 1 },
	} },
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

-- Wheel segments 1-8 match the numbered folders under the Wheel menu (Wheel.Canva.Wheel.Main.Wheel).
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
	WeekBonus = 0.5, -- +50% Clacks and rolls per full week kept
	MaxWeeks = 4,
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

-- Full weeks kept after claiming `day` today: a Day 1 that continues the
-- streak starts a new week; a broken streak starts over.
function Rewards.weeksAfterClaim(state: any, today: number, day: number): number
	local weeks = if typeof(state) == "table" and typeof(state.Weeks) == "number" then state.Weeks else 0
	local lastDay = if typeof(state) == "table" and typeof(state.LastDay) == "number" then state.LastDay else -1
	local continuing = lastDay == today - 1
	if not continuing then return 0 end
	return if day == 1 then weeks + 1 else weeks
end

function Rewards.weekMultiplier(weeks: number): number
	return 1 + math.min(weeks, Rewards.MaxWeeks) * Rewards.WeekBonus
end

-- Day `day`'s reward with the week streak applied (Clacks and FreeRolls).
function Rewards.dailyReward(day: number, weeks: number): Reward
	local multiplier = Rewards.weekMultiplier(weeks)
	local function boosted(reward: Reward): Reward
		local copy = table.clone(reward)
		if reward.Kind == "Clacks" or reward.Kind == "FreeRolls" then
			copy.Amount = math.floor(reward.Amount * multiplier)
		elseif reward.Kind == "Bundle" and reward.Items then
			local items = {}
			for i, item in reward.Items do
				items[i] = boosted(item)
			end
			copy.Items = items
		end
		return copy
	end
	return boosted(daily[day])
end

return Rewards
