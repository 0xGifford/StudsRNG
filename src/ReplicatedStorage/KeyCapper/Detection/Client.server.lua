--!strict
-- Single responsibility: DETECTION.
-- Ticks at a fixed rate, tests a box at the player's feet against the
-- hitboxes, and drives the Keycap objects. Knows nothing about animation or sound.
--
-- RunContext = Client: placed directly under ReplicatedStorage.KeyCapper,
-- the whole module lives in one place, no need for StarterPlayerScripts.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- This script's own folder (Detection): where its sibling KeycapRegistry
-- lives. KeyCapperFolder is one level up — the installed root
-- (ReplicatedStorage.KeyCapper) — where the shared singletons and the
-- Points subfolder live.
local DetectionFolder = script.Parent
local KeyCapperFolder = DetectionFolder.Parent
local Config = require(KeyCapperFolder:WaitForChild("Config"))
local KeycapRegistry = require(DetectionFolder:WaitForChild("KeycapRegistry"))
local Settings = require(KeyCapperFolder:WaitForChild("Settings"))

-- A RunContext = Client script starts as soon as IT replicates, which is not
-- the same moment the client is fully set up: LocalPlayer can still be nil,
-- and this folder's siblings may not have arrived yet. Both were assumed
-- present below, and either one missing killed this script outright — no
-- animation, no sound, nothing, for the whole session. That is the "it just
-- does nothing until I touch something in the panel" report: the panel edit
-- was never the fix, reloading into a luckier ordering was.
while not Players.LocalPlayer do
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
end
local player = Players.LocalPlayer

-- Public: a technical dev listens with
-- ReplicatedStorage.KeyCapper.KeyPressed.Event:Connect(function(model, letter) ... end).
-- Fires on every local press regardless of the points system being on —
-- it is not part of the points feature, just piggybacking on the same
-- detection loop that already knows a press just happened.
local keyPressedEvent = KeyCapperFolder:WaitForChild(Config.KEY_PRESSED_EVENT) :: BindableEvent

-- Read once at startup: these are Studio-side toggles the developer flips
-- rarely, not something that needs to react mid-session.
local pointsEnabled = Settings.GetValue("PointsEnabled")
local autoUIEnabled = pointsEnabled and Settings.GetValue("AutoUIEnabled")
local pendingPoints = 0
-- Both are filled in by the points bootstrap at the bottom of this file, which
-- runs in its own thread. Detection must never wait on them: the points system
-- depends on the SERVER having built the player's data folder, and anything
-- that stops it doing so (DataStore trouble, the toggle read differently on
-- the two sides) used to hang this script before the first key was ever
-- registered. Presses are the feature; points are an extra.
local remote: RemoteEvent? = nil
local PointsUI: any = nil

local registry = KeycapRegistry.new()
registry:Start()

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include

-- The parts whose bottom face IS the sole, in both rigs. R15 names first,
-- R6's two legs after: a character only ever has one set.
local LEG_PARTS = { "LeftFoot", "RightFoot", "Left Leg", "Right Leg" }

-- Feet position, measured from the legs themselves rather than derived from
-- the root.
--
-- The old form was root.Position - (root.Size.Y/2 + HipHeight), which is only
-- correct on R15. On R6 the root sits at the TORSO and HipHeight is 0, so that
-- landed roughly two studs above the ground: the test box floated at knee
-- height and never touched a single cap. That is the whole of "it doesn't work
-- on R6": detection, and therefore animation, sound and points, all silently
-- off for anyone using the R6 rig.
--
-- Taking the lowest leg bottom needs no per-rig arithmetic at all, and stays
-- right while walking or on a slope. HipHeight is kept only as a fallback for
-- a character whose limbs haven't replicated yet.
local function getFeetCFrame(): CFrame?
	local character = player.Character
	if not character then return nil end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end

	local sole: number? = nil
	for _, name in ipairs(LEG_PARTS) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local bottom = part.Position.Y - part.Size.Y / 2
			if not sole or bottom < sole then
				sole = bottom
			end
		end
	end

	if sole then
		return CFrame.new(root.Position.X, sole, root.Position.Z)
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	return CFrame.new(root.Position - Vector3.new(0, root.Size.Y / 2 + humanoid.HipHeight, 0))
end

local STEP = 1 / Config.TICK_RATE
local accumulator = 0
local touchingLastTick: { [BasePart]: boolean } = {}

RunService.Heartbeat:Connect(function(deltaTime: number)
	accumulator += deltaTime
	if accumulator < STEP then return end
	accumulator -= STEP

	local touchingNow: { [BasePart]: boolean } = {}

	local feet = getFeetCFrame()
	if feet then
		overlapParams.FilterDescendantsInstances = registry:GetFilterList()
		local hits = workspace:GetPartBoundsInBox(feet, Config.FEET_BOX_SIZE, overlapParams)
		for _, part in ipairs(hits) do
			touchingNow[part] = true
		end
	end

	-- Diff against the previous tick. We only iterate over the keys involved
	-- (a handful), never over every loaded key: the cost stays constant
	-- even with a keyboard of several hundred keys.
	for hitbox in pairs(touchingNow) do
		if not touchingLastTick[hitbox] then
			local keycap = registry:Get(hitbox)
			if keycap then
				keycap:Press()
				keyPressedEvent:Fire(hitbox.Parent, hitbox.Parent and hitbox.Parent:GetAttribute("Letter"))
				if pointsEnabled then
					pendingPoints += 1
					-- PointsUI is nil until the bootstrap below has it: presses
					-- before that still count, they just don't pop a "+1".
					if PointsUI then
						PointsUI.Notify(keycap.cap.Position)
					end
				end
			end
		end
	end

	for hitbox in pairs(touchingLastTick) do
		if not touchingNow[hitbox] then
			local keycap = registry:Get(hitbox)
			if keycap then keycap:Release() end
		end
	end

	touchingLastTick = touchingNow
end)

-- Everything points-related, off the critical path — see the note next to the
-- `remote` declaration. The flush loop batches the pending count instead of
-- firing per press: at TICK_RATE=30 a fast typist could otherwise fire dozens
-- of remote events a second. Only the running total since the last flush is
-- ever sent.
if pointsEnabled then
	task.spawn(function()
		local pointsFolder = KeyCapperFolder:WaitForChild("Points")
		remote = pointsFolder:WaitForChild("PointsRemote") :: RemoteEvent

		if autoUIEnabled then
			local ui = require(pointsFolder:WaitForChild("PointsUI"))
			-- Server.lua builds this under the Player as soon as it joins.
			-- Waited on HERE rather than at the top of the file: if the server
			-- never builds it, this thread is the only thing that stalls.
			local dataFolder = player:WaitForChild(Config.POINTS_DATA_FOLDER)
			local pointsValue = dataFolder:WaitForChild(Config.POINTS_VALUE_NAME) :: IntValue
			ui.Init(pointsValue)
			PointsUI = ui
		end

		while true do
			task.wait(Config.POINTS_BATCH_INTERVAL)
			local target = remote
			if pendingPoints > 0 and target then
				local toSend = pendingPoints
				pendingPoints = 0
				target:FireServer(toSend)
			end
		end
	end)
end

-- Under StreamingEnabled this count is normally 0 at startup: keys register
-- themselves as they stream in.
if Config.DEBUG then
	print(string.format("[KeyCapper] client started - %d key(s) initially", registry:Count()))
end
