--!strict
-- ModuleScript -> ReplicatedStorage/MenuSystem/Menus/Motion
--
-- Idle motion driven by attributes. Anything in PlayerGui that declares
-- one starts moving; nothing needs registering.
--
--   Sway = 5              rocks between -5 and +5 degrees
--   Sway = "-2,8"         asymmetric: -2 to +8
--   SwaySpeed = 1.5       full cycles per second
--   SwayOffset = 0.5      phase, 0 to 1, to stagger a row of icons
--
--   Bob = 6               moves up and down 6 pixels
--   Pulse = 0.08          scales between 1 and 1.08
--   Spin = 45             continuous rotation, degrees per second
--
-- Sway, Bob and Pulse are sine waves; Spin is linear and never reverses.
-- They combine, so an icon can sway and pulse at once.
--
-- Every value can be a number or a "min,max" string. A bare number means
-- symmetric around the resting value, which is what you want almost
-- always: Sway = 5 gives -5 to +5.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MenuSystem = script.Parent.Parent
local Config = require(MenuSystem.Config)

local ATTR = Config.Attributes
local MOTION = Config.Motion

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Motion = {}

type Range = { Min: number, Max: number }

type Entry = {
	Instance: GuiObject,

	Sway: Range?,
	Bob: Range?,
	Pulse: Range?,
	Spin: number?,

	Speed: number,
	Phase: number,

	-- Where it started, so motion is relative and a restyle doesn't fight it
	BaseRotation: number,
	BasePosition: UDim2,
	Scale: UIScale?,
}

local entries: { [GuiObject]: Entry } = {}
local running = false

-- A single clock rather than a running sum of deltas. Accumulating drifts
-- as float error builds over a long session, and a frame hitch shows up as
-- a visible jump; reading the clock each frame is immune to both.
local startedAt = os.clock()

--------------------------------------------------------------------
-- PARSING
--------------------------------------------------------------------

-- A number is symmetric: 5 becomes -5 to 5. A "min,max" string is taken
-- literally, so "0,10" only ever moves one way.
local function parseRange(value: any): Range?
	if type(value) == "number" then
		if value == 0 then return nil end
		return { Min = -math.abs(value), Max = math.abs(value) }
	end

	if type(value) ~= "string" then return nil end

	local minText, maxText = value:match("^%s*(%-?[%d%.]+)%s*,%s*(%-?[%d%.]+)%s*$")
	if minText and maxText then
		local min, max = tonumber(minText), tonumber(maxText)
		if min and max then
			if min > max then min, max = max, min end
			return { Min = min, Max = max }
		end
	end

	-- A single number as a string, since Studio attributes are easy to
	-- type into the wrong field
	local single = tonumber(value)
	if single then
		return { Min = -math.abs(single), Max = math.abs(single) }
	end

	return nil
end

local function number(instance: GuiObject, attribute: string, fallback: number): number
	local value = instance:GetAttribute(attribute)
	return type(value) == "number" and value or fallback
end

--------------------------------------------------------------------
-- BINDING
--------------------------------------------------------------------

local function scaleOf(instance: GuiObject): UIScale
	local existing = instance:FindFirstChildOfClass("UIScale")
	if existing then return existing end

	local scale = Instance.new("UIScale")
	scale.Name = "UIScale"
	scale.Parent = instance
	return scale
end

local function build(instance: GuiObject): Entry?
	local sway = parseRange(instance:GetAttribute(ATTR.Sway))
	local bob = parseRange(instance:GetAttribute(ATTR.Bob))
	local pulse = parseRange(instance:GetAttribute(ATTR.Pulse))

	local spinValue = instance:GetAttribute(ATTR.Spin)
	local spin = type(spinValue) == "number" and spinValue ~= 0 and spinValue or nil

	if not (sway or bob or pulse or spin) then return nil end

	-- A phase of 0 to 1 maps to a full cycle, so a row of five icons at
	-- 0, 0.2, 0.4... ripples rather than moving in lockstep
	local phase = number(instance, ATTR.MotionOffset, 0) * math.pi * 2

	-- Random when asked for, so a grid of identical cards doesn't pulse
	-- as one block
	if instance:GetAttribute(ATTR.MotionRandom) == true then
		phase = math.random() * math.pi * 2
	end

	-- A layout owns its children's positions and rewrites them every
	-- frame, so a bob underneath one fights the layout and stutters.
	-- Pulse works fine there, since UIScale isn't a position.
	if bob then
		local parent = instance.Parent

		if parent and (parent:FindFirstChildOfClass("UIListLayout")
			or parent:FindFirstChildOfClass("UIGridLayout"))
		then
			warn(string.format(
				"[Motion] %s has Bob but its parent has a layout, which will " ..
					"fight it. Use Pulse, or wrap the icon in a plain frame.",
				instance:GetFullName()))
		end
	end

	return {
		Instance = instance,
		Sway = sway,
		Bob = bob,
		Pulse = pulse,
		Spin = spin,
		Speed = number(instance, ATTR.MotionSpeed, MOTION.Speed),
		Phase = phase,
		BaseRotation = instance.Rotation,
		BasePosition = instance.Position,
		Scale = pulse and scaleOf(instance) or nil,
	}
