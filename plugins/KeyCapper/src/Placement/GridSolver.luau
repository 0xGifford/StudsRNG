--!strict
-- Single responsibility: snap a position WITHIN a surface frame (provided by
-- SurfaceProbe), and handle rotation in 90-degree steps.
--
-- Knows nothing about raycasting or Parts: pure 2D geometry in a plane. This
-- is what lets this module be tested without a Workspace.

local Constants = require(script.Parent.Parent.Constants)

local GridSolver = {}

-- hitPosition/gridOrigin come from the same Probe.Probe(...): gridOrigin's
-- position is the grid anchor (the Part's center), hitPosition the aimed point.
function GridSolver.Snap(hitPosition: Vector3, gridOrigin: CFrame, pitch: number): Vector3
	-- Express the aimed point in the grid's local frame: snapping only
	-- happens on the surface's two axes (local X/Z), never on local Y
	-- (height follows the raycast, not a grid).
	local relative = gridOrigin:PointToObjectSpace(hitPosition)
	local snappedX = math.round(relative.X / pitch) * pitch
	local snappedZ = math.round(relative.Z / pitch) * pitch

	-- relative.Y is kept as-is: the height comes from the raycast, the grid
	-- anchor sits at the Part's center and must not drag the key down into it.
	return gridOrigin:PointToWorldSpace(Vector3.new(snappedX, relative.Y, snappedZ))
end

-- Cell offsets of an N×N footprint around the aimed cell. Offsets are WHOLE
-- cells, always: an even N therefore sits slightly off-centre rather than on
-- half-steps. Half-steps would centre it prettily under the cursor but put its
-- keys half a pitch off the grid, so a 2x2 would no longer line up with a 1x1.
-- Alignment wins over centring.
function GridSolver.Footprint(size: number): { Vector2 }
	local cells: { Vector2 } = {}
	local half = math.floor((size - 1) / 2)

	for x = 0, size - 1 do
		for z = 0, size - 1 do
			table.insert(cells, Vector2.new(x - half, z - half))
		end
	end

	return cells
end

-- Moves a snapped point by a whole number of cells WITHIN the surface plane.
function GridSolver.OffsetByCell(position: Vector3, surfaceFrame: CFrame, cell: Vector2, pitch: number): Vector3
	return position
		+ surfaceFrame.RightVector * (cell.X * pitch)
		+ surfaceFrame.LookVector * (cell.Y * pitch)
end

-- rotationSteps: number of 90-degree steps (0-3), provided by the Brush (scroll wheel / key).
function GridSolver.BuildCFrame(snappedPosition: Vector3, surfaceFrame: CFrame, rotationSteps: number): CFrame
	local yaw = Constants.ROTATION_STEP * (rotationSteps % 4) + Constants.MESH_YAW_OFFSET
	-- surfaceFrame gives the orientation (up = normal); we only keep its
	-- rotation, replacing its position with the snapped point.
	return CFrame.new(snappedPosition) * (surfaceFrame - surfaceFrame.Position) * CFrame.Angles(0, yaw, 0)
end

return GridSolver
