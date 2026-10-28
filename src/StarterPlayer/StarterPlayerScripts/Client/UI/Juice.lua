--[[

Juice
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/UI/Juice

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Game-feel effects, shared by every controller:
--   Juice.shake(strength, duration)      camera shake (decays)
--   Juice.fov(amount, duration)          FOV punch that springs back
--   Juice.flash(color, alpha, duration)  full-screen flash
--   Juice.confetti(count, origin?)       UI confetti burst (screen pixels)
--   Juice.banner(title, subtitle, color) big centre title card (queued)
--   Juice.pop(guiObject, scale?)         elastic scale punch

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Juice = {}

local player = Players.LocalPlayer
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 90, 120), Color3.fromRGB(255, 210, 70), Color3.fromRGB(110, 230, 120),
	Color3.fromRGB(90, 190, 255), Color3.fromRGB(190, 120, 255),
}

local gui: ScreenGui? = nil

local function screen(): ScreenGui
	local existing = gui
	if existing and existing.Parent then return existing end
	local created = Instance.new("ScreenGui")
	created.Name = "Juice"
	created.ResetOnSpawn = false
	created.IgnoreGuiInset = true
	created.DisplayOrder = 25
	created.Parent = player:WaitForChild("PlayerGui")
	gui = created
	return created
end

--------------------------------------------------------------------------
-- Camera
--------------------------------------------------------------------------

local shakeStrength = 0
local shakeEnd = 0
local shakeDuration = 1

RunService:BindToRenderStep("JuiceShake", Enum.RenderPriority.Camera.Value + 1, function()
	local now = os.clock()
	if now >= shakeEnd then return end
	local camera = workspace.CurrentCamera
	if not camera then return end
	local fade = (shakeEnd - now) / shakeDuration
	local s = shakeStrength * fade
	local offset = CFrame.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
		* CFrame.Angles(0, 0, math.rad((math.random() - 0.5) * s * 4))
	camera.CFrame *= offset
end)

function Juice.shake(strength: number, duration: number)
	local now = os.clock()
	-- A stronger shake replaces a weaker one; a weaker one doesn't cut it short.
	if now < shakeEnd and strength < shakeStrength * (shakeEnd - now) / shakeDuration then return end
	shakeStrength = strength
	shakeDuration = duration
	shakeEnd = now + duration
end

local baseFov: number? = nil

