--[[

WorldFx
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/WorldFx

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Small world effects, driven by tags on things built in Studio:
--   Scroll         a Texture that scrolls (water). Attributes ScrollU /
--                  ScrollV: studs per second (default 2 / 1).
--   Detail_Small   a Model / part hidden locally beyond its distance
--                  attribute (studs from the camera, default 150): cheap
--                  level of detail for grass, small rocks and the like.
--   WaterSpout     a part that bobs up and down (fountain spray). Attribute
--                  Bob: studs (default 0.4).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local WorldFx = {}

local DETAIL_CHECK = 0.5 -- seconds between distance checks
local DEFAULT_DETAIL_DISTANCE = 150

type Detail = { root: Instance, parts: { BasePart }, distance: number, hidden: boolean }

local scrolling: { [Texture]: boolean } = {}
local details: { [Instance]: Detail } = {}
local spouts: { [BasePart]: { base: CFrame, phase: number } } = {}

local function watch(tag: string, added: (Instance) -> (), removed: (Instance) -> ())
	for _, instance in CollectionService:GetTagged(tag) do
		task.spawn(added, instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(added)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(removed)
end

local function partsOf(root: Instance): { BasePart }
	local parts: { BasePart } = {}
	if root:IsA("BasePart") then
		table.insert(parts, root)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

local function setHidden(detail: Detail, hidden: boolean)
	if detail.hidden == hidden then return end
	detail.hidden = hidden
	for _, part in detail.parts do
		part.LocalTransparencyModifier = if hidden then 1 else 0
	end
end

local function positionOf(root: Instance): Vector3?
	if root:IsA("BasePart") then return root.Position end
	if root:IsA("Model") then return root:GetPivot().Position end
	local part = root:FindFirstChildWhichIsA("BasePart", true)
	return if part then part.Position else nil
end

function WorldFx.start()
	watch("Scroll", function(instance)
		if instance:IsA("Texture") then
			scrolling[instance] = true
		end
	end, function(instance)
		scrolling[instance :: Texture] = nil
	end)

	watch("Detail_Small", function(instance)
		local distance = instance:GetAttribute("distance") or instance:GetAttribute("Distance")
		details[instance] = {
			root = instance,
			parts = partsOf(instance),
			distance = if typeof(distance) == "number" then distance else DEFAULT_DETAIL_DISTANCE,
			hidden = false,
		}
	end, function(instance)
		local detail = details[instance]
		if detail then
			setHidden(detail, false)
			details[instance] = nil
		end
	end)

	watch("WaterSpout", function(instance)
		if instance:IsA("BasePart") then
			spouts[instance] = { base = instance.CFrame, phase = math.random() * math.pi * 2 }
		end
	end, function(instance)
		spouts[instance :: BasePart] = nil
	end)

	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		for texture in scrolling do
			local u = texture:GetAttribute("ScrollU")
			local v = texture:GetAttribute("ScrollV")
			texture.OffsetStudsU = (texture.OffsetStudsU + (if typeof(u) == "number" then u else 2) * dt) % math.max(texture.StudsPerTileU, 1)
			texture.OffsetStudsV = (texture.OffsetStudsV + (if typeof(v) == "number" then v else 1) * dt) % math.max(texture.StudsPerTileV, 1)
		end
		for part, spout in spouts do
			local bob = part:GetAttribute("Bob")
			local height = if typeof(bob) == "number" then bob else 0.4
			part.CFrame = spout.base + Vector3.new(0, math.sin(t * 3 + spout.phase) * height, 0)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(DETAIL_CHECK)
			local camera = workspace.CurrentCamera
			if camera then
				local from = camera.Focus.Position -- what it looks at (the isometric camera is far off)
				for _, detail in details do
					local position = positionOf(detail.root)
					if position then
						setHidden(detail, (position - from).Magnitude > detail.distance)
					end
				end
			end
		end
	end)
end

return WorldFx
