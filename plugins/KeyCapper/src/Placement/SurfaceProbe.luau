--!strict
-- Single responsibility: turn a ray into a SURFACE FRAME.
--
-- This is the piece that makes keys follow terrain slope and rotation
-- without any other module having to care: everything else then works in
-- this frame as if it were flat ground.
--
-- UpVector = the surface normal.
-- LookVector = a reference direction of the hit surface, projected onto the
-- plane. Two keys placed on the same Part therefore share the same frame,
-- hence the same grid: they are forced to align.

local SurfaceProbe = {}

export type Hit = {
	instance: Instance,
	position: Vector3,
	normal: Vector3,
	frame: CFrame, -- surface frame, origin at the impact point
	origin: CFrame, -- surface frame, origin at the grid anchor
}

local function referenceVectors(instance: Instance, up: Vector3): (Vector3, Vector3)
	-- Look for a stable reference direction carried by the surface.
	local candidates: { Vector3 }
	if instance:IsA("BasePart") then
		candidates = { instance.CFrame.LookVector, instance.CFrame.RightVector, instance.CFrame.UpVector }
	else
		-- Terrain: no own CFrame, fall back to world axes.
		candidates = { Vector3.new(0, 0, -1), Vector3.new(1, 0, 0) }
	end

	for _, candidate in ipairs(candidates) do
		-- Projection onto the surface plane.
		local projected = candidate - up * candidate:Dot(up)
		if projected.Magnitude > 1e-3 then
			local forward = projected.Unit
			return forward, forward:Cross(up).Unit
		end
	end

	-- Should never happen: at least one of the axes is never collinear with up.
	local fallback = Vector3.new(1, 0, 0)
	local forward = (fallback - up * fallback:Dot(up)).Unit
	return forward, forward:Cross(up).Unit
end

-- Where to anchor the grid. For a Part, its center: every key placed on that
-- Part then lands on the same grid, regardless of placement order.
local function gridAnchor(instance: Instance): Vector3
	if instance:IsA("BasePart") then
		return instance.Position
	end
	return Vector3.zero -- Terrain: grid anchored on the world origin
end

function SurfaceProbe.Probe(origin: Vector3, direction: Vector3, ignore: { Instance }?): Hit?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	params.IgnoreWater = true

	local result = workspace:Raycast(origin, direction, params)
	if not result then return nil end

	local up = result.Normal
	local forward, right = referenceVectors(result.Instance, up)

	return {
		instance = result.Instance,
		position = result.Position,
		normal = up,
		frame = CFrame.fromMatrix(result.Position, right, up, -forward),
		origin = CFrame.fromMatrix(gridAnchor(result.Instance), right, up, -forward),
	}
end

return SurfaceProbe
