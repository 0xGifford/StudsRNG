--!strict
-- Single responsibility: list the existing keys occupying a given spot.
-- Fully replaces a grid-occupancy check: this is what allows floors/overlaps
-- on Y without keeping anything up to date besides the KeyCapper_Key tag
-- (CollectionService already tracks that for us).
--
-- It only reports: deciding what to do with those keys (replace them) is the
-- Brush's call.

local CollectionService = game:GetService("CollectionService")
local Constants = require(script.Parent.Parent.Constants)

local OverlapGuard = {}

-- Negative margin: two keys placed perfectly side by side must NOT count as
-- overlapping each other. Only a real overlap is reported.
local MARGIN = 0.05

-- Walks up to the Model carrying the key tag. Written by hand because
-- FindFirstAncestorWhich does not exist (only ...WhichIsA, on class names).
local function taggedKeyAncestor(part: BasePart): Instance?
	local node: Instance? = part
	while node and node ~= workspace do
		if CollectionService:HasTag(node, Constants.TAG_KEY) then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- Returns the distinct key models overlapping the box (empty table if free).
function OverlapGuard.FindOverlapping(cframe: CFrame, size: Vector3, excluding: Instance?): { Instance }
	-- Scoped to the keys FOLDER, not to CollectionService:GetTagged. This runs
	-- once per footprint cell per placement, and handing the engine a filter
	-- list containing every key on the board is what made painting get slower
	-- as the build grew. KeyPlacer parents every key here, and the tag is
	-- still verified per hit below, so nothing untagged sneaks through.
	local folder = workspace:FindFirstChild(Constants.KEYS_FOLDER)
	if not folder then return {} end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }

	local shrunk = Vector3.new(
		math.max(size.X - MARGIN * 2, 0.05),
		math.max(size.Y - MARGIN * 2, 0.05),
		math.max(size.Z - MARGIN * 2, 0.05)
	)

	local found: { Instance } = {}
	local seen: { [Instance]: true } = {}

	for _, part in ipairs(workspace:GetPartBoundsInBox(cframe, shrunk, params)) do
		local model = taggedKeyAncestor(part)
		if model and model ~= excluding and not seen[model] then
			seen[model] = true
			table.insert(found, model)
		end
	end

	return found
end

return OverlapGuard
