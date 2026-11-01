--!strict
-- ModuleScript -> ReplicatedStorage/MenuSystem/Menus/MenuController
--
-- The public face. Holds open/closed state across every menu and decides
-- what exclusivity means.
--
--   MenuController.Toggle("ShopMenu")
--   MenuController.Open("ShopMenu")
--   MenuController.Close("ShopMenu")
--   MenuController.CloseAll()
--   MenuController.IsOpen("ShopMenu")
--   MenuController.OpenMenus()            -- oldest first
--   MenuController.Newest()
--
--   MenuController.Opened:Connect(function(name) end)
--   MenuController.Closed:Connect(function(name) end)

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local MenuSystem = script.Parent.Parent
local Config = require(MenuSystem.Config)
local Signal = require(MenuSystem.Core.Signal)
local Menu = require(script.Parent.Menu)
local Focus = require(script.Parent.Focus)
local Registry = require(script.Parent.Registry)

local MenuController = {}

MenuController.Opened = Signal.new()   -- (name)
MenuController.Closed = Signal.new()   -- (name)

local instances: { [string]: Menu.Menu } = {}
local openOrder: { string } = {}       -- oldest first, so Escape takes the newest

--------------------------------------------------------------------

local function bind(gui: ScreenGui): Menu.Menu?
	local existing = instances[gui.Name]
	if existing and existing.Gui == gui then return existing end
	if existing then existing:Destroy() end

	local menu = Menu.new(gui)
	if menu then instances[gui.Name] = menu end
	return menu
end

local function get(name: string): Menu.Menu?
	local existing = instances[name]
	if existing and existing.Gui.Parent then return existing end

	local gui = Registry.Get(name)
	if gui then return bind(gui) end

	if Config.Behaviour.WarnOnMissingMenu then
		warn("[MenuController] no menu named '" .. name .. "'")
	end
	return nil
end

local function remember(name: string)
	local index = table.find(openOrder, name)
	if index then table.remove(openOrder, index) end
	table.insert(openOrder, name)
end

local function forget(name: string)
	local index = table.find(openOrder, name)
	if index then table.remove(openOrder, index) end
end

-- Gamepad B closes the newest menu, bound only while a menu is open so
-- gameplay keeps the button the rest of the time.
local BACK_ACTION = "MenuSystemBack"
local backBound = false

local function syncBack()
	local want = #openOrder > 0
	if want == backBound then return end
	backBound = want
	if want then
		ContextActionService:BindActionAtPriority(BACK_ACTION, function(_, state)
			if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
			local newest = openOrder[#openOrder]
			if not newest then return Enum.ContextActionResult.Pass end
			MenuController.Close(newest)
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.ButtonB)
	else
		ContextActionService:UnbindAction(BACK_ACTION)
	end
end

--------------------------------------------------------------------
-- QUERIES
--------------------------------------------------------------------

function MenuController.IsOpen(name: string): boolean
	local menu = instances[name]
	return menu ~= nil and menu.IsOpen
end

function MenuController.OpenMenus(): { string }
	return table.clone(openOrder)
end

function MenuController.Newest(): string?
	return openOrder[#openOrder]
end

function MenuController.Get(name: string): Menu.Menu?
	return instances[name]
end

--------------------------------------------------------------------
-- CONTROL
--------------------------------------------------------------------

function MenuController.Close(name: string)
	local menu = instances[name]
	if not menu or not menu.IsOpen then return end

	menu:Close()
	Focus.Leave(menu.Panel)
	forget(name)
	syncBack()

	-- focus falls back to the menu underneath, if one is still open
	local newest = openOrder[#openOrder]
	local below = newest and instances[newest]
	if below and below.IsOpen then Focus.Select(below.Panel) end

	if Config.Behaviour.Verbose then print("[Menu] closed " .. name) end
	MenuController.Closed:Fire(name)
end

function MenuController.CloseAll(except: string?)
	for _, name in ipairs(table.clone(openOrder)) do
		if name ~= except then MenuController.Close(name) end
	end
end

function MenuController.Open(name: string)
	local menu = get(name)
	if not menu or menu.IsOpen then return end

	-- Exclusivity is the incoming menu's call, not a global rule: a
	-- non-exclusive panel can sit alongside whatever is already open.
	if menu:IsExclusive() then
		MenuController.CloseAll(name)
	end

	menu:Open()
	remember(name)
	Focus.Enter(menu.Panel)
	syncBack()

	if Config.Behaviour.Verbose then print("[Menu] opened " .. name) end

	-- Fired after Enabled flips, so listeners can measure or populate
	MenuController.Opened:Fire(name)
end

function MenuController.Toggle(name: string)
	if MenuController.IsOpen(name) then
		MenuController.Close(name)
	else
		MenuController.Open(name)
	end
end

--------------------------------------------------------------------

function MenuController.Start()
	for _, gui in pairs(Registry.All()) do
		bind(gui)
	end

	Registry.MenuAdded:Connect(bind)

	Registry.MenuRemoved:Connect(function(name)
		local menu = instances[name]
		if menu then menu:Destroy() end
		instances[name] = nil
		forget(name)
	end)

	-- Picking up a controller with a menu open: give it something to focus.
	pcall(function()
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
			local newest = openOrder[#openOrder]
			local menu = newest and instances[newest]
			if menu and menu.IsOpen then Focus.Select(menu.Panel) end
		end)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end

		-- Escape closes the most recent, so nested panels unwind in order
		if Config.Behaviour.CloseOnEscape and input.KeyCode == Enum.KeyCode.Escape then
			local newest = MenuController.Newest()
			if newest then
				MenuController.Close(newest)
				return
			end
		end

		for name, menu in pairs(instances) do
			if menu:HotKey() == input.KeyCode then
				MenuController.Toggle(name)
				break
			end
		end
	end)
end

return MenuController