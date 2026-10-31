--!strict
-- Single responsibility: own the group DATA. Which groups exist, what each
-- one is worth, and which keys belong to one.
--
-- A group is what makes the plugin usable at all: you never edit 87 keys, you
-- edit the group they were painted into. Membership is a plain attribute on
-- the key Model, so a key carries its own identity and nothing has to be kept
-- in sync on the side.
--
-- Storage lives in ReplicatedStorage.KeyCapperGroups, deliberately OUTSIDE
-- ReplicatedStorage.KeyCapper: the Installer wipes and re-clones the runtime
-- folder on a version bump, and that must never take the user's groups with it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(script.Parent.Parent.Constants)

local GroupRegistry = {}

-- Defaults applied to a group the first time it is created. Also the schema:
-- these keys are the only attributes a group carries.
-- Text/stroke defaults mirror GuiFactory's own build-time defaults, so a
-- freshly placed key and a freshly created group agree before any edit.
local DEFAULTS = {
	-- Cap colour channel. Mode picks which of the three fields below is live
	-- — see Edit.ColorModes / GroupStyler.
	CapColorMode = "Solid", -- "Solid" | "Gradient" | "Random"
	Color = Color3.fromRGB(230, 240, 250), -- Solid value, and Gradient's start
	GradientAxis = "X", -- "X" | "Z", only read when CapColorMode == "Gradient"
	GradientColor = Color3.fromRGB(90, 140, 220), -- Gradient's end
	-- Random mode: variation AMPLITUDES around Color (the same base the Solid
	-- mode uses). Hue at 1 is a full turn, i.e. "any colour"; a small hue
	-- range gives shades of one colour. See Edit.RandomColor.
	CapRandomHue = 1.00,
	CapRandomSat = 0.15,
	CapRandomValue = 0.15,

	SoundIds = "", -- comma-separated; empty = runtime default sound
	PitchJitter = 0.06,
	-- Mirrors RuntimeSource.Config.SOUND_VOLUME: the group's value and the
	-- runtime's fallback must agree, or a group left untouched would sound
	-- different from one that was.
	Volume = 0.5,

	-- Text colour channel: same three-mode shape as the cap's, independent.
	TextColorMode = "Solid",
	TextColor = Color3.new(0, 0, 0),
	TextGradientAxis = "X",
	TextGradientColor = Color3.fromRGB(255, 255, 255),
	TextRandomHue = 1.00,
	TextRandomSat = 0.15,
	TextRandomValue = 0.15,

	FontName = "Fredoka", -- see RuntimeSource.FontPresets
	StrokeEnabled = false,
	StrokeColor = Color3.new(0, 0, 0),
	StrokeSize = 1,
	-- SurfaceGui.MaxDistance for the label: how far away it stays readable.
	-- 150 studs by default, adjustable between 100-250 in the panel.
	LabelMaxDistance = 150,
	AnimationStyle = "Default", -- see RuntimeSource.AnimationPresets
	PressTime = 0.045,
	ReleaseTime = 0.13,
}

function GroupRegistry.EnsureFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(Constants.GROUPS_FOLDER)
	if existing then return existing :: Folder end

	local folder = Instance.new("Folder")
	folder.Name = Constants.GROUPS_FOLDER
	folder.Parent = ReplicatedStorage
	return folder
end

-- Creates the group on first mention. Painting into a group name that does not
-- exist yet is the normal way to create one: no "new group" ceremony.
function GroupRegistry.Ensure(name: string): Configuration
	local folder = GroupRegistry.EnsureFolder()
	local existing = folder:FindFirstChild(name)
	if existing then return existing :: Configuration end

	local group = Instance.new("Configuration")
	group.Name = name
	for key, value in pairs(DEFAULTS) do
		group:SetAttribute(key, value)
	end
	group.Parent = folder
	return group
end

function GroupRegistry.Get(name: string): Configuration?
	local folder = ReplicatedStorage:FindFirstChild(Constants.GROUPS_FOLDER)
	if not folder then return nil end
	local group = folder:FindFirstChild(name)
	return group and group :: Configuration or nil
end

function GroupRegistry.List(): { string }
	local names: { string } = {}
	local folder = ReplicatedStorage:FindFirstChild(Constants.GROUPS_FOLDER)
	if not folder then return names end

	for _, child in ipairs(folder:GetChildren()) do
		table.insert(names, child.Name)
	end
	table.sort(names)
	return names
end

-- Removes the group's stored style. Members keep their Group attribute, so
-- they simply fall back to DEFAULTS (via GetValue) until repainted or
-- reassigned — deleting a group never touches placed keys.
function GroupRegistry.Delete(name: string)
	local group = GroupRegistry.Get(name)
	if group then
		group:Destroy()
	end
end

function GroupRegistry.Set(name: string, key: string, value: any)
	GroupRegistry.Ensure(name):SetAttribute(key, value)
end

function GroupRegistry.GetValue(name: string, key: string): any
	local group = GroupRegistry.Get(name)
	if not group then return DEFAULTS[key] end

	local value = group:GetAttribute(key)
	if value == nil then return DEFAULTS[key] end
	return value
end

-- Walks the tagged keys rather than keeping a member list: CollectionService is
-- already the source of truth, and a list would drift on every undo/delete.
function GroupRegistry.Members(name: string): { Model }
	local members: { Model } = {}
	for _, key in ipairs(CollectionService:GetTagged(Constants.TAG_KEY)) do
		if key:IsA("Model") and key:GetAttribute(Constants.ATTR_GROUP) == name then
			table.insert(members, key)
		end
	end
	return members
end

-- Every group's members from ONE walk of the tagged keys. Members() above
-- scans the whole board to answer for a single group, so anything touching
-- several groups through it was O(groups x keys) — quadratic on exactly the
-- big builds where it hurts. Callers that need more than one group use this.
function GroupRegistry.MembersByGroup(): { [string]: { Model } }
	local buckets: { [string]: { Model } } = {}
	for _, key in ipairs(CollectionService:GetTagged(Constants.TAG_KEY)) do
		if key:IsA("Model") then
			local group = key:GetAttribute(Constants.ATTR_GROUP)
			if typeof(group) == "string" then
				local bucket = buckets[group]
				if not bucket then
					bucket = {}
					buckets[group] = bucket
				end
				table.insert(bucket, key)
			end
		end
	end
	return buckets
end

return GroupRegistry
