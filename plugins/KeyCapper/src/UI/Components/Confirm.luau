--!strict
-- Single responsibility: ask a yes/no question about a destructive action and
-- report the answer. It does NOT know what is being destroyed, and it never
-- performs anything itself — it takes a callback and calls it on confirm.
--
-- Built on Popup like every other floating surface, which also gives it the
-- "only one thing floats at a time" rule for free: opening the confirmation
-- closes the dropdown the × was clicked in, so the question is never buried
-- under the list it came from.
--
-- Deliberately anchored rather than centred on the widget: a modal in the
-- middle of a 320px dock widget covers the very row it is asking about.

local Theme = require(script.Parent.Theme)
local Popup = require(script.Parent.Popup)

local Confirm = {}
Confirm.__index = Confirm

local PAD = 10
local TITLE_HEIGHT = 18
local BODY_HEIGHT = 46
local BUTTON_HEIGHT = 26
local BUTTON_WIDTH = 76
local GAP = 6
local WIDTH = 244
local HEIGHT = PAD * 2 + TITLE_HEIGHT + BODY_HEIGHT + BUTTON_HEIGHT + GAP

function Confirm.new(overlay: GuiObject)
	local self = setmetatable({}, Confirm)
	self.popup = Popup.new(overlay)
	-- Set fresh on every Ask, and cleared as soon as it fires: a stale
	-- callback surviving a cancelled question is exactly how a confirmation
	-- dialog ends up deleting the wrong thing.
	self.onConfirm = nil :: (() -> ())?

	local frame = self.popup.Frame

	local title = Theme.Text("", frame)
	title.Position = UDim2.fromOffset(PAD, PAD)
	title.Size = UDim2.new(1, -PAD * 2, 0, TITLE_HEIGHT)
	title.Font = Theme.FONT_BOLD
	title.ZIndex = 21
	self.title = title

	local body = Theme.Text("", frame)
	body.Position = UDim2.fromOffset(PAD, PAD + TITLE_HEIGHT)
	body.Size = UDim2.new(1, -PAD * 2, 0, BODY_HEIGHT)
	body.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.DimmedText)
	body.TextSize = Theme.TEXT_SIZE - 1
	body.TextYAlignment = Enum.TextYAlignment.Top
	-- The body is the only variable-length text here, and truncating the
	-- consequences of a destructive action would defeat the point.
	body.TextWrapped = true
	body.TextTruncate = Enum.TextTruncate.None
	body.ZIndex = 21
	self.body = body

	local confirmButton = Theme.Button("Delete", frame)
	confirmButton.Size = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT)
	confirmButton.Position = UDim2.new(1, -(PAD + BUTTON_WIDTH), 1, -(PAD + BUTTON_HEIGHT))
	confirmButton.BackgroundColor3 = Theme.DANGER
	confirmButton.TextColor3 = Theme.ACCENT_TEXT
	confirmButton.Font = Theme.FONT_BOLD
	confirmButton.ZIndex = 21
	-- See Panel: AutoButtonColor restores the fill it cached on mouse-enter,
	-- which would turn this red into Studio grey after the first hover.
	confirmButton.AutoButtonColor = false
	confirmButton.MouseEnter:Connect(function()
		confirmButton.BackgroundColor3 = Theme.DANGER:Lerp(Color3.new(1, 1, 1), 0.15)
	end)
	confirmButton.MouseLeave:Connect(function()
		confirmButton.BackgroundColor3 = Theme.DANGER
	end)
	self.confirmButton = confirmButton

	local cancel = Theme.Button("Cancel", frame)
	cancel.Size = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT)
	cancel.Position = UDim2.new(1, -(PAD + BUTTON_WIDTH * 2 + GAP), 1, -(PAD + BUTTON_HEIGHT))
	cancel.ZIndex = 21

	confirmButton.Activated:Connect(function()
		-- Read and cleared BEFORE the popup closes: Close() is also what a
		-- cancel runs, and the callback must not be reachable twice.
		local callback = self.onConfirm
		self.onConfirm = nil
		self.popup:Close()
		if callback then callback() end
	end)
	cancel.Activated:Connect(function()
		self.onConfirm = nil
		self.popup:Close()
	end)

	return self
end

-- spec: Title, Body, ConfirmText (defaults to "Delete").
-- Clicking outside dismisses it through Popup's shared backdrop, which counts
-- as a cancel: nothing is destroyed unless the red button is pressed.
function Confirm:Ask(anchor: GuiObject, spec: { [string]: any }, onConfirm: () -> ())
	self.title.Text = spec.Title or "Are you sure?"
	self.body.Text = spec.Body or ""
	self.confirmButton.Text = spec.ConfirmText or "Delete"
	self.onConfirm = onConfirm
	self.popup:OpenAt(anchor, WIDTH, HEIGHT)
end

return Confirm
