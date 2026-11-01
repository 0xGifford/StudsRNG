--!strict
-- ModuleScript -> ReplicatedStorage/MenuSystem/Menus/TabController
--
-- Finds tab groups and wires tab buttons to them.
--
-- Buttons rarely sit inside the thing they control: a tab strip is usually
-- a sibling of the pages, not an ancestor. And a menu can contain SEVERAL
-- UIPageLayouts -- a shop with page tabs and a detail panel switcher has
-- two -- so "nearest layout" isn't enough to identify the right one.
--
-- Resolution therefore prefers the group that actually has a page matching
-- the button's Tab value, and only falls back to proximity when nothing
-- matches. An explicit TabGroup attribute always wins.
--
--   TabController.Show("Pages", "Eggs")
--   TabController.Current("Pages")
--   TabController.Changed:Connect(function(group, page) end)

local MenuSystem = script.Parent.Parent
local Config = require(MenuSystem.Config)
local ButtonBounce = require(MenuSystem.Core.ButtonBounce)
local Signal = require(MenuSystem.Core.Signal)
local StateStyle = require(script.Parent.StateStyle)
local TabGroup = require(script.Parent.TabGroup)
local MenuController = require(script.Parent.MenuController)
local Registry = require(script.Parent.Registry)

local ATTR = Config.Attributes

local TabController = {}

TabController.Changed = Signal.new()   -- (groupName, pageName)

local groups: { [GuiObject]: TabGroup.TabGroup } = {}
local byName: { [string]: TabGroup.TabGroup } = {}
local boundButtons: { [GuiButton]: boolean } = {}

--------------------------------------------------------------------

local function register(container: GuiObject): TabGroup.TabGroup?
	local existing = groups[container]
	if existing then return existing end

	local group = TabGroup.new(container)
	if not group then return nil end

	groups[container] = group

	-- "Left" repeats across every page of a shop, so a bare container name
	-- collides constantly. A clash gets qualified with its parent rather
	-- than warned about: Limited/Left and Coins/Left are both addressable,
	-- and neither silently overwrites the other.
	if byName[group.Name] and byName[group.Name] ~= group then
		local parent = container.Parent
		local qualified = parent and (parent.Name .. "/" .. group.Name) or group.Name

		if byName[qualified] then
			qualified = container:GetFullName()
		end

		if Config.Behaviour.Verbose then
			print(("[Tabs] '%s' was taken; this one is '%s'")
				:format(group.Name, qualified))
		end

		group.Name = qualified
	end

	byName[group.Name] = group

	group.Changed:Connect(function(pageName)
		TabController.Changed:Fire(group.Name, pageName)
	end)

	group:ShowDefault()

	if Config.Behaviour.Verbose then
		local names = {}
		for _, page in ipairs(group:Pages()) do
			table.insert(names, page.Name)
		end

		print(string.format("[Tabs] group '%s' at %s: %s",
			group.Name, container:GetFullName(), table.concat(names, ", ")))
	end

	return group
end

-- Every group anywhere in this subtree, registering as it goes
local function groupsWithin(root: Instance): { TabGroup.TabGroup }
	local found = {}

	local function consider(instance: Instance)
		if not instance:IsA("GuiObject") then return end

		local existing = groups[instance]
		if existing then
			table.insert(found, existing)
			return
		end

		if instance:FindFirstChildOfClass("UIPageLayout") then
			local group = register(instance)
			if group then table.insert(found, group) end
		end
	end

	consider(root)
	for _, d in ipairs(root:GetDescendants()) do
		consider(d)
	end

	return found
end

-- Walk up from the button. At each level, take any group that has a page
-- by the wanted name; a menu with two layouts is otherwise a coin flip.
-- Nothing matching by name falls back to the first group found, which is
-- what a single-layout menu has always done.
local function groupFor(button: GuiButton, pageName: string): TabGroup.TabGroup?
	local named = button:GetAttribute(ATTR.TabGroup)
	if type(named) == "string" then
		local group = byName[named]
		if group then return group end

		warn(string.format("[Tabs] %s wants group '%s', which doesn't exist",
			button:GetFullName(), named))
	end

	local ancestor: Instance? = button.Parent
	local fallback: TabGroup.TabGroup? = nil

	while ancestor do
		local candidates = groupsWithin(ancestor)

		for _, group in ipairs(candidates) do
			if group:PageNamed(pageName) then
				return group
			end
		end

		if not fallback and #candidates > 0 then
			fallback = candidates[1]
		end

		-- Don't climb out of the menu into PlayerGui and grab a group
		-- belonging to some other panel
		if ancestor:IsA("ScreenGui") then break end
		ancestor = ancestor.Parent
	end

	return fallback
