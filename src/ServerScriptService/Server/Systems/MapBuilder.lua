--[[

MapBuilder
ModuleScript
/ServerScriptService/Server/Systems/MapBuilder

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Builds the playable map at server start (Config.Map): one floating island
-- per zone (Shared/Zones order) along +Z, joined by bridges.
--
-- workspace.Zones.<ZoneId> (Model, attributes Center/ZoneSize) contains
--   Floor, Trim, Walls      the island
--   Keyboard                KeyCapper keys: Model{Hitbox (tagged), Cap}
--                           with World / Value / Group attributes, so the
--                           KeyCapper runtime animates them and PressTracker
--                           pays them exactly like hand-placed keys
--   Spawn                   teleport target (a SpawnLocation in the first zone)
--   Barrier                 entrance force field (opens locally when owned)
--   Props                   themed decoration (Shared/MapThemes)
--
-- A zone that already exists under workspace.Zones is skipped, so any zone
-- can be replaced by a hand-built one. Players who fall off an island are
-- put back at the nearest zone they own.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Zones = require(Shared.Zones)
local MapThemes = require(Shared.MapThemes)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)

local MapBuilder = {}

local MapConfig = Config.Map
local KEY_SIZE = Vector3.new(3, 1.368114709854126, 3)
local KEY_PITCH = 3.15
local HITBOX_XZ = 0.8123 -- KeyCapper's hitbox footprint ratio
local MESH_YAW = CFrame.Angles(0, math.rad(-90), 0)
local BRIDGE_WIDTH = 20
local WALL_HEIGHT = 40
local FALL_DEPTH = 70

local rng = Random.new(1337) -- fixed seed: the same map every server

type ZoneBuild = { def: Zones.ZoneDef, center: Vector3, model: Model }
local built: { ZoneBuild } = {}

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

-- Decoration: doesn't collide, can't be touched or queried (cheap).
local function deco(parent: Instance, props: PartProps): Part
	props.CanCollide = if props.CanCollide == nil then false else props.CanCollide
	local p = part(parent, props)
	p.CanTouch = false
	p.CanQuery = false
	return p
end

local function neon(parent: Instance, size: Vector3, cframe: CFrame, color: Color3): Part
	return deco(parent, { Name = "Neon", Size = size, CFrame = cframe, Color = color, Material = Enum.Material.Neon, CastShadow = false })
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
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
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
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
	-- No mesh: a plain rounded-looking block keeps the map playable.
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

local function buildKeyboard(zone: Model, center: Vector3, def: Zones.ZoneDef)
	local theme = MapThemes[def.Id]
	local folder = Instance.new("Folder")
	folder.Name = "Keyboard"
	folder.Parent = zone

	local cols, rows = MapConfig.KeyCols, MapConfig.KeyRows
	local width = cols * KEY_PITCH
	local depth = rows * KEY_PITCH

	-- The plate the keys sit in.
	local plate = part(zone, {
		Name = "KeyboardPlate",
		Size = Vector3.new(width + 3, 0.6, depth + 3),
		CFrame = CFrame.new(center + Vector3.new(0, 0.3, 0)),
		Color = theme.Floor:Lerp(Color3.new(0, 0, 0), 0.55),
		Material = Enum.Material.SmoothPlastic,
	})
	for _, side in { -1, 1 } do
		neon(zone, Vector3.new(width + 3.4, 0.3, 0.4), CFrame.new(center + Vector3.new(0, 0.5, side * (depth + 3) / 2)), theme.Trim)
		neon(zone, Vector3.new(0.4, 0.3, depth + 3.4), CFrame.new(center + Vector3.new(side * (width + 3) / 2, 0.5, 0)), theme.Trim)
	end

	local material = if def.Id == "Neon" or def.Id == "Arcade" then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local top = plate.Position.Y + plate.Size.Y / 2
	for row = 1, rows do
		local color = theme.Keys[(row - 1) % #theme.Keys + 1]
		for col = 1, cols do
			local x = (col - (cols + 1) / 2) * KEY_PITCH
			local z = (row - (rows + 1) / 2) * KEY_PITCH
			local position = Vector3.new(center.X + x, top + KEY_SIZE.Y / 2, center.Z + z)
			-- Neon zones: every few keys stay solid so the board isn't a light wall.
			local keyMaterial = if material == Enum.Material.Neon and (row + col) % 3 ~= 0 then Enum.Material.SmoothPlastic else material
			placeKey(folder, CFrame.new(position), color, keyMaterial, def.Id)
		end
	end
end

--------------------------------------------------------------------------
-- Props
--------------------------------------------------------------------------

-- Spots around the keyboard: left/right margins, front/back strips.
local function sideSpots(center: Vector3, count: number): { Vector3 }
	local spots: { Vector3 } = {}
	local halfW = MapConfig.ZoneWidth / 2
	local keyHalf = MapConfig.KeyCols * KEY_PITCH / 2
	local margin = (halfW - keyHalf) / 2 + keyHalf
	for i = 1, count do
		local t = (i - 0.5) / count
		local z = (t - 0.5) * (MapConfig.ZoneDepth - 20)
		table.insert(spots, center + Vector3.new(-margin, 0, z))
		table.insert(spots, center + Vector3.new(margin, 0, z))
	end
	return spots
end

local function facing(position: Vector3, center: Vector3): CFrame
	local look = Vector3.new(center.X, position.Y, position.Z)
	return CFrame.lookAt(position, look)
end

local PROPS: { [string]: (Instance, Vector3, Vector3) -> () } = {}

PROPS.Office = function(parent, spot, center)
	local cf = facing(spot, center)
	local wood = Color3.fromRGB(150, 110, 75)
	deco(parent, { Size = Vector3.new(8, 0.5, 4), CFrame = cf * CFrame.new(0, 3, 0), Color = wood, Material = Enum.Material.Wood, CanCollide = true })
	for _, x in { -3.6, 3.6 } do
		for _, z in { -1.6, 1.6 } do
			deco(parent, { Size = Vector3.new(0.4, 3, 0.4), CFrame = cf * CFrame.new(x, 1.5, z), Color = wood:Lerp(Color3.new(0, 0, 0), 0.3) })
		end
	end
	-- Monitor
	deco(parent, { Size = Vector3.new(0.4, 1.2, 0.4), CFrame = cf * CFrame.new(0, 3.85, 1), Color = Color3.fromRGB(30, 30, 34) })
	deco(parent, { Size = Vector3.new(4.4, 2.8, 0.3), CFrame = cf * CFrame.new(0, 5.6, 1), Color = Color3.fromRGB(25, 25, 30) })
	local screen = neon(parent, Vector3.new(4, 2.4, 0.05), cf * CFrame.new(0, 5.6, 0.83), Color3.fromRGB(120, 180, 255))
	light(screen, Color3.fromRGB(120, 180, 255), 8, 0.6)
	-- Chair
	deco(parent, { Size = Vector3.new(2.4, 0.4, 2.4), CFrame = cf * CFrame.new(0, 2, -3), Color = Color3.fromRGB(40, 40, 48), CanCollide = true })
	deco(parent, { Size = Vector3.new(2.4, 2.6, 0.4), CFrame = cf * CFrame.new(0, 3.4, -4.1), Color = Color3.fromRGB(40, 40, 48) })
	deco(parent, { Size = Vector3.new(0.4, 1.8, 0.4), CFrame = cf * CFrame.new(0, 0.9, -3), Color = Color3.fromRGB(80, 80, 90) })
	-- Plant
	local plant = spot + (cf.RightVector * 6)
	deco(parent, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2, 2.2, 2.2), CFrame = CFrame.new(plant + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(200, 120, 80), CanCollide = true })
	for i = 1, 4 do
		local offset = Vector3.new(rng:NextNumber(-0.8, 0.8), 2.6 + i * 0.6, rng:NextNumber(-0.8, 0.8))
		deco(parent, { Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(1.6, 2.4), CFrame = CFrame.new(plant + offset), Color = Color3.fromRGB(70, 150 + i * 10, 70), Material = Enum.Material.Grass })
	end
end

PROPS.Arcade = function(parent, spot, center)
	local cf = facing(spot, center)
	local palette = { Color3.fromRGB(255, 70, 200), Color3.fromRGB(120, 80, 255), Color3.fromRGB(60, 220, 255), Color3.fromRGB(255, 220, 60) }
	for i, x in { -4, 0, 4 } do
		local body = palette[(i + math.floor(spot.Z)) % #palette + 1]
		local base = cf * CFrame.new(x, 0, 0)
		deco(parent, { Size = Vector3.new(3.4, 7, 3), CFrame = base * CFrame.new(0, 3.5, 0), Color = Color3.fromRGB(25, 20, 35), CanCollide = true })
		neon(parent, Vector3.new(3.5, 0.3, 3.1), base * CFrame.new(0, 7.1, 0), body)
		local screen = neon(parent, Vector3.new(2.6, 2, 0.1), base * CFrame.new(0, 5, -1.5) * CFrame.Angles(math.rad(-12), 0, 0), body:Lerp(Color3.new(1, 1, 1), 0.3))
		light(screen, body, 10, 1)
		deco(parent, { Size = Vector3.new(3, 0.4, 1.2), CFrame = base * CFrame.new(0, 3.4, -1.7), Color = Color3.fromRGB(40, 35, 55) })
		deco(parent, { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.6, CFrame = base * CFrame.new(-0.6, 3.8, -1.8), Color = Color3.fromRGB(255, 60, 60), Material = Enum.Material.Neon })
	end
end

PROPS.Studio = function(parent, spot, center)
	local cf = facing(spot, center)
	-- Speaker stack
	for i = 0, 1 do
		local box = cf * CFrame.new(-3, 2.5 + i * 5, 0)
		deco(parent, { Size = Vector3.new(4, 5, 3), CFrame = box, Color = Color3.fromRGB(28, 28, 32), CanCollide = i == 0 })
		for _, y in { -1.1, 1.1 } do
			deco(parent, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2, 2), CFrame = box * CFrame.new(0, y, -1.55) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(70, 70, 76) })
		end
	end
	-- Mic stand
	deco(parent, { Size = Vector3.new(0.3, 5, 0.3), CFrame = cf * CFrame.new(3, 2.5, 0), Color = Color3.fromRGB(150, 150, 155), Material = Enum.Material.Metal })
	deco(parent, { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, CFrame = cf * CFrame.new(3, 5.3, -0.3), Color = Color3.fromRGB(40, 40, 44), Material = Enum.Material.Metal })
	-- Spotlight on a truss
	deco(parent, { Size = Vector3.new(0.6, 14, 0.6), CFrame = cf * CFrame.new(6, 7, 2), Color = Color3.fromRGB(120, 120, 128), Material = Enum.Material.Metal })
	local lamp = deco(parent, { Size = Vector3.new(1.4, 1.4, 2), CFrame = CFrame.lookAt((cf * CFrame.new(6, 14, 2)).Position, center), Color = Color3.fromRGB(30, 30, 34) })
	local beam = Instance.new("SpotLight")
	beam.Color = Color3.fromRGB(255, 200, 120)
	beam.Range = 50
	beam.Angle = 35
	beam.Brightness = 4
	beam.Face = Enum.NormalId.Front
	beam.Parent = lamp
