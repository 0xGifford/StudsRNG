--[[

Achievements
ModuleScript
/ReplicatedStorage/Shared/Achievements

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Achievements: reach Target on a Stat to unlock one (Systems/Achievements
-- checks), get its Reward, and, when it has a Title, wear that title over
-- your head and in chat. Progress is computed from saved data, so the
-- client shows the same bars the server checks (Achievements.progress).
--
-- Stats: Presses, Rolls, Enemies, MiniBosses, Titans, Zones, Index,
--        Rebirths, BestRoll (1 in X), StudLevel (best stud), Clacks (lifetime)
--
-- Ids are saved in player data: never rename an Id once the game is live.

local Shared = script.Parent
local Types = require(Shared.Types)
local RollLogic = require(Shared.Util.RollLogic)

type Reward = Types.Reward

export type AchievementDef = {
	Id: string,
	Name: string,
	Text: string,
	Stat: string,
	Target: number,
	Reward: Reward,
	Title: string?,
	TitleColor: Color3?,
}

local GOLD = Color3.fromRGB(255, 205, 60)
local RED = Color3.fromRGB(255, 90, 80)
local PURPLE = Color3.fromRGB(190, 120, 255)
local CYAN = Color3.fromRGB(90, 220, 255)
local GREEN = Color3.fromRGB(120, 255, 140)

local list: { AchievementDef } = {
	-- Keys
	{ Id = "Press1k", Name = "Warming Up", Text = "Press 1,000 keys", Stat = "Presses", Target = 1_000, Reward = { Kind = "FreeRolls", Amount = 10 } },
	{ Id = "Press25k", Name = "Keysmith", Text = "Press 25,000 keys", Stat = "Presses", Target = 25_000, Reward = { Kind = "Spins", Amount = 2 }, Title = "Keysmith", TitleColor = CYAN },
	{ Id = "Press250k", Name = "Keyboard Warrior", Text = "Press 250,000 keys", Stat = "Presses", Target = 250_000, Reward = { Kind = "Luck", Amount = 1 }, Title = "Keyboard Warrior", TitleColor = CYAN },
	-- Rolls
	{ Id = "Roll100", Name = "Feeling Lucky", Text = "Roll 100 studs", Stat = "Rolls", Target = 100, Reward = { Kind = "Clacks", Amount = 5_000 } },
	{ Id = "Roll1k", Name = "Roller", Text = "Roll 1,000 studs", Stat = "Rolls", Target = 1_000, Reward = { Kind = "Spins", Amount = 2 }, Title = "Roller", TitleColor = GREEN },
	{ Id = "Roll10k", Name = "High Roller", Text = "Roll 10,000 studs", Stat = "Rolls", Target = 10_000, Reward = { Kind = "Luck", Amount = 1 }, Title = "High Roller", TitleColor = GREEN },
	-- Combat
	{ Id = "Enemy10", Name = "First Blood", Text = "Defeat 10 enemies", Stat = "Enemies", Target = 10, Reward = { Kind = "FreeRolls", Amount = 10 } },
	{ Id = "Enemy250", Name = "Hunter", Text = "Defeat 250 enemies", Stat = "Enemies", Target = 250, Reward = { Kind = "Spins", Amount = 2 }, Title = "Hunter", TitleColor = RED },
	{ Id = "Enemy2500", Name = "Slayer", Text = "Defeat 2,500 enemies", Stat = "Enemies", Target = 2_500, Reward = { Kind = "Luck", Amount = 1 }, Title = "Slayer", TitleColor = RED },
	{ Id = "Boss1", Name = "Giant Killer", Text = "Defeat a Mini Boss", Stat = "MiniBosses", Target = 1, Reward = { Kind = "Boost", Amount = 1, Boost = "Luck", Minutes = 15 } },
	{ Id = "Boss25", Name = "Boss Breaker", Text = "Defeat 25 Mini Bosses", Stat = "MiniBosses", Target = 25, Reward = { Kind = "Spins", Amount = 3 }, Title = "Boss Breaker", TitleColor = GOLD },
	{ Id = "Titan1", Name = "Titan Slayer", Text = "Help defeat a Zone Boss Titan", Stat = "Titans", Target = 1, Reward = { Kind = "Spins", Amount = 3 }, Title = "Titan Slayer", TitleColor = RED },
	{ Id = "Titan10", Name = "Titan Bane", Text = "Help defeat 10 Titans", Stat = "Titans", Target = 10, Reward = { Kind = "Luck", Amount = 2 }, Title = "Titan Bane", TitleColor = RED },
	{ Id = "Level10", Name = "Trainer", Text = "Get a stud to Lv 10", Stat = "StudLevel", Target = 10, Reward = { Kind = "FreeRolls", Amount = 25 } },
	{ Id = "Level50", Name = "Stud Master", Text = "Get a stud to Lv 50", Stat = "StudLevel", Target = 50, Reward = { Kind = "Luck", Amount = 2 }, Title = "Stud Master", TitleColor = GOLD },
	-- Exploring
	{ Id = "Zones5", Name = "Explorer", Text = "Own 5 zones", Stat = "Zones", Target = 5, Reward = { Kind = "Clacks", Amount = 25_000 } },
	{ Id = "Zones10", Name = "Pathfinder", Text = "Own 10 zones", Stat = "Zones", Target = 10, Reward = { Kind = "FreeRolls", Amount = 25 } },
	{ Id = "Zones20", Name = "Voyager", Text = "Own 20 zones", Stat = "Zones", Target = 20, Reward = { Kind = "Spins", Amount = 3 }, Title = "Voyager", TitleColor = CYAN },
	{ Id = "Zones30", Name = "Trailblazer", Text = "Own 30 zones", Stat = "Zones", Target = 30, Reward = { Kind = "Spins", Amount = 5 } },
	{ Id = "Zones50", Name = "World Walker", Text = "Own all 34 zones", Stat = "Zones", Target = 34, Reward = { Kind = "Luck", Amount = 3 }, Title = "World Walker", TitleColor = CYAN },
	-- Collecting
	{ Id = "Index25", Name = "Collector", Text = "Find 25 Index entries", Stat = "Index", Target = 25, Reward = { Kind = "FreeRolls", Amount = 15 } },
	{ Id = "Index100", Name = "Curator", Text = "Find 100 Index entries", Stat = "Index", Target = 100, Reward = { Kind = "Spins", Amount = 3 }, Title = "Curator", TitleColor = PURPLE },
	{ Id = "Index250", Name = "Archivist", Text = "Find 250 Index entries", Stat = "Index", Target = 250, Reward = { Kind = "Luck", Amount = 2 }, Title = "Archivist", TitleColor = PURPLE },
	{ Id = "Rare10k", Name = "Lucky Break", Text = "Roll a 1 in 10,000", Stat = "BestRoll", Target = 10_000, Reward = { Kind = "Spins", Amount = 2 } },
	{ Id = "Rare100k", Name = "Fortune's Pet", Text = "Roll a 1 in 100,000", Stat = "BestRoll", Target = 100_000, Reward = { Kind = "Luck", Amount = 1 } },
	{ Id = "Rare1m", Name = "Chosen One", Text = "Roll a 1 in 1,000,000", Stat = "BestRoll", Target = 1_000_000, Reward = { Kind = "Luck", Amount = 2 }, Title = "Chosen One", TitleColor = PURPLE },
	-- Progress
	{ Id = "Rebirth1", Name = "Born Again", Text = "Rebirth once", Stat = "Rebirths", Target = 1, Reward = { Kind = "Spins", Amount = 2 } },
	{ Id = "Rebirth10", Name = "Reborn", Text = "Rebirth 10 times", Stat = "Rebirths", Target = 10, Reward = { Kind = "Luck", Amount = 2 }, Title = "Reborn", TitleColor = GOLD },
	{ Id = "Rare100m", Name = "Myth Maker", Text = "Roll a 1 in 100,000,000", Stat = "BestRoll", Target = 100_000_000, Reward = { Kind = "Luck", Amount = 5 }, Title = "Myth Maker", TitleColor = PURPLE },
	{ Id = "Index500", Name = "Curator", Text = "Find 500 Index entries", Stat = "Index", Target = 500, Reward = { Kind = "Luck", Amount = 4 }, Title = "Curator", TitleColor = PURPLE },
	{ Id = "Rebirth5", Name = "Second Wind", Text = "Rebirth 5 times", Stat = "Rebirths", Target = 5, Reward = { Kind = "Spins", Amount = 3 } },
	{ Id = "Rebirth25", Name = "Phoenix", Text = "Rebirth 25 times", Stat = "Rebirths", Target = 25, Reward = { Kind = "Luck", Amount = 4 }, Title = "Phoenix", TitleColor = GOLD },
	{ Id = "Clacks1m", Name = "Millionaire", Text = "Earn 1M Clacks in total", Stat = "Clacks", Target = 1e6, Reward = { Kind = "FreeRolls", Amount = 20 } },
	{ Id = "Clacks1b", Name = "Tycoon", Text = "Earn 1B Clacks in total", Stat = "Clacks", Target = 1e9, Reward = { Kind = "Luck", Amount = 2 }, Title = "Tycoon", TitleColor = GOLD },
	{ Id = "Clacks1t", Name = "Magnate", Text = "Earn 1T Clacks in total", Stat = "Clacks", Target = 1e12, Reward = { Kind = "Luck", Amount = 3 }, Title = "Magnate", TitleColor = GOLD },
	{ Id = "Clacks1qa", Name = "Clack Emperor", Text = "Earn 1 quadrillion Clacks in total", Stat = "Clacks", Target = 1e15, Reward = { Kind = "Luck", Amount = 5 }, Title = "Clack Emperor", TitleColor = GOLD },
}

local byId: { [string]: AchievementDef } = {}
for _, def in list do
	assert(not byId[def.Id], `Duplicate achievement id {def.Id}`)
	byId[def.Id] = def
end

local Achievements = {
	List = list,
	ById = byId,
}

local function count(set: any): number
	local n = 0
	if typeof(set) == "table" then
		for _, value in set do
			if value == true then n += 1 end
		end
	end
	return n
end

local function bestLevel(xp: any): number
	local best = 1
	if typeof(xp) == "table" then
		for _, amount in xp do
			best = math.max(best, RollLogic.levelOf(amount))
		end
	end
	return best
end

local STATS: { [string]: (data: any) -> number } = {
	Presses = function(data) return data.TotalPresses or 0 end,
	Rolls = function(data) return data.TotalRolls or 0 end,
	Enemies = function(data) return data.EnemiesDefeated or 0 end,
	MiniBosses = function(data) return data.BossesDefeated or 0 end,
	Titans = function(data) return data.TitansDefeated or 0 end,
	Zones = function(data) return count(data.UnlockedWorlds) end,
	Index = function(data) return if typeof(data.Index) == "table" then RollLogic.countIndex(data.Index) else 0 end,
	Rebirths = function(data) return data.Rebirths or 0 end,
	BestRoll = function(data) return data.BestRoll or 0 end,
	StudLevel = function(data) return bestLevel(data.StudXP) end,
	Clacks = function(data) return data.LifetimeClacks or 0 end,
}

-- How far along a player is (can exceed Target).
function Achievements.progress(def: AchievementDef, data: any): number
	local stat = STATS[def.Stat]
	return if stat then stat(data) else 0
end

return Achievements
