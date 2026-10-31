--!strict
-- Single responsibility: the group control at the top of the panel — picking
-- a group, creating one, deleting one. One row tall, always, in both of its
-- states, because the Panel's pinned header reserves exactly that much and a
-- control that changed height would shove the whole body around.
--
-- It has two faces, swapped in place:
--
--   BROWSE   [◉ Group] [ Default          12 ▾] [+]
--   CREATE   [ name…                ] [Create] [×]
--
-- Creating used to live INSIDE the dropdown's popup, which had it backwards:
-- you opened a *selector* in order to *create*, the field appeared under a
-- row that still read "+ New group" (so the obvious thing to click was the
-- label, not the field), and there were two competing entry points into the
-- same flow. Now creation is its own mode, it owns the full row width instead
-- of being squeezed into a popup, and there is exactly one way in: the [+].
--
-- The one rule that matters here: losing focus NEVER commits or cancels.
-- Clicking [Create] necessarily blurs the text field first, so a field that
-- acted on FocusLost would tear its own UI down before the click it was
-- waiting for could land. Only Enter, [Create] and [×] change state.

local Components = script.Parent.Parent.Components
local Theme = require(Components.Theme)
local Dropdown = require(Components.Dropdown)
local Confirm = require(Components.Confirm)

local GroupSection = {}
GroupSection.__index = GroupSection

local ADD_WIDTH = 26
local CANCEL_WIDTH = 24
local CREATE_WIDTH = 62
local GAP = 6

local function trim(text: string): string
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function GroupSection.new(parent: Instance, order: number, overlay: GuiObject)
	local self = setmetatable({}, GroupSection)
	self.OnChanged = nil :: ((string) -> ())?
	self.OnCreated = nil :: ((string) -> ())?
	self.OnDeleted = nil :: ((string) -> ())?
	self.names = {} :: { [string]: boolean }
	-- Kept alongside `names` because the delete confirmation needs the key
	-- COUNT, not just whether the name exists. Main already computes it for
	-- the dropdown's Detail column; re-deriving it here would mean the view
	-- walking the board itself, which is not its job.
	self.entries = {} :: { [string]: any }

	local frame = Instance.new("Frame")
	frame.Name = "GroupSection"
	frame.Size = UDim2.new(1, 0, 0, Theme.ROW_HEIGHT)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.LayoutOrder = order
	frame.Parent = parent
	self.Frame = frame

	self:_buildBrowse(frame, overlay)
	self:_buildCreate(frame)
	self:_setCreating(false)

	return self
end