end

PROPS.Neon = function(parent, spot, center)
	local cf = facing(spot, center)
	local color = ({ Color3.fromRGB(0, 230, 255), Color3.fromRGB(255, 40, 140), Color3.fromRGB(255, 240, 0) })[rng:NextInteger(1, 3)]
	-- Street lamp
	deco(parent, { Size = Vector3.new(0.5, 10, 0.5), CFrame = cf * CFrame.new(0, 5, 0), Color = Color3.fromRGB(40, 42, 50), Material = Enum.Material.Metal })
	deco(parent, { Size = Vector3.new(0.5, 0.5, 3), CFrame = cf * CFrame.new(0, 10, -1.3), Color = Color3.fromRGB(40, 42, 50), Material = Enum.Material.Metal })
	local bulb = neon(parent, Vector3.new(1.2, 0.5, 1.2), cf * CFrame.new(0, 9.7, -2.6), color)
	light(bulb, color, 18, 2)
	-- Bench
	deco(parent, { Size = Vector3.new(5, 0.4, 1.6), CFrame = cf * CFrame.new(4, 1.6, 0), Color = Color3.fromRGB(50, 52, 60), CanCollide = true })
	neon(parent, Vector3.new(5, 0.15, 0.15), cf * CFrame.new(4, 1.35, -0.8), color)
