--[[

StudPass
ModuleScript
/ServerScriptService/Server/Systems/StudPass

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The Stud Pass (Shared/StudPass): points for defeats, Mini Bosses, Titans,
-- rolls, quests and daily rewards; ClaimPass(tier, premium) claims one
-- reward, ClaimPass(0) claims everything available. Premium rewards need
-- the StudPass game pass (Systems/Products). A new Season id resets
-- everyone's points and claims on their next load.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local PassDefs = require(Shared.StudPass)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local RewardService = require(Systems.RewardService)
local Products = require(Systems.Products)
local Combat = require(Systems.Combat)
local Rolls = require(Systems.Rolls)
local QuestService = require(Systems.QuestService)

type Response = Types.Response

local StudPass = {}

local POINTS = PassDefs.Points

-- The player's pass state for this season (reset when the season changed).
local function stateOf(player: Player): any
	local data = PlayerData.get(player)
	if not data then return nil end
	local pass = data.Pass
	if typeof(pass) ~= "table" or pass.Season ~= PassDefs.Season then
		pass = { Season = PassDefs.Season, Points = 0, Free = {}, Premium = {} }
		data.Pass = pass
		StateSync.push(player, "Pass", pass)
	end
	return pass
end

function StudPass.addPoints(player: Player, amount: number)
	local pass = stateOf(player)
	if not pass or amount <= 0 then return end
	local before = PassDefs.tierOf(pass.Points)
	pass.Points += math.floor(amount)
	StateSync.push(player, "Pass", pass)
	local after = PassDefs.tierOf(pass.Points)
	if after > before then
		Net.fire(player, "Notify", { Kind = "PassTier", Tier = after, Text = `Stud Pass tier {after} reached! Claim your rewards.`, Color = Color3.fromRGB(255, 205, 60) })
	end
end

local function claimOne(player: Player, pass: any, tier: number, premium: boolean): { [string]: any }?
	local key = tostring(tier)
	local claimed = if premium then pass.Premium else pass.Free
	if claimed[key] then return nil end
	claimed[key] = true
	local def = PassDefs.Tiers[tier]
	return RewardService.grant(player, if premium then def.Premium else def.Free)
end

local function claim(player: Player, tier: unknown, premium: unknown): Response
	if typeof(tier) ~= "number" or tier ~= math.floor(tier) or tier < 0 or tier > #PassDefs.Tiers then
		return { Ok = false, Error = "InvalidReward" }
	end
	local pass = stateOf(player)
	if not pass then return { Ok = false, Error = "NotLoaded" } end
	local reached = PassDefs.tierOf(pass.Points)
	local hasPremium = Products.ownsPass(player, "StudPass")
	local given = {}

	if tier == 0 then
		-- Everything available.
		for t = 1, reached do
			local free = claimOne(player, pass, t, false)
			if free then table.insert(given, free) end
			if hasPremium then
				local paid = claimOne(player, pass, t, true)
				if paid then table.insert(given, paid) end
			end
		end
		if #given == 0 then return { Ok = false, Error = "NothingToClaim" } end
	else
		if typeof(premium) ~= "boolean" then return { Ok = false, Error = "InvalidReward" } end
		if tier > reached then return { Ok = false, Error = "NotReady" } end
		if premium and not hasPremium then return { Ok = false, Error = "PassLocked" } end
		local reward = claimOne(player, pass, tier :: number, premium :: boolean)
		if not reward then return { Ok = false, Error = "AlreadyClaimed" } end
		table.insert(given, reward)
	end

	StateSync.push(player, "Pass", pass)
	return { Ok = true, Rewards = given }
end

function StudPass.init()
	Net.handle("ClaimPass", { Rate = 2, Burst = 5 }, claim)

	PlayerData.Loaded:Connect(function(player)
		stateOf(player) -- reset on a new season
	end)
	Combat.Defeated:Connect(function(player, boss, zoneBoss)
		StudPass.addPoints(player, if zoneBoss then POINTS.Titan elseif boss then POINTS.MiniBoss else POINTS.Defeat)
	end)
	Rolls.Rolled:Connect(function(player, results)
		StudPass.addPoints(player, #results * POINTS.Roll)
	end)
	QuestService.Claimed:Connect(function(player)
		StudPass.addPoints(player, POINTS.Quest)
	end)
	RewardService.DailyClaimed:Connect(function(player)
		StudPass.addPoints(player, POINTS.Daily)
	end)
end

return StudPass
