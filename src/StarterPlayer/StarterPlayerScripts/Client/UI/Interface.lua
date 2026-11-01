--[[ 

Interface
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/UI/Interface

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Shared plumbing for every UI controller: references to the HUD ScreenGui
-- and UI assets, sounds, the kit's button feel (hover shrink + click pop),
-- menus and toasts.
--
-- Menus are MenuSystem menus (ReplicatedStorage.MenuSystem): each is its own
-- ScreenGui (tagged "Menu", its window marked MenuPanel = true), opened and
-- closed by MenuController with the kit's blur, scale-in and HUD slide
-- (PackShared, HudSlide). Interface.open / close / toggle / isOpen and the
-- MenuOpened / MenuClosed signals are a thin layer over MenuController, plus
-- "custom" menus that run their own gui (Interface.registerMenu, e.g. the
-- upgrade tree). Only one menu of either kind is open at a time.
--
-- Buttons open menus by attribute, MenuSystem style: a GuiButton (for a kit
-- button, its "Button") with Menu = "Store" toggles it; MenuAction = "open" /
-- "close" / "closeAll" (MenuSystem's ButtonBinder). A ScreenGui's Backdrop =
-- false skips the blur, KeepHud = true leaves the HUD in place.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)

local MenuSystem = ReplicatedStorage:WaitForChild("MenuSystem")
local MenuController = require(MenuSystem.Menus.MenuController)

local UIConfig = require(script.Parent.UIConfig)
local Roles = require(script.Parent.Roles)

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
Interface.Templates = (nil :: any) :: Instance -- StarterGui.Templates
Interface.SFX = (nil :: any) :: SoundGroup
Interface.Music = (nil :: any) :: SoundGroup

local ready = false
local sounds: { [string]: Sound } = {}
local toastGui: ScreenGui? = nil

export type CustomMenu = {
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
}
local customMenus: { [string]: CustomMenu } = {}

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

-- Yields until the ReplicatedFirst loading screen is gone (it marks the
-- LocalPlayer LoadingScreen / LoadingScreenDone), or `timeout` seconds.
-- Returns at once when there is no loading screen.
function Interface.waitForLoadingScreen(timeout: number?)
	local deadline = os.clock() + (timeout or 40)
	while player:GetAttribute("LoadingScreen") == true and player:GetAttribute("LoadingScreenDone") ~= true do
		if os.clock() > deadline then return end
		task.wait(0.1)
	end
end

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

	local assets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("UI")
	-- Reusable pieces live in StarterGui.Templates (a disabled ScreenGui);
	-- older places still have them in ReplicatedStorage.Assets.UI.Templates.
	local templates = playerGui:WaitForChild("Templates", 10) or assets:WaitForChild("Templates")
	Interface.Templates = templates :: any

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

	-- MenuController's menus are Interface's menus.
	MenuController.Opened:Connect(function(name: string)
		Interface.MenuOpened:Fire(name)
	end)
	MenuController.Closed:Connect(function(name: string)
		Interface.MenuClosed:Fire(name)
	end)

	ready = true
end

-- A menu's window (its MenuPanel frame), e.g. Interface.window("Store").
-- Yields until it has replicated.
function Interface.window(name: string): GuiObject
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(name)
	while true do
		for _, descendant in gui:GetDescendants() do
			if descendant:GetAttribute("MenuPanel") == true and descendant:IsA("GuiObject") then
				return descendant
			end
		end
		task.wait(0.1)
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
-- Menus
--------------------------------------------------------------------------

-- A menu that runs its own gui instead of being a MenuSystem menu.
function Interface.registerMenu(name: string, menu: CustomMenu)
	customMenus[name] = menu
end

local function closeCustomMenus(except: string?)
	for name, menu in customMenus do
		if name ~= except and menu.isOpen() then
			menu.close()
			Interface.MenuClosed:Fire(name)
		end
	end
end

local function customOpen(): boolean
	for _, menu in customMenus do
		if menu.isOpen() then
			return true
		end
	end
	return false
end

function Interface.isOpen(name: string?): boolean
	if name then
		local menu = customMenus[name]
		if menu then
			return menu.isOpen()
		end
		return MenuController.IsOpen(name)
	end
	return #MenuController.OpenMenus() > 0 or customOpen()
end

function Interface.open(name: string)
	local custom = customMenus[name]
	if custom then
		if custom.isOpen() then return end
		MenuController.CloseAll()
		closeCustomMenus(name)
		custom.open()
		Interface.MenuOpened:Fire(name)
		return
	end
	closeCustomMenus(nil)
	MenuController.Open(name)
end

-- Closes the named menu, or every open one when name is nil.
function Interface.close(name: string?)
	if name and customMenus[name] then
		local custom = customMenus[name]
		if custom.isOpen() then
			custom.close()
			Interface.MenuClosed:Fire(name)
		end
		return
	end
	if not name then
		closeCustomMenus(nil)
		MenuController.CloseAll()
		return
	end
	MenuController.Close(name)
end

function Interface.toggle(name: string)
	if Interface.isOpen(name) then
		Interface.close(name)
	else
		Interface.open(name)
	end
end

-- Runs a Menu / MenuAction pair (as set on a MenuTrigger part).
function Interface.runMenuAction(menu: string, action: string?)
	local verb = if action then string.lower(action) else "toggle"
	if verb == "open" then
		Interface.open(menu)
	elseif verb == "close" or verb == "closeall" then
		Interface.close(if menu == "" or verb == "closeall" then nil else menu)
	else
		Interface.toggle(menu)
	end
end

--------------------------------------------------------------------------
-- Toasts
--------------------------------------------------------------------------

-- StarterGui.Toasts (tools/ui/screens/Toasts.luau): its UIListLayout stacks
-- copies of its "Toast" template.
local function ensureToasts(): ScreenGui
	if toastGui then return toastGui end
	local gui = Roles.gui("Toasts")
	toastGui = gui
	return gui
end

local toastOrder = 0

-- Short message under the top bar. color tints the text (default white).
function Interface.toast(text: string, color: Color3?)
	if text == "" then return end
	local gui = ensureToasts()
	toastOrder += 1
	local toast = Roles.template(gui, "Toast")
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
