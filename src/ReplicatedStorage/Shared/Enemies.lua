--[[

Enemies
ModuleScript
/ReplicatedStorage/Shared/Enemies

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- What lives in each zone. Every zone has one kind of enemy whose Health,
-- Damage and Clacks reward follow the zone's place in the list, so deeper
-- zones need stronger studs (RollLogic.statsOf). Read by the server's Combat
-- system and the client's Enemies controller.

local Zones = require(script.Parent.Zones)

export type EnemyDef = {
	Name: string,
	Level: number,
	Health: number,
	Damage: number, -- per second against the player's team
	Reward: number, -- Clacks per defeat, before rebirths
	Color: Color3,
	Size: number, -- body size in studs
}

local KINDS = { "Grub", "Brute", "Golem", "Crusher", "Beast" }

local Enemies = {}

local cache: { [string]: EnemyDef } = {}

function Enemies.forZone(zoneId: string): EnemyDef?
	local cached = cache[zoneId]
	if cached then return cached end
	local zone = Zones.ById[zoneId]
	if not zone then return nil end
	local n = zone.Order
	local def: EnemyDef = {
		Name = `{zone.Name} {KINDS[(n - 1) % #KINDS + 1]}`,
		Level = n,
		Health = math.floor(40 * n ^ 2.2),
		Damage = math.floor(1.5 * n ^ 1.5 * 10 + 0.5) / 10,
		Reward = math.floor(60 * zone.KeyMultiplier * (1 + n * 0.25)),
		Color = zone.Color,
		Size = 4 + math.min(n, 30) * 0.1,
	}
	cache[zoneId] = def
	return def
end

return Enemies
