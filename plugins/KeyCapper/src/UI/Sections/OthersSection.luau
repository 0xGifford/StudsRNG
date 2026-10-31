--!strict
-- Single responsibility: plugin-wide settings that are NOT per-group — right
-- now just whether the points/DataStore system runs at all. Talks straight
-- to RuntimeSource.Settings (a game-side attribute), unlike every other
-- section here which forwards to the CURRENT GROUP's Configuration.

local Components = script.Parent.Parent.Components
local Row = require(Components.Row)
local Theme = require(Components.Theme)
local Toggle = require(Components.Toggle)

local OthersSection = {}
OthersSection.__index = OthersSection

function OthersSection.new(parent: Instance, order: number)
	local self = setmetatable({}, OthersSection)
	-- Same (key, value) shape as every group section's OnValueChanged, even
	-- though these two keys land in Settings instead of a group's
	-- Configuration — Panel/Main don't need a second callback shape for it.
	self.OnValueChanged = nil :: ((string, any) -> ())?

	local function emit(key: string, value: any)
		if self.OnValueChanged then self.OnValueChanged(key, value) end
	end

	local pointsRow = Row.new(parent, order, "Points + DataStore")
	self.points = Toggle.new(pointsRow.Content, {})

	local hintRow = Row.new(parent, order + 1, nil, 32)
	local hint = Theme.Text("Counts key presses per player, saved via DataStore.", hintRow.Content)
	hint.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.DimmedText)
	hint.TextWrapped = true
	hint.TextYAlignment = Enum.TextYAlignment.Top
	hint.TextSize = Theme.TEXT_SIZE - 2

	-- Meaningless with Points off (there is nothing for it to display), so it
	-- only ever shows up once Points itself is on — see the points toggle
	-- handler below, which is the only thing that flips this row's visibility.
	local autoUIRow = Row.new(parent, order + 2, "AutoUI")
	self.autoUIRow = autoUIRow
	self.autoUI = Toggle.new(autoUIRow.Content, {})
	self.autoUI.OnChanged = function(value) emit("AutoUIEnabled", value) end

	local autoUIHintRow = Row.new(parent, order + 3, nil, 32)
	self.autoUIHintRow = autoUIHintRow
	local autoUIHint = Theme.Text("Builds the points counter and \"+1\" popups automatically.", autoUIHintRow.Content)
	autoUIHint.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.DimmedText)
	autoUIHint.TextWrapped = true
	autoUIHint.TextYAlignment = Enum.TextYAlignment.Top
	autoUIHint.TextSize = Theme.TEXT_SIZE - 2

	self.points.OnChanged = function(value)
		self:_refreshAutoUIVisibility(value)
		emit("PointsEnabled", value)
	end

	-- Hidden until Panel:SetOthers (Main.lua, at plugin load) proves Points is
	-- actually on: a Toggle defaults to false internally (see Toggle.new) but
	-- a Row defaults to VISIBLE, so without this the row showed up for one
	-- frame — or longer, if that first SetOthers call was ever delayed or
	-- skipped — regardless of the real persisted setting.
	--
	-- "Or longer" is exactly what happened: SetOthers used to be called ONLY
	-- when the brush was switched on, so a user who just opened the panel saw
	-- Points reading OFF while it was really on, and no AutoUI switch at all.
	-- Main now pushes the real values at load and on every widget open; do not
	-- go back to a single conditional call site.
	self:_refreshAutoUIVisibility(false)

	return self
end

function OthersSection:_refreshAutoUIVisibility(pointsEnabled: boolean)
	self.autoUIRow:SetVisible(pointsEnabled)
	self.autoUIHintRow:SetVisible(pointsEnabled)
end

OthersSection.ROW_COUNT = 4

function OthersSection:Show(values: { [string]: any })
	self.points:Set(values.PointsEnabled)
	self.autoUI:Set(values.AutoUIEnabled)
	-- Coerced to a real boolean: SetVisible errors on nil, which a missing
	-- attribute (typeof(nil)) would otherwise pass straight through as a
	-- silent failure that left this row stuck visible.
	self:_refreshAutoUIVisibility(values.PointsEnabled == true)
end

return OthersSection
