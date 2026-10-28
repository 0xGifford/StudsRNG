--!strict
-- GAME-side counterpart of the plugin's GroupRegistry: reads the group data
-- the plugin wrote, nothing more. Read-only on purpose — the runtime must
-- never edit what the plugin owns.
--
-- Tolerates the folder being absent entirely: a game whose keys were placed
-- before groups existed keeps working on the Config defaults.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(script.Parent.Parent.Config)
local SoundId = require(script.Parent.SoundId)

local GroupConfig = {}

local function groupOf(name: string?): Configuration?
	if not name then return nil end
	local folder = ReplicatedStorage:FindFirstChild(Config.GROUPS_FOLDER)
	if not folder then return nil end
	local group = folder:FindFirstChild(name)
	return group and group :: Configuration or nil
end

-- Splits the comma-separated list the plugin stores. Empty list = the caller
-- falls back to the global default sound.
--
-- Every entry goes through SoundId.Parse, so a bare number stored by an older
-- version (or typed before the panel started normalising) still plays, and
-- anything unusable is dropped here rather than assigned to a Sound where it
-- would fail silently at press time.
function GroupConfig.SoundIds(name: string?): { string }
	local group = groupOf(name)
	if not group then return {} end

	local raw = group:GetAttribute("SoundIds")
	if type(raw) ~= "string" or raw == "" then return {} end

	local ids: { string } = {}
	for piece in string.gmatch(raw, "[^,]+") do
		local id = SoundId.Parse(piece)
		if id then
			table.insert(ids, id)
		end
	end
	return ids
end

function GroupConfig.PitchJitter(name: string?): number
	local group = groupOf(name)
	local jitter = group and group:GetAttribute("PitchJitter")
	if type(jitter) ~= "number" then return Config.SOUND_PITCH_JITTER end
	return jitter
end

function GroupConfig.Volume(name: string?): number
	local group = groupOf(name)
	local volume = group and group:GetAttribute("Volume")
	if type(volume) ~= "number" then return Config.SOUND_VOLUME end
	return volume
end

function GroupConfig.AnimationStyle(name: string?): string?
	local group = groupOf(name)
	local style = group and group:GetAttribute("AnimationStyle")
	return type(style) == "string" and style or nil
end

function GroupConfig.PressTime(name: string?): number
	local group = groupOf(name)
	local time = group and group:GetAttribute("PressTime")
	if type(time) ~= "number" then return Config.PRESS_TIME end
	return time
end

function GroupConfig.ReleaseTime(name: string?): number
	local group = groupOf(name)
	local time = group and group:GetAttribute("ReleaseTime")
	if type(time) ~= "number" then return Config.RELEASE_TIME end
	return time
end

return GroupConfig
