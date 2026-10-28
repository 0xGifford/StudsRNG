--[[

Rebirth
ModuleScript
/ServerScriptService/Server/Systems/Rebirth

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Rebirth: costs RollLogic.rebirthCost(rebirths) Clacks, then resets Clacks
-- to 0 (and zones, if Config.Rebirth.ResetZones). Studs, the index,
-- upgrades, Lucky Rolls, spins and boosts are kept. Each rebirth adds a
-- permanent Clacks and luck multiplier (RollLogic.computeStats).
-- The SkipRebirth product rebirths without the Clacks requirement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local RollLogic = require(Shared.Util.RollLogic)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local Modifiers = require(Systems.Modifiers)
local Economy = require(Systems.Economy)
local ZoneShop = require(Systems.ZoneShop)

type Response = Types.Response

local Rebirth = {}

-- skipCost: the Robux skip (still resets, just doesn't need the Clacks).
function Rebirth.perform(player: Player, skipCost: boolean): Response
	local data = PlayerData.get(player)
	if not data then return { Ok = false, Error = "NotLoaded" } end

	if not skipCost then
		local cost = RollLogic.rebirthCost(data.Rebirths)
		if data.Clacks < cost then
			return { Ok = false, Error = "NotEnoughClacks" }
		end
	end

	data.Rebirths += 1
	Economy.setClacks(player, 0)
	if Config.Rebirth.ResetZones then
		ZoneShop.resetZones(player)
	end

	StateSync.push(player, "Rebirths", data.Rebirths)
	Economy.refreshLeaderstats(player)
	Modifiers.invalidate(player)

	local multiplier = string.gsub(string.format("%.2f", Modifiers.get(player).RebirthClacks), "%.?0+$", "")
	Net.fire(player, "Notify", {
		Text = `Rebirth {data.Rebirths}! Rebirth Clacks bonus is now x{multiplier}`,
		Color = Color3.fromRGB(255, 230, 90),
	})
	return { Ok = true, Rebirths = data.Rebirths }
end

function Rebirth.init()
	Net.handle("Rebirth", { Rate = 0.5, Burst = 2 }, function(player)
		return Rebirth.perform(player, false)
	end)
end

return Rebirth
