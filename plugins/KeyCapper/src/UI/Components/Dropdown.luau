--!strict
-- Single responsibility: pick one entry from a list, and optionally remove
-- one. Nothing else — in particular it does NOT know how to create an entry.
--
-- It used to. The group selector needed a way to name a new group, so a text
-- field and a "+ New group" row were bolted inside the popup, which left this
-- module owning a create flow that had nothing to do with picking from a
-- list. That flow now lives in UI.Sections.GroupSection, which is also the
-- only thing that ever needed it.

local Theme = require(script.Parent.Theme)
local Popup = require(script.Parent.Popup)

local Dropdown = {}
Dropdown.__index = Dropdown

local ENTRY_HEIGHT = 22

-- spec: Entries ({ {Value, Text, Detail, Color, Deletable} }), Value,
-- Overlay, OnDelete (nil disables the per-entry × everywhere; an entry with
-- Deletable = false opts out on its own).
function Dropdown.new(parent: Instance, spec: { [string]: any })
	local self = setmetatable({}, Dropdown)
	self.overlay = spec.Overlay
	self.entries = spec.Entries or {}
	-- Falls back to the first entry rather than nil, for the same reason
	-- Segmented does: a control whose stored value matches no entry drew an
	-- open list with NOTHING highlighted, so there was no way to tell what was
	-- currently selected.
	self.value = spec.Value or (self.entries[1] and self.entries[1].Value)
	self.OnChanged = nil :: ((string) -> ())?
	-- Present only when the caller wants entries deletable (the group list);
	-- absent, no × is drawn at all.
	self.OnDelete = spec.OnDelete :: ((string) -> ())?

	local button = Theme.Button("", parent)
	-- Reads as a field you can open, not as a label: in the light theme the
	-- fill alone is a couple of percent off the page white.
	Theme.Edge(button, 1)
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.LayoutOrder = spec.LayoutOrder or 1
	self.Frame = button

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	-- Not symmetry, and not a nudge for its own sake: Gotham's line box carries
	-- a deep descent, so text the engine has centred vertically still sits low
	-- by about a pixel. Taking that pixel off the BOTTOM of the content area is
	-- what puts the cap-height block on the field's real middle. Compared at
	-- 4.5x against 0/2/4/6; 2 is the value that lands.
	pad.PaddingBottom = UDim.new(0, 2)
	pad.Parent = button

	local arrow = Theme.Text("\u{25BC}", button)
	arrow.Size = UDim2.new(0, 12, 1, 0)
	-- Lifted 2px in total, and only 1 of them is written here: the padding
	-- above already shortens this label's parent area and carries the other.
	-- TextYAlignment.Center centres the LINE BOX, not the glyph's ink, and
	-- 25BC sits low in its em square in Gotham, so the triangle read as
	-- sagging below the middle of the field. Measured at 4x, not guessed.
	arrow.Position = UDim2.new(1, -12, 0, -1)
	arrow.TextSize = Theme.TEXT_SIZE - 3
	arrow.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.DimmedText)

	button.Activated:Connect(function()
		if self.popup and self.popup:IsOpen() then
			self.popup:Close()
		else
			self:_open()
		end
	end)

	self:_refreshButton()
	return self
end

function Dropdown:_refreshButton()
	local text = self.value or ""
	for _, entry in ipairs(self.entries) do
		if entry.Value == self.value then
			text = entry.Text or entry.Value
			break
		end
	end
	self.Frame.Text = text
end

