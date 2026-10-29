--[[ 

StudFollowers
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/StudFollowers

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Renders every player's equipped studs, locally, from the server-set
-- "EquippedStuds" player attribute. Purely cosmetic: parts are client-only,
-- anchored, and hidden past Config.Followers.RenderDistance (except your own).
-- Bigger variants (Big, Huge, Jumbo) are bigger parts and take more room in
-- the line. While the player's FightTarget attribute names an enemy
-- (Systems/Combat) the studs surround it and take turns lunging at it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local RollLogic = require(Shared.Util.RollLogic)
local StudVisuals = require(Shared.Util.StudVisuals)
local Tags = require(Shared.Tags)

local FollowConfig = Config.Followers
local localPlayer = Players.LocalPlayer

local StudFollowers = {}

type Follower = { part: BasePart, phase: number, size: number }
type Entry = { followers: { Follower }, connection: RBXScriptConnection, visible: boolean }

local entries: { [Player]: Entry } = {}
local container: Folder
local showOthers = true

local function clearFollowers(entry: Entry)
	for _, follower in entry.followers do
		follower.part:Destroy()
	end
	table.clear(entry.followers)
end

local function rebuild(player: Player)
	local entry = entries[player]
	if not entry then return end
	clearFollowers(entry)

	local raw = player:GetAttribute("EquippedStuds")
	if typeof(raw) ~= "string" or raw == "" then return end

	for _, key in string.split(raw, ",") do
		local def, variant = RollLogic.decodeKey(key)
		if def and variant then
			local part = StudVisuals.build(def, variant)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				part.CFrame = root.CFrame -- start at the player, not the world origin
			end
			part.Parent = if entry.visible then container else nil
			table.insert(entry.followers, { part = part, phase = math.random() * math.pi * 2, size = part.Size.Y })
		end
	end
end

local function track(player: Player)
	if entries[player] then return end
	local entry: Entry = {
		followers = {},
		visible = true,
		connection = player:GetAttributeChangedSignal("EquippedStuds"):Connect(function()
			rebuild(player)
		end),
	}
	entries[player] = entry
	rebuild(player)
end

local function untrack(player: Player)
	local entry = entries[player]
	if not entry then return end
	entry.connection:Disconnect()
	clearFollowers(entry)
	entries[player] = nil
end

-- Slots in a shallow arc behind the player, wider apart for bigger studs.
local function slotOffsets(followers: { Follower }): { Vector3 }
	local widths: { number } = {}
	local total = 0
	for i, follower in followers do
		widths[i] = math.max(FollowConfig.Spacing, follower.size + 0.8)
		total += widths[i]
	end
	local offsets: { Vector3 } = {}
	local x = -total / 2
	for i, follower in followers do
		local centre = x + widths[i] / 2
		x += widths[i]
		local z = FollowConfig.BackOffset + math.abs(centre) * 0.25 + (follower.size - 1) * 0.5
		offsets[i] = Vector3.new(centre, FollowConfig.Height + (follower.size - 1) / 2, z)
	end
	return offsets
end

-- Enemy models by EnemyId (Systems/Combat tags them Enemy).
local enemyModels: { [number]: Model } = {}

local function trackEnemy(instance: Instance)
	local id = instance:GetAttribute("EnemyId")
	if typeof(id) == "number" and instance:IsA("Model") then
		enemyModels[id] = instance
	end
end

local function untrackEnemy(instance: Instance)
	local id = instance:GetAttribute("EnemyId")
	if typeof(id) == "number" and enemyModels[id] == instance then
		enemyModels[id] = nil
	end
end

-- The enemy this player is fighting, if it's here.
local function fightTarget(player: Player): BasePart?
	local id = player:GetAttribute("FightTarget")
	local model = if typeof(id) == "number" then enemyModels[id] else nil
	local body = model and model.PrimaryPart
	return if body and body.Parent then body else nil
end

local function setVisible(entry: Entry, visible: boolean)
	if entry.visible == visible then return end
	entry.visible = visible
	for _, follower in entry.followers do
		follower.part.Parent = if visible then container else nil
	end
end

local function update(dt: number)
	local t = os.clock()
	local camera = workspace.CurrentCamera
	local cameraPos = camera and camera.CFrame.Position or Vector3.zero
	local alpha = 1 - math.exp(-FollowConfig.FollowSpeed * dt)

	for player, entry in entries do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) or #entry.followers == 0 then
			setVisible(entry, false)
			continue
		end

		local isLocal = player == localPlayer
		local inRange = isLocal
			or (showOthers and (root.Position - cameraPos).Magnitude <= FollowConfig.RenderDistance)
		setVisible(entry, inRange)
		if not inRange then continue end

		-- Flatten the root's facing so studs don't tilt when the character does.
		local look = root.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude < 1e-3 then
			flatLook = Vector3.new(0, 0, -1)
		end
		local basis = CFrame.lookAt(root.Position, root.Position + flatLook.Unit)

		local total = #entry.followers
		local enemy = fightTarget(player)
		local offsets = if enemy then nil else slotOffsets(entry.followers)
		for i, follower in entry.followers do
			local part = follower.part
			local position: Vector3
			local spin: CFrame
			if enemy then
				-- A ring around the enemy; each stud lunges in on its own beat.
				local angle = (i / total) * math.pi * 2 + t * 0.6
				local reach = enemy.Size.X / 2 + 1.5 + follower.size
				local lunge = math.max(0, math.sin(t * 7 + follower.phase)) ^ 6
				local radius = reach - lunge * (reach - enemy.Size.X / 2 - follower.size / 2)
				local goal = enemy.Position + Vector3.new(math.cos(angle) * radius, follower.size / 2 - enemy.Size.Y * 0.15, math.sin(angle) * radius)
				position = part.Position:Lerp(goal, 1 - math.exp(-FollowConfig.FollowSpeed * 1.6 * dt))
				spin = CFrame.Angles(lunge * 1.2, t * 3 + follower.phase, 0)
			else
				local bob = math.sin(t * FollowConfig.BobSpeed + follower.phase) * FollowConfig.BobHeight
				local target = basis * CFrame.new((offsets :: { Vector3 })[i] + Vector3.new(0, bob, 0))
				position = part.Position:Lerp(target.Position, alpha)
				spin = CFrame.Angles(0, t * 0.8 + follower.phase, 0)
			end
			part.CFrame = CFrame.new(position) * spin
			StudVisuals.step(part, t)
		end
	end
end

-- Options toggle: hide every other player's studs (yours always show).
function StudFollowers.setShowOthers(value: boolean)
	showOthers = value
end

function StudFollowers.init()
	container = Instance.new("Folder")
	container.Name = "StudFollowers"
	container.Parent = workspace
end

function StudFollowers.start()
	for _, enemy in CollectionService:GetTagged(Tags.Enemy) do
		trackEnemy(enemy)
	end
	CollectionService:GetInstanceAddedSignal(Tags.Enemy):Connect(trackEnemy)
	CollectionService:GetInstanceRemovedSignal(Tags.Enemy):Connect(untrackEnemy)
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	RunService.RenderStepped:Connect(update)
end

return StudFollowers
