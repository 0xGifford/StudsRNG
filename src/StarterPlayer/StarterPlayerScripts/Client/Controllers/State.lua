--[[ 

State
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/State

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The client's mirror of its own PlayerData, plus the request API UI calls.
-- Renders nothing and decides nothing: every action is a server request,
-- and the server's patches are the only thing that changes this state.
--
-- UI usage:
--   State.Changed:Connect(function(field, value) ... end)
--   State.get("Clacks"), State.stats().ClackMultiplier
--   local res = State.roll(1, true)  -- res.Ok, res.Results / res.Error

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)
local RollLogic = require(Shared.Util.RollLogic)

type Response = Types.Response
type Stats = Types.Stats
type StatePatch = Types.StatePatch

local State = {}

State.Changed = Signal.new() :: Signal.Signal<string, any> -- (field, value)
State.Ready = Signal.new() :: Signal.Signal<>
State.Announced = Signal.new() :: Signal.Signal<any>

local data: { [string]: any } = {}
local seq = -1 -- -1 until the snapshot lands
local buffered: { StatePatch } = {}
local cachedStats: Stats? = nil
local ready = false

local STAT_FIELDS = { Studs = true, Equipped = true, Index = true }

local function applyPatch(patch: StatePatch)
	if typeof(patch) ~= "table" or typeof(patch.Seq) ~= "number" then return end
	if patch.Seq <= seq then return end
	seq = patch.Seq
	for field, value in patch.Data do
		data[field] = value
		if STAT_FIELDS[field] then
			cachedStats = nil
		end
		State.Changed:Fire(field, value)
	end
end

local function loadSnapshot(): boolean
	local response = Net.invoke("GetSnapshot")
	if not response.Ok then return false end

	data = response.Data
	seq = response.Seq
	cachedStats = nil
	for field, value in data do
		State.Changed:Fire(field, value)
	end

	-- Patches that arrived before the snapshot: keep only the newer ones.
	table.sort(buffered, function(a, b)
		return a.Seq < b.Seq
	end)
	for _, patch in buffered do
		applyPatch(patch)
	end
	table.clear(buffered)
	return true
end

--------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------

function State.isReady(): boolean
	return ready
end

function State.get(field: string): any
	return data[field]
end

-- Multiplier, luck, slots, index progress. Display only.
function State.stats(): Stats
	if not cachedStats then
		cachedStats = RollLogic.computeStats({
			Index = data.Index or {},
			Equipped = data.Equipped or {},
			Studs = data.Studs or {},
		})
	end
	return cachedStats :: Stats
end

--------------------------------------------------------------------------
-- Requests (all yield until the server answers)
--------------------------------------------------------------------------

function State.roll(count: number, useFree: boolean): Response
	return Net.invoke("Roll", count, useFree)
end

function State.equip(key: string): Response
	return Net.invoke("Equip", key)
end

function State.unequip(key: string): Response
	return Net.invoke("Unequip", key)
end

function State.equipBest(): Response
	return Net.invoke("EquipBest")
end

function State.unequipAll(): Response
	return Net.invoke("UnequipAll")
end

function State.fuse(key: string): Response
	return Net.invoke("Fuse", key)
end

function State.delete(key: string, amount: number): Response
	return Net.invoke("Delete", key, amount)
end

function State.setAutoDelete(rarity: string, enabled: boolean): Response
	return Net.invoke("SetAutoDelete", rarity, enabled)
end

--------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------

function State.init()
	Net.on("StatePatch", function(patch)
		if seq < 0 then
			table.insert(buffered, patch)
		else
			applyPatch(patch)
		end
	end)

	Net.on("Announce", function(payload)
		State.Announced:Fire(payload)
	end)
end

function State.start()
	while not loadSnapshot() do
		task.wait(2)
	end
	ready = true
	State.Ready:Fire()
end

return State
