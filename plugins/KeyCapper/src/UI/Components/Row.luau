--!strict
-- Single responsibility: one line of the panel, laid out as
-- [ label | control ]. Owns no control of its own — it hands back an empty
-- Content frame the caller fills.
--
-- Two columns rather than label-above-field: halves the panel's height, which
-- is what makes the group style readable without endless scrolling.

local Theme = require(script.Parent.Theme)

local Row = {}
Row.__index = Row

-- labelText nil => the control spans the full width (used for buttons and
-- segmented controls that read as their own label). withIcon adds an icon
-- chip before the label, for the handful of rows worth calling out visually
-- (Group, mainly) — most rows don't need one.
function Row.new(parent: Instance, order: number, labelText: string?, height: number?, withIcon: boolean?)
	local self = setmetatable({}, Row)

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, height or Theme.ROW_HEIGHT)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.LayoutOrder = order
	frame.Parent = parent
	self.Frame = frame

	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Parent = frame
	self.Content = content

	if labelText then
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.new(Theme.LABEL_WIDTH, -Theme.GAP, 1, 0)
		holder.Parent = frame

		if withIcon then
			local holderLayout = Instance.new("UIListLayout")
			holderLayout.FillDirection = Enum.FillDirection.Horizontal
			holderLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			holderLayout.Padding = UDim.new(0, 6)
			holderLayout.SortOrder = Enum.SortOrder.LayoutOrder
			holderLayout.Parent = holder

			local chip = Theme.IconChip(holder, labelText, 20, 12)
			chip.LayoutOrder = 1
			self.Icon = chip

			local label = Theme.Text(labelText, holder)
			label.Size = UDim2.new(1, -26, 1, 0)
			label.LayoutOrder = 2
			label.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.DimmedText)
			self.Label = label
		else
			local label = Theme.Text(labelText, holder)
			label.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.DimmedText)
			self.Label = label
		end

		content.Position = UDim2.fromScale(Theme.LABEL_WIDTH, 0)
		content.Size = UDim2.new(1 - Theme.LABEL_WIDTH, 0, 1, 0)
	else
		content.Size = UDim2.fromScale(1, 1)
	end

	return self
end

function Row:SetVisible(visible: boolean)
	self.Frame.Visible = visible
end

return Row
