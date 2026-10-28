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
		if field ~= "Version" then
			StateSync.push(player, field, value)
		end
	end
	Inventory.refresh(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local clacks = leaderstats and leaderstats:FindFirstChild("Clacks")
	if clacks and clacks:IsA("NumberValue") then
		clacks.Value = math.floor(data.Clacks)
	end
end

local function run(player: Player, command: unknown, arg: unknown): any
	local amount = if typeof(arg) == "number" and arg == arg then math.clamp(math.floor(arg), 1, 1e12) else 1

	if command == "Clacks" then
		Economy.addClacks(player, amount)
	elseif command == "FreeRolls" then
		Economy.addFreeRolls(player, amount)
	elseif command == "Stud" then
		local def, variant = RollLogic.decodeKey(arg)
		if not def or not variant then return "bad key" end
		return Inventory.grant(player, def.Id, variant.Name)
	elseif command == "Roll" then
		return Rolls.rollFor(player, math.min(amount, 100))
	elseif command == "Reset" then
		PlayerData.reset(player)
		resync(player)
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
