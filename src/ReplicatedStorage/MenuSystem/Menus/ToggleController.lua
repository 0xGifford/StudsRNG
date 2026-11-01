--!strict
-- ModuleScript -> ReplicatedStorage/MenuSystem/Menus/ToggleController
--
-- Buttons that flip between two looks and stay there. The looks come from
-- the same attribute pairs everything else uses:
--
--   Toggle          = true                  on the button
--   ToggleDefault   = true                  starts toggled on
--
--   DefaultImage      = "rbxassetid://111"  off
--   DefaultHoverImage = "rbxassetid://222"  off, hovered
--   ToggledImage      = "rbxassetid://333"  on
--   ToggledHoverImage = "rbxassetid://444"  on, hovered
--
--   ToggleController.Get("MuteButton")
--   ToggleController.Set("MuteButton", false)
--   ToggleController.Changed:Connect(function(id, on) end)

local MenuSystem = script.Parent.Parent
local Config = require(MenuSystem.Config)
local ButtonBounce = require(MenuSystem.Core.ButtonBounce)
local Signal = require(MenuSystem.Core.Signal)
local StateStyle = require(script.Parent.StateStyle)
local Registry = require(script.Parent.Registry)

local ATTR = Config.Attributes

local ToggleController = {}

ToggleController.Changed = Signal.new()   -- (id, on)

local states: { [string]: boolean } = {}
local buttons: { [string]: { GuiButton } } = {}
local bound: { [GuiButton]: boolean } = {}

--------------------------------------------------------------------

-- Toggle = true means "use my own name", so a one-off toggle needs no id
-- invented for it. A string id lets two buttons drive the same state.
local function idOf(button: GuiButton): string?
	local value = button:GetAttribute(ATTR.Toggle)
	if type(value) == "string" and value ~= "" then return value end
	if value == true then return button.Name end
	return nil
end

local function paint(id: string, instant: boolean?)
	local on = states[id] == true
	local list = buttons[id]
	if not list then return end

	-- Backwards, so destroyed buttons can be removed while iterating
	for index = #list, 1, -1 do
		local button = list[index]
		if button.Parent then
			StateStyle.Apply(button, on, instant)
		else
			table.remove(list, index)
		end
	end
end

--------------------------------------------------------------------
-- PUBLIC
--------------------------------------------------------------------

function ToggleController.Get(id: string): boolean
	return states[id] == true
end

function ToggleController.Set(id: string, on: boolean, silent: boolean?)
	if states[id] == on then return end

	states[id] = on
	paint(id)

	if Config.Behaviour.Verbose then
		print(string.format("[Toggle] %s -> %s", id, tostring(on)))
	end

	if not silent then
		ToggleController.Changed:Fire(id, on)
	end
end

function ToggleController.Toggle(id: string)
	ToggleController.Set(id, not ToggleController.Get(id))
end

function ToggleController.All(): { [string]: boolean }
	return table.clone(states)
end

-- Restores saved state without firing Changed, for loading settings
function ToggleController.Restore(values: { [string]: boolean })
	for id, on in pairs(values) do
		ToggleController.Set(id, on, true)
	end
end

--------------------------------------------------------------------

function ToggleController.Bind(button: GuiButton)
	if bound[button] then return end

	local id = idOf(button)
	if not id then return end

	bound[button] = true

	buttons[id] = buttons[id] or {}
	table.insert(buttons[id], button)

	-- The first button to claim an id sets the starting state; later ones
	-- adopt it, so two buttons for one toggle can't disagree.
	if states[id] == nil then
		states[id] = button:GetAttribute(ATTR.ToggleDefault) == true
	end

	if not StateStyle.IsStyled(button) then
		warn(string.format(
			"[Toggle] '%s' has no Default/Toggled attributes, so nothing will change",
			button:GetFullName()))
	end

	-- No animation on first paint, or everything fades in at join
	StateStyle.Initialise(button, states[id])

	if button:GetAttribute(ATTR.Bounce) ~= false then
		ButtonBounce.apply(button, button:GetAttribute(ATTR.BounceHover))
	end

	button.Activated:Connect(function()
		ToggleController.Toggle(id)
	end)

	button.Destroying:Connect(function()
		bound[button] = nil
	end)
end

function ToggleController.Start()
	Registry.ButtonAdded:Connect(ToggleController.Bind)
end

return ToggleController