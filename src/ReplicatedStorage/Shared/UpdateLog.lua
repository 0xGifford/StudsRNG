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
		Version = "1.4",
		Date = "Oct 29, 2026",
		Title = "50 Zones",
		Notes = {
			"43 new zones, from the Desert to Keyboard Kingdom: 50 in all.",
			"Every zone is rebuilt brick by brick, with its own sky, fog and gravity.",
			"Zones flow straight into each other: walk up to the next gate to see its price and buy it.",
			"Enemies roam every zone and hunt you down: your studs break off, swarm them and dash in for Clacks, then move on to the next enemy nearby.",
			"Rare Mini Bosses: crowned, tougher and far more rewarding.",
			"Studs now have Strength and Health, and come in Base, Big, Huge, Jumbo, Shiny and Inverted.",
			"A brand new Stud Index: one tab per variant, stud stats, roll counts and a reward for every completed tab.",
		},
	},
	{
		Version = "1.3",
		Date = "Oct 28, 2026",
		Title = "The Biomes Update",
		Notes = {
			"The map is rebuilt: seven biome valleys walled in by cliffs, joined by canyon passes.",
			"Zones are now Grasslands, Beach, Polar, Volcano, Islands, Cave and Heaven. Your unlocks carry over.",
			"Two new zones, Islands and Cave, each with four new zone studs.",
			"The Teleporter: numbered zone list with one-tap teleports.",
			"Zone gates show the next zone's price with a Buy button right on the gate.",
		},
	},
	{
		Version = "1.2",
		Date = "Oct 28, 2026",
		Title = "The Big Juice Update",
		Notes = {
			"A brand new map: five themed islands, from the Office to low-gravity Space.",
			"Combo meter: keep pressing keys to build up to +50% Clacks.",
			"Daily Quests: three new quests every day.",
			"Welcome back bonus: earn Clacks while you're away.",
			"Glowing +1 tiles appear on random keys: step on them for free rolls.",
			"A first-join tour and tutorial, plus way more effects everywhere.",
			"Brand new roll: a spinning reel over your head, AUTO and HIDE buttons, and a cleaner HUD with Roll at the bottom.",
		},
	},
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
