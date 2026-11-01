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
-- (Systems/Combat) the studs break off, fly to it and hover around it, each
-- one in turn winding up and dashing in; when the attribute clears they fly
-- back into line (or straight on to the next enemy the server picks).
-- Flying and fighting studs leave a trail; each dash that connects pops a
-- ring at the point of contact (UI/CombatFx).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local RollLogic = require(Shared.Util.RollLogic)
local StudVisuals = require(Shared.Util.StudVisuals)
local Tags = require(Shared.Tags)

local UI = script.Parent.Parent:WaitForChild("UI")
local CombatFx = require(UI.CombatFx)
local Format = require(UI.Format)
local Roles = require(UI.Roles)
local EnemyVisuals = require(script.Parent.EnemyVisuals)

local FollowConfig = Config.Followers

-- One attack cycle per stud: hover, wind up, dash in, recoil.
local ATTACK_PERIOD = 1.5
local HOVER_END, WINDUP_END, DASH_END = 0.55, 0.72, 0.8
-- Further than this from where it should be, a stud flies there at FLY_SPEED
-- (so leaving for an enemy and coming back read as a flight, not a snap).
local FLY_DISTANCE = 5
local FLY_SPEED = 50 -- studs per second

-- Moves `from` towards `goal`: a steady flight when far, an eased settle
-- when close.
local function approach(from: Vector3, goal: Vector3, dt: number, ease: number): Vector3
	local offset = goal - from
	local distance = offset.Magnitude
	if distance > FollowConfig.RenderDistance then
		return goal -- teleported: no cross-map flight
	elseif distance > FLY_DISTANCE then
		return from + offset.Unit * math.min(distance - FLY_DISTANCE * 0.5, FLY_SPEED * dt)
	end
	return from:Lerp(goal, 1 - math.exp(-ease * dt))
end
local localPlayer = Players.LocalPlayer

local StudFollowers = {}

