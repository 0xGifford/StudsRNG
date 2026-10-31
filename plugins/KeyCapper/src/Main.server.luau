--!strict
-- KeyCapper — Copyright (c) 2026 sebattfg. All rights reserved.
-- Proprietary. Redistribution, reupload and resale are prohibited; sebattfg
-- is the sole authorised distributor. Full terms in the sibling `License`
-- module, and in LICENSE / CREDITS.md at the project root.
-- Panel icons: Font Awesome 5 Free (CC BY 4.0) — https://fontawesome.com/
--
-- Plugin entry point. Creates the toolbar button, owns the Panel and the
-- Brush, and wires them together. Contains NO business logic: everything is
-- delegated (Installer, Brush, Panel, GroupRegistry).
--
-- Only exists and runs once this folder is saved as a Local Plugin (right
-- click > Save as Local Plugin): `plugin` is only defined in that context.

local RunService = game:GetService("RunService")

local Constants = require(script.Parent.Constants)
local Installer = require(script.Parent.Core.Installer)
local Brush = require(script.Parent.Placement.Brush)
local Panel = require(script.Parent.UI.Panel)
local History = require(script.Parent.Core.History)
local GroupRegistry = require(script.Parent.Core.GroupRegistry)
local RestyleQueue = require(script.Parent.Edit.RestyleQueue)
local Settings = require(script.Parent.RuntimeSource.Settings)
local ZoneResolver = require(script.Parent.Placement.ZoneResolver) -- StudsRNG

local toolbar = plugin:CreateToolbar("KeyCapper")
local toolbarButton = toolbar:CreateButton(
	"KeyCapper",
	"Place functional keycaps",
	"rbxassetid://91265798541583"
)
toolbarButton.ClickableWhenViewportHidden = true

local panel = Panel.new(plugin)
local brush = Brush.new(plugin)

-- currentGroup and showGroup are declared before any callback that closes
-- over them: a local declared later would leave those closures reading a
-- nil global instead (bit us twice already).
local currentGroup = Constants.DEFAULT_GROUP

