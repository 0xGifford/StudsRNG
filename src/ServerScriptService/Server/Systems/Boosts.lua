--[[

Boosts
ModuleScript
/ServerScriptService/Server/Systems/Boosts

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Personal timed boosts (Config.Boosts). Saved as seconds remaining in
-- PlayerData.Boosts and only counted down while the player is online, so a
-- purchase is never wasted by leaving.
--
-- The client gets "BoostEnds" ({ [id] = server time it runs out }) whenever
-- the set changes, and counts down locally.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local Modifiers = require(Systems.Modifiers)

local Boosts = {}

local TICK = 1

local function sync(player: Player, data: any)
	local now = workspace:GetServerTimeNow()
	local active: { [string]: boolean } = {}
	local ends: { [string]: number } = {}
	for id, seconds in data.Boosts do
		if seconds > 0 then
			active[id] = true
			ends[id] = now + seconds
		end
	end
	Modifiers.setActiveBoosts(player, active)
	StateSync.setVolatile(player, "BoostEnds", ends)
	StateSync.push(player, "Boosts", data.Boosts)
end

-- Adds `seconds` of boost `id` (stacks with any time left).
function Boosts.add(player: Player, id: string, seconds: number): boolean
	local data = PlayerData.get(player)
	local def = Config.Boosts[id]
	if not data or not def or seconds ~= seconds or seconds <= 0 then return false end
	local current = data.Boosts[id] or 0
	data.Boosts[id] = math.min(current + seconds, Config.MaxBoostSeconds)
	sync(player, data)
	return true
end

function Boosts.remaining(player: Player, id: string): number
	local data = PlayerData.get(player)
	return if data then data.Boosts[id] or 0 else 0
end

function Boosts.init()
	PlayerData.Loaded:Connect(function(player, data)
		sync(player, data)
	end)
end

function Boosts.start()
	while true do
		task.wait(TICK)
		for _, player in Players:GetPlayers() do
			local data = PlayerData.get(player)
			if data and next(data.Boosts) then
				local expired = false
				for id, seconds in data.Boosts do
					local left = seconds - TICK
					if left <= 0 then
						data.Boosts[id] = nil
						expired = true
					else
						data.Boosts[id] = left
					end
				end
				if expired then
					sync(player, data)
				end
			end
		end
	end
end

return Boosts
