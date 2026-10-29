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
--
-- Balance: Health and Damage grow exponentially, like a player's team does,
-- so an enemy in your own zone takes ~4-7 s to defeat and your studs last
-- 2-4x that. Reward is ~25 key presses of that zone, and Combat multiplies
-- it by the player's Clacks multiplier, so fighting keeps pace with
-- pressing keys the whole game.

local Zones = require(script.Parent.Zones)

export type EnemyDef = {
	Name: string,
	Level: number,
	Health: number,
	Damage: number, -- per second against the player's team
	Reward: number, -- Clacks per defeat, before the player's Clacks multiplier
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
		Health = math.floor(45 * 1.2 ^ n),
		Damage = math.floor(4 * 1.16 ^ n * 10 + 0.5) / 10,
		Reward = math.floor(25 * zone.KeyMultiplier),
		Color = zone.Color,
		Size = 4 + math.min(n, 30) * 0.1,
	}
	cache[zoneId] = def
	return def
end

return Enemies
