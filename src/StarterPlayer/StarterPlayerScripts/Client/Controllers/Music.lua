--[[

Music
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/Music

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Background music: Config.Music.SoundId loops in the Music SoundGroup, so
-- the Options menu's Music slider (OptionsMenu → Interface.Music.Volume)
-- controls it. Fades in once loaded.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local Interface = require(UI.Interface)

local Music = {}

local MusicConfig = Config.Music

function Music.start()
	Interface.setup()

	local sound = Instance.new("Sound")
	sound.Name = "BackgroundMusic"
	sound.SoundId = MusicConfig.SoundId
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = Interface.Music
	sound.Parent = SoundService

	if not sound.IsLoaded then
		sound.Loaded:Wait()
	end
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(MusicConfig.FadeIn), { Volume = MusicConfig.Volume }):Play()
end

return Music