end

PROPS.Space = function(parent, spot, center)
	local cf = facing(spot, center)
	-- Crystal cluster
	for i = 1, 4 do
		local h = rng:NextNumber(3, 7)
		local tilt = CFrame.Angles(math.rad(rng:NextNumber(-20, 20)), rng:NextNumber(0, 6.28), math.rad(rng:NextNumber(-20, 20)))
		local crystal = deco(parent, {
			Size = Vector3.new(1.2, h, 1.2),
			CFrame = cf * CFrame.new(rng:NextNumber(-2, 2), h / 2, rng:NextNumber(-2, 2)) * tilt,
			Color = ({ Color3.fromRGB(176, 104, 255), Color3.fromRGB(90, 220, 255) })[i % 2 + 1],
			Material = Enum.Material.Neon,
			CastShadow = false,
		})
		if i == 1 then
			light(crystal, crystal.Color, 14, 1.5)
		end
	end
end

-- Big set pieces outside the island edges.
local function backdrop(parent: Instance, def: Zones.ZoneDef, center: Vector3)
	local theme = MapThemes[def.Id]
	local halfW = MapConfig.ZoneWidth / 2
	if def.Id == "Neon" then
		for _, side in { -1, 1 } do
			for i = 1, 6 do
				local h = rng:NextNumber(40, 110)
				local w = rng:NextNumber(12, 20)
				local z = center.Z + (i - 3.5) * 15
				local x = center.X + side * (halfW + 14 + rng:NextNumber(0, 10))
				local base = Vector3.new(x, center.Y - 30 + h / 2, z)
				deco(parent, { Size = Vector3.new(w, h, w), CFrame = CFrame.new(base), Color = Color3.fromRGB(22, 24, 34), Material = Enum.Material.Concrete })
				local color = theme.Keys[rng:NextInteger(1, #theme.Keys)]
				for y = 8, h - 4, 9 do
					neon(parent, Vector3.new(w + 0.2, 0.6, w + 0.2), CFrame.new(base.X, center.Y - 30 + y, base.Z), color)
				end
			end
		end
	elseif def.Id == "Space" then
		local planets = {
			{ Offset = Vector3.new(-120, 70, 40), Size = 70, Color = Color3.fromRGB(110, 60, 200), Ring = true },
			{ Offset = Vector3.new(140, 40, -30), Size = 40, Color = Color3.fromRGB(255, 140, 70), Ring = false },
			{ Offset = Vector3.new(30, 120, 160), Size = 30, Color = Color3.fromRGB(90, 220, 255), Ring = true },
		}
		for _, planet in planets do
			local position = center + planet.Offset
			deco(parent, { Shape = Enum.PartType.Ball, Size = Vector3.one * planet.Size, CFrame = CFrame.new(position), Color = planet.Color, Material = Enum.Material.SmoothPlastic })
			if planet.Ring then
				deco(parent, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, planet.Size * 1.9, planet.Size * 1.9), CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(80)) * CFrame.Angles(math.rad(15), 0, 0), Color = planet.Color:Lerp(Color3.new(1, 1, 1), 0.5), Material = Enum.Material.Neon, Transparency = 0.4 })
			end
		end
		for _ = 1, 24 do
			local offset = Vector3.new(rng:NextNumber(-140, 140), rng:NextNumber(-40, 60), rng:NextNumber(-90, 90))
			if math.abs(offset.X) > halfW + 10 or offset.Y < -10 then
				deco(parent, { Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(3, 10), CFrame = CFrame.new(center + offset), Color = Color3.fromRGB(70, 66, 80), Material = Enum.Material.Slate })
			end
		end
		-- Drifting star dust above the island
		local emitterPart = deco(parent, { Size = Vector3.new(MapConfig.ZoneWidth, 1, MapConfig.ZoneDepth), CFrame = CFrame.new(center + Vector3.new(0, 40, 0)), Transparency = 1 })
		local stars = Instance.new("ParticleEmitter")
		stars.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		stars.Rate = 25
		stars.Lifetime = NumberRange.new(4, 7)
		stars.Speed = NumberRange.new(1, 3)
		stars.SpreadAngle = Vector2.new(180, 180)
		stars.Size = NumberSequence.new(0.4, 0)
		stars.LightEmission = 1
		stars.Color = ColorSequence.new(Color3.fromRGB(220, 200, 255))
		stars.Parent = emitterPart
	elseif def.Id == "Arcade" then
		-- Giant neon arch over the keyboard
		for _, side in { -1, 1 } do
			neon(parent, Vector3.new(2, 30, 2), CFrame.new(center + Vector3.new(side * (halfW - 4), 15, 0)), theme.Trim)
		end
		neon(parent, Vector3.new(MapConfig.ZoneWidth - 6, 2, 2), CFrame.new(center + Vector3.new(0, 30, 0)), Color3.fromRGB(60, 220, 255))
	elseif def.Id == "Office" then
		-- Title board behind the spawn
		local board = part(parent, {
			Name = "TitleBoard",
			Size = Vector3.new(44, 14, 1),
			CFrame = CFrame.new(center + Vector3.new(0, 16, -MapConfig.ZoneDepth / 2 - 3)),
			Color = Color3.fromRGB(30, 34, 50),
		})
		sign(board, Enum.NormalId.Back, "STUDS RNG", Color3.fromRGB(255, 220, 90))
		sign(board, Enum.NormalId.Front, "STUDS RNG", Color3.fromRGB(255, 220, 90))
		neon(parent, Vector3.new(45, 0.6, 1.4), board.CFrame * CFrame.new(0, 7.2, 0), theme.Trim)
		neon(parent, Vector3.new(45, 0.6, 1.4), board.CFrame * CFrame.new(0, -7.2, 0), theme.Trim)
	end