type Follower = { part: BasePart, phase: number, size: number, trail: Trail, lastU: number }
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
				StudVisuals.place(part, root.CFrame) -- start at the player, not the world origin
			end
			part.Parent = if entry.visible then container else nil
			-- A short streak behind it while it flies or fights.
			local top = Instance.new("Attachment")
			top.Position = Vector3.new(0, part.Size.Y * 0.4, 0)
			top.Parent = part
			local bottom = Instance.new("Attachment")
			bottom.Position = Vector3.new(0, -part.Size.Y * 0.4, 0)
			bottom.Parent = part
			local trail = Instance.new("Trail")
			trail.Attachment0 = top
			trail.Attachment1 = bottom
			trail.Color = ColorSequence.new(part.Color:Lerp(Color3.new(1, 1, 1), 0.35))
			trail.Transparency = NumberSequence.new(0.35, 1)
			trail.LightEmission = 0.6
			trail.Lifetime = 0.22
			trail.FaceCamera = true
			trail.Enabled = false
			trail.Parent = part
			-- Your own Shiny / Inverted studs glow through the world with a
			-- Highlight (Roblox draws ~31 at once, so only yours: at most 12).
			if player == localPlayer and variant.Outline then
				local highlight = Instance.new("Highlight")
				highlight.Name = "VariantHighlight"
				highlight.FillColor = variant.Outline
				highlight.FillTransparency = 0.8
				highlight.OutlineColor = variant.Outline
				highlight.OutlineTransparency = 0
				highlight.DepthMode = Enum.HighlightDepthMode.Occluded
				highlight.Adornee = StudVisuals.adorneeOf(part)
				highlight.Parent = part
			end
			-- Odds and name floating over it ("1/3.07M" / "Stormy"): a copy of
			-- StarterGui.WorldUI's StudNametag.
			local tag = Roles.template(Roles.gui("WorldUI"), "StudNametag") :: BillboardGui
			tag.Name = "Nametag"
			tag.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 0.9, 0)
			if player ~= localPlayer then
				-- Others' tags show from half as far (the camera's own
				-- distance, Roles.distanceBonus, isn't halved).
				tag.MaxDistance = (tag.MaxDistance - Roles.distanceBonus) / 2 + Roles.distanceBonus
			end
			local rarity = if def.Rarity == "Secret" then Color3.new(1, 1, 1) else Config.Rarities.Colors[def.Rarity] or Color3.new(1, 1, 1)
			local odds = Roles.find(tag, "NametagRole", "Odds")
			if odds then
				odds.Text = `1/{Format.number(def.OneIn * variant.OneIn)}`
			end
			local name = Roles.find(tag, "NametagRole", "Name")
			if name then
				name.Text = Format.studName(def, variant)
				name.TextColor3 = rarity
			end
			tag.Parent = part
			table.insert(entry.followers, { part = part, phase = math.random() * math.pi * 2, size = part.Size.Y, trail = trail, lastU = 0 })
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
	if not model then return nil end
	-- Orbit the drawn monster (smooth); the server proxy (Body; PrimaryPart
	-- can lag behind under streaming) if it isn't drawn yet.
	local visual = EnemyVisuals.rootOf(model)
	if visual and visual.Parent then return visual end
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	return if body and body:IsA("BasePart") and body.Parent then body else nil
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
	local cameraPos = camera and camera.Focus.Position or Vector3.zero -- what it looks at (IsoCamera)

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
				-- Hover on a slowly turning ring around the enemy. Studs are
				-- staggered through the cycle so they dash in one after another.
				local angle = (i / total) * math.pi * 2 + t * 0.5
				local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
				local surface = enemy.Size.X / 2 + follower.size / 2
				local hover = surface + 2 + follower.size
				local u = ((t + (i - 1) / total * ATTACK_PERIOD + follower.phase * 0.05) / ATTACK_PERIOD) % 1
				local radius, lift, tilt, speed = hover, 0, 0, 3
				if u < HOVER_END then
					lift = math.sin(t * 2.5 + follower.phase) * 0.6
				elseif u < WINDUP_END then
					-- Pull back and rise, tilting away.
					local k = (u - HOVER_END) / (WINDUP_END - HOVER_END)
					local ease = k * k * (3 - 2 * k)
					radius = hover + ease * 1.5
					lift = ease * 1.2
					tilt = -ease * 0.6
				elseif u < DASH_END then
					-- Snap into the enemy.
					radius = surface - 0.2
					lift = 0
					tilt = 1.1
					speed = 14
				else
					-- Bounce back out to the ring.
					local k = (u - DASH_END) / (1 - DASH_END)
					radius = surface + k * (hover - surface)
					lift = math.sin(k * math.pi) * 0.8
					tilt = (1 - k) * 0.8
				end
				-- The dash connects: a ring where it hits.
				local strike = (WINDUP_END + DASH_END) / 2
				if follower.lastU < strike and u >= strike then
					CombatFx.impact(enemy.Position + outward * (enemy.Size.X / 2), part.Color:Lerp(Color3.new(1, 1, 1), 0.5), follower.size)
				end
				follower.lastU = u
				local goal = enemy.Position + outward * radius + Vector3.new(0, follower.size / 2 - enemy.Size.Y * 0.1 + lift, 0)
				position = approach(part.Position, goal, dt, FollowConfig.FollowSpeed * speed)
				follower.trail.Enabled = true
				-- Face the enemy, tipping forward into the dash.
				local facing = CFrame.lookAt(Vector3.zero, -outward)
				spin = facing.Rotation * CFrame.Angles(-tilt, 0, 0) * CFrame.Angles(0, t * 2 + follower.phase, 0)
			else
				local bob = math.sin(t * FollowConfig.BobSpeed + follower.phase) * FollowConfig.BobHeight
				local target = basis * CFrame.new((offsets :: { Vector3 })[i] + Vector3.new(0, bob, 0))
				position = approach(part.Position, target.Position, dt, FollowConfig.FollowSpeed)
				follower.trail.Enabled = (target.Position - part.Position).Magnitude > FLY_DISTANCE
				spin = CFrame.Angles(0, t * 0.8 + follower.phase, 0)
			end
			StudVisuals.place(part, CFrame.new(position) * spin)
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
