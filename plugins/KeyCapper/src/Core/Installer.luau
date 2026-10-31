--!strict
-- Single responsibility: guarantee that ReplicatedStorage.KeyCapper exists and
-- is up to date in the USER's game. Idempotent: safe to call on every plugin
-- activation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(script.Parent.Parent.Constants)

local Installer = {}

local watchdog: RBXScriptConnection? = nil

local function install(parentService: Instance, existing: Instance?): Folder
	local source = script.Parent.Parent:FindFirstChild("RuntimeSource")
	assert(source, "KeyCapper: RuntimeSource not found in the plugin")

	local installed = source:Clone()
	installed.Name = Constants.RUNTIME_NAME
	installed:SetAttribute("Version", Constants.VERSION)

	local detection = installed:FindFirstChild("Detection")
	local client = detection and detection:FindFirstChild("Client")
	if client then (client :: Script).Disabled = false end

	local points = installed:FindFirstChild("Points")
	local server = points and points:FindFirstChild("Server")
	if server then (server :: Script).Disabled = false end

	-- Parent the replacement BEFORE dropping the old one. On a version bump the
	-- two orders look equivalent, but they are not: destroying first means that
	-- anything throwing in between (a RuntimeSource the plugin can't see, most
	-- obviously) leaves the game with NO runtime at all, and the only symptom of
	-- that is keys which silently stop working.
	installed.Parent = parentService
	if existing then existing:Destroy() end
	return installed
end

-- The install is deliberately made outside any ChangeHistory recording, so it
-- is not itself undoable. That is not enough: undo restores a whole DataModel
-- state, so a Ctrl+Z reaching back past the install wipes the folder anyway.
-- It happens on the most ordinary gesture there is — place a first stroke, undo
-- it, place another. The keys come back, the runtime does not, and the board is
-- dead for the rest of the session with nothing in the Output to say so.
-- Nothing ever looks at the folder again, so re-installing it when it goes
-- missing is the only repair.
local function watch(installed: Folder)
	if watchdog then watchdog:Disconnect() end
	watchdog = installed.AncestryChanged:Connect(function(_, parent)
		if parent then return end
		-- Deferred: a redo can put this very instance back, and re-installing
		-- ahead of it would leave a duplicate behind.
		task.defer(function()
			if installed.Parent then return end
			Installer.EnsureRuntime()
		end)
	end)
end

function Installer.EnsureRuntime(): Folder
	local parentService = game:GetService(Constants.RUNTIME_PARENT :: any) :: Instance
	local existing = parentService:FindFirstChild(Constants.RUNTIME_NAME)

	if existing and existing:GetAttribute("Version") == Constants.VERSION then
		-- Re-armed even on the no-op path: the folder may have been restored by
		-- a redo, or be a leftover from a previous session that no live
		-- connection is watching.
		watch(existing :: Folder)
		return existing :: Folder
	end

	-- Different version (or nothing there): replace cleanly instead of letting
	-- two copies of the runtime coexist.
	local installed = install(parentService, existing)
	watch(installed)
	return installed
end

return Installer