end

--------------------------------------------------------------------------
-- Zone
--------------------------------------------------------------------------

local function zoneCenter(index: number): Vector3
	return MapConfig.Origin + Vector3.new(0, 0, (index - 1) * (MapConfig.ZoneDepth + MapConfig.Bridge))
end

local function buildZone(zonesFolder: Instance, def: Zones.ZoneDef, index: number): Model
	local theme = MapThemes[def.Id]
	local center = zoneCenter(index)
	local halfW, halfD = MapConfig.ZoneWidth / 2, MapConfig.ZoneDepth / 2

	local zone = Instance.new("Model")
	zone.Name = def.Id
	zone:SetAttribute("Center", center)
	zone:SetAttribute("ZoneSize", Vector3.new(MapConfig.ZoneWidth, 60, MapConfig.ZoneDepth))

	-- Island
	local floor = part(zone, {
		Name = "Floor",
		Size = Vector3.new(MapConfig.ZoneWidth, 4, MapConfig.ZoneDepth),
		CFrame = CFrame.new(center - Vector3.new(0, 2, 0)),
		Color = theme.Floor,
		Material = theme.FloorMaterial,
	})
	zone.PrimaryPart = floor
	part(zone, {
		Name = "Underside",
		Size = Vector3.new(MapConfig.ZoneWidth - 8, 10, MapConfig.ZoneDepth - 8),
		CFrame = CFrame.new(center - Vector3.new(0, 8.5, 0)),
		Color = theme.Floor:Lerp(Color3.new(0, 0, 0), 0.6),
		Material = Enum.Material.Rock,
		CanCollide = false,
	})
	for _, side in { -1, 1 } do
		neon(zone, Vector3.new(MapConfig.ZoneWidth + 0.4, 0.6, 0.6), CFrame.new(center + Vector3.new(0, 0.05, side * halfD)), theme.Trim)
		neon(zone, Vector3.new(0.6, 0.6, MapConfig.ZoneDepth + 0.4), CFrame.new(center + Vector3.new(side * halfW, 0.05, 0)), theme.Trim)
	end

	-- Invisible walls (openings for the bridges in the middle of each end).
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = zone
	local function wall(size: Vector3, position: Vector3)
		local w = part(walls, { Name = "Wall", Size = size, CFrame = CFrame.new(position), Transparency = 1 })
		w.CanQuery = false
	end
	for _, side in { -1, 1 } do
		wall(Vector3.new(1, WALL_HEIGHT, MapConfig.ZoneDepth), center + Vector3.new(side * (halfW + 0.5), WALL_HEIGHT / 2, 0))
		local segment = (MapConfig.ZoneWidth - BRIDGE_WIDTH) / 2
		for _, endSide in { -1, 1 } do
			wall(Vector3.new(segment, WALL_HEIGHT, 1), center + Vector3.new(side * (BRIDGE_WIDTH / 2 + segment / 2), WALL_HEIGHT / 2, endSide * (halfD + 0.5)))
		end
	end
	if index == 1 then
		wall(Vector3.new(BRIDGE_WIDTH, WALL_HEIGHT, 1), center + Vector3.new(0, WALL_HEIGHT / 2, -halfD - 0.5))
	end
	if index == #Zones.List then
		wall(Vector3.new(BRIDGE_WIDTH, WALL_HEIGHT, 1), center + Vector3.new(0, WALL_HEIGHT / 2, halfD + 0.5))
	end

	buildKeyboard(zone, center + Vector3.new(0, 0, 6), def)

	-- Spawn near the entrance
	local spawnPosition = center + Vector3.new(0, 0.5, -halfD + 9)
	if index == 1 then
		local spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Name = "Spawn"
		spawnLocation.Size = Vector3.new(10, 1, 10)
		spawnLocation.CFrame = CFrame.lookAt(spawnPosition, spawnPosition + Vector3.new(0, 0, 1))
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
	else
		deco(zone, { Name = "Spawn", Size = Vector3.new(10, 1, 10), CFrame = CFrame.lookAt(spawnPosition, spawnPosition + Vector3.new(0, 0, 1)), Color = theme.Trim, Material = Enum.Material.Neon, Transparency = 0.6 })
	end

	-- Entrance gate (every zone but the first)
	if index > 1 then
		local gateZ = center.Z - halfD - 1
		for _, side in { -1, 1 } do
			deco(zone, { Name = "Pillar", Size = Vector3.new(3, 22, 3), CFrame = CFrame.new(center.X + side * (BRIDGE_WIDTH / 2 + 1.5), center.Y + 11, gateZ), Color = Color3.fromRGB(35, 35, 45), CanCollide = true })
			neon(zone, Vector3.new(3.2, 0.5, 3.2), CFrame.new(center.X + side * (BRIDGE_WIDTH / 2 + 1.5), center.Y + 21.5, gateZ), theme.Trim)
		end
		local beam = part(zone, { Name = "GateSign", Size = Vector3.new(BRIDGE_WIDTH + 6, 4, 2), CFrame = CFrame.new(center.X, center.Y + 24, gateZ), Color = Color3.fromRGB(30, 30, 40) })
		sign(beam, Enum.NormalId.Front, string.upper(def.Name), def.Color)
		sign(beam, Enum.NormalId.Back, string.upper(def.Name), def.Color)

		local barrier = part(zone, {
			Name = "Barrier",
			Size = Vector3.new(BRIDGE_WIDTH, 20, 1),
			CFrame = CFrame.new(center.X, center.Y + 10, gateZ),
			Color = theme.Trim,
			Material = Enum.Material.ForceField,
			Transparency = 0.15,
			CastShadow = false,
		})
		barrier.CanQuery = false
	end

	-- Props and backdrop
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = zone
	local build = PROPS[theme.Prop]
	if build then
		for _, spot in sideSpots(center, 3) do
			build(props, spot, center)
		end
	end
	backdrop(props, def, center)

	zone.Parent = zonesFolder
	return zone
