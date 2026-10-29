--[[

EnemyVisuals
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/EnemyVisuals

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Draws every enemy. The server only moves an invisible proxy part (Body,
-- 20 updates a second, Systems/Combat); here each enemy gets its brick
-- monster (body, eyes, brows, mouth, feet; Mini Bosses a crown, Titans horns
-- and spikes too) that glides after the proxy every frame and is animated
-- procedurally:
--   idle bob, hopping feet and a forward lean while walking, recoil when
--   hit, blinking, red glowing eyes while it hunts you, and rising out of
--   the ground on spawn.
-- Every piece is anchored and placed with one BulkMoveTo per frame; enemies
-- far from the camera aren't animated.
--
-- Other controllers anchor UI and effects to the visual, not the proxy:
--   EnemyVisuals.rootOf(model) -> BasePart?   EnemyVisuals.modelOf(model) -> Model?

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tags = require(Shared.Tags)

local EnemyVisuals = {}

local ANIMATE_RANGE = 260 -- studs from the camera
local FOLLOW = 14 -- position smoothing (higher = snappier)
local TURN = 10
local WHITE = Color3.fromRGB(245, 245, 245)
local BLACK = Color3.fromRGB(20, 20, 26)
local RED = Color3.fromRGB(255, 70, 50)
local GOLD = Color3.fromRGB(255, 205, 60)

local player = Players.LocalPlayer

type Piece = { part: BasePart, offset: CFrame, kind: string, side: number }
type Visual = {
	model: Model,
	proxy: BasePart,
	root: BasePart,
	pieces: { Piece },
	pupils: { BasePart },
	whites: { BasePart },
	size: number,
	boss: boolean,
	position: Vector3,
	rotation: CFrame,
	phase: number,
	spawnedAt: number,
	hit: number,
	lastHealth: number,
	nextBlink: number,
	blinking: boolean,
	hunting: boolean,
	connections: { RBXScriptConnection },
}

local visuals: { [Model]: Visual } = {}
local folder: Folder

local function newPart(size: Vector3, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Studs
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

local function build(model: Model, proxy: BasePart): Visual
	local s = proxy.Size.X
	local color = model:GetAttribute("Color")
	local bodyColor = if typeof(color) == "Color3" then color else proxy.Color
	local boss = model:GetAttribute("Boss") == true
	local titan = model:GetAttribute("ZoneBoss") == true

	local visual = Instance.new("Model")
	visual.Name = model.Name
	local root = newPart(Vector3.new(s, s * 0.8, s), bodyColor)
	root.Name = "Body"
	root.Parent = visual
	visual.PrimaryPart = root

	local pieces: { Piece } = {}
	local pupils, whites = {}, {}
	local function add(kind: string, side: number, size: Vector3, offset: CFrame, partColor: Color3, material: Enum.Material?): BasePart
		local part = newPart(size, partColor, material)
		part.Parent = visual
		table.insert(pieces, { part = part, offset = offset, kind = kind, side = side })
		return part
	end

	for _, side in { -1, 1 } do
		table.insert(whites, add("eye", side, Vector3.new(s * 0.22, s * 0.26, 0.2), CFrame.new(side * s * 0.2, s * 0.08, -s / 2 - 0.1), WHITE))
		table.insert(pupils, add("pupil", side, Vector3.new(s * 0.1, s * 0.13, 0.15), CFrame.new(side * s * 0.18, s * 0.05, -s / 2 - 0.22), if boss then RED else BLACK, if boss then Enum.Material.Neon else nil))
		add("brow", side, Vector3.new(s * 0.26, s * 0.06, 0.15), CFrame.new(side * s * 0.2, s * 0.26, -s / 2 - 0.12) * CFrame.Angles(0, 0, side * 0.35), BLACK)
		add("foot", side, Vector3.new(s * 0.3, 0.6, s * 0.4), CFrame.new(side * s * 0.25, -s * 0.4 - 0.3, -s * 0.05), bodyColor:Lerp(BLACK, 0.4))
	end
	add("mouth", 0, Vector3.new(s * 0.4, s * 0.08, 0.15), CFrame.new(0, -s * 0.18, -s / 2 - 0.1), BLACK)
	if boss then
		add("crown", 0, Vector3.new(s * 0.7, s * 0.14, s * 0.7), CFrame.new(0, s * 0.47, 0), GOLD, Enum.Material.Foil)
		for k = 0, 3 do
			local a = k * math.pi / 2
			add("crown", 0, Vector3.new(s * 0.14, s * 0.22, s * 0.14), CFrame.new(math.cos(a) * s * 0.26, s * 0.62, math.sin(a) * s * 0.26), GOLD, Enum.Material.Foil)
		end
	end
	if titan then
		local horn = Color3.fromRGB(70, 20, 25)
		for _, side in { -1, 1 } do
			add("horn", side, Vector3.new(s * 0.12, s * 0.4, s * 0.12), CFrame.new(side * s * 0.42, s * 0.42, -s * 0.15) * CFrame.Angles(0, 0, -side * 0.5), horn)
		end
		for k = -1, 1 do
			add("spike", 0, Vector3.new(s * 0.1, s * 0.3, s * 0.18), CFrame.new(k * s * 0.22, s * 0.3, s * 0.42) * CFrame.Angles(-0.6, 0, 0), horn)
		end
	end
	visual.Parent = folder

	local health = model:GetAttribute("Health")
	return {
		model = visual,
		proxy = proxy,
		root = root,
		pieces = pieces,
		pupils = pupils,
		whites = whites,
		size = s,
		boss = boss,
		position = proxy.Position,
		rotation = proxy.CFrame.Rotation,
		phase = math.random() * math.pi * 2,
		spawnedAt = os.clock(),
		hit = 0,
		lastHealth = if typeof(health) == "number" then health else 0,
		nextBlink = os.clock() + 1 + math.random() * 3,
		blinking = false,
		hunting = false,
		connections = {},
	}
end

local function setEyeColor(visual: Visual, color: Color3, neon: boolean)
	for _, pupil in visual.pupils do
		pupil.Color = color
		pupil.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
end

local function untrack(instance: Instance)
	local visual = visuals[instance :: Model]
	if not visual then return end
	visuals[instance :: Model] = nil
	for _, connection in visual.connections do
		connection:Disconnect()
	end
	visual.model:Destroy()
end

local function track(instance: Instance): Visual?
	if not instance:IsA("Model") then return nil end
	local existing = visuals[instance]
	if existing then return existing end
	local proxy = instance.PrimaryPart or instance:FindFirstChild("Body")
	if not (proxy and proxy:IsA("BasePart")) then return nil end
	local visual = build(instance, proxy)
	visuals[instance] = visual

	table.insert(visual.connections, instance.AttributeChanged:Connect(function(name)
		if name == "Health" then
			local health = instance:GetAttribute("Health")
			if typeof(health) == "number" then
				if health < visual.lastHealth then
					visual.hit = 1
				end
				visual.lastHealth = health
			end
		elseif name == "Hunting" then
			local hunting = instance:GetAttribute("Hunting") == player.UserId
			if hunting ~= visual.hunting then
				visual.hunting = hunting
				setEyeColor(visual, if hunting or visual.boss then RED else BLACK, hunting or visual.boss)
			end
		end
	end))
	table.insert(visual.connections, instance.AncestryChanged:Connect(function()
		if not instance:IsDescendantOf(workspace) then
			untrack(instance)
		end
	end))
	return visual
end

--------------------------------------------------------------------------
-- Animation
--------------------------------------------------------------------------

local parts: { BasePart } = {}
local cframes: { CFrame } = {}

local function blink(visual: Visual, now: number)
	if visual.blinking then
		if now >= visual.nextBlink then
			visual.blinking = false
			for _, eye in visual.whites do
				eye.Size = Vector3.new(eye.Size.X, visual.size * 0.26, eye.Size.Z)
			end
			visual.nextBlink = now + 2 + math.random() * 3
		end
	elseif now >= visual.nextBlink then
		visual.blinking = true
		for _, eye in visual.whites do
			eye.Size = Vector3.new(eye.Size.X, visual.size * 0.04, eye.Size.Z)
		end
		visual.nextBlink = now + 0.12
	end
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	local cameraPos = camera and camera.CFrame.Position or Vector3.zero
	local now = os.clock()
	table.clear(parts)
	table.clear(cframes)

	for _, visual in visuals do
		local proxy = visual.proxy
		if (proxy.Position - cameraPos).Magnitude > ANIMATE_RANGE then continue end
		local s = visual.size

		-- Glide after the proxy.
		local previous = visual.position
		visual.position = previous:Lerp(proxy.Position, 1 - math.exp(-FOLLOW * dt))
		visual.rotation = visual.rotation:Lerp(proxy.CFrame.Rotation, 1 - math.exp(-TURN * dt))
		local velocity = (visual.position - previous) / math.max(dt, 1e-3)
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local walk = math.clamp(speed / 8, 0, 1)

		-- Body motion: idle bob, walking hop, lean, hit recoil, spawn rise.
		local t = now + visual.phase
		local bob = math.sin(t * 2.6) * 0.1 * s * (1 - walk)
		local hop = math.abs(math.sin(t * 9)) * 0.12 * s * walk
		local lean = walk * 0.22
		visual.hit = math.max(0, visual.hit - dt * 5)
		local recoil = visual.hit ^ 2
		local rise = math.clamp((now - visual.spawnedAt) / 0.6, 0, 1)
		local riseOffset = -(1 - (1 - (1 - rise) ^ 3)) * s
		local rootCFrame = CFrame.new(visual.position + Vector3.new(0, bob + hop + riseOffset, 0))
			* visual.rotation
			* CFrame.new(0, 0, recoil * 0.35 * s)
			* CFrame.Angles(-lean + recoil * 0.35, 0, 0)
		table.insert(parts, visual.root)
		table.insert(cframes, rootCFrame)

		blink(visual, now)
		for _, piece in visual.pieces do
			local offset = piece.offset
			if piece.kind == "foot" then
				-- Alternate feet lift and swing while walking.
				local stride = math.sin(t * 9 + (if piece.side > 0 then math.pi else 0))
				offset = CFrame.new(0, math.max(0, stride) * 0.3 * s * walk - (bob + hop) * 0.6, -stride * 0.15 * s * walk) * offset
			elseif piece.kind == "brow" and visual.hunting then
				offset = offset * CFrame.Angles(0, 0, piece.side * 0.25) -- angrier
			end
			table.insert(parts, piece.part)
			table.insert(cframes, rootCFrame * offset)
		end
	end

	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

--------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------

-- The visual body (falls back to nothing; callers use the proxy then).
function EnemyVisuals.rootOf(model: Model): BasePart?
	local visual = visuals[model] or track(model)
	return if visual then visual.root else nil
end

function EnemyVisuals.modelOf(model: Model): Model?
	local visual = visuals[model] or track(model)
	return if visual then visual.model else nil
end

function EnemyVisuals.init()
	folder = Instance.new("Folder")
	folder.Name = "EnemyVisuals"
	folder.Parent = workspace
end

function EnemyVisuals.start()
	for _, model in CollectionService:GetTagged(Tags.Enemy) do
		task.spawn(track, model)
	end
	CollectionService:GetInstanceAddedSignal(Tags.Enemy):Connect(function(model)
		if model:IsA("Model") and not (model.PrimaryPart or model:FindFirstChild("Body")) then
			model:WaitForChild("Body", 5)
		end
		track(model)
	end)
	CollectionService:GetInstanceRemovedSignal(Tags.Enemy):Connect(untrack)
	RunService.RenderStepped:Connect(update)
end

return EnemyVisuals
