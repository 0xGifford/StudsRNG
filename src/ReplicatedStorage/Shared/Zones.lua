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
	{ Id = "Arcade", Name = "Beach", Order = 2, Price = 1_400, KeyMultiplier = 2, Emoji = "🏖️",
		Color = Color3.fromRGB(255, 214, 120) },
	{ Id = "Studio", Name = "Polar", Order = 3, Price = 3_700, KeyMultiplier = 4, Emoji = "❄️",
		Color = Color3.fromRGB(150, 220, 255) },
	{ Id = "Neon", Name = "Volcano", Order = 4, Price = 9_700, KeyMultiplier = 7, Emoji = "🌋",
		Color = Color3.fromRGB(255, 110, 50) },
	{ Id = "Islands", Name = "Islands", Order = 5, Price = 22_000, KeyMultiplier = 11, Emoji = "🏝️",
		Color = Color3.fromRGB(60, 220, 200) },
	{ Id = "Cave", Name = "Cave", Order = 6, Price = 45_000, KeyMultiplier = 17, Emoji = "💎",
		Color = Color3.fromRGB(176, 104, 255) },
	{ Id = "Space", Name = "Heaven", Order = 7, Price = 91_000, KeyMultiplier = 26, Emoji = "☁️",
		Color = Color3.fromRGB(255, 236, 150) },
}

