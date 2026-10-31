--[[ 

StudVisuals
ModuleScript
/ReplicatedStorage/Shared/Util/StudVisuals

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Builds the visual for one stud + variant. Client-side only in practice
-- (followers, index viewports, roll reveal). Cosmetic: no gameplay reads it.
--
-- Your own stud model: put ONE Model (or Part / MeshPart) named
-- "StudTemplate" in ServerStorage (Systems/Templates copies it where clients
-- can see it). Build it at the size a normal stud should be. Every stud uses
-- it:
--   colour     every part takes the stud's colour (Inverted: the inverse,
--              Gold: gold), except parts with the attribute KeepColor = true
--   material   your parts keep their own material, unless the stud or
--              variant has a special one (Neon, Glass, Foil for Gold...)
--   size       Big / Huge / Jumbo scale the whole model up
--   effects    the stud's particles and glow, Shiny sparkles, the Shiny /
--              Inverted outline, Rainbow colour cycling
-- build() always returns one BasePart (for a Model: an invisible box around
-- it, carrying the model). Move it with StudVisuals.place, not .CFrame, so a
-- Model's parts come along (also inside ViewportFrames, where welds don't run).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = script.Parent.Parent
local Config = require(Shared.Config)
local Types = require(Shared.Types)

type StudDef = Types.StudDef
type VariantDef = Types.VariantDef

local StudVisuals = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- Particle presets referenced by name from Studs.luau. Color = nil means
-- "use the stud's own colour".
type Preset = {
	Texture: string,
	Rate: number,
	Lifetime: NumberRange,
	Speed: NumberRange,
	Size: NumberSequence,
	Transparency: NumberSequence?,
	LightEmission: number?,
	SpreadAngle: Vector2?,
	Acceleration: Vector3?,
	RotSpeed: NumberRange?,
	Color: Color3?,
}

local fade = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})

local PRESETS: { [string]: Preset } = {
	Dust = { Texture = SPARKLE, Rate = 3, Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(0.2, 0.5),
		Size = NumberSequence.new(0.15), Transparency = fade, SpreadAngle = Vector2.new(180, 180) },
	Embers = { Texture = FIRE, Rate = 10, Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(1, 2),
		Size = NumberSequence.new(0.25, 0), Transparency = fade, LightEmission = 1, Acceleration = Vector3.new(0, 2, 0) },
	Bubbles = { Texture = SPARKLE, Rate = 5, Lifetime = NumberRange.new(1, 1.5), Speed = NumberRange.new(0.5, 1),
		Size = NumberSequence.new(0.2), Transparency = fade, Acceleration = Vector3.new(0, 1.5, 0),
		Color = Color3.fromRGB(200, 240, 255) },
	Leaves = { Texture = SMOKE, Rate = 3, Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(0.3, 0.8),
		Size = NumberSequence.new(0.2), Transparency = fade, RotSpeed = NumberRange.new(-90, 90),
		Acceleration = Vector3.new(0, -1, 0) },
	Sparkle = { Texture = SPARKLE, Rate = 8, Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(0.5, 1.2),
		Size = NumberSequence.new(0.3, 0), Transparency = fade, LightEmission = 1, SpreadAngle = Vector2.new(180, 180) },
	Snow = { Texture = SPARKLE, Rate = 6, Lifetime = NumberRange.new(1.2, 1.8), Speed = NumberRange.new(0.2, 0.4),
		Size = NumberSequence.new(0.18), Transparency = fade, Acceleration = Vector3.new(0, -0.8, 0),
		Color = Color3.new(1, 1, 1), SpreadAngle = Vector2.new(180, 180) },
	Flare = { Texture = FIRE, Rate = 14, Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(1.5, 2.5),
		Size = NumberSequence.new(0.45, 0), Transparency = fade, LightEmission = 1, SpreadAngle = Vector2.new(180, 180) },
	Stars = { Texture = SPARKLE, Rate = 10, Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(0.3, 0.8),
		Size = NumberSequence.new(0.35, 0), Transparency = fade, LightEmission = 1, SpreadAngle = Vector2.new(180, 180),
		Color = Color3.fromRGB(220, 200, 255) },
	Void = { Texture = SMOKE, Rate = 12, Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(-1.5, -0.8),
		Size = NumberSequence.new(0.6, 0), Transparency = fade, SpreadAngle = Vector2.new(180, 180),
		Color = Color3.fromRGB(120, 40, 255) },
	Glitch = { Texture = SPARKLE, Rate = 20, Lifetime = NumberRange.new(0.1, 0.3), Speed = NumberRange.new(3, 6),
		Size = NumberSequence.new(0.25), LightEmission = 1, SpreadAngle = Vector2.new(180, 180) },

	-- Variant overlays
	Shine = { Texture = SPARKLE, Rate = 4, Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(0, 0.2),
		Size = NumberSequence.new(0.4, 0), Transparency = fade, LightEmission = 1, Color = Color3.new(1, 1, 1),
		SpreadAngle = Vector2.new(180, 180) },
	Gold = { Texture = SPARKLE, Rate = 6, Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(0.2, 0.6),
		Size = NumberSequence.new(0.3, 0), Transparency = fade, LightEmission = 1,
		Color = Color3.fromRGB(255, 220, 90), SpreadAngle = Vector2.new(180, 180) },
	Rainbow = { Texture = SPARKLE, Rate = 10, Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(0.4, 1),
		Size = NumberSequence.new(0.35, 0), Transparency = fade, LightEmission = 1,
		SpreadAngle = Vector2.new(180, 180) },
	Invert = { Texture = SPARKLE, Rate = 8, Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(-0.8, -0.3),
		Size = NumberSequence.new(0.35, 0), Transparency = fade, Color = Color3.fromRGB(20, 0, 40),
		SpreadAngle = Vector2.new(180, 180) },
}