end

function Motion.Bind(instance: GuiObject)
	local entry = build(instance)
	if not entry then return end

	entries[instance] = entry

	instance.Destroying:Connect(function()
		entries[instance] = nil
	end)

	-- Editing an attribute live rebuilds, so tuning a sway in Studio
	-- during a playtest shows immediately
	instance.AttributeChanged:Connect(function(name)
		if MOTION.Attributes[name] then
			local rebuilt = build(instance)

			if rebuilt then
				-- Keep the resting values from the original bind, or a
				-- rebuild mid-swing bakes in the current offset
				local existing = entries[instance]
				if existing then
					rebuilt.BaseRotation = existing.BaseRotation
					rebuilt.BasePosition = existing.BasePosition
				end
				entries[instance] = rebuilt
			else
				-- Motion removed: put it back where it started
				local existing = entries[instance]
				if existing then
					instance.Rotation = existing.BaseRotation
					instance.Position = existing.BasePosition
					if existing.Scale then existing.Scale.Scale = 1 end
				end
				entries[instance] = nil
			end
		end
	end)
end

--------------------------------------------------------------------
-- STEP
--------------------------------------------------------------------

-- Maps a sine wave onto a range. Sine gives -1 to 1, so this rescales
-- rather than assuming the range is symmetric.
local function wave(range: Range, t: number): number
	local unit = (math.sin(t) + 1) / 2
	return range.Min + (range.Max - range.Min) * unit
end

local function step(_delta: number)
	local elapsed = os.clock() - startedAt

	for instance, entry in pairs(entries) do
		if not instance.Parent then
			entries[instance] = nil
			continue
		end

		local t = elapsed * entry.Speed * math.pi * 2 + entry.Phase

		local rotation = entry.BaseRotation

		if entry.Sway then
			rotation += wave(entry.Sway, t)
		end

		if entry.Spin then
			-- Wrapped, or the number grows without limit over a long session
			rotation += (elapsed * entry.Spin) % 360
		end

		if entry.Sway or entry.Spin then
			instance.Rotation = rotation
		end

		if entry.Bob then
			-- Fractional pixels, deliberately. Rounding to whole ones makes
			-- a 5px bob step through six positions, which reads as jitter
			-- rather than float: Roblox renders sub-pixel offsets fine.
			local offset = wave(entry.Bob, t)

			instance.Position = UDim2.new(
				entry.BasePosition.X.Scale,
				entry.BasePosition.X.Offset,
				entry.BasePosition.Y.Scale,
				entry.BasePosition.Y.Offset + offset)
		end

		if entry.Pulse and entry.Scale then
			entry.Scale.Scale = 1 + wave(entry.Pulse, t)
		end
	end
end

--------------------------------------------------------------------

local function consider(instance: Instance)
	if instance:IsA("GuiObject") and not entries[instance] then
		Motion.Bind(instance)
	end
end

function Motion.Start()
	if running then return end
	running = true

	for _, descendant in ipairs(playerGui:GetDescendants()) do
		consider(descendant)
	end

	playerGui.DescendantAdded:Connect(function(instance)
		-- Attributes are usually set a frame after parenting
		task.defer(function()
			if instance.Parent then consider(instance) end
		end)
	end)

	RunService.RenderStepped:Connect(step)
end

-- Stops everything and puts each instance back where it started
function Motion.StopAll()
	for instance, entry in pairs(entries) do
		if instance.Parent then
			instance.Rotation = entry.BaseRotation
			instance.Position = entry.BasePosition
			if entry.Scale then entry.Scale.Scale = 1 end
		end
	end

	table.clear(entries)
end

function Motion.Count(): number
	local n = 0
	for _ in pairs(entries) do n += 1 end
	return n
end

return Motion