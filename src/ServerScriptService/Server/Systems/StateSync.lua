--[[ 

StateSync
ModuleScript
/ServerScriptService/Server/Systems/StateSync

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Replicates player state to its owner. Systems call StateSync.push(player,
-- field, value) whenever they change a top-level PlayerData field; pushes are
-- merged and flushed as one patch every Config.Sync.FlushInterval.
--
-- Patches carry an increasing Seq. The snapshot (Session.GetSnapshot)
-- carries the Seq it was taken at, so the client can drop patches it
-- already has and apply the ones that raced ahead of the snapshot.
--
-- Volatile fields (StateSync.setVolatile) are client state that isn't saved
-- (computed Stats, owned passes, boost timers, playtime). They are pushed
-- like any field and also included in every snapshot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local StateSync = {}

local pending: { [Player]: { [string]: any } } = {}
local seqs: { [Player]: number } = {}
local volatile: { [Player]: { [string]: any } } = {}

function StateSync.push(player: Player, field: string, value: any)
	local patch = pending[player]
	if not patch then
		patch = {}
		pending[player] = patch
	end
	patch[field] = value
end

function StateSync.setVolatile(player: Player, field: string, value: any)
	if player.Parent ~= Players then return end
	local fields = volatile[player]
	if not fields then
		fields = {}
		volatile[player] = fields
	end
	fields[field] = value
	StateSync.push(player, field, value)
end

function StateSync.getVolatile(player: Player): { [string]: any }
	return volatile[player] or {}
end

-- Sends anything pending right now. Returns the player's current Seq.
function StateSync.flush(player: Player): number
	local patch = pending[player]
	if patch then
		pending[player] = nil
		local seq = (seqs[player] or 0) + 1
		seqs[player] = seq
		Net.fire(player, "StatePatch", { Seq = seq, Data = patch })
	end
	return seqs[player] or 0
end

function StateSync.init()
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		seqs[player] = nil
		volatile[player] = nil
	end)
end

function StateSync.start()
	while true do
		task.wait(Config.Sync.FlushInterval)
		for player in pending do
			if player.Parent == Players then
				StateSync.flush(player)
			else
				pending[player] = nil
			end
		end
	end
end

return StateSync
