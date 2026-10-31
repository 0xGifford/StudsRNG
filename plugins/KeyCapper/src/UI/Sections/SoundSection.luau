--!strict
-- Single responsibility: edit the group's sound list.
--
-- Stored as a comma-separated string (that is the attribute's shape), but
-- never SHOWN as one: a text field holding "123,456,789" is unreadable and
-- one stray comma silently drops a sound. Here each id is its own row with
-- its own remove button.

local Components = script.Parent.Parent.Components
local Theme = require(Components.Theme)
local Row = require(Components.Row)
local Slider = require(Components.Slider)
local SoundId = require(script.Parent.Parent.Parent.RuntimeSource.Style.SoundId)

local SoundSection = {}
SoundSection.__index = SoundSection

local KEY = "SoundIds"

-- Kept RAW on purpose: an entry the game will reject still has to come back
-- into the field so it can be corrected. Judging it is SoundId's job, and it
-- happens per row at build time, not here.
local function split(csv: string): { string }
	local ids: { string } = {}
	for piece in tostring(csv):gmatch("[^,]+") do
		local trimmed = SoundId.Trim(piece)
		if trimmed ~= "" then
			table.insert(ids, trimmed)
		end
	end
	return ids
end

function SoundSection.new(parent: Instance, order: number)
	local self = setmetatable({}, SoundSection)
	self.ids = {} :: { string }
	self.OnValueChanged = nil :: ((string, any) -> ())?

	-- The id rows are rebuilt on every change, so they live in their own
	-- stack: rebuilding must not take the pitch row with it.
	local stack = Theme.Stack(parent, order)
	self.stack = stack

	local addRow = Row.new(parent, order + 1, nil)
	local add = Theme.Button("", addRow.Content)
	add.Activated:Connect(function()
		table.insert(self.ids, "")
		self:_rebuild()
	end)

	local addInner = Instance.new("Frame")
	addInner.Size = UDim2.fromScale(1, 1)
	addInner.BackgroundTransparency = 1
	addInner.Parent = add
	local addLayout = Instance.new("UIListLayout")
	addLayout.FillDirection = Enum.FillDirection.Horizontal
	addLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	addLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	addLayout.Padding = UDim.new(0, 5)
	addLayout.Parent = addInner

	local addIcon = Theme.Icon(addInner, "AddSound", 14)
	addIcon.LayoutOrder = 1

	local addLabel = Theme.Text("Add sound", addInner)
	addLabel.Size = UDim2.fromOffset(0, 20)
	addLabel.AutomaticSize = Enum.AutomaticSize.X
	addLabel.LayoutOrder = 2
	addLabel.TextColor3 = Theme.ACCENT

	local volumeRow = Row.new(parent, order + 2, "Volume")
	-- Max 5, not 1: 1 is only Roblox's DEFAULT Sound.Volume, not its ceiling
	-- (the property goes to 10). A board in a noisy scene needs the headroom.
	self.volume = Slider.new(volumeRow.Content, {
		Min = 0, Max = 5, Step = 0.05,
		Format = function(value: number) return string.format("%d%%", math.round(value * 100)) end,
	})
	self.volume.OnChanged = function(value)
		if self.OnValueChanged then self.OnValueChanged("Volume", value) end
	end

	local pitchRow = Row.new(parent, order + 3, "Pitch jitter")
	self.pitch = Slider.new(pitchRow.Content, {
		Min = 0, Max = 0.5, Step = 0.01,
		Format = function(value: number) return string.format("%d%%", math.round(value * 100)) end,
	})
	self.pitch.OnChanged = function(value)
		if self.OnValueChanged then self.OnValueChanged("PitchJitter", value) end
	end

	self:_rebuild()
	return self
end

SoundSection.ROW_COUNT = 4

function SoundSection:_commit()
	if self.OnValueChanged then
		self.OnValueChanged(KEY, table.concat(self.ids, ","))
	end
end

function SoundSection:_rebuild()
	for _, child in ipairs(self.stack:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end

	if #self.ids == 0 then
		local empty = Row.new(self.stack, 1, nil)
		local hint = Theme.Text("Default sound", empty.Content)
		hint.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.DimmedText)
		return
	end

	-- Two rows per id at most, so the order has to leave room: an id's field
	-- and the message that may sit under it are one unit.
	for index, id in ipairs(self.ids) do
		local row = Row.new(self.stack, index * 2, nil)

		local box = Theme.TextBox(id, row.Content)
		box.Size = UDim2.new(1, -26, 1, 0)
		-- Says both accepted forms rather than only the canonical one: the
		-- number alone is what the toolbox gives you, and it works.
		box.PlaceholderText = "number or rbxassetid://"
		box.FocusLost:Connect(function()
			-- The canonical form is stored when there is one, so typing "123"
			-- and seeing it become "rbxassetid://123" is itself the
			-- confirmation that it was understood. Unusable text is kept
			-- verbatim so it can be fixed rather than silently swallowed.
			local parsed = SoundId.Parse(box.Text)
			self.ids[index] = parsed or SoundId.Trim(box.Text)
			self:_rebuild()
			self:_commit()
		end)

		local _, problem = SoundId.Parse(id)
		if problem then
			-- Border, not the default Contextual: on a TextBox, Contextual
			-- strokes the GLYPHS. Same reason GroupSection's name field does it.
			local stroke = Instance.new("UIStroke")
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Color = Theme.DANGER
			stroke.Thickness = 1
			stroke.Parent = box

			-- The reason goes UNDER the field it belongs to, not in the status
			-- line: with several ids listed there would be no way to tell which
			-- one a single shared message was about.
			local messageRow = Row.new(self.stack, index * 2 + 1, nil, 28)
			local message = Theme.Text(problem, messageRow.Content)
			message.TextColor3 = Theme.DANGER
			message.TextSize = Theme.TEXT_SIZE - 2
			-- Wrapped, not truncated: these run past the panel's width and the
			-- end of the sentence is the half that says what to do about it.
			message.TextWrapped = true
			message.TextTruncate = Enum.TextTruncate.None
			message.TextYAlignment = Enum.TextYAlignment.Top
		end

		local remove = Theme.Button("\u{00D7}", row.Content)
		remove.Size = UDim2.new(0, 22, 1, 0)
		remove.Position = UDim2.new(1, -22, 0, 0)
		remove.TextColor3 = Theme.DANGER
		remove.Activated:Connect(function()
			table.remove(self.ids, index)
			self:_rebuild()
			self:_commit()
		end)
	end
end

function SoundSection:Show(values: { [string]: any })
	self.ids = split(values[KEY] or "")
	self:_rebuild()
	self.volume:Set(values.Volume)
	self.pitch:Set(values.PitchJitter)
end

return SoundSection
