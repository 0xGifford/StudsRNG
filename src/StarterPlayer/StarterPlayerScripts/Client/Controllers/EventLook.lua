--[[

EventLook
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/EventLook

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Makes the world look like the running event (Config.Events: Look).
-- Lighting, the Atmosphere and a ColorCorrection ("EventGrade") blend in
-- over BLEND seconds; a Sky swaps in. When the event ends everything blends
-- back to how the place had it the moment the event started.
--
-- Skies: put Sky objects in ReplicatedStorage.Assets.Skies and name them in
-- an event's Look.Sky (e.g. "BloodMoon"); a missing one keeps the place's sky.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local RollLogic = require(Shared.Util.RollLogic)

local EventLook = {}

local BLEND = TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local GRADE_NAME = "EventGrade"
local SKY_NAME = "EventSky"

-- What the place looked like before the current event, per instance.
type Saved = { [Instance]: { [string]: any } }
local saved: Saved = {}
local hiddenSky: Sky? = nil
local active: string? = nil

local function remember(instance: Instance, props: { [string]: any })
	local record = saved[instance]
	if not record then
		record = {}
		saved[instance] = record
	end
	for key in props do
		if record[key] == nil then
			local ok, value = pcall(function()
				return (instance :: any)[key]
			end)
			if ok then
				record[key] = value
			end
		end
	end
end

local function blend(instance: Instance, props: { [string]: any })
	local tweenable: { [string]: any } = {}
	for key, value in props do
		if typeof(value) == "number" or typeof(value) == "Color3" then
			tweenable[key] = value
		else
			pcall(function()
				(instance :: any)[key] = value
			end)
		end
	end
	if next(tweenable) then
		TweenService:Create(instance, BLEND, tweenable):Play()
	end
end

local function atmosphere(): Atmosphere
	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	if existing then return existing end
	local created = Instance.new("Atmosphere")
	created.Density = 0
	created.Parent = Lighting
	return created
end

local function grade(): ColorCorrectionEffect
	local existing = Lighting:FindFirstChild(GRADE_NAME)
	if existing and existing:IsA("ColorCorrectionEffect") then return existing end
	local created = Instance.new("ColorCorrectionEffect")
	created.Name = GRADE_NAME
	created.Parent = Lighting
	return created
end

local function skyFor(spec: any): Sky?
	if typeof(spec) == "string" then
		local assets = ReplicatedStorage:FindFirstChild(Config.Visuals.TemplateFolder)
		local skies = assets and assets:FindFirstChild("Skies")
		local found = skies and skies:FindFirstChild(spec)
		return if found and found:IsA("Sky") then found:Clone() else nil
	elseif typeof(spec) == "table" then
		local sky = Instance.new("Sky")
		for key, value in spec do
			pcall(function()
				(sky :: any)[key] = value
			end)
		end
		return sky
	end
	return nil
end

local function setSky(spec: any)
	local old = Lighting:FindFirstChild(SKY_NAME)
	if old then old:Destroy() end
	if hiddenSky then
		hiddenSky.Parent = Lighting
		hiddenSky = nil
	end
	local sky = if spec then skyFor(spec) else nil
	if not sky then return end
	-- Only one Sky renders: park the place's own while the event runs.
	local own = Lighting:FindFirstChildOfClass("Sky")
	if own then
		hiddenSky = own
		own.Parent = nil
	end
	sky.Name = SKY_NAME
	sky.Parent = Lighting
end

-- Blends to the event's look; anything an earlier event changed that this
-- one doesn't goes back to the place's own value. No event: all of it does.
local function apply(id: string?)
	if id == active then return end
	active = id
	local def = RollLogic.eventById(id)
	local look = def and def.Look

	local parts: { { instance: Instance, props: { [string]: any } } } = {}
	if look then
		if look.Lighting then table.insert(parts, { instance = Lighting, props = look.Lighting }) end
		if look.Atmosphere then table.insert(parts, { instance = atmosphere(), props = look.Atmosphere }) end
		if look.Grade then table.insert(parts, { instance = grade(), props = look.Grade }) end
	end

	-- Originals first (kept until no event runs), then this look on top.
	local targets: { [Instance]: { [string]: any } } = {}
	for _, part in parts do
		remember(part.instance, part.props)
	end
	for instance, props in saved do
		targets[instance] = table.clone(props)
	end
	for _, part in parts do
		local target = targets[part.instance]
		for key, value in part.props do
			target[key] = value
		end
	end
	for instance, target in targets do
		if instance.Parent then
			blend(instance, target)
		end
	end
	if not look then
		table.clear(saved)
	end
	setSky(if look then look.Sky else nil)
end

function EventLook.start()
	local function refresh()
		local id = ReplicatedStorage:GetAttribute("EventId")
		apply(if typeof(id) == "string" and id ~= "" then id else nil)
	end
	ReplicatedStorage:GetAttributeChangedSignal("EventId"):Connect(refresh)
	refresh()
end

return EventLook