end

--------------------------------------------------------------------

local function bindButton(button: GuiButton)
	if boundButtons[button] then return end

	local pageName = button:GetAttribute(ATTR.Tab)
	if type(pageName) ~= "string" or pageName == "" then return end

	local group = groupFor(button, pageName)

	if not group then
		warn(string.format(
			"[Tabs] '%s' targets page '%s' but no UIPageLayout was found near it",
			button:GetFullName(), pageName))
		return
	end

	if not group:PageNamed(pageName) then
		-- Resolved by proximity to a group that doesn't have this page.
		-- Naming both sides turns a silent dead button into an obvious
		-- mismatch.
		local names = {}
		for _, page in ipairs(group:Pages()) do
			table.insert(names, page.Name)
		end

		warn(string.format(
			"[Tabs] '%s' wants page '%s', but group '%s' only has: %s",
			button:GetFullName(), pageName, group.Name,
			#names > 0 and table.concat(names, ", ") or "nothing"))
		return
	end

	boundButtons[button] = true
	group:AddButton(button, pageName)

	if button:GetAttribute(ATTR.Bounce) ~= false then
		ButtonBounce.apply(button)
	end

	button.Activated:Connect(function()
		group:Show(pageName)
	end)

	button.Destroying:Connect(function()
		boundButtons[button] = nil
	end)
end

--------------------------------------------------------------------
-- PUBLIC
--------------------------------------------------------------------

function TabController.Show(groupName: string, pageName: string)
	local group = byName[groupName]
	if group then
		group:Show(pageName)
	else
		warn("[Tabs] no group named '" .. groupName .. "'")
	end
end

function TabController.Current(groupName: string): string?
	local group = byName[groupName]
	return group and group.Current or nil
end

function TabController.Group(groupName: string): TabGroup.TabGroup?
	return byName[groupName]
end

function TabController.GroupNames(): { string }
	local names = {}
	for name in pairs(byName) do table.insert(names, name) end
	table.sort(names)
	return names
end

-- Every group and its pages, for working out a mismatch
function TabController.Describe()
	print("[Tabs] groups:")

	for name, group in pairs(byName) do
		local names = {}
		for _, page in ipairs(group:Pages()) do
			table.insert(names, page.Name)
		end

		print(string.format("    %-14s %s", name, group.Container:GetFullName()))
		print(string.format("        showing %s of: %s",
			tostring(group.Current), table.concat(names, ", ")))
	end
end

--------------------------------------------------------------------

local function scan(root: Instance)
	-- Groups first, so every button has something to match against
	groupsWithin(root)

	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("GuiButton") and d:GetAttribute(ATTR.Tab) ~= nil then
			bindButton(d)
		end
	end
end

function TabController.Start()
	for _, gui in pairs(Registry.All()) do
		scan(gui)
	end

	Registry.MenuAdded:Connect(scan)
	Registry.ButtonAdded:Connect(bindButton)

	-- A menu reopening shows its default tab rather than wherever the
	-- player left it, unless it's marked to remember
	MenuController.Opened:Connect(function(name)
		local gui = Registry.Get(name)
		if not gui then return end
		if gui:GetAttribute(ATTR.TabRemember) == true then return end

		for container, group in pairs(groups) do
			if container:IsDescendantOf(gui) then
				group:ShowDefault()
			end
		end
	end)

	-- Styled buttons that belong to nobody still want their resting look.
	-- Toggles and tabs are excluded: their own controllers own the state,
	-- and painting one here installs a second hover watcher.
	Registry.ButtonAdded:Connect(function(button)
		local claimed = button:GetAttribute(ATTR.Tab) ~= nil
			or button:GetAttribute(ATTR.Toggle) ~= nil

		if not claimed and StateStyle.IsStyled(button) then
			StateStyle.Initialise(button, StateStyle.IsActive(button))
		end
	end)
end

return TabController