--[[ 

DevCommands
ModuleScript
/ServerScriptService/Server/Systems/DevCommands

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- QA commands. The remote ONLY exists in Studio: in a live server this module
-- does nothing at all. Uses the same API paths as real gameplay.
--
-- Commands: "Clacks" n | "FreeRolls" n | "Stud" "Id:Variant" | "Roll" n | "Reset"
--           "Rebirth" | "Zones" | "Upgrades" | "Boost" id | "Spins" n | "Luck" n
--           "ServerLuck" | "Event" id | "Intro" | "Tutorial" | "Quests"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local RollLogic = require(Shared.Util.RollLogic)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local Economy = require(Systems.Economy)
local Inventory = require(Systems.Inventory)
local Rolls = require(Systems.Rolls)
local Modifiers = require(Systems.Modifiers)
local Boosts = require(Systems.Boosts)
local ServerEffects = require(Systems.ServerEffects)
local UpgradeShop = require(Systems.UpgradeShop)
local ZoneShop = require(Systems.ZoneShop)
local Rebirth = require(Systems.Rebirth)
local RewardService = require(Systems.RewardService)

local DevCommands = {}

local function isAllowed(player: Player): boolean
	if not RunService:IsStudio() then return false end
	if player.UserId <= 0 then return true end -- Studio test players
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then return true end
	return table.find(Config.Dev.AllowedUserIds, player.UserId) ~= nil
end

local function resync(player: Player)
	local data = PlayerData.get(player)
	if not data then return end
	for field, value in data :: any do
		if field ~= "Version" and field ~= "PurchaseIds" then
			StateSync.push(player, field, value)
		end
	end
	Inventory.refresh(player)
	Economy.refreshLeaderstats(player)
	Modifiers.invalidate(player)
end

local function run(player: Player, command: unknown, arg: unknown): any
	local amount = if typeof(arg) == "number" and arg == arg then math.clamp(math.floor(arg), 1, 1e12) else 1

	if command == "Clacks" then
		Economy.addClacks(player, amount)
	elseif command == "FreeRolls" then
		Economy.addFreeRolls(player, amount, true)
	elseif command == "Stud" then
		local def, variant = RollLogic.decodeKey(arg)
		if not def or not variant then return "bad key" end
		return Inventory.grant(player, def.Id, variant.Name)
	elseif command == "Roll" then
		return Rolls.rollFor(player, math.min(amount, 100))
	elseif command == "Reset" then
		PlayerData.reset(player)
		resync(player)
	elseif command == "Rebirth" then
		return Rebirth.perform(player, true)
	elseif command == "Zones" then
		ZoneShop.unlockAll(player)
	elseif command == "Upgrades" then
		UpgradeShop.maxAll(player)
	elseif command == "Boost" then
		local id = if typeof(arg) == "string" then arg else ""
		local boost = Config.Boosts[id]
		if not boost then return "bad boost id" end
		Boosts.add(player, id, boost.Duration)
	elseif command == "Spins" then
		RewardService.addSpins(player, amount)
	elseif command == "Luck" then
		RewardService.addLuck(player, amount)
	elseif command == "ServerLuck" then
		ServerEffects.addServerLuck(player)
	elseif command == "Intro" or command == "Tutorial" or command == "Quests" then
		-- Replay the first-join flow / reroll quests (takes effect on rejoin).
		local data = PlayerData.get(player)
		if not data then return "not loaded" end
		if command == "Intro" then
			data.SeenIntro = false
		elseif command == "Tutorial" then
			data.Tutorial = 1
			StateSync.push(player, "Tutorial", 1)
		else
			data.Quests = { Day = -1, List = {} }
		end
	elseif command == "Event" then
		local id = if typeof(arg) == "string" then arg else ""
		if not ServerEffects.forceEvent(id, 120) then return "bad event id" end
	else
		return "unknown command"
	end
	return "ok"
end

function DevCommands.init()
	if not RunService:IsStudio() then return end

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = Instance.new("RemoteFunction")
	remote.Name = "DevCommand"
	remote.OnServerInvoke = function(player: Player, command: unknown, arg: unknown)
		if not isAllowed(player) then return nil end
		local ok, result = pcall(run, player, command, arg)
		return if ok then result else `error: {result}`
	end
	remote.Parent = remotes
end

return DevCommands
