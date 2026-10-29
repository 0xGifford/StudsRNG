--[[

Drops
ModuleScript
/ServerScriptService/Server/Systems/Drops

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Boss drops: studs with Drop = true (Shared/Studs) can't be rolled; Mini
-- Bosses and Zone Bosses drop them (Combat calls Drops.roll per fighter).
-- A drop goes through Inventory.grant like a roll (index, auto-delete, full
-- inventory), is revealed to the player with the roll reel ("Drop" event)
-- and announced in the Rolls chat channel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local RollLogic = require(Shared.Util.RollLogic)

local Systems = script.Parent
local Inventory = require(Systems.Inventory)
local Modifiers = require(Systems.Modifiers)

type RollResult = Types.RollResult

local Drops = {}

local rng = Random.new()

-- baseLuck: Config.Drops.MiniBossLuck or ZoneBossLuck. Returns the drop, if any.
function Drops.roll(player: Player, baseLuck: number, enemyLevel: number): RollResult?
	local luck = baseLuck * (1 + enemyLevel * Config.Drops.PerEnemyLevel)
	local def = RollLogic.rollDrop(rng, luck)
	if not def then return nil end
	local variant = RollLogic.rollVariant(rng, Modifiers.get(player).VariantLuck)
	local grant = Inventory.grant(player, def.Id, variant.Name)
	if not grant then return nil end

	local oneIn = def.OneIn * variant.OneIn
	local result: RollResult = {
		Id = def.Id,
		Variant = variant.Name,
		Key = grant.Key,
		OneIn = oneIn,
		New = grant.New,
		Kept = grant.Kept,
		Reason = grant.Reason,
	}
	Net.fire(player, "Drop", { result })
	Net.fireAll("Announce", {
		Player = player.DisplayName,
		UserId = player.UserId,
		Id = def.Id,
		Variant = variant.Name,
		OneIn = oneIn,
		Drop = true,
	})
	return result
end

return Drops
