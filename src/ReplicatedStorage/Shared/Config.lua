--[[ 

Config
ModuleScript
/ReplicatedStorage/Shared/Config

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Every tunable number in one place. This module replicates, so treat it as
-- public: the server still re-checks everything it reads from here.

local Config = {}

-- Rarity order matters: lowest → highest. Used for sorting, auto-delete and UI.
Config.Rarities = {
	Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" },
	Colors = {
		Common = Color3.fromRGB(196, 202, 212),
		Uncommon = Color3.fromRGB(108, 222, 140),
		Rare = Color3.fromRGB(86, 168, 255),
		Epic = Color3.fromRGB(176, 104, 255),
		Legendary = Color3.fromRGB(255, 196, 64),
		Mythic = Color3.fromRGB(255, 84, 132),
		Secret = Color3.fromRGB(20, 20, 24),
	},
	-- Rarities the player is allowed to auto-delete.
	AutoDeletable = { Common = true, Uncommon = true, Rare = true, Epic = true },
}

-- Server-side keypress detection (Systems/PressTracker).
Config.Press = {
	HitboxTag = "KeyCapper_Hitbox", -- must match KeyCapper's Config.TAG_HITBOX
	AttrValue = "Value", -- Clacks per press, stamped on the key Model by the plugin
	AttrWorld = "World",
	DefaultKeyValue = 1,
	SampleRate = 10, -- Hz per player. Sweeps cover the gap between samples.
	FeetBoxSize = Vector3.new(2.2, 1.2, 2.2),
	MaxPressesPerSample = 12,
	-- A sample that moved further than WalkSpeed * dt * SpeedSlack + TeleportSlack
	-- is treated as a teleport/fling: no presses counted for it.
	SpeedSlack = 1.6,
	TeleportSlack = 6,
}

-- Reward tiles: random keys light up with "+1" text; the first player to
-- step on one (in a zone they own) gets the reward. KeyCapper's letter
-- labels are hidden so only reward tiles carry text.
Config.KeyRewards = {
	HideLetters = true,
	Interval = 3, -- seconds between new reward tiles
	MaxActive = 8, -- reward tiles on the board at once
	Lifetime = 40, -- seconds before an unclaimed tile fades
	Text = "+1",
	-- Any Shared/Rewards kind: Clacks (scaled by progress), FreeRolls, Spins...
	Reward = { Kind = "FreeRolls", Amount = 1 },
	Attribute = "RewardTile", -- set on the key Model while active
}

Config.Economy = {
	PressesPerFreeRoll = 150,
	MinPressesPerFreeRoll = 40, -- floor after meter upgrades
	MaxBankedFreeRolls = 25,
}

Config.Rolls = {
	ClackCost = 250, -- per paid roll
	MaxBatch = 3, -- rolls per request
	Cooldown = 0.9, -- seconds between roll requests at x1 roll speed (lets the client animate)
	MinCooldown = 0.2, -- floor however fast roll speed gets
	BaseLuck = 1,
	MinCostFraction = 0.2, -- roll-cost upgrades never go below this share of ClackCost
}

Config.Inventory = {
	MaxStuds = 150, -- total stud count (sum of all stacks) before Storage upgrades
	BaseSlots = 3,
	MaxSlots = 12, -- hard cap after milestones, upgrades and the +1 Equip pass
	FuseCost = 5, -- this many of one stud+variant fuse into one of the next variant
	MinFuseCost = 2,
	KeepFirstDiscovery = true, -- never auto-delete a brand-new index entry
}

Config.Movement = {
	BaseWalkSpeed = 16, -- Swift Feet upgrades add to this (server sets Humanoid.WalkSpeed)
}

-- Rebirth costs Clacks and resets Clacks (and zones, if ResetZones). Studs,
-- the index, upgrades, Lucky Rolls, spins and boosts are kept.
Config.Rebirth = {
	BaseCost = 500_000,
	CostGrowth = 3, -- cost × this for every rebirth already done
	ClacksPerRebirth = 0.5, -- +x0.5 Clacks multiplier per rebirth (1 → 1.5 → 2 ...)
	LuckPerRebirth = 0.1, -- +10% luck per rebirth
	ResetZones = true,
}

-- Personal timed boosts (Robux, rewards, wheel). Time only counts down
-- while the player is in the game; buying more adds time.
export type BoostDef = {
	Name: string,
	Short: string, -- tiny label for the HUD timer
	Luck: number?, -- added to base luck (before multipliers)
	Clacks: number?, -- multiplies Clacks
	RollSpeed: number?, -- multiplies roll speed
	Duration: number, -- seconds per purchase
	Color: Color3,
}

local boosts: { [string]: BoostDef } = {
	Luck = { Name = "Luck Boost", Short = "+1 Luck", Luck = 1, Duration = 180, Color = Color3.fromRGB(120, 255, 140) },
	UltraLuck = { Name = "Ultra Luck Boost", Short = "+2 Luck", Luck = 2, Duration = 180, Color = Color3.fromRGB(80, 255, 220) },
	Speed = { Name = "Roll Speed Boost", Short = "x2 Speed", RollSpeed = 2, Duration = 180, Color = Color3.fromRGB(110, 200, 255) },
	Clacks = { Name = "Clacks Boost", Short = "x2 Clacks", Clacks = 2, Duration = 180, Color = Color3.fromRGB(255, 230, 90) },
}
Config.Boosts = boosts
Config.BoostOrder = { "Luck", "UltraLuck", "Speed", "Clacks" }
Config.MaxBoostSeconds = 24 * 60 * 60

-- Bought with Robux by anyone in the server; multiplies everyone's luck.
-- Buying again while active adds Duration to the remaining time.
Config.ServerLuck = {
	Multiplier = 2,
	Duration = 15 * 60,
	MaxDuration = 6 * 60 * 60,
}

-- Global events: one starts every Interval seconds and lasts Duration.
-- The schedule is computed from the clock, so every server runs the same
-- event at the same time with no cross-server messaging.
export type EventDef = {
	Id: string,
	Name: string,
	Luck: number?, -- multiplies luck
	Clacks: number?, -- multiplies Clacks
	RollSpeed: number?, -- multiplies roll speed
	Color: Color3,
}

local events: { EventDef } = {
	{ Id = "LuckyRush", Name = "Lucky Rush", Luck = 2, Color = Color3.fromRGB(120, 255, 140) },
	{ Id = "ClackFrenzy", Name = "Clack Frenzy", Clacks = 2, Color = Color3.fromRGB(255, 230, 90) },
	{ Id = "SpeedRush", Name = "Speed Rush", RollSpeed = 1.5, Color = Color3.fromRGB(110, 200, 255) },
}
Config.Events = {
	Interval = 20 * 60,
	Duration = 5 * 60,
	List = events,
}

Config.Social = {
	FriendBonus = 0.1, -- +10% Clacks per friend in the server
	MaxFriends = 5,
	PremiumBonus = 0.2, -- +20% Clacks for Roblox Premium members
}

Config.VIP = {
	Clacks = 1.25,
	Luck = 1.25,
	TagText = "[VIP]",
	TagColor = Color3.fromRGB(255, 205, 60),
	TrailColors = { Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 120, 200) },
}

-- Bonuses unlock automatically from the number of index entries discovered
-- (each stud+variant pair is one entry). Values are additive.
export type Milestone = { Count: number, Slots: number?, Luck: number?, Clacks: number? }

local milestones: { Milestone } = {
	{ Count = 5, Slots = 1 },
	{ Count = 10, Luck = 0.1 },
	{ Count = 20, Clacks = 0.25 },
	{ Count = 30, Slots = 1 },
	{ Count = 45, Luck = 0.25 },
	{ Count = 60, Slots = 1, Clacks = 0.5 },
	{ Count = 80, Luck = 0.25 },
	{ Count = 100, Clacks = 1 },
	{ Count = 120, Slots = 1, Luck = 0.5 },
}
Config.IndexMilestones = milestones

Config.Announce = {
	MinOneIn = 10000, -- server-wide announcement at or rarer than this (stud × variant odds)
}

Config.Sync = {
	FlushInterval = 0.2, -- seconds between batched state patches
}

-- Zone parts in the world (all optional):
--   workspace.Zones.<ZoneId>.Spawn    BasePart: teleport target
--   workspace.Zones.<ZoneId>.Barrier  BasePart or Model: walls that open
--                                     (locally) once the zone is owned
-- Keys inside workspace.Zones.<ZoneId> (or with a World attribute) only
-- pay Clacks to players who own that zone.
Config.ZoneFolder = "Zones"

Config.Followers = {
	RenderDistance = 120, -- other players' studs further than this are hidden
	Spacing = 2.4,
	BackOffset = 4,
	Height = 1.5,
	BobHeight = 0.3,
	BobSpeed = 3,
	FollowSpeed = 12,
}

Config.Visuals = {
	-- Optional template: a 1×1×1 Part carrying your inset-stud texture
	-- (Texture/Decal/SurfaceAppearance). If missing, a plain part is built
	-- and FallbackTextureId (if set) is applied to all six faces.
	TemplateFolder = "Assets",
	TemplateName = "StudTemplate",
	FallbackTextureId = "",
	Size = Vector3.new(1, 1, 1),
}

Config.Data = {
	StoreName = "Mosswake_Players_v1",
	UseMockInStudio = false, -- true = Studio sessions never touch real data
}

Config.Dev = {
	-- Dev commands only ever exist in Studio. Extra UserIds allowed there:
	AllowedUserIds = {} :: { number },
}

return Config
