--!strict
-- Single responsibility: the plugin's dock widget — its shell, its layout,
-- and the composition of the sections that fill it. Knows nothing about
-- placement, groups or colours: it exposes callbacks that Main wires up.
--
-- Layout, in order of how often a control is touched:
--   * BRUSH ON/OFF, pinned at the top, never scrolls. It is the feature.
--   * the group selector, pinned right under it: everything below is scoped
--     to it, and that has to be visible without scrolling back up.
--   * the tool settings, then the group's style in collapsible sections.
--   * a status line pinned at the bottom.
--
-- Anything that floats (dropdown lists, colour pickers) lives in a single
-- overlay frame so only one can be open and an outside click dismisses it.

local Components = script.Parent.Components
local Theme = require(Components.Theme)
local Row = require(Components.Row)
local Section = require(Components.Section)
local Popup = require(Components.Popup)
local LinkButton = require(Components.LinkButton)
local DragCapture = require(Components.DragCapture)

local Sections = script.Parent.Sections
local GroupSection = require(Sections.GroupSection)
local ToolSection = require(Sections.ToolSection)
local ColorChannel = require(Sections.ColorChannel)
local TextStyleSection = require(Sections.TextStyleSection)
local SoundSection = require(Sections.SoundSection)
local AnimationSection = require(Sections.AnimationSection)
local OthersSection = require(Sections.OthersSection)

local Panel = {}
Panel.__index = Panel

local Constants = require(script.Parent.Parent.Constants)

local WIDGET_ID = "KeyCapperPanel"
-- The brush bar shares its line with the Discord button now, so it gives up
-- both a little height and the width of that square. It stays by far the
-- largest control in the header, which is the point — it just no longer
-- needs to be the ONLY thing on its line to say so.
local BRUSH_HEIGHT = 34
local LINK_SIZE = BRUSH_HEIGHT
local STATUS_HEIGHT = 18
-- Brush bar + group row + the padding around them: where the scroll starts.
local HEADER_HEIGHT = Theme.PADDING + BRUSH_HEIGHT + Theme.GAP + Theme.ROW_HEIGHT + Theme.PADDING

function Panel.new(pluginInstance: Plugin)
	local self = setmetatable({}, Panel)

	-- Callbacks. Main assigns these; the Panel never calls into logic itself.
	self.OnBrushToggled = nil :: ((boolean) -> ())?
	self.OnToolChanged = nil :: ((string) -> ())?
	self.OnSizeChanged = nil :: ((number) -> ())?
	self.OnRotationChanged = nil :: ((number) -> ())?
	self.OnEraseScopeChanged = nil :: ((string) -> ())?
	self.OnLabelModeChanged = nil :: ((string) -> ())?
	self.OnLabelChanged = nil :: ((string) -> ())?
	self.OnCharsetChanged = nil :: ((string) -> ())?
	self.OnGroupChanged = nil :: ((string) -> ())?
	self.OnGroupDeleted = nil :: ((string) -> ())?
	-- One callback for every group attribute: the Panel does not know what a
	-- Color or a SoundIds means, it just forwards the edit.
	self.OnGroupValueChanged = nil :: ((string, any) -> ())?
	-- Not a group edit: these flip game-side settings shared by every group
	-- (RuntimeSource.Settings), not a group's own Configuration.
	self.OnSettingChanged = nil :: ((string, any) -> ())?

	self.brushActive = false
	self.brushHovered = false

	-- 320 wide: at 240 the two-column rows truncate their labels and a
	-- three-option segmented control stops being readable.
	local info = DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Float,
		false, -- not enabled on creation
		false, -- don't override the restored state
		320, 560, -- floating size
		300, 420 -- minimum size
	)

	local widget = pluginInstance:CreateDockWidgetPluginGui(WIDGET_ID, info)
	widget.Title = "KeyCapper"
	widget.Name = WIDGET_ID
	widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self.widget = widget

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Theme.Color(Enum.StudioStyleGuideColor.MainBackground)
	background.BorderSizePixel = 0
	background.Parent = widget

	-- Built first so every control that opens a popup gets it at construction.
	-- Order of creation does not affect stacking: the widget is in Sibling
	-- ZIndex mode and the overlay sits at ZIndex 10.
	self:_buildOverlay(background)
	self:_buildHeader(background)
	self:_buildBody(background)
	self:_buildStatus(background)

	-- Closing the widget must never leave the brush running in the background.
	widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not widget.Enabled then
			DragCapture.Release()
			-- Forced: a persistent popup (the colour picker) ignores an outside
			-- click, but the widget closing is a tear-down, not a dismissal.
			Popup.CloseAny(true)
		end
		if not widget.Enabled and self.brushActive then
			self:SetBrushActive(false)
			if self.OnBrushToggled then
				self.OnBrushToggled(false)
			end
		end
	end)

	return self
