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

-- The world (Systems/World): the map is built by hand in Studio
-- (workspace.Zones: Lobby, Zone1 .. Zone34; tools/wire_zones.luau or the
-- ZoneManager plugin wire it up).
Config.World = {
	-- Players who fall below FallY are put back at the nearest zone they own
	-- (or the Lobby).
	FallRescue = true,
	FallY = -90,
}

-- Press streak: presses closer together than Window keep a combo going;
-- every press adds Step to the Clacks bonus, up to Max.
Config.Combo = {
	Window = 1.25,
	Step = 0.005,
	Max = 0.5,
}

-- Clacks earned while away: ClacksPerSecond × reward scale, for at most
-- MaxSeconds, if the player was gone at least MinAway.
Config.Offline = {
	MinAway = 5 * 60,
	MaxSeconds = 8 * 60 * 60,
	ClacksPerSecond = 0.5, -- × Rewards.scale; ~8% of active play at zone 1
}

Config.Tutorial = {
	Reward = {
		{ Kind = "FreeRolls", Amount = 5 },
		{ Kind = "Spins", Amount = 1 },
	},
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
	Variants: { [string]: number }?, -- multiplies the chance of these variants (Shared/Variants names)
	Duration: number, -- seconds per purchase
	Color: Color3,
}

local boosts: { [string]: BoostDef } = {
	Luck = { Name = "Luck Boost", Short = "+1 Luck", Luck = 1, Duration = 180, Color = Color3.fromRGB(120, 255, 140) },
	UltraLuck = { Name = "Ultra Luck Boost", Short = "+2 Luck", Luck = 2, Duration = 180, Color = Color3.fromRGB(80, 255, 220) },
	Speed = { Name = "Roll Speed Boost", Short = "x2 Speed", RollSpeed = 2, Duration = 180, Color = Color3.fromRGB(110, 200, 255) },
	Clacks = { Name = "Clacks Boost", Short = "x2 Clacks", Clacks = 2, Duration = 180, Color = Color3.fromRGB(255, 230, 90) },
	-- Rare enemy drops (Config.Combat.RareDrops), also sold in the shop.
	BigRoll = { Name = "Big Roll", Short = "x4 Big", Variants = { Big = 4, Huge = 2, Jumbo = 2 }, Duration = 120,
		Color = Color3.fromRGB(255, 160, 60) },
	ShinyRoll = { Name = "Shiny Roll", Short = "x4 Shiny", Variants = { Shiny = 4 }, Duration = 120,
		Color = Color3.fromRGB(255, 250, 170) },
}
Config.Boosts = boosts
Config.BoostOrder = { "Luck", "UltraLuck", "Speed", "Clacks", "BigRoll", "ShinyRoll" }
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

-- Completing an Index tab (every stud in one variant) lets the player claim
-- this, once per tab. Shown in the Index; stacks with milestones.
Config.IndexTabReward = {
	Luck = 0.05,
	Clacks = 0.05,
}

-- Enemies (Systems/Combat, Shared/Enemies). An enemy chases (pathfinds to)
-- any player who owns its zone within AggroRange, never straying more than
-- HomeRadius from where it lives. Players fight automatically: the nearest
-- enemy within EngageRange draws their equipped studs, which deal the team's
-- total Strength per second while the enemy hits the team's total Health.
-- A defeat pays Clacks; the studs then take the next enemy within
-- RetargetRange, or fly home.
Config.Combat = {
	-- Enemies per zone: one per AreaPerEnemy square studs of floor (ZoneSize),
	-- between MinPerZone and MaxPerZone (each one pathfinds: keep it modest).
	AreaPerEnemy = 1500,
	MinPerZone = 4,
	MaxPerZone = 12,
	Tick = 0.25, -- seconds per combat step
	AggroRange = 50, -- studs: enemies notice players this close
	EngageRange = 32, -- studs: studs start fighting an enemy this close
	RetargetRange = 45, -- studs: after a defeat, the next enemy this close is next
	LeashRange = 80, -- the player walking further than this ends the fight
	HomeRadius = 70, -- enemies never chase further than this from home
	ChaseSpeed = 11, -- studs per second
	WanderSpeed = 5,
	WanderRadius = 14,
	RepathTime = 0.8, -- seconds between path recomputes while chasing
	WakeRange = 260, -- enemies only spawn and move while a player is this close
	Respawn = 8, -- seconds before a defeated enemy comes back
	RegenPerSecond = 0.15, -- share of team Health restored per second out of a fight
	KnockoutCooldown = 4, -- seconds before a defeated team can fight again
	RetreatCooldown = 6, -- seconds RETREAT keeps the studs out of fights
	FreeRollChance = 0.1, -- extra drop on each defeat
	-- Fights are paced to the studs' animation: no damage until they've flown
	-- over, and even a strong team takes a moment, so every stud gets a dash.
	ArriveTime = 0.7, -- seconds after a fight starts before damage lands
	MinFightTime = 1.5, -- seconds: the fastest any enemy can go down
	-- Crits: each combat step can land a crit for CritMultiplier damage.
	CritChance = 0.12,
	CritMultiplier = 2.5,
	-- Rare drops: each defeat may drop a variant boost (Config.Boosts).
	-- Mini Bosses multiply the chance by BossDropBonus, Titans by TitanDropBonus.
	RareDrops = {
		{ Boost = "BigRoll", Chance = 1 / 30 },
		{ Boost = "ShinyRoll", Chance = 1 / 120 },
	},
	BossDropBonus = 5,
	TitanDropBonus = 10,
	-- Kill streaks: defeats within StreakWindow of each other chain up, each
	-- link adding StreakBonus Clacks on a defeat, up to StreakMax links.
	StreakWindow = 15,
	StreakBonus = 0.1,
	StreakMax = 20,
	-- Client sounds (built-in Roblox sounds; swap for your own asset ids).
	-- Played in the SFX SoundGroup, so the Options slider controls them.
	Sounds = {
		Dash = "rbxasset://sounds/swordlunge.wav",
		Hit = "rbxasset://sounds/swordslash.wav",
		Crit = "rbxasset://sounds/snap.wav",
		Explode = "rbxasset://sounds/collide.wav",
		Coin = "rbxasset://sounds/electronicpingshort.wav",
		Aggro = "rbxasset://sounds/button.wav",
	},
	-- Mini bosses: any spawn can be one.
	BossChance = 1 / 12,
	BossHealth = 8,
	BossDamage = 2,
	BossReward = 10,
	BossSize = 1.7,
}

