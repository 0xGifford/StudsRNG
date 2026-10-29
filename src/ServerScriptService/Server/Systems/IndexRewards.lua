--[[

IndexRewards
ModuleScript
/ServerScriptService/Server/Systems/IndexRewards

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Index tab rewards: once a player has found every stud in one variant
-- (Base, Big, Huge, Jumbo, Shiny, Inverted) they can claim that tab's
-- reward, once. Claimed tabs live in PlayerData.IndexClaims and add
-- Config.IndexTabReward luck and Clacks each (RollLogic.computeStats).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Variants = require(Shared.Variants)
local RollLogic = require(Shared.Util.RollLogic)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local Modifiers = require(Systems.Modifiers)

local IndexRewards = {}

function IndexRewards.claim(player: Player, variant: unknown): any
	if typeof(variant) ~= "string" or not table.find(Variants.Order, variant) then
		return { Ok = false, Error = "InvalidReward" }
	end
	local data = PlayerData.get(player)
	if not data then return { Ok = false, Error = "NotLoaded" } end
	if data.IndexClaims[variant :: string] then return { Ok = false, Error = "AlreadyClaimed" } end
	local found, total = RollLogic.tabProgress(data.Index, variant :: string)
	if found < total then return { Ok = false, Error = "IndexIncomplete" } end

	data.IndexClaims[variant :: string] = true
	StateSync.push(player, "IndexClaims", data.IndexClaims)
	Modifiers.invalidate(player)
	return { Ok = true }
end

function IndexRewards.init()
	Net.handle("ClaimIndexTab", { Rate = 1, Burst = 3 }, IndexRewards.claim)
end

return IndexRewards
