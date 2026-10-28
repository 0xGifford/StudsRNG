--[[ 

RollLogic
ModuleScript
/ReplicatedStorage/Shared/Util/RollLogic

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Pure functions shared by server and client. The server's result is the
-- only one that counts; the client copy exists so UI can show odds, stats
-- and multipliers without asking the server.

local Shared = script.Parent.Parent
local Config = require(Shared.Config)
local Studs = require(Shared.Studs)
local Variants = require(Shared.Variants)
local Types = require(Shared.Types)

type StudDef = Types.StudDef
type VariantDef = Types.VariantDef
type Stats = Types.Stats

local RollLogic = {}

local MAX_KEY_LENGTH = 64

-- Rarest first: the roll walks this list and stops at the first hit.
local studsRarestFirst: { StudDef } = table.clone(Studs.List)
table.sort(studsRarestFirst, function(a, b)
	return a.OneIn > b.OneIn
end)

local variantsRarestFirst: { VariantDef } = {}
for _, name in Variants.Order do
	table.insert(variantsRarestFirst, Variants.ById[name])
end
table.sort(variantsRarestFirst, function(a, b)
	return a.OneIn > b.OneIn
end)

local rarityRank: { [string]: number } = {}
for i, rarity in Config.Rarities.Order do
	rarityRank[rarity] = i
end

--------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------

function RollLogic.encodeKey(id: string, variant: string): string
	return `{id}:{variant}`
end

-- Returns nil for anything that isn't a real stud + variant. Safe on
-- hostile input: callers pass raw remote arguments straight in.
function RollLogic.decodeKey(key: unknown): (StudDef?, VariantDef?)
	if typeof(key) ~= "string" then return nil, nil end
	if #key == 0 or #key > MAX_KEY_LENGTH then return nil, nil end
	local id, variant = string.match(key, "^([%w_]+):([%w_]+)$")
	if not id or not variant then return nil, nil end
	local def = Studs.ById[id]
	local variantDef = Variants.ById[variant]
	if not def or not variantDef then return nil, nil end
	return def, variantDef
end

function RollLogic.rarityRank(rarity: string): number
	return rarityRank[rarity] or 0
end

--------------------------------------------------------------------------
-- Odds
--------------------------------------------------------------------------

-- "1 in X" shown to players after luck. Luck divides the odds.
function RollLogic.displayOneIn(oneIn: number, luck: number): number
	return math.max(1, oneIn / math.max(luck, 1e-6))
end

-- Sequential rarest-first roll: each candidate hits with chance luck / OneIn.
-- The commonest candidate is the fallback, so a roll always returns a stud.
function RollLogic.rollStud(rng: Random, luck: number, unlockedWorlds: { [string]: boolean }): StudDef?
	local fallback: StudDef? = nil
	for _, def in studsRarestFirst do
		if unlockedWorlds[def.World] then
			fallback = def
			if rng:NextNumber() * def.OneIn < luck then
				return def
			end
		end
	end
	return fallback
end

function RollLogic.rollVariant(rng: Random, luck: number): VariantDef
	for _, def in variantsRarestFirst do
		if def.OneIn > 1 and rng:NextNumber() * def.OneIn < luck then
			return def
		end
	end
	return Variants.ById.Normal
end

--------------------------------------------------------------------------
-- Stats
--------------------------------------------------------------------------

function RollLogic.multiplierOf(def: StudDef, variant: VariantDef): number
	return def.Multiplier * variant.Multiplier
end

function RollLogic.indexTotal(): number
	return #Studs.List * #Variants.Order
end

function RollLogic.countIndex(index: { [string]: boolean }): number
	local n = 0
	for key, found in index do
		if found and RollLogic.decodeKey(key) then
			n += 1
		end
	end
	return n
end

function RollLogic.countStuds(studs: { [string]: number }): number
	local n = 0
	for _, count in studs do
		n += count
	end
	return n
end

function RollLogic.milestoneBonuses(discovered: number): (number, number, number)
	local slots, luck, clacks = 0, 0, 0
	for _, milestone in Config.IndexMilestones do
		if discovered >= milestone.Count then
			slots += milestone.Slots or 0
			luck += milestone.Luck or 0
			clacks += milestone.Clacks or 0
		end
	end
	return slots, luck, clacks
end

-- Equipped studs stack ADDITIVELY with each other (×2 and ×3 → ×4), then
-- the whole stud total multiplies with every other source.
function RollLogic.computeStats(data: any): Stats
	local discovered = RollLogic.countIndex(data.Index)
	local bonusSlots, bonusLuck, bonusClacks = RollLogic.milestoneBonuses(discovered)

	local studBonus = 0
	for _, key in data.Equipped do
		local def, variant = RollLogic.decodeKey(key)
		if def and variant then
			studBonus += RollLogic.multiplierOf(def, variant) - 1
		end
	end

	return {
		ClackMultiplier = (1 + studBonus) * (1 + bonusClacks),
		Luck = Config.Rolls.BaseLuck * (1 + bonusLuck),
		Slots = math.min(Config.Inventory.BaseSlots + bonusSlots, Config.Inventory.MaxSlots),
		Discovered = discovered,
		IndexTotal = RollLogic.indexTotal(),
		StudCount = RollLogic.countStuds(data.Studs),
	}
end

-- Owned keys sorted best multiplier first (ties: rarer first).
function RollLogic.sortedOwned(studs: { [string]: number }): { string }
	local keys: { string } = {}
	local mult: { [string]: number } = {}
	local rank: { [string]: number } = {}
	for key, count in studs do
		local def, variant = RollLogic.decodeKey(key)
		if def and variant and count > 0 then
			table.insert(keys, key)
			mult[key] = RollLogic.multiplierOf(def, variant)
			rank[key] = def.OneIn * variant.OneIn
		end
	end
	table.sort(keys, function(a, b)
		if mult[a] ~= mult[b] then
			return mult[a] > mult[b]
		end
		return rank[a] > rank[b]
	end)
	return keys
end

function RollLogic.countInList(list: { string }, key: string): number
	local n = 0
	for _, k in list do
		if k == key then
			n += 1
		end
	end
	return n
end

return RollLogic
