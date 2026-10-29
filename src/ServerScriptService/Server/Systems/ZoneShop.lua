--[[

ZoneShop
ModuleScript
/ServerScriptService/Server/Systems/ZoneShop

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Zones are bought with Clacks in order (Shared/Zones). Owning a zone adds
-- its studs to the roll pool and lets its keys pay out (Economy.ownsZone).
-- Barriers open on the client; the server only decides ownership and
-- teleports to the zone's ZoneSpawn-tagged part (Shared/Tags).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Zones = require(Shared.Zones)
local Tags = require(Shared.Tags)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local Modifiers = require(Systems.Modifiers)
local Economy = require(Systems.Economy)

type Response = Types.Response

local ZoneShop = {}

local TELEPORT_COOLDOWN = 2
local lastTeleport: { [Player]: number } = {}

function ZoneShop.teleport(player: Player, zoneId: string): Response
	local data = PlayerData.get(player)
	if not data then return { Ok = false, Error = "NotLoaded" } end
	if not data.UnlockedWorlds[zoneId] then return { Ok = false, Error = "ZoneLocked" } end

	local now = os.clock()
	if now - (lastTeleport[player] or 0) < TELEPORT_COOLDOWN then
		return { Ok = false, Error = "Cooldown" }
	end

	local spawnPart = Tags.spawnOf(zoneId)
	local character = player.Character
	if not spawnPart then return { Ok = false, Error = "NoSpawn" } end
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return { Ok = false, Error = "NoCharacter" }
	end

	lastTeleport[player] = now
	character:PivotTo(spawnPart.CFrame + Vector3.new(0, spawnPart.Size.Y / 2 + 3, 0))
	return { Ok = true }
end

function ZoneShop.buy(player: Player, zoneId: string): Response
	local data = PlayerData.get(player)
	if not data then return { Ok = false, Error = "NotLoaded" } end
	local def = Zones.ById[zoneId]
	if not def then return { Ok = false, Error = "InvalidZone" } end
	if data.UnlockedWorlds[zoneId] then return { Ok = false, Error = "AlreadyOwned" } end

	local nextZone = Zones.nextFor(data.UnlockedWorlds)
	if not nextZone or nextZone.Id ~= zoneId then
		return { Ok = false, Error = "ZoneOrder" }
	end

	local price = Zones.price(def, Modifiers.get(player).ZoneDiscount)
	if not Economy.spendClacks(player, price) then return { Ok = false, Error = "NotEnoughClacks" } end

	data.UnlockedWorlds[zoneId] = true
	StateSync.push(player, "UnlockedWorlds", data.UnlockedWorlds)
	Modifiers.invalidate(player)

	lastTeleport[player] = nil
	task.defer(ZoneShop.teleport, player, zoneId)
	return { Ok = true }
end

-- Rebirth: back to the first zone only. The player is sent home (or
-- respawned when the first zone has no Spawn) so nobody is left behind a
-- barrier that just closed again.
function ZoneShop.resetZones(player: Player)
	local data = PlayerData.get(player)
	if not data then return end
	table.clear(data.UnlockedWorlds)
	data.UnlockedWorlds[Zones.Default] = true
	StateSync.push(player, "UnlockedWorlds", data.UnlockedWorlds)
	Modifiers.invalidate(player)
	lastTeleport[player] = nil
	task.defer(function()
		local result = ZoneShop.teleport(player, Zones.Default)
		local hasZones = #CollectionService:GetTagged(Tags.ZoneSpawn) > 0
		if not result.Ok and result.Error == "NoSpawn" and hasZones and player.Parent == Players then
			player:LoadCharacter()
		end
	end)
end

-- Dev: own every zone.
function ZoneShop.unlockAll(player: Player)
	local data = PlayerData.get(player)
	if not data then return end
	for _, def in Zones.List do
		data.UnlockedWorlds[def.Id] = true
	end
	StateSync.push(player, "UnlockedWorlds", data.UnlockedWorlds)
	Modifiers.invalidate(player)
end

function ZoneShop.init()
	local function isZoneId(value: unknown): boolean
		return typeof(value) == "string" and Zones.ById[value :: string] ~= nil
	end

	Net.handle("BuyZone", { Rate = 2, Burst = 3 }, function(player, zoneId)
		if not isZoneId(zoneId) then return { Ok = false, Error = "InvalidZone" } end
		return ZoneShop.buy(player, zoneId)
	end)

	Net.handle("TeleportZone", { Rate = 1, Burst = 3 }, function(player, zoneId)
		if not isZoneId(zoneId) then return { Ok = false, Error = "InvalidZone" } end
		return ZoneShop.teleport(player, zoneId)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastTeleport[player] = nil
	end)
end

return ZoneShop
