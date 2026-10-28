--!strict
-- One key. Single responsibility: its pressed/released state, its
-- animation, its sound. Knows NOTHING about detection: it's just told
-- Press() / Release(), that's it.

local TweenService = game:GetService("TweenService")
local Config = require(script.Parent.Parent.Config)
local GroupConfig = require(script.Parent.Parent.Style.GroupConfig)
local AnimationPresets = require(script.Parent.Parent.Style.AnimationPresets)
local SoundGate = require(script.Parent.Parent.Style.SoundGate)

local Keycap = {}
Keycap.__index = Keycap

function Keycap.new(hitbox: BasePart)
	local model = hitbox.Parent
	local cap = model and model:FindFirstChild("Cap")
	if not (cap and cap:IsA("BasePart")) then
		-- Under streaming, the hitbox can arrive before the Cap: this isn't
		-- an error, the registry will retry once the model is complete.
		return nil
	end

	local self = setmetatable({}, Keycap)
	self.hitbox = hitbox
	self.cap = cap
	self.group = model:GetAttribute(Config.ATTR_GROUP)
	-- Resolved once at build time: a key does not change group while the game
	-- runs, and re-reading the folder on every press would be wasteful.
	self.soundIds = GroupConfig.SoundIds(self.group)
	self.pitchJitter = GroupConfig.PitchJitter(self.group)
	self.volume = GroupConfig.Volume(self.group)
	self.restCFrame = cap.CFrame -- rest position, captured once
	self.restSize = cap.Size -- rest size, captured once
	self.pressed = false
	self.tween = nil
	self.sound = self:_buildSound()

	-- Style and durations are resolved once, like sound: a key does not
	-- change group mid-game, so there is nothing to gain re-reading the
	-- group's attributes on every press.
	local style = AnimationPresets.Resolve(GroupConfig.AnimationStyle(self.group))
	self.style = style
	self.pressInfo = TweenInfo.new(
		GroupConfig.PressTime(self.group),
		style.PressEasingStyle,
		style.PressEasingDirection
	)
	self.releaseInfo = TweenInfo.new(
		GroupConfig.ReleaseTime(self.group),
		style.ReleaseEasingStyle,
		style.ReleaseEasingDirection
	)

	return self
end

function Keycap:_buildSound(): Sound
	local sound = Instance.new("Sound")
	sound.Name = "KeyCapperSound"
	-- A group with no sound of its own falls back to the global default.
	sound.SoundId = self.soundIds[1] or Config.SOUND_ID
	sound.Volume = self.volume
	sound.RollOffMaxDistance = Config.SOUND_MAX_DISTANCE
	sound.Parent = self.hitbox -- 3D sound, emitted from the key
	return sound
end

function Keycap:_tweenTo(targetCFrame: CFrame, targetSize: Vector3, info: TweenInfo)
	if self.tween then
		self.tween:Cancel()
	end
	self.tween = TweenService:Create(self.cap, info, { CFrame = targetCFrame, Size = targetSize })
	self.tween:Play()
end

function Keycap:Press()
	if self.pressed then return end
	self.pressed = true

	local style = self.style
	-- CFrame.new(0, -depth, 0) applied AFTER restCFrame = translation in the
	-- cap's local frame. This is what makes the press correct on a slope.
	-- The tilt multiplies on the RIGHT of the sink, so it too is expressed in
	-- the cap's local frame: a preset that rocks the cap rocks it about the
	-- cap's own axis, which is what keeps it correct on a sloped surface.
	-- Presets with no tilt pass 0 and this is an identity rotation.
	local targetCFrame = self.restCFrame
		* CFrame.new(0, -style.PressDepth, 0)
		* CFrame.Angles(math.rad(style.PressTilt or 0), 0, 0)
	local targetSize = Vector3.new(
		self.restSize.X * style.PressSizeScale.X,
		self.restSize.Y * style.PressSizeScale.Y,
		self.restSize.Z * style.PressSizeScale.Z
	)
	self:_tweenTo(targetCFrame, targetSize, self.pressInfo)

	-- Picked per press, not per key: that's what keeps a long typing run from
	-- sounding like a loop.
	if #self.soundIds > 1 then
		self.sound.SoundId = self.soundIds[math.random(#self.soundIds)]
	end

	-- Checked AFTER the animation is under way, and it only skips the sound:
	-- a key whose sound was merged into one already playing still goes down.
	-- Asked after the random pick too, since which asset this press landed on
	-- is exactly what the gate is deciding about.
	if not SoundGate.Allow(self.sound.SoundId) then return end

	self.sound.PlaybackSpeed = 1 + (math.random() * 2 - 1) * self.pitchJitter
	self.sound:Play()
end

function Keycap:Release()
	if not self.pressed then return end
	self.pressed = false
	self:_tweenTo(self.restCFrame, self.restSize, self.releaseInfo)
end

function Keycap:Destroy()
	if self.tween then self.tween:Cancel() end
	if self.sound then self.sound:Destroy() end
	-- The key may have been streamed out: the Cap no longer exists then.
	if self.cap and self.cap.Parent then
		self.cap.CFrame = self.restCFrame
		self.cap.Size = self.restSize
	end
end

return Keycap
