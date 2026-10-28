--[[

UpdateLog
ModuleScript
/ReplicatedStorage/Shared/UpdateLog

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Shown in the Updates menu (TopbarPlus icon), newest first. Add a new entry
-- at the TOP for every update: players who haven't opened the newest
-- Version yet get a notification dot on the icon.

export type Entry = {
	Version: string,
	Date: string,
	Title: string,
	Notes: { string },
}

local entries: { Entry } = {
	{
		Version = "1.1",
		Date = "Oct 28, 2026",
		Title = "Zones, Upgrades & Shop",
		Notes = {
			"Zones! Buy the Arcade, Studio, Neon City and Space with Clacks. Keys there pay more and each zone has its own studs.",
			"Upgrade tree: spend Clacks on permanent upgrades. Drag to look around, tap a node to buy it.",
			"Rebirth for a permanent Clacks and luck multiplier.",
			"Shop: game passes, boosts, Lucky Rolls, jackpot spins and Clack packs.",
			"Jackpot wheel, daily streak rewards and playtime rewards.",
			"Global events every 20 minutes, friend boost and Premium boost.",
		},
	},
	{
		Version = "1.0",
		Date = "Oct 2026",
		Title = "Release",
		Notes = {
			"Walk the keyboard to earn Clacks and free rolls.",
			"Roll studs, fill the index and equip your best studs.",
		},
	},
}

return {
	Entries = entries,
	Latest = entries[1].Version,
}
