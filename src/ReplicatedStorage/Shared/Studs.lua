--[[ 

Studs
ModuleScript
/ReplicatedStorage/Shared/Studs

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The stud index. Every stud is the same 1×1×1 part; only Color, Material,
-- Particle preset and Light change. Particle presets live in Util/StudVisuals.
--
-- OneIn: nominal odds ("1 in X") before luck.
-- Multiplier: Clacks multiplier when equipped (Normal variant).
-- World: which pool it rolls from. A player only rolls studs from worlds they
--        have unlocked (PlayerData.UnlockedWorlds).
--
-- Ids are saved in player data: never rename an Id once the game is live.

local Types = require(script.Parent.Types)

type StudDef = Types.StudDef

local list: { StudDef } = {
	-- Common
	{ Id = "Chalk", Name = "Chalk", Rarity = "Common", OneIn = 2, Multiplier = 1.1, World = "Office",
		Color = Color3.fromRGB(235, 235, 230), Material = Enum.Material.SmoothPlastic },
	{ Id = "Pebble", Name = "Pebble", Rarity = "Common", OneIn = 3, Multiplier = 1.15, World = "Office",
		Color = Color3.fromRGB(140, 140, 150), Material = Enum.Material.SmoothPlastic },
	{ Id = "Moss", Name = "Moss", Rarity = "Common", OneIn = 4, Multiplier = 1.2, World = "Office",
		Color = Color3.fromRGB(110, 150, 80), Material = Enum.Material.SmoothPlastic },
	{ Id = "Sky", Name = "Sky", Rarity = "Common", OneIn = 5, Multiplier = 1.25, World = "Office",
		Color = Color3.fromRGB(130, 190, 255), Material = Enum.Material.SmoothPlastic },

	-- Uncommon
	{ Id = "Mint", Name = "Mint", Rarity = "Uncommon", OneIn = 10, Multiplier = 1.4, World = "Office",
		Color = Color3.fromRGB(150, 255, 200), Material = Enum.Material.SmoothPlastic },
	{ Id = "Coral", Name = "Coral", Rarity = "Uncommon", OneIn = 15, Multiplier = 1.5, World = "Office",
		Color = Color3.fromRGB(255, 130, 110), Material = Enum.Material.SmoothPlastic },
	{ Id = "Lilac", Name = "Lilac", Rarity = "Uncommon", OneIn = 25, Multiplier = 1.6, World = "Office",
		Color = Color3.fromRGB(200, 160, 255), Material = Enum.Material.SmoothPlastic, Particle = "Dust" },

	-- Rare
	{ Id = "Ember", Name = "Ember", Rarity = "Rare", OneIn = 50, Multiplier = 2, World = "Office",
		Color = Color3.fromRGB(255, 90, 30), Material = Enum.Material.Neon, Particle = "Embers" },
	{ Id = "Tide", Name = "Tide", Rarity = "Rare", OneIn = 100, Multiplier = 2.3, World = "Office",
		Color = Color3.fromRGB(40, 140, 255), Material = Enum.Material.Glass, Particle = "Bubbles" },
	{ Id = "Spruce", Name = "Spruce", Rarity = "Rare", OneIn = 150, Multiplier = 2.6, World = "Office",
		Color = Color3.fromRGB(30, 110, 60), Material = Enum.Material.SmoothPlastic, Particle = "Leaves" },

	-- Epic
	{ Id = "Plasma", Name = "Plasma", Rarity = "Epic", OneIn = 400, Multiplier = 3.5, World = "Office",
		Color = Color3.fromRGB(255, 60, 220), Material = Enum.Material.Neon, Particle = "Sparkle", Light = true },
	{ Id = "Frostbite", Name = "Frostbite", Rarity = "Epic", OneIn = 750, Multiplier = 4, World = "Office",
		Color = Color3.fromRGB(190, 240, 255), Material = Enum.Material.Glass, Particle = "Snow", Light = true },

	-- Legendary
	{ Id = "Solar", Name = "Solar", Rarity = "Legendary", OneIn = 2500, Multiplier = 6, World = "Office",
		Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Nebula", Name = "Nebula", Rarity = "Legendary", OneIn = 5000, Multiplier = 8, World = "Office",
		Color = Color3.fromRGB(90, 40, 200), Material = Enum.Material.ForceField, Particle = "Stars", Light = true },

	-- Mythic
	{ Id = "Void", Name = "Void", Rarity = "Mythic", OneIn = 25000, Multiplier = 15, World = "Office",
		Color = Color3.fromRGB(15, 10, 25), Material = Enum.Material.Neon, Particle = "Void", Light = true },
	{ Id = "Prism", Name = "Prism", Rarity = "Mythic", OneIn = 50000, Multiplier = 20, World = "Office",
		Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.Glass, Particle = "Sparkle", Light = true },

	-- Secret
	{ Id = "Glitch", Name = "???", Rarity = "Secret", OneIn = 1000000, Multiplier = 50, World = "Office",
		Color = Color3.fromRGB(0, 255, 120), Material = Enum.Material.Neon, Particle = "Glitch", Light = true },

	-- Beach (zone exclusive; Id Arcade)
	{ Id = "Pixel", Name = "Seashell", Rarity = "Uncommon", OneIn = 35, Multiplier = 1.8, World = "Arcade",
		Color = Color3.fromRGB(255, 190, 200), Material = Enum.Material.SmoothPlastic, Particle = "Dust" },
	{ Id = "Token", Name = "Sandcastle", Rarity = "Rare", OneIn = 200, Multiplier = 3, World = "Arcade",
		Color = Color3.fromRGB(255, 190, 60), Material = Enum.Material.Foil, Particle = "Sparkle" },
	{ Id = "Combo", Name = "Lagoon", Rarity = "Epic", OneIn = 1200, Multiplier = 5, World = "Arcade",
		Color = Color3.fromRGB(40, 220, 210), Material = Enum.Material.Neon, Particle = "Sparkle", Light = true },
	{ Id = "Highscore", Name = "Sunset", Rarity = "Legendary", OneIn = 8000, Multiplier = 10, World = "Arcade",
		Color = Color3.fromRGB(255, 120, 60), Material = Enum.Material.Neon, Particle = "Flare", Light = true },

	-- Polar (zone exclusive; Id Studio)
	{ Id = "Vinyl", Name = "Snowflake", Rarity = "Rare", OneIn = 300, Multiplier = 3.5, World = "Studio",
		Color = Color3.fromRGB(235, 245, 255), Material = Enum.Material.Glass, Particle = "Snow" },
	{ Id = "Spotlight", Name = "Glacier", Rarity = "Epic", OneIn = 2000, Multiplier = 6, World = "Studio",
		Color = Color3.fromRGB(140, 210, 255), Material = Enum.Material.Ice, Particle = "Sparkle", Light = true },
	{ Id = "Encore", Name = "Aurora", Rarity = "Legendary", OneIn = 12000, Multiplier = 12, World = "Studio",
		Color = Color3.fromRGB(90, 255, 170), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Platinum", Name = "Permafrost", Rarity = "Mythic", OneIn = 80000, Multiplier = 25, World = "Studio",
		Color = Color3.fromRGB(220, 230, 240), Material = Enum.Material.Foil, Particle = "Stars", Light = true },

	-- Volcano (zone exclusive; Id Neon)
	{ Id = "Synth", Name = "Magma", Rarity = "Epic", OneIn = 3000, Multiplier = 7, World = "Neon",
		Color = Color3.fromRGB(255, 120, 20), Material = Enum.Material.Neon, Particle = "Embers", Light = true },
	{ Id = "Laser", Name = "Obsidian", Rarity = "Legendary", OneIn = 20000, Multiplier = 14, World = "Neon",
		Color = Color3.fromRGB(40, 20, 50), Material = Enum.Material.Glass, Particle = "Embers", Light = true },
	{ Id = "Overdrive", Name = "Eruption", Rarity = "Mythic", OneIn = 120000, Multiplier = 30, World = "Neon",
		Color = Color3.fromRGB(255, 70, 20), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Cyber", Name = "Inferno", Rarity = "Mythic", OneIn = 250000, Multiplier = 40, World = "Neon",
		Color = Color3.fromRGB(255, 40, 0), Material = Enum.Material.ForceField, Particle = "Embers", Light = true },

	-- Islands (zone exclusive)
	{ Id = "Coconut", Name = "Coconut", Rarity = "Rare", OneIn = 500, Multiplier = 4, World = "Islands",
		Color = Color3.fromRGB(130, 85, 50), Material = Enum.Material.Wood, Particle = "Dust" },
	{ Id = "Hibiscus", Name = "Hibiscus", Rarity = "Epic", OneIn = 5000, Multiplier = 9, World = "Islands",
		Color = Color3.fromRGB(255, 70, 120), Material = Enum.Material.SmoothPlastic, Particle = "Sparkle", Light = true },
	{ Id = "Tsunami", Name = "Tsunami", Rarity = "Legendary", OneIn = 25000, Multiplier = 15, World = "Islands",
		Color = Color3.fromRGB(30, 140, 255), Material = Enum.Material.Glass, Particle = "Flare", Light = true },
	{ Id = "Kraken", Name = "Kraken", Rarity = "Mythic", OneIn = 180000, Multiplier = 33, World = "Islands",
		Color = Color3.fromRGB(120, 40, 160), Material = Enum.Material.Neon, Particle = "Void", Light = true },

	-- Cave (zone exclusive)
	{ Id = "Amethyst", Name = "Amethyst", Rarity = "Epic", OneIn = 8000, Multiplier = 11, World = "Cave",
		Color = Color3.fromRGB(170, 90, 255), Material = Enum.Material.Glass, Particle = "Sparkle", Light = true },
	{ Id = "Glowshroom", Name = "Glowshroom", Rarity = "Legendary", OneIn = 40000, Multiplier = 18, World = "Cave",
		Color = Color3.fromRGB(60, 255, 200), Material = Enum.Material.Neon, Particle = "Stars", Light = true },
	{ Id = "Geode", Name = "Geode", Rarity = "Mythic", OneIn = 300000, Multiplier = 42, World = "Cave",
		Color = Color3.fromRGB(255, 120, 220), Material = Enum.Material.Foil, Particle = "Flare", Light = true },
	{ Id = "Abyss", Name = "Abyss", Rarity = "Secret", OneIn = 1800000, Multiplier = 80, World = "Cave",
		Color = Color3.fromRGB(15, 5, 30), Material = Enum.Material.ForceField, Particle = "Void", Light = true },

	-- Heaven (zone exclusive; Id Space)
	{ Id = "Comet", Name = "Halo", Rarity = "Legendary", OneIn = 30000, Multiplier = 16, World = "Space",
		Color = Color3.fromRGB(255, 230, 140), Material = Enum.Material.Foil, Particle = "Sparkle", Light = true },
	{ Id = "Quasar", Name = "Seraph", Rarity = "Mythic", OneIn = 200000, Multiplier = 35, World = "Space",
		Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.Neon, Particle = "Stars", Light = true },
	{ Id = "Supernova", Name = "Paradise", Rarity = "Mythic", OneIn = 400000, Multiplier = 50, World = "Space",
		Color = Color3.fromRGB(255, 200, 230), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Singularity", Name = "Divine", Rarity = "Secret", OneIn = 2500000, Multiplier = 100, World = "Space",
		Color = Color3.fromRGB(255, 250, 210), Material = Enum.Material.ForceField, Particle = "Stars", Light = true },
}

local byId: { [string]: StudDef } = {}
for _, def in list do
	assert(not byId[def.Id], `Duplicate stud id: {def.Id}`)
	byId[def.Id] = def
end

return {
	List = list,
	ById = byId,
}