end

local function buildBridge(parent: Instance, from: number)
	local a = zoneCenter(from)
	local b = zoneCenter(from + 1)
	local startZ = a.Z + MapConfig.ZoneDepth / 2
	local endZ = b.Z - MapConfig.ZoneDepth / 2
	local length = endZ - startZ
	local mid = Vector3.new(a.X, a.Y, (startZ + endZ) / 2)
	local fromTheme = MapThemes[Zones.List[from].Id]
	local toTheme = MapThemes[Zones.List[from + 1].Id]

	part(parent, { Name = "Bridge", Size = Vector3.new(BRIDGE_WIDTH, 2, length + 2), CFrame = CFrame.new(mid - Vector3.new(0, 1, 0)), Color = Color3.fromRGB(45, 45, 55), Material = Enum.Material.DiamondPlate })
	for _, side in { -1, 1 } do
		neon(parent, Vector3.new(0.5, 0.5, length), CFrame.new(mid + Vector3.new(side * BRIDGE_WIDTH / 2, 0.2, 0)), fromTheme.Trim:Lerp(toTheme.Trim, 0.5))
		local rail = part(parent, { Name = "Rail", Size = Vector3.new(1, WALL_HEIGHT, length), CFrame = CFrame.new(mid + Vector3.new(side * (BRIDGE_WIDTH / 2 + 0.5), WALL_HEIGHT / 2, 0)), Transparency = 1 })
		rail.CanQuery = false
	end
