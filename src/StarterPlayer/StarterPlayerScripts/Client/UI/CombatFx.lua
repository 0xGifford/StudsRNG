--[[

CombatFx
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/UI/CombatFx

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- World-space combat effects, shared by Controllers/Enemies and
-- Controllers/StudFollowers. Client-only parts in one folder, all cleaned
-- up by themselves:
--   CombatFx.sound(name, at?, pitch?, volume?)  Config.Combat.Sounds, SFX group
--   CombatFx.sparks(part, count?, color?)       spark burst on a part
--   CombatFx.impact(position, color, size)      quick neon ring + pop
--   CombatFx.shockwave(position, color, size)   flat ring rolling outward
--   CombatFx.debris(cframe, color, size, count) the enemy bursts into bricks
--   CombatFx.coins(from, count, onArrive?)      coins burst, then fly to you

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Interface = require(script.Parent.Interface)

local CombatFx = {}

local SOUNDS = Config.Combat.Sounds
local COIN_COLOR = Color3.fromRGB(255, 205, 60)

local player = Players.LocalPlayer
local folder: Folder? = nil

local function container(): Folder
	if folder and folder.Parent then return folder end
	local f = Instance.new("Folder")
	f.Name = "CombatFx"
	f.Parent = workspace
	folder = f
	return f
end

local function fxPart(shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- 2D when `at` is nil, else from that position in the world.
function CombatFx.sound(name: string, at: Vector3?, pitch: number?, volume: number?)
	local id = SOUNDS[name]
	if not id then return end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 0.5
	sound.PlaybackSpeed = (pitch or 1) * (0.94 + math.random() * 0.12)
	sound.SoundGroup = Interface.SFX
	if at then
		local holder = fxPart()
		holder.Transparency = 1
		holder.Size = Vector3.one
		holder.Position = at
		holder.Parent = container()
		sound.RollOffMaxDistance = 120
		sound.Parent = holder
		Debris:AddItem(holder, 3)
	else
		sound.Parent = SoundService
		Debris:AddItem(sound, 3)
	end
	sound:Play()
end

function CombatFx.sparks(part: BasePart, count: number?, color: Color3?)
	local attachment = Instance.new("Attachment")
	local half = part.Size.X / 2
	attachment.Position = Vector3.new(math.random() - 0.5, math.random() * 0.6, math.random() - 0.5).Unit * half
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	local tint = color or Color3.fromRGB(255, 240, 150)
	sparks.Color = ColorSequence.new(tint, Color3.fromRGB(255, 150, 60))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.2, 0.45)
	sparks.Speed = NumberRange.new(12, 22)
	sparks.SpreadAngle = Vector2.new(80, 80)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Enabled = false
	sparks.Parent = attachment
	attachment.Parent = part
	sparks:Emit(count or 10)
	Debris:AddItem(attachment, 0.7)
end

function CombatFx.impact(position: Vector3, color: Color3, size: number)
	local ball = fxPart(Enum.PartType.Ball)
	ball.Color = color
	ball.Size = Vector3.one * size * 0.4
	ball.Transparency = 0.2
	ball.Position = position
	ball.Parent = container()
	TweenService:Create(ball, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * size * 1.8,
		Transparency = 1,
	}):Play()
	Debris:AddItem(ball, 0.3)
end

function CombatFx.shockwave(position: Vector3, color: Color3, size: number)
	local ring = fxPart(Enum.PartType.Cylinder)
	ring.Color = color
	ring.Size = Vector3.new(0.3, size, size)
	ring.Transparency = 0.25
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = container()
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.1, size * 5, size * 5),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.5)

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = size * 4
	light.Brightness = 4
	light.Parent = ring
	TweenService:Create(light, TweenInfo.new(0.45), { Brightness = 0 }):Play()
end

-- The enemy bursts into its own bricks, which tumble, then shrink away.
function CombatFx.debris(cframe: CFrame, color: Color3, size: number, count: number)
	for _ = 1, count do
		local brick = fxPart()
		brick.Material = Enum.Material.SmoothPlastic
		brick.TopSurface = Enum.SurfaceType.Studs
		brick.Color = color:Lerp(Color3.new(1, 1, 1), math.random() * 0.25)
		local piece = size * (0.15 + math.random() * 0.15)
		brick.Size = Vector3.new(piece, piece, piece)
		brick.CFrame = cframe * CFrame.new((math.random() - 0.5) * size * 0.6, (math.random() - 0.3) * size * 0.6, (math.random() - 0.5) * size * 0.6)
		brick.Anchored = false
		brick.CanCollide = true
		brick.Parent = container()
		local out = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
		out = if out.Magnitude > 0.01 then out.Unit else Vector3.xAxis
		brick.AssemblyLinearVelocity = out * (14 + math.random() * 16) + Vector3.new(0, 22 + math.random() * 18, 0)
		brick.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
		task.delay(1 + math.random() * 0.4, function()
			if brick.Parent then
				brick.Anchored = true
				TweenService:Create(brick, TweenInfo.new(0.4), { Size = Vector3.one * 0.05, Transparency = 1 }):Play()
			end
		end)
		Debris:AddItem(brick, 2)
	end
end

-- Coins burst out of `from`, hang for a beat, then fly into the player.
function CombatFx.coins(from: Vector3, count: number, onArrive: (() -> ())?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then return end
	local arrived = 0
	for i = 1, count do
		local coin = fxPart(Enum.PartType.Cylinder)
		coin.Color = COIN_COLOR
		coin.Material = Enum.Material.Neon
		coin.Size = Vector3.new(0.25, 1.1, 1.1)
		coin.Parent = container()
		local burst = from + Vector3.new((math.random() - 0.5) * 7, 2 + math.random() * 4, (math.random() - 0.5) * 7)
		local start = os.clock()
		local delayTime = 0.25 + i * 0.04
		local flyTime = 0.35
		local connection: RBXScriptConnection
		connection = RunService.RenderStepped:Connect(function()
			local t = os.clock() - start
			local position: Vector3
			if t < delayTime then
				local k = math.min(1, t / 0.2)
				position = from:Lerp(burst, 1 - (1 - k) ^ 3)
			else
				local k = math.min(1, (t - delayTime) / flyTime)
				local target = root.Position
				position = burst:Lerp(target, k * k) + Vector3.new(0, math.sin(k * math.pi) * 2, 0)
				if k >= 1 then
					connection:Disconnect()
					coin:Destroy()
					arrived += 1
					CombatFx.sound("Coin", nil, 1 + arrived * 0.05, 0.25)
					if arrived == count and onArrive then
						onArrive()
					end
					return
				end
			end
			coin.CFrame = CFrame.new(position) * CFrame.Angles(0, t * 10, math.pi / 2)
		end)
		Debris:AddItem(coin, 3)
	end
end

return CombatFx
