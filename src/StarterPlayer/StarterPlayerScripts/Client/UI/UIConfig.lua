--[[ 

UIConfig
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/UI/UIConfig

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Client-only UI tunables. Features set to false are hidden from the HUD
-- until their backend exists; flip them on as each system lands.

return {
	Features = {
		Store = false,
		Rebirth = false,
		Rewards = false,
		Wheel = false,
		Daily = false,
		Boosts = false, -- FriendBoost / Premium / DailyRewards labels
		Events = false, -- "Next event" timer
	},

	BlurSize = 24,

	Reveal = {
		SpinTime = 1.1,
		HoldTime = 1.4,
		AutoSpinTime = 0.45,
		AutoHoldTime = 0.6,
		-- Results at or rarer than this (stud × variant odds) get a wind-up
		-- shake before landing.
		DramaOneIn = 1000,
	},

	Toast = {
		Duration = 2,
	},

	-- Friendly text for server error codes. Codes mapped to "" stay silent.
	Errors = {
		NotEnoughClacks = "Not enough Clacks",
		NoFreeRolls = "No free rolls left",
		SlotsFull = "All slots full, unequip a stud first",
		NotOwned = "You don't own that stud",
		NotEnough = "Not enough to fuse",
		MaxVariant = "Rainbow is the highest variant",
		InvalidStud = "That stud doesn't exist",
		NotLoaded = "Still loading your data…",
		NetworkError = "Connection hiccup, try again",
		ServerError = "Something went wrong, try again",
		Cooldown = "",
		Busy = "",
		RateLimited = "",
	} :: { [string]: string },
}
