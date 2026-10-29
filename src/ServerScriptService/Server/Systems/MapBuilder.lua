--[[

MapBuilder
ModuleScript
/ServerScriptService/Server/Systems/MapBuilder

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Builds the playable map at server start (Config.Map), Slime RNG style:
-- every zone is a wide biome valley walled in by chunky cliffs, joined to
-- the next zone (along +Z) by a canyon pass with a gate. Everything is
-- plain Parts; the look of each biome comes from Shared/MapThemes.
--
-- Everything it builds carries the same tags and attributes as a hand-built
-- map (Shared/Tags), and the rest of the game only ever looks things up by
-- tag. workspace.Zones.<ZoneId> (Model, tagged Zone, attributes
-- ZoneId/Center/ZoneSize) contains
--   Ground                  floor, patches, trail, sea (Beach / Islands)
--   Cliffs                  the valley walls (rock chunks or cloud banks)
--   Walls                   invisible walls behind the cliffs
--   Keyboard                tagged Keyboard; KeyCapper keys: Model{Hitbox
--                           (tagged), Cap} with World / Value / Group
--                           attributes, so the KeyCapper runtime animates
--                           them and PressTracker pays them exactly like
--                           hand-placed keys
--   Spawn                   tagged ZoneSpawn (a SpawnLocation in the first zone)
--   Gate, Barrier           tagged ZoneGate / ZoneBarrier: entrance arch and
--                           force field (opens locally when owned, see
--                           ZonesMenu)
--   Props                   trees, rocks, crystals... and the biome set pieces
--
-- A zone that already exists (a Zone-tagged instance with its id, or
-- workspace.Zones.<ZoneId>) is skipped, so any zone can be replaced by a
-- hand-built one; untagged hand-built zones under workspace.Zones get the
-- Zone / ZoneSpawn / ZoneBarrier tags from their names. Players who fall
-- out of the map are put back at the nearest zone they own.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Zones = require(Shared.Zones)
local MapThemes = require(Shared.MapThemes)
local Tags = require(Shared.Tags)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)

type Theme = MapThemes.Theme

local MapBuilder = {}

local MapConfig = Config.Map
local KEY_SIZE = Vector3.new(3, 1.368114709854126, 3)
local KEY_PITCH = 3.15
local HITBOX_XZ = 0.8123 -- KeyCapper's hitbox footprint ratio
local MESH_YAW = CFrame.Angles(0, math.rad(-90), 0)
local PASS_WIDTH = 26 -- canyon pass between zones
local WALL_HEIGHT = 140
local FALL_DEPTH = 70
local CLIFF_SPACING = 13
local KEYBOARD_OFFSET = Vector3.new(0, 0, 8) -- from the zone centre
local MAX_LIGHTS = 10 -- per zone

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)

local rng = Random.new(1337) -- fixed seed: the same map every server
local lightsLeft = MAX_LIGHTS

type ZoneBuild = { def: Zones.ZoneDef, center: Vector3, model: Model }
local built: { ZoneBuild } = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function shade(color: Color3, amount: number): Color3
	return if amount >= 0 then color:Lerp(Color3.new(1, 1, 1), amount) else color:Lerp(Color3.new(0, 0, 0), -amount)
end

--------------------------------------------------------------------------
-- Part helpers
--------------------------------------------------------------------------

type PartProps = {
	Name: string?,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	Shape: Enum.PartType?,
	CanCollide: boolean?,
	CastShadow: boolean?,
}

local function part(parent: Instance, props: PartProps): Part
	local p = Instance.new("Part")
	p.Name = props.Name or "Part"
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color or Color3.fromRGB(160, 160, 160)
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Transparency = props.Transparency or 0
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	p.Parent = parent
	return p
end

-- Decoration: doesn't collide (unless asked), can't be touched or queried.
local function deco(parent: Instance, props: PartProps): Part
	props.CanCollide = if props.CanCollide == nil then false else props.CanCollide
	local p = part(parent, props)
	p.CanTouch = false
	p.CanQuery = false
	return p
end

local function block(parent: Instance, cframe: CFrame, size: Vector3, color: Color3, material: Enum.Material, collide: boolean?): Part
	return deco(parent, { Size = size, CFrame = cframe, Color = color, Material = material, CanCollide = collide })
end

local function ball(parent: Instance, position: Vector3, size: number, color: Color3, material: Enum.Material?): Part
	return deco(parent, {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * size,
		CFrame = CFrame.new(position),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

-- Upright cylinder centred on position.
local function cylinder(parent: Instance, position: Vector3, height: number, diameter: number, color: Color3, material: Enum.Material?, collide: boolean?): Part
	return deco(parent, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(position) * UPRIGHT,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = collide,
	})
end

local function glow(parent: Instance, size: Vector3, cframe: CFrame, color: Color3): Part
	return deco(parent, { Name = "Glow", Size = size, CFrame = cframe, Color = color, Material = Enum.Material.Neon, CastShadow = false })
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number)
	if lightsLeft <= 0 then return end
	lightsLeft -= 1
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
end

local function emitter(parent: BasePart, props: { [string]: any })
	local e = Instance.new("ParticleEmitter")
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
end

local function sign(parent: BasePart, face: Enum.NormalId, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.FontFace = FONT
	label.Text = text
	label.TextColor3 = color
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 20, 25)
	stroke.Thickness = 4
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = parent
end

--------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------

local capTemplate: BasePart? = nil

local function getCapTemplate(): BasePart
	if capTemplate then return capTemplate end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local found = assets and assets:FindFirstChild("KeyCap")
	if found and found:IsA("BasePart") then
		capTemplate = found
		return found
	end
	-- No mesh: a plain block keeps the map playable.
	warn("[MapBuilder] ReplicatedStorage.Assets.KeyCap missing; using plain keycaps")
	local fallback = Instance.new("Part")
	fallback.Size = KEY_SIZE
	fallback.Material = Enum.Material.SmoothPlastic
	capTemplate = fallback
	return fallback
end

local function placeKey(parent: Instance, cframe: CFrame, color: Color3, material: Enum.Material, zoneId: string)
	local model = Instance.new("Model")
	model.Name = "Key"

	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(KEY_SIZE.X * HITBOX_XZ, KEY_SIZE.Y, KEY_SIZE.Z * HITBOX_XZ)
	hitbox.CFrame = cframe
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true
	hitbox.Transparency = 1
	hitbox.Parent = model

	local cap = getCapTemplate():Clone()
	cap.Name = "Cap"
	cap.CFrame = cframe * MESH_YAW
	cap.Anchored = true
	cap.CanCollide = false
	cap.CanTouch = false
	cap.CanQuery = false
	cap.CastShadow = false
	cap.Color = color
	cap.Material = material
	cap.Parent = model

	model.PrimaryPart = hitbox
	model:SetAttribute("Letter", "")
	model:SetAttribute("Group", zoneId)
	model:SetAttribute(Config.Press.AttrWorld, zoneId)
	model:SetAttribute(Config.Press.AttrValue, 1)
	model.Parent = parent
	CollectionService:AddTag(hitbox, Config.Press.HitboxTag)
	CollectionService:AddTag(model, "KeyCapper_Key")