-- Every attribute a group carries (mirrors GroupRegistry's DEFAULTS schema).
-- Kept as an explicit list rather than iterating the Configuration's own
-- attributes: a freshly-picked group that doesn't exist yet has none at all,
-- and the Panel still needs every field populated with its default.
local GROUP_ATTRIBUTE_KEYS = {
	"CapColorMode", "Color", "GradientAxis", "GradientColor",
	"CapRandomHue", "CapRandomSat", "CapRandomValue",
	"SoundIds", "PitchJitter", "Volume",
	"TextColorMode", "TextColor", "TextGradientAxis", "TextGradientColor",
	"TextRandomHue", "TextRandomSat", "TextRandomValue",
	"FontName", "StrokeEnabled", "StrokeColor", "StrokeSize", "LabelMaxDistance",
	"AnimationStyle", "PressTime", "ReleaseTime",
}

-- The dropdown shows each group's key count and a colour chip: past a couple
-- of groups the names alone stop being enough to tell them apart.
--
-- One bucketed walk of the board, not Members() per group: this runs at
-- plugin load and on every group change, and asking each group separately
-- rescanned every key on the board once per group.
local function groupEntries(): { any }
	local buckets = GroupRegistry.MembersByGroup()
	local entries = {}
	for _, name in ipairs(GroupRegistry.List()) do
		local members = buckets[name]
		table.insert(entries, {
			Value = name,
			Detail = tostring(members and #members or 0),
			-- The colour the group paints its caps: with half a dozen groups
			-- the names alone stop being enough to tell them apart.
			Color = GroupRegistry.GetValue(name, "Color"),
			-- The default group is where the brush falls back to and where
			-- orphaned keys are read from, so it must always exist. No × is
			-- drawn for it rather than drawing one that refuses.
			Deletable = name ~= Constants.DEFAULT_GROUP,
		})
	end
	return entries
end

-- The Others section is the ONLY part of the panel whose real state lives
-- game-side (RuntimeSource.Settings) with defaults of TRUE, while its Toggles
-- start at FALSE like every other Toggle. So the panel MUST be told the real
-- values before it is ever looked at, not just when something else happens to
-- push them. It used to be pushed from one place only — brush activation —
-- and until the user turned the brush on, Others showed Points as OFF while
-- the points system was actually running, and hid the AutoUI switch entirely
-- (that row only shows when Points is known to be on). Worse, the first click
-- on the desynced Points toggle wrote back `true`, i.e. no change: the user
-- had to click it twice to turn a running system off, which read as "the
-- switch does nothing / isn't there".
local function showSettings()
	panel:SetOthers({
		PointsEnabled = Settings.GetValue("PointsEnabled"),
		AutoUIEnabled = Settings.GetValue("AutoUIEnabled"),
	})
end

local function showGroup(name: string)
	panel:SetGroups(groupEntries(), name)

	local values = {}
	for _, key in ipairs(GROUP_ATTRIBUTE_KEYS) do
		values[key] = GroupRegistry.GetValue(name, key)
	end
	panel:ShowGroupValues(values)
end

-- Declared here, above every callback that closes over them, for the reason
-- given at the top of this file.
--
-- A slider fires a value change on every frame of a drag. Three things have
-- to be kept apart there, and used to be done together on every one of them:
--
--   * the attribute write, cheap, and immediate so the panel stays live;
--   * the restyle, O(keys) and what actually froze Studio — now coalesced and
--     time-sliced by RestyleQueue, so only the last value is ever painted;
--   * the undo entry, which has to cover the WHOLE gesture. One recording per
--     change was both slow and useless: a hundred waypoints to undo one drag.
--
-- So the recording opens on the first change of a gesture and closes once the
-- values have settled AND the queued restyle has caught up — committing while
-- the restyle is still running would leave the colours it writes outside the
-- entry that is supposed to own them.
local SETTLE = 0.25
local gestureRecording: History.Recording = nil
local gestureGroup: string? = nil
local lastChange = 0
local settling = false

local function flushGesture()
	if not gestureGroup then return end
	History.Commit(gestureRecording)
	gestureRecording, gestureGroup = nil, nil
end

local function settleGesture()
	if settling then return end
	settling = true

	task.spawn(function()
		repeat
			task.wait(SETTLE)
		until os.clock() - lastChange >= SETTLE and not RestyleQueue.IsBusy()
		flushGesture()
		settling = false
	end)
end

-- StudsRNG zones. The zone list is re-read whenever it could have changed
-- (panel opened, brush switched on): zones are Models the user builds.
local function showZones()
	local zones = ZoneResolver.List()
	if brush.zoneLock == nil and zones[1] then
		brush:SetZoneLock(zones[1])
	end
	panel:SetZones(zones, brush.zoneLock)
end

panel.OnZoneModeChanged = function(mode: string)
	brush:SetZoneMode(mode)
	showZones()
end

panel.OnZoneLockChanged = function(zone: number)
	brush:SetZoneLock(zone)
end

panel.OnZoneGroupsChanged = function(enabled: boolean)
	brush:SetZoneGroups(enabled)
end

brush.OnHoverZone = function(zone: number?)
	panel:SetHoverZone(zone)
end

-- A stroke started in a zone with its own group: the panel follows, so the
-- style shown (and edited next) is that zone's.
brush.OnZoneGroup = function(name: string)
	currentGroup = name
	brush:SetGroup(name)
	showGroup(name)
end

toolbarButton.Click:Connect(function()
	panel:Toggle()
	toolbarButton:SetActive(panel.widget.Enabled)
end)

panel.OnBrushToggled = function(active: boolean)
	-- A stroke needs its own recording, and one already open would refuse it.
	-- Reaching for the brush is also exactly when panel fiddling has stopped.
	flushGesture()
	if active then
		-- Install on first real use rather than on plugin load: we never touch
		-- the user's game until they actually ask for a key.
		Installer.EnsureRuntime()
		GroupRegistry.Ensure(currentGroup)
		showSettings()
		showGroup(currentGroup)
		showZones()
		brush:Activate()
		panel:SetStatus("Click or drag in the viewport. R to rotate.")
	else
		brush:Deactivate()
		panel:SetStatus("")
	end
end

panel.OnToolChanged = function(tool: string)
	brush:SetTool(tool)
	if not panel.brushActive then return end
	panel:SetStatus(tool == "Erase"
		and "Drag to erase. The eraser does not snap to the grid."
		or "Click or drag in the viewport. R to rotate.")
end

panel.OnEraseScopeChanged = function(scope: string)
	brush:SetEraseScope(scope)
end

panel.OnLabelChanged = function(label: string)
	brush:SetLetter(label)
end

panel.OnLabelModeChanged = function(mode: string)
	brush:SetLabelMode(mode)
end

panel.OnCharsetChanged = function(name: string)
	brush:SetLabelCharset(name)
end

panel.OnGroupChanged = function(name: string)
	currentGroup = name
	brush:SetGroup(name)
	-- Picking or creating a group is an explicit act, so it may exist right
	-- away: that is what puts it in the list.
	GroupRegistry.Ensure(name)
	-- The fields must follow the group, otherwise the panel would show the
	-- previous group's colour and the next edit would silently overwrite it.
	showGroup(name)
end

panel.OnGroupDeleted = function(name: string)
	-- The UI draws no × for it, so this only fires if something else ever
	-- calls in — the invariant is enforced here, not just hidden in the view.
	if name == Constants.DEFAULT_GROUP then return end
	-- There must always be somewhere for the brush to paint into.
	if #GroupRegistry.List() <= 1 then
		panel:SetStatus("Can't delete the only group.")
		return
	end
	-- Recorded like every other mutation the plugin makes. It was the one
	-- destructive action that wasn't: the group's whole style vanished and
	-- Ctrl+Z did nothing, on the only operation in the plugin with no other
	-- way back. A panel edit in progress must not be swallowed into this
	-- entry, hence the flush first.
	flushGesture()
	local recording = History.Begin("KeyCapper: delete group " .. name)
	-- The keys go WITH the group, they are not left behind. Keeping them was
	-- the worse outcome: a key whose group no longer exists cannot be selected
	-- in the panel, so the group eraser can never reach it either — the only
	-- way to remove it was to switch the erase scope to All and go over it by
	-- hand. Orphaning keys made them practically permanent, which is not
	-- something a delete button should be able to do. Undo brings both the
	-- style and the keys back in one step, since both happen inside this
	-- recording.
	for _, key in ipairs(GroupRegistry.Members(name)) do
		key:Destroy()
	end
	GroupRegistry.Delete(name)
	History.Commit(recording)

	if name == currentGroup then
		currentGroup = GroupRegistry.List()[1]
		brush:SetGroup(currentGroup)
	end
	showGroup(currentGroup)
end

panel.OnGroupValueChanged = function(key: string, value: any)
	-- An edit to another group must never land in the previous one's entry.
	if gestureGroup and gestureGroup ~= currentGroup then
		flushGesture()
	end
	if not gestureGroup then
		gestureRecording = History.Begin("KeyCapper: edit group " .. currentGroup)
		gestureGroup = currentGroup
	end

	lastChange = os.clock()
	GroupRegistry.Set(currentGroup, key, value)
	RestyleQueue.Request(currentGroup)
	settleGesture()
end

panel.OnSizeChanged = function(size: number)
	brush:SetSize(size)
end

panel.OnRotationChanged = function(value: string)
	if value == "Random" then
		brush:SetRotationRandom()
	else
		brush:SetRotation(tonumber(value) // 90)
	end
end

brush.OnRotated = function(steps: number)
	panel:SetRotation(steps)
end

-- Only the group list, never showGroup(): the counts are the sole thing a
-- stroke can invalidate. showGroup would also reload every style field from
-- the registry, overwriting whatever the user is part-way through editing.
brush.OnStrokeEnded = function()
	panel:SetGroups(groupEntries(), currentGroup)
end

panel.OnSettingChanged = function(key: string, value: any)
	Settings.Set(key, value)
end

-- Studio revokes the mouse focus as soon as another tool takes over, or Play
-- starts: the panel must not keep claiming the brush is ON, and the ghost
-- must not be left sitting in the place (it would otherwise persist into
-- Play/publish, since it's just an ordinary part parented to Workspace).
local function forceBrushOff()
	if panel.brushActive then
		panel:SetBrushActive(false)
		brush:Deactivate()
		panel:SetStatus("")
	end
end

plugin.Deactivation:Connect(forceBrushOff)

-- RunService.RunStateChanged is not reliably present across Studio API
-- versions (errors with "not a valid member" on some), so play-mode start is
-- detected by polling RunService:IsRunning() instead, which is always there.
do
	local wasRunning = RunService:IsRunning()
	RunService.Heartbeat:Connect(function()
		local running = RunService:IsRunning()
		if running ~= wasRunning then
			wasRunning = running
			if running then
				forceBrushOff()
			end
		end
	end)
end

plugin.Unloading:Connect(function()
	brush:Deactivate()
end)

-- Re-read on every open: the settings folder is a plain Configuration in
-- ReplicatedStorage, so it can also be edited by hand, undone, or changed by
-- another Studio window while the widget sits closed.
panel.widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	if panel.widget.Enabled then
		showSettings()
		showZones()
	end
end)

-- Both at load, so the panel can never be looked at before it has been told
-- the truth. Settings.GetValue only ever reads (it never creates the folder),
-- so this keeps the "we never touch the user's game until they ask for a key"
-- rule that keeps Installer.EnsureRuntime out of plugin load.
showSettings()
showGroup(currentGroup)
showZones()

-- The one exception to that rule, and it doesn't really break it: keys in the
-- Workspace mean the user has already asked for the runtime, so this puts
-- nothing in the place that isn't meant to be there. It repairs a place SAVED
-- in the broken state — keys, no runtime — which is otherwise indistinguishable
-- from a working one right up until you press a key and nothing happens.
if workspace:FindFirstChild(Constants.KEYS_FOLDER) then
	Installer.EnsureRuntime()
end