-- Stud levels: every stud (all variants of it share one level) earns XP when
-- it's equipped and its team defeats an enemy. Each level adds StatsPerLevel
-- to its Strength and Health. XP for level L: XpBase × (L - 1)².
Config.Levels = {
	Max = 50,
	XpBase = 25,
	StatsPerLevel = 0.05, -- +5% per level → +245% at Lv 50
	XpPerDefeat = 5, -- + XpPerEnemyLevel × the enemy's level
	XpPerEnemyLevel = 3,
	BossXp = 5, -- Mini Boss multiplier
}

-- Zone Bosses (Systems/Combat): every Interval seconds (on the clock, the
-- same for every server) a Titan spawns in every Every-th zone (10, 20, ...)
-- for Lifetime seconds. Everyone who damages it is paid by damage rank.
-- Stats multiply that zone's normal enemy.
Config.ZoneBoss = {
	Every = 10,
	Interval = 20 * 60,
	Warning = 60, -- seconds of warning before they spawn
	Lifetime = 5 * 60, -- then it escapes
	Health = 40,
	Damage = 3,
	Reward = 30,
	Size = 3.2,
	-- By damage rank: Clacks multiplier and extras.
	Ranks = {
		{ Top = 1, Clacks = 3, FreeRolls = 10, Spins = 2 },
		{ Top = 3, Clacks = 2, FreeRolls = 5, Spins = 1 },
		{ Top = math.huge, Clacks = 1, FreeRolls = 3, Spins = 0 },
	},
}

-- Boss drops (Studs with Drop = true). Each kill tries the drop studs
-- rarest first, each hitting with chance Luck / OneIn; Luck grows with the
-- enemy's level (+PerEnemyLevel per level).
Config.Drops = {
	MiniBossLuck = 30,
	ZoneBossLuck = 600,
	PerEnemyLevel = 0.04,
}

-- Global leaderboards (Systems/Leaderboards → Leaderboard-tagged parts).
Config.Leaderboards = {
	Refresh = 120, -- seconds between saving scores and reading the top lists
	Size = 50, -- entries kept per board (parts show the top 10)
	Stores = { -- OrderedDataStore names; bump the version to reset a board
		Clacks = "LB_Clacks_v1",
		Enemies = "LB_Enemies_v1",
		Rarest = "LB_Rarest_v1",
	},
}

Config.Announce = {
	Channel = "Rolls", -- chat channel (tab) every announced roll goes to; never the main chat
	ChannelMinOneIn = 100, -- announced at or rarer than this (stud × variant odds)
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
	-- Your own models (Systems/Templates copies them from ServerStorage to
	-- ReplicatedStorage.<TemplateFolder> at boot, where clients can see them):
	--   TemplateName         ONE Model (or Part / MeshPart) every stud is built
	--                        from, at the size a normal stud should be. The game
	--                        recolours it (parts with KeepColor = true keep
	--                        theirs), scales it for Big / Huge / Jumbo and adds
	--                        particles, glow and the Shiny / Inverted outline
	--                        (Util/StudVisuals). Without one, studs are classic
	--                        bricks (plus FallbackTextureId, if set).
	--   EnemyTemplateFolder  a Folder of Models named Enemy, MiniBoss, Titan
	--                        (Controllers/EnemyVisuals). Without them, enemies
	--                        are the built-in brick monsters.
	TemplateFolder = "Assets",
	TemplateName = "StudTemplate",
	EnemyTemplateFolder = "EnemyTemplates",
	FallbackTextureId = "",
	Size = Vector3.new(1, 1, 1),
}

-- Background music, looped in the "Music" SoundGroup (Options → Music
-- slider sets that group's volume).
Config.Music = {
	SoundId = "rbxassetid://96708360520100",
	Volume = 0.5, -- at a full slider
	FadeIn = 3,
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