function GroupSection:_buildBrowse(parent: Frame, overlay: GuiObject)
	local face = Instance.new("Frame")
	face.Name = "Browse"
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundTransparency = 1
	face.Parent = parent
	self.browseFace = face

	-- Same icon-chip + dimmed-label treatment Row gives its labelled rows.
	-- Built by hand rather than through Row because the CREATE face has to be
	-- able to take over the label's half of the line too — 168px of field is
	-- the difference between comfortably naming a group and not.
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(Theme.LABEL_WIDTH, -Theme.GAP, 1, 0)
	holder.Parent = face

	local holderLayout = Instance.new("UIListLayout")
	holderLayout.FillDirection = Enum.FillDirection.Horizontal
	holderLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	holderLayout.Padding = UDim.new(0, 6)
	holderLayout.SortOrder = Enum.SortOrder.LayoutOrder
	holderLayout.Parent = holder

	local chip = Theme.IconChip(holder, "Group", 20, 12)
	chip.LayoutOrder = 1

	local label = Theme.Text("Group", holder)
	label.Size = UDim2.new(1, -26, 1, 0)
	label.LayoutOrder = 2
	label.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.DimmedText)

	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromScale(Theme.LABEL_WIDTH, 0)
	content.Size = UDim2.new(1 - Theme.LABEL_WIDTH, 0, 1, 0)
	content.Parent = face

	self.dropdown = Dropdown.new(content, {
		Entries = {},
		Overlay = overlay,
		OnDelete = function(name: string)
			self:_askDelete(name)
		end,
	})
	self.dropdown.Frame.Size = UDim2.new(1, -(ADD_WIDTH + GAP), 1, 0)
	self.dropdown.OnChanged = function(name: string)
		if self.OnChanged then self.OnChanged(name) end
	end

	-- One instance reused for every question: Popup already enforces that only
	-- one floating surface is open, so a second one would only ever be dead
	-- weight in the overlay.
	self.confirm = Confirm.new(overlay)

	-- Accent-FILLED, not an accent-coloured glyph on the default button fill:
	-- this is the only creative action in the header and it has to read as
	-- the primary affordance next to a dropdown, not as a third piece of
	-- dropdown furniture.
	local add = Theme.Button("+", content)
	add.Name = "Add"
	add.Size = UDim2.new(0, ADD_WIDTH, 1, 0)
	add.Position = UDim2.new(1, -ADD_WIDTH, 0, 0)
	add.BackgroundColor3 = Theme.ACCENT
	add.TextColor3 = Theme.ACCENT_TEXT
	-- Required for any button with an overridden fill: AutoButtonColor writes
	-- back the colour it cached on mouse-enter when the cursor leaves, which
	-- turns this accent into Studio's default grey after the first hover.
	-- Same failure the brush bar had — see Panel.
	add.AutoButtonColor = false
	add.MouseEnter:Connect(function()
		add.BackgroundColor3 = Theme.ACCENT:Lerp(Color3.new(1, 1, 1), 0.15)
	end)
	add.MouseLeave:Connect(function()
		add.BackgroundColor3 = Theme.ACCENT
	end)
	add.Font = Theme.FONT_BOLD
	add.TextSize = Theme.TEXT_SIZE + 3
	-- Same one-pixel lift the dropdown beside it needs, for the same reason:
	-- Gotham's descent leaves engine-centred text sitting low, and a [+] that
	-- is off-centre inside its own square is the kind of thing you feel before
	-- you can name it. See the note in Dropdown.new.
	local addPad = Instance.new("UIPadding")
	addPad.PaddingBottom = UDim.new(0, 2)
	addPad.Parent = add
	add.Activated:Connect(function()
		self:_setCreating(true)
	end)
end

function GroupSection:_buildCreate(parent: Frame)
	local face = Instance.new("Frame")
	face.Name = "Create"
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundTransparency = 1
	face.Parent = parent
	self.createFace = face

	local reserved = CREATE_WIDTH + CANCEL_WIDTH + GAP * 2

	local box = Theme.TextBox("", face)
	box.Name = "Name"
	box.Size = UDim2.new(1, -reserved, 1, 0)
	box.PlaceholderText = "Group name…"
	box.ClearTextOnFocus = false
	self.nameBox = box

	-- Border, NOT the default Contextual: on a TextBox, Contextual strokes
	-- the GLYPHS, so this outlined the typed text itself instead of the
	-- field. And it only ever appears for a collision — a permanent accent
	-- ring around a field that is merely focused is noise, the caret already
	-- says where you are typing.
	local boxStroke = Instance.new("UIStroke")
	boxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	boxStroke.Color = Theme.DANGER
	boxStroke.Thickness = 1
	boxStroke.Enabled = false
	boxStroke.Parent = box
	self.boxStroke = boxStroke

	local create = Theme.Button("Create", face)
	create.Name = "Confirm"
	create.Size = UDim2.new(0, CREATE_WIDTH, 1, 0)
	create.Position = UDim2.new(1, -(CREATE_WIDTH + CANCEL_WIDTH + GAP), 0, 0)
	create.Font = Theme.FONT_BOLD
	self.createButton = create

	local cancel = Theme.Button("\u{00D7}", face)
	cancel.Name = "Cancel"
	cancel.Size = UDim2.new(0, CANCEL_WIDTH, 1, 0)
	cancel.Position = UDim2.new(1, -CANCEL_WIDTH, 0, 0)
	cancel.BackgroundTransparency = 1
	cancel.AutoButtonColor = false
	cancel.Font = Theme.FONT_BOLD
	cancel.TextSize = Theme.TEXT_SIZE + 2
	cancel.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.DimmedText)

	box:GetPropertyChangedSignal("Text"):Connect(function()
		self:_refreshValidity()
	end)

	-- Enter commits, and only when the name is actually usable. An unusable
	-- name keeps the field open with its reason showing rather than silently
	-- throwing away what was typed.
	box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			self:_commit()
		end
	end)

	create.Activated:Connect(function()
		self:_commit()
	end)
	cancel.Activated:Connect(function()
		self:_setCreating(false)
	end)
