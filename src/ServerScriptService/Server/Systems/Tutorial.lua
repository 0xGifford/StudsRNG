--[[

Tutorial
ModuleScript
/ServerScriptService/Server/Systems/Tutorial

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Server side of the first-session flow:
--   MarkIntroSeen   the cinematic has played (PlayerData.SeenIntro)
--   AdvanceTutorial re-checks the current step (Shared/Tutorial) against
--                   saved data and moves on; finishing pays Config.Tutorial.Reward.
-- The server also checks every player in the tutorial once a second, so a
-- step finishes even if the client never asks. On the +1 tile step it keeps
-- a tile close to the player (KeyRewards.ensureNear).
-- Players who were already playing before the tutorial existed skip it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local TutorialDefs = require(Shared.Tutorial)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local RewardService = require(Systems.RewardService)
local KeyRewards = require(Systems.KeyRewards)

type Response = Types.Response

local Tutorial = {}

local VETERAN_ROLLS = 20

local function advance(player: Player): Response
	local data = PlayerData.get(player)
	if not data then return { Ok = false, Error = "NotLoaded" } end
	local index = math.max(data.Tutorial, 1)
	local advanced = false
	-- Several steps may already be done (e.g. rolled before equipping).
	while index < TutorialDefs.Finished do
		local step = TutorialDefs.Steps[index]
		if not step.Done(data) then break end
		index += 1
		advanced = true
	end
	if not advanced then return { Ok = false, Error = "NotReady" } end

	data.Tutorial = index
	StateSync.push(player, "Tutorial", index)
	if index >= TutorialDefs.Finished then
		for _, reward in Config.Tutorial.Reward do
			RewardService.grant(player, reward)
		end
		Net.fire(player, "Notify", { Kind = "TutorialDone", Text = "Tutorial complete! +5 Free Rolls and a Spin", Color = Color3.fromRGB(120, 255, 140) })
	end
	return { Ok = true, Step = index }
end

function Tutorial.init()
	Net.handle("AdvanceTutorial", { Rate = 2, Burst = 4 }, advance)

	Net.handle("MarkIntroSeen", { Rate = 0.5, Burst = 2 }, function(player)
		local data = PlayerData.get(player)
		if not data then return { Ok = false, Error = "NotLoaded" } end
		data.SeenIntro = true
		StateSync.push(player, "SeenIntro", true)
		return { Ok = true }
	end)

	PlayerData.Loaded:Connect(function(player, data)
		if data.Tutorial == 0 then
			data.Tutorial = if data.TotalRolls >= VETERAN_ROLLS then TutorialDefs.Finished else 1
			StateSync.push(player, "Tutorial", data.Tutorial)
		end
	end)
end

function Tutorial.start()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local data = PlayerData.get(player)
			if data and data.Tutorial >= 1 and data.Tutorial < TutorialDefs.Finished then
				local ok, err = pcall(function()
					advance(player)
					local step = TutorialDefs.Steps[data.Tutorial]
					if step and step.Id == "Tile" then
						KeyRewards.ensureNear(player, 45)
					end
				end)
				if not ok then
					warn("[Tutorial]", err)
				end
			end
		end
	end
end

return Tutorial
