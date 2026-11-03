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
-- to MaxWeeks weeks (Rewards.dailyReward).
--
-- Forgiving streaks: one missed day every GraceEvery days is forgiven (the
-- Grace Day; the streak carries on). Missing more resets the calendar, but
-- a streak of Recovery.MinDays+ days earns a "welcome back": the next
-- Recovery.Claims daily rewards are Recovery.Multiplier times bigger.
-- Daily.Days counts consecutive days (for the 7 / 14 / 30 / 60 / 100 day
-- achievements); Daily.Best is the longest ever.
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
	GraceEvery = 7, -- one missed day forgiven per this many days
	Recovery = { MinDays = 3, Claims = 2, Multiplier = 2 },
}

-- Clacks multiplier for reward amounts: rebirths and best zone.
function Rewards.scale(data: any): number
	local rebirths = if typeof(data.Rebirths) == "number" then data.Rebirths else 0
	local unlocked = if typeof(data.UnlockedWorlds) == "table" then data.UnlockedWorlds else {}
	return Config.rebirthMultiplier(rebirths) * Zones.bestMultiplier(unlocked)
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

local function number(state: any, field: string, default: number): number
	local value = if typeof(state) == "table" then state[field] else nil
	return if typeof(value) == "number" then value else default
end

-- Is the Grace Day ready (none used in the last GraceEvery days)?
function Rewards.graceReady(state: any, today: number): boolean
	return number(state, "GraceDay", -1000) <= today - Rewards.GraceEvery
end

-- Does claiming today keep the streak going? (claimed yesterday, or missed
-- exactly one day with the Grace Day ready). Second value: uses the grace.
function Rewards.continues(state: any, today: number): (boolean, boolean)
	if number(state, "Streak", 0) <= 0 then return false, false end
	local lastDay = number(state, "LastDay", -1)
	if lastDay == today - 1 then return true, false end
	if lastDay == today - 2 and Rewards.graceReady(state, today) then return true, true end
	return false, false
end

-- Consecutive days so far (saves from before Days existed: weeks * 7 + day).
function Rewards.days(state: any): number
	return number(state, "Days", number(state, "Weeks", 0) * #daily + number(state, "Streak", 0))
end

-- Daily state for `today`: whether the player can claim, and which day of
-- the 7-day cycle that claim (or the last one) is.
function Rewards.dailyState(state: any, today: number): (boolean, number)
	local streak = number(state, "Streak", 0)
	if number(state, "LastDay", -1) >= today then
		return false, math.max(streak, 1)
	end
	if Rewards.continues(state, today) then
		return true, streak % #daily + 1
	end
	return true, 1
end

-- Full weeks kept after claiming `day` today: a Day 1 that continues the
-- streak starts a new week; a broken streak starts over.
function Rewards.weeksAfterClaim(state: any, today: number, day: number): number
	if not Rewards.continues(state, today) then return 0 end
	local weeks = number(state, "Weeks", 0)
	return if day == 1 then weeks + 1 else weeks
end

export type ClaimInfo = { Day: number, Weeks: number, Days: number, Graced: boolean, Recovery: boolean }

-- The Daily state after claiming today, and what the claim was (call only
-- when dailyState says it can be claimed).
function Rewards.afterClaim(state: any, today: number): (any, ClaimInfo)
	local _, day = Rewards.dailyState(state, today)
	local continuing, graced = Rewards.continues(state, today)
	local weeks = Rewards.weeksAfterClaim(state, today, day)
	local days = if continuing then Rewards.days(state) + 1 else 1
	local recovery = number(state, "Recovery", 0)
	if not continuing then
		-- A broken streak worth mentioning: welcome back with bigger rewards.
		recovery = if Rewards.days(state) >= Rewards.Recovery.MinDays then Rewards.Recovery.Claims else 0
	end
	local boosted = recovery > 0
	local new = {
		Streak = day,
		LastDay = today,
		Weeks = weeks,
		Days = days,
		Best = math.max(number(state, "Best", 0), days),
		GraceDay = if graced then today else number(state, "GraceDay", -1000),
		Recovery = if boosted then recovery - 1 else 0,
	}
	return new, { Day = day, Weeks = weeks, Days = days, Graced = graced, Recovery = boosted }
end

function Rewards.weekMultiplier(weeks: number): number
	return 1 + math.min(weeks, Rewards.MaxWeeks) * Rewards.WeekBonus
end

-- Day `day`'s reward with the week streak applied (Clacks and FreeRolls);
-- recovery: the welcome-back bonus (everything bigger).
function Rewards.dailyReward(day: number, weeks: number, recovery: boolean?): Reward
	local extra = if recovery then Rewards.Recovery.Multiplier else 1
	local multiplier = Rewards.weekMultiplier(weeks) * extra
	local function boosted(reward: Reward): Reward
		local copy = table.clone(reward)
		if reward.Kind == "Clacks" or reward.Kind == "FreeRolls" then
			copy.Amount = math.floor(reward.Amount * multiplier)
		elseif reward.Kind == "Spins" then
			copy.Amount = reward.Amount * extra
		elseif reward.Kind == "Boost" and reward.Minutes then
			copy.Minutes = reward.Minutes * extra
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
