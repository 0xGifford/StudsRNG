--[[

Modifiers
ModuleScript
/ServerScriptService/Server/Systems/Modifiers

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Owns every player's derived Stats (luck, Clacks multiplier, roll speed,
-- slots, ...). Systems that change an input either edit PlayerData and call
-- Modifiers.invalidate(player), or set context here (passes, active boosts,
-- friends, Premium, server luck, the global event).
--
-- Stats are recomputed lazily and pushed to the client as the volatile
-- "Stats" field, at most once per frame per player. The server's copy is
-- the only one gameplay reads; the client's is for display.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)
local RollLogic = require(Shared.Util.RollLogic)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)

type Stats = Types.Stats
type StatContext = Types.StatContext

local Modifiers = {}

-- Fires after a player's stats were recomputed: (player, stats)
Modifiers.Changed = Signal.new() :: Signal.Signal<Player, Stats>

type PlayerContext = {
	Passes: { [string]: boolean },
	ActiveBoosts: { [string]: boolean },
	Friends: number,
	Premium: boolean,
}

local contexts: { [Player]: PlayerContext } = {}
local cache: { [Player]: Stats } = {}
local queued: { [Player]: boolean } = {}

local globalServerLuck = 1
local globalEvent: string? = nil

local function contextFor(player: Player): PlayerContext
	local ctx = contexts[player]
	if not ctx then
		ctx = { Passes = {}, ActiveBoosts = {}, Friends = 0, Premium = false }
		contexts[player] = ctx
	end
	return ctx
end

local function buildContext(player: Player): StatContext
	local ctx = contextFor(player)
	return {
		Passes = ctx.Passes,
		ActiveBoosts = ctx.ActiveBoosts,
		ServerLuck = globalServerLuck,
		Event = globalEvent,
		Friends = ctx.Friends,
		Premium = ctx.Premium,
	}
end

local function applyWalkSpeed(player: Player, stats: Stats)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.WalkSpeed ~= stats.WalkSpeed then
		humanoid.WalkSpeed = stats.WalkSpeed
	end
end

local function compute(player: Player): Stats
	local data = PlayerData.get(player)
	local stats = RollLogic.computeStats(data or { Index = {}, Equipped = {}, Studs = {} }, buildContext(player))
	if data then
		cache[player] = stats
	end
	return stats
end

local function flush(player: Player)
	queued[player] = nil
	if player.Parent ~= Players or not PlayerData.get(player) then return end
	local stats = cache[player] or compute(player)
	StateSync.setVolatile(player, "Stats", stats)
	applyWalkSpeed(player, stats)
	Modifiers.Changed:Fire(player, stats)
end

--------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------

function Modifiers.get(player: Player): Stats
	return cache[player] or compute(player)
end

-- Something feeding this player's stats changed: recompute and push.
function Modifiers.invalidate(player: Player)
	cache[player] = nil
	if queued[player] then return end
	queued[player] = true
	task.defer(flush, player)
end

function Modifiers.invalidateAll()
	for _, player in Players:GetPlayers() do
		Modifiers.invalidate(player)
	end
end

function Modifiers.setPasses(player: Player, passes: { [string]: boolean })
	contextFor(player).Passes = passes
	Modifiers.invalidate(player)
end

function Modifiers.getPasses(player: Player): { [string]: boolean }
	return contextFor(player).Passes
end

function Modifiers.setActiveBoosts(player: Player, active: { [string]: boolean })
	contextFor(player).ActiveBoosts = active
	Modifiers.invalidate(player)
end

function Modifiers.setFriends(player: Player, friends: number)
	local ctx = contextFor(player)
	if ctx.Friends == friends then return end
	ctx.Friends = friends
	Modifiers.invalidate(player)
end

function Modifiers.setPremium(player: Player, premium: boolean)
	local ctx = contextFor(player)
	if ctx.Premium == premium then return end
	ctx.Premium = premium
	Modifiers.invalidate(player)
end

function Modifiers.setServerLuck(multiplier: number)
	if globalServerLuck == multiplier then return end
	globalServerLuck = multiplier
	Modifiers.invalidateAll()
end

function Modifiers.setEvent(id: string?)
	if globalEvent == id then return end
	globalEvent = id
	Modifiers.invalidateAll()
end

--------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------

function Modifiers.init()
	PlayerData.Loaded:Connect(function(player)
		Modifiers.invalidate(player)
	end)

	local function onCharacter(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") and PlayerData.get(player) then
			applyWalkSpeed(player, Modifiers.get(player))
		end
	end
	local function track(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		contexts[player] = nil
		cache[player] = nil
		queued[player] = nil
	end)
end

return Modifiers
