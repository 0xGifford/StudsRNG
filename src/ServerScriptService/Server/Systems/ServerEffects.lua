--[[

ServerEffects
ModuleScript
/ServerScriptService/Server/Systems/ServerEffects

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Server-wide multipliers:
--   Server Luck: bought with Robux by anyone, x2 luck for everyone in this
--   server for 15 minutes (buying again adds time).
--   Global events: RollLogic.eventSchedule decides from the clock alone, so
--   every server runs the same event at the same moment.
--
-- Replicated as ReplicatedStorage attributes (server time, seconds):
--   ServerLuckEnds, ServerLuckBy, EventId, EventEnds, NextEventAt

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local RollLogic = require(Shared.Util.RollLogic)

local Systems = script.Parent
local Modifiers = require(Systems.Modifiers)

local ServerEffects = {}

local serverLuckEnds = 0
-- Dev override: { id, ends } forces an event outside the schedule.
local forced: { id: string, ends: number }? = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

local function refreshServerLuck()
	local active = serverLuckEnds > now()
	Modifiers.setServerLuck(if active then Config.ServerLuck.Multiplier else 1)
	ReplicatedStorage:SetAttribute("ServerLuckEnds", if active then serverLuckEnds else 0)
end

local function refreshEvent()
	local t = now()
	local event, ends, nextAt = RollLogic.eventSchedule(t)
	local id: string? = if event then event.Id else nil
	local currentForced = forced
	if currentForced then
		if currentForced.ends > t then
			id = currentForced.id
			ends = currentForced.ends
		else
			forced = nil
		end
	end

	local previous = ReplicatedStorage:GetAttribute("EventId")
	Modifiers.setEvent(id)
	ReplicatedStorage:SetAttribute("EventId", id or "")
	ReplicatedStorage:SetAttribute("EventEnds", if id then ends else 0)
	ReplicatedStorage:SetAttribute("NextEventAt", nextAt)

	if id and previous ~= id then
		local def = RollLogic.eventById(id)
		if def then
			Net.fireAll("Notify", { Text = `{def.Name} started!`, Color = def.Color })
		end
	end
end

-- Robux purchase: x2 luck for everyone, stacking time.
function ServerEffects.addServerLuck(buyer: Player)
	local t = now()
	local base = math.max(serverLuckEnds, t)
	serverLuckEnds = math.min(base + Config.ServerLuck.Duration, t + Config.ServerLuck.MaxDuration)
	ReplicatedStorage:SetAttribute("ServerLuckBy", buyer.DisplayName)
	refreshServerLuck()
	Net.fireAll("Notify", {
		Text = `{buyer.DisplayName} boosted Server Luck x{Config.ServerLuck.Multiplier}!`,
		Color = Color3.fromRGB(120, 255, 140),
	})
end

function ServerEffects.serverLuckEnds(): number
	return serverLuckEnds
end

-- Dev/admin: run an event now for `seconds`.
function ServerEffects.forceEvent(id: string, seconds: number): boolean
	if not RollLogic.eventById(id) then return false end
	forced = { id = id, ends = now() + seconds }
	refreshEvent()
	return true
end

function ServerEffects.init()
	ReplicatedStorage:SetAttribute("ServerLuckEnds", 0)
	ReplicatedStorage:SetAttribute("ServerLuckBy", "")
	refreshEvent()
end

function ServerEffects.start()
	while true do
		task.wait(1)
		refreshServerLuck()
		refreshEvent()
	end
end

return ServerEffects