end

local function keyboardSize(): Vector3
	return Vector3.new(MapConfig.KeyCols * KEY_PITCH, 0, MapConfig.KeyRows * KEY_PITCH)
end

local function buildKeyboard(zone: Model, center: Vector3, def: Zones.ZoneDef, theme: Theme)
	local folder = Instance.new("Folder")
	folder.Name = "Keyboard"
	folder:SetAttribute(Tags.Attr.ZoneId, def.Id)
	CollectionService:AddTag(folder, Tags.Keyboard)
	folder.Parent = zone

	local cols, rows = MapConfig.KeyCols, MapConfig.KeyRows
	local size = keyboardSize()

	-- The plate the keys sit in, with a glowing rim.
	local plate = part(zone, {
		Name = "KeyboardPlate",
		Size = Vector3.new(size.X + 4, 0.8, size.Z + 4),
		CFrame = CFrame.new(center + Vector3.new(0, 0.4, 0)),
		Color = theme.Plate,
		Material = Enum.Material.SmoothPlastic,
	})
	for _, side in { -1, 1 } do
		glow(zone, Vector3.new(size.X + 4.4, 0.35, 0.5), CFrame.new(center + Vector3.new(0, 0.7, side * (size.Z + 4) / 2)), theme.Trim)
		glow(zone, Vector3.new(0.5, 0.35, size.Z + 4.4), CFrame.new(center + Vector3.new(side * (size.X + 4) / 2, 0.7, 0)), theme.Trim)
	end

	local top = plate.Position.Y + plate.Size.Y / 2
	for row = 1, rows do
		local color = theme.Keys[(row - 1) % #theme.Keys + 1]
		for col = 1, cols do
			local x = (col - (cols + 1) / 2) * KEY_PITCH
			local z = (row - (rows + 1) / 2) * KEY_PITCH
			placeKey(folder, CFrame.new(center.X + x, top + KEY_SIZE.Y / 2, center.Z + z), color, theme.KeyMaterial, def.Id)
		end
	end
end

--------------------------------------------------------------------------
-- Cliffs
--------------------------------------------------------------------------

-- One chunk of valley wall at `base` (on the valley edge, floor height),
-- leaning out along `outward`. Chunky rotated blocks, Slime RNG style, with
-- a grass / snow cap when the theme has one.
local function rockChunk(parent: Instance, base: Vector3, outward: Vector3, theme: Theme, heightScale: number, distance: number)
	local width = rng:NextNumber(16, 26)
	local depth = rng:NextNumber(14, 22)
	local height = theme.CliffHeight * heightScale * rng:NextNumber(0.75, 1.15)
	local yaw = math.atan2(-outward.X, -outward.Z) + rng:NextNumber(-0.35, 0.35)
	local position = base + outward * (distance + depth / 2 - rng:NextNumber(1, 4))
	local tilt = CFrame.Angles(rng:NextNumber(-0.08, 0.08), 0, rng:NextNumber(-0.08, 0.08))
	local color = pick(theme.Rock)
	local main = block(parent, CFrame.new(position.X, base.Y - 8 + height / 2, position.Z) * CFrame.Angles(0, yaw, 0) * tilt,
		Vector3.new(width, height + 8, depth), color, theme.RockMaterial, true)

	-- A smaller block on top breaks up the silhouette.
	local topSize = Vector3.new(width * rng:NextNumber(0.55, 0.8), height * rng:NextNumber(0.2, 0.35), depth * rng:NextNumber(0.55, 0.8))
	local topCFrame = main.CFrame * CFrame.new(rng:NextNumber(-3, 3), main.Size.Y / 2 + topSize.Y / 2 - 1, rng:NextNumber(-2, 2))
		* CFrame.Angles(0, rng:NextNumber(-0.6, 0.6), 0)
	local topBlock = block(parent, topCFrame, topSize, shade(color, rng:NextNumber(-0.08, 0.08)), theme.RockMaterial, true)

	local cap = theme.Cap
	if cap then
		block(parent, CFrame.new(main.Position + main.CFrame.UpVector * (main.Size.Y / 2 + 0.3)) * (main.CFrame - main.CFrame.Position),
			Vector3.new(width + 0.6, 0.8, depth + 0.6), cap, theme.CapMaterial or Enum.Material.Grass)
		block(parent, topBlock.CFrame * CFrame.new(0, topSize.Y / 2 + 0.3, 0), Vector3.new(topSize.X + 0.6, 0.8, topSize.Z + 0.6), cap,
			theme.CapMaterial or Enum.Material.Grass)
	end
end

-- Heaven's walls: banks of cloud.
local function cloudChunk(parent: Instance, base: Vector3, outward: Vector3, theme: Theme, heightScale: number, distance: number)
	local height = theme.CliffHeight * heightScale
	for _ = 1, 3 do
		local size = rng:NextNumber(14, 24) * heightScale
		local offset = outward * (distance + size * 0.35 + rng:NextNumber(0, 6)) + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-4, height * 0.5), rng:NextNumber(-6, 6))
		local puff = ball(parent, base + offset, size, pick(theme.Rock), Enum.Material.SmoothPlastic)
		puff.CastShadow = false
	end
end

local function cliffChunk(parent: Instance, base: Vector3, outward: Vector3, theme: Theme, heightScale: number, distance: number)
	if theme.CliffStyle == "Cloud" then
		cloudChunk(parent, base, outward, theme, heightScale, distance)
	else
		rockChunk(parent, base, outward, theme, heightScale, distance)
	end
end

-- Walls the valley in: an inner row of cliffs on the edge and a taller,
-- further-out row behind it for depth. Gaps are left for the passes.
local function buildCliffs(zone: Model, center: Vector3, theme: Theme, hasEntrance: boolean, hasExit: boolean)
	local folder = Instance.new("Folder")
	folder.Name = "Cliffs"
	folder.Parent = zone
	local halfW, halfD = MapConfig.ZoneWidth / 2, MapConfig.ZoneDepth / 2
	local gap = PASS_WIDTH / 2 + 3

	-- gapped: leave the middle of this edge open for a pass. Chunks are up
	-- to 26 wide, so each row keeps clear of the opening by its own margin.
	local function edge(from: Vector3, to: Vector3, outward: Vector3, gapped: boolean)
		local length = (to - from).Magnitude
		local steps = math.max(1, math.floor(length / CLIFF_SPACING))
		for i = 0, steps do
			local spot = from:Lerp(to, i / steps)
			local dx = math.abs(spot.X - center.X)
			if not (gapped and dx < gap + 10) then
				cliffChunk(folder, spot, outward, theme, 1, 0)
			end
			if not (gapped and dx < gap + 24) then
				cliffChunk(folder, spot, outward, theme, 1.45, 14)
			end
		end
	end

	local y = center.Y
	-- -Z (entrance) and +Z (exit) ends
	edge(Vector3.new(center.X - halfW - 10, y, center.Z - halfD), Vector3.new(center.X + halfW + 10, y, center.Z - halfD), Vector3.new(0, 0, -1), hasEntrance)
	edge(Vector3.new(center.X - halfW - 10, y, center.Z + halfD), Vector3.new(center.X + halfW + 10, y, center.Z + halfD), Vector3.new(0, 0, 1), hasExit)
	-- Sides (the sea side stays open)
	edge(Vector3.new(center.X - halfW, y, center.Z - halfD), Vector3.new(center.X - halfW, y, center.Z + halfD), Vector3.new(-1, 0, 0), false)
	if not theme.Water then
		edge(Vector3.new(center.X + halfW, y, center.Z - halfD), Vector3.new(center.X + halfW, y, center.Z + halfD), Vector3.new(1, 0, 0), false)
	end