end

--------------------------------------------------------------------------
-- Falling off
--------------------------------------------------------------------------

local function nearestOwnedSpawn(player: Player, position: Vector3): BasePart?
	local data = PlayerData.get(player)
	local zonesFolder = workspace:FindFirstChild(Config.ZoneFolder)
	if not zonesFolder then return nil end
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, def in Zones.List do
		local owned = def.Id == Zones.Default or (data ~= nil and data.UnlockedWorlds[def.Id] == true)
		local zone = zonesFolder:FindFirstChild(def.Id)
		local spawnPart = zone and zone:FindFirstChild("Spawn")
		if owned and spawnPart and spawnPart:IsA("BasePart") then
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

	for index, def in Zones.List do
		if not (zonesFolder :: Instance):FindFirstChild(def.Id) then
			local zone = buildZone(zonesFolder :: Instance, def, index)
			table.insert(built, { def = def, center = zoneCenter(index), model = zone })
		end
		if index < #Zones.List then
			buildBridge(mapFolder, index)
		end
	end

	if MapConfig.TakeOverSpawns then
		for _, descendant in workspace:GetDescendants() do
			if descendant:IsA("SpawnLocation") and not descendant:IsDescendantOf(zonesFolder :: Instance) then
				descendant.Enabled = false
			end
		end
	end
	print(`[MapBuilder] built {#built} zone(s)`)
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
