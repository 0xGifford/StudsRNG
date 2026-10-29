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
		Version = "1.7",
		Date = "Oct 30, 2026",
		Title = "Bigger & Better",
		Notes = {
			"Rebalanced: zones are much quicker to unlock, and fights in your own zone are fast and winnable.",
			"Big, Huge and Jumbo studs are MUCH bigger; Shiny and Inverted studs glow with an outline.",
			"Rare drops: enemies can drop Big Roll and Shiny Roll boosts.",
			"A brand new Backpack, a new HUD layout, and names over your equipped studs.",
			"New combat upgrades: Sharp Studs, Tough Studs and Loot Luck.",
		},
	},
	{
		Version = "1.6",
		Date = "Oct 29, 2026",
		Title = "Season 1: Titans",
		Notes = {
			"The Stud Pass: 30 tiers of rewards for playing, with a premium track and two pass-exclusive studs.",
			"Enemies are brought to life: smooth movement, hopping feet, leaning, blinking, and red eyes when they hunt you.",
			"Smarter enemies: they route around obstacles and stop piling on top of each other.",
			"New: Starter Pack, Summon Mini Boss, Lucky Drops and Stud Trainer.",
		},
	},
	{
		Version = "1.5",
		Date = "Oct 29, 2026",
		Title = "Titans & Glory",
		Notes = {
			"Zone Boss Titans: every 20 minutes a Titan invades zones 10, 20, 30, 40 and 50. Fight it together; rewards by damage rank.",
			"Stud levels: equipped studs earn XP from every fight and get stronger, up to Lv 50.",
			"Boss drops: five studs you can't roll, only won from Mini Bosses and Titans.",
			"Achievements: 27 to unlock, with rewards and titles to wear over your head and in chat.",
			"Global leaderboards for Clacks, enemies defeated and rarest roll.",
			"Daily rewards: Day 7 is a jackpot, and every week you keep your streak boosts your rewards.",
			"A Rolls chat tab announcing every 1 in 100+ roll.",
			"More juice: barriers dissolve when you buy a zone, fusing celebrates, and the reel sometimes almost lands on something rarer...",
		},
	},
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
			"Fights hit harder: crits, hit flashes, trails, impact rings, and enemies burst into bricks and shower you with coins.",
			"Kill streaks: chain defeats for up to +190% Clacks.",
			"New daily quests: defeat enemies and take down a Mini Boss.",
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
