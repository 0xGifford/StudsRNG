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
-- Drop:  never rolled; only dropped by Mini Bosses and Zone Bosses
--        (Systems/Drops; World "Boss"), or Stud Pass rewards (World "Pass").
--        A boss drop's OneIn is its base odds.
--
-- Ids are saved in player data: never rename an Id once the game is live.

local Types = require(script.Parent.Types)

type StudDef = Types.StudDef

local list: { StudDef } = {
	-- Common
	{ Id = "Chalk", Name = "Chalk", Rarity = "Common", OneIn = 2, Multiplier = 1.1, World = "001",
		Color = Color3.fromRGB(235, 235, 230), Material = Enum.Material.SmoothPlastic },
	{ Id = "Pebble", Name = "Pebble", Rarity = "Common", OneIn = 3, Multiplier = 1.15, World = "001",
		Color = Color3.fromRGB(140, 140, 150), Material = Enum.Material.SmoothPlastic },
	{ Id = "Moss", Name = "Moss", Rarity = "Common", OneIn = 4, Multiplier = 1.2, World = "001",
		Color = Color3.fromRGB(110, 150, 80), Material = Enum.Material.SmoothPlastic },
	{ Id = "Sky", Name = "Sky", Rarity = "Common", OneIn = 5, Multiplier = 1.25, World = "001",
		Color = Color3.fromRGB(130, 190, 255), Material = Enum.Material.SmoothPlastic },

	-- Uncommon
	{ Id = "Mint", Name = "Mint", Rarity = "Uncommon", OneIn = 10, Multiplier = 1.4, World = "001",
		Color = Color3.fromRGB(150, 255, 200), Material = Enum.Material.SmoothPlastic },
	{ Id = "Coral", Name = "Coral", Rarity = "Uncommon", OneIn = 15, Multiplier = 1.5, World = "001",
		Color = Color3.fromRGB(255, 130, 110), Material = Enum.Material.SmoothPlastic },
	{ Id = "Lilac", Name = "Lilac", Rarity = "Uncommon", OneIn = 25, Multiplier = 1.6, World = "001",
		Color = Color3.fromRGB(200, 160, 255), Material = Enum.Material.SmoothPlastic, Particle = "Dust" },

	-- Rare
	{ Id = "Ember", Name = "Ember", Rarity = "Rare", OneIn = 50, Multiplier = 2, World = "001",
		Color = Color3.fromRGB(255, 90, 30), Material = Enum.Material.Neon, Particle = "Embers" },
	{ Id = "Tide", Name = "Tide", Rarity = "Rare", OneIn = 100, Multiplier = 2.3, World = "001",
		Color = Color3.fromRGB(40, 140, 255), Material = Enum.Material.Glass, Particle = "Bubbles" },
	{ Id = "Spruce", Name = "Spruce", Rarity = "Rare", OneIn = 150, Multiplier = 2.6, World = "001",
		Color = Color3.fromRGB(30, 110, 60), Material = Enum.Material.SmoothPlastic, Particle = "Leaves" },

	-- Epic
	{ Id = "Plasma", Name = "Plasma", Rarity = "Epic", OneIn = 400, Multiplier = 3.5, World = "001",
		Color = Color3.fromRGB(255, 60, 220), Material = Enum.Material.Neon, Particle = "Sparkle", Light = true },
	{ Id = "Frostbite", Name = "Frostbite", Rarity = "Epic", OneIn = 750, Multiplier = 4, World = "001",
		Color = Color3.fromRGB(190, 240, 255), Material = Enum.Material.Glass, Particle = "Snow", Light = true },

	-- Legendary
	{ Id = "Solar", Name = "Solar", Rarity = "Legendary", OneIn = 2500, Multiplier = 6, World = "001",
		Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Nebula", Name = "Nebula", Rarity = "Legendary", OneIn = 5000, Multiplier = 8, World = "001",
		Color = Color3.fromRGB(90, 40, 200), Material = Enum.Material.ForceField, Particle = "Stars", Light = true },

	-- Mythic
	{ Id = "Void", Name = "Void", Rarity = "Mythic", OneIn = 25000, Multiplier = 15, World = "001",
		Color = Color3.fromRGB(15, 10, 25), Material = Enum.Material.Neon, Particle = "Void", Light = true },
	{ Id = "Prism", Name = "Prism", Rarity = "Mythic", OneIn = 50000, Multiplier = 20, World = "001",
		Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.Glass, Particle = "Sparkle", Light = true },

	-- Secret
	{ Id = "Glitch", Name = "???", Rarity = "Secret", OneIn = 1000000, Multiplier = 50, World = "001",
		Color = Color3.fromRGB(0, 255, 120), Material = Enum.Material.Neon, Particle = "Glitch", Light = true },

	-- City (zone exclusive)
	{ Id = "Pixel", Name = "Seashell", Rarity = "Uncommon", OneIn = 35, Multiplier = 1.8, World = "002",
		Color = Color3.fromRGB(255, 190, 200), Material = Enum.Material.SmoothPlastic, Particle = "Dust" },
	{ Id = "Token", Name = "Sandcastle", Rarity = "Rare", OneIn = 200, Multiplier = 3, World = "002",
		Color = Color3.fromRGB(255, 190, 60), Material = Enum.Material.Foil, Particle = "Sparkle" },
	{ Id = "Combo", Name = "Lagoon", Rarity = "Epic", OneIn = 1200, Multiplier = 5, World = "002",
		Color = Color3.fromRGB(40, 220, 210), Material = Enum.Material.Neon, Particle = "Sparkle", Light = true },
	{ Id = "Highscore", Name = "Sunset", Rarity = "Legendary", OneIn = 8000, Multiplier = 10, World = "002",
		Color = Color3.fromRGB(255, 120, 60), Material = Enum.Material.Neon, Particle = "Flare", Light = true },

	-- Desert (zone exclusive)
	{ Id = "Vinyl", Name = "Snowflake", Rarity = "Rare", OneIn = 300, Multiplier = 3.5, World = "003",
		Color = Color3.fromRGB(235, 245, 255), Material = Enum.Material.Glass, Particle = "Snow" },
	{ Id = "Spotlight", Name = "Glacier", Rarity = "Epic", OneIn = 2000, Multiplier = 6, World = "003",
		Color = Color3.fromRGB(140, 210, 255), Material = Enum.Material.Ice, Particle = "Sparkle", Light = true },
	{ Id = "Encore", Name = "Aurora", Rarity = "Legendary", OneIn = 12000, Multiplier = 12, World = "003",
		Color = Color3.fromRGB(90, 255, 170), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Platinum", Name = "Permafrost", Rarity = "Mythic", OneIn = 80000, Multiplier = 25, World = "003",
		Color = Color3.fromRGB(220, 230, 240), Material = Enum.Material.Foil, Particle = "Stars", Light = true },

	-- Orchard (zone exclusive)
	{ Id = "Synth", Name = "Magma", Rarity = "Epic", OneIn = 3000, Multiplier = 7, World = "004",
		Color = Color3.fromRGB(255, 120, 20), Material = Enum.Material.Neon, Particle = "Embers", Light = true },
	{ Id = "Laser", Name = "Obsidian", Rarity = "Legendary", OneIn = 20000, Multiplier = 14, World = "004",
		Color = Color3.fromRGB(40, 20, 50), Material = Enum.Material.Glass, Particle = "Embers", Light = true },
	{ Id = "Overdrive", Name = "Eruption", Rarity = "Mythic", OneIn = 120000, Multiplier = 30, World = "004",
		Color = Color3.fromRGB(255, 70, 20), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Cyber", Name = "Inferno", Rarity = "Mythic", OneIn = 250000, Multiplier = 40, World = "004",
		Color = Color3.fromRGB(255, 40, 0), Material = Enum.Material.ForceField, Particle = "Embers", Light = true },

	-- Frostlands (zone exclusive)
	{ Id = "Coconut", Name = "Coconut", Rarity = "Rare", OneIn = 500, Multiplier = 4, World = "005",
		Color = Color3.fromRGB(130, 85, 50), Material = Enum.Material.Wood, Particle = "Dust" },
	{ Id = "Hibiscus", Name = "Hibiscus", Rarity = "Epic", OneIn = 5000, Multiplier = 9, World = "005",
		Color = Color3.fromRGB(255, 70, 120), Material = Enum.Material.SmoothPlastic, Particle = "Sparkle", Light = true },
	{ Id = "Tsunami", Name = "Tsunami", Rarity = "Legendary", OneIn = 25000, Multiplier = 15, World = "005",
		Color = Color3.fromRGB(30, 140, 255), Material = Enum.Material.Glass, Particle = "Flare", Light = true },
	{ Id = "Kraken", Name = "Kraken", Rarity = "Mythic", OneIn = 180000, Multiplier = 33, World = "005",
		Color = Color3.fromRGB(120, 40, 160), Material = Enum.Material.Neon, Particle = "Void", Light = true },

	-- Fountain Springs (zone exclusive)
	{ Id = "Amethyst", Name = "Amethyst", Rarity = "Epic", OneIn = 8000, Multiplier = 11, World = "006",
		Color = Color3.fromRGB(170, 90, 255), Material = Enum.Material.Glass, Particle = "Sparkle", Light = true },
	{ Id = "Glowshroom", Name = "Glowshroom", Rarity = "Legendary", OneIn = 40000, Multiplier = 18, World = "006",
		Color = Color3.fromRGB(60, 255, 200), Material = Enum.Material.Neon, Particle = "Stars", Light = true },
	{ Id = "Geode", Name = "Geode", Rarity = "Mythic", OneIn = 300000, Multiplier = 42, World = "006",
		Color = Color3.fromRGB(255, 120, 220), Material = Enum.Material.Foil, Particle = "Flare", Light = true },
	{ Id = "Abyss", Name = "Abyss", Rarity = "Secret", OneIn = 1800000, Multiplier = 80, World = "006",
		Color = Color3.fromRGB(15, 5, 30), Material = Enum.Material.ForceField, Particle = "Void", Light = true },

	-- Village (zone exclusive)
	{ Id = "Comet", Name = "Halo", Rarity = "Legendary", OneIn = 30000, Multiplier = 16, World = "007",
		Color = Color3.fromRGB(255, 230, 140), Material = Enum.Material.Foil, Particle = "Sparkle", Light = true },
	{ Id = "Quasar", Name = "Seraph", Rarity = "Mythic", OneIn = 200000, Multiplier = 35, World = "007",
		Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.Neon, Particle = "Stars", Light = true },
	{ Id = "Supernova", Name = "Paradise", Rarity = "Mythic", OneIn = 400000, Multiplier = 50, World = "007",
		Color = Color3.fromRGB(255, 200, 230), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Singularity", Name = "Divine", Rarity = "Secret", OneIn = 2500000, Multiplier = 100, World = "007",
		Color = Color3.fromRGB(255, 250, 210), Material = Enum.Material.ForceField, Particle = "Stars", Light = true },

	-- Zones 8-34 (zone exclusive): three a zone, a Secret every fourth.
	-- Generated by tools/gen_zone_studs.py (balance: tools/simulate.py).
	-- Zone 8
	{ Id = "Z08Lantern", Name = "Lantern", Rarity = "Epic", OneIn = 20_000, Multiplier = 14.6, World = "008",
		Color = Color3.fromRGB(255, 195, 114), Material = Enum.Material.Glass, Particle = "Sparkle" },
	{ Id = "Z08Beacon", Name = "Beacon", Rarity = "Legendary", OneIn = 140_000, Multiplier = 26, World = "008",
		Color = Color3.fromRGB(255, 244, 89), Material = Enum.Material.Foil, Particle = "Stars", Light = true },
	{ Id = "Z08Lighthouse", Name = "Lighthouse", Rarity = "Mythic", OneIn = 900_000, Multiplier = 46, World = "008",
		Color = Color3.fromRGB(198, 255, 63), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	-- Zone 9
	{ Id = "Z09Ripple", Name = "Ripple", Rarity = "Epic", OneIn = 25_000, Multiplier = 15.6, World = "009",
		Color = Color3.fromRGB(199, 255, 114), Material = Enum.Material.Neon, Particle = "Shine" },
	{ Id = "Z09Undertow", Name = "Undertow", Rarity = "Legendary", OneIn = 170_000, Multiplier = 28, World = "009",
		Color = Color3.fromRGB(129, 255, 89), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z09Maelstrom", Name = "Maelstrom", Rarity = "Mythic", OneIn = 1_100_000, Multiplier = 49, World = "009",
		Color = Color3.fromRGB(63, 255, 86), Material = Enum.Material.ForceField, Particle = "Glitch", Light = true },
	-- Zone 10
	{ Id = "Z10Cinder", Name = "Cinder", Rarity = "Epic", OneIn = 31_000, Multiplier = 16.7, World = "010",
		Color = Color3.fromRGB(114, 255, 145), Material = Enum.Material.Glass, Particle = "Sparkle" },
	{ Id = "Z10Magma", Name = "Magma", Rarity = "Legendary", OneIn = 220_000, Multiplier = 30, World = "010",
		Color = Color3.fromRGB(89, 255, 185), Material = Enum.Material.Foil, Particle = "Stars", Light = true },
	{ Id = "Z10Inferno", Name = "Inferno", Rarity = "Mythic", OneIn = 1_400_000, Multiplier = 52, World = "010",
		Color = Color3.fromRGB(63, 255, 243), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z10Dragonheart", Name = "Dragonheart", Rarity = "Secret", OneIn = 18_000_000, Multiplier = 113, World = "010",
		Color = Color3.fromRGB(38, 189, 255), Material = Enum.Material.ForceField, Particle = "Void", Light = true },
	-- Zone 11
	{ Id = "Z11Frost", Name = "Frost", Rarity = "Epic", OneIn = 38_000, Multiplier = 17.7, World = "011",
		Color = Color3.fromRGB(114, 249, 255), Material = Enum.Material.Neon, Particle = "Shine" },
	{ Id = "Z11Glacier", Name = "Glacier", Rarity = "Legendary", OneIn = 270_000, Multiplier = 32, World = "011",
		Color = Color3.fromRGB(89, 188, 255), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z11Avalanche", Name = "Avalanche", Rarity = "Mythic", OneIn = 1_700_000, Multiplier = 55, World = "011",
		Color = Color3.fromRGB(63, 109, 255), Material = Enum.Material.ForceField, Particle = "Glitch", Light = true },
	-- Zone 12
	{ Id = "Z12Thistle", Name = "Thistle", Rarity = "Epic", OneIn = 47_000, Multiplier = 18.9, World = "012",
		Color = Color3.fromRGB(114, 133, 255), Material = Enum.Material.Glass, Particle = "Sparkle" },
	{ Id = "Z12Briar", Name = "Briar", Rarity = "Legendary", OneIn = 330_000, Multiplier = 34, World = "012",
		Color = Color3.fromRGB(126, 89, 255), Material = Enum.Material.Foil, Particle = "Stars", Light = true },
	{ Id = "Z12Thornwood", Name = "Thornwood", Rarity = "Mythic", OneIn = 2_100_000, Multiplier = 59, World = "012",
		Color = Color3.fromRGB(175, 63, 255), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	-- Zone 13
	{ Id = "Z13Gear", Name = "Gear", Rarity = "Epic", OneIn = 59_000, Multiplier = 20.2, World = "013",
		Color = Color3.fromRGB(210, 114, 255), Material = Enum.Material.Neon, Particle = "Shine" },
	{ Id = "Z13Clockwork", Name = "Clockwork", Rarity = "Legendary", OneIn = 410_000, Multiplier = 36, World = "013",
		Color = Color3.fromRGB(255, 89, 247), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z13Automaton", Name = "Automaton", Rarity = "Mythic", OneIn = 2_600_000, Multiplier = 63, World = "013",
		Color = Color3.fromRGB(255, 63, 177), Material = Enum.Material.ForceField, Particle = "Glitch", Light = true },
	-- Zone 14
	{ Id = "Z14Petal", Name = "Petal", Rarity = "Epic", OneIn = 73_000, Multiplier = 21.6, World = "014",
		Color = Color3.fromRGB(255, 114, 183), Material = Enum.Material.Glass, Particle = "Sparkle" },
	{ Id = "Z14Bloom", Name = "Bloom", Rarity = "Legendary", OneIn = 510_000, Multiplier = 39, World = "014",
		Color = Color3.fromRGB(255, 89, 111), Material = Enum.Material.Foil, Particle = "Stars", Light = true },
	{ Id = "Z14Everbloom", Name = "Everbloom", Rarity = "Mythic", OneIn = 3_300_000, Multiplier = 68, World = "014",
		Color = Color3.fromRGB(255, 107, 63), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z14Gaia", Name = "Gaia", Rarity = "Secret", OneIn = 44_000_000, Multiplier = 147, World = "014",
		Color = Color3.fromRGB(255, 165, 38), Material = Enum.Material.ForceField, Particle = "Void", Light = true },
	-- Zone 15
	{ Id = "Z15Spark", Name = "Spark", Rarity = "Epic", OneIn = 90_000, Multiplier = 23, World = "015",
		Color = Color3.fromRGB(255, 161, 114), Material = Enum.Material.Neon, Particle = "Shine" },
	{ Id = "Z15Volt", Name = "Volt", Rarity = "Legendary", OneIn = 630_000, Multiplier = 41, World = "015",
		Color = Color3.fromRGB(255, 203, 89), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z15Tempest", Name = "Tempest", Rarity = "Mythic", OneIn = 4_100_000, Multiplier = 72, World = "015",
		Color = Color3.fromRGB(245, 255, 63), Material = Enum.Material.ForceField, Particle = "Glitch", Light = true },
	-- Zone 16
	{ Id = "Z16Quartz", Name = "Quartz", Rarity = "Epic", OneIn = 110_000, Multiplier = 24, World = "016",
		Color = Color3.fromRGB(233, 255, 114), Material = Enum.Material.Glass, Particle = "Sparkle" },
	{ Id = "Z16Obsidian", Name = "Obsidian", Rarity = "Legendary", OneIn = 780_000, Multiplier = 44, World = "016",
		Color = Color3.fromRGB(170, 255, 89), Material = Enum.Material.Foil, Particle = "Stars", Light = true },
	{ Id = "Z16Monolith", Name = "Monolith", Rarity = "Mythic", OneIn = 5_000_000, Multiplier = 77, World = "016",
		Color = Color3.fromRGB(88, 255, 63), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	-- Zone 17
	{ Id = "Z17Dune", Name = "Dune", Rarity = "Epic", OneIn = 140_000, Multiplier = 26, World = "017",
		Color = Color3.fromRGB(118, 255, 114), Material = Enum.Material.Neon, Particle = "Shine" },
	{ Id = "Z17Mirage", Name = "Mirage", Rarity = "Legendary", OneIn = 970_000, Multiplier = 47, World = "017",
		Color = Color3.fromRGB(89, 255, 144), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z17Sandstorm", Name = "Sandstorm", Rarity = "Mythic", OneIn = 6_200_000, Multiplier = 82, World = "017",
		Color = Color3.fromRGB(63, 255, 196), Material = Enum.Material.ForceField, Particle = "Glitch", Light = true },
	-- Zone 18
	{ Id = "Z18Fern", Name = "Fern", Rarity = "Epic", OneIn = 170_000, Multiplier = 28, World = "018",
		Color = Color3.fromRGB(114, 255, 226), Material = Enum.Material.Glass, Particle = "Sparkle" },
	{ Id = "Z18Canopy", Name = "Canopy", Rarity = "Legendary", OneIn = 1_200_000, Multiplier = 50, World = "018",
		Color = Color3.fromRGB(89, 229, 255), Material = Enum.Material.Foil, Particle = "Stars", Light = true },
	{ Id = "Z18Worldtree", Name = "Worldtree", Rarity = "Mythic", OneIn = 7_700_000, Multiplier = 87, World = "018",
		Color = Color3.fromRGB(63, 156, 255), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z18Yggdrasil", Name = "Yggdrasil", Rarity = "Secret", OneIn = 100_000_000, Multiplier = 188, World = "018",
		Color = Color3.fromRGB(38, 65, 255), Material = Enum.Material.ForceField, Particle = "Void", Light = true },
	-- Zone 19
	{ Id = "Z19Ink", Name = "Ink", Rarity = "Epic", OneIn = 210_000, Multiplier = 30, World = "019",
		Color = Color3.fromRGB(114, 168, 255), Material = Enum.Material.Neon, Particle = "Shine" },
	{ Id = "Z19Shadow", Name = "Shadow", Rarity = "Legendary", OneIn = 1_500_000, Multiplier = 53, World = "019",
		Color = Color3.fromRGB(89, 92, 255), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z19Eclipse", Name = "Eclipse", Rarity = "Mythic", OneIn = 9_600_000, Multiplier = 93, World = "019",
		Color = Color3.fromRGB(128, 63, 255), Material = Enum.Material.ForceField, Particle = "Glitch", Light = true },
	-- Zone 20
	{ Id = "Z20Copper", Name = "Copper", Rarity = "Epic", OneIn = 260_000, Multiplier = 32, World = "020",
		Color = Color3.fromRGB(176, 114, 255), Material = Enum.Material.Glass, Particle = "Sparkle" },
	{ Id = "Z20Bronze", Name = "Bronze", Rarity = "Legendary", OneIn = 1_900_000, Multiplier = 57, World = "020",
		Color = Color3.fromRGB(221, 89, 255), Material = Enum.Material.Foil, Particle = "Stars", Light = true },
	{ Id = "Z20Colossus", Name = "Colossus", Rarity = "Mythic", OneIn = 12_000_000, Multiplier = 100, World = "020",
		Color = Color3.fromRGB(255, 63, 224), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	-- Zone 21
	{ Id = "Z21Cloud", Name = "Cloud", Rarity = "Epic", OneIn = 330_000, Multiplier = 34, World = "021",
		Color = Color3.fromRGB(255, 114, 218), Material = Enum.Material.Neon, Particle = "Shine" },
	{ Id = "Z21Zephyr", Name = "Zephyr", Rarity = "Legendary", OneIn = 2_300_000, Multiplier = 61, World = "021",
		Color = Color3.fromRGB(255, 89, 151), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z21Skyward", Name = "Skyward", Rarity = "Mythic", OneIn = 15_000_000, Multiplier = 107, World = "021",
		Color = Color3.fromRGB(255, 63, 67), Material = Enum.Material.ForceField, Particle = "Glitch", Light = true },
	-- Zone 22
	{ Id = "Z22Shell", Name = "Shell", Rarity = "Epic", OneIn = 410_000, Multiplier = 36, World = "022",
		Color = Color3.fromRGB(255, 126, 114), Material = Enum.Material.Glass, Particle = "Sparkle" },
	{ Id = "Z22Pearl", Name = "Pearl", Rarity = "Legendary", OneIn = 2_800_000, Multiplier = 64, World = "022",
		Color = Color3.fromRGB(255, 162, 89), Material = Enum.Material.Foil, Particle = "Stars", Light = true },
	{ Id = "Z22Leviathan", Name = "Leviathan", Rarity = "Mythic", OneIn = 18_000_000, Multiplier = 113, World = "022",
		Color = Color3.fromRGB(255, 217, 63), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z22AbyssalKing", Name = "Abyssal King", Rarity = "Secret", OneIn = 240_000_000, Multiplier = 245, World = "022",
		Color = Color3.fromRGB(219, 255, 38), Material = Enum.Material.ForceField, Particle = "Void", Light = true },
	-- Zone 23
	{ Id = "Z23Rune", Name = "Rune", Rarity = "Epic", OneIn = 500_000, Multiplier = 38, World = "023",
		Color = Color3.fromRGB(255, 241, 114), Material = Enum.Material.Neon, Particle = "Shine" },
	{ Id = "Z23Sigil", Name = "Sigil", Rarity = "Legendary", OneIn = 3_500_000, Multiplier = 69, World = "023",
		Color = Color3.fromRGB(210, 255, 89), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z23Arcana", Name = "Arcana", Rarity = "Mythic", OneIn = 23_000_000, Multiplier = 121, World = "023",
		Color = Color3.fromRGB(135, 255, 63), Material = Enum.Material.ForceField, Particle = "Glitch", Light = true },
	-- Zone 24
	{ Id = "Z24EmberFox", Name = "Ember Fox", Rarity = "Epic", OneIn = 620_000, Multiplier = 41, World = "024",
		Color = Color3.fromRGB(152, 255, 114), Material = Enum.Material.Glass, Particle = "Sparkle" },
	{ Id = "Z24Phoenix", Name = "Phoenix", Rarity = "Legendary", OneIn = 4_400_000, Multiplier = 74, World = "024",
		Color = Color3.fromRGB(89, 255, 103), Material = Enum.Material.Foil, Particle = "Stars", Light = true },
	{ Id = "Z24Firebird", Name = "Firebird", Rarity = "Mythic", OneIn = 28_000_000, Multiplier = 129, World = "024",
		Color = Color3.fromRGB(63, 255, 149), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	-- Zone 25
	{ Id = "Z25Orbit", Name = "Orbit", Rarity = "Epic", OneIn = 770_000, Multiplier = 44, World = "025",
		Color = Color3.fromRGB(114, 255, 191), Material = Enum.Material.Neon, Particle = "Shine" },
	{ Id = "Z25Pulsar", Name = "Pulsar", Rarity = "Legendary", OneIn = 5_400_000, Multiplier = 78, World = "025",
		Color = Color3.fromRGB(89, 255, 240), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z25Galaxy", Name = "Galaxy", Rarity = "Mythic", OneIn = 35_000_000, Multiplier = 137, World = "025",
		Color = Color3.fromRGB(63, 203, 255), Material = Enum.Material.ForceField, Particle = "Glitch", Light = true },
	-- Zone 26
	{ Id = "Z26Candy", Name = "Candy", Rarity = "Epic", OneIn = 960_000, Multiplier = 47, World = "026",
		Color = Color3.fromRGB(114, 202, 255), Material = Enum.Material.Glass, Particle = "Sparkle" },
	{ Id = "Z26Sugarstorm", Name = "Sugarstorm", Rarity = "Legendary", OneIn = 6_700_000, Multiplier = 84, World = "026",
		Color = Color3.fromRGB(89, 133, 255), Material = Enum.Material.Foil, Particle = "Stars", Light = true },
	{ Id = "Z26GumdropKing", Name = "Gumdrop King", Rarity = "Mythic", OneIn = 43_000_000, Multiplier = 146, World = "026",
		Color = Color3.fromRGB(81, 63, 255), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z26Wonderland", Name = "Wonderland", Rarity = "Secret", OneIn = 580_000_000, Multiplier = 319, World = "026",
		Color = Color3.fromRGB(136, 38, 255), Material = Enum.Material.ForceField, Particle = "Void", Light = true },
	-- Zone 27
	{ Id = "Z27Echo", Name = "Echo", Rarity = "Epic", OneIn = 1_200_000, Multiplier = 50, World = "027",
		Color = Color3.fromRGB(141, 114, 255), Material = Enum.Material.Neon, Particle = "Shine" },
	{ Id = "Z27Resonance", Name = "Resonance", Rarity = "Legendary", OneIn = 8_300_000, Multiplier = 89, World = "027",
		Color = Color3.fromRGB(181, 89, 255), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z27Harmony", Name = "Harmony", Rarity = "Mythic", OneIn = 54_000_000, Multiplier = 157, World = "027",
		Color = Color3.fromRGB(238, 63, 255), Material = Enum.Material.ForceField, Particle = "Glitch", Light = true },
	-- Zone 28
	{ Id = "Z28Neon", Name = "Neon", Rarity = "Epic", OneIn = 1_500_000, Multiplier = 53, World = "028",
		Color = Color3.fromRGB(255, 114, 252), Material = Enum.Material.Glass, Particle = "Sparkle" },
	{ Id = "Z28Hologram", Name = "Hologram", Rarity = "Legendary", OneIn = 10_000_000, Multiplier = 94, World = "028",
		Color = Color3.fromRGB(255, 89, 192), Material = Enum.Material.Foil, Particle = "Stars", Light = true },
	{ Id = "Z28Mainframe", Name = "Mainframe", Rarity = "Mythic", OneIn = 66_000_000, Multiplier = 166, World = "028",
		Color = Color3.fromRGB(255, 63, 114), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	-- Zone 29
	{ Id = "Z29Moonlit", Name = "Moonlit", Rarity = "Epic", OneIn = 1_800_000, Multiplier = 56, World = "029",
		Color = Color3.fromRGB(255, 114, 137), Material = Enum.Material.Neon, Particle = "Shine" },
	{ Id = "Z29Lunar", Name = "Lunar", Rarity = "Legendary", OneIn = 13_000_000, Multiplier = 102, World = "029",
		Color = Color3.fromRGB(255, 122, 89), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z29Nightfall", Name = "Nightfall", Rarity = "Mythic", OneIn = 82_000_000, Multiplier = 178, World = "029",
		Color = Color3.fromRGB(255, 170, 63), Material = Enum.Material.ForceField, Particle = "Glitch", Light = true },
	-- Zone 30
	{ Id = "Z30Crystal", Name = "Crystal", Rarity = "Epic", OneIn = 2_300_000, Multiplier = 61, World = "030",
		Color = Color3.fromRGB(255, 207, 114), Material = Enum.Material.Glass, Particle = "Sparkle" },
	{ Id = "Z30Prismatic", Name = "Prismatic", Rarity = "Legendary", OneIn = 16_000_000, Multiplier = 109, World = "030",
		Color = Color3.fromRGB(251, 255, 89), Material = Enum.Material.Foil, Particle = "Stars", Light = true },
	{ Id = "Z30Kaleidoscope", Name = "Kaleidoscope", Rarity = "Mythic", OneIn = 100_000_000, Multiplier = 188, World = "030",
		Color = Color3.fromRGB(182, 255, 63), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z30Infinity", Name = "Infinity", Rarity = "Secret", OneIn = 1_400_000_000, Multiplier = 416, World = "030",
		Color = Color3.fromRGB(94, 255, 38), Material = Enum.Material.ForceField, Particle = "Void", Light = true },
	-- Zone 31
	{ Id = "Z31Storm", Name = "Storm", Rarity = "Epic", OneIn = 2_800_000, Multiplier = 64, World = "031",
		Color = Color3.fromRGB(187, 255, 114), Material = Enum.Material.Neon, Particle = "Shine" },
	{ Id = "Z31Thunderhead", Name = "Thunderhead", Rarity = "Legendary", OneIn = 20_000_000, Multiplier = 116, World = "031",
		Color = Color3.fromRGB(115, 255, 89), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z31Cyclone", Name = "Cyclone", Rarity = "Mythic", OneIn = 130_000_000, Multiplier = 204, World = "031",
		Color = Color3.fromRGB(63, 255, 102), Material = Enum.Material.ForceField, Particle = "Glitch", Light = true },
	-- Zone 32
	{ Id = "Z32Aurora", Name = "Aurora", Rarity = "Epic", OneIn = 3_500_000, Multiplier = 69, World = "032",
		Color = Color3.fromRGB(114, 255, 157), Material = Enum.Material.Glass, Particle = "Sparkle" },
	{ Id = "Z32Borealis", Name = "Borealis", Rarity = "Legendary", OneIn = 24_000_000, Multiplier = 123, World = "032",
		Color = Color3.fromRGB(89, 255, 199), Material = Enum.Material.Foil, Particle = "Stars", Light = true },
	{ Id = "Z32Celestial", Name = "Celestial", Rarity = "Mythic", OneIn = 160_000_000, Multiplier = 217, World = "032",
		Color = Color3.fromRGB(63, 250, 255), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	-- Zone 33
	{ Id = "Z33Omen", Name = "Omen", Rarity = "Epic", OneIn = 4_300_000, Multiplier = 73, World = "033",
		Color = Color3.fromRGB(114, 237, 255), Material = Enum.Material.Neon, Particle = "Shine" },
	{ Id = "Z33Fate", Name = "Fate", Rarity = "Legendary", OneIn = 30_000_000, Multiplier = 131, World = "033",
		Color = Color3.fromRGB(89, 174, 255), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z33Destiny", Name = "Destiny", Rarity = "Mythic", OneIn = 190_000_000, Multiplier = 228, World = "033",
		Color = Color3.fromRGB(63, 93, 255), Material = Enum.Material.ForceField, Particle = "Glitch", Light = true },
	-- Zone 34
	{ Id = "Z34Crown", Name = "Crown", Rarity = "Epic", OneIn = 5_400_000, Multiplier = 78, World = "034",
		Color = Color3.fromRGB(114, 122, 255), Material = Enum.Material.Glass, Particle = "Sparkle" },
	{ Id = "Z34Sovereign", Name = "Sovereign", Rarity = "Legendary", OneIn = 38_000_000, Multiplier = 141, World = "034",
		Color = Color3.fromRGB(140, 89, 255), Material = Enum.Material.Foil, Particle = "Stars", Light = true },
	{ Id = "Z34Eternity", Name = "Eternity", Rarity = "Mythic", OneIn = 240_000_000, Multiplier = 245, World = "034",
		Color = Color3.fromRGB(191, 63, 255), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
	{ Id = "Z34Genesis", Name = "Genesis", Rarity = "Secret", OneIn = 3_200_000_000, Multiplier = 533, World = "034",
		Color = Color3.fromRGB(255, 38, 248), Material = Enum.Material.ForceField, Particle = "Void", Light = true },

	-- Boss drops (never rolled: Systems/Drops)
	{ Id = "BossFang", Name = "Fang", Rarity = "Rare", OneIn = 300, Multiplier = 3, World = "Boss", Drop = true,
		Color = Color3.fromRGB(240, 235, 220), Material = Enum.Material.SmoothPlastic, Particle = "Dust" },
	{ Id = "BossCrown", Name = "Crown", Rarity = "Epic", OneIn = 2500, Multiplier = 7, World = "Boss", Drop = true,
		Color = Color3.fromRGB(255, 200, 50), Material = Enum.Material.Foil, Particle = "Sparkle", Light = true },
	{ Id = "BossWarlord", Name = "Warlord", Rarity = "Legendary", OneIn = 20000, Multiplier = 16, World = "Boss", Drop = true,
		Color = Color3.fromRGB(200, 30, 40), Material = Enum.Material.Neon, Particle = "Embers", Light = true },
	{ Id = "BossTyrant", Name = "Tyrant", Rarity = "Mythic", OneIn = 150000, Multiplier = 38, World = "Boss", Drop = true,
		Color = Color3.fromRGB(60, 0, 80), Material = Enum.Material.ForceField, Particle = "Void", Light = true },
	-- Stud Pass exclusives (never rolled or dropped: Shared/StudPass)
	{ Id = "PassTicket", Name = "Ticket", Rarity = "Epic", OneIn = 5000, Multiplier = 9, World = "Pass", Drop = true,
		Color = Color3.fromRGB(80, 200, 255), Material = Enum.Material.Neon, Particle = "Sparkle", Light = true },
	{ Id = "PassChampion", Name = "Champion", Rarity = "Legendary", OneIn = 40000, Multiplier = 20, World = "Pass", Drop = true,
		Color = Color3.fromRGB(255, 215, 80), Material = Enum.Material.Foil, Particle = "Flare", Light = true },
	{ Id = "BossOverlord", Name = "Overlord", Rarity = "Secret", OneIn = 1500000, Multiplier = 95, World = "Boss", Drop = true,
		Color = Color3.fromRGB(255, 60, 30), Material = Enum.Material.Neon, Particle = "Flare", Light = true },
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
