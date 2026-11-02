--[[ 

Session
ModuleScript
/ServerScriptService/Server/Systems/Session

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Answers GetSnapshot: the client's full starting state on join (and after
-- any desync). Incremental changes then arrive as StateSync patches.
-- Also records which update log version the player has read.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local UpdateLog = require(Shared.UpdateLog)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)

local Session = {}

-- Fields sent to the client. Anything not listed stays server-only.
local CLIENT_FIELDS = {
	"Clacks",
	"LifetimeClacks",
	"TotalPresses",
	"FreeRolls",
	"RollMeter",
	"TotalRolls",
	"Studs",
	"Equipped",
	"Index",
	"AutoDelete",
	"UnlockedWorlds",
	"Rebirths",
	"Upgrades",
	"LuckyRolls",
	"Boosts",
	"Spins",
	"Daily",
	"SeenUpdate",
	"SeenIntro",
	"Tutorial",
	"Quests",
	"TilesClaimed",
	"LuckyMeter",
	"IndexClaims",
	"RollCounts",
	"EnemiesDefeated",
	"StudXP",
	"BestRoll",
	"BossesDefeated",
	"TitansDefeated",
	"Achievements",
	"Title",
	"Pass",
	"Bought",
}

function Session.init()
	Net.handle("GetSnapshot", { Rate = 0.5, Burst = 3 }, function(player)
		local data = PlayerData.waitFor(player, 30)
		if not data then
			return { Ok = false, Error = "NotLoaded" }
		end

		-- Flush first so the snapshot's Seq covers everything already sent.
		local seq = StateSync.flush(player)

		local snapshot = {}
		for _, field in CLIENT_FIELDS do
			snapshot[field] = (data :: any)[field]
		end
		for field, value in StateSync.getVolatile(player) do
			snapshot[field] = value
		end
		return { Ok = true, Seq = seq, Data = snapshot }
	end)

	Net.handle("MarkUpdateSeen", { Rate = 0.5, Burst = 2 }, function(player)
		local data = PlayerData.get(player)
		if not data then return { Ok = false, Error = "NotLoaded" } end
		data.SeenUpdate = UpdateLog.Latest
		StateSync.push(player, "SeenUpdate", data.SeenUpdate)
		return { Ok = true }
	end)
end

return Session
