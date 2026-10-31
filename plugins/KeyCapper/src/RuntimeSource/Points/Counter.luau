--!strict
-- Single responsibility: the top-center points number, and how it REACTS when
-- a point lands. Owns nothing but its own pixels: it is told a value and told
-- "a point just landed", and never decides what the score is.
--
-- The resting state is deliberately bare — a white outlined number, top
-- center, no card, no background, no border. Everything else in this module
-- is TRANSIENT: every effect returns the counter to exactly that resting
-- state, so the HUD is only ever "just the number" when nothing is happening.
--
-- The feel is built from four things landing together, which is what makes an
-- impact read as one event rather than four effects:
--   * a punch — fast scale up, slow elastic settle (see PUNCH_* below);
--   * a wobble — a few degrees of rotation, unwinding elastically;
--   * a shockwave — a ring that expands out of the number and fades;
--   * a rising pitch on the landing sound as presses chain into a combo.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(script.Parent.Parent:WaitForChild("Config"))

local Counter = {}
Counter.__index = Counter

-- One knob for the whole HUD's size. Every pixel metric in this module and in
-- PointPopup is expressed against it, so the counter and its "+1"s cannot
-- drift out of proportion with each other — change this alone to rescale the
-- entire HUD.
Counter.SCALE = 2.5

-- Exported: PointPopup sizes itself against this so a "+1" can never read as
-- bigger or louder than the total it is feeding.
Counter.TEXT_SIZE = 34 * Counter.SCALE

-- Exported so PointPopup outlines its "+1" identically: the counter and the
-- popups have to read as the same typeface at the same weight, and a stroke
-- that differs between them is immediately visible as two different fonts.
-- 2.1 rather than 3 — at SCALE 2.5 a 3px base stroke was thick enough to eat
-- into the counters of the glyphs and blunt them.
Counter.STROKE_THICKNESS = 2.1 * Counter.SCALE

local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
local TOP_MARGIN = 20 * Counter.SCALE

-- The punch. Asymmetric on purpose and this is the whole trick: a scale-up
-- that is over almost before it is seen (PUNCH_UP), then a long elastic
-- return that does the actual selling (PUNCH_DOWN). Symmetric easing on both
-- halves reads as a gentle pulse; this reads as an impact.
local PUNCH_SCALE = 1.30
local PUNCH_UP = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PUNCH_DOWN = TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
-- Combo adds to the punch on top of PUNCH_SCALE. Kept small: the counter has
-- to stay readable at the top of a streak, and a number that doubles in size
-- stops reading as a number.
local PUNCH_COMBO_BONUS = 0.12

local WOBBLE_DEGREES = 5
local WOBBLE_INFO = TweenInfo.new(0.55, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)

local RING_TIME = 0.4
local RING_START_PADDING = 14 * Counter.SCALE -- how far outside the digits the ring is born
local RING_GROWTH = 46 * Counter.SCALE -- how much further it travels before dying
local RING_THICKNESS = 2 * Counter.SCALE

-- Presses closer together than this chain into a combo; a gap resets it.
-- 0.6s is a little above a fast typist's inter-key gap, so ordinary typing
-- sustains a combo and pausing visibly drops it.
local COMBO_WINDOW = 0.6
local COMBO_MAX = 8
-- A rising pitch across a streak is doing most of the audible work here — the
-- same trick as a coin run in a platformer. The jitter on top keeps a
-- sustained streak from sounding like a loop.
local PITCH_COMBO_RANGE = 0.5
local PITCH_JITTER = 0.06

-- Numbers only roll when they jump by more than one. A single press must
-- change the digits on the SAME frame the key went down — rolling a +1 would
-- put the number behind the punch that is meant to be celebrating it. A jump
-- (the server reconciling a rejoin with a higher persisted total) is the case
-- worth animating, and there the roll is what makes it read as earned.
local ROLL_TIME = 0.45

-- The counter growing in from nothing when the HUD is first built.
local INTRO_TIME = 0.5

