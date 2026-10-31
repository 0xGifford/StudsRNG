--!strict
-- Single responsibility: build ONE key instance (Model + Hitbox + Cap + GUI)
-- at a given CFrame, and parent it into the Workspace.
-- Decides neither where nor whether it's allowed: that's GridSolver/OverlapGuard.

local CollectionService = game:GetService("CollectionService")

local Constants = require(script.Parent.Parent.Constants)
local GuiFactory = require(script.Parent.Parent.RuntimeSource.Style.GuiFactory)
local GroupRegistry = require(script.Parent.Parent.Core.GroupRegistry)

local KeyPlacer = {}

-- Shrinks the touch hitbox's footprint below the visual cap: a hitbox exactly
-- matching the mesh reads as slightly wider than the cap at the corners
-- (the mesh isn't a perfect box), which felt like pressing a neighbouring key.
-- Tuned by eye by Seb against a scratch prop in Workspace, kept as a ratio
-- rather than a fixed stud value so it still tracks KEY_SIZE if that changes.
local HITBOX_XZ_RATIO = 0.8123

local function getKeysFolder(): Folder
	local folder = workspace:FindFirstChild(Constants.KEYS_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Constants.KEYS_FOLDER
		folder.Parent = workspace
	end
	return folder :: Folder
end

-- The mesh ships inside the plugin (ServerStorage.KeyCapperPlugin.MeshTemplateSource),
-- not re-downloaded on every placement: faster, and avoids permission
-- propagation issues with InsertService:LoadAsset at runtime.
local meshTemplate: MeshPart? = nil
local function getMeshTemplate(): MeshPart
	if meshTemplate then return meshTemplate end

	local source = script.Parent.Parent:FindFirstChild("MeshTemplateSource")
	assert(source, "KeyCapper: MeshTemplateSource not found in the plugin")
	local mesh = source:FindFirstChildWhichIsA("MeshPart", true)
	assert(mesh, "KeyCapper: no MeshPart in MeshTemplateSource")

	meshTemplate = mesh
	return mesh
end

-- cframe: the final CFrame of the CAP (at rest). label: the displayed text.
-- group: the group the key is born into; its look is applied by GroupStyler,
-- not here, because a gradient depends on the whole group.
function KeyPlacer.Place(cframe: CFrame, label: string, group: string): Model
	local model = Instance.new("Model")
	model.Name = "Key_" .. label

	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	-- Y stays the cap's real height, no padding. X/Z shrunk by HITBOX_XZ_RATIO
	-- — see its comment.
	hitbox.Size = Vector3.new(
		Constants.KEY_SIZE.X * HITBOX_XZ_RATIO,
		Constants.KEY_SIZE.Y,
		Constants.KEY_SIZE.Z * HITBOX_XZ_RATIO
	)
	hitbox.CFrame = cframe
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true
	hitbox.Transparency = 1
	hitbox.Parent = model

	local cap = getMeshTemplate():Clone()
	cap.Name = "Cap"
	cap.CFrame = cframe
	cap.Anchored = true
	cap.CanCollide = false
	cap.CanTouch = false
	cap.CanQuery = false
	cap.Parent = model

	GuiFactory.BuildLabel(cap, label, GroupRegistry.GetValue(group, "LabelMaxDistance"))

	model.PrimaryPart = hitbox
	model:SetAttribute("Letter", label)
	model:SetAttribute(Constants.ATTR_GROUP, group)
	model.Parent = getKeysFolder()

	CollectionService:AddTag(hitbox, Constants.TAG_HITBOX)
	CollectionService:AddTag(model, Constants.TAG_KEY)

	-- No undo waypoint here on purpose: the caller groups a whole stroke into
	-- a single recording (see Core.History).
	return model
end


return KeyPlacer
