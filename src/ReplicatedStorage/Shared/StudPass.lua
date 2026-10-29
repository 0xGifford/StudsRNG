--[[

StudPass
ModuleScript
/ReplicatedStorage/Shared/StudPass

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The Stud Pass (a season pass). Playing earns Pass points (Points); every
-- PointsPerTier points is a tier. Each tier has a free reward and a premium
-- reward; premium rewards need the "StudPass" game pass (Shared/Products)
-- and can be claimed any time after buying, back to tier 1.
--
-- New season: change Season (everyone's points and claims reset) and,
-- optionally, the rewards. Ends is shown as a countdown (unix time, 0 = no
-- end date shown).

local Shared = script.Parent
local Types = require(Shared.Types)

type Reward = Types.Reward

export type Tier = { Free: Reward, Premium: Reward }

local StudPass = {
	Season = "S1",
	Name = "Season 1: Titans",
	Ends = 0,
	PointsPerTier = 120,
	-- What earns points (Systems/StudPass)
	Points = {
		Defeat = 6,
		MiniBoss = 40,
		Titan = 120,
		Roll = 1, -- per stud rolled
		Quest = 60,
		Daily = 80,
	},
	Tiers = {} :: { Tier },
}

-- Rewards climb with the tier; every 5th tier is a bigger one and tiers
-- 10 / 20 / 30 are milestones (luck, pass-exclusive studs, a jackpot roll).
for tier = 1, 30 do
	local free: Reward
	local premium: Reward
	if tier == 30 then
		free = { Kind = "Luck", Amount = 2 }
		premium = { Kind = "Bundle", Amount = 1, Items = {
			{ Kind = "Stud", Amount = 1, Stud = "PassChampion:Normal" },
			{ Kind = "MegaRoll", Amount = 1000 },
		} }
	elseif tier == 20 then
		free = { Kind = "Stud", Amount = 1, Stud = "PassTicket:Normal" }
		premium = { Kind = "Luck", Amount = 2 }
	elseif tier == 10 then
		free = { Kind = "Luck", Amount = 1 }
		premium = { Kind = "Bundle", Amount = 1, Items = {
			{ Kind = "Luck", Amount = 1 },
			{ Kind = "Spins", Amount = 5 },
		} }
	elseif tier == 25 then
		free = { Kind = "Spins", Amount = 3 }
		premium = { Kind = "MegaRoll", Amount = 500 }
	elseif tier % 5 == 0 then
		free = { Kind = "Spins", Amount = 2 }
		premium = { Kind = "Boost", Amount = 1, Boost = "UltraLuck", Minutes = 20 }
	elseif tier % 2 == 0 then
		free = { Kind = "Clacks", Amount = 2_000 * tier }
		premium = { Kind = "Spins", Amount = 2 }
	else
		free = { Kind = "FreeRolls", Amount = 5 + tier }
		premium = { Kind = "Boost", Amount = 1, Boost = if tier % 3 == 0 then "Clacks" else "Luck", Minutes = 15 }
	end
	StudPass.Tiers[tier] = { Free = free, Premium = premium }
end

function StudPass.tierOf(points: number): number
	return math.min(#StudPass.Tiers, math.floor(math.max(0, points) / StudPass.PointsPerTier))
end

return StudPass
