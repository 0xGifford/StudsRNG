--!strict
-- Single responsibility: the mouse loop. Translates mouse movement/clicks
-- into calls to SurfaceProbe / GridSolver / OverlapGuard / KeyPlacer / Eraser.
-- Knows nothing about how a key is built (delegated to KeyPlacer) nor about
-- what it looks like (GroupStyler).
--
-- One brush, two tools: Paint and Erase share the cursor, the footprint size
-- and the stroke/undo machinery. Only the per-cell action and the ghost's
-- colour differ.
--
-- Cost note: solving the footprint costs one raycast PER CELL, so an 8x8
-- brush is 64 raycasts. That budget is spent at most once per mouse move —
-- see _onMove.

local Constants = require(script.Parent.Parent.Constants)
local History = require(script.Parent.Parent.Core.History)
local SurfaceProbe = require(script.Parent.SurfaceProbe)
local GridSolver = require(script.Parent.GridSolver)
local OverlapGuard = require(script.Parent.OverlapGuard)
local KeyPlacer = require(script.Parent.KeyPlacer)
local GhostPreview = require(script.Parent.GhostPreview)
local LabelSource = require(script.Parent.LabelSource)
local Eraser = require(script.Parent.Eraser)
local GroupRegistry = require(script.Parent.Parent.Core.GroupRegistry)
local GroupStyler = require(script.Parent.Parent.Edit.GroupStyler)

local Brush = {}
Brush.__index = Brush

Brush.TOOLS = { "Paint", "Erase" }

local PAINT_GHOST_COLOR = Color3.fromRGB(90, 200, 255)
local ERASE_GHOST_COLOR = Color3.fromRGB(255, 90, 90)

function Brush.new(pluginInstance: Plugin)
	local self = setmetatable({}, Brush)
	-- We keep the plugin itself: without plugin:Activate(true) the PluginMouse
	-- never fires Move/Button1Down/KeyDown.
	self.plugin = pluginInstance
	self.mouse = pluginInstance:GetMouse()
	self.rotationSteps = 0
	-- When true, each CELL gets its own independent random rotation at
	-- placement time (see _cellFrames), instead of every key in the stroke
	-- sharing self.rotationSteps.
	self.rotationRandom = false
	self.currentLetter = "A"
	-- Default to Random + the full A-Z 0-9 charset: a fresh brush should
	-- immediately paint varied labels rather than a wall of the same letter.
	self.labelMode = "Random"
	self.labelCharset = LabelSource.DEFAULT_CHARSET
	self.brushSize = 1
	self.currentGroup = Constants.DEFAULT_GROUP
	self.tool = "Paint"
	self.eraseScope = "Group"
	self.ghost = nil :: any
	self.connections = {}

	-- Stroke state. A stroke = one held click. Keys it places are recorded so
	-- the same stroke never overwrites its own work when the footprints of two
	-- consecutive mouse positions overlap.
	self.painting = false
	-- Throttles how often a mouse move re-solves the footprint (see Activate):
	-- Mouse.Move can fire far faster than the raycasts need to be redone.
	self._lastSolve = 0
	self.strokeKeys = {} :: { [Instance]: true }
	-- Keys painted by this stroke, in order, so the end of the stroke can
	-- style just those instead of the whole group when the group's look does
	-- not depend on its membership.
	self.strokeNewKeys = {} :: { Model }
	-- Groups the stroke changed the membership of, painted or erased: their
	-- gradients are derived from the members, so they need a restyle at the
	-- end of the stroke (once, not per key).
	self.strokeGroups = {} :: { [string]: true }
	self.strokeErased = 0
	self.recording = nil :: History.Recording
	-- Fired whenever rotation changes, so the UI can stay in sync even when
	-- the user rotates with the R key rather than the panel button.
	self.OnRotated = nil :: ((number) -> ())?
	-- Fired at the end of any stroke that actually changed the board, painted
	-- or erased. The panel's per-group key counts are derived from the board,
	-- so this is the one moment they can go stale without anything else in the
	-- UI moving. Carries nothing: the listener re-reads the counts itself.
	self.OnStrokeEnded = nil :: (() -> ())?
	return self
end

function Brush:_ensureGhost()
	if self.ghost then return end
	self.ghost = GhostPreview.new(Constants.KEY_SIZE)
	self.ghost:SetColor(self.tool == "Erase" and ERASE_GHOST_COLOR or PAINT_GHOST_COLOR)
end

-- What the brush's rays must not hit: every existing key, plus the ghost.
--
-- Filtering on the keys FOLDER rather than on CollectionService:GetTagged is
-- what keeps this cheap. GetTagged allocates an array of every key on the
-- board and hands the engine a filter list that grows with the build — at a
-- couple of raycasts per cell per mouse move, that was the whole reason
-- painting got slower the more keys existed. The folder is one instance, and
-- KeyPlacer parents every key into it.
function Brush:_rayFilter(): { Instance }
	local filter: { Instance } = {}

	local folder = workspace:FindFirstChild(Constants.KEYS_FOLDER)
	if folder then table.insert(filter, folder) end
	if self.ghost then table.insert(filter, self.ghost.container) end

	return filter
