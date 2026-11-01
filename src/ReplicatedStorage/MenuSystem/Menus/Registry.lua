--!strict
-- ModuleScript -> ReplicatedStorage/MenuSystem/Menus/Registry
--
-- Watches PlayerGui and keeps a live index of menus and buttons. Anything
-- added at runtime is picked up without a rescan, which is what makes
-- cloned templates and dynamically built panels work.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local MenuSystem = script.Parent.Parent
local Config = require(MenuSystem.Config)
local Signal = require(MenuSystem.Core.Signal)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local ATTR = Config.Attributes
local TAGS = Config.Tags

local Registry = {}

Registry.MenuAdded = Signal.new()     -- (gui)
Registry.MenuRemoved = Signal.new()   -- (name)
Registry.ButtonAdded = Signal.new()   -- (button)

local menus: { [string]: ScreenGui } = {}
local seenButtons: { [Instance]: boolean } = {}

--------------------------------------------------------------------
-- IDENTIFICATION
--------------------------------------------------------------------

-- A ScreenGui is a menu if it's tagged, or if something inside it is
-- marked as its panel. Both, so bulk-tagging and per-instance marking work.
local function isMenu(instance: Instance): boolean
	if not instance:IsA("ScreenGui") then return false end
	if CollectionService:HasTag(instance, TAGS.Menu) then return true end

	for _, d in ipairs(instance:GetDescendants()) do
		if d:GetAttribute(ATTR.MenuPanel) == true then return true end
	end
	return false
end

-- Announced even when this module won't act on them: tabs, toggles and
-- purchases are claimed by their own controllers, which listen to the
-- same signal.
local function isButton(instance: Instance): boolean
	if not instance:IsA("GuiButton") then return false end

	return instance:GetAttribute(ATTR.Menu) ~= nil
		or instance:GetAttribute(ATTR.MenuAction) ~= nil
		or instance:GetAttribute(ATTR.Tab) ~= nil
		or instance:GetAttribute(ATTR.Toggle) ~= nil
		or instance:GetAttribute(ATTR.Gamepass) == true
		or instance:GetAttribute(ATTR.DeveloperProduct) == true
		or instance:GetAttribute(ATTR.RobloxPlus) == true
		or CollectionService:HasTag(instance, TAGS.MenuButton)
end

--------------------------------------------------------------------
-- LOOKUP
--------------------------------------------------------------------

function Registry.Get(name: string): ScreenGui?
	local gui = menus[name]
	if gui and gui.Parent then return gui end

	-- Not indexed yet: take it on faith if a ScreenGui by that name exists
	local found = playerGui:FindFirstChild(name)
	if found and found:IsA("ScreenGui") then
		menus[name] = found
		return found
	end
	return nil
end

function Registry.All(): { [string]: ScreenGui }
	return table.clone(menus)
end

function Registry.Count(): number
	local n = 0
	for _ in pairs(menus) do n += 1 end
	return n
end

function Registry.Names(): { string }
	local names = {}
	for name in pairs(menus) do table.insert(names, name) end
	table.sort(names)
	return names
end

--- Every button announced so far. A controller that starts after the first
--- scan missed those ButtonAdded fires, and seenButtons stops them being
--- announced again — so it binds these itself.
function Registry.Buttons(): { GuiButton }
	local list = {}
	for button in pairs(seenButtons) do
		if button.Parent then table.insert(list, button :: any) end
	end
	return list
end

--------------------------------------------------------------------
-- INDEXING
--------------------------------------------------------------------

local function addMenu(gui: ScreenGui)
	if menus[gui.Name] == gui then return end

	local previous = menus[gui.Name]

	-- A ResetOnSpawn clone overlaps the outgoing one for a frame, which
	-- isn't a conflict. Only warn when both are genuinely still in the tree.
	if previous and previous.Parent then
		warn(string.format(
			"[Registry] two menus named '%s'; the newer one wins", gui.Name))
	end

	menus[gui.Name] = gui
	if Config.Behaviour.Verbose then
		print("[Registry] menu: " .. gui.Name)
	end
	Registry.MenuAdded:Fire(gui)
end

local function addButton(button: GuiButton)
	if seenButtons[button] then return end
	seenButtons[button] = true

	if Config.Behaviour.Verbose then
		print("[Registry] button: " .. button:GetFullName())
	end
	Registry.ButtonAdded:Fire(button)

	button.Destroying:Connect(function()
		seenButtons[button] = nil
	end)
end

--------------------------------------------------------------------

-- Replication delivers a ScreenGui before its children, so checking a
-- freshly added ScreenGui for a panel finds nothing and the menu is missed
-- forever. Working upward from the panel covers the other order: whichever
-- arrives second registers the pair.
local function considerPanel(instance: Instance)
	if instance:GetAttribute(ATTR.MenuPanel) ~= true then return end

	local gui = instance:FindFirstAncestorWhichIsA("ScreenGui")
	if gui and gui:IsDescendantOf(playerGui) then
		addMenu(gui)
	end
end

local function consider(instance: Instance)
	if isMenu(instance) then addMenu(instance :: ScreenGui) end
	if isButton(instance) then addButton(instance :: GuiButton) end
	considerPanel(instance)
end

local function scan(root: Instance)
	consider(root)
	for _, d in ipairs(root:GetDescendants()) do
		consider(d)
	end
end

--------------------------------------------------------------------

function Registry.Start()
	scan(playerGui)

	playerGui.DescendantAdded:Connect(function(instance)
		consider(instance)

		-- Attributes are often set a frame after the instance is parented,
		-- so anything that didn't qualify gets a second look.
		task.defer(function()
			if instance.Parent then consider(instance) end
		end)
	end)

	playerGui.DescendantRemoving:Connect(function(instance)
		if instance:IsA("ScreenGui") and menus[instance.Name] == instance then
			menus[instance.Name] = nil
			Registry.MenuRemoved:Fire(instance.Name)
		end
	end)

	-- Attributes written after the tree settles: a panel marked from a
	-- script, or a button given a Menu at runtime.
	playerGui.AttributeChanged:Connect(function()
		consider(playerGui)
	end)

	-- Tagging after the fact still works
	CollectionService:GetInstanceAddedSignal(TAGS.Menu):Connect(function(instance)
		if instance:IsA("ScreenGui") and instance:IsDescendantOf(playerGui) then
			addMenu(instance)
		end
	end)

	CollectionService:GetInstanceAddedSignal(TAGS.MenuButton):Connect(function(instance)
		if instance:IsA("GuiButton") and instance:IsDescendantOf(playerGui) then
			addButton(instance)
		end
	end)

	-- StarterGui replicates over several frames, so a single scan at
	-- startup sees an empty PlayerGui on a cold join. A few passes costs
	-- nothing and removes the race entirely.
	task.spawn(function()
		for _ = 1, 5 do
			task.wait(0.2)
			scan(playerGui)
		end
	end)
end

return Registry