end

-- Invisible walls on the valley edge (gaps for the passes).
local function buildWalls(zone: Model, center: Vector3, hasEntrance: boolean, hasExit: boolean)
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = zone
	local halfW, halfD = MapConfig.ZoneWidth / 2, MapConfig.ZoneDepth / 2
	local function wall(size: Vector3, position: Vector3)
		local w = part(walls, { Name = "Wall", Size = size, CFrame = CFrame.new(position), Transparency = 1, CastShadow = false })
		w.CanQuery = false
	end
	local h = WALL_HEIGHT
	for _, side in { -1, 1 } do
		wall(Vector3.new(1, h, MapConfig.ZoneDepth + 2), center + Vector3.new(side * (halfW + 0.5), h / 2, 0))
	end
	for _, endSide in { -1, 1 } do
		local open = if endSide < 0 then hasEntrance else hasExit
		local z = endSide * (halfD + 0.5)
		if open then
			local segment = (MapConfig.ZoneWidth - PASS_WIDTH) / 2
			for _, side in { -1, 1 } do
				wall(Vector3.new(segment, h, 1), center + Vector3.new(side * (PASS_WIDTH / 2 + segment / 2), h / 2, z))
			end
		else
			wall(Vector3.new(MapConfig.ZoneWidth, h, 1), center + Vector3.new(0, h / 2, z))
		end
	end
end

--------------------------------------------------------------------------
-- Ground
--------------------------------------------------------------------------

local function buildGround(zone: Model, center: Vector3, theme: Theme): BasePart
	local folder = Instance.new("Folder")
	folder.Name = "Ground"
	folder.Parent = zone
	local W, D = MapConfig.ZoneWidth, MapConfig.ZoneDepth
	local halfW, halfD = W / 2, D / 2

	local floor = part(folder, {
		Name = "Floor",
		Size = Vector3.new(W + 4, 4, D + 4),
		CFrame = CFrame.new(center - Vector3.new(0, 2, 0)),
		Color = theme.Floor,
		Material = theme.FloorMaterial,
	})
	-- The land the cliffs stand on.
	local under = part(folder, {
		Name = "Underside",
		Size = Vector3.new(W + 90, 40, D + 90),
		CFrame = CFrame.new(center - Vector3.new(0, 24.05, 0)),
		Color = shade(pick(theme.Rock), -0.35),
		Material = theme.RockMaterial,
		CastShadow = false,
	})
	under.CanQuery = false

	-- Low-poly patches break the floor up.
	for _ = 1, 28 do
		local size = Vector3.new(rng:NextNumber(6, 22), 0.2, rng:NextNumber(6, 22))
		local x = rng:NextNumber(-halfW + 6, halfW - 6)
		local z = rng:NextNumber(-halfD + 6, halfD - 6)
		block(folder, CFrame.new(center + Vector3.new(x, 0.1, z)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), size, pick(theme.Patches), theme.FloorMaterial)
	end

	-- The trail: entrance → keyboard → exit, wobbling a little.
	local segments = 8
	local length = D / segments
	local lastX = 0
	for i = 1, segments do
		local z = -halfD + (i - 0.5) * length
		local x = if i == 1 or i == segments then 0 else rng:NextNumber(-4, 4)
		local mid = (x + lastX) / 2
		block(folder, CFrame.new(center + Vector3.new(mid, 0.15, z)) * CFrame.Angles(0, (x - lastX) / length, 0), Vector3.new(12, 0.3, length + 2),
			theme.Path, theme.PathMaterial)
		lastX = x
	end

	-- Sea along +X: shallows over the sand, open water out to the horizon.
	local water = theme.Water
	if water then
		local shallows = 30
		local shallow = block(folder, CFrame.new(center + Vector3.new(halfW - shallows / 2, 0.25, 0)), Vector3.new(shallows, 0.3, D + 4), shade(water, 0.25),
			Enum.Material.Glass)
		shallow.Transparency = 0.35
		local foam = block(folder, CFrame.new(center + Vector3.new(halfW - shallows, 0.32, 0)), Vector3.new(1.4, 0.3, D + 4), Color3.new(1, 1, 1),
			Enum.Material.SmoothPlastic)
		foam.Transparency = 0.2
		local sea = block(folder, CFrame.new(center + Vector3.new(halfW + 302, -0.4, 0)), Vector3.new(600, 1, D + 600), water, Enum.Material.Glass)
		sea.Transparency = 0.15
		sea.CastShadow = false
	end
	return floor
end

--------------------------------------------------------------------------
-- Props
--------------------------------------------------------------------------

local PROPS: { [string]: (Instance, Vector3, Theme) -> () } = {}

local GREENS = { rgb(80, 170, 60), rgb(96, 188, 72), rgb(70, 150, 56), rgb(110, 196, 80) }
local BARK = rgb(120, 84, 56)

PROPS.Tree = function(parent, at, _theme)
	local height = rng:NextNumber(7, 11)
	cylinder(parent, at + Vector3.new(0, height / 2, 0), height, rng:NextNumber(1.4, 2), BARK, Enum.Material.Wood, true)
	for _ = 1, 4 do
		ball(parent, at + Vector3.new(rng:NextNumber(-2.5, 2.5), height + rng:NextNumber(-1, 2.5), rng:NextNumber(-2.5, 2.5)), rng:NextNumber(6, 9),
			pick(GREENS), Enum.Material.Grass)
	end
end

PROPS.Pine = function(parent, at, theme)
	local snowy = theme.FloorMaterial == Enum.Material.Snow
	cylinder(parent, at + Vector3.new(0, 2, 0), 4, 1.4, BARK, Enum.Material.Wood, true)
	local scale = rng:NextNumber(0.85, 1.25)
	for tier = 1, 4 do
		local size = (10 - tier * 2.1) * scale
		local cf = CFrame.new(at + Vector3.new(0, (2.5 + tier * 2.6) * scale, 0)) * CFrame.Angles(0, math.rad(45 + tier * 17), 0)
		block(parent, cf, Vector3.new(size, 3 * scale, size), rgb(40, 110, 70), Enum.Material.Grass)
		if snowy then
			block(parent, cf * CFrame.new(0, 1.6 * scale, 0), Vector3.new(size * 0.8, 0.6, size * 0.8), rgb(245, 250, 255), Enum.Material.Snow)
		end
	end
end

