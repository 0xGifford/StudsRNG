--!strict
-- ModuleScript -> ReplicatedStorage/MenuSystem/Menus/StateStyle
--
-- Two-state styling with optional hover variants. Nothing here knows about
-- tabs or toggles; it's equally useful for a selected inventory slot.
--
-- NAMED TARGETS are the normal way to style something. Each is a child
-- name plus a property, declared in Config.State.Targets, so authoring is
-- a colour rather than a property path:
--
--   ActiveBackground   InactiveBackground
--   ActiveStroke       InactiveStroke
--   ActiveShadow       InactiveShadow
--   ActiveText         InactiveText
--   ActiveIcon         InactiveIcon
--
-- Each takes a Hover variant too, laid over the base:
--
--   ActiveHoverStroke  InactiveHoverBackground
--
-- PRESETS save repeating the same six colours on every tab in the game:
--
--   StatePreset = "Tab"
--
-- Per-instance attributes override the preset, so one odd button can
-- differ without leaving the preset.
--
-- RAW PROPERTIES still work for anything the targets don't cover. Any
-- suffix that isn't a target name is treated as a property and resolved
-- against whatever instance actually has it:
--
--   ActiveImage        ActiveBackgroundTransparency

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MenuSystem = script.Parent.Parent
local Config = require(MenuSystem.Config)

local ATTR = Config.Attributes
local STATE = Config.State

-- Touch devices fire MouseEnter on tap, which would leave a button stuck
-- in its hover look after the finger lifts.
local TOUCH_ONLY = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

-- Types that can be tweened. Anything else is assigned outright, so a
-- string Image doesn't silently fail to animate.
local TWEENABLE = {
	Color3 = true,
	number = true,
	UDim2 = true,
	UDim = true,
	Vector2 = true,
}

local StateStyle = {}

local hovering: { [GuiObject]: boolean } = {}
local watched: { [GuiObject]: boolean } = {}

--------------------------------------------------------------------
-- PARSING
--------------------------------------------------------------------

