--!strict
-- Single responsibility: a titled, collapsible "card". Groups the rows that
-- belong together (Cap / Text / Sound / Animation) so the panel can be
-- skimmed instead of read.
--
-- Styled as a card (subtle stroke + raised background) rather than a flat
-- unbordered block: on a single dark background colour, a plain block reads
-- as "part of the page", not as a distinct group of controls.

local Theme = require(script.Parent.Theme)

local Section = {}
Section.__index = Section

function Section.new(parent: Instance, order: number, title: string, openByDefault: boolean?)
	local self = setmetatable({}, Section)

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	-- Fill and transparency together: in the light theme Studio's Item IS the
	-- page white, so a translucent card over it has no edge at all and the
	-- panel read as one undifferentiated sheet. See Theme.CardFill.
	local cardFill, cardTransparency = Theme.CardFill()
	frame.BackgroundColor3 = cardFill
	frame.BackgroundTransparency = cardTransparency
	frame.BorderSizePixel = 0
	frame.LayoutOrder = order
	frame.Parent = parent
	Theme.Corner(frame, 10)
	self.Frame = frame

	Theme.Edge(frame, 0.6)

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, Theme.GAP - 1)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = frame

	local header = Instance.new("TextButton")
	header.Size = UDim2.new(1, 0, 0, 22)
	header.BackgroundTransparency = 1
	header.Text = ""
	header.LayoutOrder = 0
	header.AutoButtonColor = false
	header.Parent = frame

	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Horizontal
	headerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	headerLayout.Padding = UDim.new(0, 7)
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Parent = header

	local chevron = Theme.Text("", header)
	chevron.Size = UDim2.fromOffset(10, 20)
	chevron.LayoutOrder = 1
	chevron.TextSize = 11
	chevron.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.DimmedText)
	self.chevron = chevron

	-- Placeholder icon slot for this section's title. Swap Icon_<title>'s
	-- Image property for a real asset later; the Name makes it easy to find.
	local chip = Theme.IconChip(header, title, 22, 13)
	chip.LayoutOrder = 2

	local caption = Theme.Text(title, header)
	caption.Size = UDim2.new(1, -40, 1, 0)
	caption.LayoutOrder = 3
	caption.Font = Theme.FONT_BOLD
	self.caption = caption
	self.title = title

	-- Children live in their own stack so collapsing is one Visible flip
	-- instead of hiding every row one by one.
	local body = Theme.Stack(frame, 1)
	self.Content = body

	self.open = openByDefault ~= false
	header.Activated:Connect(function()
		self:SetOpen(not self.open)
	end)
	self:SetOpen(self.open)

	return self
end

function Section:SetOpen(open: boolean)
	self.open = open
	self.Content.Visible = open
	-- 25BC/25B6 and not the small 25BE/25B8 variants: those render as tofu
	-- in the Studio UI font.
	self.chevron.Text = open and "\u{25BC}" or "\u{25B6}"
end

function Section:SetVisible(visible: boolean)
	self.Frame.Visible = visible
end

return Section