end

function Panel:_buildHeader(background: Frame)
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	-- A faintly raised card rather than flat-on-background: separates the
	-- "always visible" controls from the scrolling body below, on top of
	-- the hairline added at the end of this function.
	-- Same card treatment as a Section, for the same reason: in the light
	-- theme Studio's Item IS the page white, so a translucent header sat on
	-- an identical white and the pinned controls read as loose text at the
	-- top of the scroll rather than as a bar of their own.
	local headerFill, headerTransparency = Theme.CardFill()
	header.BackgroundColor3 = headerFill
	header.BackgroundTransparency = headerTransparency
	header.BorderSizePixel = 0
	header.ZIndex = 2
	header.Parent = background

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, Theme.PADDING)
	pad.PaddingLeft = UDim.new(0, Theme.PADDING)
	pad.PaddingRight = UDim.new(0, Theme.PADDING)
	pad.Parent = header

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, Theme.GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = header

	-- Brush and Discord share one line: [ BRUSH: OFF ][D]
	local topRow = Instance.new("Frame")
	topRow.Name = "TopRow"
	topRow.Size = UDim2.new(1, 0, 0, BRUSH_HEIGHT)
	topRow.BackgroundTransparency = 1
	topRow.LayoutOrder = 1
	topRow.Parent = header

	-- Taller than anything else, colour-coded, and with a subtle vertical
	-- gradient + white icon chip: this is the one control the user reaches
	-- for constantly, it must not read as just another button.
	local brushButton = Theme.Button("", topRow)
	brushButton.Size = UDim2.new(1, -(LINK_SIZE + Theme.GAP), 1, 0)
	brushButton.LayoutOrder = 1
	-- THE reason every previous attempt to colour this button failed.
	-- AutoButtonColor caches BackgroundColor3 when the cursor ENTERS the
	-- button, and writes that cached value back when it leaves. The toggle is
	-- clicked with the cursor on the button, so SetBrushActive's fill was
	-- being applied mid-hover and then reverted to Studio's default button
	-- grey the moment the mouse moved away — a grey that is within a few
	-- percent of the header card behind it. The colour in the source was
	-- always correct; it just never survived the first hover.
	-- Hover feedback is done by hand below instead, on the stroke, which
	-- AutoButtonColor never touched anyway.
	brushButton.AutoButtonColor = false
	brushButton.MouseEnter:Connect(function()
		self.brushHovered = true
		self:_refreshBrushGradient(self.brushActive)
	end)
	brushButton.MouseLeave:Connect(function()
		self.brushHovered = false
		self:_refreshBrushGradient(self.brushActive)
	end)
	brushButton.Activated:Connect(function()
		self:SetBrushActive(not self.brushActive)
		if self.OnBrushToggled then
			self.OnBrushToggled(self.brushActive)
		end
	end)
	self.brushButton = brushButton

	local brushGradient = Instance.new("UIGradient")
	brushGradient.Rotation = 90
	brushGradient.Parent = brushButton
	self.brushGradient = brushGradient

	-- Kept visible (not just a faint highlight) when OFF: it is the only
	-- thing that reads as "button" once the fill matches the header card.
	local brushStroke = Instance.new("UIStroke")
	brushStroke.Color = Color3.new(1, 1, 1)
	brushStroke.Transparency = 0.85
	brushStroke.Thickness = 1
	brushStroke.Parent = brushButton
	self.brushStroke = brushStroke

	-- Icon + text, centred as a pair rather than the button's own centred
	-- text: this is the one control every other row in the panel takes its
	-- cue from, it earns a slightly custom layout.
	local brushInner = Instance.new("Frame")
	brushInner.Size = UDim2.fromScale(1, 1)
	brushInner.BackgroundTransparency = 1
	brushInner.Parent = brushButton
	local brushLayout = Instance.new("UIListLayout")
	brushLayout.FillDirection = Enum.FillDirection.Horizontal
	brushLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	brushLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	brushLayout.Padding = UDim.new(0, 8)
	brushLayout.Parent = brushInner

	-- White chip (not the accent-tinted one Section/Row use): the button's
	-- own fill IS the accent colour here, so a same-colour chip would
	-- disappear into it.
	local brushChip = Instance.new("Frame")
	brushChip.Size = UDim2.fromOffset(26, 26)
	brushChip.BackgroundColor3 = Color3.new(1, 1, 1)
	brushChip.BackgroundTransparency = 0.82
	brushChip.BorderSizePixel = 0
	brushChip.LayoutOrder = 1
	brushChip.Parent = brushInner
	Theme.Corner(brushChip, 13)

	-- Opts out of Theme.IconTint: this glyph sits on the button's own red/green
	-- fill in either theme, where white is the only colour that reads.
	local brushIcon = Theme.Icon(brushChip, "Brush", 15)
	brushIcon.ImageColor3 = Color3.new(1, 1, 1)
	brushIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	brushIcon.Position = UDim2.fromScale(0.5, 0.5)
	self.brushIcon = brushIcon

	local brushLabel = Theme.Text("BRUSH: OFF", brushInner)
	brushLabel.Size = UDim2.new(0, 0, 1, 0)
	brushLabel.AutomaticSize = Enum.AutomaticSize.X
	brushLabel.LayoutOrder = 2
	brushLabel.Font = Theme.FONT_BOLD
	brushLabel.TextSize = Theme.TEXT_SIZE + 3
	self.brushLabel = brushLabel

	-- In Discord's own brand colour rather than the panel's accent: it points
	-- somewhere outside the plugin, and reading as "not one of the tools" is
	-- exactly what stops it competing with the brush beside it.
	local discord = LinkButton.new(topRow, {
		Icon = "Discord",
		Url = Constants.DISCORD_URL,
		Overlay = self.overlay,
		Color = Theme.DISCORD,
		Tooltip = "KeyCapper Discord",
	})
	discord.Frame.Size = UDim2.fromOffset(LINK_SIZE, LINK_SIZE)
	discord.Frame.Position = UDim2.new(1, -LINK_SIZE, 0, 0)

	-- Owns the whole group line (label, selector, create mode, delete) and
	-- keeps it exactly one row tall in every state, which is what lets
	-- HEADER_HEIGHT above stay a constant.
	self.groupSection = GroupSection.new(header, 2, self.overlay)
	self.groupSection.OnChanged = function(name)
		if self.OnGroupChanged then self.OnGroupChanged(name) end
	end
	-- Creating and picking land on the same callback: Main treats a group as
	-- existing the moment it is named (GroupRegistry.Ensure), so "selected
	-- this group" is the whole of what either gesture means here.
	self.groupSection.OnCreated = function(name)
		if self.OnGroupChanged then self.OnGroupChanged(name) end
	end
	self.groupSection.OnDeleted = function(name)
		if self.OnGroupDeleted then self.OnGroupDeleted(name) end
	end

	-- Hairline between the pinned header and the scrolling body: without it
	-- the two blend into the same flat background.
	--
	-- Parented to the BACKGROUND, not to the header. The header runs a
	-- UIListLayout, which lays out every GuiObject child it has — including
	-- this one, at the LayoutOrder 0 it never set, i.e. FIRST. Its Position of
	-- (0,0,1,0) was overridden and it ate 1px plus a full 8px gap at the top of
	-- the stack, pushing the brush bar and the group row 9px down: the group
	-- row ended at y=85 in an 84px header, hanging a pixel below the header's
	-- own bottom edge. Measured, and the reason "the group row sits too low"
	-- survived every attempt to fix it inside the row itself.
	local separator = Instance.new("Frame")
	separator.Size = UDim2.new(1, 0, 0, 1)
	separator.Position = UDim2.fromOffset(0, HEADER_HEIGHT)
	separator.BackgroundColor3 = Theme.Color(Enum.StudioStyleGuideColor.Separator)
	separator.BorderSizePixel = 0
	separator.ZIndex = 2
	separator.Parent = background

	-- Forces the initial fill/stroke/label to the OFF state: Theme.Button()
	-- leaves brushButton at Studio's default button colour otherwise, and
	-- SetBrushActive is only ever called from a toggle or a deactivation
	-- event afterwards — never on first build. Without this call the button
	-- was invisible against the header on every plugin reload until clicked.
	self:SetBrushActive(false)
