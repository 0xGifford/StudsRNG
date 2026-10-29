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
local Upgrades = require(Shared.Upgrades)

type StudDef = Types.StudDef
type VariantDef = Types.VariantDef
type Stats = Types.Stats
type StatContext = Types.StatContext

local RollLogic = {}

local MAX_KEY_LENGTH = 64

-- Rarest first: the roll walks this list and stops at the first hit.
local studsRarestFirst: { StudDef } = table.clone(Studs.List)
table.sort(studsRarestFirst, function(a, b)
	return a.OneIn > b.OneIn
end)

local variantsRarestFirst: { VariantDef } = {}
for _, name in Variants.Order do -- retired variants aren't in Order, so never roll
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
		if unlockedWorlds[def.World] and not def.Drop then
			fallback = def
			if rng:NextNumber() * def.OneIn < luck then
				return def
			end
		end
	end
	return fallback
end

-- A boss drop: drop studs rarest first, each with chance luck / OneIn.
-- Nil when nothing drops.
function RollLogic.rollDrop(rng: Random, luck: number): StudDef?
	for _, def in studsRarestFirst do
		if def.Drop and def.World == "Boss" and rng:NextNumber() * def.OneIn < luck then
			return def
		end
	end
	return nil
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

-- Stud levels (Config.Levels): level from XP, XP needed for a level, and
-- the stat multiplier a level gives.
function RollLogic.levelOf(xp: number?): number
	local levels = Config.Levels
	local x = math.max(0, xp or 0)
	return math.min(levels.Max, math.floor(math.sqrt(x / levels.XpBase)) + 1)
end

function RollLogic.xpForLevel(level: number): number
	return Config.Levels.XpBase * (level - 1) ^ 2
end

function RollLogic.levelBonus(level: number): number
	return 1 + (level - 1) * Config.Levels.StatsPerLevel
end

-- Strength and Health of one stud: rarer studs hit harder and last longer,
-- the variant multiplies both (a StudDef can set its own), and so does the
-- stud's level.
function RollLogic.statsOf(def: StudDef, variant: VariantDef, level: number?): (number, number)
	local strength = def.Strength or math.max(1, math.floor(1.5 * def.OneIn ^ 0.38 + 0.5))
	local health = def.Health or math.max(5, math.floor(7 * def.OneIn ^ 0.36 + 0.5))
	local mult = (variant.Stats or 1) * RollLogic.levelBonus(level or 1)
	return math.floor(strength * mult + 0.5), math.floor(health * mult + 0.5)
end

-- The equipped studs' combined Strength and Health (xp: PlayerData.StudXP).
function RollLogic.teamStats(equipped: { string }, xp: { [string]: number }?): (number, number)
	local strength, health = 0, 0
	for _, key in equipped do
		local def, variant = RollLogic.decodeKey(key)
		if def and variant then
			local s, h = RollLogic.statsOf(def, variant, RollLogic.levelOf(xp and xp[def.Id]))
			strength += s
			health += h
		end
	end
	return strength, health
end

function RollLogic.indexTotal(): number
	return #Studs.List * #Variants.Order
end

-- Retired variants (Golden, Rainbow) don't count towards the index.
function RollLogic.countIndex(index: { [string]: boolean }): number
	local n = 0
	for key, found in index do
		if found then
			local def, variant = RollLogic.decodeKey(key)
			if def and variant and not variant.Retired then
				n += 1
			end
		end
	end
	return n
end

-- One Index tab: how many of its studs are found, out of how many.
function RollLogic.tabProgress(index: { [string]: boolean }, variant: string): (number, number)
	local found = 0
	for _, def in Studs.List do
		if index[RollLogic.encodeKey(def.Id, variant)] then
			found += 1
		end
	end
	return found, #Studs.List
end

-- How many Index tab rewards are claimed.
function RollLogic.claimedTabs(claims: any): number
	local n = 0
	if typeof(claims) == "table" then
		for _, name in Variants.Order do
			if claims[name] == true then
				n += 1
			end
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

local eventsById: { [string]: Config.EventDef } = {}
for _, event in Config.Events.List do
	eventsById[event.Id] = event
end

local EMPTY_CONTEXT: StatContext = {
	Passes = {},
	ActiveBoosts = {},
	ServerLuck = 1,
	Event = nil,
	Friends = 0,
	Premium = false,
}

function RollLogic.eventById(id: string?): Config.EventDef?
	return if id then eventsById[id] else nil
end

