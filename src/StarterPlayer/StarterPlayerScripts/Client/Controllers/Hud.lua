--[[ 

Hud
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/Hud

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The always-on HUD: Studs / Roll / Auto buttons, the free-roll meter under
-- Roll, Clacks + multiplier labels and the side menu buttons. Renders State;
-- every action goes through RollReveal or a menu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local RollReveal = require(Controllers.RollReveal)
local Interface = require(UI.Interface)
local Format = require(UI.Format)
local UIConfig = require(UI.UIConfig)

local Hud = {}

local rollFrame: Frame
local autoFrame: Frame
local meter: Frame
local meterBar: Frame
local clacksFrame: Frame
local multiplierFrame: Frame

-- Count-up display for Clacks.
local shownClacks = Instance.new("NumberValue")
local clacksTween: Tween? = nil

local function hideDisabledFeatures()
	local features = UIConfig.Features
	local side = Interface.HUD:FindFirstChild("Side")
	local buttons = side and side:FindFirstChild("Buttons")
	if buttons then
		for _, name in { "Store", "Rebirth", "Rewards", "Wheel" } do
			local frame = buttons:FindFirstChild(name)
			if frame and frame:IsA("GuiObject") then
				frame.Visible = (features :: any)[name] == true
			end
		end
	end

	local labels = Interface.HUD:FindFirstChild("Labels")
	local boosts = labels and labels:FindFirstChild("Boosts")
	if boosts and boosts:IsA("GuiObject") then
		boosts.Visible = features.Boosts
	end

	local events = Interface.HUD:FindFirstChild("Events")
	if events then
		for _, frame in events:GetChildren() do
			if frame:IsA("GuiObject") then
				frame.Visible = features.Events
			end
		end
	end
end

local function updateRollButton()
	local free = State.get("FreeRolls") or 0
	if free > 0 then
		Interface.setText(rollFrame, `Free Roll ({free})`)
	else
		Interface.setText(rollFrame, `Roll · {Format.number(Config.Rolls.ClackCost)}`)
	end
end

local function updateMeter()
	local perRoll = Config.Economy.PressesPerFreeRoll
	local value = State.get("RollMeter") or 0
	local free = State.get("FreeRolls") or 0
	local fraction = math.clamp(value / perRoll, 0, 1)
	local text = if free >= Config.Economy.MaxBankedFreeRolls then "Bank full" else `{value}/{perRoll}`
	Interface.setText(meter, text, "Amount", "AmountShadow")
	TweenService:Create(meterBar, Interface.FAST, { Size = UDim2.fromScale(fraction, 1) }):Play()
end

local function renderClacks(value: number)
	Interface.setText(clacksFrame, `{Format.number(value)} Clacks`, "Amount", "AmountShadow")
end

local function updateClacks()
	local target = State.get("Clacks") or 0
	if clacksTween then clacksTween:Cancel() end
	clacksTween = TweenService:Create(shownClacks, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Value = target })
	;(clacksTween :: Tween):Play()
end

local function updateMultiplier()
	Interface.setText(multiplierFrame, `{Format.multiplier(State.stats().ClackMultiplier)} Clacks`, "Amount", "AmountShadow")
end

local function updateAuto(on: boolean)
	Interface.setText(autoFrame, if on then "Auto: On" else "Auto: Off")
end

function Hud.start()
	Interface.setup()

	local top = Interface.HUD:WaitForChild("Top"):WaitForChild("Frame")
	local studsFrame = top:WaitForChild("Studs") :: Frame
	rollFrame = top:WaitForChild("Roll") :: Frame
	autoFrame = top:WaitForChild("Auto") :: Frame
	meter = rollFrame:WaitForChild("Meter") :: Frame
	meterBar = meter:WaitForChild("Bar") :: Frame

	local amounts = Interface.HUD:WaitForChild("Labels"):WaitForChild("Amounts")
	clacksFrame = amounts:WaitForChild("Clacks") :: Frame
	multiplierFrame = amounts:WaitForChild("Multiplier") :: Frame

	hideDisabledFeatures()

	Interface.bindButton(studsFrame, function()
		Interface.toggle("Studs")
	end)
	Interface.bindButton(rollFrame, function()
		RollReveal.roll(false)
	end)
	Interface.bindButton(autoFrame, function()
		RollReveal.setAuto(not RollReveal.isAuto())
	end)

	-- Side buttons open the menu of the same name.
	local buttons = Interface.HUD:WaitForChild("Side"):WaitForChild("Buttons")
	for _, frame in buttons:GetChildren() do
		if frame:IsA("Frame") and frame:FindFirstChild("Button") then
			local name = frame.Name
			Interface.bindButton(frame, function()
				Interface.toggle(name)
			end, 0.9, 0.8)
		end
	end

	shownClacks.Changed:Connect(renderClacks)
	RollReveal.AutoChanged:Connect(updateAuto)
	updateAuto(RollReveal.isAuto())

	local function renderAll()
		shownClacks.Value = State.get("Clacks") or 0
		renderClacks(shownClacks.Value)
		updateRollButton()
		updateMeter()
		updateMultiplier()
	end

	State.Changed:Connect(function(field)
		if field == "Clacks" then
			updateClacks()
			updateRollButton()
		elseif field == "FreeRolls" then
			updateRollButton()
			updateMeter()
		elseif field == "RollMeter" then
			updateMeter()
		elseif field == "Equipped" or field == "Index" or field == "Studs" then
			updateMultiplier()
		end
	end)

	if State.isReady() then
		renderAll()
	else
		State.Ready:Connect(renderAll)
	end
end

return Hud