end

-- Every CFrame the brush covers right now, one per footprint cell.
--
-- snap=false is the eraser: it deletes whatever its box touches, wherever
-- that key was placed from. Snapping would make erasing a key that belongs to
-- another surface's grid a game of alignment.
function Brush:_cellFrames(snap: boolean): { CFrame }
	local unitRay = self.mouse.UnitRay

	-- Existing keys are transparent to the brush: aiming at one targets the
	-- surface underneath, so the new key lands exactly where the old one is
	-- and simply replaces it at placement time. The eraser wants the same
	-- thing for the opposite reason: it needs the surface, not the key, to
	-- lay its footprint out.
	local ignore = self:_rayFilter()

	local hit = SurfaceProbe.Probe(unitRay.Origin, unitRay.Direction * 1000, ignore)
	if not hit then return {} end

	local anchor = snap
		and GridSolver.Snap(hit.position, hit.origin, Constants.GRID_PITCH)
		or hit.position

	local reach = Constants.CELL_PROBE_REACH
	local frames: { CFrame } = {}

	for _, cell in ipairs(GridSolver.Footprint(self.brushSize)) do
		local cellPosition = GridSolver.OffsetByCell(anchor, hit.frame, cell, Constants.GRID_PITCH)

		-- Every cell gets its own probe, not just the aimed one: extrapolating
		-- the centre cell's plane would float keys over a ledge or a hole. No
		-- surface under the cell means no key there.
		local cellHit = SurfaceProbe.Probe(
			cellPosition + hit.normal * reach,
			-hit.normal * (reach * 2),
			ignore
		)
		if cellHit then
			-- Everything below comes from the CELL's own hit, never the aimed
			-- one: a footprint spilling off a plate onto the ground must lay
			-- those keys flat on the ground instead of keeping the plate's tilt.
			-- Re-snapping here for the same reason: a key belongs to the grid of
			-- the surface it actually landed on.
			local cellAnchor = snap
				and GridSolver.Snap(cellHit.position, cellHit.origin, Constants.GRID_PITCH)
				or cellPosition
			-- The cap rests on the surface: raise it by half its height along
			-- the local normal (local Y of the surface frame).
			local resting = cellAnchor + cellHit.normal * (Constants.KEY_SIZE.Y / 2)
			-- Rolled once per cell, at solve time, same as everything else in this
			-- loop: since placement uses the exact frames the ghost just showed,
			-- the key that lands is the rotation the player saw about to land.
			local steps = self.rotationRandom and math.random(0, 3) or self.rotationSteps
			table.insert(frames, GridSolver.BuildCFrame(resting, cellHit.frame, steps))
		end
	end

	return frames
end

-- Solve the footprint, show it, and act on it if a stroke is running — all
-- from ONE solve. Painting used to solve the footprint twice per mouse move
-- (once for the ghost, once to place), doubling an already per-cell raycast
-- cost for no reason.
function Brush:_refresh(applyIfPainting: boolean)
	self:_ensureGhost()
	local frames = self:_cellFrames(self.tool ~= "Erase")
	self.ghost:Show(frames)

	if applyIfPainting and self.painting then
		self:_applyTool(frames)
	end
end

function Brush:_updateGhost()
	self:_refresh(false)
end

function Brush:Rotate()
	self:SetRotation(self.rotationSteps + 1)
end

function Brush:SetRotation(steps: number)
	self.rotationRandom = false
	self.rotationSteps = steps % 4
	if self.ghost then
		self:_updateGhost()
	end
	if self.OnRotated then
		self.OnRotated(self.rotationSteps)
	end
end

function Brush:SetRotationRandom()
	self.rotationRandom = true
	if self.ghost then
		self:_updateGhost()
	end
end

function Brush:SetLetter(letter: string)
	self.currentLetter = letter
end

function Brush:SetLabelMode(mode: string)
	self.labelMode = mode
end

function Brush:SetLabelCharset(name: string)
	self.labelCharset = name
end

function Brush:SetTool(tool: string)
	self.tool = tool
	if self.ghost then
		self.ghost:SetColor(tool == "Erase" and ERASE_GHOST_COLOR or PAINT_GHOST_COLOR)
		self:_updateGhost()
	end
end

function Brush:SetEraseScope(scope: string)
	self.eraseScope = scope
end

function Brush:SetGroup(name: string)
	-- No Ensure here on purpose: the group is created at the first stroke, so
	-- merely picking a name never writes into the user's game.
	self.currentGroup = name
