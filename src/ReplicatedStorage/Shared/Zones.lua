--[[

Zones
ModuleScript
/ReplicatedStorage/Shared/Zones

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Zones are bought with Clacks, in order. A zone's Id is also the World
-- that its studs roll from (Studs.luau) and the World its keys belong to
-- (PressTracker), and owned zones are saved in PlayerData.UnlockedWorlds.
--
-- KeyMultiplier: every key press inside the zone is worth this many times
-- the key's own Value.
--
-- Ids are saved in player data: never rename an Id once the game is live.

local Studs = require(script.Parent.Studs)

export type ZoneDef = {
	Id: string,
	Name: string,
	Order: number,
	Price: number,
	KeyMultiplier: number,
	Emoji: string,
	Color: Color3,
}

local list: { ZoneDef } = {
	{ Id = "Office", Name = "Office", Order = 1, Price = 0, KeyMultiplier = 1, Emoji = "🏢",
		Color = Color3.fromRGB(196, 202, 212) },
	{ Id = "Arcade", Name = "Arcade", Order = 2, Price = 25_000, KeyMultiplier = 2, Emoji = "🕹️",
		Color = Color3.fromRGB(255, 120, 200) },
	{ Id = "Studio", Name = "Studio", Order = 3, Price = 400_000, KeyMultiplier = 4, Emoji = "🎙️",
		Color = Color3.fromRGB(255, 196, 64) },
	{ Id = "Neon", Name = "Neon City", Order = 4, Price = 6_000_000, KeyMultiplier = 8, Emoji = "🌃",
		Color = Color3.fromRGB(90, 220, 255) },
	{ Id = "Space", Name = "Space", Order = 5, Price = 100_000_000, KeyMultiplier = 16, Emoji = "🚀",
		Color = Color3.fromRGB(176, 104, 255) },
}

local byId: { [string]: ZoneDef } = {}
for _, def in list do
	assert(not byId[def.Id], `Duplicate zone id: {def.Id}`)
	byId[def.Id] = def
end

local Zones = {
	List = list,
	ById = byId,
	Default = list[1].Id,
}

function Zones.price(def: ZoneDef, discount: number): number
	return math.floor(def.Price * (1 - math.clamp(discount, 0, 1)))
end

-- The next zone the player can buy, or nil when they own every zone.
function Zones.nextFor(unlocked: { [string]: boolean }): ZoneDef?
	for _, def in list do
		if not unlocked[def.Id] then
			return def
		end
	end
	return nil
end

-- Highest owned zone's KeyMultiplier (used to scale Clack rewards).
function Zones.bestMultiplier(unlocked: { [string]: boolean }): number
	local best = 1
	for _, def in list do
		if unlocked[def.Id] then
			best = math.max(best, def.KeyMultiplier)
		end
	end
	return best
end

-- How many studs roll only in this zone.
function Zones.studCount(zoneId: string): number
	local n = 0
	for _, def in Studs.List do
		if def.World == zoneId then
			n += 1
		end
	end
	return n
end

return Zones
