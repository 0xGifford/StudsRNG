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

-- The zones built in Studio (workspace.Zones.Zone1 .. Zone34), in the
-- order players unlock them. Zone N's Id is N padded to three digits
-- ("001"), and the model's ZoneId attribute carries it (tools/wire_zones.luau
-- or the ZoneManager plugin set it; Tags.idOfZone also reads "ZoneN" names).
-- Players see "Zone N". Colors tint the zone's UI (signs, cards, banners).
local COUNT = 34
local PALETTE = {
	Color3.fromRGB(120, 220, 90), Color3.fromRGB(110, 190, 255), Color3.fromRGB(240, 200, 90),
	Color3.fromRGB(255, 110, 90), Color3.fromRGB(120, 200, 255), Color3.fromRGB(220, 120, 220),
	Color3.fromRGB(130, 210, 110), Color3.fromRGB(190, 190, 205), Color3.fromRGB(230, 180, 110),
	Color3.fromRGB(230, 200, 70), Color3.fromRGB(255, 130, 110), Color3.fromRGB(255, 160, 140),
	Color3.fromRGB(255, 214, 120), Color3.fromRGB(150, 230, 100), Color3.fromRGB(90, 190, 90),
	Color3.fromRGB(150, 230, 60), Color3.fromRGB(235, 170, 80), Color3.fromRGB(140, 220, 140),
	Color3.fromRGB(200, 140, 90), Color3.fromRGB(255, 170, 50), Color3.fromRGB(230, 245, 255),
	Color3.fromRGB(100, 200, 110), Color3.fromRGB(80, 220, 200), Color3.fromRGB(255, 100, 60),
	Color3.fromRGB(100, 180, 255), Color3.fromRGB(200, 130, 255), Color3.fromRGB(170, 220, 120),
	Color3.fromRGB(255, 140, 200), Color3.fromRGB(240, 190, 120), Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(200, 230, 255), Color3.fromRGB(120, 210, 150), Color3.fromRGB(230, 150, 70),
	Color3.fromRGB(170, 120, 255),
}

local zones: { { Id: string, Name: string, Emoji: string, Color: Color3 } } = {}
for n = 1, COUNT do
	table.insert(zones, {
		Id = string.format("%03d", n),
		Name = `Zone {n}`,
		Emoji = "",
		Color = PALETTE[(n - 1) % #PALETTE + 1],
	})
end

-- The first zones are priced by hand; after that the curve takes over.
local HAND_PRICES = { 0, 600, 2_500, 8_000, 24_000, 65_000, 170_000 }
local HAND_MULTIPLIERS = { 1, 2, 3, 5, 8, 12, 17 }
-- Each zone after the hand-priced ones costs PRICE_GROWTH times the last,
-- easing to PRICE_GROWTH_END by the last zone (steep mid-game, gentler at
-- the end, where upgrades are maxed and only studs and rebirths still grow).
-- Balance with tools/simulate.py.
local PRICE_GROWTH = 3.4
local PRICE_GROWTH_END = 1.55
local MULTIPLIER_GROWTH = 1.22

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
		Price = HAND_PRICES[order] or roundTo2Figures(previous.Price * (PRICE_GROWTH
			+ (PRICE_GROWTH_END - PRICE_GROWTH) * (order - #HAND_PRICES) / math.max(COUNT - #HAND_PRICES, 1))),
		KeyMultiplier = HAND_MULTIPLIERS[order] or math.floor(previous.KeyMultiplier * MULTIPLIER_GROWTH + 0.5),
		Emoji = entry.Emoji,
		Color = entry.Color,
	})
end

-- Saved ids from earlier maps, by version, in unlock order. PlayerData
-- migrates a save by place in the order (the 3rd zone stays the 3rd zone).
local LEGACY = {
	-- v1: the generated map
	[1] = {
		"Office", "Arcade", "Studio", "Neon", "Islands", "Cave", "Space", "Desert", "Jungle", "Candy",
		"Autumn", "Shroom", "Reef", "Swamp", "Sakura", "Canyon", "Tundra", "Ashlands", "Toyland", "Farm",
		"Haunted", "Geode", "Clockwork", "CyberCity", "Moon", "Mars", "Galaxy", "Atlantis", "Pirate", "WildWest",
		"Oasis", "Savanna", "Bamboo", "Frostpeak", "Rainbow", "Dino", "Bakery", "Toxic", "Factory", "Ruins",
		"SkyIsles", "CrystalGarden", "NeonNights", "Underworld", "Fairy", "Thunder", "Abyss", "GoldenCity", "Void", "Kingdom",
	},
	-- v2: the first hand-built map
	[2] = {
		"Grasslands", "City", "Desert", "Orchard", "Frostlands", "Springs", "Village", "Metro", "WildWest", "Quarry",
		"Reef", "Lagoon", "Beach", "Meadow", "Woodlands", "Jungle", "Canyon", "Suburbs", "Lumberyard", "Hive",
		"Snowfield", "Wildwood", "Tropics", "Ashlands", "Glacier", "CrystalSprings", "Hamlet", "Downtown", "Frontier", "Honeycomb",
		"Tundra", "Elderwood", "Badlands", "Obsidian",
	},
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
	Legacy = LEGACY,
}

-- The id for a zone model named "Zone7" (or "zone 7"), else nil.
function Zones.idFromName(name: string): string?
	local n = tonumber(string.match(string.lower(name), "^zone%s*(%d+)$"))
	return if n then string.format("%03d", n) else nil
end

-- What signs, cards and banners show: "🌵 Zone 4", or "Zone 4" with no emoji.
function Zones.title(def: ZoneDef): string
	return if def.Emoji ~= "" then `{def.Emoji} {def.Name}` else def.Name
end

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