PROPS.Palm = function(parent, at, _theme)
	local cf = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local bend = math.rad(rng:NextNumber(5, 9))
	for _ = 1, 6 do
		cf *= CFrame.Angles(bend, 0, 0)
		block(parent, cf * CFrame.new(0, 1.4, 0), Vector3.new(1.3, 2.9, 1.3), rgb(150, 110, 70), Enum.Material.Wood, true)
		cf *= CFrame.new(0, 2.8, 0)
	end
	local top = cf.Position
	for k = 1, 7 do
		local leaf = CFrame.new(top) * CFrame.Angles(0, k * math.pi * 2 / 7, 0) * CFrame.Angles(math.rad(-22), 0, 0) * CFrame.new(0, 0, -3.6)
		block(parent, leaf, Vector3.new(2, 0.3, 7.5), pick(GREENS), Enum.Material.Grass)
	end
	for k = 1, 3 do
		ball(parent, top + Vector3.new(math.cos(k * 2.1) * 0.9, -0.8, math.sin(k * 2.1) * 0.9), 1, rgb(110, 76, 44))
	end
end

PROPS.Bush = function(parent, at, _theme)
	for _ = 1, 3 do
		ball(parent, at + Vector3.new(rng:NextNumber(-1.6, 1.6), rng:NextNumber(0.8, 1.6), rng:NextNumber(-1.6, 1.6)), rng:NextNumber(3, 4.5),
			pick(GREENS), Enum.Material.Grass)
	end
end

PROPS.Flowers = function(parent, at, _theme)
	local colors = { rgb(255, 90, 120), rgb(255, 220, 80), rgb(170, 120, 255), rgb(255, 255, 255), rgb(255, 150, 60) }
	for _ = 1, 7 do
		local spot = at + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
		block(parent, CFrame.new(spot + Vector3.new(0, 0.5, 0)), Vector3.new(0.2, 1, 0.2), rgb(70, 150, 60), Enum.Material.Grass)
		ball(parent, spot + Vector3.new(0, 1.1, 0), 0.8, pick(colors))
	end
end

PROPS.Boulder = function(parent, at, theme)
	local color = pick(theme.Rock)
	for i = 1, 2 do
		local size = Vector3.new(rng:NextNumber(4, 8), rng:NextNumber(3, 6), rng:NextNumber(4, 8)) * (if i == 1 then 1 else 0.6)
		local cf = CFrame.new(at + Vector3.new(rng:NextNumber(-2, 2) * (i - 1), size.Y / 2 - 0.5, rng:NextNumber(-2, 2) * (i - 1)))
			* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3))
		block(parent, cf, size, shade(color, rng:NextNumber(-0.1, 0.1)), theme.RockMaterial, true)
	end
end

PROPS.Umbrella = function(parent, at, _theme)
	local colors = { rgb(255, 80, 80), rgb(60, 160, 255), rgb(255, 200, 60), rgb(80, 220, 140) }
	local color = pick(colors)
	cylinder(parent, at + Vector3.new(0, 3.5, 0), 7, 0.3, rgb(240, 240, 240), Enum.Material.SmoothPlastic, true)
	cylinder(parent, at + Vector3.new(0, 7, 0), 0.5, 9, color)
	cylinder(parent, at + Vector3.new(0, 7.3, 0), 0.4, 5, rgb(255, 255, 255))
	block(parent, CFrame.new(at + Vector3.new(3, 0.12, 1)) * CFrame.Angles(0, rng:NextNumber(0, 1), 0), Vector3.new(3, 0.1, 6), pick(colors), Enum.Material.Fabric)
end

PROPS.Shells = function(parent, at, _theme)
	local colors = { rgb(255, 200, 210), rgb(255, 245, 230), rgb(255, 150, 120) }
	for _ = 1, 5 do
		ball(parent, at + Vector3.new(rng:NextNumber(-3, 3), 0.25, rng:NextNumber(-3, 3)), rng:NextNumber(0.6, 1.1), pick(colors))
	end
	-- Starfish
	local star = at + Vector3.new(rng:NextNumber(-2, 2), 0.15, rng:NextNumber(-2, 2))
	for k = 1, 5 do
		block(parent, CFrame.new(star) * CFrame.Angles(0, k * math.pi * 2 / 5, 0) * CFrame.new(0, 0, -0.6), Vector3.new(0.45, 0.2, 1.2), rgb(255, 120, 70))
	end
end

PROPS.IceSpike = function(parent, at, _theme)
	for _ = 1, rng:NextInteger(3, 4) do
		local h = rng:NextNumber(6, 15)
		local w = rng:NextNumber(1.6, 3)
		local cf = CFrame.new(at + Vector3.new(rng:NextNumber(-2, 2), h / 2 - 0.5, rng:NextNumber(-2, 2)))
			* CFrame.Angles(math.rad(rng:NextNumber(-20, 20)), rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-20, 20)))
		local spike = block(parent, cf, Vector3.new(w, h, w), rgb(170, 225, 255), Enum.Material.Ice, true)
		spike.Transparency = 0.15
	end
end

PROPS.Snowman = function(parent, at, _theme)
	local white = rgb(250, 252, 255)
	ball(parent, at + Vector3.new(0, 1.8, 0), 4, white, Enum.Material.Snow).CanCollide = true
	ball(parent, at + Vector3.new(0, 4.6, 0), 3, white, Enum.Material.Snow)
	ball(parent, at + Vector3.new(0, 6.6, 0), 2.1, white, Enum.Material.Snow)
	for _, x in { -0.4, 0.4 } do
		ball(parent, at + Vector3.new(x, 6.9, -0.95), 0.3, rgb(20, 20, 20))
	end
	block(parent, CFrame.new(at + Vector3.new(0, 6.6, -1.3)), Vector3.new(0.3, 0.3, 1), rgb(255, 140, 40))
	cylinder(parent, at + Vector3.new(0, 7.6, 0), 0.2, 2.2, rgb(30, 30, 34))
	cylinder(parent, at + Vector3.new(0, 8.3, 0), 1.4, 1.4, rgb(30, 30, 34))
end

PROPS.LavaPool = function(parent, at, theme)
	local d = rng:NextNumber(8, 12)
	local pool = cylinder(parent, at + Vector3.new(0, 0.15, 0), 0.3, d, rgb(255, 110, 30), Enum.Material.Neon)
	pool.CastShadow = false
	light(pool, rgb(255, 120, 40), 18, 2)
	emitter(pool, {
		Texture = FIRE, Rate = 6, Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(2, 4),
		Size = NumberSequence.new(1.2, 0), LightEmission = 1, Color = ColorSequence.new(rgb(255, 160, 60), rgb(255, 60, 20)),
		Shape = Enum.ParticleEmitterShape.Disc, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
	})
	for k = 1, 6 do
		local angle = k * math.pi * 2 / 6
		local size = Vector3.new(rng:NextNumber(2, 3.5), rng:NextNumber(1, 2.5), rng:NextNumber(2, 3.5))
		block(parent, CFrame.new(at + Vector3.new(math.cos(angle) * d / 2, size.Y / 2 - 0.3, math.sin(angle) * d / 2)) * CFrame.Angles(0, angle, 0.2),
			size, pick(theme.Rock), theme.RockMaterial, true)
	end
end

