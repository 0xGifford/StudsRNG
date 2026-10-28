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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local RollLogic = require(Shared.Util.RollLogic)
local StudVisuals = require(Shared.Util.StudVisuals)

local FollowConfig = Config.Followers
local localPlayer = Players.LocalPlayer

local StudFollowers = {}

type Follower = { part: BasePart, phase: number }
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
			table.insert(entry.followers, { part = part, phase = math.random() * math.pi * 2 })
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

-- Slots in a shallow arc behind the player.
local function slotOffset(index: number, total: number): Vector3
	local centered = index - (total + 1) / 2
	local x = centered * FollowConfig.Spacing
	local z = FollowConfig.BackOffset + math.abs(centered) * 0.6
	return Vector3.new(x, FollowConfig.Height, z)
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
		for i, follower in entry.followers do
			local bob = math.sin(t * FollowConfig.BobSpeed + follower.phase) * FollowConfig.BobHeight
			local target = basis * CFrame.new(slotOffset(i, total) + Vector3.new(0, bob, 0))
			local spin = CFrame.Angles(0, t * 0.8 + follower.phase, 0)
			local part = follower.part
			local position = part.Position:Lerp(target.Position, alpha)
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
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	RunService.RenderStepped:Connect(update)
end

return StudFollowers
