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

	-- Arcade (zone exclusive)
	{ Id = "Pixel", Name = "Pixel", Rarity = "Uncommon", OneIn = 35, Multiplier = 1.8, World = "Arcade",
		Color = Color3.fromRGB(255, 120, 200), Material = Enum.Material.SmoothPlastic, Particle = "Dust" },
	{ Id = "Token", Name = "Token", Rarity = "Rare", OneIn = 200, Multiplier = 3, World = "Arcade",
		Color = Color3.fromRGB(255, 190, 60), Material = Enum.Material.Foil, Particle = "Sparkle" },
	{ Id = "Combo", Name = "Combo", Rarity = "Epic", OneIn = 1200, Multiplier = 5, World = "Arcade",
		Color = Color3.fromRGB(120, 80, 255), Material = Enum.Material.Neon, Particle = "Sparkle", Light = true },
	{ Id = "Highscore", Name = "Highscore", Rarity = "Legendary", OneIn = 8000, Multiplier = 10, World = "Arcade",
		Color = Color3.fromRGB(255, 60, 90), Material = Enum.Material.Neon, Particle = "Flare", Light = true },

	-- Studio (zone exclusive)
	{ Id = "Vinyl", Name = "Vinyl", Rarity = "Rare", OneIn = 300, Multiplier = 3.5, World = "Studio",
		Color = Color3.fromRGB(30, 30, 36), Material = Enum.Material.Glass, Particle = "Dust" },
	{ Id = "Spotlight", Name = "Spotlight", Rarity = "Epic", OneIn = 2000, Multiplier = 6, World = "Studio",
		Color = Color3.fromRGB(255, 250, 220), Material = Enum.Material.Neon, Particle = "Sparkle", Light = true },
	{ Id = "Encore", Name = "Encore", Rarity = "Legendary", OneIn = 12000, Multiplier = 12, World = "Studio",
		Color = Color3.fromRGB(255, 150, 40), Material = Enum.Material.Foil, Particle = "Flare", Light = true },
	{ Id = "Platinum", Name = "Platinum", Rarity = "Mythic", OneIn = 80000, Multiplier = 25, World = "Studio",
		Color = Color3.fromRGB(220, 230, 240), Material = Enum.Material.Foil, Particle = "Stars", Light = true },

	-- Neon City (zone exclusive)
	{ Id = "Synth", Name = "Synth", Rarity = "Epic", OneIn = 3000, Multiplier = 7, World = "Neon",
		Color = Color3.fromRGB(0, 230, 255), Material = Enum.Material.Neon, Particle = "Sparkle", Light = true },
	{ Id = "Laser", Name = "Laser", Rarity = "Legendary", OneIn = 20000, Multiplier = 14, World = "Neon",
		Color = Color3.fromRGB(255, 0, 80), Material = Enum.Material.Neon, Particle = "Embers", Light = true },
	{ Id = "Overdrive", Name = "Overdrive", Rarity = "Mythic", OneIn = 120000, Multiplier = 30, World = "Neon",
		Color = Color3.fromRGB(255, 240, 0), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Cyber", Name = "Cyber", Rarity = "Mythic", OneIn = 250000, Multiplier = 40, World = "Neon",
		Color = Color3.fromRGB(170, 0, 255), Material = Enum.Material.ForceField, Particle = "Glitch", Light = true },

	-- Space (zone exclusive)
	{ Id = "Comet", Name = "Comet", Rarity = "Legendary", OneIn = 30000, Multiplier = 16, World = "Space",
		Color = Color3.fromRGB(150, 220, 255), Material = Enum.Material.Ice, Particle = "Snow", Light = true },
	{ Id = "Quasar", Name = "Quasar", Rarity = "Mythic", OneIn = 200000, Multiplier = 35, World = "Space",
		Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.Neon, Particle = "Stars", Light = true },
	{ Id = "Supernova", Name = "Supernova", Rarity = "Mythic", OneIn = 400000, Multiplier = 50, World = "Space",
		Color = Color3.fromRGB(255, 110, 40), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Singularity", Name = "Singularity", Rarity = "Secret", OneIn = 2500000, Multiplier = 100, World = "Space",
		Color = Color3.fromRGB(10, 0, 20), Material = Enum.Material.ForceField, Particle = "Void", Light = true },
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
