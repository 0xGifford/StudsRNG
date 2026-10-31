--!strict
-- Single responsibility: the list of valid color modes, shared between the
-- Panel (cycling button) and GroupStyler (branching on the stored value) so
-- neither hardcodes the names independently.
--
-- A mode is reusable across color CHANNELS (cap, text, later others): each
-- channel picks its own mode independently.

local ColorModes = {}

local MODES = { "Solid", "Gradient", "Random" }

ColorModes.DEFAULT_NAME = MODES[1]

function ColorModes.List(): { string }
	return MODES
end

return ColorModes