end

function Brush:SetSize(size: number)
	self.brushSize = math.max(1, math.floor(size))
	-- Only refresh an existing preview: resizing while the brush is off must
	-- not spawn a ghost in the user's Workspace.
	if self.ghost then
		self:_updateGhost()
	end
end

-- Places one cell. Returns the new key, or nil if the cell was left untouched.
function Brush:_placeCell(cframe: CFrame): Model?
	local overlapping = OverlapGuard.FindOverlapping(cframe, Constants.KEY_SIZE)

	for _, existing in ipairs(overlapping) do
		-- Placed by the stroke in progress: the user is dragging over ground
		-- they just covered, not asking to redo it. Leave the cell alone.
		if self.strokeKeys[existing] then return nil end
	end

	-- Only older keys here: a taken spot is not a refusal, they give way.
	for _, existing in ipairs(overlapping) do
		local group = existing:GetAttribute(Constants.ATTR_GROUP)
		if typeof(group) == "string" then
			self.strokeGroups[group] = true
		end
		existing:Destroy()
	end

	local label = LabelSource.Pick(self.labelMode, self.currentLetter, self.labelCharset)
	local key = KeyPlacer.Place(cframe, label, self.currentGroup)
	self.strokeKeys[key] = true
	table.insert(self.strokeNewKeys, key)
	return key
end

function Brush:_applyTool(frames: { CFrame })
	if self.tool == "Erase" then
		local touched, removed = Eraser.Erase(
			frames,
			Constants.KEY_SIZE,
			self.eraseScope,
			self.currentGroup
		)
		for group in pairs(touched) do
			self.strokeGroups[group] = true
		end
		self.strokeErased += removed
		return
	end

	self.strokeGroups[self.currentGroup] = true
	for _, cframe in ipairs(frames) do
		self:_placeCell(cframe)
	end
end

-- A whole stroke is ONE undo entry: undoing a drag of fifty keys must not
-- cost fifty Ctrl+Z. Same for erasing.
function Brush:_beginStroke()
	self.painting = true
	self.strokeKeys = {}
	self.strokeNewKeys = {}
	self.strokeGroups = {}
	self.strokeErased = 0
	self.recording = History.Begin(
		self.tool == "Erase" and "KeyCapper: erase keys" or "KeyCapper: place keys"
	)
	if self.tool ~= "Erase" then
		GroupRegistry.Ensure(self.currentGroup)
	end
	self:_refresh(true)
end

function Brush:_endStroke()
	if not self.painting then return end
	self.painting = false

	if next(self.strokeKeys) or self.strokeErased > 0 then
		for group in pairs(self.strokeGroups) do
			-- Styling only the keys this stroke added, when the group's look
			-- allows it. A full Apply walks and recolours every member, so a
			-- one-key stroke on a 500-key group used to cost 500 recolours —
			-- that is what made painting slow down as the build grew.
			-- GroupStyler decides: a gradient depends on the whole membership
			-- and still forces the full pass, an erase always does.
			local incremental = (self.strokeErased == 0) and group == self.currentGroup
			GroupStyler.Apply(group, incremental and self.strokeNewKeys or nil)
		end
		History.Commit(self.recording)
		-- After the commit, not before: the counts must describe the board as
		-- the undo entry leaves it.
		if self.OnStrokeEnded then
			self.OnStrokeEnded()
		end
	else
		History.Cancel(self.recording)
	end

	self.recording = nil
	self.strokeKeys = {}
	self.strokeNewKeys = {}
	self.strokeGroups = {}
end

function Brush:Activate()
	-- Takes the mouse focus: mandatory for the events below to fire at all.
	self.plugin:Activate(true)
	self:_ensureGhost()
	table.insert(self.connections, self.mouse.Move:Connect(function()
		-- Mouse.Move fires far more often than the footprint needs
		-- re-solving (one raycast per cell — 257 of them on a 16x16 brush).
		-- Capping to ~120Hz is well above what's visible but cuts a large
		-- share of redundant raycasts during a fast paint drag.
		local now = os.clock()
		if now - self._lastSolve < (1 / 120) then return end
		self._lastSolve = now
		self:_refresh(true)
	end))
	table.insert(self.connections, self.mouse.Button1Down:Connect(function()
		self:_beginStroke()
	end))
	table.insert(self.connections, self.mouse.Button1Up:Connect(function()
		self:_endStroke()
	end))
	table.insert(self.connections, self.mouse.KeyDown:Connect(function(key)
		if key:lower() == "r" then
			self:Rotate()
		end
	end))
end

function Brush:Deactivate()
	-- Never leave a recording open: it would swallow every later edit.
	self:_endStroke()
	self.plugin:Deactivate()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	self.connections = {}
	if self.ghost then
		self.ghost:Destroy()
		self.ghost = nil
	end
end

return Brush
