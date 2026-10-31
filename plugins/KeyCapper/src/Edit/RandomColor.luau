--!strict
-- Single responsibility: turn a set of positions into per-key colour
-- VARIATIONS around a base colour. Pure maths, no Instance touched.
--
-- Replaces the old "random hue, fixed saturation, one brightness knob": that
-- could only produce confetti. The model here is a base colour plus three
-- amplitudes (hue / saturation / value), which covers the whole spread with
-- one set of controls:
--   * small hue range          -> shades of one colour
--   * full hue range           -> fully multicoloured
--   * pastel base colour       -> pastel keys, whatever the ranges
-- So there is deliberately NO dedicated "pastel" setting: a pastel result is
-- a pastel base, picked in the colour picker like any other.
--
-- The variation is DETERMINISTIC (hashed from position), not math.random():
-- GroupStyler.Apply runs again every time a single key joins the group, and
-- re-rolling would reshuffle every OTHER member's colour on each stroke.

local RandomColor = {}

local function hash01(x: number): number
	local n = math.sin(x) * 43758.5453
	return n - math.floor(n)
end

-- Reflects off the 0..1 borders instead of clamping. Clamping would pile
-- every out-of-range key onto pure black or pure white, so a light base with
-- a wide value range came out as a block of identical white caps.
local function fold(value: number): number
	value = math.abs(value)
	value = value % 2
	if value > 1 then
		value = 2 - value
	end
	return value
end

-- hueRange/satRange/valueRange: amplitudes in 0..1. Hue is a full turn at 1
-- (so 1 means "any colour"), saturation and value are +/- that much around
-- the base. salt shifts the hash so two channels (cap vs text) fed the SAME
-- positions don't land on the same variation.
function RandomColor.Colors(
	positions: { Vector3 },
	base: Color3,
	hueRange: number,
	satRange: number,
	valueRange: number,
	salt: number
): { Color3 }
	local baseHue, baseSat, baseValue = base:ToHSV()
	local colors: { Color3 } = {}

	for index, position in ipairs(positions) do
		local seed = position.X * 12.9898 + position.Y * 78.233 + position.Z * 37.719 + salt

		local hue = (baseHue + (hash01(seed) - 0.5) * hueRange) % 1
		local saturation = fold(baseSat + (hash01(seed + 91.7) - 0.5) * 2 * satRange)
		-- Value floored just above black: a key that renders pure black reads
		-- as a bug rather than as a dark variation.
		local value = math.max(fold(baseValue + (hash01(seed + 157.3) - 0.5) * 2 * valueRange), 0.04)

		colors[index] = Color3.fromHSV(hue, saturation, value)
	end

	return colors
end

return RandomColor