function Counter.new(gui: ScreenGui)
	local self = setmetatable({}, Counter)
	self.gui = gui
	self.shown = 0 -- what the digits currently read
	self.target = 0 -- what they are heading toward
	self.combo = 0
	self.lastLand = 0
	self.wobbleSide = 1
	self.activeScale = nil :: Tween?
	self.activeRotation = nil :: Tween?
	self.rollConnection = nil :: RBXScriptConnection?

	-- AnchorPoint is centered on BOTH axes so the punch and the wobble pivot
	-- around the middle of the digits. Anchored at the top (the obvious
	-- choice for a top-margin HUD) the number would visibly grow downward and
	-- swing from its top edge, which reads as a hinge rather than an impact.
	local holder = Instance.new("Frame")
	holder.Name = "Counter"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.new(0.5, 0, 0, TOP_MARGIN + Counter.TEXT_SIZE / 2)
	holder.Size = UDim2.fromOffset(0, Counter.TEXT_SIZE)
	holder.AutomaticSize = Enum.AutomaticSize.X
	holder.BackgroundTransparency = 1
	-- Above the shockwave rings, which are siblings (see _shockwave) at
	-- ZIndex 1. Equal ZIndex would fall back to child order, and a ring
	-- created later would paint over the digits.
	holder.ZIndex = 2
	holder.Parent = gui
	self.holder = holder

	-- Fixed TextSize + AutomaticSize, NOT TextScaled: TextScaled recomputes
	-- the glyph layout against the label's OWN size every frame, which fought
	-- with the UIScale punch — the digits would grow past whatever bounding
	-- box the label had a moment before ("les chiffres dépassent le
	-- compteur"). A fixed size that the box grows to fit is stable no matter
	-- how many digits or how hard the punch is currently stretching them.
	local label = Instance.new("TextLabel")
	label.Name = "Value"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0, 0, 1, 0)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.TextSize = Counter.TEXT_SIZE
	label.FontFace = FONT
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 1
	label.Text = "0"
	label.Parent = holder
	self.label = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = Counter.STROKE_THICKNESS
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label

	local scale = Instance.new("UIScale")
	scale.Parent = holder
	self.scale = scale

	local sound = Instance.new("Sound")
	sound.Name = "PointsLand"
	sound.SoundId = Config.POINTS_LAND_SOUND_ID
	sound.Volume = Config.POINTS_LAND_SOUND_VOLUME
	sound.Parent = gui
	self.sound = sound

	self:_intro()

	return self
end