function Dropdown:_open()
	if not self.popup then
		self.popup = Popup.new(self.overlay)
		self.list = Instance.new("Frame")
		self.list.Size = UDim2.new(1, -8, 1, -8)
		self.list.Position = UDim2.fromOffset(4, 4)
		self.list.BackgroundTransparency = 1
		self.list.ZIndex = 21
		self.list.Parent = self.popup.Frame

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 2)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = self.list
	end

	self:_fill()
	self.popup:OpenAt(self.Frame, self.Frame.AbsoluteSize.X, #self.entries * (ENTRY_HEIGHT + 2) + 8)
end

function Dropdown:_fill()
	for _, child in ipairs(self.list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local function addEntry(order: number, text: string, color: Color3?): TextButton
		local entry = Theme.Button(text, self.list)
		entry.Size = UDim2.new(1, 0, 0, ENTRY_HEIGHT)
		entry.LayoutOrder = order
		entry.TextXAlignment = Enum.TextXAlignment.Left
		entry.ZIndex = 22
		entry.BackgroundTransparency = 1
		-- Not AutoButtonColor: it caches the fill on mouse-enter and writes it
		-- back on leave, which turns the selected entry's accent fill into
		-- Studio grey the first time the cursor crosses it. Hover is drawn by
		-- hand below so the selection keeps its colour.
		entry.AutoButtonColor = false

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, color and 22 or 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = entry

		if color then
			-- A colour chip per group: with half a dozen groups the names
			-- alone stop being enough to tell them apart at a glance.
			local chip = Instance.new("Frame")
			chip.Size = UDim2.fromOffset(10, 10)
			chip.Position = UDim2.new(0, -16, 0.5, -5)
			chip.BackgroundColor3 = color
			chip.BorderSizePixel = 0
			chip.ZIndex = 23
			chip.Parent = entry
			Theme.Corner(chip, 2)
		end

		return entry
	end

	for index, spec in ipairs(self.entries) do
		local entry = addEntry(index, spec.Text or spec.Value, spec.Color)
		-- Per entry, not per list: an undeletable entry has no × to leave room
		-- for, so its count sits where every other row's would look ragged
		-- against — the counts stay in one column either way.
		local deletable = self.OnDelete ~= nil and spec.Deletable ~= false
		local detailRight = self.OnDelete and -58 or -40
		if spec.Detail then
			local detail = Theme.Text(spec.Detail, entry)
			detail.Size = UDim2.new(0, 40, 1, 0)
			detail.Position = UDim2.new(1, detailRight, 0, 0)
			detail.TextXAlignment = Enum.TextXAlignment.Right
			detail.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.DimmedText)
			detail.ZIndex = 23
		end
		local selected = spec.Value == self.value
		if selected then
			entry.BackgroundTransparency = 0
			entry.BackgroundColor3 = Theme.ACCENT
			entry.TextColor3 = Theme.ACCENT_TEXT
		else
			-- Unselected rows are transparent, so hover is the only thing that
			-- tells the user which one they are about to pick.
			entry.BackgroundColor3 = Theme.Outline(self.popup.Frame.BackgroundColor3)
			entry.MouseEnter:Connect(function()
				entry.BackgroundTransparency = 0.75
			end)
			entry.MouseLeave:Connect(function()
				entry.BackgroundTransparency = 1
			end)
		end
		entry.Activated:Connect(function()
			self.popup:Close()
			self:Set(spec.Value)
			if self.OnChanged then
				self.OnChanged(spec.Value)
			end
		end)

		if deletable then
			local delete = Instance.new("TextButton")
			delete.Size = UDim2.fromOffset(18, ENTRY_HEIGHT)
			delete.Position = UDim2.new(1, -18, 0, 0)
			delete.Text = "\u{00D7}"
			delete.Font = Theme.FONT_BOLD
			delete.TextSize = Theme.TEXT_SIZE + 2
			delete.TextColor3 = Theme.DANGER
			delete.BackgroundTransparency = 1
			delete.AutoButtonColor = false
			delete.ZIndex = 23
			delete.Parent = entry
			delete.Activated:Connect(function()
				if self.OnDelete then
					self.OnDelete(spec.Value)
				end
			end)
		end
	end
end

function Dropdown:SetEntries(entries: { any }, value: string?)
	self.entries = entries
	if value then self.value = value end
	self:_refreshButton()
	if self.popup and self.popup:IsOpen() then
		self:_fill()
	end
end

-- Unknown data (a preset renamed since the group was styled, a hand-edited
-- attribute) falls back to the first entry rather than leaving the list with
-- no highlighted row at all — see the note in Dropdown.new.
function Dropdown:Set(value: string?)
	self.value = value
	if not self:_isKnown(value) then
		self.value = self.entries[1] and self.entries[1].Value
	end
	self:_refreshButton()
	if self.popup and self.popup:IsOpen() then
		self:_fill()
	end
end

function Dropdown:_isKnown(value: any): boolean
	for _, entry in ipairs(self.entries) do
		if entry.Value == value then return true end
	end
	return false
end

return Dropdown
