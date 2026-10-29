--[[

UIConfig
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/UI/UIConfig

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Client-only UI tunables. Set a feature to false to hide its HUD entry.

return {
	Features = {
		Store = true,
		Rebirth = true,
		Rewards = true,
		Wheel = true,
		Upgrades = true,
		Zones = true,
		Quests = true,
		Boosts = true, -- FriendBoost / Premium / DailyRewards labels
		Events = true, -- active timers + "Next Event In"
	},

	-- Shows the "SALE!" tag on the Store button.
	StoreSale = false,

	BlurSize = 24,

	Reveal = {
		SpinTime = 1.1,
		HoldTime = 1.4,
		AutoSpinTime = 0.45,
		AutoHoldTime = 0.6,
		-- Results at or rarer than this (stud × variant odds) get a wind-up
		-- shake before landing.
		DramaOneIn = 1000,
		-- Manual rolls: chance a much rarer stud sits right past the result
		-- and the reel creeps towards it before settling ("SO CLOSE!").
		NearMissChance = 0.3,
	},

	Toast = {
		Duration = 2,
	},

	-- "+x Clacks" popups that fly from the player to the Clacks counter.
	ClackPopups = {
		Duration = 0.6,
		MaxInFlight = 12,
	},

	-- TopbarPlus icons (Settings and Updates replace HUD buttons).
	Topbar = {
		SettingsImage = "rbxassetid://131183305228792",
		UpdatesImage = "", -- empty = text label only
	},

	-- Images for reward / boost / event icons. Anything that isn't an
	-- rbxassetid:// is drawn as text (emoji).
	Icons = {
		Clacks = "rbxassetid://117187305699068",
		FreeRolls = "🎲",
		Spins = "rbxassetid://72974128962815",
		Luck = "🍀",
		MegaRoll = "🎰",
		Bundle = "🎁",
		Boost = "rbxassetid://131975246594329",
		Event = "rbxassetid://119611914627070",
		ServerLuck = "rbxassetid://119611914627070",
	} :: { [string]: string },

	-- Friendly text for server error codes. Codes mapped to "" stay silent.
	Errors = {
		NotEnoughClacks = "Not enough Clacks",
		NoFreeRolls = "No free rolls left",
		SlotsFull = "All slots full, unequip a stud first",
		NotOwned = "You don't own that stud",
		NotEnough = "Not enough to fuse",
		MaxVariant = "Jumbo is the biggest size (Shiny and Inverted can't be fused)",
		InvalidStud = "That stud doesn't exist",
		NotLoaded = "Still loading your data…",
		NetworkError = "Connection hiccup, try again",
		ServerError = "Something went wrong, try again",
		MaxLevel = "Already maxed",
		UpgradeLocked = "Buy the upgrade before it first",
		ZoneOrder = "Unlock the previous zone first",
		ZoneLocked = "You don't own that zone yet",
		AlreadyOwned = "You already own that",
		NoSpawn = "That zone has no spawn yet",
		NoCharacter = "",
		NoSpins = "No spins left",
		AlreadyClaimed = "Already claimed",
		NotReady = "Not ready yet",
		InvalidUpgrade = "",
		InvalidZone = "",
		InvalidReward = "",
		Cooldown = "",
		Busy = "",
		RateLimited = "",
		InvalidArgs = "",
		IndexIncomplete = "Find every stud in this tab first",
		EnemyGone = "",
		NoStuds = "Equip some studs to fight!",
		KnockedOut = "Your studs are still recovering",
		TooFar = "Get closer to fight",
		TitleLocked = "Unlock that achievement first",
	} :: { [string]: string },
}
