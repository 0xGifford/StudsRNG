--!strict
-- Single responsibility: pick a colour. Shows as a swatch in a row; clicking
-- it opens an HSV picker (saturation/value square + hue strip), with a hex
-- field kept as a fallback and a row of recently used colours.
--
-- Replaces the hex-only text fields: five colour settings in this panel, and
-- typing "E6F0FA" is not how anyone chooses a colour.

local Theme = require(script.Parent.Theme)
local Popup = require(script.Parent.Popup)
local DragCapture = require(script.Parent.DragCapture)

local ColorPicker = {}
ColorPicker.__index = ColorPicker

local WIDTH = 190
-- Square + hex row + Done row + padding. No recent-swatches row: the square
-- reaches any colour in one gesture, so a history of previous ones was a row
-- of shortcuts to something that was never far away.
local POPUP_HEIGHT = 8 + 120 + 8 + 20 + 6 + 22 + 8
local SQUARE = 120
local STRIP = 14

function ColorPicker.new(parent: Instance, spec: { [string]: any })
	local self = setmetatable({}, ColorPicker)
	self.overlay = spec.Overlay
	self.hue, self.saturation, self.value = 0, 0, 1
	self.OnChanged = nil :: ((Color3) -> ())?

	-- A fixed-width chip plus its hex, not a full-width block of colour.
	-- Full width read as an empty input field, and a dark colour on the dark
	-- panel was invisible — you could not tell a black swatch from a hole.
	-- The chip's own outline is what guarantees the edge is always visible,
	-- whatever colour sits inside it.
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 48, 1, -4)
	button.Position = UDim2.fromOffset(0, 2)
	button.Text = ""
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	button.LayoutOrder = spec.LayoutOrder or 1
	button.Parent = parent
	Theme.Corner(button, 5)
	self.Frame = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(150, 154, 162)
	stroke.Transparency = 0.25
	stroke.Thickness = 1.5
	stroke.Parent = button

	local hexLabel = Theme.Text("", parent)
	hexLabel.Size = UDim2.new(1, -56, 1, 0)
	hexLabel.Position = UDim2.fromOffset(56, 0)
	hexLabel.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.DimmedText)
	hexLabel.TextSize = Theme.TEXT_SIZE - 1
	self.hexLabel = hexLabel

	button.Activated:Connect(function()
		if self.popup and self.popup:IsOpen() then
			self.popup:Close()
		else
			self:_open()
		end
	end)

	self:Set(spec.Value or Color3.new(1, 1, 1))
	return self
end

function ColorPicker:_build()
	self.popup = Popup.new(self.overlay)
	local frame = self.popup.Frame

	-- Saturation/value square: a white-to-hue horizontal gradient with a
	-- transparent-to-black vertical one on top. Same trick every colour
	-- picker uses, and it needs no image asset.
	local square = Instance.new("Frame")
	square.Size = UDim2.fromOffset(SQUARE, SQUARE)
	square.Position = UDim2.fromOffset(8, 8)
	square.BorderSizePixel = 0
	square.ZIndex = 21
	square.Parent = frame
	Theme.Corner(square, 4)
	self.square = square

	local hueGradient = Instance.new("UIGradient")
	hueGradient.Parent = square
	self.hueGradient = hueGradient

	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BorderSizePixel = 0
	shade.ZIndex = 22
	shade.Parent = square
	Theme.Corner(shade, 4)

	local shadeGradient = Instance.new("UIGradient")
	shadeGradient.Rotation = 90
	shadeGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	shadeGradient.Parent = shade

	local cursor = Instance.new("Frame")
	cursor.Size = UDim2.fromOffset(8, 8)
	cursor.AnchorPoint = Vector2.new(0.5, 0.5)
	cursor.BackgroundTransparency = 1
	cursor.ZIndex = 23
	cursor.Parent = square
	Theme.Corner(cursor, 4)
	local cursorStroke = Instance.new("UIStroke")
	cursorStroke.Color = Color3.new(1, 1, 1)
	cursorStroke.Thickness = 2
	cursorStroke.Parent = cursor
	self.cursor = cursor

	local strip = Instance.new("Frame")
	strip.Size = UDim2.fromOffset(STRIP, SQUARE)
	strip.Position = UDim2.fromOffset(8 + SQUARE + 8, 8)
	strip.BorderSizePixel = 0
	strip.ZIndex = 21
	strip.Parent = frame
	Theme.Corner(strip, 4)
	self.strip = strip

	local stripGradient = Instance.new("UIGradient")
	stripGradient.Rotation = 90
	stripGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromHSV(0, 1, 1)),
		ColorSequenceKeypoint.new(0.17, Color3.fromHSV(0.17, 1, 1)),
		ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.33, 1, 1)),
		ColorSequenceKeypoint.new(0.50, Color3.fromHSV(0.50, 1, 1)),
		ColorSequenceKeypoint.new(0.67, Color3.fromHSV(0.67, 1, 1)),
		ColorSequenceKeypoint.new(0.83, Color3.fromHSV(0.83, 1, 1)),
		ColorSequenceKeypoint.new(1.00, Color3.fromHSV(1, 1, 1)),
	})
	stripGradient.Parent = strip

	local stripCursor = Instance.new("Frame")
	stripCursor.Size = UDim2.new(1, 4, 0, 3)
	stripCursor.AnchorPoint = Vector2.new(0.5, 0.5)
	stripCursor.Position = UDim2.fromScale(0.5, 0)
	stripCursor.BackgroundColor3 = Color3.new(1, 1, 1)
	stripCursor.BorderSizePixel = 0
	stripCursor.ZIndex = 23
	stripCursor.Parent = strip
	self.stripCursor = stripCursor

	local hexBox = Instance.new("TextBox")
	hexBox.Size = UDim2.new(1, -16, 0, 20)
	hexBox.Position = UDim2.fromOffset(8, 8 + SQUARE + 8)
	hexBox.BackgroundColor3 = Theme.FieldFill()
	hexBox.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.MainText)
	hexBox.BorderSizePixel = 0
	hexBox.Font = Theme.FONT
	hexBox.TextSize = Theme.TEXT_SIZE
	hexBox.ClearTextOnFocus = false
	hexBox.ZIndex = 21
	hexBox.Parent = frame
	Theme.Corner(hexBox)
	Theme.Edge(hexBox, 1)
	self.hexBox = hexBox

	hexBox.FocusLost:Connect(function()
		local ok, color = pcall(Color3.fromHex, hexBox.Text)
		if ok then
			self:_setColor(color, true)
		else
			-- A half-typed hex is not an edit: put the real value back.
			hexBox.Text = self:Color():ToHex()
		end
	end)

	-- The ONLY way out of this popup, because it is persistent (see below).
	-- The colour is already applied live, so this confirms nothing — it is
	-- purely the dismissal, and it has to exist precisely because clicking
	-- outside no longer performs one.
	local doneButton = Theme.Button("Done", frame)
	doneButton.Size = UDim2.new(1, -16, 0, 22)
	doneButton.Position = UDim2.fromOffset(8, 8 + SQUARE + 8 + 20 + 6)
	doneButton.BackgroundColor3 = Theme.ACCENT
	doneButton.TextColor3 = Theme.ACCENT_TEXT
	doneButton.Font = Theme.FONT_BOLD
	doneButton.ZIndex = 21
	-- See Panel: AutoButtonColor would restore the fill it cached on hover.
	doneButton.AutoButtonColor = false
	doneButton.MouseEnter:Connect(function()
		doneButton.BackgroundColor3 = Theme.ACCENT:Lerp(Color3.new(1, 1, 1), 0.15)
	end)
	doneButton.MouseLeave:Connect(function()
		doneButton.BackgroundColor3 = Theme.ACCENT
	end)
	doneButton.Activated:Connect(function()
		self.popup:Close()
	end)

	-- Dragging is the whole point of this popup, and a drag that ends outside
	-- its bounds — which is most of them, the hue strip is 14px wide — read as
	-- an outside click and dismissed it. Picking a hue on the right closed the
	-- picker before you could go back to the square on the left and refine it.
	-- So this one does not dismiss on an outside click at all: Done closes it.
	self.popup.persistent = true

	self:_bindDrag(square, function(rx, ry)
		self.saturation = rx
		self.value = 1 - ry
		self:_pushColor()
	end)
	self:_bindDrag(strip, function(_, ry)
		self.hue = ry
		self:_pushColor()
	end)