-- The digits grow out of nothing when the HUD first appears, rather than
-- being there already on frame one. Back/Out overshoots past full size and
-- settles, so the arrival uses the same vocabulary as the punch every point
-- landing will use — the counter introduces itself by doing a small version
-- of the thing it does.
--
-- Held in activeScale like any other scale animation so a point landing
-- during the intro cancels it cleanly instead of fighting it.
function Counter:_intro()
	self.scale.Scale = 0
	local grow = TweenService:Create(
		self.scale,
		TweenInfo.new(INTRO_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	self.activeScale = grow
	grow:Play()
end

-- Screen-space center of the digits. Popups aim here, and it has to be read
-- fresh every time rather than cached: the counter widens as it gains digits,
-- so a target cached at "9" would miss by half a glyph at "1000".
function Counter:Center(): Vector2
	return self.holder.AbsolutePosition + self.holder.AbsoluteSize / 2
end

function Counter:_render()
	self.label.Text = tostring(math.floor(self.shown))
end

-- Sets the value the digits should read. A step of one lands instantly; a
-- larger jump rolls (see ROLL_TIME above).
function Counter:Set(value: number)
	self.target = value

	if self.rollConnection then
		self.rollConnection:Disconnect()
		self.rollConnection = nil
	end

	if math.abs(value - self.shown) <= 1 then
		self.shown = value
		self:_render()
		return
	end

	local from = self.shown
	local elapsed = 0
	self.rollConnection = RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		local t = math.clamp(elapsed / ROLL_TIME, 0, 1)
		-- Ease out: the roll should sprint through the middle digits and coast
		-- onto the final one, not crawl to it at a constant rate.
		local eased = 1 - (1 - t) ^ 3
		self.shown = from + (self.target - from) * eased
		self:_render()

		if t >= 1 then
			self.shown = self.target
			self:_render()
			if self.rollConnection then
				self.rollConnection:Disconnect()
				self.rollConnection = nil
			end
		end
	end)
end

-- A ring born at the edge of the digits and expanding outward. Parented to
-- the ScreenGui rather than to the counter on purpose: the holder is
-- AutomaticSize.X, so a child wider than the digits would stretch the counter
-- itself and shove the number off center for as long as the ring lived.
function Counter:_shockwave()
	local center = self:Center()
	local startSize = self.holder.AbsoluteSize.X + RING_START_PADDING

	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromOffset(center.X, center.Y)
	ring.Size = UDim2.fromOffset(startSize, startSize)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 1 -- under the number: the impact radiates from behind it
	ring.Parent = self.gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = RING_THICKNESS
	stroke.Transparency = 0.35
	stroke.Parent = ring

	-- Quart Out on both: the ring should be almost fully grown and almost
	-- gone within the first third of its life, so it registers as a flash of
	-- impact rather than as an expanding circle the eye can follow.
	local info = TweenInfo.new(RING_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local grown = startSize + RING_GROWTH
	TweenService:Create(ring, info, { Size = UDim2.fromOffset(grown, grown) }):Play()

	local fade = TweenService:Create(stroke, info, { Transparency = 1, Thickness = 0 })
	fade:Play()
	fade.Completed:Once(function()
		ring:Destroy()
	end)
end

function Counter:_punch(intensity: number)
	local scale = self.scale

	-- Cancel rather than stack. Two tweens driving the same property fight
	-- for it every frame, which is what made a fast typist's counter look
	-- broken instead of energetic.
	if self.activeScale then
		self.activeScale:Cancel()
	end
	if self.activeRotation then
		self.activeRotation:Cancel()
	end

	scale.Scale = 1
	local peak = PUNCH_SCALE + PUNCH_COMBO_BONUS * intensity
	local up = TweenService:Create(scale, PUNCH_UP, { Scale = peak })
	self.activeScale = up
	up:Play()
	up.Completed:Once(function(state: Enum.PlaybackState)
		if state ~= Enum.PlaybackState.Completed or not scale.Parent then return end
		local down = TweenService:Create(scale, PUNCH_DOWN, { Scale = 1 })
		self.activeScale = down
		down:Play()
	end)

	-- Alternating sides rather than a random one: a streak that tips the same
	-- way twice reads as a drift, and one that picks randomly reads as noise.
	-- Strict alternation reads as recoil.
	self.wobbleSide = -self.wobbleSide
	self.holder.Rotation = WOBBLE_DEGREES * self.wobbleSide * (0.6 + 0.4 * intensity)
	local unwind = TweenService:Create(self.holder, WOBBLE_INFO, { Rotation = 0 })
	self.activeRotation = unwind
	unwind:Play()
end

function Counter:_playSound(intensity: number)
	local sound = self.sound
	if sound.SoundId == "" then return end
	sound.PlaybackSpeed = 1
		+ intensity * PITCH_COMBO_RANGE
		+ (math.random() * 2 - 1) * PITCH_JITTER
	sound:Play()
end

-- Called the instant a "+1" reaches the counter. Everything fires together:
-- that simultaneity is what makes it land as a single impact.
function Counter:Land()
	local now = os.clock()
	self.combo = (now - self.lastLand <= COMBO_WINDOW) and math.min(self.combo + 1, COMBO_MAX) or 0
	self.lastLand = now
	local intensity = self.combo / COMBO_MAX

	self:_punch(intensity)
	self:_shockwave()
	self:_playSound(intensity)
end

return Counter
