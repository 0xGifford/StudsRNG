--[[

EventKeys
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/EventKeys

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Events you can see on the keys, and a splash when one starts or ends.
--
-- While an event with a Keys look runs (Config.Events), the caps of the
-- keys near the camera change colour (only on this client): Clack Frenzy
-- cycles every key through the rainbow out of step with its neighbours,
-- Lucky Rush and Blood Moon breathe in the event colour, Speed Rush rolls
-- bands of colour across the board, the Mega Boss makes keys flicker. Each
-- cap's own colour and material come back when it leaves range or the
-- event ends.
--
-- An event's Ambient adds particles drifting around the camera (golden
-- sparkles falling in Clack Frenzy, embers rising in Blood Moon...).
--
-- Cost: only the nearest MAX_KEYS keys within RANGE are touched, refreshed
-- once a second, painted UPDATE_RATE times a second; one particle emitter.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local RollLogic = require(Shared.Util.RollLogic)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local Interface = require(UI.Interface)
local Juice = require(UI.Juice)

local EventKeys = {}

local RANGE = 150 -- studs from the camera
local MAX_KEYS = 220
local UPDATE_RATE = 20 -- paints per second
local REFRESH = 1 -- seconds between re-picking which keys are in range

type Saved = { color: Color3, material: Enum.Material }
type KeyLook = { Mode: string, Color: Color3?, Speed: number?, Neon: boolean?, Sparkle: boolean? }

local saved: { [BasePart]: Saved } = {}
local lit: { BasePart } = {}
local look: KeyLook? = nil
local lookColor = Color3.new(1, 1, 1)
local eventId: string? = nil
local started = 0

local function capOf(hitbox: Instance): BasePart?
	local model = hitbox.Parent
	local cap = model and model:FindFirstChild("Cap")
	return if cap and cap:IsA("BasePart") then cap else nil
end

local function restore(cap: BasePart)
	local original = saved[cap]
	if original then
		saved[cap] = nil
		if cap.Parent then
			cap.Color = original.color
			cap.Material = original.material
		end
	end
end

local function restoreAll()
	for cap in saved do
		restore(cap)
	end
	table.clear(lit)
end

-- The nearest caps in range of the camera.
local function pick()
	local camera = workspace.CurrentCamera
	if not (camera and look) then return end
	local origin = camera.CFrame.Position
	local found: { { cap: BasePart, distance: number } } = {}
	for _, hitbox in CollectionService:GetTagged(Config.Press.HitboxTag) do
		if hitbox:IsA("BasePart") then
			local distance = (hitbox.Position - origin).Magnitude
			if distance <= RANGE then
				local cap = capOf(hitbox)
				if cap then
					table.insert(found, { cap = cap, distance = distance })
				end
			end
		end
	end
	table.sort(found, function(a, b)
		return a.distance < b.distance
	end)
	local keep: { [BasePart]: boolean } = {}
	table.clear(lit)
	for i = 1, math.min(#found, MAX_KEYS) do
		local cap = found[i].cap
		keep[cap] = true
		table.insert(lit, cap)
		if not saved[cap] then
			saved[cap] = { color = cap.Color, material = cap.Material }
		end
	end
	for cap in saved do
		if not keep[cap] then
			restore(cap)
		end
	end
end

-- A key's colour right now (t = seconds since the event started).
local function colorFor(cap: BasePart, original: Saved, t: number): Color3
	local current = look :: KeyLook
	local speed = current.Speed or 1
	local p = cap.Position
	local mode = current.Mode
	if mode == "Rainbow" then
		-- Each key at its own hue, all racing round the wheel.
		local hue = (t * speed * 0.6 + (p.X * 0.071 + p.Z * 0.053)) % 1
		return Color3.fromHSV(hue, 0.85, 1)
	elseif mode == "Wave" then
		local wave = 0.5 + 0.5 * math.sin((p.X + p.Z) * 0.12 - t * speed * math.pi * 2)
		return original.color:Lerp(lookColor, wave ^ 2)
	elseif mode == "Flicker" then
		-- Each key flashes now and then, at its own moments.
		local seed = (p.X * 12.9898 + p.Z * 78.233) % 1
		local phase = (t * speed + seed * 7) % 1
		return if phase < 0.18 then lookColor else original.color:Lerp(lookColor, 0.15)
	end
	-- Pulse
	local breath = 0.5 + 0.5 * math.sin(t * speed * math.pi * 2)
	return original.color:Lerp(lookColor, 0.25 + 0.6 * breath)
end

local function paint()
	if not look then return end
	local t = os.clock() - started
	local neon = look.Neon == true
	for _, cap in lit do
		local original = saved[cap]
		if original and cap.Parent then
			cap.Color = colorFor(cap, original, t)
			if neon and cap.Material ~= Enum.Material.Neon then
				cap.Material = Enum.Material.Neon
			end
		end
	end
end

-- The splash: a banner, a flash of the event's colour, a shake and confetti
-- as it starts; a smaller one as it ends.
local function announce(def: Config.EventDef?, previous: Config.EventDef?)
	if def then
		Juice.flash(def.Color, 0.35, 0.6)
		Juice.shake(0.35, 0.35)
		Juice.fov(5, 0.6)
		Juice.banner(string.upper(def.Name) .. "!", def.Description, def.Color, 2.4)
		Juice.confetti(60)
		Interface.play("Click", 0.8)
	elseif previous then
		Juice.banner(`{previous.Name} is over`, nil, previous.Color, 1.4)
	end
end

-- One invisible box above (or below) the camera, emitting the event's
-- particles; it follows the camera.
local ambientPart: Part? = nil
local ambientEmitter: ParticleEmitter? = nil
local ambientRise = false

local function setAmbient(def: Config.EventDef?)
	local ambient = def and def.Ambient
	if not ambient then
		if ambientEmitter then
			ambientEmitter.Enabled = false
		end
		return
	end
	if not ambientPart then
		local part = Instance.new("Part")
		part.Name = "EventAmbient"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(90, 1, 90)
		part.Parent = workspace.CurrentCamera
		local emitter = Instance.new("ParticleEmitter")
		emitter.LightEmission = 1
		emitter.Lifetime = NumberRange.new(3, 5)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-90, 90)
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 0.1),
			NumberSequenceKeypoint.new(0.8, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Size = NumberSequence.new(0.35, 0.15)
		emitter.Parent = part
		ambientPart, ambientEmitter = part, emitter
	end
	local emitter = ambientEmitter :: ParticleEmitter
	local color = ambient.Color or (def :: Config.EventDef).Color
	ambientRise = ambient.Rise == true
	emitter.Texture = ambient.Texture or "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.5))
	emitter.Rate = ambient.Rate
	emitter.EmissionDirection = if ambientRise then Enum.NormalId.Top else Enum.NormalId.Bottom
	emitter.Speed = NumberRange.new(4, 9)
	emitter.Acceleration = if ambientRise then Vector3.new(0, 2, 0) else Vector3.new(0, -3, 0)
	emitter.Enabled = true
end

local function followCamera()
	local part = ambientPart
	local camera = workspace.CurrentCamera
	if not (part and camera and ambientEmitter and ambientEmitter.Enabled) then return end
	local position = camera.CFrame.Position
	part.CFrame = CFrame.new(position + Vector3.new(0, if ambientRise then -18 else 30, 0))
end

local function setEvent(id: string?, splash: boolean)
	if id == eventId then return end
	local previous = RollLogic.eventById(eventId)
	eventId = id
	local def = RollLogic.eventById(id)
	restoreAll()
	look = if def then def.Keys else nil
	lookColor = if look and look.Color then look.Color else (if def then def.Color else Color3.new(1, 1, 1))
	started = os.clock()
	if look then
		pick()
	end
	setAmbient(def)
	if splash then
		announce(def, previous)
	end
end

-- Pressed keys burst brighter during a Sparkle event.
local function bindSparkle()
	local runtime = ReplicatedStorage:WaitForChild("KeyCapper", 30)
	local event = runtime and runtime:WaitForChild("KeyPressed", 30)
	if not (event and event:IsA("BindableEvent")) then return end
	event.Event:Connect(function(model: Instance?)
		if not (look and look.Sparkle and model) then return end
		local cap = model:FindFirstChild("Cap")
		if cap and cap:IsA("BasePart") then
			local attachment = Instance.new("Attachment")
			attachment.WorldPosition = cap.Position + Vector3.new(0, cap.Size.Y / 2, 0)
			attachment.Parent = workspace.Terrain
			local burst = Instance.new("ParticleEmitter")
			burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			burst.Rate = 0
			burst.Lifetime = NumberRange.new(0.35, 0.6)
			burst.Speed = NumberRange.new(10, 18)
			burst.SpreadAngle = Vector2.new(80, 80)
			burst.EmissionDirection = Enum.NormalId.Top
			burst.Acceleration = Vector3.new(0, -30, 0)
			burst.Size = NumberSequence.new(0.6, 0)
			burst.LightEmission = 1
			burst.Color = ColorSequence.new(Color3.fromHSV(math.random(), 0.8, 1))
			burst.Parent = attachment
			burst:Emit(10)
			task.delay(0.8, function()
				attachment:Destroy()
			end)
		end
	end)
end

function EventKeys.start()
	Interface.setup()
	local function current(): string?
		local id = ReplicatedStorage:GetAttribute("EventId")
		return if typeof(id) == "string" and id ~= "" then id else nil
	end
	ReplicatedStorage:GetAttributeChangedSignal("EventId"):Connect(function()
		setEvent(current(), true)
	end)
	-- Joining mid-event: the look, without the splash.
	setEvent(current(), false)
	task.spawn(bindSparkle)

	local sincePaint, sincePick = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		followCamera()
		if not look then return end
		sincePaint += dt
		sincePick += dt
		if sincePick >= REFRESH then
			sincePick = 0
			pick()
		end
		if sincePaint >= 1 / UPDATE_RATE then
			sincePaint = 0
			paint()
		end
	end)
end

return EventKeys
