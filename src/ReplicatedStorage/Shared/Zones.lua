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

-- The zones built in Studio (workspace.Zones), in the order players unlock
-- them: a snake across the map, five per row. Each zone Model carries its
-- Id as the ZoneId attribute (tools/wire_place.luau sets them up).
-- Prices: the first seven by hand, then each zone costs PRICE_GROWTH more
-- and pays MULTIPLIER_GROWTH more per key (tools/balance.py checks the
-- curve: ~4 minutes per zone early, rising later).
local zones: { { Id: string, Name: string, Emoji: string, Color: Color3 } } = {
	{ Id = "Grasslands", Name = "Grasslands", Emoji = "🌳", Color = Color3.fromRGB(120, 220, 90) },
	{ Id = "City", Name = "City", Emoji = "🏙️", Color = Color3.fromRGB(110, 190, 255) },
	{ Id = "Desert", Name = "Desert", Emoji = "🏜️", Color = Color3.fromRGB(240, 200, 90) },
	{ Id = "Orchard", Name = "Orchard", Emoji = "🍎", Color = Color3.fromRGB(255, 110, 90) },
	{ Id = "Frostlands", Name = "Frostlands", Emoji = "❄️", Color = Color3.fromRGB(120, 200, 255) },
	{ Id = "Springs", Name = "Fountain Springs", Emoji = "⛲", Color = Color3.fromRGB(220, 120, 220) },
	{ Id = "Village", Name = "Village", Emoji = "🏡", Color = Color3.fromRGB(130, 210, 110) },
	{ Id = "Metro", Name = "Metro", Emoji = "🚕", Color = Color3.fromRGB(190, 190, 205) },
	{ Id = "WildWest", Name = "Wild West", Emoji = "🤠", Color = Color3.fromRGB(230, 180, 110) },
	{ Id = "Quarry", Name = "Quarry", Emoji = "🏗️", Color = Color3.fromRGB(230, 200, 70) },
	{ Id = "Reef", Name = "Coral Reef", Emoji = "🐠", Color = Color3.fromRGB(255, 130, 110) },
	{ Id = "Lagoon", Name = "Shell Lagoon", Emoji = "🐚", Color = Color3.fromRGB(255, 160, 140) },
	{ Id = "Beach", Name = "Beach", Emoji = "🏖️", Color = Color3.fromRGB(255, 214, 120) },
	{ Id = "Meadow", Name = "Meadow", Emoji = "🌼", Color = Color3.fromRGB(150, 230, 100) },
	{ Id = "Woodlands", Name = "Woodlands", Emoji = "🌲", Color = Color3.fromRGB(90, 190, 90) },
	{ Id = "Jungle", Name = "Jungle", Emoji = "🌴", Color = Color3.fromRGB(150, 230, 60) },
	{ Id = "Canyon", Name = "Canyon", Emoji = "🪨", Color = Color3.fromRGB(235, 170, 80) },
	{ Id = "Suburbs", Name = "Suburbs", Emoji = "🏘️", Color = Color3.fromRGB(140, 220, 140) },
	{ Id = "Lumberyard", Name = "Lumberyard", Emoji = "🪵", Color = Color3.fromRGB(200, 140, 90) },
	{ Id = "Hive", Name = "Hive", Emoji = "🐝", Color = Color3.fromRGB(255, 170, 50) },
	{ Id = "Snowfield", Name = "Snowfield", Emoji = "☃️", Color = Color3.fromRGB(230, 245, 255) },
	{ Id = "Wildwood", Name = "Wildwood", Emoji = "🍃", Color = Color3.fromRGB(100, 200, 110) },
	{ Id = "Tropics", Name = "Tropics", Emoji = "🏝️", Color = Color3.fromRGB(80, 220, 200) },
	{ Id = "Ashlands", Name = "Ashlands", Emoji = "🌋", Color = Color3.fromRGB(255, 100, 60) },
	{ Id = "Glacier", Name = "Glacier", Emoji = "🧊", Color = Color3.fromRGB(100, 180, 255) },
	{ Id = "CrystalSprings", Name = "Crystal Springs", Emoji = "💎", Color = Color3.fromRGB(200, 130, 255) },
	{ Id = "Hamlet", Name = "Hamlet", Emoji = "🛖", Color = Color3.fromRGB(170, 220, 120) },
	{ Id = "Downtown", Name = "Downtown", Emoji = "🌆", Color = Color3.fromRGB(255, 140, 200) },
	{ Id = "Frontier", Name = "Frontier", Emoji = "🐎", Color = Color3.fromRGB(240, 190, 120) },
	{ Id = "Honeycomb", Name = "Honeycomb", Emoji = "🍯", Color = Color3.fromRGB(255, 200, 60) },
	{ Id = "Tundra", Name = "Tundra", Emoji = "🐧", Color = Color3.fromRGB(200, 230, 255) },
	{ Id = "Elderwood", Name = "Elderwood", Emoji = "🦉", Color = Color3.fromRGB(120, 210, 150) },
	{ Id = "Badlands", Name = "Badlands", Emoji = "🦂", Color = Color3.fromRGB(230, 150, 70) },
	{ Id = "Obsidian", Name = "Obsidian Wastes", Emoji = "🖤", Color = Color3.fromRGB(170, 120, 255) },
}

-- The first zones are priced by hand; after that the curve takes over.
local HAND_PRICES = { 0, 1_400, 3_700, 9_700, 22_000, 45_000, 91_000 }
local HAND_MULTIPLIERS = { 1, 2, 4, 7, 11, 17, 26 }
local PRICE_GROWTH = 1.95
local MULTIPLIER_GROWTH = 1.5

local function roundTo2Figures(value: number): number
	local scale = 10 ^ math.max(0, math.floor(math.log10(value)) - 1)
	return math.floor(value / scale + 0.5) * scale
end

local list: { ZoneDef } = {}
for order, entry in zones do
	local previous = list[order - 1]
	table.insert(list, {
		Id = entry.Id,
		Name = entry.Name,
		Order = order,
		Price = HAND_PRICES[order] or roundTo2Figures(previous.Price * PRICE_GROWTH),
		KeyMultiplier = HAND_MULTIPLIERS[order] or math.floor(previous.KeyMultiplier * MULTIPLIER_GROWTH + 0.5),
		Emoji = entry.Emoji,
		Color = entry.Color,
	})
end

-- Ids before the Studio-built map, by order (PlayerData migrates saves
-- that still use them: the zone at the same place in the order).
local LEGACY_ORDER = {
	"Office", "Arcade", "Studio", "Neon", "Islands", "Cave", "Space", "Desert", "Jungle", "Candy",
	"Autumn", "Shroom", "Reef", "Swamp", "Sakura", "Canyon", "Tundra", "Ashlands", "Toyland", "Farm",
	"Haunted", "Geode", "Clockwork", "CyberCity", "Moon", "Mars", "Galaxy", "Atlantis", "Pirate", "WildWest",
	"Oasis", "Savanna", "Bamboo", "Frostpeak", "Rainbow", "Dino", "Bakery", "Toxic", "Factory", "Ruins",
	"SkyIsles", "CrystalGarden", "NeonNights", "Underworld", "Fairy", "Thunder", "Abyss", "GoldenCity", "Void", "Kingdom",
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
	LegacyOrder = LEGACY_ORDER,
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
