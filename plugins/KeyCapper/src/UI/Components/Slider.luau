--!strict
-- Single responsibility: pick a number by dragging. Stepped, clamped, and
-- deterministic — no free text to mistype.
--
-- Reused everywhere a number is edited (brush size, colour variation ranges,
-- press/release times, outline size), which is why it takes a formatter
-- rather than assuming a unit.

local Theme = require(script.Parent.Theme)
local DragCapture = require(script.Parent.DragCapture)

local Slider = {}
Slider.__index = Slider

local TRACK_HEIGHT = 6
local KNOB = 12

-- spec: Min, Max, Step, Value, Format (number -> string), LayoutOrder.
function Slider.new(parent: Instance, spec: { [string]: any })
	local self = setmetatable({}, Slider)

	self.min = spec.Min or 0
	self.max = spec.Max or 1
	self.step = spec.Step or 0
	self.format = spec.Format or function(value: number) return string.format("%.2f", value) end
	self.value = self.min
	-- Assigned by the caller. Only fired on a user drag, never by :Set, so
	-- reflecting a stored value can't echo back as an edit.
	self.OnChanged = nil :: ((number) -> ())?

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = spec.LayoutOrder or 1
	frame.Parent = parent
	self.Frame = frame

	-- The readout sits on the right of the track: the row's left column is
	-- already the name, and a value floating elsewhere would be hard to pair.
	local readout = Instance.new("TextLabel")
	readout.Size = UDim2.new(0, 46, 1, 0)
	readout.Position = UDim2.new(1, -46, 0, 0)
	readout.BackgroundTransparency = 1
	readout.Font = Theme.FONT
	readout.TextSize = Theme.TEXT_SIZE
	readout.TextXAlignment = Enum.TextXAlignment.Right
	readout.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.MainText)
	readout.Parent = frame
	self.readout = readout

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -52, 0, TRACK_HEIGHT)
	track.Position = UDim2.new(0, 0, 0.5, -TRACK_HEIGHT / 2)
	-- White-on-white in the light theme before this: the track vanished and a
	-- slider showed up as a lone floating knob with no scale under it.
	track.BackgroundColor3 = Theme.FieldFill()
	track.BorderSizePixel = 0
	track.Parent = frame
	Theme.Corner(track, TRACK_HEIGHT / 2)
	Theme.Edge(track, 1)
	self.track = track

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Theme.ACCENT
	fill.BorderSizePixel = 0
	fill.Parent = track
	Theme.Corner(fill, TRACK_HEIGHT / 2)
	self.fill = fill

	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(KNOB, KNOB)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.new(0, 0, 0.5, 0)
	knob.BackgroundColor3 = Theme.Color(Enum.StudioStyleGuideColor.MainText)
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = track
	Theme.Corner(knob, KNOB / 2)
	self.knob = knob

	-- Takes a position, not an InputObject: during the drag it comes from
	-- DragCapture's poll rather than from an input event. Both are in the
	-- widget's coordinate space, the same one AbsolutePosition is in.
	local function apply(position: Vector2)
		local width = track.AbsoluteSize.X
		if width <= 0 then return end
		local ratio = math.clamp((position.X - track.AbsolutePosition.X) / width, 0, 1)
		local raw = self.min + ratio * (self.max - self.min)
		self:_set(self:_quantize(raw), true)
	end

	-- Pressing anywhere on the row starts a drag, not just a jump-to-click:
	-- the whole row height is a hit target (a 6px track is not), and
	-- DragCapture then follows the cursor even off the control. Frame,
	-- track AND knob all need Active=true — a plain (non-button) GuiObject
	-- does not receive InputBegan at all unless Active is explicitly set,
	-- transparent or not.
	local function beginDrag(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		apply(Vector2.new(input.Position.X, input.Position.Y))
		DragCapture.Begin(frame, input, apply)
	end

	frame.Active = true
	track.Active = true
	knob.Active = true
	frame.InputBegan:Connect(beginDrag)
	track.InputBegan:Connect(beginDrag)
	knob.InputBegan:Connect(beginDrag)

	self:Set(spec.Value or self.min)
	return self
end

function Slider:_quantize(value: number): number
	if self.step and self.step > 0 then
		value = self.min + math.round((value - self.min) / self.step) * self.step
	end
	return math.clamp(value, self.min, self.max)
end

function Slider:_set(value: number, fromUser: boolean)
	local changed = value ~= self.value
	self.value = value

	local span = self.max - self.min
	local ratio = span > 0 and (value - self.min) / span or 0
	self.fill.Size = UDim2.fromScale(ratio, 1)
	self.knob.Position = UDim2.new(ratio, 0, 0.5, 0)
	self.readout.Text = self.format(value)

	if fromUser and changed and self.OnChanged then
		self.OnChanged(value)
	end
end

-- Reflects a stored value. Silent on purpose: see OnChanged.
function Slider:Set(value: number)
	self:_set(self:_quantize(value), false)
end

return Slider