end

function Panel:_buildBody(background: Frame)
	local list = Instance.new("ScrollingFrame")
	-- The 2px the padding below takes back on each side is given back here, so
	-- the cards keep the same margin against the panel edge as before.
	list.Size = UDim2.new(1, -(Theme.PADDING - 2) * 2, 1, -HEADER_HEIGHT - STATUS_HEIGHT - Theme.PADDING)
	list.Position = UDim2.fromOffset(Theme.PADDING - 2, HEADER_HEIGHT)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	-- The scrollbar must take its 6px OUT of the layout instead of floating on
	-- top of it. Left alone (the default, ScrollBarInset.None) it overlaps the
	-- rightmost 6px of every row, which is exactly where the cards' right-hand
	-- outline is — so that edge still read as cut even once the clipping on the
	-- left was fixed. It was being painted over, not clipped.
	list.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	list.Parent = background

	-- A ScrollingFrame ALWAYS clips its descendants, and a UIStroke is drawn
	-- outside the frame it belongs to. The section cards are a full 1.0 of this
	-- frame's width, so their outline was being shaved off flush against both
	-- edges: the cards looked like they had a top and a bottom line and no
	-- sides. This is the room that outline needs to exist — it is not padding
	-- for looks, and taking it out brings the cut edges straight back.
	local inset = Instance.new("UIPadding")
	inset.PaddingLeft = UDim.new(0, 2)
	inset.PaddingRight = UDim.new(0, 2)
	-- Top is not the 2px the other three sides need for the outline: the first
	-- section sat almost flush against the pinned group row above it, with no
	-- room to read as a separate block. This is that breathing space.
	inset.PaddingTop = UDim.new(0, 10)
	inset.PaddingBottom = UDim.new(0, 2)
	inset.Parent = list

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, Theme.GAP + 1)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local toolBlock = Section.new(list, 1, "Tool")
	self.tool = ToolSection.new(toolBlock.Content, 1)

	-- Says out loud what the sections below are: edits to a GROUP, not to a
	-- key. The whole plugin rests on that distinction.
	local caption = Row.new(list, 2, nil, 16)
	local captionText = Theme.Text("", caption.Content)
	captionText.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.DimmedText)
	captionText.Font = Theme.FONT_BOLD
	self.captionText = captionText

	local capBlock = Section.new(list, 3, "Cap color")
	self.capChannel = ColorChannel.new(capBlock.Content, 1, self.overlay, {
		ModeKey = "CapColorMode",
		SolidKey = "Color",
		AxisKey = "GradientAxis",
		GradientKey = "GradientColor",
		HueKey = "CapRandomHue",
		SatKey = "CapRandomSat",
		ValueKey = "CapRandomValue",
	})

	local textBlock = Section.new(list, 4, "Label", false)
	self.textChannel = ColorChannel.new(textBlock.Content, 1, self.overlay, {
		ModeKey = "TextColorMode",
		SolidKey = "TextColor",
		AxisKey = "TextGradientAxis",
		GradientKey = "TextGradientColor",
		HueKey = "TextRandomHue",
		SatKey = "TextRandomSat",
		ValueKey = "TextRandomValue",
	})
	self.textStyle = TextStyleSection.new(textBlock.Content, ColorChannel.ROW_COUNT + 1, self.overlay)

	local soundBlock = Section.new(list, 5, "Sound", false)
	self.sound = SoundSection.new(soundBlock.Content, 1)

	local feelBlock = Section.new(list, 6, "Feel", false)
	self.animation = AnimationSection.new(feelBlock.Content, 1)

	-- Not scoped to "STYLE OF <group>" above: it lives outside the group
	-- system entirely, so it sits in its own section rather than under it.
	local othersBlock = Section.new(list, 7, "Others", false)
	self.others = OthersSection.new(othersBlock.Content, 1)
	self.others.OnValueChanged = function(key, value)
		if self.OnSettingChanged then
			self.OnSettingChanged(key, value)
		end
	end

	self:_wireSections()
