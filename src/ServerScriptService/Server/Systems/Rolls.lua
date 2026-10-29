--[[ 

Rolls
ModuleScript
/ServerScriptService/Server/Systems/Rolls

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The roll. Client asks Roll(count, useFree); the server checks cooldown and
-- payment, rolls stud + variant with the player's luck, grants through
-- Inventory, and answers with the results for the reveal animation.
--
-- One paid/free roll gives Stats.StudsPerRoll studs (Double Roll pass) plus
-- a Stats.ExtraRollChance chance of one more (Multi Roll upgrade).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local RollLogic = require(Shared.Util.RollLogic)
local Signal = require(Shared.Util.Signal)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local Inventory = require(Systems.Inventory)
local Economy = require(Systems.Economy)
local Modifiers = require(Systems.Modifiers)

type RollResult = Types.RollResult
type Response = Types.Response

local Rolls = {}

-- (player, results) after any roll grants studs
Rolls.Rolled = Signal.new() :: Signal.Signal<Player, { RollResult }>

local rng = Random.new()
local lastRoll: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}

function Rolls.getLuck(player: Player): number
	return Modifiers.get(player).Luck
end

-- Rolls `count` studs for a player WITHOUT payment. Used by the remote
-- handler after it has charged, by the jackpot wheel (luckMultiplier) and by
-- dev commands.
function Rolls.rollFor(player: Player, count: number, luckMultiplier: number?): { RollResult }
	local data = PlayerData.get(player)
	if not data then return {} end
	local boost = luckMultiplier or 1

	local results: { RollResult } = {}
	for _ = 1, count do
		-- Stats are re-read per roll: a new index milestone mid-batch applies at once.
		local stats = Modifiers.get(player)
		local def = RollLogic.rollStud(rng, stats.Luck * boost, data.UnlockedWorlds)
		if not def then break end
		local variant = RollLogic.rollVariant(rng, stats.VariantLuck * boost, stats.VariantBoosts)

		local grant = Inventory.grant(player, def.Id, variant.Name)
		if grant then
			local oneIn = def.OneIn * variant.OneIn
			table.insert(results, {
				Id = def.Id,
				Variant = variant.Name,
				Key = grant.Key,
				OneIn = oneIn,
				New = grant.New,
				Kept = grant.Kept,
				Reason = grant.Reason,
			})

			if oneIn >= Config.Announce.ChannelMinOneIn then
				Net.fireAll("Announce", {
					Player = player.DisplayName,
					UserId = player.UserId,
					Id = def.Id,
					Variant = variant.Name,
					OneIn = oneIn,
				})
			end
		end
	end

	data.TotalRolls += #results
	StateSync.push(player, "TotalRolls", data.TotalRolls)
	if #results > 0 then
		-- Shown in the Index ("Rolls: 23").
		for _, result in results do
			local key = RollLogic.encodeKey(result.Id, result.Variant)
			data.RollCounts[key] = (data.RollCounts[key] or 0) + 1
		end
		StateSync.push(player, "RollCounts", data.RollCounts)
	end
	if #results > 0 then
		Rolls.Rolled:Fire(player, results)
	end
	return results
end

local function handleRoll(player: Player, count: unknown, useFree: unknown): Response
	-- TYPE + RANGE
	if typeof(count) ~= "number" or typeof(useFree) ~= "boolean" then
		return { Ok = false, Error = "InvalidArgs" }
	end
	local n = count :: number
	if n ~= n or n ~= math.floor(n) or n < 1 or n > Config.Rolls.MaxBatch then
		return { Ok = false, Error = "InvalidArgs" }
	end

	-- STATE
	local data = PlayerData.get(player)
	if not data then return { Ok = false, Error = "NotLoaded" } end
	if busy[player] then return { Ok = false, Error = "Busy" } end
	local stats = Modifiers.get(player)
	local now = os.clock()
	-- Small grace so network jitter doesn't reject a roll the client timed right.
	if now - (lastRoll[player] or 0) < stats.RollCooldown * 0.9 then
		return { Ok = false, Error = "Cooldown" }
	end

	-- PAYMENT
	local cost = stats.RollCost * n
	if useFree then
		if not Economy.spendFreeRolls(player, n) then
			return { Ok = false, Error = "NoFreeRolls" }
		end
	else
		if not Economy.spendClacks(player, cost) then
			return { Ok = false, Error = "NotEnoughClacks" }
		end
	end

	-- Studs this request gives: per-roll count plus Multi Roll chances.
	local studs = 0
	for _ = 1, n do
		studs += stats.StudsPerRoll
		if stats.ExtraRollChance > 0 and rng:NextNumber() < stats.ExtraRollChance then
			studs += 1
		end
	end

	busy[player] = true
	lastRoll[player] = now
	local ok, results = pcall(Rolls.rollFor, player, studs)
	busy[player] = nil

	if useFree then
		Economy.settleMeter(player)
	end

	if not ok then
		warn(`[Rolls] roll failed for {player.Name}: {results}`)
		-- Refund: a server bug shouldn't cost the player their roll.
		if useFree then
			Economy.addFreeRolls(player, n, true)
		else
			Economy.addClacks(player, cost)
		end
		return { Ok = false, Error = "ServerError" }
	end

	-- Send state before the response so the client's numbers line up with
	-- the reveal.
	StateSync.flush(player)
	return { Ok = true, Results = results }
end

function Rolls.init()
	Net.handle("Roll", { Rate = 6, Burst = 6 }, handleRoll)

	Players.PlayerRemoving:Connect(function(player)
		lastRoll[player] = nil
		busy[player] = nil
	end)
end

return Rolls
