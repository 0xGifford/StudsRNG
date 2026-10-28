--[[

WheelMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/WheelMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The jackpot wheel. Segments 1-8 show Shared/Rewards.Wheel prizes and their
-- odds. The server picks the prize; the wheel then spins to land that
-- segment under the pointer (each segment's angle is read from where its
-- icon sits on the wheel image). Buy1 / Buy5 sell spins for Robux.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RewardDefs = require(Shared.Rewards)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local RollReveal = require(Controllers.RollReveal)
local Interface = require(UI.Interface)
local Kit = require(UI.Kit)
local Format = require(UI.Format)
local Robux = require(UI.Robux)
local UIConfig = require(UI.UIConfig)

local WheelMenu = {}

local MENU = "Wheel"
local SPIN_TIME = 4
local TURNS = 5

local wheel: ImageLabel
local spinFrame: Frame
local angles: { [number]: number } = {}
local spinning = false

local function segment(index: number): Instance?
	return wheel:FindFirstChild(tostring(index))
end

local function updateSpinButton()
	Interface.setText(spinFrame, `Spin [{State.get("Spins") or 0}]`)
end

local function setup()
	local total = RewardDefs.wheelTotalWeight()
	for index, prize in RewardDefs.Wheel do
		local folder = segment(index)
		if folder then
			local title = folder:FindFirstChild("Title")
			if title and title:IsA("TextLabel") then
				title.Text = prize.Title
			end
			local percent = folder:FindFirstChild("Percent")
			if percent and percent:IsA("TextLabel") then
				percent.Text = Format.percent(prize.Weight / total)
			end
			local icon = folder:FindFirstChild("Icon")
			if icon and icon:IsA("ImageLabel") then
				local key = if prize.Kind == "Boost" then "Boost" else prize.Kind
				Kit.setIcon(icon, UIConfig.Icons[key] or UIConfig.Icons.Clacks)
				-- Angle clockwise from the top, from where the icon sits on the wheel.
				local position = icon.Position
				local dx = position.X.Scale - 0.5
				local dy = position.Y.Scale - 0.5
				angles[index] = math.deg(math.atan2(dx, -dy))
			end
		end
	end
	updateSpinButton()
end

local function spinTo(index: number)
	local angle = angles[index] or 0
	local current = wheel.Rotation % 360
	wheel.Rotation = current
	-- Rotating by R moves a segment at angle a to a + R: land at -a, with a
	-- little jitter so it doesn't always stop dead centre.
	local jitter = (math.random() - 0.5) * 20
	local delta = (-angle - current + jitter) % 360
	local target = current + TURNS * 360 + delta

	local tween = TweenService:Create(wheel, TweenInfo.new(SPIN_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Rotation = target,
	})
	-- Ticks as segments pass the pointer.
	local lastTick = math.floor(current / 45)
	local connection = wheel:GetPropertyChangedSignal("Rotation"):Connect(function()
		local step = math.floor(wheel.Rotation / 45)
		if step ~= lastTick then
			lastTick = step
			Interface.play("Hover", 1.2)
		end
	end)
	tween:Play()
	tween.Completed:Wait()
	connection:Disconnect()
	wheel.Rotation = target % 360
end

local function spin()
	if spinning then return end
	if (State.get("Spins") or 0) < 1 then
		Interface.toast("No spins left! Get more below or from rewards.")
		return
	end
	spinning = true
	local response = State.spinWheel()
	if not response.Ok then
		spinning = false
		Interface.toastError(response)
		return
	end

	spinTo(response.Index)
	local reward = response.Reward or {}
	Interface.play("Click", 0.8)
	Interface.toast(`You won: {Format.reward(reward)}`, Color3.fromRGB(255, 230, 90))
	spinning = false

	if typeof(reward.Results) == "table" then
		RollReveal.showResults(reward.Results)
	end
end

local function bindBuy(name: string, key: string)
	local frame = wheel.Parent and wheel.Parent:FindFirstChild(name)
	if not (frame and frame:IsA("GuiObject")) then return end
	Interface.bindButton(frame, function()
		if not Robux.prompt(false, key) then
			Interface.toast("Coming soon!")
		end
	end, 0.95, 0.85)
end

function WheelMenu.start()
	Interface.setup()
	local window = Interface.Canva:WaitForChild(MENU)
	local main = window:WaitForChild("Main")
	wheel = main:WaitForChild("Wheel") :: ImageLabel
	spinFrame = main:WaitForChild("Spin") :: Frame

	Interface.bindButton(spinFrame, spin, 0.95, 0.85)
	bindBuy("Buy1", "Spins1")
	bindBuy("Buy5", "Spins5")

	Interface.MenuOpened:Connect(function(name)
		if name == MENU then
			setup()
		end
	end)
	State.Changed:Connect(function(field)
		if field == "Spins" and Interface.isOpen(MENU) then
			updateSpinButton()
		end
	end)
end

return WheelMenu
