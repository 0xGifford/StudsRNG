--!strict
-- Single responsibility: the controls for ONE colour channel (the cap's, the
-- text's, later others). A mode picker plus the fields that mode actually
-- uses — and only those: switching to Solid hides the gradient and variation
-- rows entirely.
--
-- That hiding IS the feature. The old panel showed all three modes' fields at
-- once, so nine rows were on screen and six of them did nothing.
--
-- Knows no attribute names of its own: it is handed a key mapping, and
-- forwards edits as (attributeKey, value) exactly like every other section.

local Components = script.Parent.Parent.Components
local Theme = require(Components.Theme)
local Row = require(Components.Row)
local Slider = require(Components.Slider)
local Segmented = require(Components.Segmented)
local ColorPicker = require(Components.ColorPicker)
local ColorModes = require(script.Parent.Parent.Parent.Edit.ColorModes)

local ColorChannel = {}
ColorChannel.__index = ColorChannel

local AXES = { "X", "Z" }

-- Named starting points for the variation sliders. They only move the
-- controls — every value stays visible and editable afterwards, so a preset
-- is a shortcut, never a mode.
-- Pastel also desaturates the BASE colour, because that is where pastel
-- actually lives (see Edit.RandomColor): the ranges alone cannot make one.
local PRESETS = {
	{ Name = "Shades", Hue = 0.04, Sat = 0.10, Value = 0.18 },
	{ Name = "Pastel", Hue = 0.35, Sat = 0.08, Value = 0.10, BaseSaturation = 0.30, BaseValue = 0.95 },
	{ Name = "Multicolor", Hue = 1.00, Sat = 0.15, Value = 0.15 },
}

local function degrees(value: number): string
	return string.format("%d\u{00B0}", math.round(value * 180))
end

local function percent(value: number): string
	return string.format("%d%%", math.round(value * 100))
end

-- spec: ModeKey, SolidKey, AxisKey, GradientKey, HueKey, SatKey, ValueKey.
function ColorChannel.new(parent: Instance, order: number, overlay: GuiObject, spec: { [string]: string })
	local self = setmetatable({}, ColorChannel)
	self.spec = spec
	self.OnValueChanged = nil :: ((string, any) -> ())?

	local function emit(key: string, value: any)
		if self.OnValueChanged then
			self.OnValueChanged(key, value)
		end
	end

	local modeRow = Row.new(parent, order, nil)
	self.mode = Segmented.new(modeRow.Content, { Options = ColorModes.List() })

	-- The base colour is shared by all three modes: Solid paints it, Gradient
	-- starts from it, Random varies around it. Keeping one control (with a
	-- label that says which role it plays) means switching modes never loses
	-- the colour you already chose.
	local baseRow = Row.new(parent, order + 1, "Color")
	self.baseRow = baseRow
	self.base = ColorPicker.new(baseRow.Content, { Overlay = overlay })
	self.base.OnChanged = function(color)
		emit(spec.SolidKey, color)
	end

	local endRow = Row.new(parent, order + 2, "To")
	self.endRow = endRow
	self.gradientEnd = ColorPicker.new(endRow.Content, { Overlay = overlay })
	self.gradientEnd.OnChanged = function(color)
		emit(spec.GradientKey, color)
	end

	local axisRow = Row.new(parent, order + 3, "Axis")
	self.axisRow = axisRow
	self.axis = Segmented.new(axisRow.Content, { Options = AXES })
	self.axis.OnChanged = function(value)
		emit(spec.AxisKey, value)
	end

	local presetRow = Row.new(parent, order + 4, nil)
	self.presetRow = presetRow
	local presetNames = {}
	for _, preset in ipairs(PRESETS) do
		table.insert(presetNames, preset.Name)
	end
	-- Stays lit on the preset you picked, so the row reflects what's applied.
	-- Note this can drift from the sliders if you drag one afterwards — the
	-- sliders remain the actual state, the highlight is just a shortcut hint.
	self.presets = Segmented.new(presetRow.Content, { Options = presetNames, Value = "" })
	self.presets.OnChanged = function(name)
		self:_applyPreset(name)
	end

	local hueRow = Row.new(parent, order + 5, "Hue range")
	self.hueRow = hueRow
	self.hue = Slider.new(hueRow.Content, { Min = 0, Max = 1, Step = 0.01, Format = degrees })
	self.hue.OnChanged = function(value) emit(spec.HueKey, value) end

	local satRow = Row.new(parent, order + 6, "Saturation")
	self.satRow = satRow
	self.sat = Slider.new(satRow.Content, { Min = 0, Max = 1, Step = 0.01, Format = percent })
	self.sat.OnChanged = function(value) emit(spec.SatKey, value) end

	local valueRow = Row.new(parent, order + 7, "Brightness")
	self.valueRow = valueRow
	self.value = Slider.new(valueRow.Content, { Min = 0, Max = 1, Step = 0.01, Format = percent })
	self.value.OnChanged = function(value) emit(spec.ValueKey, value) end

	self.mode.OnChanged = function(value)
		self:_refreshVisibility(value)
		emit(spec.ModeKey, value)
	end

	self:_refreshVisibility(ColorModes.DEFAULT_NAME)
	return self
end

-- Returns the LayoutOrder slots this channel occupies, so the caller can lay
-- out what comes after it without counting rows by hand.
ColorChannel.ROW_COUNT = 8

-- Finds the preset (if any) that matches the given hue/sat/value, so the
-- highlighted button always reflects what's actually loaded.
--
-- Compared with a tolerance, not with ==. The sliders step by 0.01 and the
-- values make a round trip through an attribute, so a value that IS the
-- preset's comes back as 0.15000000000000002 often enough to matter: exact
-- equality left the row with nothing lit and no way to tell what was applied.
-- Half a step is well inside the gap between any two presets.
local MATCH_EPSILON = 0.005

local function near(a: number?, b: number): boolean
	return type(a) == "number" and math.abs(a - b) < MATCH_EPSILON
end

local function matchPreset(hue: number?, sat: number?, value: number?): string
	for _, preset in ipairs(PRESETS) do
		if near(hue, preset.Hue) and near(sat, preset.Sat) and near(value, preset.Value) then
			return preset.Name
		end
	end
	return ""
end

function ColorChannel:_applyPreset(name: string)
	for _, preset in ipairs(PRESETS) do
		if preset.Name == name then
			self.hue:Set(preset.Hue)
			self.sat:Set(preset.Sat)
			self.value:Set(preset.Value)
			if self.OnValueChanged then
				self.OnValueChanged(self.spec.HueKey, preset.Hue)
				self.OnValueChanged(self.spec.SatKey, preset.Sat)
				self.OnValueChanged(self.spec.ValueKey, preset.Value)
			end
			if preset.BaseSaturation then
				local hue = select(1, self.base:Color():ToHSV())
				local pastel = Color3.fromHSV(hue, preset.BaseSaturation, preset.BaseValue)
				self.base:Set(pastel)
				if self.OnValueChanged then
					self.OnValueChanged(self.spec.SolidKey, pastel)
				end
			end
			break
		end
	end
end

function ColorChannel:_refreshVisibility(mode: string)
	local gradient = mode == "Gradient"
	local random = mode == "Random"

	self.baseRow.Label.Text = gradient and "From" or (random and "Base color" or "Color")
	self.endRow:SetVisible(gradient)
	self.axisRow:SetVisible(gradient)
	self.presetRow:SetVisible(random)
	self.hueRow:SetVisible(random)
	self.satRow:SetVisible(random)
	self.valueRow:SetVisible(random)
end

-- Reflects the group's stored values. Silent by construction: every component
-- :Set is silent, so loading a group can never echo back as an edit.
function ColorChannel:Show(values: { [string]: any })
	local spec = self.spec
	local mode = values[spec.ModeKey]
	self.mode:Set(mode)
	self:_refreshVisibility(self.mode.value)
	self.base:Set(values[spec.SolidKey])
	self.gradientEnd:Set(values[spec.GradientKey])
	self.axis:Set(values[spec.AxisKey])
	self.hue:Set(values[spec.HueKey])
	self.sat:Set(values[spec.SatKey])
	self.value:Set(values[spec.ValueKey])
	self.presets:Set(matchPreset(values[spec.HueKey], values[spec.SatKey], values[spec.ValueKey]))
end

return ColorChannel
