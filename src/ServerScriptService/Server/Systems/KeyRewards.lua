--[[

KeyRewards
ModuleScript
/ServerScriptService/Server/Systems/KeyRewards

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Reward tiles. Every Config.KeyRewards.Interval a random key gets the
-- attribute RewardTile = "+1" on its Model (clients draw the text). The
-- first player whose press PressTracker counts on that key claims it: the
-- tile clears and they get Config.KeyRewards.Reward. Unclaimed tiles expire
-- after Lifetime. Presses only count in zones the player owns, so locked
-- zones' tiles can't be claimed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local Systems = script.Parent
local PressTracker = require(Systems.PressTracker)
local RewardService = require(Systems.RewardService)

type Reward = Types.Reward

local KeyRewards = {}

local Settings = Config.KeyRewards
local rng = Random.new()

-- hitbox → server time the tile expires
local active: { [BasePart]: number } = {}

local function modelOf(hitbox: BasePart): Instance?
	return hitbox.Parent
end

local function clear(hitbox: BasePart)
	active[hitbox] = nil
	local model = modelOf(hitbox)
	if model then
		model:SetAttribute(Settings.Attribute, nil)
	end
end

local function count(): number
	local n = 0
	for _ in active do
		n += 1
	end
	return n
end

local function spawnTile()
	if count() >= Settings.MaxActive then return end
	local hitboxes = PressTracker.getHitboxes()
	if #hitboxes == 0 then return end
	-- A few tries to land on a key that isn't already a tile.
	for _ = 1, 6 do
		local hitbox = hitboxes[rng:NextInteger(1, #hitboxes)]
		local model = modelOf(hitbox)
		if model and not active[hitbox] and hitbox:IsDescendantOf(workspace) then
			active[hitbox] = os.clock() + Settings.Lifetime
			model:SetAttribute(Settings.Attribute, Settings.Text)
			return
		end
	end
end

local function onKeysPressed(player: Player, pressed: { BasePart })
	for _, hitbox in pressed do
		if active[hitbox] then
			clear(hitbox)
			local reward: Reward = Settings.Reward
			local given = RewardService.grant(player, reward)
			-- Clacks already fly into the counter; anything else gets a toast.
			if reward.Kind ~= "Clacks" then
				local amount = given.Amount or reward.Amount
				local what = if reward.Kind == "FreeRolls" then (if amount == 1 then "Free Roll" else "Free Rolls")
					elseif reward.Kind == "Spins" then (if amount == 1 then "Spin" else "Spins")
					else reward.Kind
				Net.fire(player, "Notify", { Text = `+{amount} {what}!`, Color = Color3.fromRGB(255, 230, 90) })
			end
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
