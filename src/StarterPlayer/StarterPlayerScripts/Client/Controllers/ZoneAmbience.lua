--[[

ZoneAmbience
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/ZoneAmbience

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Knows which zone the local player stands in (workspace.Zones.<Id>: the
-- Center/ZoneSize attributes MapBuilder sets, or the model's bounding box
-- for hand-built zones) and makes it feel different: lighting, fog and
-- atmosphere blend to Shared/MapThemes, gravity changes locally (Heaven is
-- floaty) and a title card announces the zone.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Zones = require(Shared.Zones)
local MapThemes = require(Shared.MapThemes)
local Signal = require(Shared.Util.Signal)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local Juice = require(UI.Juice)

local ZoneAmbience = {}

-- (zoneId) when the player walks into another zone
ZoneAmbience.Changed = Signal.new() :: Signal.Signal<string>
-- The intro sets this so the title card doesn't fire under the cinematic.
ZoneAmbience.Quiet = false

local BLEND = TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local player = Players.LocalPlayer
local current: string? = nil
local boxes: { [string]: { cframe: CFrame, size: Vector3 } } = {}

local function boxOf(zone: Instance): { cframe: CFrame, size: Vector3 }?
	local cached = boxes[zone.Name]
	if cached then return cached end
	local center = zone:GetAttribute("Center")
	local size = zone:GetAttribute("ZoneSize")
	local box: { cframe: CFrame, size: Vector3 }
	if typeof(center) == "Vector3" and typeof(size) == "Vector3" then
		box = { cframe = CFrame.new(center + Vector3.new(0, size.Y / 2 - 10, 0)), size = size }
	elseif zone:IsA("Model") then
		local cframe, extents = zone:GetBoundingBox()
		box = { cframe = cframe, size = extents + Vector3.new(0, 40, 0) }
	else
		return nil
	end
	boxes[zone.Name] = box
	return box
end

local function zoneAt(position: Vector3): string?
	local folder = workspace:FindFirstChild(Config.ZoneFolder)
	if not folder then return nil end
	for _, def in Zones.List do
		local zone = folder:FindFirstChild(def.Id)
		local box = zone and boxOf(zone)
		if box then
			local localPoint = box.cframe:PointToObjectSpace(position)
			local half = box.size / 2
			if math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z then
				return def.Id
			end
		end
	end
	return nil
end

local function atmosphere(): Atmosphere
	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	if existing then return existing end
	local created = Instance.new("Atmosphere")
	created.Parent = Lighting
	return created
end

function ZoneAmbience.apply(zoneId: string, instant: boolean?)
	local theme = MapThemes[zoneId]
	if not theme then return end
	local info = if instant then TweenInfo.new(0) else BLEND
	TweenService:Create(Lighting, info, {
		ClockTime = theme.ClockTime,
		Ambient = theme.Ambient,
		OutdoorAmbient = theme.OutdoorAmbient,
		FogColor = theme.FogColor,
		FogEnd = theme.FogEnd,
	}):Play()
	TweenService:Create(atmosphere(), info, {
		Color = theme.AtmosphereColor,
		Decay = theme.AtmosphereColor:Lerp(Color3.new(0, 0, 0), 0.5),
		Density = theme.AtmosphereDensity,
	}):Play()
	workspace.Gravity = theme.Gravity
end

function ZoneAmbience.current(): string?
	return current
end

function ZoneAmbience.start()
	while true do
		task.wait(0.4)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local zoneId = zoneAt(root.Position)
			if zoneId and zoneId ~= current then
				local first = current == nil
				current = zoneId
				ZoneAmbience.apply(zoneId, first)
				ZoneAmbience.Changed:Fire(zoneId)
				local def = Zones.ById[zoneId]
				local theme = MapThemes[zoneId]
				if def and theme and not ZoneAmbience.Quiet then
					Juice.banner(string.upper(def.Name), theme.Subtitle, def.Color, 1.4)
				end
			end
		end
	end
end

return ZoneAmbience
