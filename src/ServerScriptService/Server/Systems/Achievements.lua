--[[

Achievements
ModuleScript
/ServerScriptService/Server/Systems/Achievements

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Unlocks achievements (Shared/Achievements) as players reach them: a check
-- every few seconds and after every defeat, the Reward granted once, and the
-- "Achievements" field pushed (the client celebrates the new entry).
--
-- Titles: SetTitle(id | "") wears an unlocked achievement's title. It shows
-- in chat (the "Title" / "TitleColor" player attributes, Controllers/ChatTags)
-- and over the player's head (a TitleTag BillboardGui everyone sees).
-- Also counts Mini Boss and Titan defeats (Combat.Defeated).

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local AchievementDefs = require(Shared.Achievements)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local RewardService = require(Systems.RewardService)
local Combat = require(Systems.Combat)

local Achievements = {}

local CHECK_INTERVAL = 5

local function check(player: Player)
	local data = PlayerData.get(player)
	if not data then return end
	local unlocked = false
	for _, def in AchievementDefs.List do
		if not data.Achievements[def.Id] and AchievementDefs.progress(def, data) >= def.Target then
			data.Achievements[def.Id] = true
			RewardService.grant(player, def.Reward)
			unlocked = true
		end
	end
	if unlocked then
		StateSync.push(player, "Achievements", data.Achievements)
	end
end

-- The worn title: attributes for chat, a tag over the head for everyone.
local function applyTitle(player: Player)
	local data = PlayerData.get(player)
	local def = if data and data.Title ~= "" then AchievementDefs.ById[data.Title] else nil
	local worn = def ~= nil and def.Title ~= nil and data ~= nil and data.Achievements[def.Id] == true
	player:SetAttribute("Title", if worn and def then def.Title else nil)
	player:SetAttribute("TitleColor", if worn and def then def.TitleColor else nil)

	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then return end
	local existing = head:FindFirstChild("TitleTag")
	if existing then
		existing:Destroy()
	end
	if not (worn and def and def.Title) then return end
	-- A copy of StarterGui.WorldUI's TitleTag (TitleRole = "Text").
	local worldUI = StarterGui:FindFirstChild("WorldUI")
	local template = worldUI and worldUI:FindFirstChild("TitleTag", true)
	if not (template and template:IsA("BillboardGui")) then
		warn("[Achievements] StarterGui.WorldUI.TitleTag is missing: no title over heads")
		return
	end
	local tag = template:Clone()
	tag.Name = "TitleTag"
	tag:SetAttribute("UITemplate", nil)
	tag.Enabled = true
	-- MaxDistance is from the camera; with the isometric camera that sits
	-- far away, so add its distance (the template's value means "from you").
	if Config.Camera.Enabled and tag.MaxDistance > 0 then
		tag.MaxDistance += math.ceil(Config.Camera.Distance * Config.Camera.MaxZoom)
	end
	for _, d in tag:GetDescendants() do
		if d:GetAttribute("TitleRole") == "Text" and d:IsA("TextLabel") then
			d.Text = `« {def.Title} »`
			d.TextColor3 = def.TitleColor or Color3.new(1, 1, 1)
		end
	end
	tag.Parent = head
end

local function setTitle(player: Player, id: unknown): any
	local data = PlayerData.get(player)
	if not data then return { Ok = false, Error = "NotLoaded" } end
	if id == "" then
		data.Title = ""
	else
		if typeof(id) ~= "string" then return { Ok = false, Error = "InvalidReward" } end
		local def = AchievementDefs.ById[id]
		if not def or not def.Title then return { Ok = false, Error = "InvalidReward" } end
		if not data.Achievements[def.Id] then return { Ok = false, Error = "TitleLocked" } end
		data.Title = def.Id
	end
	StateSync.push(player, "Title", data.Title)
	applyTitle(player)
	return { Ok = true }
end

function Achievements.init()
	Net.handle("SetTitle", { Rate = 1, Burst = 3 }, setTitle)

	Combat.Defeated:Connect(function(player, boss, zoneBoss)
		local data = PlayerData.get(player)
		if not data then return end
		if zoneBoss then
			data.TitansDefeated += 1
			StateSync.push(player, "TitansDefeated", data.TitansDefeated)
		elseif boss then
			data.BossesDefeated += 1
			StateSync.push(player, "BossesDefeated", data.BossesDefeated)
		end
		check(player)
	end)

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Head", 10)
			applyTitle(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	PlayerData.Loaded:Connect(function(player)
		applyTitle(player)
		check(player)
	end)
end

function Achievements.start()
	while true do
		task.wait(CHECK_INTERVAL)
		for _, player in Players:GetPlayers() do
			check(player)
		end
	end
end

return Achievements
