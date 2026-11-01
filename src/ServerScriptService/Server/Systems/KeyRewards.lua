--[[

KeyRewards
ModuleScript
/ServerScriptService/Server/Systems/KeyRewards

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Reward tiles. Every Config.KeyRewards.Interval a random key becomes a
-- tile of a random kind (Config.KeyRewards.Kinds, by weight: "+1" free roll,
-- 💰 Golden Clacks, 🍀 Lucky boost, ⚡ Frenzy): its Model gets RewardTile =
-- the kind's Text and RewardTileKind = its Id (clients draw them). The
-- first player whose press PressTracker counts on that key claims it: the
-- tile clears and they get that kind's Reward. Unclaimed tiles expire
-- after Lifetime. Presses only count in zones the player owns, so locked
-- zones' tiles can't be claimed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local PressTracker = require(Systems.PressTracker)
local RewardService = require(Systems.RewardService)
local QuestService = require(Systems.QuestService)

type Reward = Types.Reward

local KeyRewards = {}

local Settings = Config.KeyRewards
local rng = Random.new()

-- hitbox → server time the tile expires, and the kind of tile it is
local active: { [BasePart]: number } = {}
local kinds: { [BasePart]: any } = {}

local totalWeight = 0
for _, kind in Settings.Kinds do
	totalWeight += kind.Weight
end

local function pickKind(): any
	local roll = rng:NextNumber() * totalWeight
	for _, kind in Settings.Kinds do
		roll -= kind.Weight
		if roll <= 0 then
			return kind
		end
	end
	return Settings.Kinds[1]
end

local function modelOf(hitbox: BasePart): Instance?
	return hitbox.Parent
end

local function clear(hitbox: BasePart)
	active[hitbox] = nil
	kinds[hitbox] = nil
	local model = modelOf(hitbox)
	if model then
		model:SetAttribute(Settings.Attribute, nil)
		model:SetAttribute(Settings.KindAttribute, nil)
	end
end

local function count(): number
	local n = 0
	for _ in active do
		n += 1
	end
	return n
end

local function activate(hitbox: BasePart): boolean
	local model = modelOf(hitbox)
	if not model or active[hitbox] or not hitbox:IsDescendantOf(workspace) then return false end
	local kind = pickKind()
	active[hitbox] = os.clock() + Settings.Lifetime
	kinds[hitbox] = kind
	model:SetAttribute(Settings.KindAttribute, kind.Id)
	model:SetAttribute(Settings.Attribute, kind.Text)
	return true
end

local function claimable(hitbox: BasePart, unlocked: { [string]: boolean }): boolean
	local world = PressTracker.zoneOf(hitbox)
	return PressTracker.isEnabled(hitbox) and (world == nil or unlocked[world] == true)
end

-- Tiles go where people can grab them: a key in a zone that a random
-- online player owns, near that player when they're on the keys.
local function spawnTile()
	if count() >= Settings.MaxActive then return end
	local players = Players:GetPlayers()
	if #players == 0 then return end
	local player = players[rng:NextInteger(1, #players)]
	local data = PlayerData.get(player)
	local unlocked = if data then data.UnlockedWorlds else {}

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local origin = if root and root:IsA("BasePart") then root.Position else nil
	local near, anywhere = {}, {}
	for _, hitbox in PressTracker.getHitboxes() do
		if not active[hitbox] and claimable(hitbox, unlocked) then
			table.insert(anywhere, hitbox)
			if origin and (hitbox.Position - origin).Magnitude <= Settings.NearRadius then
				table.insert(near, hitbox)
			end
		end
	end
	local pool = if #near > 0 and rng:NextNumber() < Settings.NearChance then near else anywhere
	if #pool > 0 then
		activate(pool[rng:NextInteger(1, #pool)])
	end
end

-- Makes sure there's a tile within `radius` of the player (the tutorial's
-- "step on a +1 tile" step). Returns true if one is there now.
function KeyRewards.ensureNear(player: Player, radius: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local data = PlayerData.get(player)
	if not (root and root:IsA("BasePart") and data) then return false end
	local origin = root.Position
	for hitbox in active do
		if (hitbox.Position - origin).Magnitude <= radius then
			return true
		end
	end
	local best, bestDistance = nil, math.huge
	for _, hitbox in PressTracker.getHitboxes() do
		local distance = (hitbox.Position - origin).Magnitude
		-- Not the key under their feet: a few steps away reads as "go there".
		if distance > 6 and distance < bestDistance and distance <= radius and claimable(hitbox, data.UnlockedWorlds) then
			best, bestDistance = hitbox, distance
		end
	end
	return best ~= nil and activate(best)
end

local function onKeysPressed(player: Player, pressed: { BasePart })
	for _, hitbox in pressed do
		if active[hitbox] then
			local kind = kinds[hitbox] or Settings.Kinds[1]
			clear(hitbox)
			local data = PlayerData.get(player)
			if data then
				data.TilesClaimed += 1
				StateSync.push(player, "TilesClaimed", data.TilesClaimed)
			end
			QuestService.progress(player, "Tiles", 1)
			local reward: Reward = kind.Reward
			local given = RewardService.grant(player, reward)
			-- The client bursts the tile (Controllers/KeyLabels) and names it.
			Net.fire(player, "Notify", {
				Kind = "Tile",
				Tile = kind.Id,
				Reward = given,
				Position = hitbox.Position,
				Color = kind.Color,
			})
		end
	end
end

function KeyRewards.init()
	PressTracker.KeysPressed:Connect(onKeysPressed)
end

function KeyRewards.start()
	while true do
		task.wait(Settings.Interval)
		local now = os.clock()
		for hitbox, expires in active do
			if now >= expires or not hitbox:IsDescendantOf(workspace) then
				clear(hitbox)
			end
		end
		if #Players:GetPlayers() > 0 then
			spawnTile()
		end
	end
end

return KeyRewards
