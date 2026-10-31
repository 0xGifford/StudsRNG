--!strict
-- Single responsibility: an on/off switch. Used where the state is a plain
-- boolean with no sub-options (outline on/off) — anything with sub-options
-- belongs in a Segmented instead.

local Theme = require(script.Parent.Theme)

local Toggle = {}
Toggle.__index = Toggle

local WIDTH = 34
local HEIGHT = 18
local KNOB = 14

function Toggle.new(parent: Instance, spec: { [string]: any })
	local self = setmetatable({}, Toggle)
	self.value = spec.Value == true
	self.OnChanged = nil :: ((boolean) -> ())?

	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	button.Position = UDim2.new(0, 0, 0.5, -HEIGHT / 2)
	button.Text = ""
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.LayoutOrder = spec.LayoutOrder or 1
	button.Parent = parent
	Theme.Corner(button, HEIGHT / 2)
	self.Frame = button

	-- THE reason this control was reported as "there is no switch". The OFF
	-- track is InputFieldBackground, which in the LIGHT Studio theme is very
	-- nearly the panel's own white — and the knob was hardcoded white on top
	-- of it. An OFF toggle was therefore white-on-white with no edge: totally
	-- invisible, and only findable by clicking blind until it turned green.
	-- Never let this control rely on its fill alone to be seen: the outline is
	-- derived from the fill (Theme.Outline lightens a dark one, darkens a light
	-- one), so it has a visible edge in either theme.
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Transparency = 0.35
	stroke.Parent = button
	self.stroke = stroke

	-- White in BOTH states, as a switch knob is everywhere else: it is what
	-- makes the control read as a switch rather than as a coloured pill. It
	-- only survives on a light track because of the outline below — without
	-- one, the light theme's knob was white on near-white and the whole
	-- control disappeared.
	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(KNOB, KNOB)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.Parent = button
	Theme.Corner(knob, KNOB / 2)
	self.knob = knob

	local knobStroke = Instance.new("UIStroke")
	knobStroke.Thickness = 1
	knobStroke.Transparency = 0.55
	knobStroke.Parent = knob
	self.knobStroke = knobStroke

	button.Activated:Connect(function()
		self.value = not self.value
		self:_refresh()
		if self.OnChanged then
			self.OnChanged(self.value)
		end
	end)

	self:_refresh()
	return self
end

function Toggle:_refresh()
	-- Theme.FieldFill, not InputFieldBackground: that Studio colour is pure
	-- white in the light theme, i.e. the same white as the panel behind it,
	-- which is what made an OFF switch invisible. Unchanged in the dark theme.
	local fill = self.value and Theme.OK or Theme.FieldFill()
	self.Frame.BackgroundColor3 = fill
	self.stroke.Color = Theme.Outline(fill)
	-- Only the OFF knob needs an edge: on the green ON track white already has
	-- all the contrast it needs, and an outline there just muddies it.
	self.knobStroke.Transparency = self.value and 1 or 0.55
	self.knobStroke.Color = Theme.Outline(fill)
	self.knob.Position = self.value
		and UDim2.new(1, -KNOB / 2 - 2, 0.5, 0)
		or UDim2.new(0, KNOB / 2 + 2, 0.5, 0)
end

-- Coerced, not stored raw: a caller reading a missing attribute passes nil,
-- and a nil here made the NEXT click compute `not nil` = true — so a switch
-- whose real state was already on took two clicks to turn off.
function Toggle:Set(value: boolean)
	self.value = value == true
	self:_refresh()
end

return Toggle
