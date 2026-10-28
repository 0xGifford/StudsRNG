--!strict
-- Single responsibility: own plugin-wide, non-per-group settings — currently
-- just whether the points/DataStore system runs at all. Same "kept outside
-- the versioned runtime folder" pattern as GroupRegistry.GROUPS_FOLDER: the
-- Installer wipes the RuntimeSource clone on a version bump, and a toggle the
-- user set once must survive that.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "KeyCapperSettings"

local DEFAULTS = {
	PointsEnabled = false,
	-- Whether the runtime builds the points counter + "+1" popups itself.
	-- Off lets a game with its own HUD use the points value without the
	-- built-in display fighting it.
	AutoUIEnabled = false,
}

local Settings = {}

function Settings.EnsureFolder(): Configuration
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then return existing :: Configuration end

	local config = Instance.new("Configuration")
	config.Name = FOLDER_NAME
	for key, value in pairs(DEFAULTS) do
		config:SetAttribute(key, value)
	end
	config.Parent = ReplicatedStorage
	return config
end

-- Read-only lookup: never creates the folder. The game-side runtime (Server,
-- Client) only ever reads here; only the plugin panel writes, via Set below.
function Settings.GetValue(key: string): any
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then return DEFAULTS[key] end
	local value = folder:GetAttribute(key)
	if value == nil then return DEFAULTS[key] end
	return value
end

function Settings.Set(key: string, value: any)
	Settings.EnsureFolder():SetAttribute(key, value)
end

return Settings
