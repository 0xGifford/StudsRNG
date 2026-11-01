--!strict
--[[
	ReplicatedStorage/MenuSystem/Menus/ZoneView

	A ViewportFrame that shows a zone. Set its attributes and it draws
	itself; change them and it redraws.

		Viewport (ViewportFrame)   Zone = "003"

	What it shows, first that exists:
		1. your own preview: a Model named after the zone's Id (or "Zone3")
		   in ReplicatedStorage.Assets.ZonePreviews
		2. the zone's enemy (ReplicatedStorage.Assets.EnemyTemplates.Enemy),
		   parts with Tint = true in the zone's colour, its idle face
		3. the zone's rarest stud
	ZoneShow picks one instead of that order.

	ATTRIBUTES
		Zone            string   the zone's Id ("001"); "" shows nothing.
		                         This is the marker.
		ZoneShow        string   "Preview", "Enemy" or "Stud"
		ViewTurn        Vector3  degrees it's turned, default 10, 30, 0
		ViewSpin        number   degrees per second it spins, 0 = still
		ViewZoom        number   1 = framed snugly, less = closer
		ViewSilhouette  boolean  a dark shape (a zone not unlocked yet)
		ViewSilhouetteColor Color3

	API
		ZoneView.Start()
		ZoneView.Set(viewport, { Zone = id, ... })
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Component = require(script.Parent.Component)
local ViewportUtil = require(script.Parent.ViewportUtil)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config)
local Zones = require(Shared.Zones)
local Enemies = require(Shared.Enemies)
local Studs = require(Shared.Studs)
local Variants = require(Shared.Variants)
local StudVisuals = require(Shared.Util.StudVisuals)

local DEFAULT_TURN = Vector3.new(10, 30, 0)

local function assets(): Instance?
	return ReplicatedStorage:FindFirstChild(GameConfig.Visuals.TemplateFolder)
end

local function preview(zone: Zones.ZoneDef): Model?
	local folder = assets()
	local previews = folder and folder:FindFirstChild("ZonePreviews")
	if not previews then return nil end
	local found = previews:FindFirstChild(zone.Id) or previews:FindFirstChild(`Zone{zone.Order}`)
	return if found and found:IsA("Model") then found:Clone() else nil
end

local function enemy(zone: Zones.ZoneDef): Model?
	local folder = assets()
	local templates = folder and folder:FindFirstChild(GameConfig.Visuals.EnemyTemplateFolder)
	local source = templates and templates:FindFirstChild("Enemy")
	if not (source and source:IsA("Model")) then return nil end
	local model = source:Clone()
	local def = Enemies.forZone(zone.Id)
	local color = if def then def.Color else zone.Color
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			if d:GetAttribute("Tint") == true then
				d.Color = color
			end
		elseif d:IsA("Decal") and d.Parent and d.Parent.Name == "Body" then
			d.Texture = GameConfig.Visuals.EnemyFaces.Enemy
		elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		end
	end
	return model
end

local function rarestStud(zone: Zones.ZoneDef): Model?
	local best = nil
	for _, def in Studs.List do
		if def.World == zone.Id and not def.Drop and (not best or def.OneIn > best.OneIn) then
			best = def
		end
	end
	if not best then return nil end
	-- Wrapped in a Model so it frames like the others.
	local part = StudVisuals.build(best, Variants.ById.Normal, 1)
	for _, d in part:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("SelectionBox") then
			d:Destroy()
		end
	end
	local model = Instance.new("Model")
	part.Parent = model
	model.PrimaryPart = part
	return model
end

local function render(viewport: ViewportFrame, state: { [string]: any }): ()
	ViewportUtil.silhouette(viewport, state)

	local id = viewport:GetAttribute("Zone")
	local zone = if type(id) == "string" then Zones.ById[id] else nil
	if not zone then
		state.key = nil
		ViewportUtil.clear(viewport)
		ViewportUtil.stopSpin(viewport)
		return
	end

	local show = viewport:GetAttribute("ZoneShow")
	local key = `{zone.Id}/{tostring(show)}/{tostring(viewport:GetAttribute("ViewTurn"))}/{tostring(viewport:GetAttribute("ViewZoom"))}`
	if state.key ~= key and not ViewportUtil.onScreen(viewport) then
		-- Built when it scrolls into view (a long Teleporter list costs
		-- nothing until then).
		state.key = nil
		ViewportUtil.clear(viewport)
		ViewportUtil.whenOnScreen(viewport, function()
			render(viewport, state)
		end)
		return
	end
	ViewportUtil.cancelWait(viewport)
	if state.key ~= key then
		state.key = key
		local model: Model?
		if show == "Preview" then
			model = preview(zone)
		elseif show == "Enemy" then
			model = enemy(zone)
		elseif show == "Stud" then
			model = rarestStud(zone)
		else
			model = preview(zone) or enemy(zone) or rarestStud(zone)
		end
		if model then
			ViewportUtil.show(viewport, model, DEFAULT_TURN)
		else
			ViewportUtil.clear(viewport)
		end
	end
	ViewportUtil.spin(viewport)
end

local ZoneView = Component.new({
	Marker = "Zone",
	Watch = { "ZoneShow", "ViewTurn", "ViewSpin", "ViewZoom", "ViewSilhouette", "ViewSilhouetteColor" },
	Class = "ViewportFrame",
	Render = render,
	Cleanup = function(viewport: ViewportFrame)
		ViewportUtil.cancelWait(viewport)
		ViewportUtil.stopSpin(viewport)
	end,
})

return ZoneView