end

-- Empty is "not ready yet" and says nothing; a collision is a real error and
-- says so on the button itself, where the eye already is when it finds the
-- button greyed out.
function GroupSection:_validity(): (boolean, string)
	local name = trim(self.nameBox.Text)
	if name == "" then return false, "Create" end
	if self.names[name] then return false, "Exists" end
	return true, "Create"
end

function GroupSection:_refreshValidity()
	local valid, caption = self:_validity()
	local collision = caption == "Exists"

	self.createButton.Text = caption
	-- Never AutoButtonColor here either (see the [+] above): it would cache
	-- the accent fill on hover and restore it over the disabled grey the
	-- moment the name became invalid under the cursor.
	self.createButton.AutoButtonColor = false
	self.createButton.BackgroundColor3 = valid
		and Theme.ACCENT
		or Theme.ButtonFill()
	self.createButton.TextColor3 = valid
		and Theme.ACCENT_TEXT
		or Theme.Color(Enum.StudioStyleGuideColor.DimmedText)

	self.boxStroke.Enabled = collision
end

function GroupSection:_commit()
	local valid = self:_validity()
	if not valid then
		-- Nothing usable to create, but the user is clearly still working on
		-- it: keep the mode and put the caret back where they left it.
		if trim(self.nameBox.Text) ~= "" then
			self.nameBox:CaptureFocus()
		end
		return
	end

	local name = trim(self.nameBox.Text)
	self:_setCreating(false)
	if self.OnCreated then self.OnCreated(name) end
end

function GroupSection:_setCreating(creating: boolean)
	self.creating = creating
	self.browseFace.Visible = not creating
	self.createFace.Visible = creating

	if creating then
		-- Always from empty: an abandoned name must not be waiting in the
		-- field the next time the [+] is pressed.
		self.nameBox.Text = ""
		self:_refreshValidity()
		self.nameBox:CaptureFocus()
	else
		self.nameBox:ReleaseFocus()
	end
end

-- Deleting a group takes its keys with it (see Main for why), which is the
-- kind of thing a × must never do silently. The count is the whole point of
-- the question: "delete a group" and "delete 22 keys off the board" are very
-- different decisions, and the × alone looks like the first one.
function GroupSection:_askDelete(name: string)
	local entry = self.entries[name]
	local count = tonumber(entry and entry.Detail) or 0

	local body
	if count == 0 then
		body = "This group has no keys. Its style will be discarded."
	else
		body = string.format(
			"Its %d key%s will be deleted from the place along with it. Ctrl+Z brings the group and its keys back.",
			count,
			count == 1 and "" or "s"
		)
	end

	self.confirm:Ask(self.dropdown.Frame, {
		Title = string.format("Delete « %s »?", name),
		Body = body,
	}, function()
		if self.OnDeleted then self.OnDeleted(name) end
	end)
end

-- entries: { { Value, Detail, Color } }, built by Main from the registry.
function GroupSection:SetEntries(entries: { any }, current: string)
	self.names = {}
	self.entries = {}
	for _, entry in ipairs(entries) do
		self.names[entry.Value] = true
		self.entries[entry.Value] = entry
	end
	self.dropdown:SetEntries(entries, current)

	-- A name can become taken while the field is open (a group deleted or
	-- added from elsewhere), so the verdict has to be re-read, not cached
	-- from the keystroke that produced it.
	if self.creating then
		self:_refreshValidity()
	end
end

return GroupSection
