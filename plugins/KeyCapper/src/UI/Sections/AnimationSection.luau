--!strict
-- Single responsibility: how a key behaves when it is pressed — which
-- animation preset, and the two timings around it.
--
-- The timings were free-text seconds before. As sliders they are bounded to a
-- range that still reads as a keypress: 0.4s to go down is not a slow key,
-- it is a broken one.

local Components = script.Parent.Parent.Components
local Row = require(Components.Row)
local Slider = require(Components.Slider)
local Segmented = require(Components.Segmented)
local AnimationPresets = require(script.Parent.Parent.Parent.RuntimeSource.Style.AnimationPresets)

local AnimationSection = {}
AnimationSection.__index = AnimationSection

local function seconds(value: number): string
	return string.format("%.3fs", value)
end

function AnimationSection.new(parent: Instance, order: number)
	local self = setmetatable({}, AnimationSection)
	self.OnValueChanged = nil :: ((string, any) -> ())?

	local function emit(key: string, value: any)
		if self.OnValueChanged then
			self.OnValueChanged(key, value)
		end
	end

	local styleRow = Row.new(parent, order, nil)
	self.style = Segmented.new(styleRow.Content, { Options = AnimationPresets.List() })
	self.style.OnChanged = function(value) emit("AnimationStyle", value) end

	local pressRow = Row.new(parent, order + 1, "Press")
	self.press = Slider.new(pressRow.Content, { Min = 0.01, Max = 0.2, Step = 0.005, Format = seconds })
	self.press.OnChanged = function(value) emit("PressTime", value) end

	local releaseRow = Row.new(parent, order + 2, "Release")
	self.release = Slider.new(releaseRow.Content, { Min = 0.02, Max = 0.4, Step = 0.005, Format = seconds })
	self.release.OnChanged = function(value) emit("ReleaseTime", value) end

	return self
end

AnimationSection.ROW_COUNT = 3

function AnimationSection:Show(values: { [string]: any })
	self.style:Set(values.AnimationStyle)
	self.press:Set(values.PressTime)
	self.release:Set(values.ReleaseTime)
end

return AnimationSection
