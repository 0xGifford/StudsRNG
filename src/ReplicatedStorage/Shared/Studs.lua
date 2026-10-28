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
