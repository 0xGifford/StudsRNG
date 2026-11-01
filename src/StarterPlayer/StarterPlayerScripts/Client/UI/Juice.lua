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
--
-- The flash, confetti and banner are copies of the templates in
-- StarterGui.Juice (tools/ui/screens/Juice.luau): restyle them there.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Roles = require(script.Parent.Roles)

local Juice = {}

local CONFETTI_COLORS = {
	Color3.fromRGB(255, 90, 120), Color3.fromRGB(255, 210, 70), Color3.fromRGB(110, 230, 120),
	Color3.fromRGB(90, 190, 255), Color3.fromRGB(190, 120, 255),
}

local gui: ScreenGui? = nil

local function screen(): ScreenGui
	local existing = gui
	if existing and existing.Parent then return existing end
	local found = Roles.gui("Juice")
	gui = found
	return found
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

-- FOV punch. `amount` is in degrees at a normal 70 degree view; it scales
-- with the real one, so the narrow isometric camera punches by the same
-- share. When a camera controller owns the FOV (Juice.ownFov), it reads
-- Juice.fovScale() each frame instead of the camera being tweened here.
local baseFov: number? = nil
local fovOwned = false
local kickAmount = 0
local kickStart = 0
local kickDuration = 1

function Juice.ownFov(owned: boolean)
	fovOwned = owned
end

-- The current punch as a multiplier on the base FOV (1 = none).
function Juice.fovScale(): number
	local t = (os.clock() - kickStart) / kickDuration
	if t >= 1 or kickAmount == 0 then return 1 end
	-- Elastic settle back to 1.
	local settle = 2 ^ (-10 * t) * math.cos(t * math.pi * 4)
	return 1 + kickAmount * settle
end

function Juice.fov(amount: number, duration: number)
	kickAmount = amount / 70
	kickStart = os.clock()
	kickDuration = math.max(duration, 0.05)
	if fovOwned then return end
	local camera = workspace.CurrentCamera
	if not camera then return end
	local base = baseFov or camera.FieldOfView
	baseFov = base
	camera.FieldOfView = base * (1 + kickAmount)
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
	local parent = screen()
	local frame = Roles.template(parent, "Flash")
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 1 - alpha
	frame.Parent = parent
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
		local frame = Roles.template(parent, "ConfettiBit")
		frame.Size = UDim2.fromOffset(math.random(6, 12), math.random(10, 18))
		frame.Position = UDim2.fromOffset(start.X, start.Y)
		frame.BackgroundColor3 = CONFETTI_COLORS[math.random(#CONFETTI_COLORS)]
		frame.Rotation = math.random(0, 360)
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

local function tint(label: Instance?, color: Color3)
	local gradient = label and label:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.55), color)
	end
end

local function showNext()
	local banner = table.remove(queue, 1)
	if not banner then
		showing = false
		return
	end
	showing = true

	local parent = screen()
	local holder = Roles.template(parent, "Banner") :: CanvasGroup
	local home = holder.Position
	local title = Roles.find(holder, "JuiceRole", "Title")
	local sub = Roles.find(holder, "JuiceRole", "Subtitle")
	if title and title:IsA("TextLabel") then
		title.Text = banner.title
		tint(title, banner.color)
	end
	if sub and sub:IsA("TextLabel") then
		sub.Text = banner.subtitle
		sub.Visible = banner.subtitle ~= ""
		tint(sub, Color3.new(1, 1, 1))
	end

	local scale = holder:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = holder
	end
	local uiScale = scale :: UIScale
	uiScale.Scale = 2.2
	holder.GroupTransparency = 1
	holder.Parent = parent
	TweenService:Create(uiScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(holder, TweenInfo.new(0.15), { GroupTransparency = 0 }):Play()

	task.delay(0.35 + banner.hold, function()
		local out = TweenService:Create(holder, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			GroupTransparency = 1,
			Position = home - UDim2.fromScale(0, 0.08),
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
