--[[

ZoneRotation
ModuleScript
/ReplicatedStorage/Shared/ZoneRotation

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Which zones are boosted right now (Config.ZoneRotation). Worked out from
-- the UTC day / week alone, so every server (and every client) agrees with
-- no messages:
--   Favoured  two a day: one of zones 1..EarlyMax and one deeper zone.
--             More Clacks from keys, more luck while you play there, and
--             the Limited Prismatic variant rolls there.
--   Vintage   three a week (never a Favoured one that day).
-- ZoneRotation.bonus(zoneId, now) -> { Kind, Luck, Clacks, Prismatic } or nil.

local Config = require(script.Parent.Config)
local Zones = require(script.Parent.Zones)

local ZoneRotation = {}

local DAY = 24 * 60 * 60
local WEEK = 7 * DAY

export type Bonus = { Kind: string, Luck: number, Clacks: number, Prismatic: boolean }

-- A stable pseudo-random pick for a period number.
local function pick(seed: number, low: number, high: number): number
	local rng = Random.new(seed)
	return rng:NextInteger(low, high)
end

function ZoneRotation.day(now: number): number
	return math.floor(now / DAY)
end

function ZoneRotation.week(now: number): number
	-- Weeks start on Monday (the Unix epoch was a Thursday).
	return math.floor((now + 3 * DAY) / WEEK)
end

-- Picks are cached per day / week: bonus() runs on every press sample.
local favouredCache: { day: number, ids: { string } }? = nil
local vintageCache: { day: number, ids: { string } }? = nil

-- Today's Favoured zone ids (early, deep).
function ZoneRotation.favoured(now: number): { string }
	local day = ZoneRotation.day(now)
	local cached = favouredCache
	if cached and cached.day == day then
		return cached.ids
	end
	local count = #Zones.List
	local earlyMax = math.min(Config.ZoneRotation.EarlyMax, count)
	local early = Zones.List[pick(day * 7919 + 11, 1, earlyMax)]
	local ids = { early.Id }
	if count > earlyMax then
		table.insert(ids, Zones.List[pick(day * 6007 + 23, earlyMax + 1, count)].Id)
	end
	favouredCache = { day = day, ids = ids }
	return ids
end

-- This week's Vintage zone ids (skipping today's Favoured ones).
function ZoneRotation.vintage(now: number): { string }
	local day = ZoneRotation.day(now)
	local cached = vintageCache
	if cached and cached.day == day then
		return cached.ids
	end
	local week = ZoneRotation.week(now)
	local favoured = {}
	for _, id in ZoneRotation.favoured(now) do
		favoured[id] = true
	end
	local rng = Random.new(week * 104729 + 5)
	local ids: { string } = {}
	local tries = 0
	while #ids < Config.ZoneRotation.Vintage.Count and tries < 200 do
		tries += 1
		local def = Zones.List[rng:NextInteger(1, #Zones.List)]
		if not favoured[def.Id] and not table.find(ids, def.Id) then
			table.insert(ids, def.Id)
		end
	end
	vintageCache = { day = day, ids = ids }
	return ids
end

function ZoneRotation.bonus(zoneId: string?, now: number): Bonus?
	if not zoneId then return nil end
	if table.find(ZoneRotation.favoured(now), zoneId) then
		local f = Config.ZoneRotation.Favoured
		return { Kind = "Favoured", Luck = f.Luck, Clacks = f.Clacks, Prismatic = true }
	end
	if table.find(ZoneRotation.vintage(now), zoneId) then
		local v = Config.ZoneRotation.Vintage
		return { Kind = "Vintage", Luck = v.Luck, Clacks = v.Clacks, Prismatic = false }
	end
	return nil
end

-- Short text for a bonus: "🌟 Favoured · x2 Luck · x1.5 Clacks · Prismatic".
function ZoneRotation.describe(bonus: Bonus, short: boolean?): string
	local icon = if bonus.Kind == "Favoured" then "🌟" else "🕰️"
	if short then
		return `{icon} {bonus.Kind}`
	end
	local text = `{icon} {bonus.Kind} · x{bonus.Luck} Luck · x{bonus.Clacks} Clacks`
	if bonus.Prismatic then
		text ..= " · Prismatic rolls"
	end
	return text
end

-- Seconds until the Favoured zones change (next UTC midnight).
function ZoneRotation.untilNextDay(now: number): number
	return (ZoneRotation.day(now) + 1) * DAY - now
end

-- Seconds until the week rolls over (Vintage zones, weekly quests, weekly
-- leaderboards): next Monday 00:00 UTC.
function ZoneRotation.untilNextWeek(now: number): number
	return (ZoneRotation.week(now) + 1) * WEEK - 3 * DAY - now
end

return ZoneRotation
