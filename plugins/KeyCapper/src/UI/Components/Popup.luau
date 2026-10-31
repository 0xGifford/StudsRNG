--!strict
-- Single responsibility: float a panel over the rest of the UI, anchored to
-- the control that opened it, and close it on an outside click.
--
-- Exists because the group list used to expand INSIDE the layout, shoving
-- every row below it down the page. A popup keeps the panel still.
-- Everything floating lives in one overlay frame (created by the Panel and
-- passed in), so only one popup can be open at a time.

local Theme = require(script.Parent.Theme)
local DragCapture = require(script.Parent.DragCapture)

local Popup = {}
Popup.__index = Popup

local openPopup: any = nil

function Popup.new(overlay: GuiObject)
	local self = setmetatable({}, Popup)
	self.overlay = overlay
	-- When true, an outside click no longer dismisses this popup — only its
	-- own control can close it. For popups you WORK inside: a drag that ends
	-- outside the popup's bounds is indistinguishable from a click meant to
	-- dismiss it, so a colour picker you drag in kept closing itself the
	-- moment you released the mouse. See ColorPicker.
	self.persistent = false

	-- Sits BEHIND the popup (lower ZIndex, inset a couple of pixels on every
	-- side so it only shows as a halo). A popup floating over rows that are
	-- nearly its own colour needs depth, not just an outline, to read as
	-- floating rather than as one more section of the panel.
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.Visible = false
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.55
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 19
	shadow.Parent = overlay
	Theme.Corner(shadow, 8)
	self.shadow = shadow

	local frame = Instance.new("Frame")
	frame.Visible = false
	-- Lifted off Studio's Dropdown colour: unlifted it lands on the panel's
	-- own background in the dark theme and the list bled into the page.
	frame.BackgroundColor3 = Theme.Elevate(Theme.Color(Enum.StudioStyleGuideColor.Dropdown))
	frame.BorderSizePixel = 0
	frame.ZIndex = 20
	frame.Parent = overlay
	Theme.Corner(frame, 6)
	self.Frame = frame

	-- Derived from the fill rather than taken from StudioStyleGuideColor.Border,
	-- which is itself near-invisible against a dark panel. See Theme.Outline.
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Outline(frame.BackgroundColor3)
	stroke.Thickness = 1
	stroke.Parent = frame

	return self
end

-- Anchors under the control, flipping above it when there isn't room below:
-- a popup half off the bottom of a docked widget is unusable.
function Popup:OpenAt(anchor: GuiObject, width: number, height: number)
	if openPopup and openPopup ~= self then
		openPopup:Close()
	end
	openPopup = self

	local overlayPos = self.overlay.AbsolutePosition
	local x = anchor.AbsolutePosition.X - overlayPos.X
	local y = anchor.AbsolutePosition.Y - overlayPos.Y + anchor.AbsoluteSize.Y + 4

	x = math.clamp(x, 0, math.max(self.overlay.AbsoluteSize.X - width, 0))
	if y + height > self.overlay.AbsoluteSize.Y then
		local above = anchor.AbsolutePosition.Y - overlayPos.Y - height - 4
		y = above >= 0 and above or math.max(self.overlay.AbsoluteSize.Y - height, 0)
	end

	self.Frame.Size = UDim2.fromOffset(width, height)
	self.Frame.Position = UDim2.fromOffset(x, y)
	self.Frame.Visible = true

	-- Offset down-right by 3px and grown by 2 on the other sides: a soft edge
	-- all round, heaviest where a light from above would put it.
	self.shadow.Size = UDim2.fromOffset(width + 4, height + 4)
	self.shadow.Position = UDim2.fromOffset(x - 1, y + 1)
	self.shadow.Visible = true

	self.overlay.Visible = true
end

function Popup:Close()
	-- Closing while a drag is still latched (picker dismissed mid-drag) would
	-- leave the capture layer live over a hidden popup.
	DragCapture.Release()
	self.Frame.Visible = false
	self.shadow.Visible = false
	if openPopup == self then
		openPopup = nil
		self.overlay.Visible = false
	end
end

function Popup:IsOpen(): boolean
	return self.Frame.Visible
end

-- Called by the Panel's backdrop button: one click anywhere else dismisses
-- whatever is open, whichever control owns it.
-- force is for tear-downs (the widget being closed), not for dismissals: a
-- persistent popup ignores the backdrop, but it must not survive the panel
-- going away, or the overlay would come back still covering everything.
function Popup.CloseAny(force: boolean?)
	if openPopup and (force or not openPopup.persistent) then
		openPopup:Close()
	end
end

return Popup