end

-- Every style section speaks the same (attributeKey, value) language, so they
-- all forward to the same callback. Adding a section is one line here.
function Panel:_wireSections()
	local function forward(key: string, value: any)
		if self.OnGroupValueChanged then
			self.OnGroupValueChanged(key, value)
		end
	end

	for _, section in ipairs({ self.capChannel, self.textChannel, self.textStyle, self.sound, self.animation }) do
		section.OnValueChanged = forward
	end

	self.tool.OnToolChanged = function(value)
		if self.OnToolChanged then self.OnToolChanged(value) end
	end
	self.tool.OnSizeChanged = function(value)
		if self.OnSizeChanged then self.OnSizeChanged(value) end
	end
	self.tool.OnRotationChanged = function(steps)
		if self.OnRotationChanged then self.OnRotationChanged(steps) end
	end
	self.tool.OnEraseScopeChanged = function(value)
		if self.OnEraseScopeChanged then self.OnEraseScopeChanged(value) end
	end
	self.tool.OnLabelModeChanged = function(value)
		if self.OnLabelModeChanged then self.OnLabelModeChanged(value) end
	end
	self.tool.OnLabelChanged = function(value)
		if self.OnLabelChanged then self.OnLabelChanged(value) end
	end
	self.tool.OnCharsetChanged = function(value)
		if self.OnCharsetChanged then self.OnCharsetChanged(value) end
	end
