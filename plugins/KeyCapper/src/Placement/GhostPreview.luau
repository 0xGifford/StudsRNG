--!strict
-- Single responsibility: display the translucent preview of what the brush is
-- about to place. Owns a pool of parts (one per footprint cell) so a brush
-- resize does not churn instances every mouse move.
--
-- Knows nothing about grids or raycasts: it receives ready-made CFrames.

local GhostPreview = {}
GhostPreview.__index = GhostPreview

local CONTAINER_NAME = "KeyCapperGhost"
local DEFAULT_COLOR = Color3.fromRGB(90, 200, 255)
local TRANSPARENCY = 0.4
-- The ghost sits exactly where the key will rest, which puts its bottom face
-- coplanar with the floor: the two surfaces then z-fight and the preview
-- flickers as the camera moves. Lifting it a hair along its own up axis (not
-- world Y, so it still works on a slope) kills the flicker. Placement itself
-- is untouched — this offset only ever applies to the preview.
local LIFT = 0.03

function GhostPreview.new(size: Vector3)
	local self = setmetatable({}, GhostPreview)
	self.size = size
	self.parts = {} :: { BasePart }
	self.color = DEFAULT_COLOR

	-- A single container: the Brush passes it whole to the raycast filter, so
	-- the ghost never blocks its own probe however many cells it has.
	local container = Instance.new("Folder")
	container.Name = CONTAINER_NAME
	-- The ghost is scratch state that belongs to the plugin, but it lives in
	-- the Workspace like any ordinary part — so entering Play, saving or
	-- publishing with the brush on used to carry it along, and it turned up
	-- floating in the running game. Archivable = false excludes the whole
	-- subtree from every copy Studio makes of the datamodel (play solo,
	-- save, publish), which is a guarantee rather than a race with whatever
	-- event we could try to deactivate the brush on.
	container.Archivable = false
	container.Parent = workspace
	self.container = container

	return self
end

function GhostPreview:_partAt(index: number): BasePart
	local existing = self.parts[index]
	if existing then return existing end

	local part = Instance.new("Part")
	part.Name = "Cell" .. index
	part.Size = self.size
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.ForceField
	part.Color = self.color
	part.Transparency = TRANSPARENCY
	part.Parent = self.container

	self.parts[index] = part
	return part
end

-- Shows exactly one cell per CFrame; surplus pooled parts are just hidden.
function GhostPreview:Show(cframes: { CFrame })
	for index, cframe in ipairs(cframes) do
		local part = self:_partAt(index)
		part.CFrame = cframe + cframe.UpVector * LIFT
		part.Transparency = TRANSPARENCY
	end

	for index = #cframes + 1, #self.parts do
		self.parts[index].Transparency = 1
	end
end

-- The eraser reuses the same preview in red: one ghost, and its colour is the
-- only thing telling you whether the next click adds or removes.
function GhostPreview:SetColor(color: Color3)
	self.color = color
	for _, part in ipairs(self.parts) do
		part.Color = color
	end
end

function GhostPreview:Hide()
	for _, part in ipairs(self.parts) do
		part.Transparency = 1
	end
end

function GhostPreview:Destroy()
	self.container:Destroy()
	self.parts = {}
end

return GhostPreview
