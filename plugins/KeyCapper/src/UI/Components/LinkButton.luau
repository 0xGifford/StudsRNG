--!strict
-- Single responsibility: an icon button that reveals a URL ready to be copied.
--
-- It shows the link rather than copying it because a Studio plugin has no
-- clipboard API at all — there is no plugin:SetClipboard(), and no permission
-- that would grant one. So the next best thing is to remove every step
-- between the click and Ctrl+C: the popup opens with the field already
-- focused and the whole URL already selected, so the copy is two keys and
-- never a drag-select.

local Theme = require(script.Parent.Theme)
local Popup = require(script.Parent.Popup)

local LinkButton = {}
LinkButton.__index = LinkButton

local POPUP_WIDTH = 250
local HINT_HEIGHT = 16
local FIELD_HEIGHT = 26
local PAD = 6

-- spec: Icon (Theme.Icon slug), Url, Overlay, Color (button fill), Tooltip.
function LinkButton.new(parent: Instance, spec: { [string]: any })
	local self = setmetatable({}, LinkButton)
	self.overlay = spec.Overlay
	self.url = spec.Url

	local button = Theme.Button("", parent)
	button.Name = spec.Icon .. "Link"
	button.BackgroundColor3 = spec.Color or Theme.ACCENT
	-- Mandatory whenever a Theme.Button's fill is overridden: AutoButtonColor
	-- restores the colour it cached on mouse-enter when the cursor leaves, so
	-- a brand fill set at build time survives only until the first hover and
	-- then silently becomes Studio's default grey. Same failure the brush bar
	-- had (see Panel).
	button.AutoButtonColor = false
	local fill = button.BackgroundColor3
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = fill:Lerp(Color3.new(1, 1, 1), 0.15)
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = fill
	end)

	-- Theme.Button defaults to filling its parent (Size = 1,0,1,0), which on
	-- the header's full-width TopRow rendered as a long horizontal pill for
	-- the one frame before the caller's own Size override landed. Locking
	-- the aspect ratio to 1:1 HERE means this button is square no matter what
	-- Size the caller sets it to (width or height, whichever is smaller
	-- wins), so there is no longer a caller-ordering dependency to get wrong.
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.Parent = button
	if spec.Tooltip then
		-- Studio renders a GuiObject's tooltip on hover for free; cheaper and
		-- less intrusive than a label that would need room in the header.
		button.AutoLocalize = false
		pcall(function() (button :: any).Tooltip = spec.Tooltip end)
	end
	self.Frame = button

	local icon = Theme.Icon(button, spec.Icon, 18)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	-- Belt and suspenders: Theme.Icon already sets Fit, restated here because
	-- a stretched (non-uniformly scaled) glyph is exactly the failure mode
	-- this button must never have, brand mark or not.
	icon.ScaleType = Enum.ScaleType.Fit
	-- Opts out of Theme.IconTint: this is a real brand logo on its own brand
	-- fill, so it must not be re-inked with the panel's icon colour.
	icon.ImageColor3 = Color3.new(1, 1, 1)

	-- The button itself is fixed at LINK_SIZE (34px, see Panel) to match the
	-- brush bar's height, but an 18px glyph inside it reads as lost in the
	-- square. Scaling the icon rather than raising its base size keeps
	-- Theme.Icon's default meaningful for every OTHER caller.
	local iconScale = Instance.new("UIScale")
	iconScale.Scale = 1.45
	iconScale.Parent = icon

	button.Activated:Connect(function()
		if self.popup and self.popup:IsOpen() then
			self.popup:Close()
		else
			self:_open()
		end
	end)

	return self
end

function LinkButton:_open()
	if not self.popup then
		self.popup = Popup.new(self.overlay)

		local hint = Theme.Text("Ctrl+C to copy", self.popup.Frame)
		hint.Position = UDim2.fromOffset(PAD, PAD)
		hint.Size = UDim2.new(1, -PAD * 2, 0, HINT_HEIGHT)
		hint.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.DimmedText)
		hint.TextSize = Theme.TEXT_SIZE - 2
		hint.ZIndex = 21

		local field = Theme.TextBox(self.url, self.popup.Frame)
		field.Position = UDim2.fromOffset(PAD, PAD + HINT_HEIGHT)
		field.Size = UDim2.new(1, -PAD * 2, 0, FIELD_HEIGHT)
		field.ZIndex = 21
		self.field = field
	end

	-- Reset every open: the field stays editable (a non-editable TextBox is
	-- not reliably selectable across Studio versions, and selectable is the
	-- whole point here), so anything typed into it last time is discarded
	-- rather than handed out as the link.
	self.field.Text = self.url

	self.popup:OpenAt(self.Frame, POPUP_WIDTH, PAD * 2 + HINT_HEIGHT + FIELD_HEIGHT)

	-- Deferred: CaptureFocus on a frame that was Visible = false this same
	-- frame silently does nothing.
	task.defer(function()
		if not self.popup:IsOpen() then return end
		self.field:CaptureFocus()
		self.field.SelectionStart = 1
		self.field.CursorPosition = #self.url + 1
	end)
end

return LinkButton
