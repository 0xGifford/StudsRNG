--!strict
-- KeyCapper runtime — Copyright (c) 2026 sebattfg. All rights reserved.
-- Proprietary; installed by the KeyCapper plugin. Redistribution of the
-- plugin or of this runtime is prohibited. sebattfg is the sole authorised
-- distributor. Icons: Font Awesome 5 Free (CC BY 4.0), fontawesome.com
--
-- Centralized settings. Single source of truth for the whole prototype.

return {
	TAG_HITBOX = "KeyCapper_Hitbox",

	-- Written by the plugin, read here. Must stay identical to
	-- Constants.GROUPS_FOLDER / Constants.ATTR_GROUP on the plugin side.
	GROUPS_FOLDER = "KeyCapperGroups",
	ATTR_GROUP = "Group",

	-- Detection
	TICK_RATE = 30, -- Hz. 30 is plenty, 60 is wasteful.
	FEET_BOX_SIZE = Vector3.new(2.2, 1.2, 2.2), -- box tested at the player's feet

	-- Fallback press timing when a group doesn't override its own (see
	-- RuntimeSource.GroupConfig / AnimationPresets for the per-group style
	-- and depth).
	PRESS_TIME = 0.045,
	RELEASE_TIME = 0.13,

	-- Sound
	SOUND_ID = "rbxassetid://76552892647565",
	SOUND_VOLUME = 0.5,
	SOUND_PITCH_JITTER = 0.06, -- +/- 6% to avoid a repetitive feel
	SOUND_MAX_DISTANCE = 120, -- was 60: too easy to walk out of hearing range on a normal-sized board
	-- Minimum gap between two starts of the SAME sound asset (see
	-- Style.SoundGate). Kept DELIBERATELY under one detection tick
	-- (1/TICK_RATE = ~33ms): most groups share Config.SOUND_ID as their
	-- default, so this gate sees the whole board as one asset, and any value
	-- close to or above the tick period started swallowing ordinary fast
	-- typing across DIFFERENT keys landing on consecutive ticks — that was
	-- the "barely hear it" regression, not a volume problem. 15ms only merges
	-- presses detected in the SAME tick (overlapping hitboxes, a foot
	-- covering two caps at once), which is the one case this exists for.
	SOUND_MIN_INTERVAL = 0.015,

	-- Logs of keys arriving/leaving (streaming). Off by default: the per-key
	-- log calls GetFullName() and prints once per key, which on a board of
	-- several thousand is seconds of startup on its own. Turn on to diagnose
	-- streaming, not to leave on.
	DEBUG = false,

	-- Points system. Toggled from the plugin panel's "Others" section, stored
	-- in RuntimeSource.Settings ("PointsEnabled"), read by both Client and
	-- Server here.
	SETTINGS_FOLDER = "KeyCapperSettings",
	POINTS_REMOTE = "PointsRemote",
	POINTS_DATASTORE = "KeyCapperPoints_v1",
	POINTS_DATA_FOLDER = "KeyCapperData",
	POINTS_VALUE_NAME = "Points",
	-- How often the client flushes its pending point count to the server.
	-- Batched rather than fired per key press: at TICK_RATE=30 a fast typist
	-- could otherwise fire dozens of remote events a second.
	POINTS_BATCH_INTERVAL = 1,
	-- We trust the client's reported delta (no server-side proof a key was
	-- actually pressed) — this clamp is the only guard against an obviously
	-- spoofed value: generously above what TICK_RATE could produce in one
	-- batch interval, but far below anything worth spoofing for.
	POINTS_MAX_PER_BATCH = 60,

	-- Played by PointsUI when a "+1" popup lands in the counter. A plain
	-- Config field (not baked into PointsUI) so a technical dev can swap the
	-- asset without touching the module.
	POINTS_LAND_SOUND_ID = "rbxassetid://128538570525273",
	POINTS_LAND_SOUND_VOLUME = 0.4,

	-- Public event name: fired by Client.lua on every local key press,
	-- regardless of the points system being on. A technical dev listens with
	-- ReplicatedStorage.KeyCapper.KeyPressed.Event:Connect(function(model, letter) ... end).
	KEY_PRESSED_EVENT = "KeyPressed",
}
