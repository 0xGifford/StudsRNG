--[[

IsoCamera
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/IsoCamera

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The isometric camera: it looks down at you from far away through a narrow
-- field of view (Config.Camera: 208 studs out along the (1, 1, 1) diagonal,
-- FOV 7, the same view as a camera at head + Vector3.new(120, 120, 120)).
--
-- Fitted to the zones:
--   * each Zone can override the view with attributes on its Zone model
--     (CameraDistance, CameraPitch, CameraYaw, CameraFov); it eases between
--     zones as you walk from one to the next
--   * walls and roofs between the camera and you fade out (locally), so
--     caves and buildings never hide you
--   * Camera.Focus stays on you, so streaming, level of detail and every
--     "near the player" check measure from you, not from the far-off lens
-- Scroll wheel / pinch zooms (Config.Camera.MinZoom..MaxZoom), Q / E turn
-- the view 90 degrees. It follows you smoothly and leads a little in the
-- direction you walk. Sounds are heard from your head, not the camera.
--
-- Other code: IsoCamera.setSuspended(true) hands the camera over (the intro
-- does); setSuspended(false) takes it back with a short blend from wherever
-- the camera was.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local ZoneAmbience = require(Controllers.ZoneAmbience)
local Interface = require(UI.Interface)
local Juice = require(UI.Juice)
local Roles = require(UI.Roles)

local IsoCamera = {}

local Settings = Config.Camera
local RENDER_NAME = "IsoCamera"
local FADE_RATE = 1 / 15 -- seconds between occlusion checks
local FADE_SPEED = 8 -- how fast walls fade in / out
local HANDOFF_TIME = 1.2 -- seconds to blend in after being suspended
local SNAP_DISTANCE = 60 -- studs: further than this in one frame (a teleport) snaps

local player = Players.LocalPlayer

type View = { distance: number, pitch: number, yaw: number, fov: number }

local suspended = false
local current: View = { distance = Settings.Distance, pitch = Settings.Pitch, yaw = Settings.Yaw, fov = Settings.FieldOfView }
local zoom = 1
local yawTurn = 0 -- Q / E: added to the zone's yaw, in degrees
local shownTurn = 0
local focus: Vector3? = nil
local handoff: { from: CFrame, fov: number, started: number }? = nil

--------------------------------------------------------------------------
-- The view for where you are
--------------------------------------------------------------------------

local zoneCache: { [string]: Instance | false } = {}

local function zoneModel(id: string): Instance?
	local cached = zoneCache[id]
	if cached == nil or (cached and not cached.Parent) then
		cached = Tags.forZone(Tags.Zone, id)[1] or false
		zoneCache[id] = cached
	end
	return if cached then cached else nil
end

local function number(instance: Instance?, name: string, default: number): number
	local value = instance and instance:GetAttribute(name)
	return if typeof(value) == "number" and value > 0 then value else default
end

local function wanted(): View
	local id = ZoneAmbience.current()
	local zone = if id then zoneModel(id) else nil
	return {
		distance = number(zone, "CameraDistance", Settings.Distance),
		pitch = number(zone, "CameraPitch", Settings.Pitch),
		-- Yaw may be 0 or negative: any number.
		yaw = if zone and typeof(zone:GetAttribute("CameraYaw")) == "number" then zone:GetAttribute("CameraYaw") :: number else Settings.Yaw,
		fov = number(zone, "CameraFov", Settings.FieldOfView),
	}
end

--------------------------------------------------------------------------
-- Fading what's in the way
--------------------------------------------------------------------------

local faded: { [BasePart]: number } = {} -- part → target LocalTransparencyModifier
local fadeParams = RaycastParams.new()
fadeParams.FilterType = Enum.RaycastFilterType.Exclude
local sinceFade = 0

local function blocking(from: Vector3, to: Vector3, found: { [BasePart]: boolean })
	local ignore: { Instance } = {}
	local character = player.Character
	if character then
		table.insert(ignore, character)
	end
	local direction = to - from
	for _ = 1, 10 do
		fadeParams.FilterDescendantsInstances = ignore
		local hit = workspace:Spherecast(from, 1.5, direction, fadeParams)
		if not hit then return end
		local part = hit.Instance
		table.insert(ignore, part)
		if part:IsA("BasePart") and part.Transparency < 0.95 then
			found[part] = true
		end
	end
end

local function updateFades(cameraPosition: Vector3, root: BasePart)
	local found: { [BasePart]: boolean } = {}
	if Settings.FadeWalls then
		-- To your head and your feet, so a low wall or a roof both count.
		blocking(cameraPosition, root.Position + Vector3.new(0, 2, 0), found)
		blocking(cameraPosition, root.Position - Vector3.new(0, 2, 0), found)
	end
	for part in found do
		faded[part] = Settings.FadeTransparency
	end
	for part in faded do
		if not found[part] then
			faded[part] = 0
		end
	end
end

local function stepFades(dt: number)
	local k = 1 - math.exp(-FADE_SPEED * dt)
	for part, target in faded do
		if not part.Parent then
			faded[part] = nil
			continue
		end
		local value = part.LocalTransparencyModifier
		value += (target - value) * k
		if target == 0 and value < 0.02 then
			part.LocalTransparencyModifier = 0
			faded[part] = nil
		else
			part.LocalTransparencyModifier = value
		end
	end
end

local function clearFades()
	for part in faded do
		if part.Parent then
			part.LocalTransparencyModifier = 0
		end
	end
	table.clear(faded)
end

--------------------------------------------------------------------------
-- Each frame
--------------------------------------------------------------------------

local function rootOf(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function ease(t: number): number
	return 1 - (1 - t) ^ 3
end

local function step(dt: number)
	if suspended or not Settings.Enabled then return end
	local camera = workspace.CurrentCamera
	local root = rootOf()
	if not (camera and root) then return end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	-- Ease toward this zone's view (and the Q / E turn).
	local want = wanted()
	local k = 1 - math.exp(-dt * 3 / math.max(Settings.Blend, 0.05))
	current.distance += (want.distance - current.distance) * k
	current.pitch += (want.pitch - current.pitch) * k
	current.yaw += (want.yaw - current.yaw) * k
	current.fov += (want.fov - current.fov) * k
	shownTurn += (yawTurn - shownTurn) * (1 - math.exp(-dt * 10))

	-- Follow, leading a little where you walk.
	local velocity = root.AssemblyLinearVelocity
	local lead = Vector3.new(velocity.X, 0, velocity.Z) * (Settings.LookAhead / 16)
	if lead.Magnitude > Settings.LookAhead then
		lead = lead.Unit * Settings.LookAhead
	end
	local target = root.Position + Vector3.new(0, Settings.FocusHeight, 0) + lead
	local previous = focus
	if not previous or (target - previous).Magnitude > SNAP_DISTANCE then
		focus = target
	else
		focus = previous:Lerp(target, 1 - math.exp(-Settings.Follow * dt))
	end
	local at = focus :: Vector3

	local yaw = math.rad(current.yaw + shownTurn)
	local pitch = math.rad(current.pitch)
	local direction = Vector3.new(math.cos(yaw) * math.cos(pitch), math.sin(pitch), math.sin(yaw) * math.cos(pitch))
	local position = at + direction * current.distance * zoom
	local cframe = CFrame.lookAt(position, at)
	local fov = current.fov * Juice.fovScale()

	-- Coming back from a cutscene: blend from where the camera was.
	local blend = handoff
	if blend then
		local t = (os.clock() - blend.started) / HANDOFF_TIME
		if t >= 1 then
			handoff = nil
		else
			local e = ease(t)
			cframe = blend.from:Lerp(cframe, e)
			fov = blend.fov + (fov - blend.fov) * e
		end
	end

	camera.CFrame = cframe
	camera.Focus = CFrame.new(at)
	camera.FieldOfView = fov

	sinceFade += dt
	if sinceFade >= FADE_RATE then
		sinceFade = 0
		updateFades(cframe.Position, root)
	end
	stepFades(dt)
end

--------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------

local function canZoom(gameProcessed: boolean): boolean
	return not suspended and not gameProcessed and not Interface.isOpen()
end

local function setZoom(value: number)
	zoom = math.clamp(value, Settings.MinZoom, Settings.MaxZoom)
end

local function bindInput()
	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseWheel and canZoom(gameProcessed) then
			setZoom(zoom * (1 - Settings.ZoomStep * input.Position.Z))
		end
	end)
	local pinchStart = 1
	UserInputService.TouchPinch:Connect(function(_positions, scale, _velocity, state, gameProcessed)
		if not canZoom(gameProcessed) then return end
		if state == Enum.UserInputState.Begin then
			pinchStart = zoom
		end
		setZoom(pinchStart / math.max(scale, 0.05))
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or suspended or not Settings.RotateKeys then return end
		if input.KeyCode == Enum.KeyCode.Q then
			yawTurn -= 90
		elseif input.KeyCode == Enum.KeyCode.E then
			yawTurn += 90
		end
	end)
end

-- Sounds are heard from your head (the camera is far away).
local function listenFromHead(character: Model)
	local head = character:WaitForChild("Head", 10)
	if head and head:IsA("BasePart") and Settings.Enabled then
		SoundService:SetListener(Enum.ListenerType.ObjectCFrame, head)
	end
end

--------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------

function IsoCamera.setSuspended(value: boolean)
	if suspended == value then return end
	suspended = value
	local camera = workspace.CurrentCamera
	if value then
		clearFades()
	elseif camera then
		-- Blend in from the cutscene's last shot.
		handoff = { from = camera.CFrame, fov = camera.FieldOfView, started = os.clock() }
		focus = nil
	end
end

function IsoCamera.isActive(): boolean
	return Settings.Enabled and not suspended
end

function IsoCamera.start()
	if not Settings.Enabled then return end
	Interface.setup()
	Juice.ownFov(true)
	-- World UI distances are "from you": add how far the camera can be.
	Roles.distanceBonus = math.ceil(Settings.Distance * Settings.MaxZoom)
	player.DevEnableMouseLock = false -- shift lock makes no sense from up here
	bindInput()
	if player.Character then
		task.spawn(listenFromHead, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		focus = nil
		listenFromHead(character)
	end)
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value, step)
end

return IsoCamera
