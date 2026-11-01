--!strict
-- ModuleScript -> ReplicatedStorage/MenuSystem/Menus/ButtonBinder
--
-- Reads the attributes off a button and does what they say. Buttons added
-- later are bound automatically, so cloned templates need no extra call.
--
--   Menu = "ShopMenu"        toggles that menu
--   MenuAction = "close"     with no Menu, targets the menu it lives in
--   Tab = "Eggs"             belongs to TabController, ignored here
--   Toggle = true            belongs to ToggleController, ignored here
--   Gamepass = true          belongs to PurchaseController, ignored here
--   Bounce = false           opt out of hover and press scaling

local CollectionService = game:GetService("CollectionService")

local ButtonBounce = require(script.Parent.Parent.Core.ButtonBounce)
local Config = require(script.Parent.Parent.Config)
local MenuController = require(script.Parent.MenuController)
local Registry = require(script.Parent.Registry)

local ATTR = Config.Attributes
local TAGS = Config.Tags

local ButtonBinder = {}

local bound: { [GuiButton]: RBXScriptConnection } = {}

--------------------------------------------------------------------
-- TARGETING
--------------------------------------------------------------------

-- The menu a button targets. Falls back to the ScreenGui it lives in,
-- which is what lets a close button work with no target named at all.
local function targetOf(button: GuiButton): string?
	local explicit = button:GetAttribute(ATTR.Menu)
	if type(explicit) == "string" and explicit ~= "" then return explicit end

	local gui = button:FindFirstAncestorWhichIsA("ScreenGui")
	return gui and gui.Name or nil
end

local ACTIONS: { [string]: (string?) -> () } = {
	open = function(target)
		if target then MenuController.Open(target) end
	end,
	close = function(target)
		if target then MenuController.Close(target) end
	end,
	toggle = function(target)
		if target then MenuController.Toggle(target) end
	end,
	closeall = function()
		MenuController.CloseAll()
	end,
}

local function activate(button: GuiButton)
	local action = button:GetAttribute(ATTR.MenuAction)
	local name = type(action) == "string" and action:lower() or "toggle"

	local handler = ACTIONS[name]
	if not handler then
		warn(string.format("[ButtonBinder] '%s' has unknown %s '%s'",
			button.Name, ATTR.MenuAction, tostring(action)))
		return
	end

	handler(targetOf(button))
end

--------------------------------------------------------------------
-- OWNERSHIP
--------------------------------------------------------------------

-- Registry announces tab and toggle buttons so their controllers find
-- them, which means they arrive here too. Binding one would toggle the
-- enclosing menu on the same click that switches the page or flips the
-- switch, closing the panel you're using.
--
-- A button carrying both a Tab or Toggle AND an explicit Menu or
-- MenuAction keeps both behaviours, since "open the shop on the Eggs tab"
-- is a reasonable thing to want from a HUD button.
local function isOwnedElsewhere(button: GuiButton): boolean
	local claimed = button:GetAttribute(ATTR.Tab) ~= nil
		or button:GetAttribute(ATTR.Toggle) ~= nil
		or button:GetAttribute(ATTR.Gamepass) == true
		or button:GetAttribute(ATTR.DeveloperProduct) == true
		or button:GetAttribute(ATTR.RobloxPlus) == true

	if not claimed then return false end

	return button:GetAttribute(ATTR.Menu) == nil
		and button:GetAttribute(ATTR.MenuAction) == nil
end

--------------------------------------------------------------------

function ButtonBinder.Bind(button: GuiButton)
	if bound[button] then return end

	if isOwnedElsewhere(button) then
		-- Its own controller handles the bounce and the click
		if Config.Behaviour.Verbose then
			print("[ButtonBinder] skipped " .. button.Name .. ", owned elsewhere")
		end
		return
	end

	-- Bounce is opt-out, since a button you can't press back is rare
	if button:GetAttribute(ATTR.Bounce) ~= false then
		ButtonBounce.apply(button, button:GetAttribute(ATTR.BounceHover))
	end

	bound[button] = button.Activated:Connect(function()
		activate(button)
	end)

	if Config.Behaviour.Verbose then
		print(string.format("[ButtonBinder] %s -> %s (%s)",
			button.Name,
			tostring(targetOf(button)),
			tostring(button:GetAttribute(ATTR.MenuAction) or "toggle")))
	end

	button.Destroying:Connect(function()
		local connection = bound[button]
		if connection then connection:Disconnect() end
		bound[button] = nil
	end)
end

-- Releases a button so something else can own its click
function ButtonBinder.Unbind(button: GuiButton)
	local connection = bound[button]
	if connection then
		connection:Disconnect()
		bound[button] = nil
	end
end

function ButtonBinder.IsBound(button: GuiButton): boolean
	return bound[button] ~= nil
end

--------------------------------------------------------------------

function ButtonBinder.Start()
	Registry.ButtonAdded:Connect(ButtonBinder.Bind)

	-- Registry starts earlier in the boot order and its first scan announces
	-- every button already in PlayerGui (a live join has the whole HUD there)
	-- before this module is listening. Bind those too; Bind skips repeats.
	for _, button in ipairs(Registry.Buttons()) do
		ButtonBinder.Bind(button)
	end

	-- Bounce-only, no menu behaviour
	local function applyBounce(instance: Instance)
		if instance:IsA("GuiButton") then ButtonBounce.apply(instance) end
	end

	for _, instance in ipairs(CollectionService:GetTagged(TAGS.Bounce)) do
		applyBounce(instance)
	end

	CollectionService:GetInstanceAddedSignal(TAGS.Bounce):Connect(applyBounce)
end

return ButtonBinder