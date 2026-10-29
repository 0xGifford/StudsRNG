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
--
-- Each key belongs to a zone (Shared/Tags.keyZone: the key Model's World,
-- else its Keyboard's or Zone's ZoneId). Its Value (else its Keyboard's
-- KeyValue) is multiplied by the Keyboard's Multiplier and the zone's
-- KeyMultiplier, and the filter set by Economy drops keys in zones the
-- player doesn't own. A key or Keyboard with Enabled = false never pays.
-- Attribute changes on keys, Keyboards and Zones are picked up live.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Zones = require(Shared.Zones)
local Signal = require(Shared.Util.Signal)
local Tags = require(Shared.Tags)

local PressConfig = Config.Press

local PressTracker = {}

-- (player, pressCount, clackValueSum)
PressTracker.Pressed = Signal.new() :: Signal.Signal<Player, number, number>
-- (player, hitboxes pressed this sample) — only keys that paid out
PressTracker.KeysPressed = Signal.new() :: Signal.Signal<Player, { BasePart }>

type KeyInfo = { value: number, world: string?, enabled: boolean }
type Tracked = { lastFeet: Vector3?, touching: { [BasePart]: boolean } }

local LEG_PARTS = { "LeftFoot", "RightFoot", "Left Leg", "Right Leg" }

local hitboxes: { [BasePart]: KeyInfo } = {}
local hitboxList: { Instance } = {}
local listDirty = true
local infoDirty = false
local keyConnections: { [BasePart]: RBXScriptConnection } = {}
local tracked: { [Player]: Tracked } = {}
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include

-- (player, zoneId?) -> may this player earn from a key in that zone?
local filter: ((Player, string?) -> boolean)? = nil

local function readKeyInfo(hitbox: BasePart): KeyInfo
	local model = hitbox.Parent
	if not model then
		return { value = 0, world = nil, enabled = false }
	end
	local keyboard = Tags.ancestorWith(model, Tags.Keyboard)
	local world = Tags.keyZone(hitbox)
	local zone = if world then Zones.ById[world] else nil

	local value = model:GetAttribute(PressConfig.AttrValue)
	if not (typeof(value) == "number" and value > 0) then
		value = if keyboard then Tags.read(keyboard, Tags.Attr.KeyValue, PressConfig.DefaultKeyValue) else PressConfig.DefaultKeyValue
	end
	local multiplier = if keyboard then Tags.read(keyboard, Tags.Attr.Multiplier, 1) else 1
	local enabled = Tags.read(model, Tags.Attr.Enabled, true) and (keyboard == nil or Tags.read(keyboard, Tags.Attr.Enabled, true))
	return {
		value = (value :: number) * multiplier * (if zone then zone.KeyMultiplier else 1),
		world = world,
		enabled = enabled,
	}
end

local function addHitbox(instance: Instance)
	if not instance:IsA("BasePart") or hitboxes[instance] then return end
	hitboxes[instance] = readKeyInfo(instance)
	listDirty = true
	local model = instance.Parent
	if model then
		keyConnections[instance] = model.AttributeChanged:Connect(function()
			if hitboxes[instance] then
				hitboxes[instance] = readKeyInfo(instance)
			end
		end)
	end
end

local function removeHitbox(instance: Instance)
	if hitboxes[instance :: BasePart] then
		hitboxes[instance :: BasePart] = nil
		listDirty = true
	end
	local connection = keyConnections[instance :: BasePart]
	if connection then
		connection:Disconnect()
		keyConnections[instance :: BasePart] = nil
	end
end

-- A Keyboard or Zone changed: every key may have a new zone or value.
local function refreshInfo()
	if not infoDirty then return end
	infoDirty = false
	for part in hitboxes do
		hitboxes[part] = readKeyInfo(part)
	end
end

local function watchContainer(tag: string)
	local function watch(instance: Instance)
		infoDirty = true
		instance.AttributeChanged:Connect(function()
			infoDirty = true
		end)
	end
	for _, instance in CollectionService:GetTagged(tag) do
		watch(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(watch)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function()
		infoDirty = true
	end)
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
	local pressed: { BasePart } = {}
	for _, part in sweepHits do
		if not state.touching[part] then
			local info = hitboxes[part]
			if info and info.enabled and (filter == nil or filter(player, info.world)) then
				count += 1
				valueSum += info.value
				table.insert(pressed, part)
				if count >= PressConfig.MaxPressesPerSample then
					break
				end
			end
		end
	end

	state.touching = nowTouching

	if count > 0 then
		PressTracker.Pressed:Fire(player, count, valueSum)
		PressTracker.KeysPressed:Fire(player, pressed)
	end
end

-- Every key hitbox currently known (a fresh list).
function PressTracker.getHitboxes(): { BasePart }
	local list: { BasePart } = {}
	for part in hitboxes do
		table.insert(list, part)
	end
	return list
end

-- A key's zone, or nil when it pays everywhere / isn't a key.
function PressTracker.zoneOf(hitbox: BasePart): string?
	local info = hitboxes[hitbox]
	return info and info.world
end

-- Whether a key currently pays at all (Enabled on it and its Keyboard).
function PressTracker.isEnabled(hitbox: BasePart): boolean
	local info = hitboxes[hitbox]
	return info ~= nil and info.enabled
end

-- Economy sets this so keys in unowned zones never pay.
function PressTracker.setFilter(fn: (Player, string?) -> boolean)
	filter = fn
end

function PressTracker.init()
	for _, instance in CollectionService:GetTagged(PressConfig.HitboxTag) do
		addHitbox(instance)
	end
	CollectionService:GetInstanceAddedSignal(PressConfig.HitboxTag):Connect(addHitbox)
	CollectionService:GetInstanceRemovedSignal(PressConfig.HitboxTag):Connect(removeHitbox)
	watchContainer(Tags.Keyboard)
	watchContainer(Tags.Zone)

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
		refreshInfo()
		if #hitboxList > 0 then
			for player, state in tracked do
				sample(player, state, dt)
			end
		end
	end
end

return PressTracker