-- Global event schedule from the clock alone (same answer on every server
-- and client). Returns the running event (or nil), when it ends, and when
-- the next one starts.
function RollLogic.eventSchedule(now: number): (Config.EventDef?, number, number)
	local interval = Config.Events.Interval
	local list = Config.Events.List
	local cycle = math.floor(now / interval)
	local start = cycle * interval
	local nextStart = start + interval
	if #list > 0 and now < start + Config.Events.Duration then
		return list[cycle % #list + 1], start + Config.Events.Duration, nextStart
	end
	return nil, start + Config.Events.Duration, nextStart
end

-- Every stat in one place. Equipped studs stack ADDITIVELY with each other
-- (×2 and ×3 → ×4); everything else multiplies.
--
-- Luck = (base + Lucky Rolls + boost luck)
--        × index milestones × rebirths × upgrades × VIP × server luck × event
-- Flat luck is added BEFORE the multipliers, so a +1 Lucky Roll is worth
-- more the more multipliers the player has.
function RollLogic.computeStats(data: any, context: StatContext?): Stats
	local ctx = context or EMPTY_CONTEXT
	local discovered = RollLogic.countIndex(data.Index or {})
	local bonusSlots, bonusLuck, bonusClacks = RollLogic.milestoneBonuses(discovered)
	local tabs = RollLogic.claimedTabs(data.IndexClaims)
	bonusLuck += tabs * Config.IndexTabReward.Luck
	bonusClacks += tabs * Config.IndexTabReward.Clacks
	local upgrades = Upgrades.totals(data.Upgrades)
	local function up(stat: string): number
		return upgrades[stat] or 0
	end

	local studBonus = 0
	for _, key in data.Equipped or {} do
		local def, variant = RollLogic.decodeKey(key)
		if def and variant then
			studBonus += RollLogic.multiplierOf(def, variant) - 1
		end
	end

	-- Timed boosts and the global event
	local boostLuck, boostClacks, boostSpeed = 0, 1, 1
	for id, active in ctx.ActiveBoosts do
		local boost = Config.Boosts[id]
		if active and boost then
			boostLuck += boost.Luck or 0
			boostClacks *= boost.Clacks or 1
			boostSpeed *= boost.RollSpeed or 1
		end
	end
	local event = RollLogic.eventById(ctx.Event)
	local eventLuck = if event then event.Luck or 1 else 1
	local eventClacks = if event then event.Clacks or 1 else 1
	local eventSpeed = if event then event.RollSpeed or 1 else 1

	local passes = ctx.Passes
	local vip = passes.VIP == true
	local rebirths = if typeof(data.Rebirths) == "number" then data.Rebirths else 0
	local luckyRolls = if typeof(data.LuckyRolls) == "number" then data.LuckyRolls else 0

	local friends = math.min(ctx.Friends, Config.Social.MaxFriends)
	local friendBonus = friends * Config.Social.FriendBonus
	local premiumBonus = if ctx.Premium then Config.Social.PremiumBonus else 0
	local rebirthClacks = 1 + rebirths * (Config.Rebirth.ClacksPerRebirth + up("RebirthBonus"))
	local rebirthLuck = 1 + rebirths * Config.Rebirth.LuckPerRebirth

	local luck = (Config.Rolls.BaseLuck + luckyRolls + boostLuck)
		* (1 + bonusLuck)
		* rebirthLuck
		* (1 + up("LuckPct"))
		* (if vip then Config.VIP.Luck else 1)
		* ctx.ServerLuck
		* eventLuck

	local clacks = (1 + studBonus)
		* (1 + bonusClacks)
		* rebirthClacks
		* (1 + up("ClacksPct"))
		* boostClacks
		* (if vip then Config.VIP.Clacks else 1)
		* (1 + friendBonus + premiumBonus)
		* eventClacks

	local rollSpeed = (if passes.FastRoll then 2 else 1) * boostSpeed * (1 + up("RollSpeedPct")) * eventSpeed
	local slots = Config.Inventory.BaseSlots + bonusSlots + up("Slots") + (if passes.ExtraEquip then 1 else 0)
	local costFraction = math.max(Config.Rolls.MinCostFraction, 1 - up("RollCostPct"))
	local presses = Config.Economy.PressesPerFreeRoll * (1 - up("MeterPct"))

	return {
		ClackMultiplier = clacks,
		Luck = luck,
		Slots = math.min(slots, Config.Inventory.MaxSlots),
		Discovered = discovered,
		IndexTotal = RollLogic.indexTotal(),
		StudCount = RollLogic.countStuds(data.Studs or {}),
		MaxStuds = Config.Inventory.MaxStuds + up("MaxStuds"),
		RollSpeed = rollSpeed,
		RollCooldown = math.max(Config.Rolls.MinCooldown, Config.Rolls.Cooldown / rollSpeed),
		RollCost = math.floor(Config.Rolls.ClackCost * costFraction),
		StudsPerRoll = if passes.DoubleRoll then 2 else 1,
		ExtraRollChance = math.clamp(up("ExtraRollChance"), 0, 1),
		VariantLuck = luck * (1 + up("VariantLuckPct")),
		PressesPerFreeRoll = math.max(Config.Economy.MinPressesPerFreeRoll, math.floor(presses)),
		MaxBankedFreeRolls = Config.Economy.MaxBankedFreeRolls + up("BankSize"),
		CritChance = math.clamp(up("CritChance"), 0, 1),
		FuseCost = math.max(Config.Inventory.MinFuseCost, Config.Inventory.FuseCost - up("FuseDiscount")),
		WalkSpeed = Config.Movement.BaseWalkSpeed + up("WalkSpeed"),
		ZoneDiscount = math.clamp(up("ZoneDiscountPct"), 0, 0.5),
		AutoRoll = up("AutoRoll") > 0,
		Friends = friends,
		FriendBonus = friendBonus,
		PremiumBonus = premiumBonus,
		RebirthClacks = rebirthClacks,
		RebirthLuck = rebirthLuck,
		ServerLuck = ctx.ServerLuck,
	}
end

-- Clacks needed for the next rebirth.
function RollLogic.rebirthCost(rebirths: number): number
	return math.floor(Config.Rebirth.BaseCost * Config.Rebirth.CostGrowth ^ rebirths)
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