PROPS.DeadTree = function(parent, at, _theme)
	local charcoal = rgb(45, 36, 34)
	local h = rng:NextNumber(6, 9)
	cylinder(parent, at + Vector3.new(0, h / 2, 0), h, 1.2, charcoal, Enum.Material.Wood, true)
	for _ = 1, 3 do
		local y = rng:NextNumber(h * 0.5, h)
		block(parent, CFrame.new(at + Vector3.new(0, y, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), math.rad(rng:NextNumber(35, 60))) * CFrame.new(0, 1.6, 0),
			Vector3.new(0.5, 3.2, 0.5), charcoal, Enum.Material.Wood)
	end
end

PROPS.Vent = function(parent, at, theme)
	local color = pick(theme.Rock)
	for tier = 1, 3 do
		local size = 7 - tier * 1.8
		block(parent, CFrame.new(at + Vector3.new(0, tier * 1.2 - 0.4, 0)) * CFrame.Angles(0, tier * 0.5, 0), Vector3.new(size, 1.4, size), shade(color, -0.1 * tier),
			theme.RockMaterial, true)
	end
	local mouth = glow(parent, Vector3.new(1.4, 0.2, 1.4), CFrame.new(at + Vector3.new(0, 3.4, 0)), rgb(255, 120, 40))
	emitter(mouth, {
		Texture = SMOKE, Rate = 4, Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(3, 5), Size = NumberSequence.new(2, 6),
		Transparency = NumberSequence.new(0.4, 1), Color = ColorSequence.new(rgb(90, 80, 80)), RotSpeed = NumberRange.new(-30, 30),
	})
end

PROPS.Hut = function(parent, at, _theme)
	local wood = rgb(140, 100, 64)
	local straw = rgb(220, 186, 110)
	local yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	local base = CFrame.new(at) * yaw
	for _, x in { -3.5, 3.5 } do
		for _, z in { -3.5, 3.5 } do
			block(parent, base * CFrame.new(x, 3.5, z), Vector3.new(0.7, 7, 0.7), wood, Enum.Material.Wood, true)
		end
	end
	block(parent, base * CFrame.new(0, 0.2, 0), Vector3.new(8, 0.4, 8), wood, Enum.Material.WoodPlanks, true)
	for tier = 1, 3 do
		local size = 11 - tier * 3
		block(parent, base * CFrame.new(0, 6.6 + tier * 1.3, 0) * CFrame.Angles(0, math.rad(45 * tier), 0), Vector3.new(size, 1.5, size), straw, Enum.Material.Fabric)
	end
end

PROPS.Crystal = function(parent, at, theme)
	local colors = { theme.Trim, theme.Keys[2] or theme.Trim, theme.Keys[3] or theme.Trim }
	local first: Part? = nil
	for _ = 1, rng:NextInteger(3, 5) do
		local h = rng:NextNumber(3, 8)
		local cf = CFrame.new(at + Vector3.new(rng:NextNumber(-1.8, 1.8), h / 2 - 0.4, rng:NextNumber(-1.8, 1.8)))
			* CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-25, 25)))
		local crystal = block(parent, cf, Vector3.new(1.3, h, 1.3), pick(colors), Enum.Material.Neon)
		crystal.CastShadow = false
		first = first or crystal
	end
	if first then
		light(first, first.Color, 16, 1.5)
	end
end

PROPS.Mushroom = function(parent, at, theme)
	local h = rng:NextNumber(2, 4.5)
	local d = rng:NextNumber(3, 5.5)
	cylinder(parent, at + Vector3.new(0, h / 2, 0), h, d * 0.25, rgb(235, 230, 240), Enum.Material.SmoothPlastic, true)
	local cap = cylinder(parent, at + Vector3.new(0, h + 0.4, 0), 1, d, pick({ theme.Trim, rgb(60, 230, 255), rgb(255, 110, 220) }), Enum.Material.Neon)
	cap.CastShadow = false
	if rng:NextNumber() < 0.4 then
		light(cap, cap.Color, 12, 1.2)
	end
end

PROPS.Pillar = function(parent, at, _theme)
	local marble = rgb(250, 248, 240)
	local gold = rgb(255, 210, 90)
	local h = if rng:NextNumber() < 0.3 then rng:NextNumber(5, 8) else 14
	block(parent, CFrame.new(at + Vector3.new(0, 0.6, 0)), Vector3.new(4.6, 1.2, 4.6), marble, Enum.Material.Marble, true)
	cylinder(parent, at + Vector3.new(0, 1.2 + h / 2, 0), h, 3, marble, Enum.Material.Marble, true)
	if h >= 14 then
		block(parent, CFrame.new(at + Vector3.new(0, 1.2 + h + 0.5, 0)), Vector3.new(4.6, 1, 4.6), gold, Enum.Material.Foil)
	end
end

PROPS.Cloud = function(parent, at, _theme)
	for _ = 1, rng:NextInteger(3, 5) do
		local puff = ball(parent, at + Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(1, 3), rng:NextNumber(-3, 3)), rng:NextNumber(4, 8), rgb(255, 255, 255))
		puff.CastShadow = false
	end
end

-- Free spots for props: off the trail, the keyboard and the spawn, and out
-- of the shallows.
local function propSpots(center: Vector3, theme: Theme, count: number): { Vector3 }
	local halfW, halfD = MapConfig.ZoneWidth / 2, MapConfig.ZoneDepth / 2
	local board = keyboardSize()
	local spots: { Vector3 } = {}
	local tries = 0
	while #spots < count and tries < count * 30 do
		tries += 1
		local x = rng:NextNumber(-halfW + 12, halfW - 12)
		local z = rng:NextNumber(-halfD + 12, halfD - 12)
		local ok = math.abs(x) > 11 -- the trail
			and not (math.abs(x) < board.X / 2 + 8 and math.abs(z - KEYBOARD_OFFSET.Z) < board.Z / 2 + 8)
			and not (theme.Water ~= nil and x > halfW - 36)
		if ok then
			for _, other in spots do
				if (Vector3.new(x, 0, z) - other).Magnitude < 11 then
					ok = false
					break
				end
			end
		end
		if ok then
			table.insert(spots, Vector3.new(x, 0, z))
		end
	end
	for i, spot in spots do
		spots[i] = center + spot
	end
	return spots
end

local function weightedPick(weights: { [string]: number }): string
	local total = 0
	local names: { string } = {}
	for name, weight in weights do
		total += weight
		table.insert(names, name)
	end
	table.sort(names) -- pairs order isn't stable; the map must be
	local roll = rng:NextNumber() * total
	for _, name in names do
		roll -= weights[name]
		if roll <= 0 then
			return name
		end
	end
	return names[#names]
end

--------------------------------------------------------------------------
-- Biome set pieces
--------------------------------------------------------------------------

local function skyClouds(parent: Instance, center: Vector3, low: boolean)
	for _ = 1, 7 do
		local at = center + Vector3.new(rng:NextNumber(-160, 160), if low then rng:NextNumber(-40, -15) else rng:NextNumber(90, 120), rng:NextNumber(-140, 140))
		for _ = 1, rng:NextInteger(3, 5) do
			local puff = ball(parent, at + Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(-3, 4), rng:NextNumber(-8, 8)), rng:NextNumber(14, 28), rgb(255, 255, 255))
			puff.CastShadow = false
			puff.Transparency = 0.05
		end
	end
end

