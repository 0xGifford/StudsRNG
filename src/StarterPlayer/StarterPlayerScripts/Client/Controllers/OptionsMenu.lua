--[[ 

OptionsMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/OptionsMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Sound effects and music volume sliders (mouse and touch), plus the switch
-- that shows or hides other players' studs. Key clack sounds from KeyCapper
-- are routed into the SFX SoundGroup so the slider controls them too.
-- Settings last for the session.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local Interface = require(UI.Interface)
local StudFollowers = require(Controllers.StudFollowers)

local OptionsMenu = {}

local KEY_SOUND_NAME = "KeyCapperSound"

local SWITCH_ON = {
	inner = ColorSequence.new(Color3.fromRGB(255, 255, 105), Color3.fromRGB(155, 255, 105)),
	outer = ColorSequence.new(Color3.fromRGB(255, 255, 0), Color3.fromRGB(85, 255, 0)),
}
local SWITCH_OFF = {
	inner = ColorSequence.new(Color3.fromRGB(255, 105, 180), Color3.fromRGB(255, 105, 105)),
	outer = ColorSequence.new(Color3.fromRGB(255, 0, 127), Color3.fromRGB(255, 0, 0)),
}

local function routeKeySound(instance: Instance)
	if instance:IsA("Sound") and instance.Name == KEY_SOUND_NAME then
		instance.SoundGroup = Interface.SFX
	end
end

-- Slider: Fill + Press(Button, Percent) inside a frame. onChange gets 0..100.
local function bindSlider(slider: Frame, initial: number, onChange: (number) -> ())
	local fill = slider:WaitForChild("Fill") :: Frame
	local press = slider:WaitForChild("Press") :: Frame
	local button = press:WaitForChild("Button") :: GuiButton
	local percentLabel = press:WaitForChild("Percent") :: TextLabel
	local pressSize = press.Size
	local dragging = false
	local last = -1

	local function set(percent: number)
		percent = math.clamp(math.floor(percent + 0.5), 0, 100)
		fill.Size = UDim2.new(percent / 100, 0, 1, 0)
		press.Position = UDim2.new(percent / 100, 0, 0.5, 0)
		percentLabel.Text = tostring(percent)
		if percent ~= last then
			last = percent
			onChange(percent)
		end
	end

	local function fromX(x: number)
		local width = slider.AbsoluteSize.X
		if width <= 0 then return end
		set((x - slider.AbsolutePosition.X) / width * 100)
	end

	button.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = true
			Interface.play("Click")
			fromX(input.Position.X)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
			fromX(input.Position.X)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	button.MouseEnter:Connect(function()
		Interface.play("Hover")
		TweenService:Create(press, Interface.FAST, { Size = Interface.scaled(pressSize, 1.25) }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(press, Interface.FAST, { Size = pressSize }):Play()
	end)

	set(initial)
end

local function bindSwitch(switch: Frame, initial: boolean, onChange: (boolean) -> ())
	local white = switch:WaitForChild("White") :: Frame
	local inner = switch:WaitForChild("Inner")
	local innerGradient = inner:FindFirstChildOfClass("UIGradient")
	local outerGradient = switch:FindFirstChildOfClass("UIGradient")
	local on = initial

	local function apply(animate: boolean)
		local position = if on then UDim2.fromScale(0.8, 0.5) else UDim2.fromScale(0.2, 0.5)
		if animate then
			TweenService:Create(white, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Position = position }):Play()
		else
			white.Position = position
		end
		local colors = if on then SWITCH_ON else SWITCH_OFF
		if innerGradient then innerGradient.Color = colors.inner end
		if outerGradient then outerGradient.Color = colors.outer end
	end

	Interface.bindButton(switch, function()
		on = not on
		apply(true)
		onChange(on)
	end, 0.92, 0.82)

	apply(false)
	onChange(on)
end

function OptionsMenu.start()
	Interface.setup()

	-- Key clacks → SFX group (they're created client-side by KeyCapper).
	for _, instance in workspace:GetDescendants() do
		routeKeySound(instance)
	end
	workspace.DescendantAdded:Connect(routeKeySound)

	local main = Interface.Canva:WaitForChild("Options"):WaitForChild("Main")

	local sfxRow = main:FindFirstChild("Sound Effect")
	local sfxSlider = sfxRow and sfxRow:FindFirstChild("Slider")
	if sfxSlider and sfxSlider:IsA("Frame") then
		bindSlider(sfxSlider, 100, function(percent)
			Interface.SFX.Volume = percent / 100
		end)
	end

	local musicRow = main:FindFirstChild("Music")
	local musicSlider = musicRow and musicRow:FindFirstChild("Slider")
	if musicSlider and musicSlider:IsA("Frame") then
		bindSlider(musicSlider, 100, function(percent)
			Interface.Music.Volume = percent / 100
		end)
	end

	local studsRow = main:FindFirstChild("Stud Effects")
	local switch = studsRow and studsRow:FindFirstChild("Switch")
	if switch and switch:IsA("Frame") then
		bindSwitch(switch, true, function(on)
			StudFollowers.setShowOthers(on)
		end)
	end
end

return OptionsMenu
