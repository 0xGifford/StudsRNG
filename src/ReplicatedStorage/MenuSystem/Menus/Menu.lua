--!strict
-- ModuleScript -> ReplicatedStorage/MenuSystem/Menus/Menu
--
-- One menu. Owns its own animation state, so a reopen landing mid-close
-- can't leave a panel disabled at full scale. Opens and closes with the UI
-- pack's motion (PackShared).
--
-- Sound comes in two kinds, and the difference matters:
--
--   MenuOpenSound / MenuCloseSound
--     One-shot stings. Created, played, discarded. Nothing holds them,
--     so nothing can stop them -- which is why a long track put here
--     keeps playing after the menu closes.
--
--   MenuMusic
--     A looping bed the menu owns. Created once, faded in on open and
--     out on close, and stopped when the fade finishes.

local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local MenuSystem = script.Parent.Parent
local Config = require(MenuSystem.Config)
local PackShared = require(script.Parent.PackShared)

local ATTR = Config.Attributes
local SOUND = Config.Sound or {}

--------------------------------------------------------------------
-- MOTION
--------------------------------------------------------------------
-- The UI pack's: the panel scales 0.92 -> 1 opening and 1 -> 0.92 closing,
-- 0.125s Quad Out both ways (PackShared.PlayOpen / PlayClose). At rest the
-- panel's UIScale is 0 closed and 1 open.

local effectsModule: any = nil
local function getEffects(): any
	if effectsModule == nil then
		local m = script.Parent:FindFirstChild("Effects")
		local ok, result = pcall(function()
			return m and require(m :: any)
		end)
		effectsModule = (ok and result) or false
	end
	return effectsModule or nil
end

--------------------------------------------------------------------
-- MUSIC SETTINGS
--------------------------------------------------------------------
-- Resolved once, with a fallback for every value. Music that won't stop
-- because a config key is missing is a much worse failure than music at
-- the wrong fade time, so nothing here is allowed to be nil.

local function number(value: any, fallback: number): number
	return (type(value) == "number" and value == value and value >= 0)
		and value
		or fallback
end

local MUSIC = {
	Volume = number(SOUND.MusicVolume, 0.35),
	FadeIn = number(SOUND.MusicFadeIn, 0.6),
	FadeOut = number(SOUND.MusicFadeOut, 0.8),
	Resumes = SOUND.MusicResumes ~= false,
}

-- Named at load rather than at the moment a menu misbehaves
do
	local missing = {}
	for _, key in ipairs({ "MusicVolume", "MusicFadeIn", "MusicFadeOut" }) do
		if type(SOUND[key]) ~= "number" then table.insert(missing, key) end
	end

	if #missing > 0 then
		warn(("[Menu] Config.Sound is missing %s; using defaults")
			:format(table.concat(missing, ", ")))
	end
end

local STING_VOLUME = number(SOUND.Volume, 0.5)
local STING_LIFETIME = number(SOUND.MaxLifetime, 6)

--------------------------------------------------------------------

local Menu = {}
Menu.__index = Menu

export type Menu = typeof(setmetatable({} :: {
	Name: string,
	Gui: ScreenGui,
	Panel: GuiObject,
	Scale: UIScale,
	IsOpen: boolean,
	_tween: Tween?,
	_music: Sound?,
	_musicTween: Tween?,
}, Menu))

--------------------------------------------------------------------

-- A marked panel wins; otherwise the first GuiObject child. Explicit beats
-- guessing, but guessing beats refusing to work.
local function findPanel(gui: ScreenGui): GuiObject?
	for _, d in ipairs(gui:GetDescendants()) do
		if d:GetAttribute(ATTR.MenuPanel) == true and d:IsA("GuiObject") then
			return d
		end
	end

	for _, child in ipairs(gui:GetChildren()) do
		if child:IsA("GuiObject") then return child end
	end
	return nil
end

function Menu.new(gui: ScreenGui): Menu?
	local panel = findPanel(gui)
	if not panel then
		if Config.Behaviour.WarnOnMissingPanel then
			warn(string.format(
				"[Menu] '%s' has nothing to animate; set %s = true on its frame",
				gui.Name, ATTR.MenuPanel))
		end
		return nil
	end

	local scale = panel:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "UIScale"
		scale.Parent = panel
	end

	scale.Scale = 0
	gui.Enabled = false
	gui.ResetOnSpawn = false

	return setmetatable({
		Name = gui.Name,
		Gui = gui,
		Panel = panel,
		Scale = scale,
		IsOpen = false,
		_tween = nil,
		_music = nil,
		_musicTween = nil,
	}, Menu)
end

--------------------------------------------------------------------

function Menu:IsExclusive(): boolean
	local value = self.Gui:GetAttribute(ATTR.MenuExclusive)
	if value == nil then return Config.Behaviour.ExclusiveByDefault end
	return value == true
end

function Menu:HotKey(): Enum.KeyCode?
	local name = self.Gui:GetAttribute(ATTR.MenuKey)
	if type(name) ~= "string" then return nil end

	local ok, key = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	return ok and key or nil
end

--------------------------------------------------------------------
-- ONE-SHOT SOUNDS
--------------------------------------------------------------------