end

-- Both the square and the strip drag the same way, so the geometry is written
-- once and the caller only interprets the normalised coordinates.
--
-- The drag runs through DragCapture rather than being tracked here: see that
-- module for why an in-place drag left the picker latched and un-escapable.
function ColorPicker:_bindDrag(target: GuiObject, handler: (number, number) -> ())
	-- Takes a position, not an InputObject: during the drag it comes from
	-- DragCapture's poll rather than from an input event.
	local function apply(position: Vector2)
		local size = target.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then return end
		handler(
			math.clamp((position.X - target.AbsolutePosition.X) / size.X, 0, 1),
			math.clamp((position.Y - target.AbsolutePosition.Y) / size.Y, 0, 1)
		)
	end

	target.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		apply(Vector2.new(input.Position.X, input.Position.Y))
		-- No release callback: releasing the mouse ends the drag and that is
		-- the whole of it. The colour was already applied on every frame of it.
		DragCapture.Begin(target, input, apply)
	end)
end

function ColorPicker:_open()
	if not self.popup then
		self:_build()
	end
	self:_refreshFields()
	self.popup:OpenAt(self.Frame, WIDTH, POPUP_HEIGHT)
end

function ColorPicker:Color(): Color3
	return Color3.fromHSV(self.hue, self.saturation, self.value)
end

function ColorPicker:_pushColor()
	self:_refreshFields()
	self.Frame.BackgroundColor3 = self:Color()
	self.hexLabel.Text = "#" .. self:Color():ToHex():upper()
	if self.OnChanged then
		self.OnChanged(self:Color())
	end
end

function ColorPicker:_setColor(color: Color3, fromUser: boolean)
	self.hue, self.saturation, self.value = color:ToHSV()
	self.Frame.BackgroundColor3 = color
	self.hexLabel.Text = "#" .. color:ToHex():upper()
	self:_refreshFields()
	if fromUser and self.OnChanged then
		self.OnChanged(color)
	end
end

function ColorPicker:_refreshFields()
	if not self.popup then return end
	self.hueGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(self.hue, 1, 1))
	self.cursor.Position = UDim2.fromScale(self.saturation, 1 - self.value)
	self.stripCursor.Position = UDim2.fromScale(0.5, self.hue)
	if not self.hexBox:IsFocused() then
		self.hexBox.Text = self:Color():ToHex()
	end
end

-- Reflects a stored colour. Silent, like every other component's :Set.
function ColorPicker:Set(color: Color3)
	self:_setColor(color, false)
end

return ColorPicker