end

function Panel:_buildStatus(background: Frame)
	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, -Theme.PADDING * 2, 0, STATUS_HEIGHT)
	holder.Position = UDim2.new(0, Theme.PADDING, 1, -STATUS_HEIGHT)
	holder.BackgroundTransparency = 1
	holder.Parent = background

	local status = Theme.Text("", holder)
	status.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.DimmedText)
	status.TextSize = Theme.TEXT_SIZE - 1
	self.status = status
end

-- One shared floating layer: a transparent backdrop that swallows the click
-- that dismisses a popup. DragCapture no longer needs a layer registered
-- here — it tracks drags through UserInputService now, see that module.
function Panel:_buildOverlay(background: Frame)
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 1
	overlay.Visible = false
	overlay.ZIndex = 10
	overlay.Parent = background
	self.overlay = overlay

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundTransparency = 1
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.ZIndex = 10
	backdrop.Parent = overlay
	backdrop.Activated:Connect(function()
		Popup.CloseAny()
	end)
end

-- The OFF state is deliberately a COLOUR of its own, not the Studio button
-- colour. That default sits within a few percent of the header card behind
-- it, so the control disappeared into the panel exactly when it most needed
-- to be found — it is how the plugin is switched on, and it spends most of
-- its life OFF. Red (Theme.DANGER) reads unmistakably as "off/inactive" and
-- stays unmistakably distinct from the green ON, unlike the earlier slate
-- which was too close to the header card's own tint to notice.
local BRUSH_OFF_FILL = Theme.DANGER