local function weather(parent: Instance, center: Vector3, theme: Theme)
	local kind = theme.Weather
	if not kind then return end
	local W, D = MapConfig.ZoneWidth, MapConfig.ZoneDepth
	local high = kind == "Snow" or kind == "Sparkle"
	local area = deco(parent, {
		Name = "Weather",
		Size = Vector3.new(W, 1, D),
		CFrame = CFrame.new(center + Vector3.new(0, if high then 40 else 1, 0)),
		Transparency = 1,
		CastShadow = false,
	})
	if kind == "Snow" then
		emitter(area, {
			Texture = SPARKLE, Rate = 60, Lifetime = NumberRange.new(8, 10), Speed = NumberRange.new(4, 6), EmissionDirection = Enum.NormalId.Bottom,
			Size = NumberSequence.new(0.5), Color = ColorSequence.new(rgb(255, 255, 255)), SpreadAngle = Vector2.new(15, 15), RotSpeed = NumberRange.new(-40, 40),
		})
	elseif kind == "Embers" then
		emitter(area, {
			Texture = FIRE, Rate = 30, Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(3, 7), EmissionDirection = Enum.NormalId.Top,
			Size = NumberSequence.new(0.35, 0), LightEmission = 1, Color = ColorSequence.new(rgb(255, 170, 60), rgb(255, 60, 20)), SpreadAngle = Vector2.new(25, 25),
		})
	elseif kind == "Sparkle" then
		emitter(area, {
			Texture = SPARKLE, Rate = 25, Lifetime = NumberRange.new(4, 7), Speed = NumberRange.new(1, 2), EmissionDirection = Enum.NormalId.Bottom,
			Size = NumberSequence.new(0.5, 0), LightEmission = 1, Color = ColorSequence.new(theme.Trim), SpreadAngle = Vector2.new(180, 180),
		})
	elseif kind == "Fireflies" then
		emitter(area, {
			Texture = SPARKLE, Rate = 10, Lifetime = NumberRange.new(5, 8), Speed = NumberRange.new(0.5, 1.5), EmissionDirection = Enum.NormalId.Top,
			Size = NumberSequence.new(0.4, 0), LightEmission = 1, Color = ColorSequence.new(rgb(230, 255, 140)), SpreadAngle = Vector2.new(60, 60),
		})
	end
end

local function volcanoPeak(parent: Instance, center: Vector3, theme: Theme)
	-- The big volcano looming over the +X cliffs.
	local base = center + Vector3.new(MapConfig.ZoneWidth / 2 + 140, -10, 30)
	local color = theme.Rock[2] or theme.Rock[1]
	local tiers = 7
	for tier = 1, tiers do
		local d = 190 - tier * 22
		cylinder(parent, base + Vector3.new(0, tier * 18, 0), 20, d, shade(color, -0.04 * tier), theme.RockMaterial)
	end
	local crater = cylinder(parent, base + Vector3.new(0, tiers * 18 + 10.5, 0), 1, 190 - tiers * 22 - 10, rgb(255, 100, 20), Enum.Material.Neon)
	crater.CastShadow = false
	light(crater, rgb(255, 110, 30), 60, 3)
	emitter(crater, {
		Texture = SMOKE, Rate = 8, Lifetime = NumberRange.new(8, 12), Speed = NumberRange.new(10, 16), Size = NumberSequence.new(14, 40),
		Transparency = NumberSequence.new(0.3, 1), Color = ColorSequence.new(rgb(70, 60, 60)), RotSpeed = NumberRange.new(-20, 20),
	})
	-- Lava running down its face.
	for k = 1, 3 do
		local angle = math.rad(150 + k * 25)
		local top = base + Vector3.new(math.cos(angle) * 40, tiers * 18 + 8, math.sin(angle) * 40)
		local bottom = base + Vector3.new(math.cos(angle) * 92, 22, math.sin(angle) * 92)
		local mid = (top + bottom) / 2
		glow(parent, Vector3.new(5, 1, (top - bottom).Magnitude), CFrame.lookAt(mid, top), rgb(255, 120, 30))
	end
end

local function lavaRivers(parent: Instance, center: Vector3)
	local halfD = MapConfig.ZoneDepth / 2
	for _, side in { -1, 1 } do
		local x = side * (MapConfig.ZoneWidth / 2 - 20)
		local lastX = x
		local segments = 7
		local length = (MapConfig.ZoneDepth - 30) / segments
		for i = 1, segments do
			local z = -halfD + 15 + (i - 0.5) * length
			local nx = x + rng:NextNumber(-6, 6)
			local strip = glow(parent, Vector3.new(4, 0.25, length + 2), CFrame.new(center + Vector3.new((nx + lastX) / 2, 0.12, z)) * CFrame.Angles(0, (nx - lastX) / length, 0),
				rgb(255, 110, 30))
			if i % 3 == 0 then
				light(strip, rgb(255, 120, 40), 16, 1.5)
			end
			lastX = nx
		end
	end
end

local function islets(parent: Instance, center: Vector3, theme: Theme)
	for k = 1, 5 do
		local at = center + Vector3.new(MapConfig.ZoneWidth / 2 + 30 + k * 26, 0, (k - 3) * 38 + rng:NextNumber(-10, 10))
		local d = rng:NextNumber(16, 26)
		cylinder(parent, at + Vector3.new(0, -0.5, 0), 2, d, rgb(240, 220, 160), Enum.Material.Sand)
		cylinder(parent, at + Vector3.new(0, 0.6, 0), 0.6, d * 0.65, theme.Floor, Enum.Material.Grass)
		PROPS.Palm(parent, at + Vector3.new(0, 0.9, 0), theme)
	end
end

local function dock(parent: Instance, center: Vector3)
	local x0 = MapConfig.ZoneWidth / 2 - 34
	local wood = rgb(150, 110, 72)
	local z = 34
	for i = 0, 7 do
		block(parent, CFrame.new(center + Vector3.new(x0 + i * 4, 0.7, z)), Vector3.new(3.6, 0.4, 7), shade(wood, (i % 2) * 0.06), Enum.Material.WoodPlanks, true)
	end
	for i = 0, 3 do
		for _, side in { -1, 1 } do
			cylinder(parent, center + Vector3.new(x0 + i * 10, 1, z + side * 3.6), 3, 0.8, shade(wood, -0.2), Enum.Material.Wood)
		end
	end
end

