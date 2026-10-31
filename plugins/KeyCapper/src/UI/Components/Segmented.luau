--!strict
-- Single responsibility: pick exactly one option among a small fixed set,
-- with every option visible at once.
--
-- Replaces the cycling buttons the panel used to have: a button reading
-- "Cap color: Solid" never told you what the other choices were, or that
-- there were any. Also the natural host for mode switching, since the caller
-- can show/hide fields from OnChanged.

local Theme = require(script.Parent.Theme)

local Segmented = {}
Segmented.__index = Segmented

-- spec: Options ({string}), Value, LayoutOrder, Labels ({[string]: string})
-- for a display text that differs from the stored value, Icons ({string})
-- for the options that should also get a placeholder icon (the plugin's
-- main tool switch, mostly — a segmented row of plain words doesn't need
-- one everywhere).
function Segmented.new(parent: Instance, spec: { [string]: any })
	local self = setmetatable({}, Segmented)

	self.options = spec.Options
	self.value = spec.Value or self.options[1]
	self.buttons = {} :: { [string]: TextButton }
	self.labels = {} :: { [string]: TextLabel }
	-- Only the options that asked for one, so _refresh has to tolerate a hole.
	self.icons = {} :: { [string]: ImageLabel }
	self.OnChanged = nil :: ((string) -> ())?

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Theme.FieldFill()
	frame.BorderSizePixel = 0
	frame.LayoutOrder = spec.LayoutOrder or 1
	frame.Parent = parent
	-- Pill shape, not the flat card corner: a segmented control reads as a
	-- toggle switch, and a toggle switch is round.
	Theme.Corner(frame, Theme.ROW_HEIGHT / 2)
	-- The pill's own outline. Without it the unselected half of the control is
	-- just floating words in the light theme — nothing says the other options
	-- are part of one switch, or that they can be clicked at all.
	Theme.Edge(frame, 1)
	self.Frame = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 2)
	pad.PaddingBottom = UDim.new(0, 2)
	pad.PaddingLeft = UDim.new(0, 2)
	pad.PaddingRight = UDim.new(0, 2)
	pad.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	local iconOptions = {}
	for _, option in ipairs(spec.Icons or {}) do
		iconOptions[option] = true
	end

	local count = #self.options
	for index, option in ipairs(self.options) do
		local button = Theme.Button("", frame)
		Theme.Corner(button, Theme.ROW_HEIGHT / 2 - 2)
		button.LayoutOrder = index
		-- The 2px gaps between segments are taken out of each share so the
		-- last one still lands inside the frame.
		button.Size = UDim2.new(1 / count, -2 * (count - 1) / count, 1, 0)
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false

		local inner = Instance.new("Frame")
		inner.Size = UDim2.fromScale(1, 1)
		inner.BackgroundTransparency = 1
		inner.Parent = button
		local innerLayout = Instance.new("UIListLayout")
		innerLayout.FillDirection = Enum.FillDirection.Horizontal
		innerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		innerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		innerLayout.Padding = UDim.new(0, 4)
		innerLayout.SortOrder = Enum.SortOrder.LayoutOrder
		innerLayout.Parent = inner

		if iconOptions[option] then
			local icon = Theme.Icon(inner, option, 14)
			icon.LayoutOrder = 1
			self.icons[option] = icon
		end

		local label = Theme.Text((spec.Labels and spec.Labels[option]) or option, inner)
		label.Size = UDim2.fromOffset(0, 20)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.LayoutOrder = 2
		label.TextSize = Theme.TEXT_SIZE - 1
		label.TextXAlignment = Enum.TextXAlignment.Center

		button.Activated:Connect(function()
			self:_set(option, true)
		end)
		self.buttons[option] = button
		self.labels[option] = label
	end

	self:_refresh()
	return self
end

function Segmented:_refresh()
	for option, button in pairs(self.buttons) do
		local selected = option == self.value
		button.BackgroundTransparency = selected and 0 or 1
		button.BackgroundColor3 = Theme.ACCENT
		local label = self.labels[option]
		label.TextColor3 = selected
			and Theme.ACCENT_TEXT
			or Theme.Color(Enum.StudioStyleGuideColor.DimmedText)
		label.Font = selected and Theme.FONT_BOLD or Theme.FONT
		-- Follows the label: the selected segment is an accent fill, so its glyph
		-- needs the same white the text uses, not the panel's icon colour.
		local icon = self.icons[option]
		if icon then
			icon.ImageColor3 = selected and Theme.ACCENT_TEXT or Theme.IconTint()
		end
	end
end

function Segmented:_set(value: string, fromUser: boolean)
	if value == self.value then return end
	self.value = value
	self:_refresh()
	if fromUser and self.OnChanged then
		self.OnChanged(value)
	end
end

-- Reflects a stored value without firing OnChanged. Falls back to the first
-- option on unknown data rather than showing nothing selected.
function Segmented:Set(value: string?)
	-- "" is a deliberate deselect (see ColorChannel's preset row): only
	-- unrecognised, non-empty data falls back to the first option.
	--
	-- nil is checked before table.find rather than handed to it: find errors
	-- on a nil needle, and that error came out of the middle of a
	-- ShowGroupValues pass — taking every control after it down with it, so a
	-- whole run of rows kept showing the PREVIOUS group's selection.
	if value == nil or (value ~= "" and not table.find(self.options, value)) then
		value = self.options[1]
	end
	self.value = value
	self:_refresh()
end

return Segmented