local function scaleSequence(sequence: NumberSequence, factor: number): NumberSequence
	local points = {}
	for _, point in sequence.Keypoints do
		table.insert(points, NumberSequenceKeypoint.new(point.Time, point.Value * factor, point.Envelope * factor))
	end
	return NumberSequence.new(points)
end

local function makeEmitter(name: string, preset: Preset, color: Color3, scale: number?): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Texture = preset.Texture
	emitter.Rate = preset.Rate
	emitter.Lifetime = preset.Lifetime
	emitter.Speed = preset.Speed
	-- Bigger studs, bigger particles (gently: square root of the size).
	emitter.Size = if scale and scale > 1 then scaleSequence(preset.Size, math.sqrt(scale)) else preset.Size
	emitter.Transparency = preset.Transparency or NumberSequence.new(0)
	emitter.LightEmission = preset.LightEmission or 0
	emitter.SpreadAngle = preset.SpreadAngle or Vector2.new(30, 30)
	emitter.Acceleration = preset.Acceleration or Vector3.zero
	emitter.RotSpeed = preset.RotSpeed or NumberRange.new(0)
	emitter.Color = ColorSequence.new(preset.Color or color)
	emitter.LockedToPart = false
	return emitter
end

-- A Model-built stud: its root box → the parts it carries, where they sit
-- relative to it, and which of them take the stud's colour.
type Rig = { parts: { BasePart }, offsets: { CFrame }, tinted: { BasePart } }
local rigs: { [BasePart]: Rig } = setmetatable({}, { __mode = "k" }) :: any

local PLAIN = { [Enum.Material.Plastic] = true, [Enum.Material.SmoothPlastic] = true }

local function template(): Instance?
	local folder = ReplicatedStorage:FindFirstChild(Config.Visuals.TemplateFolder)
	local found = folder and folder:FindFirstChild(Config.Visuals.TemplateName)
	if found and (found:IsA("BasePart") or found:IsA("Model")) then
		return found
	end
	return nil
end

local function largest(size: Vector3): number
	return math.max(size.X, size.Y, size.Z, 1e-3)
end

-- A stud from a Model template: scaled, coloured, wrapped in a root box.
-- fit: the size of its largest side (index cells), else the variant's scale.
local function fromModel(source: Model, color: Color3, material: Enum.Material?, scale: number, fit: number?): BasePart
	local model = source:Clone()
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then d:Destroy() end
	end
	local _, extents = model:GetBoundingBox()
	local factor = if fit then fit / largest(extents) else scale
	if math.abs(factor - 1) > 1e-3 then
		model:ScaleTo(model:GetScale() * factor)
	end
	local cframe, size = model:GetBoundingBox()

	local root = Instance.new("Part")
	root.Size = size
	root.CFrame = cframe
	root.Transparency = 1
	root.Color = color

	local rig: Rig = { parts = {}, offsets = {}, tinted = {} }
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			if d:GetAttribute("KeepColor") ~= true then
				d.Color = color
				if material then
					d.Material = material
				end
				table.insert(rig.tinted, d)
			end
			table.insert(rig.parts, d)
			table.insert(rig.offsets, cframe:ToObjectSpace(d.CFrame))
		end
	end
	model.Parent = root
	rigs[root] = rig
	return root
end

