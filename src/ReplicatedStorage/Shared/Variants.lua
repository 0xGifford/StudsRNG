--[[ 

Variants
ModuleScript
/ReplicatedStorage/Shared/Variants

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Variants (mutations) any stud can roll as. Each stud × variant is its own
-- index entry. Multiplier scales the stud's own multiplier.
--
-- Order is also the fuse chain: FuseCost of one variant → 1 of the next.
-- Names are saved in player data: never rename one once the game is live.

local Types = require(script.Parent.Types)

type VariantDef = Types.VariantDef

local order = { "Normal", "Shiny", "Golden", "Rainbow" }

local defs: { [string]: VariantDef } = {
	Normal = { Name = "Normal", OneIn = 1, Multiplier = 1 },
	Shiny = { Name = "Shiny", OneIn = 20, Multiplier = 1.5, Effect = "Shine" },
	Golden = {
		Name = "Golden",
		OneIn = 150,
		Multiplier = 3,
		Effect = "Gold",
		ColorOverride = Color3.fromRGB(255, 205, 70),
		MaterialOverride = Enum.Material.Foil,
	},
	Rainbow = { Name = "Rainbow", OneIn = 1500, Multiplier = 8, Effect = "Rainbow" },
}

local nextInChain: { [string]: string } = {}
for i = 1, #order - 1 do
	nextInChain[order[i]] = order[i + 1]
end

return {
	Order = order,
	ById = defs,
	Next = nextInChain,
}
