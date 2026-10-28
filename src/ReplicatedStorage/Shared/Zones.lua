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
	-- Ids predate the biome names (they're saved in player data): Office is
	-- Grasslands, Arcade is Beach, Studio is Polar, Neon is Volcano and Space
	-- is Heaven.
	{ Id = "Office", Name = "Grasslands", Order = 1, Price = 0, KeyMultiplier = 1, Emoji = "🌳",
		Color = Color3.fromRGB(120, 220, 90) },
	{ Id = "Arcade", Name = "Beach", Order = 2, Price = 25_000, KeyMultiplier = 2, Emoji = "🏖️",
		Color = Color3.fromRGB(255, 214, 120) },
	{ Id = "Studio", Name = "Polar", Order = 3, Price = 400_000, KeyMultiplier = 4, Emoji = "❄️",
		Color = Color3.fromRGB(150, 220, 255) },
	{ Id = "Neon", Name = "Volcano", Order = 4, Price = 6_000_000, KeyMultiplier = 8, Emoji = "🌋",
		Color = Color3.fromRGB(255, 110, 50) },
	{ Id = "Islands", Name = "Islands", Order = 5, Price = 40_000_000, KeyMultiplier = 12, Emoji = "🏝️",
		Color = Color3.fromRGB(60, 220, 200) },
	{ Id = "Cave", Name = "Cave", Order = 6, Price = 250_000_000, KeyMultiplier = 20, Emoji = "💎",
		Color = Color3.fromRGB(176, 104, 255) },
	{ Id = "Space", Name = "Heaven", Order = 7, Price = 1_500_000_000, KeyMultiplier = 32, Emoji = "☁️",
		Color = Color3.fromRGB(255, 236, 150) },
}

local byId: { [string]: ZoneDef } = {}
for index, def in list do
	assert(def.Order == index, `Zone {def.Id} has Order {def.Order}, expected {index}`)
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