function Panel:_refreshBrushGradient(active: boolean)
	-- UIGradient.Transparency is the BUTTON's transparency along the gradient,
	-- NOT "how strongly the gradient tints". Setting it to 1 for the OFF state
	-- — meaning to say "no gradient here" — rendered the fill fully see-through
	-- instead, so OFF showed the panel behind it whatever BRUSH_OFF_FILL was
	-- set to. That is the bug that made this button look uncoloured through
	-- every attempt to recolour it: the colour was applied, then erased.
	--
	-- It stays at 0 in both states now. "No gradient" is expressed the only
	-- way it can be: a Color of pure white, which multiplies BackgroundColor3
	-- by 1 and leaves the fill exactly as SetBrushActive set it.
	self.brushGradient.Transparency = NumberSequence.new(0)
	self.brushGradient.Color = active
		and ColorSequence.new(Color3.fromRGB(88, 198, 138), Color3.fromRGB(48, 148, 98))
		-- Same subtle top-lit shading as ON, expressed as a multiplier so it
		-- rides on top of the red rather than replacing it.
		or ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 215, 215))
	-- A bright accent border on top of the fill: two independent cues that
	-- this is a control, so it survives whatever the user's Studio theme does.
	self.brushStroke.Color = Color3.new(1, 1, 1)
	self.brushStroke.Transparency = active and 0.85 or 0.1
	self.brushStroke.Thickness = active and 1 or 2
	-- Hover: brighten the outline rather than the fill. The fill is the state
	-- (red = off, green = on) and must not wobble.
	if self.brushHovered then
		self.brushStroke.Transparency = math.max(self.brushStroke.Transparency - 0.35, 0)
	end
end

function Panel:SetBrushActive(active: boolean)
	self.brushActive = active
	self.brushLabel.Text = active and "BRUSH: ON" or "BRUSH: OFF"
	self.brushButton.BackgroundColor3 = active and Theme.OK or BRUSH_OFF_FILL
	-- White in both states: ButtonText is a dimmed grey meant for flat Studio
	-- buttons and reads as disabled on a filled one.
	self.brushLabel.TextColor3 = Theme.ACCENT_TEXT
	self:_refreshBrushGradient(active)
end

-- entries: { { Value, Detail, Color } }, built by Main from the registry —
-- the Panel never reads the registry itself, it only renders what it is given.
function Panel:SetGroups(entries: { any }, current: string)
	self.groupSection:SetEntries(entries, current)
	self.captionText.Text = string.format("STYLE OF \u{00AB} %s \u{00BB}", current)
end

-- Loads a group's stored values into the fields. Called when the current group
-- changes, so the panel always shows the group being edited, never stale
-- values. Takes a plain {attributeKey -> value} table (built by Main straight
-- from GroupRegistry) rather than positional args: the attribute set keeps
-- growing, and a 12+ argument positional list was already unreadable.
function Panel:ShowGroupValues(values: { [string]: any })
	self.capChannel:Show(values)
	self.textChannel:Show(values)
	self.textStyle:Show(values)
	self.sound:Show(values)
	self.animation:Show(values)
end

-- Not part of ShowGroupValues: this reflects plugin-wide settings, not
-- something that changes when the current group does.
function Panel:SetOthers(values: { [string]: any })
	self.others:Show(values)
end

-- Rotation can come from the R key, not just from the panel.
function Panel:SetRotation(steps: number)
	self.tool:SetRotation(steps)
end

function Panel:SetStatus(text: string)
	self.status.Text = text
end

function Panel:Toggle()
	self.widget.Enabled = not self.widget.Enabled
end

return Panel
