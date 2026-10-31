--!strict
-- Single responsibility: given a set of positions and an axis, say what colour
-- each one takes. Pure maths: no Instance touched, no group read.
--
-- The anchors are DERIVED from the members' bounding box, never stored. That's
-- what makes the gradient survive adding keys to the group later: the ends
-- simply move, and everything is recomputed. Baking the colour once would
-- freeze the gradient the day the keyboard grows.

local GradientSolver = {}

local AXES: { [string]: Vector3 } = {
	X = Vector3.xAxis,
	Z = Vector3.zAxis,
}

function GradientSolver.IsAxis(axis: string): boolean
	return AXES[axis] ~= nil
end

-- Returns the 0..1 position of each entry along the axis, in the same order.
-- A group whose members are all at the same coordinate gets 0 everywhere
-- rather than a division by zero.
function GradientSolver.Ratios(positions: { Vector3 }, axis: string): { number }
	local direction = AXES[axis]
	local ratios: { number } = {}
	if not direction or #positions == 0 then
		for index = 1, #positions do
			ratios[index] = 0
		end
		return ratios
	end

	local minimum = math.huge
	local maximum = -math.huge
	local projections: { number } = {}

	for index, position in ipairs(positions) do
		local projection = position:Dot(direction)
		projections[index] = projection
		minimum = math.min(minimum, projection)
		maximum = math.max(maximum, projection)
	end

	local span = maximum - minimum
	for index, projection in ipairs(projections) do
		ratios[index] = span > 1e-4 and (projection - minimum) / span or 0
	end

	return ratios
end

function GradientSolver.Colors(positions: { Vector3 }, axis: string, from: Color3, to: Color3): { Color3 }
	local colors: { Color3 } = {}
	for index, ratio in ipairs(GradientSolver.Ratios(positions, axis)) do
		colors[index] = from:Lerp(to, ratio)
	end
	return colors
end

return GradientSolver
