--[[

LuckyMeter
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/LuckyMeter

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The Lucky Roll meter (StarterGui.LuckyMeter, LuckyRole pieces): every roll
-- fills it (PlayerData.LuckyMeter, Systems/Rolls); when it's full the next
-- roll is a LUCKY ROLL with Config.LuckyMeter.Luck times the luck. One roll
-- away, the bar glows and pulses so you know the next one counts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Roles = require(UI.Roles)
local Juice = require(UI.Juice)

local Menus = ReplicatedStorage:WaitForChild("MenuSystem"):WaitForChild("Menus")
local ProgressBar = require(Menus:WaitForChild("ProgressBar"))

local LuckyMeter = {}

local ROLE = "LuckyRole"
local player = Players.LocalPlayer

local meter: GuiObject
local fill: GuiObject?
local label: TextLabel?
local outline: UIStroke?
local outlineColor = Color3.new()
local readyColor = Color3.fromRGB(120, 255, 140)
local pulse: Tween? = nil
local last = -1

local function render()
	local needed = Config.LuckyMeter.Rolls
	local value = State.get("LuckyMeter") or 0
	local ready = value >= needed - 1
	if fill then
		ProgressBar.Set(fill, { Progress = if ready then 1 else value / needed })
	end
	if label then
		label.Text = if ready then "🍀 NEXT ROLL IS LUCKY!" else `🍀 LUCKY ROLL {value}/{needed}`
	end
	if outline then
		outline.Color = if ready then readyColor else outlineColor
	end

	-- One roll away: pulse until it's used.
	local scale = meter:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", meter)
	if ready and not pulse then
		local tween = TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.08 })
		tween:Play()
		pulse = tween
		Interface.play("Click", 1.5)
	elseif not ready and pulse then
		pulse:Cancel()
		pulse = nil
		scale.Scale = 1
	end
	-- Just used (back to the start): a pop.
	if last >= needed - 1 and value < last then
		Juice.pop(meter, 1.2)
	end
	last = value
end

function LuckyMeter.start()
	Interface.setup()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("LuckyMeter", 15)
	local found = gui and Roles.find(gui, ROLE, "Meter")
	if not (gui and found) then
		warn("[LuckyMeter] StarterGui.LuckyMeter is missing (run tools/sync_scripts.luau on your place); no meter shown")
		return
	end
	meter = found
	fill = Roles.find(gui, ROLE, "Fill")
	label = Roles.find(gui, ROLE, "Label")
	outline = meter:FindFirstChildOfClass("UIStroke")
	if outline then
		outlineColor = outline.Color
	end
	local ready = meter:GetAttribute("ReadyColor")
	if typeof(ready) == "Color3" then
		readyColor = ready
	end

	if not State.isReady() then
		State.Ready:Wait()
	end
	render()
	State.Changed:Connect(function(field)
		if field == "LuckyMeter" then
			render()
		end
	end)
end

return LuckyMeter
