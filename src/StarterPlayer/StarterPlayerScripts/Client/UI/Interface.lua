--[[ 

Interface
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/UI/Interface

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Shared plumbing for every UI controller: references to the HUD/Menu
-- ScreenGuis and UI assets, sounds, the kit's button feel (hover shrink +
-- click pop), menu open/close (blur, HUD slides away, canvas fade) and toasts.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)

local UIConfig = require(script.Parent.UIConfig)

local player = Players.LocalPlayer

local FAST = TweenInfo.new(0.125, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLOW = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local Interface = {}

Interface.FAST = FAST
Interface.SLOW = SLOW
Interface.MenuOpened = Signal.new() :: Signal.Signal<string>
Interface.MenuClosed = Signal.new() :: Signal.Signal<string>

-- Filled by Interface.setup()
Interface.HUD = (nil :: any) :: ScreenGui
Interface.Menu = (nil :: any) :: ScreenGui
Interface.Canva = (nil :: any) :: CanvasGroup
Interface.Templates = (nil :: any) :: Folder
Interface.SFX = (nil :: any) :: SoundGroup
Interface.Music = (nil :: any) :: SoundGroup

local ready = false
local sounds: { [string]: Sound } = {}
local currentOpen: string? = nil
local animating = false
local hudHome: { [GuiObject]: UDim2 } = {}
local blur: BlurEffect? = nil
local toastGui: ScreenGui? = nil
local toastTemplate: Frame? = nil

--------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------

local function getSoundGroup(name: string): SoundGroup
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name = name
	group.Volume = 1
	group.Parent = SoundService
	return group
end

-- Idempotent; every controller calls it at the top of start().
local settingUp = false

function Interface.setup()
	if ready then return end
	if settingUp then
		-- Another controller is mid-setup (it yields on WaitForChild): wait for it.
		while not ready do
			task.wait()
		end
		return
	end
	settingUp = true

	local playerGui = player:WaitForChild("PlayerGui")
	Interface.HUD = playerGui:WaitForChild("HUD") :: ScreenGui
	Interface.Menu = playerGui:WaitForChild("Menu") :: ScreenGui
	Interface.Canva = Interface.Menu:WaitForChild("Canva") :: CanvasGroup

	local assets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("UI")
	Interface.Templates = assets:WaitForChild("Templates") :: Folder

	Interface.SFX = getSoundGroup("SFX")
	Interface.Music = getSoundGroup("Music")

	-- Sounds play from SoundService so they're audible wherever the asset lives.
	local soundFolder = Instance.new("Folder")
	soundFolder.Name = "UISounds"
	soundFolder.Parent = SoundService
	for _, sound in assets:WaitForChild("Sounds"):GetChildren() do
		if sound:IsA("Sound") then
			local copy = sound:Clone()
			copy.SoundGroup = Interface.SFX
			copy.Parent = soundFolder
			sounds[copy.Name] = copy
		end
	end

	-- The kit's tiled stud texture overlays: shown or removed by one flag.
	local studsFlag = assets:FindFirstChild("Studs")
	local showStuds = studsFlag and studsFlag:IsA("BoolValue") and studsFlag.Value
	for _, overlay in CollectionService:GetTagged("Studs") do
		if overlay:IsA("GuiObject") and overlay:IsDescendantOf(playerGui) then
			if showStuds then
				overlay.Visible = true
			else
				overlay:Destroy()
			end
		end
	end

	Interface.Canva.Visible = false
	for _, child in Interface.Canva:GetChildren() do
		if child:IsA("Frame") then
			child.Visible = false
		end
	end

	ready = true

	-- Exit buttons on every menu window.
	for _, window in Interface.Canva:GetChildren() do
		local top = window:FindFirstChild("Top")
		local exit = top and top:FindFirstChild("Exit")
		if exit and exit:IsA("GuiObject") then
			Interface.bindButton(exit, function()
				Interface.close(window.Name)
			end)
		end
	end
end

--------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------

function Interface.play(name: string, pitch: number?)
	local sound = sounds[name]
	if not sound then return end
	sound.PlaybackSpeed = pitch or 1
	sound:Play()
end

-- Sets a kit label and its drop-shadow twin together.
function Interface.setText(parent: Instance, text: string, titleName: string?, shadowName: string?)
	local title = parent:FindFirstChild(titleName or "Title")
	local shadow = parent:FindFirstChild(shadowName or "TitleShadow")
	if title and title:IsA("TextLabel") then title.Text = text end
	if shadow and shadow:IsA("TextLabel") then shadow.Text = text end
end

function Interface.scaled(size: UDim2, factor: number): UDim2
	return UDim2.new(size.X.Scale * factor, size.X.Offset * factor, size.Y.Scale * factor, size.Y.Offset * factor)
end

export type ButtonHandle = {
	setEnabled: (enabled: boolean) -> (),
	destroy: () -> (),
}

-- Gives a kit button frame (a Frame with a transparent TextButton named
-- "Button" inside) the kit's hover shrink, click pop and sounds.
function Interface.bindButton(frame: GuiObject, onActivated: () -> (), hoverFactor: number?, pressFactor: number?): ButtonHandle
	local button = frame:FindFirstChild("Button")
	assert(button and button:IsA("GuiButton"), `{frame:GetFullName()} has no Button`)

	local hoverF = hoverFactor or 0.94
	local pressF = pressFactor or 0.85
	local hovering = false
	local enabled = true
	local connections: { RBXScriptConnection } = {}

	-- Frames sized by a layout (grid cells) can't tween Size; use a UIScale.
	local base = frame.Size
	local uiScale: UIScale? = nil
	if base == UDim2.new() then
		local existing = frame:FindFirstChildOfClass("UIScale")
		uiScale = existing or Instance.new("UIScale")
		;(uiScale :: UIScale).Parent = frame
	end

	local function tweenTo(factor: number)
		if uiScale then
			TweenService:Create(uiScale, FAST, { Scale = factor }):Play()
		else
			TweenService:Create(frame, FAST, { Size = Interface.scaled(base, factor) }):Play()
		end
	end

	table.insert(connections, button.MouseEnter:Connect(function()
		if not enabled then return end
		hovering = true
		Interface.play("Hover")
		tweenTo(hoverF)
	end))

	table.insert(connections, button.MouseLeave:Connect(function()
		hovering = false
		tweenTo(1)
	end))

	table.insert(connections, button.Activated:Connect(function()
		if not enabled then return end
		Interface.play("Click")
		tweenTo(pressF)
		task.delay(FAST.Time, function()
			tweenTo(if hovering then hoverF else 1)
		end)
		task.spawn(onActivated)
	end))

	return {
		setEnabled = function(value: boolean)
			enabled = value
			button.Active = value
			button.AutoButtonColor = false
		end,
		destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
		end,
	}
end

--------------------------------------------------------------------------
-- HUD slide in/out (ported from the kit's Shared module)
--------------------------------------------------------------------------

local function hudFrames(): { GuiObject }
	local frames: { GuiObject } = {}
	for _, folder in Interface.HUD:GetChildren() do
		if folder:IsA("Folder") then
			for _, frame in folder:GetChildren() do
				if frame:IsA("GuiObject") and frame.Visible then
					table.insert(frames, frame)
				end
			end
		end
	end
	return frames
end

local function exitPosition(frame: GuiObject): UDim2
	local camera = workspace.CurrentCamera
	local screen = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
	local pos, size = frame.AbsolutePosition, frame.AbsoluteSize
	local home = hudHome[frame] or frame.Position
	local px, py = home.X.Scale, home.Y.Scale
	if screen.X == 0 or screen.Y == 0 then
		return UDim2.new(px, 0, py + 1.5, 0)
	end
	local left, right = pos.X, screen.X - (pos.X + size.X)
	local topDist, bottom = pos.Y, screen.Y - (pos.Y + size.Y)
	local nearest = math.min(left, right, topDist, bottom)
	if nearest == left then
		return UDim2.new(px - (pos.X + size.X) / screen.X - 0.5, 0, py, 0)
	elseif nearest == right then
		return UDim2.new(px + (screen.X - pos.X) / screen.X + 0.5, 0, py, 0)
	elseif nearest == topDist then
		return UDim2.new(px, 0, py - (pos.Y + size.Y) / screen.Y - 0.5, 0)
	end
	return UDim2.new(px, 0, py + (screen.Y - pos.Y) / screen.Y + 0.5, 0)
end

local function slideHUD(show: boolean)
	for _, frame in hudFrames() do
		if not hudHome[frame] then
			hudHome[frame] = frame.Position
		end
		local target = if show then hudHome[frame] else exitPosition(frame)
		TweenService:Create(frame, if show then FAST else SLOW, { Position = target }):Play()
	end
end

local function setBlur(on: boolean)
	if not blur then
		local effect = Instance.new("BlurEffect")
		effect.Name = "MenuBlur"
		effect.Size = 0
		effect.Parent = Lighting
		blur = effect
	end
	TweenService:Create(blur :: BlurEffect, FAST, { Size = if on then UIConfig.BlurSize else 0 }):Play()
end

local function fadeCanvas(open: boolean)
	local canva = Interface.Canva
	if open then
		canva.Size = UDim2.fromScale(0.92, 0.92)
		canva.GroupTransparency = 1
		canva.Visible = true
	end
	local tween = TweenService:Create(canva, FAST, {
		Size = if open then UDim2.fromScale(1, 1) else UDim2.fromScale(0.92, 0.92),
		GroupTransparency = if open then 0 else 1,
	})
	tween:Play()
	tween.Completed:Wait()
end

--------------------------------------------------------------------------
-- Menus
--------------------------------------------------------------------------

function Interface.isOpen(name: string?): boolean
	if name then
		return currentOpen == name
	end
	return currentOpen ~= nil
end

function Interface.open(name: string)
	if currentOpen == name or animating then return end
	local window = Interface.Canva:FindFirstChild(name)
	if not (window and window:IsA("GuiObject")) then return end
	animating = true

	if currentOpen then
		local previous = Interface.Canva:FindFirstChild(currentOpen)
		local previousName = currentOpen
		currentOpen = nil
		fadeCanvas(false)
		if previous and previous:IsA("GuiObject") then previous.Visible = false end
		Interface.MenuClosed:Fire(previousName :: string)
	else
		setBlur(true)
		slideHUD(false)
	end

	Interface.Menu.Enabled = true
	window.Visible = true
	currentOpen = name
	Interface.MenuOpened:Fire(name)
	fadeCanvas(true)
	animating = false
end

-- Closes the named menu, or whichever is open when name is nil.
function Interface.close(name: string?)
	if animating or not currentOpen then return end
	if name and currentOpen ~= name then return end
	animating = true
	local closing = currentOpen :: string
	currentOpen = nil

	setBlur(false)
	slideHUD(true)
	fadeCanvas(false)

	local window = Interface.Canva:FindFirstChild(closing)
	if window and window:IsA("GuiObject") then window.Visible = false end
	Interface.Canva.Visible = false
	Interface.MenuClosed:Fire(closing)
	animating = false
end

function Interface.toggle(name: string)
	if currentOpen == name then
		Interface.close(name)
	else
		Interface.open(name)
	end
end

--------------------------------------------------------------------------
-- Toasts
--------------------------------------------------------------------------

local function ensureToasts(): (ScreenGui, Frame?)
	if toastGui then return toastGui, toastTemplate end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Toasts"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0.005, 0)
	layout.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.2, 0)
	padding.Parent = gui

	-- Same look as the HUD amount labels.
	local source = Interface.HUD:FindFirstChild("Labels")
	source = source and source:FindFirstChild("Amounts")
	source = source and source:FindFirstChild("Clacks")
	if source and source:IsA("Frame") then
		local template = source:Clone()
		template.Size = UDim2.fromScale(0.45, 0.045)
		template.Position = UDim2.new()
		toastTemplate = template
	end
	toastGui = gui
	return gui, toastTemplate
end

local toastOrder = 0

-- Short message under the top bar. color tints the text (default white).
function Interface.toast(text: string, color: Color3?)
	if text == "" then return end
	local gui, template = ensureToasts()
	if not template then
		warn("[UI]", text)
		return
	end
	toastOrder += 1
	local toast = template:Clone()
	toast.LayoutOrder = toastOrder
	Interface.setText(toast, text, "Amount", "AmountShadow")
	local amount = toast:FindFirstChild("Amount")
	if color and amount and amount:IsA("TextLabel") then
		amount.TextColor3 = color
	end
	toast.Parent = gui

	task.delay(UIConfig.Toast.Duration, function()
		local fadeInfo = TweenInfo.new(0.3)
		for _, label in toast:GetDescendants() do
			if label:IsA("TextLabel") then
				TweenService:Create(label, fadeInfo, { TextTransparency = 1 }):Play()
			elseif label:IsA("UIStroke") then
				TweenService:Create(label, fadeInfo, { Transparency = 1 }):Play()
			end
		end
		task.wait(0.3)
		toast:Destroy()
	end)
end

-- Toasts the friendly text for a failed Response (silent codes stay silent).
function Interface.toastError(response: { Ok: boolean, Error: string? })
	if response.Ok then return end
	local code = response.Error or "ServerError"
	local text = UIConfig.Errors[code]
	if text == nil then
		text = code
	end
	Interface.toast(text, Color3.fromRGB(255, 110, 110))
end

return Interface