-- Zones 8+ are priced on a curve from the last hand-priced zone: each costs
-- PRICE_GROWTH times the one before and multiplies keys by MULTIPLIER_GROWTH
-- (prices kept to 2 significant figures). Built in Studio with tools/ZoneKit.
-- Balance (see the curve notes below): each zone pays x1.5 per key and costs
-- x1.95 more, so the next zone takes ~4 minutes early and ~45 near the end
-- for a player whose studs / rebirths / upgrades keep pace.
local PRICE_GROWTH = 1.95
local MULTIPLIER_GROWTH = 1.5
local curved: { { Id: string, Name: string, Emoji: string, Color: Color3 } } = {
	{ Id = "Desert", Name = "Desert", Emoji = "🏜️", Color = Color3.fromHex("#FFAA3C") },
	{ Id = "Jungle", Name = "Jungle", Emoji = "🌴", Color = Color3.fromHex("#3CC85A") },
	{ Id = "Candy", Name = "Candyland", Emoji = "🍭", Color = Color3.fromHex("#FF78C8") },
	{ Id = "Autumn", Name = "Autumn Woods", Emoji = "🍂", Color = Color3.fromHex("#FF8C28") },
	{ Id = "Shroom", Name = "Shroomlands", Emoji = "🍄", Color = Color3.fromHex("#FF5A5A") },
	{ Id = "Reef", Name = "Coral Reef", Emoji = "🐠", Color = Color3.fromHex("#FF6EAA") },
	{ Id = "Swamp", Name = "Swamp", Emoji = "🐸", Color = Color3.fromHex("#8CC83C") },
	{ Id = "Sakura", Name = "Sakura Gardens", Emoji = "🌸", Color = Color3.fromHex("#FF96C8") },
	{ Id = "Canyon", Name = "Red Canyon", Emoji = "🏜️", Color = Color3.fromHex("#E0643C") },
	{ Id = "Tundra", Name = "Tundra", Emoji = "🐧", Color = Color3.fromHex("#78B4FF") },
	{ Id = "Ashlands", Name = "Ashlands", Emoji = "🔥", Color = Color3.fromHex("#FF5A28") },
	{ Id = "Toyland", Name = "Toyland", Emoji = "🧸", Color = Color3.fromHex("#3C8CFF") },
	{ Id = "Farm", Name = "Farm", Emoji = "🚜", Color = Color3.fromHex("#E0B43C") },
	{ Id = "Haunted", Name = "Haunted Hollow", Emoji = "👻", Color = Color3.fromHex("#9A5AFF") },
	{ Id = "Geode", Name = "Geode Grotto", Emoji = "🔮", Color = Color3.fromHex("#5AE6FF") },
	{ Id = "Clockwork", Name = "Clockwork", Emoji = "⚙️", Color = Color3.fromHex("#D4A048") },
	{ Id = "CyberCity", Name = "Cyber City", Emoji = "🌃", Color = Color3.fromHex("#3CF0FF") },
	{ Id = "Moon", Name = "Moon Base", Emoji = "🌙", Color = Color3.fromHex("#C8C8D2") },
	{ Id = "Mars", Name = "Mars", Emoji = "🔴", Color = Color3.fromHex("#E05A2E") },
	{ Id = "Galaxy", Name = "Galaxy", Emoji = "🌌", Color = Color3.fromHex("#B478FF") },
	{ Id = "Atlantis", Name = "Atlantis", Emoji = "🔱", Color = Color3.fromHex("#3CC8E6") },
	{ Id = "Pirate", Name = "Pirate Cove", Emoji = "🏴‍☠️", Color = Color3.fromHex("#E0B43C") },
	{ Id = "WildWest", Name = "Wild West", Emoji = "🤠", Color = Color3.fromHex("#C8783C") },
	{ Id = "Oasis", Name = "Oasis", Emoji = "🐪", Color = Color3.fromHex("#3CC8B4") },
	{ Id = "Savanna", Name = "Savanna", Emoji = "🦁", Color = Color3.fromHex("#E6B43C") },
	{ Id = "Bamboo", Name = "Bamboo Forest", Emoji = "🎋", Color = Color3.fromHex("#6DB33F") },
	{ Id = "Frostpeak", Name = "Frostpeak", Emoji = "🏔️", Color = Color3.fromHex("#5AA0FF") },
	{ Id = "Rainbow", Name = "Rainbow Road", Emoji = "🌈", Color = Color3.fromHex("#FF5AA0") },
	{ Id = "Dino", Name = "Dino Valley", Emoji = "🦖", Color = Color3.fromHex("#7AB43C") },
	{ Id = "Bakery", Name = "Sweet Bakery", Emoji = "🧁", Color = Color3.fromHex("#FFB4C8") },
	{ Id = "Toxic", Name = "Toxic Wastes", Emoji = "☢️", Color = Color3.fromHex("#8CFF3C") },
	{ Id = "Factory", Name = "Factory", Emoji = "🏭", Color = Color3.fromHex("#FFC83C") },
	{ Id = "Ruins", Name = "Ancient Ruins", Emoji = "🏛️", Color = Color3.fromHex("#C8B478") },
	{ Id = "SkyIsles", Name = "Floating Isles", Emoji = "🪂", Color = Color3.fromHex("#5AC8FF") },
	{ Id = "CrystalGarden", Name = "Crystal Garden", Emoji = "💠", Color = Color3.fromHex("#78FFDC") },
	{ Id = "NeonNights", Name = "Neon Nights", Emoji = "🌆", Color = Color3.fromHex("#FF3CC8") },
	{ Id = "Underworld", Name = "Underworld", Emoji = "💀", Color = Color3.fromHex("#FF3C3C") },
	{ Id = "Fairy", Name = "Fairy Forest", Emoji = "🧚", Color = Color3.fromHex("#E6A0FF") },
	{ Id = "Thunder", Name = "Thunder Peaks", Emoji = "⚡", Color = Color3.fromHex("#FFE63C") },
	{ Id = "Abyss", Name = "The Abyss", Emoji = "🦑", Color = Color3.fromHex("#3C5AFF") },
	{ Id = "GoldenCity", Name = "Golden City", Emoji = "👑", Color = Color3.fromHex("#FFD23C") },
	{ Id = "Void", Name = "The Void", Emoji = "🕳️", Color = Color3.fromHex("#FFFFFF") },
	{ Id = "Kingdom", Name = "Keyboard Kingdom", Emoji = "🏰", Color = Color3.fromHex("#FF4E6A") },
}

local function roundTo2Figures(value: number): number
	local scale = 10 ^ math.max(0, math.floor(math.log10(value)) - 1)
	return math.floor(value / scale + 0.5) * scale
end

for _, entry in curved do
	local previous = list[#list]
	table.insert(list, {
		Id = entry.Id,
		Name = entry.Name,
		Order = #list + 1,
		Price = roundTo2Figures(previous.Price * PRICE_GROWTH),
		KeyMultiplier = math.floor(previous.KeyMultiplier * MULTIPLIER_GROWTH + 0.5),
		Emoji = entry.Emoji,
		Color = entry.Color,
	})
end

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
