--[[

UpgradeShop
ModuleScript
/ServerScriptService/Server/Systems/UpgradeShop

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Buys upgrade tree levels with Clacks (BuyUpgrade remote). Levels live in
-- PlayerData.Upgrades and feed Modifiers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Upgrades = require(Shared.Upgrades)
local Signal = require(Shared.Util.Signal)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local Modifiers = require(Systems.Modifiers)
local Economy = require(Systems.Economy)

type Response = Types.Response

local UpgradeShop = {}

-- (player, upgradeId, newLevel)
UpgradeShop.Bought = Signal.new() :: Signal.Signal<Player, string, number>

function UpgradeShop.buy(player: Player, id: string): Response
	local data = PlayerData.get(player)
	if not data then return { Ok = false, Error = "NotLoaded" } end
	local def = Upgrades.ById[id]
	if not def then return { Ok = false, Error = "InvalidUpgrade" } end

	local level = Upgrades.level(data.Upgrades, id)
	if level >= def.MaxLevel then return { Ok = false, Error = "MaxLevel" } end
	if not Upgrades.isUnlocked(def, data.Upgrades) then return { Ok = false, Error = "UpgradeLocked" } end

	local cost = Upgrades.cost(def, level)
	if not Economy.spendClacks(player, cost) then return { Ok = false, Error = "NotEnoughClacks" } end

	data.Upgrades[id] = level + 1
	StateSync.push(player, "Upgrades", data.Upgrades)
	Modifiers.invalidate(player)
	UpgradeShop.Bought:Fire(player, id, level + 1)
	return { Ok = true, Level = level + 1 }
end

-- Dev: max every node.
function UpgradeShop.maxAll(player: Player)
	local data = PlayerData.get(player)
	if not data then return end
	for _, def in Upgrades.List do
		data.Upgrades[def.Id] = def.MaxLevel
	end
	StateSync.push(player, "Upgrades", data.Upgrades)
	Modifiers.invalidate(player)
end

function UpgradeShop.init()
	Net.handle("BuyUpgrade", { Rate = 6, Burst = 8 }, function(player, id)
		if typeof(id) ~= "string" or #id > 32 then
			return { Ok = false, Error = "InvalidUpgrade" }
		end
		return UpgradeShop.buy(player, id)
	end)
end

return UpgradeShop
