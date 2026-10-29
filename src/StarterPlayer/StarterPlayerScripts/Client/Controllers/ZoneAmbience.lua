--[[

ZoneAmbience
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/ZoneAmbience

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Knows which zone the local player stands in (Zone-tagged instances: their
-- Center/ZoneSize attributes, or their bounding box, see Shared/Tags) and
-- makes it feel different (its Zone's ClockTime / Ambient / OutdoorAmbient /
-- FogColor / FogEnd / AtmosphereColor / AtmosphereDensity / Gravity /
-- Subtitle attributes, as tools/ZoneKit sets them, else Shared/MapThemes):
-- lighting, fog and
-- atmosphere blend to Shared/MapThemes, gravity changes locally (Heaven is
-- floaty) and a title card announces the zone.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Zones)
local MapThemes = require(Shared.MapThemes)
local Signal = require(Shared.Util.Signal)
local Tags = require(Shared.Tags)

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

type Box = { cframe: CFrame, size: Vector3 }
-- Cached per Zone instance; dropped when its attributes change.
local boxes: { [Instance]: Box } = {}

local function boxOf(zone: Instance): Box?
	local cached = boxes[zone]
	if cached then return cached end
	local cframe, size = Tags.zoneBox(zone)
	if not (cframe and size) then return nil end
	local box = { cframe = cframe, size = size }
	boxes[zone] = box
	return box
end

local function zoneAt(position: Vector3): string?
	for _, zone in CollectionService:GetTagged(Tags.Zone) do
		local id = Tags.idOfZone(zone)
		local box = if Zones.ById[id] then boxOf(zone) else nil
		if box then
			local localPoint = box.cframe:PointToObjectSpace(position)
			local half = box.size / 2
			if math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z then
				return id
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

local LOOK_FIELDS = {
	"ClockTime", "Ambient", "OutdoorAmbient", "FogColor", "FogEnd", "AtmosphereColor", "AtmosphereDensity", "Gravity", "Subtitle",
}
local DEFAULT_GRAVITY = 196.2

-- A zone's look: its Zone instance's attributes over its MapThemes entry.
local function lookOf(zoneId: string): { [string]: any }
	local look: { [string]: any } = {}
	local theme = MapThemes[zoneId]
	if theme then
		for _, field in LOOK_FIELDS do
			look[field] = (theme :: any)[field]
		end
	end
	local zone = Tags.forZone(Tags.Zone, zoneId)[1]
	if zone then
		for _, field in LOOK_FIELDS do
			local value = zone:GetAttribute(field)
			if value ~= nil and value ~= "" then
				look[field] = value
			end
		end
	end
	return look
end

function ZoneAmbience.apply(zoneId: string, instant: boolean?)
	local look = lookOf(zoneId)
	local info = if instant then TweenInfo.new(0) else BLEND
	local lighting: { [string]: any } = {}
	for _, field in { "ClockTime", "Ambient", "OutdoorAmbient", "FogColor", "FogEnd" } do
		lighting[field] = look[field]
	end
	if next(lighting) then
		TweenService:Create(Lighting, info, lighting):Play()
	end
	local color = look.AtmosphereColor
	if typeof(color) == "Color3" then
		TweenService:Create(atmosphere(), info, {
			Color = color,
			Decay = color:Lerp(Color3.new(0, 0, 0), 0.5),
			Density = if typeof(look.AtmosphereDensity) == "number" then look.AtmosphereDensity else 0.3,
		}):Play()
	end
	workspace.Gravity = if typeof(look.Gravity) == "number" then look.Gravity else DEFAULT_GRAVITY
end

function ZoneAmbience.current(): string?
	return current
end

function ZoneAmbience.start()
	local function watch(zone: Instance)
		zone.AttributeChanged:Connect(function()
			boxes[zone] = nil
		end)
	end
	for _, zone in CollectionService:GetTagged(Tags.Zone) do
		watch(zone)
	end
	CollectionService:GetInstanceAddedSignal(Tags.Zone):Connect(watch)
	CollectionService:GetInstanceRemovedSignal(Tags.Zone):Connect(function(zone)
		boxes[zone] = nil
	end)

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
				if def and not ZoneAmbience.Quiet then
					Juice.banner(string.upper(def.Name), lookOf(zoneId).Subtitle or "", def.Color, 1.4)
				end
			end
		end
	end
end

return ZoneAmbience
