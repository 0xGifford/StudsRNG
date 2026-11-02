--[[

Upgrades
ModuleScript
/ReplicatedStorage/Shared/Upgrades

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The upgrade tree. Bought with Clacks; levels are permanent (a rebirth keeps
-- them), so the tree is where Clacks go before each rebirth.
--
-- Q/R: axial hex position (pointy-top). (0, 0) is the centre; the six
-- neighbours of (q, r) are (q±1, r), (q, r±1), (q+1, r-1) and (q-1, r+1).
-- Requires: every listed node needs level 1+ before this one can be bought.
-- Stat: which RollLogic.computeStats input the levels add to; each level
-- adds PerLevel.
--
-- Ids are saved in player data: never rename an Id once the game is live.

export type UpgradeDef = {
	Id: string,
	Name: string,
	Icon: string, -- emoji shown on the node
	Description: string,
	Stat: string,
	PerLevel: number,
	MaxLevel: number,
	BaseCost: number,
	CostGrowth: number,
	Q: number,
	R: number,
	Requires: { string },
	Format: string, -- "Percent" | "Flat" | "Unlock"
	Suffix: string?, -- unit after the value ("luck", "slot", ...)
}

local list: { UpgradeDef } = {
	-- Centre
	{ Id = "AutoRoll", Name = "Auto Roll", Icon = "🤖", Description = "Unlocks the Auto button.",
		Stat = "AutoRoll", PerLevel = 1, MaxLevel = 1, BaseCost = 1_000, CostGrowth = 1,
		Q = 0, R = 0, Requires = {}, Format = "Unlock" },

	-- East: Clacks
	{ Id = "Clacks1", Name = "Clack Boost I", Icon = "💰", Description = "More Clacks from every key.",
		Stat = "ClacksPct", PerLevel = 0.1, MaxLevel = 5, BaseCost = 2_000, CostGrowth = 1.6,
		Q = 1, R = 0, Requires = { "AutoRoll" }, Format = "Percent", Suffix = "Clacks" },
	{ Id = "Clacks2", Name = "Clack Boost II", Icon = "💰", Description = "Even more Clacks from every key.",
		Stat = "ClacksPct", PerLevel = 0.2, MaxLevel = 5, BaseCost = 60_000, CostGrowth = 1.7,
		Q = 2, R = 0, Requires = { "Clacks1" }, Format = "Percent", Suffix = "Clacks" },
	{ Id = "Clacks3", Name = "Clack Boost III", Icon = "💰", Description = "Big Clack multiplier.",
		Stat = "ClacksPct", PerLevel = 0.4, MaxLevel = 5, BaseCost = 2_500_000, CostGrowth = 1.8,
		Q = 3, R = 0, Requires = { "Clacks2" }, Format = "Percent", Suffix = "Clacks" },
	{ Id = "Clacks4", Name = "Clack Boost IV", Icon = "💎", Description = "Huge Clack multiplier.",
		Stat = "ClacksPct", PerLevel = 1, MaxLevel = 3, BaseCost = 80_000_000, CostGrowth = 2.5,
		Q = 4, R = 0, Requires = { "Clacks3" }, Format = "Percent", Suffix = "Clacks" },
	{ Id = "LuckyKeys", Name = "Lucky Keys", Icon = "⌨️", Description = "Chance for a key press to pay double.",
		Stat = "CritChance", PerLevel = 0.03, MaxLevel = 5, BaseCost = 25_000, CostGrowth = 1.9,
		Q = 2, R = -1, Requires = { "Clacks1" }, Format = "Percent", Suffix = "chance" },

	-- West: Luck
	{ Id = "Luck1", Name = "Luck I", Icon = "🍀", Description = "Better odds on every roll.",
		Stat = "LuckPct", PerLevel = 0.05, MaxLevel = 5, BaseCost = 3_000, CostGrowth = 1.6,
		Q = -1, R = 0, Requires = { "AutoRoll" }, Format = "Percent", Suffix = "luck" },
	{ Id = "Luck2", Name = "Luck II", Icon = "🍀", Description = "Even better odds.",
		Stat = "LuckPct", PerLevel = 0.1, MaxLevel = 5, BaseCost = 90_000, CostGrowth = 1.7,
		Q = -2, R = 0, Requires = { "Luck1" }, Format = "Percent", Suffix = "luck" },
	{ Id = "Luck3", Name = "Luck III", Icon = "🍀", Description = "Much better odds.",
		Stat = "LuckPct", PerLevel = 0.2, MaxLevel = 5, BaseCost = 3_500_000, CostGrowth = 1.8,
		Q = -3, R = 0, Requires = { "Luck2" }, Format = "Percent", Suffix = "luck" },
	{ Id = "Luck4", Name = "Luck IV", Icon = "🌟", Description = "Fortune favours the clacky.",
		Stat = "LuckPct", PerLevel = 0.5, MaxLevel = 3, BaseCost = 120_000_000, CostGrowth = 2.5,
		Q = -4, R = 0, Requires = { "Luck3" }, Format = "Percent", Suffix = "luck" },
	{ Id = "ShinyHunter", Name = "Shiny Hunter", Icon = "✨", Description = "Variants (Big, Huge, Jumbo, Shiny, Inverted) roll more often.",
		Stat = "VariantLuckPct", PerLevel = 0.1, MaxLevel = 5, BaseCost = 40_000, CostGrowth = 1.9,
		Q = -2, R = 1, Requires = { "Luck1" }, Format = "Percent", Suffix = "variant luck" },

	-- North-east: roll speed
	{ Id = "Speed1", Name = "Quick Hands I", Icon = "⚡", Description = "Roll faster.",
		Stat = "RollSpeedPct", PerLevel = 0.1, MaxLevel = 5, BaseCost = 5_000, CostGrowth = 1.6,
		Q = 1, R = -1, Requires = { "AutoRoll" }, Format = "Percent", Suffix = "roll speed" },
	{ Id = "Speed2", Name = "Quick Hands II", Icon = "⚡", Description = "Roll even faster.",
		Stat = "RollSpeedPct", PerLevel = 0.1, MaxLevel = 5, BaseCost = 150_000, CostGrowth = 1.8,
		Q = 2, R = -2, Requires = { "Speed1" }, Format = "Percent", Suffix = "roll speed" },
	{ Id = "Speed3", Name = "Quick Hands III", Icon = "⚡", Description = "Blink and you'll miss it.",
		Stat = "RollSpeedPct", PerLevel = 0.2, MaxLevel = 3, BaseCost = 8_000_000, CostGrowth = 2.2,
		Q = 3, R = -3, Requires = { "Speed2" }, Format = "Percent", Suffix = "roll speed" },
	{ Id = "MultiRoll", Name = "Multi Roll", Icon = "🎲", Description = "Chance for each roll to give an extra stud.",
		Stat = "ExtraRollChance", PerLevel = 0.04, MaxLevel = 5, BaseCost = 500_000, CostGrowth = 2,
		Q = 3, R = -2, Requires = { "Speed2" }, Format = "Percent", Suffix = "chance" },

	-- North-west: free rolls
	{ Id = "Meter1", Name = "Fast Meter I", Icon = "⏱️", Description = "Fewer key presses per free roll.",
		Stat = "MeterPct", PerLevel = 0.06, MaxLevel = 5, BaseCost = 4_000, CostGrowth = 1.6,
		Q = 0, R = -1, Requires = { "AutoRoll" }, Format = "Percent", Suffix = "fewer presses" },
	{ Id = "Bank", Name = "Bigger Bank", Icon = "🏦", Description = "Bank more free rolls.",
		Stat = "BankSize", PerLevel = 5, MaxLevel = 5, BaseCost = 50_000, CostGrowth = 1.7,
		Q = 0, R = -2, Requires = { "Meter1" }, Format = "Flat", Suffix = "free rolls" },
	{ Id = "Meter2", Name = "Fast Meter II", Icon = "⏱️", Description = "Even fewer key presses per free roll.",
		Stat = "MeterPct", PerLevel = 0.06, MaxLevel = 5, BaseCost = 1_500_000, CostGrowth = 1.9,
		Q = 0, R = -3, Requires = { "Bank" }, Format = "Percent", Suffix = "fewer presses" },
	{ Id = "Bargain", Name = "Bargain Rolls", Icon = "🏷️", Description = "Paid rolls cost fewer Clacks.",
		Stat = "RollCostPct", PerLevel = 0.08, MaxLevel = 5, BaseCost = 20_000, CostGrowth = 1.8,
		Q = -1, R = -1, Requires = { "Meter1" }, Format = "Percent", Suffix = "cheaper" },

	-- South-east: inventory
	{ Id = "Slot1", Name = "Extra Slot I", Icon = "➕", Description = "Equip one more stud.",
		Stat = "Slots", PerLevel = 1, MaxLevel = 1, BaseCost = 15_000, CostGrowth = 1,
		Q = 0, R = 1, Requires = { "AutoRoll" }, Format = "Flat", Suffix = "slot" },
	{ Id = "Storage", Name = "Storage", Icon = "📦", Description = "Hold more studs.",
		Stat = "MaxStuds", PerLevel = 25, MaxLevel = 5, BaseCost = 30_000, CostGrowth = 1.7,
		Q = 0, R = 2, Requires = { "Slot1" }, Format = "Flat", Suffix = "studs" },
	{ Id = "Slot2", Name = "Extra Slot II", Icon = "➕", Description = "Equip one more stud.",
		Stat = "Slots", PerLevel = 1, MaxLevel = 1, BaseCost = 5_000_000, CostGrowth = 1,
		Q = 0, R = 3, Requires = { "Storage" }, Format = "Flat", Suffix = "slot" },
	{ Id = "Fusion", Name = "Efficient Fusion", Icon = "🔮", Description = "Fusing needs one fewer stud.",
		Stat = "FuseDiscount", PerLevel = 1, MaxLevel = 1, BaseCost = 250_000, CostGrowth = 1,
		Q = 1, R = 2, Requires = { "Storage" }, Format = "Flat", Suffix = "fewer studs" },

	-- South-east: combat
	{ Id = "Sharp1", Name = "Sharp Studs I", Icon = "🗡️", Description = "Your studs hit harder.",
		Stat = "StrengthPct", PerLevel = 0.15, MaxLevel = 5, BaseCost = 1_500, CostGrowth = 1.7,
		Q = 1, R = 1, Requires = { "Slot1" }, Format = "Percent", Suffix = "Strength" },
	{ Id = "Sharp2", Name = "Sharp Studs II", Icon = "🗡️", Description = "Your studs hit much harder.",
		Stat = "StrengthPct", PerLevel = 0.3, MaxLevel = 5, BaseCost = 40_000, CostGrowth = 1.8,
		Q = 2, R = 1, Requires = { "Sharp1" }, Format = "Percent", Suffix = "Strength" },
	{ Id = "Sharp3", Name = "Sharp Studs III", Icon = "⚔️", Description = "Your studs hit devastatingly hard.",
		Stat = "StrengthPct", PerLevel = 0.6, MaxLevel = 5, BaseCost = 1_500_000, CostGrowth = 1.9,
		Q = 3, R = 1, Requires = { "Sharp2" }, Format = "Percent", Suffix = "Strength" },
	{ Id = "Tough1", Name = "Tough Studs", Icon = "🛡️", Description = "Your studs take more hits.",
		Stat = "HealthPct", PerLevel = 0.2, MaxLevel = 5, BaseCost = 20_000, CostGrowth = 1.8,
		Q = 2, R = 2, Requires = { "Sharp2" }, Format = "Percent", Suffix = "Health" },
	{ Id = "LootLuck", Name = "Loot Luck", Icon = "🎁", Description = "Better boss drops and more Big / Shiny Roll drops.",
		Stat = "DropLuckPct", PerLevel = 0.25, MaxLevel = 4, BaseCost = 200_000, CostGrowth = 2,
		Q = 3, R = 2, Requires = { "Tough1" }, Format = "Percent", Suffix = "drop luck" },

	-- South-west: movement and zones
	{ Id = "Swift1", Name = "Swift Feet I", Icon = "👟", Description = "Walk faster, press more keys.",
		Stat = "WalkSpeed", PerLevel = 1, MaxLevel = 4, BaseCost = 8_000, CostGrowth = 1.7,
		Q = -1, R = 1, Requires = { "AutoRoll" }, Format = "Flat", Suffix = "walk speed" },
	{ Id = "Swift2", Name = "Swift Feet II", Icon = "👟", Description = "Walk even faster.",
		Stat = "WalkSpeed", PerLevel = 1, MaxLevel = 4, BaseCost = 400_000, CostGrowth = 1.9,
		Q = -2, R = 2, Requires = { "Swift1" }, Format = "Flat", Suffix = "walk speed" },
	{ Id = "Explorer", Name = "Explorer", Icon = "🗺️", Description = "Zones cost fewer Clacks.",
		Stat = "ZoneDiscountPct", PerLevel = 0.05, MaxLevel = 5, BaseCost = 2_000_000, CostGrowth = 1.9,
		Q = -3, R = 3, Requires = { "Swift2" }, Format = "Percent", Suffix = "cheaper" },
	{ Id = "Reborn", Name = "Reborn", Icon = "🔁", Description = "Every rebirth gives more Clacks.",
		Stat = "RebirthBonus", PerLevel = 0.02, MaxLevel = 5, BaseCost = 1_000_000, CostGrowth = 2,
		Q = -1, R = 2, Requires = { "Swift1" }, Format = "Flat", Suffix = "x Clacks per rebirth" },
}

local byId: { [string]: UpgradeDef } = {}
local occupied: { [string]: string } = {}
for _, def in list do
	assert(not byId[def.Id], `Duplicate upgrade id: {def.Id}`)
	local cell = `{def.Q},{def.R}`
	assert(not occupied[cell], `Upgrades {def.Id} and {occupied[cell]} share a hex`)
	occupied[cell] = def.Id
	byId[def.Id] = def
end
for _, def in list do
	for _, id in def.Requires do
		assert(byId[id], `Upgrade {def.Id} requires unknown upgrade {id}`)
	end
end

local Upgrades = {
	List = list,
	ById = byId,
}

-- 1234 → 1200, 56789 → 57000: keeps prices readable.
local function roundNice(n: number): number
	if n < 100 then
		return math.floor(n + 0.5)
	end
	local magnitude = 10 ^ (math.floor(math.log10(n)) - 1)
	return math.floor(n / magnitude + 0.5) * magnitude
end

-- Cost of the NEXT level when the node is at `level`.
function Upgrades.cost(def: UpgradeDef, level: number): number
	return roundNice(def.BaseCost * def.CostGrowth ^ level)
end

function Upgrades.level(levels: { [string]: number }?, id: string): number
	local value = levels and levels[id]
	return if typeof(value) == "number" then value else 0
end

function Upgrades.isUnlocked(def: UpgradeDef, levels: { [string]: number }?): boolean
	for _, id in def.Requires do
		if Upgrades.level(levels, id) < 1 then
			return false
		end
	end
	return true
end

-- Sum of every node's effect, by Stat.
function Upgrades.totals(levels: { [string]: number }?): { [string]: number }
	local totals: { [string]: number } = {}
	for _, def in list do
		local level = math.min(Upgrades.level(levels, def.Id), def.MaxLevel)
		if level > 0 then
			totals[def.Stat] = (totals[def.Stat] or 0) + def.PerLevel * level
		end
	end
	return totals
end

-- "+20% Clacks", "+5 free rolls", "Unlocked" — the effect at `level`.
function Upgrades.effectText(def: UpgradeDef, level: number): string
	if def.Format == "Unlock" then
		return if level > 0 then "Unlocked" else "Locked"
	end
	local value = def.PerLevel * level
	local suffix = if def.Suffix then " " .. def.Suffix else ""
	if def.Format == "Percent" then
		return `+{math.floor(value * 100 + 0.5)}%{suffix}`
	end
	local text = string.format("%.2f", value)
	text = string.gsub(text, "%.?0+$", "")
	return `+{text}{suffix}`
end

return Upgrades
