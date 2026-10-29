--[[

QuestService
ModuleScript
/ServerScriptService/Server/Systems/QuestService

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Daily quests (Shared/Quests). Systems report progress with
-- QuestService.progress(player, kind, amount); the day's set is drawn on
-- join and whenever the UTC day rolls over. ClaimQuest(id) pays a finished
-- quest once.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local QuestDefs = require(Shared.Quests)
local RewardDefs = require(Shared.Rewards)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local RewardService = require(Systems.RewardService)
local Economy = require(Systems.Economy)
local Rolls = require(Systems.Rolls)
local UpgradeShop = require(Systems.UpgradeShop)
local Combat = require(Systems.Combat)

type Response = Types.Response

local QuestService = {}

local function today(): number
	return RewardDefs.dayNumber(os.time())
end

-- Makes sure the player's quests are today's. Returns the data or nil.
local function refresh(player: Player): any
	local data = PlayerData.get(player)
	if not data then return nil end
	local day = today()
	if data.Quests.Day ~= day then
		local scale = RewardDefs.scale(data)
		local list = {}
		for _, id in QuestDefs.draw(day, player.UserId) do
			local def = QuestDefs.ById[id]
			table.insert(list, { Id = id, Target = QuestDefs.target(def, scale), Progress = 0, Claimed = false })
		end
		data.Quests = { Day = day, List = list }
		StateSync.push(player, "Quests", data.Quests)
	end
	return data
end

function QuestService.progress(player: Player, kind: string, amount: number)
	if amount <= 0 then return end
	local data = refresh(player)
	if not data then return end
	local changed = false
	for _, quest in data.Quests.List do
		local def = QuestDefs.ById[quest.Id]
		if def and def.Kind == kind and not quest.Claimed and quest.Progress < quest.Target then
			local before = quest.Progress
			quest.Progress = math.min(quest.Target, quest.Progress + amount)
			changed = true
			if before < quest.Target and quest.Progress >= quest.Target then
				Net.fire(player, "Notify", { Text = "Quest complete! Claim it in Quests.", Color = Color3.fromRGB(120, 255, 140), Kind = "Quest" })
			end
		end
	end
	if changed then
		StateSync.push(player, "Quests", data.Quests)
	end
end

local function claim(player: Player, id: string): Response
	local data = refresh(player)
	if not data then return { Ok = false, Error = "NotLoaded" } end
	for _, quest in data.Quests.List do
		if quest.Id == id then
			if quest.Claimed then return { Ok = false, Error = "AlreadyClaimed" } end
			if quest.Progress < quest.Target then return { Ok = false, Error = "NotReady" } end
			quest.Claimed = true
			StateSync.push(player, "Quests", data.Quests)
			local def = QuestDefs.ById[id]
			return { Ok = true, Reward = RewardService.grant(player, def.Reward) }
		end
	end
	return { Ok = false, Error = "InvalidReward" }
end

function QuestService.init()
	Net.handle("ClaimQuest", { Rate = 2, Burst = 4 }, function(player, id)
		if typeof(id) ~= "string" or #id > 32 then return { Ok = false, Error = "InvalidReward" } end
		return claim(player, id)
	end)
	PlayerData.Loaded:Connect(function(player)
		refresh(player)
	end)

	Economy.Earned:Connect(function(player, presses, gained)
		QuestService.progress(player, "Press", presses)
		QuestService.progress(player, "Earn", math.floor(gained))
	end)
	Rolls.Rolled:Connect(function(player, results)
		QuestService.progress(player, "Roll", #results)
		local rare = 0
		for _, result in results do
			if result.OneIn >= QuestDefs.RareOneIn then
				rare += 1
			end
		end
		QuestService.progress(player, "Rare", rare)
	end)
	UpgradeShop.Bought:Connect(function(player)
		QuestService.progress(player, "Upgrade", 1)
	end)
	Combat.Defeated:Connect(function(player, boss)
		QuestService.progress(player, "Defeat", 1)
		if boss then
			QuestService.progress(player, "Boss", 1)
		end
	end)
end

-- Day rollover for players who stay online past midnight UTC.
function QuestService.start()
	while true do
		task.wait(30)
		for _, player in Players:GetPlayers() do
			refresh(player)
		end
	end
end

return QuestService