function Juice.fov(amount: number, duration: number)
	local camera = workspace.CurrentCamera
	if not camera then return end
	local base = baseFov or camera.FieldOfView
	baseFov = base
	camera.FieldOfView = base + amount
	local tween = TweenService:Create(camera, TweenInfo.new(duration, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { FieldOfView = base })
	tween:Play()
	tween.Completed:Once(function()
		baseFov = nil
	end)
end

--------------------------------------------------------------------------
-- Screen effects
--------------------------------------------------------------------------

function Juice.flash(color: Color3, alpha: number, duration: number)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 1 - alpha
	frame.BorderSizePixel = 0
	frame.ZIndex = 1
	frame.Parent = screen()
	local tween = TweenService:Create(frame, TweenInfo.new(duration, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 })
	tween:Play()
	tween.Completed:Once(function()
		frame:Destroy()
	end)
end

type Bit = { frame: Frame, velocity: Vector2, spin: number, life: number }

-- origin: screen pixels (defaults to the screen centre).
function Juice.confetti(count: number, origin: Vector2?)
	local parent = screen()
	local size = parent.AbsoluteSize
	local start = origin or size / 2
	local bits: { Bit } = {}
	for _ = 1, count do
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Size = UDim2.fromOffset(math.random(6, 12), math.random(10, 18))
		frame.Position = UDim2.fromOffset(start.X, start.Y)
		frame.BackgroundColor3 = CONFETTI_COLORS[math.random(#CONFETTI_COLORS)]
		frame.BorderSizePixel = 0
		frame.Rotation = math.random(0, 360)
		frame.ZIndex = 5
		frame.Parent = parent
		local angle = math.rad(math.random(200, 340))
		local speed = math.random(450, 1000)
		table.insert(bits, {
			frame = frame,
			velocity = Vector2.new(math.cos(angle), math.sin(angle)) * speed,
			spin = math.random(-720, 720),
			life = math.random(120, 200) / 100,
		})
	end

	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local alive = false
		for _, bit in bits do
			if elapsed < bit.life then
				alive = true
				bit.velocity = Vector2.new(bit.velocity.X * (1 - 1.5 * dt), bit.velocity.Y + 1400 * dt)
				local position = bit.frame.Position
				bit.frame.Position = UDim2.fromOffset(position.X.Offset + bit.velocity.X * dt, position.Y.Offset + bit.velocity.Y * dt)
				bit.frame.Rotation += bit.spin * dt
				bit.frame.BackgroundTransparency = math.clamp((elapsed - bit.life + 0.4) / 0.4, 0, 1)
			elseif bit.frame.Parent then
				bit.frame:Destroy()
			end
		end
		if not alive then
			connection:Disconnect()
		end
	end)
end

function Juice.pop(target: GuiObject, scale: number?)
	local uiScale = target:FindFirstChild("JuicePop")
	if not (uiScale and uiScale:IsA("UIScale")) then
		local created = Instance.new("UIScale")
		created.Name = "JuicePop"
		created.Parent = target
		uiScale = created
	end
	local s = uiScale :: UIScale
	s.Scale = scale or 1.25
	TweenService:Create(s, TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

--------------------------------------------------------------------------
-- Banners
--------------------------------------------------------------------------

type Banner = { title: string, subtitle: string, color: Color3, hold: number }
local queue: { Banner } = {}
local showing = false

local function label(text: string, size: UDim2, position: UDim2, color: Color3, parent: Instance): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Size = size
	l.Position = position
	l.TextScaled = true
	l.FontFace = FONT
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Text = text
	l.ZIndex = 10
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.55), color)
	gradient.Rotation = 90
	gradient.Parent = l
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 20, 25)
	stroke.Thickness = 3
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = l
	l.Parent = parent
	return l
end

local function showNext()
	local banner = table.remove(queue, 1)
	if not banner then
		showing = false
		return
	end
	showing = true

	local holder = Instance.new("CanvasGroup")
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.3)
	holder.Size = UDim2.fromScale(0.7, 0.2)
	holder.ZIndex = 10
	holder.Parent = screen()
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 4.2
	ratio.Parent = holder

	label(banner.title, UDim2.fromScale(1, 0.62), UDim2.fromScale(0.5, 0.35), banner.color, holder)
	if banner.subtitle ~= "" then
		local sub = label(banner.subtitle, UDim2.fromScale(0.8, 0.26), UDim2.fromScale(0.5, 0.82), Color3.new(1, 1, 1), holder)
		sub.ZIndex = 11
	end

	local scale = Instance.new("UIScale")
	scale.Scale = 2.2
	scale.Parent = holder
	holder.GroupTransparency = 1
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(holder, TweenInfo.new(0.15), { GroupTransparency = 0 }):Play()

	task.delay(0.35 + banner.hold, function()
		local out = TweenService:Create(holder, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			GroupTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.22),
		})
		out:Play()
		out.Completed:Wait()
		holder:Destroy()
		showNext()
	end)
end

function Juice.banner(title: string, subtitle: string?, color: Color3?, hold: number?)
	-- Keep the queue short: stale banners are worse than skipped ones.
	if #queue >= 3 then
		table.remove(queue, 1)
	end
	table.insert(queue, { title = title, subtitle = subtitle or "", color = color or Color3.fromRGB(255, 220, 90), hold = hold or 1.6 })
	if not showing then
		showNext()
	end
end

return Juice
