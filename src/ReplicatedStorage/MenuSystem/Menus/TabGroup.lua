--!strict
-- ModuleScript -> ReplicatedStorage/MenuSystem/Menus/TabGroup
--
-- One UIPageLayout and the buttons that drive it.
--
-- A Frame containing a UIPageLayout is a tab group. Its GuiObject children
-- are the pages. A button with Tab = "Stats" shows the page named "Stats".
--
-- Tabs work like the UI pack's Index tabs (UIPack "Menu Scripts.Index"): the
-- page swaps at once (no slide), and the active tab is marked by a yellow
-- "ActivatedStroke" that only it has enabled. StateStyle still applies any
-- per-tab state colours on top.

local MenuSystem = script.Parent.Parent
local Config = require(MenuSystem.Config)
local Signal = require(MenuSystem.Core.Signal)
local StateStyle = require(script.Parent.StateStyle)

local ATTR = Config.Attributes

local TabGroup = {}
TabGroup.__index = TabGroup

export type TabGroup = typeof(setmetatable({} :: {
	Container: GuiObject,
	Layout: UIPageLayout,
	Name: string,
	Current: string?,
	Buttons: { [GuiButton]: string },
	Changed: any,
}, TabGroup))

--------------------------------------------------------------------

function TabGroup.new(container: GuiObject): TabGroup?
	local layout = container:FindFirstChildOfClass("UIPageLayout")
	if not layout then return nil end

	local name = container:GetAttribute(ATTR.TabGroup)

	-- the pack swaps tab contents instantly
	layout.Animated = false

	local self = setmetatable({
		Container = container,
		Layout = layout,
		Name = type(name) == "string" and name or container.Name,
		Current = nil,
		Buttons = {},
		Changed = Signal.new(),   -- (pageName)
	}, TabGroup)

	-- UIPageLayout's events are PageEnter, PageLeave and Stopped; there is
	-- no changed event for the current page. Watching the property covers
	-- every route, including code that drives the layout directly.
	layout:GetPropertyChangedSignal("CurrentPage"):Connect(function()
		local page = layout.CurrentPage
		if page and page.Name ~= self.Current then
			self.Current = page.Name
			self:_refresh()
			self.Changed:Fire(page.Name)
		end
	end)

	return self
end

--------------------------------------------------------------------
-- PAGES
--------------------------------------------------------------------

-- A UIPageLayout only manages DIRECT children of its parent, so anything
-- deeper isn't a page however it's named.
function TabGroup:Pages(): { GuiObject }
	local pages = {}

	for _, child in ipairs(self.Container:GetChildren()) do
		if child:IsA("GuiObject") then table.insert(pages, child) end
	end

	table.sort(pages, function(a, b)
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		end
		return a.Name < b.Name
	end)

	return pages
end

-- Direct children only, matching what the layout will accept. Using
-- FindFirstChild with recursion would return a match the layout then
-- rejects with "not part of the layout".
function TabGroup:PageNamed(name: string): GuiObject?
	for _, child in ipairs(self.Container:GetChildren()) do
		if child.Name == name and child:IsA("GuiObject") then
			return child
		end
	end
	return nil
end

function TabGroup:PageNames(): { string }
	local names = {}
	for _, page in ipairs(self:Pages()) do
		table.insert(names, page.Name)
	end
	return names
end

-- Marked default, else the first page in layout order
function TabGroup:DefaultPage(): GuiObject?
	for _, page in ipairs(self:Pages()) do
		if page:GetAttribute(ATTR.TabDefault) == true then return page end
	end
	return self:Pages()[1]
end

--------------------------------------------------------------------
-- BUTTONS
--------------------------------------------------------------------

--- The pack's ActivatedStroke: a yellow outline on the active tab only.
local ACTIVE_COLOUR = Color3.fromRGB(255, 234, 0)
local function activatedStroke(button: GuiButton): UIStroke
	local existing = button:FindFirstChild("ActivatedStroke")
	if existing and existing:IsA("UIStroke") then
		return existing
	end
	local stroke = Instance.new("UIStroke")
	stroke.Name = "ActivatedStroke"
	stroke.Color = ACTIVE_COLOUR
	stroke.Thickness = 4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.Enabled = false
	stroke.Parent = button
	return stroke
end

function TabGroup:_refresh()
	for button, pageName in pairs(self.Buttons) do
		if button.Parent then
			activatedStroke(button).Enabled = pageName == self.Current
			StateStyle.Apply(button, pageName == self.Current)
		else
			self.Buttons[button] = nil
		end
	end
end

function TabGroup:AddButton(button: GuiButton, pageName: string)
	self.Buttons[button] = pageName

	-- No animation on first paint, or every tab fades in at join
	activatedStroke(button).Enabled = pageName == self.Current
	StateStyle.Initialise(button, pageName == self.Current)

	button.Destroying:Connect(function()
		self.Buttons[button] = nil
	end)
end

--------------------------------------------------------------------
-- CONTROL
--------------------------------------------------------------------

function TabGroup:Show(pageName: string, instant: boolean?)
	local page = self:PageNamed(pageName)

	if not page then
		warn(string.format("[TabGroup] '%s' has no page '%s'; it has: %s",
			self.Name, pageName, table.concat(self:PageNames(), ", ")))
		return
	end

	-- The layout rejects anything that isn't a direct child of its parent,
	-- and does it by erroring rather than returning false
	if page.Parent ~= self.Container then
		warn(string.format("[TabGroup] '%s' isn't a direct child of %s",
			pageName, self.Container:GetFullName()))
		return
	end

	-- Index rather than instance, always. JumpTo(page) rejects pages that
	-- JumpToIndex accepts in the same layout -- it matches against an
	-- internal list that doesn't always agree with the child list -- so
	-- the index is the reliable route. Animation is unaffected: instant
	-- only controls whether the tween is skipped.
	local index = table.find(self:Pages(), page)

	if not index then
		warn(("[TabGroup] '%s' isn't in %s's page list")
			:format(pageName, self.Name))
		return
	end

	-- Zero-based; table.find is one-based
	local ok, err = pcall(function()
		self.Layout:JumpToIndex(index - 1)
	end)

	if not ok then
		warn(("[TabGroup] couldn't show '%s' (index %d of %d): %s")
			:format(pageName, index, #self:Pages(), tostring(err)))
		return
	end

	-- The property change fires asynchronously, and a caller asking what's
	-- showing immediately after this should get the truth
	self.Current = pageName
	self:_refresh()
end

function TabGroup:ShowDefault()
	local page = self:DefaultPage()
	if page then self:Show(page.Name, true) end
end

function TabGroup:Destroy()
	self.Changed:DisconnectAll()
	table.clear(self.Buttons)
end

return TabGroup