-- Parented to SoundService rather than the ScreenGui: a close sting should
-- outlive the panel that triggered it.
local function playSting(gui: ScreenGui, attribute: string, fallback: any)
	local id = gui:GetAttribute(attribute)
	if id == nil then id = fallback end
	if type(id) ~= "string" or id == "" then return end

	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = STING_VOLUME
	sound.Parent = SoundService
	sound:Play()

	sound.Ended:Connect(function() sound:Destroy() end)

	-- Ended never fires for an id that fails to load, which would leak an
	-- instance per open
	Debris:AddItem(sound, STING_LIFETIME)
end

--------------------------------------------------------------------
-- MUSIC
--------------------------------------------------------------------

function Menu:_musicVolume(): number
	return number(self.Gui:GetAttribute(ATTR.MenuMusicVolume), MUSIC.Volume)
end

-- Created once and kept. A fresh Sound per open would restart the track
-- every time and give nothing to fade out.
function Menu:_ensureMusic(): Sound?
	local id = self.Gui:GetAttribute(ATTR.MenuMusic)
	if type(id) ~= "string" or id == "" then return nil end

	local existing = self._music

	if existing and existing.Parent then
		-- The attribute can be edited live while tuning
		if existing.SoundId ~= id then existing.SoundId = id end
		return existing
	end

	local sound = Instance.new("Sound")
	sound.Name = "Music_" .. self.Name
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = SoundService

	self._music = sound
	return sound
end

function Menu:_cancelMusicTween()
	if self._musicTween then
		self._musicTween:Cancel()
		self._musicTween = nil
	end
end

function Menu:_fadeMusic(target: number, seconds: number, stopAfter: boolean?)
	local sound = self._music
	if not sound or not sound.Parent then return end

	self:_cancelMusicTween()

	-- A zero or invalid time means snap rather than skip. Doing nothing
	-- here is how music ends up playing forever.
	if seconds <= 0 then
		sound.Volume = target
		if stopAfter and not self.IsOpen then sound:Stop() end
		return
	end

	local tween = TweenService:Create(
		sound,
		TweenInfo.new(seconds, Enum.EasingStyle.Linear),
		{ Volume = target })

	self._musicTween = tween

	if stopAfter then
		tween.Completed:Connect(function(state)
			-- Cancelled means a reopen landed mid-fade, so leave it playing
			if state == Enum.PlaybackState.Completed and not self.IsOpen then
				sound:Stop()
			end
		end)
	end

	tween:Play()
end

function Menu:_startMusic()
	local sound = self:_ensureMusic()
	if not sound then return end

	-- Resumes rather than restarts when reopened quickly, so flicking a
	-- menu shut and open again doesn't jump back to the first bar
	if not sound.IsPlaying then
		if not MUSIC.Resumes then
			sound.TimePosition = 0
		end
		sound:Play()
	end

	self:_fadeMusic(self:_musicVolume(), MUSIC.FadeIn)
end

function Menu:_stopMusic()
	if not self._music then return end
	self:_fadeMusic(0, MUSIC.FadeOut, true)
end

-- Stops immediately, for a teardown or a hard reset
function Menu:StopMusic()
	self:_cancelMusicTween()

	if self._music and self._music.Parent then
		self._music.Volume = 0
		self._music:Stop()
	end
end

--------------------------------------------------------------------

-- Reduced motion: the OS / Roblox preference, or the in-game setting
-- (GameSettings mirrors it onto the player and into Effects).
local function reducedMotion(): boolean
	local ok, system = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	if ok and system == true then return true end
	local player = Players.LocalPlayer
	if player and player:GetAttribute("ReducedMotion") == true then return true end
	local Effects = getEffects()
	return Effects ~= nil and Effects.IsReduced ~= nil and Effects.IsReduced() == true
end

function Menu:Open()
	if self.IsOpen then return end
	self.IsOpen = true

	if self._tween then self._tween:Cancel() end

	self.Gui.Enabled = true
	playSting(self.Gui, ATTR.MenuOpenSound, SOUND.DefaultOpen)
	self:_startMusic()

	if reducedMotion() then
		self.Scale.Scale = 1
		return
	end
	self._tween = PackShared.PlayOpen(self.Scale)
end

function Menu:Close()
	if not self.IsOpen then return end
	self.IsOpen = false

	if self._tween then self._tween:Cancel() end

	playSting(self.Gui, ATTR.MenuCloseSound, SOUND.DefaultClose)
	self:_stopMusic()

	if reducedMotion() then
		self.Gui.Enabled = false
		self.Scale.Scale = 0
		return
	end

	local tween = PackShared.PlayClose(self.Scale)
	self._tween = tween
	tween.Completed:Connect(function()
		-- A reopen may have landed during the close tween
		if not self.IsOpen then
			self.Gui.Enabled = false
			self.Scale.Scale = 0
		end
	end)
end

function Menu:Destroy()
	if self._tween then self._tween:Cancel() end
	self._tween = nil

	self:_cancelMusicTween()

	-- Destroyed rather than faded: the menu is going away, and a fade with
	-- nothing left to own it would keep playing forever
	if self._music then
		self._music:Destroy()
		self._music = nil
	end
end

return Menu