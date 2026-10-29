--[[ 

StudVisuals
ModuleScript
/ReplicatedStorage/Shared/Util/StudVisuals

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Builds the visual for one stud + variant. Client-side only in practice
-- (followers, index viewports, roll reveal). Cosmetic: no gameplay reads it.

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

local function makeEmitter(name: string, preset: Preset, color: Color3): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Texture = preset.Texture
	emitter.Rate = preset.Rate
	emitter.Lifetime = preset.Lifetime
	emitter.Speed = preset.Speed
	emitter.Size = preset.Size
	emitter.Transparency = preset.Transparency or NumberSequence.new(0)
	emitter.LightEmission = preset.LightEmission or 0
	emitter.SpreadAngle = preset.SpreadAngle or Vector2.new(30, 30)
	emitter.Acceleration = preset.Acceleration or Vector3.zero
	emitter.RotSpeed = preset.RotSpeed or NumberRange.new(0)
	emitter.Color = ColorSequence.new(preset.Color or color)
	emitter.LockedToPart = false
	return emitter
end

local function basePart(): BasePart
	local folder = ReplicatedStorage:FindFirstChild(Config.Visuals.TemplateFolder)
	local template = folder and folder:FindFirstChild(Config.Visuals.TemplateName)
	if template and template:IsA("BasePart") then
		return template:Clone()
	end

	local part = Instance.new("Part")
	part.Size = Config.Visuals.Size
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
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
-- Rainbow studs get the attribute "Rainbow" = true; call StudVisuals.step
-- each frame to animate them.
function StudVisuals.build(def: StudDef, variant: VariantDef): BasePart
	local part = basePart()
	part.Name = `{def.Id}_{variant.Name}`
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true

	part.Size *= StudVisuals.scaleOf(variant)
	local color = StudVisuals.colorOf(def, variant)
	part.Color = color
	part.Material = variant.MaterialOverride or def.Material

	if def.Particle and PRESETS[def.Particle] then
		makeEmitter("StudParticles", PRESETS[def.Particle], color).Parent = part
	end
	if variant.Effect and PRESETS[variant.Effect] then
		makeEmitter("VariantParticles", PRESETS[variant.Effect], color).Parent = part
	end

	if def.Light or variant.Effect == "Rainbow" or variant.Effect == "Gold" then
		local light = Instance.new("PointLight")
		light.Name = "Glow"
		light.Color = color
		light.Brightness = 1.5
		light.Range = 6
		light.Shadows = false
		light.Parent = part
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