-- Moves a built stud (and, for a Model template, every part of it).
function StudVisuals.place(part: BasePart, cframe: CFrame)
	part.CFrame = cframe
	local rig = rigs[part]
	if not rig then return end
	if part:IsDescendantOf(workspace) then
		local cframes = table.create(#rig.parts)
		for i, offset in rig.offsets do
			cframes[i] = cframe * offset
		end
		workspace:BulkMoveTo(rig.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	else
		-- Not in the world yet, or in a ViewportFrame.
		for i, piece in rig.parts do
			piece.CFrame = cframe * rig.offsets[i]
		end
	end
end

-- What a Highlight should outline: the model for a Model-built stud (its
-- root box is invisible), else the part itself.
function StudVisuals.adorneeOf(part: BasePart): Instance
	return if rigs[part] then part:FindFirstChildWhichIsA("Model") or part else part
end

local function basePart(): BasePart
	local found = template()
	if found and found:IsA("BasePart") then
		return found:Clone()
	end

	-- A classic brick: the studs surface on all six faces.
	local part = Instance.new("Part")
	part.Size = Config.Visuals.Size
	part.TopSurface = Enum.SurfaceType.Studs
	part.BottomSurface = Enum.SurfaceType.Studs
	part.FrontSurface = Enum.SurfaceType.Studs
	part.BackSurface = Enum.SurfaceType.Studs
	part.LeftSurface = Enum.SurfaceType.Studs
	part.RightSurface = Enum.SurfaceType.Studs
	if Config.Visuals.FallbackTextureId ~= "" then
		for _, face in Enum.NormalId:GetEnumItems() do
			local texture = Instance.new("Texture")
			texture.Face = face
			texture.Texture = Config.Visuals.FallbackTextureId
			texture.StudsPerTileU = Config.Visuals.Size.X
			texture.StudsPerTileV = Config.Visuals.Size.X
			texture.Parent = part
		end
	end
	return part
end

function StudVisuals.colorOf(def: StudDef, variant: VariantDef): Color3
	local color = variant.ColorOverride or def.Color
	if variant.Invert then
		return Color3.new(1 - color.R, 1 - color.G, 1 - color.B)
	end
	return color
end

-- How big the stud is: Big < Huge < Jumbo.
function StudVisuals.scaleOf(variant: VariantDef): number
	return variant.Scale or 1
end

-- Returns an unparented, anchored, non-colliding part.
-- fit: make its largest side this many studs (index cells) instead of
-- scaling it by the variant (Big / Huge / Jumbo).
-- Rainbow studs get the attribute "Rainbow" = true; call StudVisuals.step
-- each frame to animate them.
function StudVisuals.build(def: StudDef, variant: VariantDef, fit: number?): BasePart
	local scale = StudVisuals.scaleOf(variant)
	local color = StudVisuals.colorOf(def, variant)
	local material = variant.MaterialOverride or def.Material
	local source = template()

	local part: BasePart
	if source and source:IsA("Model") then
		-- Your model keeps its own materials unless this stud's is special.
		local special = if variant.MaterialOverride or not PLAIN[def.Material] then material else nil
		part = fromModel(source, color, special, scale, fit)
	else
		part = basePart()
		part.Size = if fit then part.Size * (fit / largest(part.Size)) else part.Size * scale
		part.Color = color
		part.Material = material
	end
	part.Name = `{def.Id}_{variant.Name}`
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true

	if def.Particle and PRESETS[def.Particle] then
		makeEmitter("StudParticles", PRESETS[def.Particle], color, scale).Parent = part
	end
	if variant.Effect and PRESETS[variant.Effect] then
		makeEmitter("VariantParticles", PRESETS[variant.Effect], color, scale).Parent = part
	end

	if def.Light or variant.Effect == "Rainbow" or variant.Effect == "Gold" then
		local light = Instance.new("PointLight")
		light.Name = "Glow"
		light.Color = color
		light.Brightness = 1.5
		light.Range = 6 * math.sqrt(scale)
		light.Shadows = false
		light.Parent = part
	end

	-- Shiny / Inverted stand out with an outline (any number of these can
	-- show at once, unlike Highlights; StudFollowers adds a Highlight to
	-- your own).
	if variant.Outline then
		local outline = Instance.new("SelectionBox")
		outline.Name = "Outline"
		outline.Adornee = part
		outline.Color3 = variant.Outline
		outline.LineThickness = 0.035 * part.Size.X
		outline.SurfaceTransparency = 1
		outline.Parent = part
	end

	if variant.Effect == "Rainbow" then
		part:SetAttribute("Rainbow", true)
	end

	return part
end

-- Per-frame cosmetic update (rainbow hue cycle). Cheap enough to call on
-- every visible stud.
function StudVisuals.step(part: BasePart, t: number)
	if not part:GetAttribute("Rainbow") then return end
	local color = Color3.fromHSV((t * 0.25) % 1, 0.75, 1)
	part.Color = color
	local rig = rigs[part]
	if rig then
		for _, piece in rig.tinted do
			piece.Color = color
		end
	end
	local glow = part:FindFirstChild("Glow")
	if glow and glow:IsA("PointLight") then
		glow.Color = color
	end
	local emitter = part:FindFirstChild("VariantParticles")
	if emitter and emitter:IsA("ParticleEmitter") then
		emitter.Color = ColorSequence.new(color)
	end
end

return StudVisuals
