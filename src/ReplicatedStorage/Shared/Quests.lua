--[[

Quests
ModuleScript
/ReplicatedStorage/Shared/Quests

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Daily quests: every UTC day each player gets Quests.PerDay quests drawn
-- from the pool (one per Kind, seeded by day + UserId so a rejoin draws
-- the same set). Progress kinds are reported by server systems:
--   Press  key presses        Roll  studs rolled      Earn  Clacks earned
--   Tiles  reward tiles       Rare  1-in-1,000+ rolls  Upgrade levels bought
-- Earn targets and Clacks rewards scale with Rewards.scale (progress).

local Types = require(script.Parent.Types)

type Reward = Types.Reward

export type QuestDef = {
	Id: string,
	Kind: string,
	Target: number,
	Text: string, -- "{n}" is replaced by the (scaled) target
	Reward: Reward,
}

local pool: { QuestDef } = {
	{ Id = "Press300", Kind = "Press", Target = 300, Text = "Press {n} keys", Reward = { Kind = "FreeRolls", Amount = 5 } },
	{ Id = "Press1000", Kind = "Press", Target = 1000, Text = "Press {n} keys", Reward = { Kind = "Spins", Amount = 1 } },
	{ Id = "Roll25", Kind = "Roll", Target = 25, Text = "Roll {n} studs", Reward = { Kind = "Clacks", Amount = 5_000 } },
	{ Id = "Roll100", Kind = "Roll", Target = 100, Text = "Roll {n} studs", Reward = { Kind = "Boost", Amount = 1, Boost = "Luck", Minutes = 10 } },
	{ Id = "Earn", Kind = "Earn", Target = 20_000, Text = "Earn {n} Clacks", Reward = { Kind = "FreeRolls", Amount = 10 } },
	{ Id = "Tiles5", Kind = "Tiles", Target = 5, Text = "Grab {n} +1 tiles", Reward = { Kind = "Boost", Amount = 1, Boost = "Clacks", Minutes = 10 } },
	{ Id = "Rare1", Kind = "Rare", Target = 1, Text = "Roll a 1 in 1,000+ stud", Reward = { Kind = "Spins", Amount = 2 } },
	{ Id = "Upgrade3", Kind = "Upgrade", Target = 3, Text = "Buy {n} upgrade levels", Reward = { Kind = "Boost", Amount = 1, Boost = "Speed", Minutes = 10 } },
}

local byId: { [string]: QuestDef } = {}
for _, def in pool do
	assert(not byId[def.Id], `Duplicate quest id {def.Id}`)
	byId[def.Id] = def
end

local Quests = {
	Pool = pool,
	ById = byId,
	PerDay = 3,
	RareOneIn = 1000,
}

-- Today's quest ids for a player (deterministic).
function Quests.draw(day: number, userId: number): { string }
	local rng = Random.new(day * 7919 + userId % 1_000_003)
	local shuffled = table.clone(pool)
	for i = #shuffled, 2, -1 do
		local j = rng:NextInteger(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	local ids: { string } = {}
	local kinds: { [string]: boolean } = {}
	for _, def in shuffled do
		if not kinds[def.Kind] then
			kinds[def.Kind] = true
			table.insert(ids, def.Id)
			if #ids >= Quests.PerDay then break end
		end
	end
	return ids
end

-- Target after scaling (Earn grows with progress).
function Quests.target(def: QuestDef, scale: number): number
	if def.Kind == "Earn" then
		return math.floor(def.Target * scale)
	end
	return def.Target
end

function Quests.text(def: QuestDef, target: number, formatNumber: (number) -> string): string
	return (string.gsub(def.Text, "{n}", formatNumber(target)))
end

return Quests
