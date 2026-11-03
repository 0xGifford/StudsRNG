--[[

Retention
ModuleScript
/ServerScriptService/Server/Systems/Retention

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The systems that stack on the core loop and give reasons to come back:
--   Zone rotation  keys in today's Favoured / this week's Vintage zones pay
--                  more (Shared/ZoneRotation; the roll luck is in Rolls)
--   Zone Mastery   stars per zone (Shared/Mastery): announced as they're
--                  earned; 2 / 3 star zones' keys pay more, every star adds
--                  to the Clack multiplier everywhere (RollLogic)
--   Stud Memories  studs levelled to the max add Clacks for good
--   Squad roles    SetStudRole(key, role) (Config.Roles)
-- Stats change when stars or memories do: this invalidates the stat cache.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Zones = require(Shared.Zones)
local Studs = require(Shared.Studs)
local Mastery = require(Shared.Mastery)
local ZoneRotation = require(Shared.ZoneRotation)
local RollLogic = require(Shared.Util.RollLogic)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local Modifiers = require(Systems.Modifiers)
local PressTracker = require(Systems.PressTracker)

local Retention = {}

local CHECK = 5 -- seconds between mastery / memory checks per player

-- Studs at max level last time we looked, per player (memories).
local memories: { [Player]: { [string]: boolean } } = {}

local function checkMastery(player: Player, data: any)
	local changed = false
	local gained: { { zone: Zones.ZoneDef, stars: number } } = {}
	for _, def in Zones.List do
		local stars = Mastery.stars(data, def.Id)
		local before = data.Mastery[def.Id]
		if before ~= stars then
			-- First look (an existing save): fill in quietly.
			if before ~= nil and stars > before and stars >= 2 then
				table.insert(gained, { zone = def, stars = stars })
			end
			data.Mastery[def.Id] = stars
			changed = true
		end
	end
	if changed then
		StateSync.push(player, "Mastery", data.Mastery)
		Modifiers.invalidate(player)
	end
	for _, entry in gained do
		Net.fire(player, "Notify", {
			Kind = "Mastery",
			Zone = entry.zone.Id,
			Stars = entry.stars,
			Text = `{entry.zone.Name} mastery {Mastery.text(entry.stars)}!`,
			Color = entry.zone.Color,
		})
	end
end

local function checkMemories(player: Player, data: any)
	local known = memories[player]
	local first = known == nil
	known = known or {}
	memories[player] = known
	local changed = false
	for id, xp in data.StudXP do
		if not known[id] and RollLogic.levelOf(xp) >= Config.Levels.Max then
			known[id] = true
			changed = true
			local def = Studs.ById[id]
			if not first and def then
				Net.fire(player, "Notify", {
					Kind = "Memory",
					Stud = id,
					Text = `Stud Memory: {def.Name} is maxed! +{math.floor(Config.Memories.Clacks * 100 + 0.5)}% Clacks for good`,
					Color = Color3.fromRGB(255, 220, 120),
				})
			end
		end
	end
	if changed and not first then
		Modifiers.invalidate(player)
	end
end

-- Keys: Favoured / Vintage zones and mastered zones pay more.
local function keyScale(player: Player, zone: string?): number
	if not zone then return 1 end
	local scale = 1
	local rotation = ZoneRotation.bonus(zone, os.time())
	if rotation then
		scale *= rotation.Clacks
	end
	local data = PlayerData.get(player)
	local stars = data and data.Mastery[zone]
	if typeof(stars) == "number" then
		scale *= 1 + Mastery.keyBonus(stars)
	end
	return scale
end

local function setRole(player: Player, key: unknown, role: unknown)
	local data = PlayerData.get(player)
	if not data then return { Ok = false, Error = "NotLoaded" } end
	if typeof(key) ~= "string" or #key > 64 or typeof(role) ~= "string" or #role > 16 then
		return { Ok = false, Error = "InvalidStud" }
	end
	if not table.find(Config.Roles.Order, role) then
		return { Ok = false, Error = "InvalidStud" }
	end
	if (data.Studs[key] or 0) <= 0 then
		return { Ok = false, Error = "NotOwned" }
	end
	data.StudRoles[key] = if role == "None" then nil else role
	StateSync.push(player, "StudRoles", data.StudRoles)
	Modifiers.invalidate(player)
	return { Ok = true, Role = role }
end

function Retention.init()
	PressTracker.setValueScale(keyScale)
	Net.handle("SetStudRole", { Rate = 6, Burst = 10 }, setRole)
	PlayerData.Loaded:Connect(function(player, data)
		-- Roles on studs the player no longer owns are dropped.
		for key in data.StudRoles do
			if (data.Studs[key] or 0) <= 0 then
				data.StudRoles[key] = nil
			end
		end
		checkMastery(player, data)
		checkMemories(player, data)
	end)
	Players.PlayerRemoving:Connect(function(player)
		memories[player] = nil
	end)
end

function Retention.start()
	while true do
		task.wait(CHECK)
		for _, player in Players:GetPlayers() do
			local data = PlayerData.get(player)
			if data then
				local ok, err = pcall(function()
					checkMastery(player, data)
					checkMemories(player, data)
				end)
				if not ok then
					warn("[Retention]", err)
				end
			end
		end
	end
end

return Retention
