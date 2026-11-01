--[[ 

StudCell
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/UI/StudCell

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Builds the square stud card used by the Index, Studs menu and roll reveal:
-- the kit's StudCell template with a ViewportFrame showing the actual 3D stud.
-- Rainbow studs cycle their hue while the cell is on screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local StudVisuals = require(Shared.Util.StudVisuals)

local Interface = require(script.Parent.Interface)
local Kit = require(script.Parent.Kit)

type StudDef = Types.StudDef
type VariantDef = Types.VariantDef

local StudCell = {}

local SILHOUETTE = Color3.new(0, 0, 0)

-- Weak set of rainbow parts currently inside a viewport.
local rainbowParts: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local rainbowLoop: RBXScriptConnection? = nil

local function ensureRainbowLoop()
	if rainbowLoop then return end
	local accumulator = 0
	rainbowLoop = RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.08 then return end -- ~12 fps is plenty for a hue cycle
		accumulator = 0
		local t = os.clock()
		for part in rainbowParts do
			if part.Parent then
				StudVisuals.step(part, t)
			else
				rainbowParts[part] = nil
			end
		end
	end)
end

local function strip(part: BasePart)
	-- Particles and lights don't render in a ViewportFrame; drop the cost.
	for _, child in part:GetChildren() do
		if child:IsA("ParticleEmitter") or child:IsA("Light") or child:IsA("SelectionBox") then
			child:Destroy()
		end
	end
end

-- A ViewportFrame showing one stud, slightly turned so three faces read.
function StudCell.viewport(def: StudDef, variant: VariantDef): ViewportFrame
	-- A copy of StarterGui.Templates.StudViewport (with its Camera).
	local viewport = Kit.template("StudViewport") :: ViewportFrame
	viewport.Name = "Viewport"
	if not viewport.CurrentCamera then
		viewport.CurrentCamera = viewport:FindFirstChildOfClass("Camera")
	end

	StudCell.setViewport(viewport, def, variant)
	return viewport
end

function StudCell.setViewport(viewport: ViewportFrame, def: StudDef, variant: VariantDef)
	local old = viewport:FindFirstChild("Stud")
	if old then old:Destroy() end

	-- Normalised so the framing fits, but bigger variants still read bigger:
	-- Base 0.75 → Jumbo 1.15 studs across.
	local fit = 0.75 + math.clamp((StudVisuals.scaleOf(variant) - 1) / 2.6, 0, 1) * 0.4
	local part = StudVisuals.build(def, variant, fit)
	part.Name = "Stud"
	StudVisuals.place(part, CFrame.Angles(math.rad(22), math.rad(38), 0))
	strip(part)
	part.Parent = viewport

	if part:GetAttribute("Rainbow") then
		rainbowParts[part] = true
		ensureRainbowLoop()
	end
end

function StudCell.setSilhouette(viewport: ViewportFrame, on: boolean)
	viewport.ImageColor3 = if on then SILHOUETTE else Color3.new(1, 1, 1)
	viewport.ImageTransparency = if on then 0.15 else 0
end

export type Cell = Frame

-- Clones the template, adds the viewport, colours the inner outline by rarity.
function StudCell.new(def: StudDef, variant: VariantDef): Cell
	local template = Interface.Templates:FindFirstChild("StudCell")
	assert(template and template:IsA("Frame"), "StarterGui.Templates.StudCell is missing")
	local cell = template:Clone()
	cell.Name = `{def.Id}:{variant.Name}`

	local viewport = StudCell.viewport(def, variant)
	viewport.Parent = cell

	StudCell.setRarity(cell, def.Rarity)
	Interface.setText(cell, def.Name)
	Interface.setText(cell, "", "Count", "Count")
	Interface.setText(cell, "", "Badge", "Badge")
	return cell
end

function StudCell.setRarity(cell: Frame, rarity: string)
	local color = Config.Rarities.Colors[rarity] or Color3.new(1, 1, 1)
	local inner = cell:FindFirstChild("Frame")
	local stroke = inner and inner:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
	end
end

function StudCell.setSelected(cell: Frame, on: boolean)
	local stroke = cell:FindFirstChild("Selected")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Enabled = on
	end
end

function StudCell.getViewport(cell: Frame): ViewportFrame?
	local viewport = cell:FindFirstChild("Viewport")
	return if viewport and viewport:IsA("ViewportFrame") then viewport else nil
end

return StudCell
