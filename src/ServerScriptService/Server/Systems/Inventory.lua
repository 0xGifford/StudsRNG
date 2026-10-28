--[[ 

Inventory
ModuleScript
/ServerScriptService/Server/Systems/Inventory

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Owns studs: granting, the index, equipping, fusing, deleting and
-- auto-delete. Also owns the derived stats (multiplier, luck, slots), cached
-- per player and invalidated whenever studs/equipped/index change.
--
-- Equipped studs are mirrored to the player attribute "EquippedStuds"
-- (comma-separated keys) so every client can render followers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Variants = require(Shared.Variants)
local RollLogic = require(Shared.Util.RollLogic)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)

type Stats = Types.Stats
type Response = Types.Response

export type GrantResult = { Key: string, New: boolean, Kept: boolean, Reason: string? }

local Inventory = {}

local statsCache: { [Player]: Stats } = {}

--------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------

local function syncEquippedAttribute(player: Player, data: any)
	player:SetAttribute("EquippedStuds", table.concat(data.Equipped, ","))
end

local function invalidate(player: Player)
	statsCache[player] = nil
end

-- Removes equipped entries the player no longer owns enough of, and trims
-- to the current slot count. Call after anything that removes studs.
local function reconcileEquipped(player: Player, data: any)
	invalidate(player)
	local slots = Inventory.getStats(player).Slots
	local used: { [string]: number } = {}
	local kept = {}
	for _, key in data.Equipped do
		local owned = data.Studs[key] or 0
		if (used[key] or 0) < owned and #kept < slots then
			used[key] = (used[key] or 0) + 1
			table.insert(kept, key)
		end
	end
	data.Equipped = kept
	invalidate(player)
end

local function pushStuds(player: Player, data: any)
	StateSync.push(player, "Studs", data.Studs)
	StateSync.push(player, "Equipped", data.Equipped)
	StateSync.push(player, "Index", data.Index)
	syncEquippedAttribute(player, data)
end

local function removeStuds(data: any, key: string, amount: number)
	local remaining = (data.Studs[key] or 0) - amount
	data.Studs[key] = if remaining > 0 then remaining else nil
end

local function fail(err: string): Response
	return { Ok = false, Error = err }
end

--------------------------------------------------------------------------
-- Public API (used by Rolls, Cheats and remote handlers)
--------------------------------------------------------------------------

function Inventory.getStats(player: Player): Stats
	local cached = statsCache[player]
	if cached then return cached end
	local data = PlayerData.get(player)
	if not data then
		return RollLogic.computeStats({ Index = {}, Equipped = {}, Studs = {} })
	end
	local stats = RollLogic.computeStats(data)
	statsCache[player] = stats
	return stats
end

-- Drops cached stats and re-mirrors equipped studs (after external data edits).
function Inventory.refresh(player: Player)
	invalidate(player)
	local data = PlayerData.get(player)
	if data then
		syncEquippedAttribute(player, data)
	end
end

-- Adds one stud. Always registers the index entry, even when the stud
-- itself is auto-deleted or the inventory is full.
function Inventory.grant(player: Player, id: string, variant: string): GrantResult?
	local data = PlayerData.get(player)
	if not data then return nil end
	local def, variantDef = RollLogic.decodeKey(RollLogic.encodeKey(id, variant))
	if not def or not variantDef then return nil end

	local key = RollLogic.encodeKey(def.Id, variantDef.Name)
	local isNew = not data.Index[key]
	data.Index[key] = true
	invalidate(player)

	local result: GrantResult = { Key = key, New = isNew, Kept = false, Reason = nil }

	local autoDelete = variantDef.Name == "Normal" and data.AutoDelete[def.Rarity] == true
	if autoDelete and not (isNew and Config.Inventory.KeepFirstDiscovery) then
		result.Reason = "AutoDelete"
	elseif RollLogic.countStuds(data.Studs) >= Config.Inventory.MaxStuds then
		result.Reason = "Full"
	else
		data.Studs[key] = (data.Studs[key] or 0) + 1
		result.Kept = true
	end

	pushStuds(player, data)
	return result
end

function Inventory.equip(player: Player, key: string): Response
	local data = PlayerData.get(player)
	if not data then return fail("NotLoaded") end
	if not RollLogic.decodeKey(key) then return fail("InvalidStud") end

	local owned = data.Studs[key] or 0
	if RollLogic.countInList(data.Equipped, key) >= owned then
		return fail("NotOwned")
	end
	if #data.Equipped >= Inventory.getStats(player).Slots then
		return fail("SlotsFull")
	end

	table.insert(data.Equipped, key)
	invalidate(player)
	pushStuds(player, data)
	return { Ok = true }
end

function Inventory.unequip(player: Player, key: string): Response
	local data = PlayerData.get(player)
	if not data then return fail("NotLoaded") end
	local index = table.find(data.Equipped, key)
	if not index then return fail("NotEquipped") end
	table.remove(data.Equipped, index)
	invalidate(player)
	pushStuds(player, data)
	return { Ok = true }
end

function Inventory.unequipAll(player: Player): Response
	local data = PlayerData.get(player)
	if not data then return fail("NotLoaded") end
	table.clear(data.Equipped)
	invalidate(player)
	pushStuds(player, data)
	return { Ok = true }
end

function Inventory.equipBest(player: Player): Response
	local data = PlayerData.get(player)
	if not data then return fail("NotLoaded") end
	local slots = Inventory.getStats(player).Slots
	local equipped = {}
	for _, key in RollLogic.sortedOwned(data.Studs) do
		for _ = 1, data.Studs[key] do
			if #equipped >= slots then break end
			table.insert(equipped, key)
		end
		if #equipped >= slots then break end
	end
	data.Equipped = equipped
	invalidate(player)
	pushStuds(player, data)
	return { Ok = true }
end

-- FuseCost of one key → 1 of the next variant in the chain.
function Inventory.fuse(player: Player, key: string): Response
	local data = PlayerData.get(player)
	if not data then return fail("NotLoaded") end
	local def, variantDef = RollLogic.decodeKey(key)
	if not def or not variantDef then return fail("InvalidStud") end

	local nextVariant = Variants.Next[variantDef.Name]
	if not nextVariant then return fail("MaxVariant") end

	local cost = Config.Inventory.FuseCost
	if (data.Studs[key] or 0) < cost then return fail("NotEnough") end

	removeStuds(data, key, cost)
	local newKey = RollLogic.encodeKey(def.Id, nextVariant)
	local isNew = not data.Index[newKey]
	data.Index[newKey] = true
	-- Fusing frees cost-1 slots of space, so the result always fits.
	data.Studs[newKey] = (data.Studs[newKey] or 0) + 1

	reconcileEquipped(player, data)
	pushStuds(player, data)
	return { Ok = true, Key = newKey, New = isNew }
end

function Inventory.delete(player: Player, key: string, amount: number): Response
	local data = PlayerData.get(player)
	if not data then return fail("NotLoaded") end
	if not RollLogic.decodeKey(key) then return fail("InvalidStud") end
	local owned = data.Studs[key] or 0
	if owned <= 0 then return fail("NotOwned") end

	removeStuds(data, key, math.min(amount, owned))
	reconcileEquipped(player, data)
	pushStuds(player, data)
	return { Ok = true }
end

function Inventory.setAutoDelete(player: Player, rarity: string, enabled: boolean): Response
	local data = PlayerData.get(player)
	if not data then return fail("NotLoaded") end
	if not Config.Rarities.AutoDeletable[rarity] then return fail("NotAllowed") end
	if enabled then
		data.AutoDelete[rarity] = true
	else
		data.AutoDelete[rarity] = nil
	end
	StateSync.push(player, "AutoDelete", data.AutoDelete)
	return { Ok = true }
end

--------------------------------------------------------------------------
-- Remote handlers: type → range → permission. Everything else lives in the
-- API functions above so dev commands reuse the same paths.
--------------------------------------------------------------------------

local function isKey(value: unknown): boolean
	return RollLogic.decodeKey(value) ~= nil
end

local function isWholeNumber(value: unknown, min: number, max: number): boolean
	if typeof(value) ~= "number" then return false end
	local n = value :: number
	return n == n and n == math.floor(n) and n >= min and n <= max
end

function Inventory.init()
	PlayerData.Loaded:Connect(function(player, data)
		invalidate(player)
		syncEquippedAttribute(player, data)
	end)
	Players.PlayerRemoving:Connect(function(player)
		statsCache[player] = nil
	end)

	local actionLimit = { Rate = 6, Burst = 10 }

	Net.handle("Equip", actionLimit, function(player, key)
		if not isKey(key) then return fail("InvalidStud") end
		return Inventory.equip(player, key)
	end)

	Net.handle("Unequip", actionLimit, function(player, key)
		if not isKey(key) then return fail("InvalidStud") end
		return Inventory.unequip(player, key)
	end)

	Net.handle("EquipBest", { Rate = 1, Burst = 2 }, function(player)
		return Inventory.equipBest(player)
	end)

	Net.handle("UnequipAll", { Rate = 1, Burst = 2 }, function(player)
		return Inventory.unequipAll(player)
	end)

	Net.handle("Fuse", { Rate = 3, Burst = 5 }, function(player, key)
		if not isKey(key) then return fail("InvalidStud") end
		return Inventory.fuse(player, key)
	end)

	Net.handle("Delete", actionLimit, function(player, key, amount)
		if not isKey(key) then return fail("InvalidStud") end
		if not isWholeNumber(amount, 1, Config.Inventory.MaxStuds) then return fail("InvalidAmount") end
		return Inventory.delete(player, key, amount)
	end)

	Net.handle("SetAutoDelete", actionLimit, function(player, rarity, enabled)
		if typeof(rarity) ~= "string" or typeof(enabled) ~= "boolean" then
			return fail("InvalidArgs")
		end
		return Inventory.setAutoDelete(player, rarity, enabled)
	end)
end

return Inventory