local function aurora(parent: Instance, center: Vector3)
	local colors = { rgb(90, 255, 170), rgb(120, 200, 255), rgb(180, 120, 255) }
	for k = 1, 5 do
		local ribbon = glow(parent, Vector3.new(90, 16, 0.5),
			CFrame.new(center + Vector3.new(-40 + k * 18, 110 + k * 4, 60 - k * 22)) * CFrame.Angles(math.rad(-20), math.rad(k * 9), 0), colors[(k - 1) % #colors + 1])
		ribbon.Transparency = 0.65
	end
end

local function caveRoof(parent: Instance, center: Vector3, theme: Theme)
	local W, D = MapConfig.ZoneWidth, MapConfig.ZoneDepth
	local y = theme.CliffHeight - 2
	block(parent, CFrame.new(center + Vector3.new(0, y + 4, 0)), Vector3.new(W + 70, 8, D + 70), shade(theme.Rock[1], -0.25), theme.RockMaterial, true)
	for _ = 1, 30 do
		local h = rng:NextNumber(8, 20)
		local w = rng:NextNumber(3, 6)
		local at = center + Vector3.new(rng:NextNumber(-W / 2 + 6, W / 2 - 6), y - h / 2 + 2, rng:NextNumber(-D / 2 + 6, D / 2 - 6))
		block(parent, CFrame.new(at) * CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), math.rad(45), math.rad(rng:NextNumber(-8, 8))),
			Vector3.new(w, h, w), pick(theme.Rock), theme.RockMaterial)
	end
	-- Crystals growing out of the walls.
	for _ = 1, 8 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local at = center + Vector3.new(side * (W / 2 - 2), rng:NextNumber(6, 30), rng:NextNumber(-D / 2 + 10, D / 2 - 10))
		local crystal = block(parent, CFrame.new(at) * CFrame.Angles(0, 0, math.rad(side * rng:NextNumber(40, 70))), Vector3.new(2, rng:NextNumber(5, 10), 2),
			pick({ theme.Trim, rgb(60, 230, 255) }), Enum.Material.Neon)
		crystal.CastShadow = false
	end
end

