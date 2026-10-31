--!strict
-- Single responsibility: the label's typography — font and outline. The
-- label's COLOUR is a ColorChannel like the cap's; this is what is left once
-- colour is handled elsewhere.
--
-- The outline colour and thickness only exist while the outline is on, so
-- they are hidden when it is off rather than sitting there doing nothing.

local Components = script.Parent.Parent.Components
local Row = require(Components.Row)
local Slider = require(Components.Slider)
local Toggle = require(Components.Toggle)
local Dropdown = require(Components.Dropdown)
local ColorPicker = require(Components.ColorPicker)
local FontPresets = require(script.Parent.Parent.Parent.RuntimeSource.Style.FontPresets)

local TextStyleSection = {}
TextStyleSection.__index = TextStyleSection

function TextStyleSection.new(parent: Instance, order: number, overlay: GuiObject)
	local self = setmetatable({}, TextStyleSection)
	self.OnValueChanged = nil :: ((string, any) -> ())?

	local function emit(key: string, value: any)
		if self.OnValueChanged then
			self.OnValueChanged(key, value)
		end
	end

	-- A dropdown rather than a segmented control: the font list is the one
	-- set here that is expected to keep growing.
	local fontRow = Row.new(parent, order, "Font")
	local entries = {}
	for _, name in ipairs(FontPresets.List()) do
		table.insert(entries, { Value = name })
	end
	self.font = Dropdown.new(fontRow.Content, { Entries = entries, Overlay = overlay })
	self.font.OnChanged = function(value) emit("FontName", value) end

	local outlineRow = Row.new(parent, order + 1, "Outline")
	self.outline = Toggle.new(outlineRow.Content, {})

	local colorRow = Row.new(parent, order + 2, "Outline color")
	self.colorRow = colorRow
	self.outlineColor = ColorPicker.new(colorRow.Content, { Overlay = overlay })
	self.outlineColor.OnChanged = function(color) emit("StrokeColor", color) end

	local sizeRow = Row.new(parent, order + 3, "Outline size")
	self.sizeRow = sizeRow
	self.outlineSize = Slider.new(sizeRow.Content, {
		Min = 0, Max = 6, Step = 0.5,
		Format = function(value: number) return string.format("%.1f", value) end,
	})
	self.outlineSize.OnChanged = function(value) emit("StrokeSize", value) end

	-- SurfaceGui.MaxDistance: how far the label stays readable. 100-250, a
	-- narrower range than a raw stud value would allow — below 100 the label
	-- starts disappearing well within normal viewing range, above 250 it never
	-- fades and the range stops meaning anything.
	local distanceRow = Row.new(parent, order + 4, "Label distance")
	self.maxDistance = Slider.new(distanceRow.Content, {
		Min = 100, Max = 250, Step = 10,
		Format = function(value: number) return string.format("%d", value) end,
	})
	self.maxDistance.OnChanged = function(value) emit("LabelMaxDistance", value) end

	self.outline.OnChanged = function(enabled)
		self:_refresh(enabled)
		emit("StrokeEnabled", enabled)
	end

	self:_refresh(false)
	return self
end

TextStyleSection.ROW_COUNT = 5

function TextStyleSection:_refresh(enabled: boolean)
	self.colorRow:SetVisible(enabled)
	self.sizeRow:SetVisible(enabled)
end

function TextStyleSection:Show(values: { [string]: any })
	self.font:Set(values.FontName)
	self.outline:Set(values.StrokeEnabled)
	self:_refresh(values.StrokeEnabled)
	self.outlineColor:Set(values.StrokeColor)
	self.outlineSize:Set(values.StrokeSize)
	self.maxDistance:Set(values.LabelMaxDistance)
end

return TextStyleSection
