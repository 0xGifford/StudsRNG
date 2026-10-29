--[[

RewardService
ModuleScript
/ServerScriptService/Server/Systems/RewardService

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Daily streak (ClaimDaily), session playtime rewards (ClaimPlaytime) and
-- the jackpot wheel (SpinWheel). Reward tables live in Shared/Rewards.
--
-- Playtime is per session: the client gets the volatile "Playtime" field
-- ({ Start = server time, Claimed = { [index] = true } }) and leaving resets it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local RewardDefs = require(Shared.Rewards)
local Signal = require(Shared.Util.Signal)
local RollLogic = require(Shared.Util.RollLogic)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local Modifiers = require(Systems.Modifiers)
local Economy = require(Systems.Economy)
local Boosts = require(Systems.Boosts)
local Rolls = require(Systems.Rolls)
local Inventory = require(Systems.Inventory)

type Response = Types.Response
type Reward = Types.Reward

local RewardService = {}

-- (player) after each daily reward claim (Systems/StudPass)
RewardService.DailyClaimed = Signal.new() :: Signal.Signal<Player>

type Session = { Start: number, Claimed: { [number]: boolean } }
local sessions: { [Player]: Session } = {}
local rng = Random.new()

--------------------------------------------------------------------------
-- Grants (also used by Products)
--------------------------------------------------------------------------

function RewardService.addSpins(player: Player, amount: number)
	local data = PlayerData.get(player)
	if not data or amount <= 0 then return end
	data.Spins += math.floor(amount)
	StateSync.push(player, "Spins", data.Spins)
end

function RewardService.addLuck(player: Player, amount: number)
	local data = PlayerData.get(player)
	if not data or amount <= 0 then return end
	data.LuckyRolls += math.floor(amount)
	StateSync.push(player, "LuckyRolls", data.LuckyRolls)
	Modifiers.invalidate(player)
end

-- Applies one reward. Returns what was actually given (Clacks after
-- scaling, MegaRoll results) so the client can show it.
function RewardService.grant(player: Player, reward: Reward): { [string]: any }
	local data = PlayerData.get(player)
	if not data then return {} end
	local given: { [string]: any } = { Kind = reward.Kind, Amount = reward.Amount, Boost = reward.Boost, Minutes = reward.Minutes }

	if reward.Kind == "Clacks" then
		local amount = math.floor(reward.Amount * RewardDefs.scale(data))
		Economy.addClacks(player, amount)
		given.Amount = amount
	elseif reward.Kind == "FreeRolls" then
		Economy.addFreeRolls(player, reward.Amount, true)
	elseif reward.Kind == "Spins" then
		RewardService.addSpins(player, reward.Amount)
	elseif reward.Kind == "Boost" then
		local boost = reward.Boost
		if boost then
			Boosts.add(player, boost, (reward.Minutes or Config.Boosts[boost].Duration / 60) * 60)
		end
	elseif reward.Kind == "Luck" then
		RewardService.addLuck(player, reward.Amount)
	elseif reward.Kind == "MegaRoll" then
		given.Results = Rolls.rollFor(player, 1, reward.Amount)
	elseif reward.Kind == "Stud" then
		local def, variant = RollLogic.decodeKey(reward.Stud)
		assert(def and variant, `bad stud reward {reward.Stud}`)
		local grant = Inventory.grant(player, def.Id, variant.Name)
		given.Results = if grant then { {
			Id = def.Id,
			Variant = variant.Name,
			Key = grant.Key,
			OneIn = def.OneIn * variant.OneIn,
			New = grant.New,
			Kept = grant.Kept,
			Reason = grant.Reason,
		} } else nil
	elseif reward.Kind == "Bundle" then
		local items: { { [string]: any } } = {}
		local bundle: { Reward } = reward.Items or {}
		for _, item in bundle do
			local itemGiven = RewardService.grant(player, item)
			table.insert(items, itemGiven)
			if itemGiven.Results then
				given.Results = itemGiven.Results
			end
		end
		given.Items = items
	else
		warn(`[RewardService] unknown reward kind {reward.Kind}`)
	end
	return given
end

--------------------------------------------------------------------------
-- Daily
--------------------------------------------------------------------------

local function claimDaily(player: Player): Response
	local data = PlayerData.get(player)
	if not data then return { Ok = false, Error = "NotLoaded" } end
	local today = RewardDefs.dayNumber(os.time())
	local canClaim, day = RewardDefs.dailyState(data.Daily, today)
	if not canClaim then return { Ok = false, Error = "AlreadyClaimed" } end

	local weeks = RewardDefs.weeksAfterClaim(data.Daily, today, day)
	data.Daily = { Streak = day, LastDay = today, Weeks = weeks }
	StateSync.push(player, "Daily", data.Daily)
	local given = RewardService.grant(player, RewardDefs.dailyReward(day, weeks))
	RewardService.DailyClaimed:Fire(player)
	return { Ok = true, Day = day, Weeks = weeks, Reward = given }
end

--------------------------------------------------------------------------
-- Playtime
--------------------------------------------------------------------------

local function syncPlaytime(player: Player)
	local session = sessions[player]
	if session then
		StateSync.setVolatile(player, "Playtime", { Start = session.Start, Claimed = session.Claimed })
	end
end

local function claimPlaytime(player: Player, index: number): Response
	local session = sessions[player]
	local reward = RewardDefs.Playtime[index]
	if not session or not PlayerData.get(player) then return { Ok = false, Error = "NotLoaded" } end
	if not reward then return { Ok = false, Error = "InvalidReward" } end
	if session.Claimed[index] then return { Ok = false, Error = "AlreadyClaimed" } end
	-- 2s grace for clock drift between the client's countdown and ours.
	if workspace:GetServerTimeNow() - session.Start + 2 < reward.At * 60 then
		return { Ok = false, Error = "NotReady" }
	end

	session.Claimed[index] = true
	syncPlaytime(player)
	return { Ok = true, Index = index, Reward = RewardService.grant(player, reward) }
end

-- SkipPlaytime product: every unclaimed playtime reward, now.
function RewardService.skipPlaytime(player: Player)
	local session = sessions[player]
	if not session then return end
	for index, reward in RewardDefs.Playtime do
		if not session.Claimed[index] then
			session.Claimed[index] = true
			RewardService.grant(player, reward)
		end
	end
	syncPlaytime(player)
end

--------------------------------------------------------------------------
-- Wheel
--------------------------------------------------------------------------

local function pickPrize(): number
	local roll = rng:NextNumber() * RewardDefs.wheelTotalWeight()
	for index, prize in RewardDefs.Wheel do
		roll -= prize.Weight
		if roll < 0 then
			return index
		end
	end
	return #RewardDefs.Wheel
end

local function spinWheel(player: Player): Response
	local data = PlayerData.get(player)
	if not data then return { Ok = false, Error = "NotLoaded" } end
	if data.Spins < 1 then return { Ok = false, Error = "NoSpins" } end

	data.Spins -= 1
	StateSync.push(player, "Spins", data.Spins)
	local index = pickPrize()
	local given = RewardService.grant(player, RewardDefs.Wheel[index])
	StateSync.flush(player)
	return { Ok = true, Index = index, Reward = given }
end

--------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------

function RewardService.init()
	Net.handle("ClaimDaily", { Rate = 0.5, Burst = 2 }, claimDaily)

	Net.handle("ClaimPlaytime", { Rate = 4, Burst = 6 }, function(player, index)
		if typeof(index) ~= "number" or index ~= math.floor(index) then
			return { Ok = false, Error = "InvalidReward" }
		end
		return claimPlaytime(player, index)
	end)

	Net.handle("SpinWheel", { Rate = 1, Burst = 2 }, spinWheel)

	PlayerData.Loaded:Connect(function(player)
		sessions[player] = { Start = workspace:GetServerTimeNow(), Claimed = {} }
		syncPlaytime(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
end

return RewardService
