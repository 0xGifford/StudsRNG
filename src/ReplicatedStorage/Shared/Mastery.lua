--[[

Mastery
ModuleScript
/ReplicatedStorage/Shared/Mastery

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Zone Mastery (Config.Mastery): 0-3 stars per zone, worked out from saved
-- data, so server and client agree.
--   1 star   own the zone
--   2 stars  + found every stud of the zone but its rarest (any variant;
--            Secrets don't count)
--   3 stars  + found all of them, and defeated Config.Mastery.Kills enemies
--            in the zone (PlayerData.ZoneKills)
-- Stars add to your Clack multiplier everywhere, and keys in 2 / 3 star
-- zones pay more.

local Config = require(script.Parent.Config)
local Studs = require(script.Parent.Studs)
local Zones = require(script.Parent.Zones)
local Variants = require(script.Parent.Variants)

local Mastery = {}

-- Each zone's own rollable, non-Secret studs, commonest first.
local zoneStuds: { [string]: { string } } = {}
do
	local byZone: { [string]: { any } } = {}
	for _, def in Studs.List do
		if not def.Drop and def.Rarity ~= "Secret" then
			byZone[def.World] = byZone[def.World] or {}
			table.insert(byZone[def.World], def)
		end
	end
	for zone, list in byZone do
		table.sort(list, function(a, b)
			return a.OneIn < b.OneIn
		end)
		local ids = {}
		for _, def in list do
			table.insert(ids, def.Id)
		end
		zoneStuds[zone] = ids
	end
end

local function found(index: { [string]: boolean }, studId: string): boolean
	for _, name in Variants.Order do
		if index[`{studId}:{name}`] then
			return true
		end
	end
	return false
end

-- How many of the zone's studs are found, of how many.
function Mastery.collection(data: any, zoneId: string): (number, number)
	local ids = zoneStuds[zoneId] or {}
	local index = if typeof(data.Index) == "table" then data.Index else {}
	local n = 0
	for _, id in ids do
		if found(index, id) then
			n += 1
		end
	end
	return n, #ids
end

function Mastery.stars(data: any, zoneId: string): number
	local unlocked = if typeof(data.UnlockedWorlds) == "table" then data.UnlockedWorlds else {}
	if not unlocked[zoneId] then return 0 end
	local have, total = Mastery.collection(data, zoneId)
	if total == 0 or have < total - 1 then return 1 end
	if have < total then return 2 end
	local kills = if typeof(data.ZoneKills) == "table" then data.ZoneKills[zoneId] or 0 else 0
	return if kills >= Config.Mastery.Kills then 3 else 2
end

function Mastery.totalStars(data: any): number
	local total = 0
	for _, def in Zones.List do
		total += Mastery.stars(data, def.Id)
	end
	return total
end

-- Extra share keys in this zone pay (0, 0.25, 0.6 by stars).
function Mastery.keyBonus(stars: number): number
	return Config.Mastery.KeyBonus[stars] or 0
end

function Mastery.text(stars: number): string
	return string.rep("★", stars) .. string.rep("☆", 3 - stars)
end

return Mastery
