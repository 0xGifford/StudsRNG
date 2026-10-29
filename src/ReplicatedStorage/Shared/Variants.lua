--[[ 

Variants
ModuleScript
/ReplicatedStorage/Shared/Variants

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Variants any stud can roll as, Slime RNG style. Each stud × variant is
-- its own index entry (and Index tab). Multiplier scales the stud's Clacks
-- multiplier; Stats scales its Strength and Health; Scale is how big it is
-- as a follower (Big < Huge < Jumbo); Invert flips its colour.
--
-- Fuse chain (FuseCost of one size → 1 of the next): Base → Big → Huge →
-- Jumbo. Shiny and Inverted only come from rolls.
--
-- Name is saved in player data (Normal is shown as "Base"): never rename
-- one. Golden and Rainbow are retired: old saves still load and show them,
-- but they no longer roll, fuse or count towards the index.

local Types = require(script.Parent.Types)

type VariantDef = Types.VariantDef

local order = { "Normal", "Big", "Huge", "Jumbo", "Shiny", "Inverted" }

local defs: { [string]: VariantDef } = {
	Normal = { Name = "Normal", Label = "Base", OneIn = 1, Multiplier = 1, Stats = 1, Scale = 1 },
	Big = { Name = "Big", Label = "Big", OneIn = 8, Multiplier = 1.5, Stats = 1.5, Scale = 1.35 },
	Huge = { Name = "Huge", Label = "Huge", OneIn = 40, Multiplier = 2.5, Stats = 2.5, Scale = 1.8 },
	Jumbo = { Name = "Jumbo", Label = "Jumbo", OneIn = 200, Multiplier = 5, Stats = 5, Scale = 2.5 },
	Shiny = { Name = "Shiny", Label = "Shiny", OneIn = 500, Multiplier = 8, Stats = 8, Scale = 1, Effect = "Shine" },
	Inverted = { Name = "Inverted", Label = "Inverted", OneIn = 2500, Multiplier = 15, Stats = 15, Scale = 1, Effect = "Invert", Invert = true },

	-- Retired
	Golden = {
		Name = "Golden",
		OneIn = 150,
		Multiplier = 3,
		Stats = 3,
		Effect = "Gold",
		ColorOverride = Color3.fromRGB(255, 205, 70),
		MaterialOverride = Enum.Material.Foil,
		Retired = true,
	},
	Rainbow = { Name = "Rainbow", OneIn = 1500, Multiplier = 8, Stats = 8, Effect = "Rainbow", Retired = true },
}

local nextInChain: { [string]: string } = {
	Normal = "Big",
	Big = "Huge",
	Huge = "Jumbo",
}

local function label(def: VariantDef): string
	return def.Label or def.Name
end

return {
	Order = order,
	ById = defs,
	Next = nextInChain,
	label = label,
}
