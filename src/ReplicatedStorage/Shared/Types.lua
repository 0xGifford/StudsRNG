--[[ 

Types
ModuleScript
/ReplicatedStorage/Shared/Types

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Types that cross the client/server boundary.

export type StudDef = {
	Id: string,
	Name: string,
	Rarity: string,
	OneIn: number,
	Multiplier: number,
	World: string,
	Color: Color3,
	Material: Enum.Material,
	Particle: string?,
	Light: boolean?,
	Strength: number?, -- overrides the rarity-based default (RollLogic.statsOf)
	Health: number?,
	Drop: boolean?, -- never rolled: only dropped by bosses (Systems/Drops)
}

export type VariantDef = {
	Name: string,
	OneIn: number,
	Multiplier: number,
	Effect: string?,
	ColorOverride: Color3?,
	MaterialOverride: Enum.Material?,
	Label: string?, -- shown name ("Base" for Normal)
	Stats: number?, -- Strength / Health multiplier
	Scale: number?, -- follower size
	Invert: boolean?, -- colour is inverted
	Outline: Color3?, -- outline colour (SelectionBox; a Highlight on your own followers)
	Retired: boolean?, -- no longer rolled, fused or indexed
	Limited: boolean?, -- only rolls in a Favoured zone (Shared/ZoneRotation)
}

-- Saved profile shape (ProfileStore template lives in Systems/PlayerData).
-- Stud keys are "StudId:Variant", e.g. "Ember:Shiny".
export type PlayerData = {
	Version: number,
	Clacks: number,
	LifetimeClacks: number,
	TotalPresses: number,
	FreeRolls: number,
	RollMeter: number,
	TotalRolls: number,
	Studs: { [string]: number }, -- key → count
	Equipped: { string }, -- keys; the same key may appear more than once
	Index: { [string]: boolean }, -- key → discovered
	AutoDelete: { [string]: boolean }, -- rarity → enabled (Normal variant only)
	UnlockedWorlds: { [string]: boolean }, -- zone id → owned (see Shared/Zones)
	Rebirths: number,
	Upgrades: { [string]: number }, -- upgrade id → level (see Shared/Upgrades)
	LuckyRolls: number, -- +1 permanent luck each
	Boosts: { [string]: number }, -- boost id → seconds remaining
	Spins: number, -- jackpot wheel spins
	Daily: { Streak: number, LastDay: number, Weeks: number? }, -- LastDay = UTC day number of the last claim; Weeks = full weeks kept
	SeenUpdate: string, -- newest update log version the player has opened
	PurchaseIds: { string }, -- recent receipt ids (server only, never sent to the client)
	SeenIntro: boolean, -- watched the first-join cinematic
	Tutorial: number, -- tutorial step reached (Systems/Tutorial)
	Quests: { Day: number, List: { QuestState }, Bonus: boolean? }, -- Bonus: the all-done Focus bonus was paid
	LastOnline: number, -- unix time, for offline earnings
	TilesClaimed: number,
	LuckyMeter: number,
	IndexClaims: { [string]: boolean },
	RollCounts: { [string]: number },
	EnemiesDefeated: number,
	StudXP: { [string]: number }, -- stud id → XP; all variants share a level
	BestRoll: number, -- rarest roll's odds (1 in X)
	BossesDefeated: number,
	TitansDefeated: number,
	Achievements: { [string]: boolean },
	Title: string, -- achievement id whose title is worn ("" = none)
	Pass: { Season: string, Points: number, Free: { [string]: boolean }, Premium: { [string]: boolean } }, -- Stud Pass (claimed tiers by tostring(tier))
	Bought: { [string]: boolean }, -- one-time products bought
	Epochs: { Economy: number, All: number }, -- admin resets this save has had (Systems/Admin)
	-- Retention systems (Shared/Mastery, Systems/QuestService, Config.Roles)
	ZoneKills: { [string]: number }, -- enemies defeated per zone (Zone Mastery)
	Mastery: { [string]: number }, -- stars last announced per zone
	FocusPoints: number,
	FocusBought: { [string]: number }, -- Focus Shop items bought (limited ones)
	Weekly: { Week: number, List: { QuestState }, Grand: boolean }, -- Weekly Grand Focus
	BonusStorage: number, -- extra stud storage (Focus Shop)
	StudRoles: { [string]: string }, -- stud key -> squad role
	ClubClaimDay: number, -- last day the Stud Club daily bundle was claimed
	WeeklyStats: { Week: number, Clacks: number, Enemies: number }, -- this week's leaderboard scores
	WeeklyPaid: number, -- last week whose leaderboard reward was checked
	WeeklyPending: number?, -- a week whose leaderboard check failed (retried next join)
	Milestones: { [string]: boolean }, -- value-pack offers already shown
}

export type QuestState = { Id: string, Target: number, Progress: number, Claimed: boolean }

-- Everything outside PlayerData that changes a player's stats. Built by the
-- server (Systems/Modifiers); the client receives the finished Stats.
export type StatContext = {
	Passes: { [string]: boolean },
	ActiveBoosts: { [string]: boolean },
	ServerLuck: number,
	Event: string?,
	Friends: number,
	Premium: boolean,
}

-- Derived by Util/RollLogic.computeStats. The server's copy is pushed to the
-- client as the "Stats" state field.
export type Stats = {
	ClackMultiplier: number,
	Luck: number,
	Slots: number,
	Discovered: number,
	IndexTotal: number,
	StudCount: number,
	MaxStuds: number,
	RollSpeed: number,
	RollCooldown: number,
	RollCost: number,
	StudsPerRoll: number,
	ExtraRollChance: number,
	VariantLuck: number,
	VariantBoosts: { [string]: number }, -- active boosts' per-variant chance multipliers
	TeamStrength: number, -- multiplies the equipped studs' Strength (upgrades)
	TeamHealth: number, -- multiplies their Health
	DropLuck: number, -- multiplies boss drop luck and rare drop chances
	PressesPerFreeRoll: number,
	MaxBankedFreeRolls: number,
	CritChance: number,
	FuseCost: number,
	WalkSpeed: number,
	ZoneDiscount: number,
	AutoRoll: boolean,
	KillClacks: number, -- extra share of Clacks from kills (Fortune role)
	FightCrit: number, -- extra combat crit chance (Swift role)
	MasteryStars: number, -- Zone Mastery stars across every zone
	Memories: number, -- studs levelled to the max (Stud Memories)
	ZoneSet: string?, -- zone id when SetSize+ equipped studs share it
	-- Breakdown for the HUD
	Friends: number,
	FriendBonus: number,
	PremiumBonus: number,
	RebirthClacks: number,
	RebirthLuck: number,
	ServerLuck: number,
}

-- A daily / playtime / wheel prize (see Shared/Rewards).
export type Reward = {
	Kind: string, -- "Clacks" | "FreeRolls" | "Spins" | "Boost" | "Luck" | "MegaRoll" | "Bundle" | "Stud" | "Storage"
	Amount: number, -- Clacks (before scaling), rolls, spins, luck, the MegaRoll luck multiplier, or storage slots
	Boost: string?, -- Kind == "Boost": boost id
	Minutes: number?, -- Kind == "Boost": duration
	Items: { Reward }?, -- Kind == "Bundle": every one of these
	Stud: string?, -- Kind == "Stud": "StudId:Variant"
}

export type RollResult = {
	Id: string,
	Variant: string,
	Key: string,
	OneIn: number, -- combined nominal odds (stud × variant)
	New: boolean, -- first time in the index
	Kept: boolean, -- added to inventory
	Reason: string?, -- "AutoDelete" | "Full" when not kept
	Lucky: boolean?, -- a Lucky Meter roll (Config.LuckyMeter)
}

-- Every RemoteFunction answers with this shape.
export type Response = {
	Ok: boolean,
	Error: string?,
	[string]: any,
}

export type StatePatch = {
	Seq: number,
	Data: { [string]: any },
}

return {}
