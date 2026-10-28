--[[ 

Format
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/UI/Format

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Number and label formatting for the UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)

type StudDef = Types.StudDef
type VariantDef = Types.VariantDef

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 999 → "999", 1234 → "1.23K", 15600000 → "15.6M"
function Format.number(value: number): string
	if value ~= value then return "0" end
	local sign = if value < 0 then "-" else ""
	value = math.abs(value)
	if value < 1000 then
		return sign .. tostring(math.floor(value))
	end
	local tier = math.min(math.floor(math.log10(value) / 3), #SUFFIXES - 1)
	local scaled = value / 10 ^ (tier * 3)
	local text
	if scaled >= 100 then
		text = string.format("%d", math.floor(scaled))
	elseif scaled >= 10 then
		text = string.format("%.1f", math.floor(scaled * 10) / 10)
	else
		text = string.format("%.2f", math.floor(scaled * 100) / 100)
	end
	text = string.gsub(text, "%.?0+$", "")
	return sign .. text .. SUFFIXES[tier + 1]
end

function Format.oneIn(value: number): string
	return "1 in " .. Format.number(math.max(1, math.floor(value + 0.5)))
end

function Format.multiplier(value: number): string
	local text = string.format("%.2f", value)
	text = string.gsub(text, "%.?0+$", "")
	return "x" .. text
end

-- "Ember", "Shiny Ember", "Rainbow Void"
function Format.studName(def: StudDef, variant: VariantDef): string
	if variant.Name == "Normal" then
		return def.Name
	end
	return `{variant.Name} {def.Name}`
end

function Format.hex(color: Color3): string
	return string.format("#%02X%02X%02X", color.R * 255 + 0.5, color.G * 255 + 0.5, color.B * 255 + 0.5)
end

-- 75 → "01:15", 3725 → "1:02:05"
function Format.duration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s % 60)
	end
	return string.format("%02d:%02d", m, s % 60)
end

-- 0.25 → "25%", 0.035 → "3.5%"
function Format.percent(fraction: number): string
	local value = fraction * 100
	local text = if value >= 10 then string.format("%d", math.floor(value + 0.5)) else string.format("%.1f", value)
	text = string.gsub(text, "%.0$", "")
	return text .. "%"
end

-- A granted reward ({ Kind, Amount, Boost, Minutes }) as short text.
function Format.reward(reward: { [string]: any }): string
	local kind = reward.Kind
	local amount = reward.Amount or 0
	if kind == "Clacks" then
		return `+{Format.number(amount)} Clacks`
	elseif kind == "FreeRolls" then
		return `+{amount} Free Rolls`
	elseif kind == "Spins" then
		return if amount == 1 then "+1 Spin" else `+{amount} Spins`
	elseif kind == "Luck" then
		return `+{amount} Permanent Luck`
	elseif kind == "MegaRoll" then
		return `JACKPOT! x{Format.number(amount)} Luck Roll`
	elseif kind == "Boost" then
		local boost = reward.Boost and Config.Boosts[reward.Boost]
		local minutes = reward.Minutes or (if boost then boost.Duration / 60 else 0)
		return `{if boost then boost.Name else "Boost"} ({minutes}m)`
	end
	return tostring(kind)
end

return Format