-- Splits "ActiveHoverStroke" into state "Active", hover true, name
-- "Stroke". Returns nil for attributes that aren't state declarations.
local function parse(key: string): (string?, boolean?, string?)
	local function split(prefix: string, canonical: string): (string?, boolean?, string?)
		if key:sub(1, #prefix) ~= prefix or #key <= #prefix then
			return nil, nil, nil
		end

		local rest = key:sub(#prefix + 1)
		local infix = STATE.HoverInfix

		if rest:sub(1, #infix) == infix and #rest > #infix then
			return canonical, true, rest:sub(#infix + 1)
		end
		return canonical, false, rest
	end

	for alias, canonical in pairs(STATE.Aliases) do
		local state, hover, name = split(alias, canonical)
		if state then return state, hover, name end
	end

	for _, state in ipairs(STATE.States) do
		local found, hover, name = split(state, state)
		if found then return found, hover, name end
	end

	return nil, nil, nil
end

--------------------------------------------------------------------
-- RESOLVING VALUES
--------------------------------------------------------------------

-- Preset first, then the instance's own attributes over the top, so one
-- button can differ from its preset without abandoning it.
local function declarations(instance: GuiObject)
	local out = {
		Active = { [false] = {}, [true] = {} },
		Inactive = { [false] = {}, [true] = {} },
	}

	local presetName = instance:GetAttribute(ATTR.StatePreset)
	if type(presetName) == "string" then
		local preset = STATE.Presets[presetName]

		if preset then
			for key, value in pairs(preset) do
				local state, hover, name = parse(key)
				if state and name and name ~= "" then
					out[state][hover == true][name] = value
				end
			end
		else
			warn(string.format("[StateStyle] %s wants unknown preset '%s'",
				instance:GetFullName(), presetName))
		end
	end

	for key, value in pairs(instance:GetAttributes()) do
		-- Our own bookkeeping attributes start with State and would
		-- otherwise parse as nonsense names
		if key:sub(1, 5) ~= "State" then
			local state, hover, name = parse(key)
			if state and name and name ~= "" then
				out[state][hover == true][name] = value
			end
		end
	end

	return out
end

-- Base look for the state with the hover variant over the top. A missing
-- hover variant means that property doesn't change on hover, rather than
-- reverting to some default.
local function resolve(instance: GuiObject, active: boolean, hover: boolean)
	local declared = declarations(instance)
	local state = active and "Active" or "Inactive"

	local values = {}
	for name, value in pairs(declared[state][false]) do
		values[name] = value
	end

	if hover then
		for name, value in pairs(declared[state][true]) do
			values[name] = value
		end
	end

	return values
end

--------------------------------------------------------------------
-- RESOLVING TARGETS
--------------------------------------------------------------------

local function has(instance: Instance, property: string): boolean
	local ok, value = pcall(function()
		return (instance :: any)[property]
	end)
	return ok and value ~= nil
end

-- A named target: a child by name, or the instance itself when Child is
-- nil. Missing children are skipped silently unless Required is set,
-- because a preset covering five parts shouldn't shout about the two a
-- given button doesn't have.
local function namedTarget(instance: GuiObject, name: string): (Instance?, string?, boolean)
	local def = STATE.Targets[name]
	if not def then return nil, nil, false end

	if not def.Child then
		return instance, def.Property, true
	end

	local child = instance:FindFirstChild(def.Child, def.Deep ~= false)
	if child then
		return child, def.Property, true
	end

	if def.Required then
		warn(string.format("[StateStyle] %s has no '%s' for %s",
			instance:GetFullName(), def.Child, name))
	end

	return nil, nil, true
end

-- A raw property name: self if it has it, then StateTarget's child, then
-- the first descendant that does.
local function propertyTarget(instance: GuiObject, property: string): Instance?
	if has(instance, property) then return instance end

	local named = instance:GetAttribute(ATTR.StateTarget)
	if type(named) == "string" and named ~= "" then
		local child = instance:FindFirstChild(named, true)
		if child and has(child, property) then return child end
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if has(descendant, property) then return descendant end
	end

	return nil
end

local function tweenInfoFor(instance: GuiObject): TweenInfo
	local seconds = instance:GetAttribute(ATTR.StateTweenTime)
	if type(seconds) ~= "number" then seconds = STATE.TweenTime end

	return TweenInfo.new(seconds, STATE.TweenStyle, STATE.TweenDirection)
end

--------------------------------------------------------------------
-- PAINTING
--------------------------------------------------------------------

local function paint(instance: GuiObject, instant: boolean?)
	local active = instance:GetAttribute(ATTR.StateActive) == true
	local isHovering = hovering[instance] == true and not TOUCH_ONLY

	local values = resolve(instance, active, isHovering)
	if next(values) == nil then return end

	-- Grouped by target so it's one tween per instance, not per property
	local goals: { [Instance]: { [string]: any } } = {}

	for name, value in pairs(values) do
		local target, property, wasNamed = namedTarget(instance, name)

		if not wasNamed then
			-- Not a declared target, so treat the name as a property
			property = name
			target = propertyTarget(instance, name)

			if not target then
				warn(string.format("[StateStyle] nothing under %s has a '%s' property",
					instance:GetFullName(), name))
			end
		end

		if target and property then
			local ok, current = pcall(function()
				return (target :: any)[property]
			end)

			if not ok then
				warn(string.format("[StateStyle] %s has no '%s'",
					target:GetFullName(), property))

			elseif instant
				or STATE.Instant[property] == true
				or not TWEENABLE[typeof(value)]
			then
				local written = pcall(function()
					(target :: any)[property] = value
				end)
				if not written then
					warn(string.format("[StateStyle] couldn't set %s on %s",
						property, target:GetFullName()))
				end

			elseif typeof(current) == typeof(value) then
				goals[target] = goals[target] or {}
				goals[target][property] = value

			else
				warn(string.format("[StateStyle] %s.%s is a %s but the value is a %s",
					target:GetFullName(), property, typeof(current), typeof(value)))
			end
		end
	end

	local info = tweenInfoFor(instance)
	for target, goal in pairs(goals) do
		TweenService:Create(target, info, goal):Play()
	end
end

--------------------------------------------------------------------
-- HOVER
--------------------------------------------------------------------

-- Connected lazily on first Apply, so nothing has to remember to call it
local function watch(instance: GuiObject)
	if watched[instance] or TOUCH_ONLY then return end
	watched[instance] = true

	instance.MouseEnter:Connect(function()
		hovering[instance] = true
		paint(instance)
	end)

	instance.MouseLeave:Connect(function()
		hovering[instance] = false
		paint(instance)
	end)

	instance.Destroying:Connect(function()
		hovering[instance] = nil
		watched[instance] = nil
	end)
end

--------------------------------------------------------------------
-- PUBLIC
--------------------------------------------------------------------

function StateStyle.IsActive(instance: GuiObject): boolean
	return instance:GetAttribute(ATTR.StateActive) == true
end

-- Whether this instance declares any look at all, directly or by preset
function StateStyle.IsStyled(instance: GuiObject): boolean
	if instance:GetAttribute(ATTR.StatePreset) ~= nil then return true end

	for key in pairs(instance:GetAttributes()) do
		if key:sub(1, 5) ~= "State" then
			local state = parse(key)
			if state then return true end
		end
	end

	return false
end

function StateStyle.Apply(instance: GuiObject, active: boolean, instant: boolean?)
	instance:SetAttribute(ATTR.StateActive, active)
	watch(instance)
	paint(instance, instant)
end

-- Sets the look without animating, for first paint
function StateStyle.Initialise(instance: GuiObject, active: boolean)
	StateStyle.Apply(instance, active, true)
end

-- Repaints without changing state, for when attributes are edited live
function StateStyle.Refresh(instance: GuiObject)
	paint(instance)
end

-- What an instance would paint in each of its four combinations, for
-- working out why something looks wrong
function StateStyle.Describe(instance: GuiObject)
	print("[StateStyle] " .. instance:GetFullName())

	local preset = instance:GetAttribute(ATTR.StatePreset)
	if preset then print("    preset: " .. tostring(preset)) end

	for _, active in ipairs({ false, true }) do
		for _, hover in ipairs({ false, true }) do
			local values = resolve(instance, active, hover)
			local parts = {}

			for name, value in pairs(values) do
				table.insert(parts, name .. "=" .. tostring(value))
			end

			table.sort(parts)
			print(string.format("    %-9s %-6s %s",
				active and "Active" or "Inactive",
				hover and "hover" or "base",
				next(parts) and table.concat(parts, "  ") or "nothing"))
		end
	end
end

return StateStyle