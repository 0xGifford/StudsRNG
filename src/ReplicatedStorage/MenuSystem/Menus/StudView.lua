--!strict
--[[
	ReplicatedStorage/MenuSystem/Menus/StudView

	A ViewportFrame that shows a stud. Set its attributes and it draws
	itself; change them and it redraws. No script per viewport.

		Viewport (ViewportFrame)   Stud = "Ember"

	ATTRIBUTES
		Stud            string   the stud's Id (Shared/Studs); "" shows nothing.
		                         This is the marker.
		StudVariant     string   Normal (default), Big, Huge, Jumbo, Shiny,
		                         Inverted (Shared/Variants)
		StudFit         number   how big it draws: 0.75 (Base) to 1.15 (Jumbo)
		                         by default, so bigger sizes read bigger
		ViewTurn        Vector3  degrees it's turned, default 22, 38, 0
		ViewSpin        number   degrees per second it spins, 0 = still
		ViewSilhouette  boolean  a dark shape ("not found yet")
		ViewSilhouetteColor Color3

	Rainbow studs cycle their hue while shown. Particles and lights, which
	don't draw in a viewport, are left out.

	API
		StudView.Start()
		StudView.Set(viewport, { Stud = id, StudVariant = name, ... })
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Component = require(script.Parent.Component)
local ViewportUtil = require(script.Parent.ViewportUtil)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Studs = require(Shared.Studs)
local Variants = require(Shared.Variants)
local StudVisuals = require(Shared.Util.StudVisuals)

local DEFAULT_TURN = Vector3.new(22, 38, 0)

-- Rainbow studs shown right now (weak: gone when their viewport goes).
local rainbow: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local rainbowLoop: RBXScriptConnection? = nil

local function watchRainbow(part: BasePart)
	rainbow[part] = true
	if rainbowLoop then return end
	local wait = 0
	rainbowLoop = RunService.RenderStepped:Connect(function(dt)
		wait += dt
		if wait < 0.08 then return end -- ~12 fps is plenty for a hue cycle
		wait = 0
		local t = os.clock()
		local any = false
		for shown in rainbow do
			if shown.Parent then
				any = true
				StudVisuals.step(shown, t)
			else
				rainbow[shown] = nil
			end
		end
		if not any and rainbowLoop then
			rainbowLoop:Disconnect()
			rainbowLoop = nil
		end
	end)
end

local function strip(part: BasePart)
	for _, d in part:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("SelectionBox") then
			d:Destroy()
		end
	end
end

local function movePart(object: Instance, turn: CFrame)
	if object:IsA("BasePart") then
		StudVisuals.place(object, turn * object.CFrame)
	end
end

local function render(viewport: ViewportFrame, state: { [string]: any })
	ViewportUtil.silhouette(viewport, state)

	local id = viewport:GetAttribute("Stud")
	local variantName = viewport:GetAttribute("StudVariant")
	local def = if type(id) == "string" then Studs.ById[id] else nil
	local variant = Variants.ById[if type(variantName) == "string" and variantName ~= "" then variantName else "Normal"]
	if not (def and variant) then
		state.key = nil
		ViewportUtil.clear(viewport)
		ViewportUtil.stopSpin(viewport)
		return
	end

	local turn = viewport:GetAttribute("ViewTurn")
	local fitAttr = viewport:GetAttribute("StudFit")
	local key = `{def.Id}/{variant.Name}/{tostring(turn)}/{tostring(fitAttr)}`
	if state.key ~= key then
		state.key = key
		-- Normalised so the framing fits, but bigger variants still read
		-- bigger: Base 0.75 → Jumbo 1.15 studs across.
		local fit = if typeof(fitAttr) == "number" and fitAttr > 0
			then fitAttr
			else 0.75 + math.clamp((StudVisuals.scaleOf(variant) - 1) / 2.6, 0, 1) * 0.4
		local part = StudVisuals.build(def, variant, fit)
		strip(part)
		ViewportUtil.clear(viewport)
		part.Name = ViewportUtil.SHOWN
		local degrees = if typeof(turn) == "Vector3" then turn else DEFAULT_TURN
		StudVisuals.place(part, CFrame.Angles(math.rad(degrees.X), math.rad(degrees.Y), math.rad(degrees.Z)))
		part.Parent = viewport
		ViewportUtil.camera(viewport)
		if part:GetAttribute("Rainbow") then
			watchRainbow(part)
		end
	end
	ViewportUtil.spin(viewport, movePart)
end

local StudView = Component.new({
	Marker = "Stud",
	Watch = { "StudVariant", "StudFit", "ViewTurn", "ViewSpin", "ViewSilhouette", "ViewSilhouetteColor" },
	Class = "ViewportFrame",
	Render = render,
	Cleanup = function(viewport: ViewportFrame)
		ViewportUtil.stopSpin(viewport)
	end,
})

return StudView
