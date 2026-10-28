--[[ 

PressTracker
ModuleScript
/ServerScriptService/Server/Systems/PressTracker

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Server-authoritative keypress detection. KeyCapper's client handles the
-- animation and sound; this module independently decides which keys a player
-- actually stepped on, so Clacks never depend on anything the client reports.
--
-- Each sample sweeps a box from the player's previous feet position to the
-- current one, so fast players don't skip keys between samples. A key counts
-- as a press when it's inside the sweep but wasn't under the player's feet at
-- the end of the previous sample. Movement faster than the player's server-side
-- WalkSpeed allows is treated as a teleport and earns nothing.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Signal = require(Shared.Util.Signal)

local PressConfig = Config.Press

local PressTracker = {}

-- (player, pressCount, clackValueSum)
PressTracker.Pressed = Signal.new() :: Signal.Signal<Player, number, number>

type KeyInfo = { value: number, world: string? }
type Tracked = { lastFeet: Vector3?, touching: { [BasePart]: boolean } }

local LEG_PARTS = { "LeftFoot", "RightFoot", "Left Leg", "Right Leg" }

local hitboxes: { [BasePart]: KeyInfo } = {}
local hitboxList: { Instance } = {}
local listDirty = true
local tracked: { [Player]: Tracked } = {}
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include

local function readKeyInfo(hitbox: BasePart): KeyInfo
	local model = hitbox.Parent
	local value = model and model:GetAttribute(PressConfig.AttrValue)
	local world = model and model:GetAttribute(PressConfig.AttrWorld)
	return {
		value = if typeof(value) == "number" and value > 0 then value else PressConfig.DefaultKeyValue,
		world = if typeof(world) == "string" then world else nil,
	}
end

local function addHitbox(instance: Instance)
	if not instance:IsA("BasePart") then return end
	hitboxes[instance] = readKeyInfo(instance)
	listDirty = true
end

local function removeHitbox(instance: Instance)
	if hitboxes[instance :: BasePart] then
		hitboxes[instance :: BasePart] = nil
		listDirty = true
	end
end

local function refreshFilter()
	if not listDirty then return end
	listDirty = false
	table.clear(hitboxList)
	for part in hitboxes do
		table.insert(hitboxList, part)
	end
	overlapParams.FilterDescendantsInstances = hitboxList
end

-- Lowest leg bottom: works for R6 and R15 (same approach as KeyCapper).
local function getFeet(character: Model): (Vector3?, Humanoid?)
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart")) or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end

	local sole: number? = nil
	for _, name in LEG_PARTS do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local bottom = part.Position.Y - part.Size.Y / 2
			if not sole or bottom < sole then
				sole = bottom
			end
		end
	end

	if sole then
		return Vector3.new(root.Position.X, sole, root.Position.Z), humanoid
	end
	return root.Position - Vector3.new(0, root.Size.Y / 2 + humanoid.HipHeight, 0), humanoid
end

local function query(cframe: CFrame, size: Vector3): { BasePart }
	return workspace:GetPartBoundsInBox(cframe, size, overlapParams)
end

local function sample(player: Player, state: Tracked, dt: number)
	local character = player.Character
	local feet, humanoid = nil, nil
	if character then
		feet, humanoid = getFeet(character)
	end
	if not feet or not humanoid then
		state.lastFeet = nil
		table.clear(state.touching)
		return
	end

	local box = PressConfig.FeetBoxSize
	local hereHits = query(CFrame.new(feet), box)
	local nowTouching: { [BasePart]: boolean } = {}
	for _, part in hereHits do
		nowTouching[part] = true
	end

	local last = state.lastFeet
	state.lastFeet = feet

	local sweepHits: { BasePart } = hereHits
	if last then
		local delta = feet - last
		local flat = Vector3.new(delta.X, 0, delta.Z)
		local flatDistance = flat.Magnitude
		local maxStep = humanoid.WalkSpeed * dt * PressConfig.SpeedSlack + PressConfig.TeleportSlack

		if flatDistance > maxStep then
			-- Teleport, fling or speed exploit: no presses for this sample.
			state.touching = nowTouching
			return
		end

		if flatDistance > 0.05 or math.abs(delta.Y) > 0.05 then
			local mid = (feet + last) / 2
			local height = box.Y + math.abs(delta.Y)
			if flatDistance > 0.05 then
				local cf = CFrame.lookAt(mid, mid + flat)
				sweepHits = query(cf, Vector3.new(box.X, height, flatDistance + box.Z))
			else
				sweepHits = query(CFrame.new(mid), Vector3.new(box.X, height, box.Z))
			end
		end
	end

	local count = 0
	local valueSum = 0
	for _, part in sweepHits do
		if not state.touching[part] then
			local info = hitboxes[part]
			if info then
				count += 1
				valueSum += info.value
				if count >= PressConfig.MaxPressesPerSample then
					break
				end
			end
		end
	end

	state.touching = nowTouching

	if count > 0 then
		PressTracker.Pressed:Fire(player, count, valueSum)
	end
end

function PressTracker.init()
	for _, instance in CollectionService:GetTagged(PressConfig.HitboxTag) do
		addHitbox(instance)
	end
	CollectionService:GetInstanceAddedSignal(PressConfig.HitboxTag):Connect(addHitbox)
	CollectionService:GetInstanceRemovedSignal(PressConfig.HitboxTag):Connect(removeHitbox)

	Players.PlayerAdded:Connect(function(player)
		tracked[player] = { lastFeet = nil, touching = {} }
	end)
	for _, player in Players:GetPlayers() do
		tracked[player] = { lastFeet = nil, touching = {} }
	end
	Players.PlayerRemoving:Connect(function(player)
		tracked[player] = nil
	end)
end

function PressTracker.start()
	local interval = 1 / PressConfig.SampleRate
	local lastTime = os.clock()
	while true do
		task.wait(interval)
		local now = os.clock()
		local dt = now - lastTime
		lastTime = now

		refreshFilter()
		if #hitboxList > 0 then
			for player, state in tracked do
				sample(player, state, dt)
			end
		end
	end
end

return PressTracker
