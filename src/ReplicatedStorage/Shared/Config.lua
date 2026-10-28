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

Config.Economy = {
	PressesPerFreeRoll = 150,
	MaxBankedFreeRolls = 25,
}

Config.Rolls = {
	ClackCost = 250, -- per paid roll
	MaxBatch = 3, -- rolls per request
	Cooldown = 0.9, -- seconds between roll requests (lets the client animate)
	BaseLuck = 1,
}

Config.Inventory = {
	MaxStuds = 150, -- total stud count (sum of all stacks)
	BaseSlots = 3,
	MaxSlots = 8,
	FuseCost = 5, -- this many of one stud+variant fuse into one of the next variant
	KeepFirstDiscovery = true, -- never auto-delete a brand-new index entry
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
}
Config.IndexMilestones = milestones

Config.Announce = {
	MinOneIn = 10000, -- server-wide announcement at or rarer than this (stud × variant odds)
}

Config.Sync = {
	FlushInterval = 0.2, -- seconds between batched state patches
}

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
