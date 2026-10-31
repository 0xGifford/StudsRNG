--!strict
-- Single responsibility: everything about the BRUSH itself — which tool,
-- how big, which way round, and what the keys it paints are labelled.
--
-- Kept apart from the style sections because these settings belong to the
-- gesture, not to the group: they change several times a minute, and the user
-- has to be able to find them without scrolling past twenty colour rows.

local Components = script.Parent.Parent.Components
local Row = require(Components.Row)
local Slider = require(Components.Slider)
local Segmented = require(Components.Segmented)
local Theme = require(Components.Theme)
local LabelSource = require(script.Parent.Parent.Parent.Placement.LabelSource)
local Eraser = require(script.Parent.Parent.Parent.Placement.Eraser)

local ToolSection = {}
ToolSection.__index = ToolSection

local ROTATIONS = { "0", "90", "180", "270", "Random" }
local MAX_BRUSH_SIZE = 16

function ToolSection.new(parent: Instance, order: number)
	local self = setmetatable({}, ToolSection)

	self.OnToolChanged = nil :: ((string) -> ())?
	self.OnSizeChanged = nil :: ((number) -> ())?
	self.OnRotationChanged = nil :: ((string) -> ())?
	self.OnEraseScopeChanged = nil :: ((string) -> ())?
	self.OnLabelModeChanged = nil :: ((string) -> ())?
	self.OnLabelChanged = nil :: ((string) -> ())?
	self.OnCharsetChanged = nil :: ((string) -> ())?

	local toolRow = Row.new(parent, order, nil)
	self.tool = Segmented.new(toolRow.Content, {
		Options = { "Paint", "Erase" },
		Icons = { "Paint", "Erase" },
	})

	local sizeRow = Row.new(parent, order + 1, "Brush size")
	self.size = Slider.new(sizeRow.Content, {
		Min = 1, Max = MAX_BRUSH_SIZE, Step = 1, Value = 1,
		Format = function(value: number) return string.format("%d\u{00D7}%d", value, value) end,
	})
	self.size.OnChanged = function(value)
		if self.OnSizeChanged then self.OnSizeChanged(value) end
	end

	-- "Random" is a 5th option, not a numeric step: rather than force it into
	-- the 0-3 range the callback used to carry, the raw string goes out and
	-- Main decides what it means (Brush.SetRotation vs SetRotationRandom).
	local rotationRow = Row.new(parent, order + 2, "Rotation (R)")
	self.rotation = Segmented.new(rotationRow.Content, { Options = ROTATIONS })
	self.rotation.OnChanged = function(value)
		if self.OnRotationChanged then
			self.OnRotationChanged(value)
		end
	end

	-- Erase only. Scoping to the current group is the default because the
	-- accident this guards against — wiping a whole keyboard while cleaning
	-- up one row — is not one you notice until several strokes later.
	local scopeRow = Row.new(parent, order + 3, "Erase")
	self.scopeRow = scopeRow
	self.scope = Segmented.new(scopeRow.Content, {
		Options = Eraser.SCOPES,
		Labels = { Group = "This group", All = "Any key" },
	})
	self.scope.OnChanged = function(value)
		if self.OnEraseScopeChanged then self.OnEraseScopeChanged(value) end
	end

	local labelRow = Row.new(parent, order + 4, "Label")
	self.labelRow = labelRow
	self.labelMode = Segmented.new(labelRow.Content, { Options = LabelSource.MODES, Value = "Random" })

	local textRow = Row.new(parent, order + 5, "Character")
	self.textRow = textRow
	local labelBox = Theme.TextBox("A", textRow.Content)
	self.labelBox = labelBox
	labelBox.FocusLost:Connect(function()
		local value = labelBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if value == "" then value = "A" end
		value = value:upper()
		labelBox.Text = value
		if self.OnLabelChanged then self.OnLabelChanged(value) end
	end)

	local charsetRow = Row.new(parent, order + 6, "Characters")
	self.charsetRow = charsetRow
	self.charset = Segmented.new(charsetRow.Content, { Options = LabelSource.CharsetNames(), Value = LabelSource.DEFAULT_CHARSET })
	self.charset.OnChanged = function(value)
		if self.OnCharsetChanged then self.OnCharsetChanged(value) end
	end

	self.labelMode.OnChanged = function(value)
		self:_refresh()
		if self.OnLabelModeChanged then self.OnLabelModeChanged(value) end
	end
	self.tool.OnChanged = function(value)
		self:_refresh()
		if self.OnToolChanged then self.OnToolChanged(value) end
	end

	self:_refresh()
	return self
end

ToolSection.ROW_COUNT = 7

-- Only the rows the current tool actually uses. Erasing has nothing to do
-- with what a key is labelled, so those rows go away entirely.
function ToolSection:_refresh()
	local erasing = self.tool.value == "Erase"
	self.scopeRow:SetVisible(erasing)
	self.labelRow:SetVisible(not erasing)
	self.textRow:SetVisible(not erasing and self.labelMode.value == "Fixed")
	self.charsetRow:SetVisible(not erasing and self.labelMode.value == "Random")
end

-- Rotation can change from the R key, so the section has to be able to follow
-- a value it did not originate.
function ToolSection:SetRotation(steps: number)
	-- "Random" is a MODE, not a rotation the brush can report back. Following
	-- the brush there would move the highlight onto whatever angle the last
	-- key happened to get, so the row would claim a fixed rotation was
	-- selected while the brush was still randomising.
	if self.rotation.value == "Random" then return end
	self.rotation:Set(ROTATIONS[(steps % 4) + 1])
end

return ToolSection