local function halo(parent: Instance, center: Vector3)
	local at = center + KEYBOARD_OFFSET + Vector3.new(0, 34, 0)
	local radius = 22
	for k = 1, 24 do
		local angle = k * math.pi * 2 / 24
		glow(parent, Vector3.new(2, 1.2, radius * math.pi * 2 / 24 + 0.4), CFrame.new(at + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
			* CFrame.Angles(0, -angle, 0), rgb(255, 230, 130))
	end
end

local function titleBoard(parent: Instance, center: Vector3)
	-- Big wooden sign on the cliff behind the spawn.
	local at = center + Vector3.new(0, 24, -MapConfig.ZoneDepth / 2 + 8)
	local board = part(parent, {
		Name = "TitleBoard",
		Size = Vector3.new(46, 14, 1.4),
		CFrame = CFrame.lookAt(at, at + Vector3.new(0, 0, 1)),
		Color = rgb(150, 105, 64),
		Material = Enum.Material.WoodPlanks,
	})
	sign(board, Enum.NormalId.Front, "STUDS RNG", rgb(255, 220, 90))
	for _, x in { -18, 18 } do
		block(parent, CFrame.new(at + Vector3.new(x, -12, -0.6)), Vector3.new(1.6, 16, 1.6), rgb(120, 84, 52), Enum.Material.Wood)
	end
end

local function setPieces(parent: Instance, def: Zones.ZoneDef, center: Vector3, theme: Theme)
	local outdoor = not theme.Roof
	if outdoor then
		skyClouds(parent, center, theme.CliffStyle == "Cloud")
	end
	weather(parent, center, theme)
	if def.Order == 1 then
		titleBoard(parent, center)
	end
	if def.Id == "Neon" then
		volcanoPeak(parent, center, theme)
		lavaRivers(parent, center)
	elseif def.Id == "Arcade" then
		dock(parent, center)
	elseif def.Id == "Islands" then
		islets(parent, center, theme)
	elseif def.Id == "Studio" then
		aurora(parent, center)
	elseif def.Id == "Cave" then
		caveRoof(parent, center, theme)
	elseif def.Id == "Space" then
		halo(parent, center)
	end
end

--------------------------------------------------------------------------
-- Zone
--------------------------------------------------------------------------

local function zoneCenter(index: number): Vector3
	return MapConfig.Origin + Vector3.new(0, 0, (index - 1) * (MapConfig.ZoneDepth + MapConfig.Bridge))
end

-- Entrance arch + force field at the start of the zone (every zone but the first).
local function buildGate(zone: Model, def: Zones.ZoneDef, center: Vector3, theme: Theme)
	local gateZ = center.Z - MapConfig.ZoneDepth / 2 - 1
	local heavenly = theme.CliffStyle == "Cloud"
	local pillarColor = if heavenly then rgb(255, 214, 100) else pick(theme.Rock)
	local pillarMaterial = if heavenly then Enum.Material.Foil else theme.RockMaterial
	local gate = Instance.new("Folder")
	gate.Name = "Gate"
	gate:SetAttribute(Tags.Attr.ZoneId, def.Id)
	CollectionService:AddTag(gate, Tags.ZoneGate)
	gate.Parent = zone
	for _, side in { -1, 1 } do
		local x = center.X + side * (PASS_WIDTH / 2 + 3)
		block(gate, CFrame.new(x, center.Y + 14, gateZ), Vector3.new(6, 28, 6), pillarColor, pillarMaterial, true)
		block(gate, CFrame.new(x, center.Y + 1, gateZ), Vector3.new(8, 2, 8), shade(pillarColor, -0.15), pillarMaterial, true)
	end
	local beam = part(gate, {
		Name = "GateSign",
		Size = Vector3.new(PASS_WIDTH + 14, 6, 3),
		CFrame = CFrame.new(center.X, center.Y + 30, gateZ),
		Color = if heavenly then rgb(255, 214, 100) else rgb(120, 84, 52),
		Material = if heavenly then Enum.Material.Foil else Enum.Material.WoodPlanks,
	})
	local text = `{def.Order}  {string.upper(def.Name)}`
	sign(beam, Enum.NormalId.Front, text, def.Color)
	sign(beam, Enum.NormalId.Back, text, def.Color)

	local barrier = part(zone, {
		Name = "Barrier",
		Size = Vector3.new(PASS_WIDTH, 26, 1),
		CFrame = CFrame.new(center.X, center.Y + 13, gateZ),
		Color = def.Color,
		Material = Enum.Material.ForceField,
		Transparency = 0.15,
		CastShadow = false,
	})
	barrier.CanQuery = false
	barrier:SetAttribute(Tags.Attr.ZoneId, def.Id)
	CollectionService:AddTag(barrier, Tags.ZoneBarrier)
end

local function buildSpawn(zone: Model, center: Vector3, theme: Theme, first: boolean)
	local position = center + Vector3.new(0, 0.5, -MapConfig.ZoneDepth / 2 + 14)
	local cframe = CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
	if first then
		local spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Name = "Spawn"
		spawnLocation.Size = Vector3.new(10, 1, 10)
		spawnLocation.CFrame = cframe
		spawnLocation.Anchored = true
		spawnLocation.Neutral = true
		spawnLocation.Duration = 0
		spawnLocation.Color = theme.Trim
		spawnLocation.Material = Enum.Material.Neon
		spawnLocation.Transparency = 0.6
		spawnLocation.CanCollide = false
		local decal = spawnLocation:FindFirstChildOfClass("Decal")
		if decal then decal:Destroy() end
		spawnLocation.Parent = zone
		CollectionService:AddTag(spawnLocation, Tags.ZoneSpawn)
	else
		local pad = deco(zone, { Name = "Spawn", Size = Vector3.new(10, 1, 10), CFrame = cframe, Color = theme.Trim, Material = Enum.Material.Neon, Transparency = 0.6 })
		CollectionService:AddTag(pad, Tags.ZoneSpawn)
	end
	-- A stone ring around the pad.
	for k = 1, 10 do
		local angle = k * math.pi * 2 / 10
		block(zone, CFrame.new(position + Vector3.new(math.cos(angle) * 7.5, -0.2, math.sin(angle) * 7.5)) * CFrame.Angles(0, -angle, 0), Vector3.new(2.2, 0.6, 4.4),
			shade(theme.Path, -0.1), theme.PathMaterial)
	end
end

local function buildZone(zonesFolder: Instance, def: Zones.ZoneDef, index: number): Model
	local theme = MapThemes[def.Id]
	local center = zoneCenter(index)
	local hasEntrance = index > 1
	local hasExit = index < #Zones.List
	lightsLeft = MAX_LIGHTS

	local zone = Instance.new("Model")
	zone.Name = def.Id
	zone:SetAttribute(Tags.Attr.ZoneId, def.Id)
	zone:SetAttribute(Tags.Attr.Center, center)
	zone:SetAttribute(Tags.Attr.ZoneSize, Vector3.new(MapConfig.ZoneWidth, 90, MapConfig.ZoneDepth))
	CollectionService:AddTag(zone, Tags.Zone)

	zone.PrimaryPart = buildGround(zone, center, theme)
	buildCliffs(zone, center, theme, hasEntrance, hasExit)
	buildWalls(zone, center, hasEntrance, hasExit)
	buildKeyboard(zone, center + KEYBOARD_OFFSET, def, theme)
	buildSpawn(zone, center, theme, index == 1)
	if hasEntrance then
		buildGate(zone, def, center, theme)
	end

	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = zone
	for _, spot in propSpots(center, theme, theme.PropCount) do
		local build = PROPS[weightedPick(theme.Props)]
		if build then
			build(props, spot, theme)
		end
	end
	setPieces(props, def, center, theme)

	zone.Parent = zonesFolder
	return zone
end

-- The canyon between zone `from` and the next: a trail floor walled by both
-- zones' rock.
local function buildPass(parent: Instance, from: number)
	local a = zoneCenter(from)
	local b = zoneCenter(from + 1)
	local startZ = a.Z + MapConfig.ZoneDepth / 2
	local endZ = b.Z - MapConfig.ZoneDepth / 2
	local length = endZ - startZ
	local mid = Vector3.new(a.X, a.Y, (startZ + endZ) / 2)
	local fromTheme = MapThemes[Zones.List[from].Id]
	local toTheme = MapThemes[Zones.List[from + 1].Id]

	local pass = Instance.new("Folder")
	pass.Name = `Pass{from}`
	pass.Parent = parent

	part(pass, { Name = "Floor", Size = Vector3.new(PASS_WIDTH + 60, 4, length + 4), CFrame = CFrame.new(mid - Vector3.new(0, 2, 0)), Color = fromTheme.Floor,
		Material = fromTheme.FloorMaterial })
	block(pass, CFrame.new(mid + Vector3.new(0, 0.15, 0)), Vector3.new(12, 0.3, length + 4), fromTheme.Path:Lerp(toTheme.Path, 0.5), fromTheme.PathMaterial)

	local steps = math.max(1, math.floor(length / 12))
	for i = 0, steps do
		local t = i / steps
		local theme = if t < 0.5 then fromTheme else toTheme
		local z = startZ + length * t
		for _, side in { -1, 1 } do
			local base = Vector3.new(mid.X + side * PASS_WIDTH / 2, mid.Y, z)
			cliffChunk(pass, base, Vector3.new(side, 0, 0), theme, 1.1, 0)
		end
	end
	for _, side in { -1, 1 } do
		local wall = part(pass, { Name = "Wall", Size = Vector3.new(1, WALL_HEIGHT, length + 2), CFrame = CFrame.new(mid + Vector3.new(side * (PASS_WIDTH / 2 + 0.5), WALL_HEIGHT / 2, 0)),
			Transparency = 1, CastShadow = false })
		wall.CanQuery = false
	end
end

--------------------------------------------------------------------------
-- Falling off
--------------------------------------------------------------------------

local function nearestOwnedSpawn(player: Player, position: Vector3): BasePart?
	local data = PlayerData.get(player)
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, def in Zones.List do
		local owned = def.Id == Zones.Default or (data ~= nil and data.UnlockedWorlds[def.Id] == true)
		local spawnPart = if owned then Tags.spawnOf(def.Id) else nil
		if spawnPart then
			local distance = math.abs(spawnPart.Position.Z - position.Z)
			if distance < bestDistance then
				bestDistance = distance
				best = spawnPart
			end
		end
	end
	return best
end

--------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------

function MapBuilder.init()
	if not MapConfig.Enabled then return end
	local zonesFolder = workspace:FindFirstChild(Config.ZoneFolder)
	if not zonesFolder then
		zonesFolder = Instance.new("Folder")
		zonesFolder.Name = Config.ZoneFolder
		zonesFolder.Parent = workspace
	end
	local mapFolder = Instance.new("Folder")
	mapFolder.Name = "StudsMap"
	mapFolder.Parent = workspace

	-- Hand-built zones named the old way: tag them so the game can find them.
	for _, zone in (zonesFolder :: Instance):GetChildren() do
		if Zones.ById[zone.Name] and not CollectionService:HasTag(zone, Tags.Zone) then
			CollectionService:AddTag(zone, Tags.Zone)
			local spawnPart = zone:FindFirstChild("Spawn")
			if spawnPart and spawnPart:IsA("BasePart") then
				CollectionService:AddTag(spawnPart, Tags.ZoneSpawn)
			end
			local barrier = zone:FindFirstChild("Barrier")
			if barrier then
				CollectionService:AddTag(barrier, Tags.ZoneBarrier)
			end
		end
	end

	local started = os.clock()
	for index, def in Zones.List do
		local exists = (zonesFolder :: Instance):FindFirstChild(def.Id) ~= nil or #Tags.forZone(Tags.Zone, def.Id) > 0
		if not exists then
			local zone = buildZone(zonesFolder :: Instance, def, index)
			table.insert(built, { def = def, center = zoneCenter(index), model = zone })
		end
		if index < #Zones.List then
			buildPass(mapFolder, index)
		end
	end

	if MapConfig.TakeOverSpawns then
		for _, descendant in workspace:GetDescendants() do
			if descendant:IsA("SpawnLocation") and not descendant:IsDescendantOf(zonesFolder :: Instance) then
				descendant.Enabled = false
			end
		end
	end
	print(`[MapBuilder] built {#built} zone(s) in {math.floor((os.clock() - started) * 1000)}ms`)
end

function MapBuilder.start()
	if not MapConfig.Enabled then return end
	local floorY = MapConfig.Origin.Y - FALL_DEPTH
	while true do
		task.wait(0.5)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if character and root and root:IsA("BasePart") and root.Position.Y < floorY then
				local spawnPart = nearestOwnedSpawn(player, root.Position)
				if spawnPart then
					root.AssemblyLinearVelocity = Vector3.zero
					character:PivotTo(spawnPart.CFrame + Vector3.new(0, 4, 0))
				end
			end
		end
	end
end

return MapBuilder
