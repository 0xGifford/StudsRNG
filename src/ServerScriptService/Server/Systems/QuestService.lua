--[[

QuestService
ModuleScript
/ServerScriptService/Server/Systems/QuestService

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Daily quests and the Weekly Grand Focus (Shared/Quests), Focus Points and
-- the Focus Shop (Config.Focus).
--
-- Systems report progress with QuestService.progress(player, kind, amount);
-- it counts toward today's quests and this week's at once. The day's set is
-- drawn on join and whenever the UTC day rolls over; the week's on Monday.
--   ClaimQuest(id)    pays a finished daily quest + Focus Points (and the
--                     all-three bonus once all of today's are claimed)
--   ClaimWeekly(id)   pays a finished weekly quest + Focus Points
--   ClaimGrandFocus   the big bundle, once all of this week's are claimed
--   BuyFocus(itemId)  spends Focus Points in the Focus Shop

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local QuestDefs = require(Shared.Quests)
local RewardDefs = require(Shared.Rewards)
local ZoneRotation = require(Shared.ZoneRotation)
local Signal = require(Shared.Util.Signal)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local RewardService = require(Systems.RewardService)
local Economy = require(Systems.Economy)
local Rolls = require(Systems.Rolls)
local UpgradeShop = require(Systems.UpgradeShop)
local Combat = require(Systems.Combat)

type Response = Types.Response
type QuestState = Types.QuestState

local QuestService = {}

-- (player, questId) after each quest claim, daily or weekly (Systems/StudPass)
QuestService.Claimed = Signal.new() :: Signal.Signal<Player, string>

local GREEN = Color3.fromRGB(120, 255, 140)
local GOLD = Color3.fromRGB(255, 205, 90)

local function today(): number
	return RewardDefs.dayNumber(os.time())
end

local function drawList(ids: { string }, scale: number): { QuestState }
	local list = {}
	for _, id in ids do
		local def = QuestDefs.ById[id]
		table.insert(list, { Id = id, Target = QuestDefs.target(def, scale), Progress = 0, Claimed = false })
	end
	return list
end

-- Makes sure the player's quests are today's and this week's. Returns the
-- data or nil.
local function refresh(player: Player): any
	local data = PlayerData.get(player)
	if not data then return nil end
	local day = today()
	if data.Quests.Day ~= day then
		local scale = RewardDefs.scale(data)
		data.Quests = { Day = day, List = drawList(QuestDefs.draw(day, player.UserId), scale) }
		StateSync.push(player, "Quests", data.Quests)
	end
	local week = ZoneRotation.week(os.time())
	if not data.Weekly or data.Weekly.Week ~= week then
		local scale = RewardDefs.scale(data)
		data.Weekly = { Week = week, List = drawList(QuestDefs.draw(week, player.UserId, true), scale), Grand = false }
		StateSync.push(player, "Weekly", data.Weekly)
	end
	return data
end

local function advance(player: Player, list: { QuestState }, kind: string, amount: number, weekly: boolean): boolean
	local changed = false
	for _, quest in list do
		local def = QuestDefs.ById[quest.Id]
		if def and def.Kind == kind and not quest.Claimed and quest.Progress < quest.Target then
			local before = quest.Progress
			quest.Progress = math.min(quest.Target, quest.Progress + amount)
			changed = true
			if before < quest.Target and quest.Progress >= quest.Target then
				Net.fire(player, "Notify", {
					Text = if weekly then "Weekly Focus complete! Claim it in Quests." else "Quest complete! Claim it in Quests.",
					Color = if weekly then GOLD else GREEN,
					Kind = "Quest",
				})
			end
		end
	end
	return changed
end

function QuestService.progress(player: Player, kind: string, amount: number)
	if amount <= 0 then return end
	local data = refresh(player)
	if not data then return end
	if advance(player, data.Quests.List, kind, amount, false) then
		StateSync.push(player, "Quests", data.Quests)
	end
	if advance(player, data.Weekly.List, kind, amount, true) then
		StateSync.push(player, "Weekly", data.Weekly)
	end
end

local function addFocus(player: Player, data: any, amount: number)
	data.FocusPoints = (data.FocusPoints or 0) + amount
	StateSync.push(player, "FocusPoints", data.FocusPoints)
end

local function allClaimed(list: { QuestState }): boolean
	for _, quest in list do
		if not quest.Claimed then return false end
	end
	return #list > 0
end

local function claimFrom(player: Player, data: any, list: { QuestState }, id: string, field: string): (Response?, QuestState?)
	for _, quest in list do
		if quest.Id == id then
			if quest.Claimed then return { Ok = false, Error = "AlreadyClaimed" }, nil end
			if quest.Progress < quest.Target then return { Ok = false, Error = "NotReady" }, nil end
			quest.Claimed = true
			StateSync.push(player, field, data[field])
			QuestService.Claimed:Fire(player, id)
			return nil, quest
		end
	end
	return { Ok = false, Error = "InvalidReward" }, nil
end

local function claim(player: Player, id: string): Response
	local data = refresh(player)
	if not data then return { Ok = false, Error = "NotLoaded" } end
	local failed = claimFrom(player, data, data.Quests.List, id, "Quests")
	if failed then return failed end

	local focus = Config.Focus.PointsPerQuest
	if not data.Quests.Bonus and allClaimed(data.Quests.List) then
		data.Quests.Bonus = true
		focus += Config.Focus.DailyBonus
		StateSync.push(player, "Quests", data.Quests)
	end
	addFocus(player, data, focus)
	return { Ok = true, Reward = RewardService.grant(player, QuestDefs.ById[id].Reward), Focus = focus }
end

local function claimWeekly(player: Player, id: string): Response
	local data = refresh(player)
	if not data then return { Ok = false, Error = "NotLoaded" } end
	local failed = claimFrom(player, data, data.Weekly.List, id, "Weekly")
	if failed then return failed end
	addFocus(player, data, Config.Focus.WeeklyPoints)
	return { Ok = true, Reward = RewardService.grant(player, QuestDefs.ById[id].Reward), Focus = Config.Focus.WeeklyPoints }
end

local function claimGrand(player: Player): Response
	local data = refresh(player)
	if not data then return { Ok = false, Error = "NotLoaded" } end
	if data.Weekly.Grand then return { Ok = false, Error = "AlreadyClaimed" } end
	if not allClaimed(data.Weekly.List) then return { Ok = false, Error = "NotReady" } end
	data.Weekly.Grand = true
	StateSync.push(player, "Weekly", data.Weekly)
	return { Ok = true, Reward = RewardService.grant(player, Config.Focus.Grand) }
end

local shopById: { [string]: any } = {}
for _, item in Config.Focus.Shop do
	shopById[item.Id] = item
end

local function buyFocus(player: Player, id: string): Response
	local data = PlayerData.get(player)
	if not data then return { Ok = false, Error = "NotLoaded" } end
	local item = shopById[id]
	if not item then return { Ok = false, Error = "InvalidReward" } end
	local bought = data.FocusBought[id] or 0
	if item.Limit and bought >= item.Limit then return { Ok = false, Error = "SoldOut" } end
	if (data.FocusPoints or 0) < item.Cost then return { Ok = false, Error = "NotEnoughFocus" } end

	data.FocusPoints -= item.Cost
	data.FocusBought[id] = bought + 1
	StateSync.push(player, "FocusPoints", data.FocusPoints)
	StateSync.push(player, "FocusBought", data.FocusBought)
	return { Ok = true, Reward = RewardService.grant(player, item.Reward) }
end

local function isId(id: any): boolean
	return typeof(id) == "string" and #id <= 32
end

function QuestService.init()
	Net.handle("ClaimQuest", { Rate = 2, Burst = 4 }, function(player, id)
		if not isId(id) then return { Ok = false, Error = "InvalidReward" } end
		return claim(player, id)
	end)
	Net.handle("ClaimWeekly", { Rate = 2, Burst = 4 }, function(player, id)
		if not isId(id) then return { Ok = false, Error = "InvalidReward" } end
		return claimWeekly(player, id)
	end)
	Net.handle("ClaimGrandFocus", { Rate = 0.5, Burst = 2 }, claimGrand)
	Net.handle("BuyFocus", { Rate = 2, Burst = 4 }, function(player, id)
		if not isId(id) then return { Ok = false, Error = "InvalidReward" } end
		return buyFocus(player, id)
	end)
	PlayerData.Loaded:Connect(function(player)
		refresh(player)
	end)

	Economy.Earned:Connect(function(player, presses, gained)
		QuestService.progress(player, "Press", presses)
		QuestService.progress(player, "Earn", math.floor(gained))
	end)
	Economy.Rushed:Connect(function(player)
		QuestService.progress(player, "KeyRush", 1)
	end)
	Rolls.Rolled:Connect(function(player, results)
		QuestService.progress(player, "Roll", #results)
		local rare, lucky = 0, 0
		for _, result in results do
			if result.OneIn >= QuestDefs.RareOneIn then
				rare += 1
			end
			if result.Lucky then
				lucky += 1
			end
		end
		QuestService.progress(player, "Rare", rare)
		QuestService.progress(player, "LuckyRoll", lucky)
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

-- Day / week rollover for players who stay online past midnight UTC.
function QuestService.start()
	while true do
		task.wait(30)
		for _, player in Players:GetPlayers() do
			refresh(player)
		end
	end
end

return QuestService
