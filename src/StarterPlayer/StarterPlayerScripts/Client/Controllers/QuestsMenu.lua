--[[

QuestsMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/QuestsMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Quests window, three sections (all Kit rows, so it's styled by the
-- StarterGui templates):
--   Daily Quests        today's three; tap a finished one to claim it.
--                       Each pays Focus Points too (+ a bonus for all three).
--   Weekly Grand Focus  this week's three bigger goals, then the Grand
--                       Focus bundle once all three are claimed.
--   Focus Shop          spend Focus Points (Config.Focus.Shop).
-- Countdowns in the headers: daily at midnight UTC, weekly on Monday.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local QuestDefs = require(Shared.Quests)
local RewardDefs = require(Shared.Rewards)
local ZoneRotation = require(Shared.ZoneRotation)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Kit = require(UI.Kit)
local Format = require(UI.Format)
local Juice = require(UI.Juice)

local QuestsMenu = {}

local MENU = "Quests"
local ICONS = {
	Press = "⌨️", Roll = "🎲", Earn = "💰", Tiles = "✨", Rare = "🌟", Upgrade = "⬆️",
	Defeat = "⚔️", Boss = "👑", KeyRush = "⚡", LuckyRoll = "🍀",
}
local COLORS = { "Green", "Blue", "Purple" }
local GREEN = Color3.fromRGB(120, 255, 140)
local GOLD = Color3.fromRGB(255, 205, 90)
local GREY = Color3.fromRGB(170, 170, 170)
local GRAND = "_Grand"

local items: ScrollingFrame
local cards: { [string]: Frame } = {}
local headers: { [string]: Frame } = {}
local pending = false

local function listOf(field: string): { any }
	local state = State.get(field)
	return if typeof(state) == "table" and typeof(state.List) == "table" then state.List else {}
end

local function focus(): number
	local points = State.get("FocusPoints")
	return if typeof(points) == "number" then points else 0
end

local function weeklyState(): any
	local state = State.get("Weekly")
	return if typeof(state) == "table" then state else { List = {}, Grand = false }
end

local function allClaimed(list: { any }): boolean
	for _, quest in list do
		if not quest.Claimed then return false end
	end
	return #list > 0
end

local function dailyText(): string
	local now = State.serverNow()
	local left = (RewardDefs.dayNumber(now) + 1) * RewardDefs.DaySeconds - now
	return `Daily Quests · new in {Format.duration(left)}`
end

local function weeklyText(): string
	return `Weekly Grand Focus · new in {Format.duration(ZoneRotation.untilNextWeek(State.serverNow()))}`
end

local function shopText(): string
	return `Focus Shop · {Format.number(focus())} Focus Points`
end

local function setHeader(key: string, text: string)
	local frame = headers[key]
	local label = frame and frame:FindFirstChildWhichIsA("TextLabel", true)
	if label then
		label.Text = text
	end
end

local function paintPrice(card: Frame, text: string, color: Color3)
	Kit.setPrice(card, text, nil)
	local price = card:FindFirstChild("Price", true)
	if price and price:IsA("TextLabel") then
		price.TextColor3 = color
	end
end

local function updateQuest(quest: any)
	local card = cards[quest.Id]
	if not card then return end
	if quest.Claimed then
		paintPrice(card, "Claimed ✓", GREY)
	elseif quest.Progress >= quest.Target then
		paintPrice(card, "CLAIM!", GREEN)
	else
		paintPrice(card, `{Format.number(quest.Progress)}/{Format.number(quest.Target)}`, Color3.new(1, 1, 1))
	end
end

local function updateGrand()
	local card = cards[GRAND]
	if not card then return end
	local weekly = weeklyState()
	if weekly.Grand then
		paintPrice(card, "Claimed ✓", GREY)
	elseif allClaimed(weekly.List) then
		paintPrice(card, "CLAIM!", GOLD)
	else
		local done = 0
		for _, quest in weekly.List do
			if quest.Claimed then
				done += 1
			end
		end
		paintPrice(card, `{done}/{#weekly.List} claimed`, Color3.new(1, 1, 1))
	end
end

local function updateShop()
	local bought = State.get("FocusBought")
	local counts = if typeof(bought) == "table" then bought else {}
	for _, item in Config.Focus.Shop do
		local card = cards["Shop:" .. item.Id]
		if card then
			local n = counts[item.Id] or 0
			if item.Limit and n >= item.Limit then
				paintPrice(card, "Sold out", GREY)
			else
				paintPrice(card, `{item.Cost} FP`, if focus() >= item.Cost then GOLD else Color3.new(1, 1, 1))
			end
		end
	end
	setHeader("Shop", shopText())
end

local function refreshAll()
	for _, quest in listOf("Quests") do
		updateQuest(quest)
	end
	for _, quest in listOf("Weekly") do
		updateQuest(quest)
	end
	updateGrand()
	updateShop()
end

local function celebrate(id: string, text: string, color: Color3)
	local card = cards[id]
	Interface.toast(text, color)
	if card then
		Juice.pop(card, 1.1)
		Juice.confetti(40, card.AbsolutePosition + card.AbsoluteSize / 2)
	end
end

local function claimQuest(field: string, id: string)
	if pending then return end
	local quest
	for _, q in listOf(field) do
		if q.Id == id then
			quest = q
		end
	end
	if not quest then return end
	if quest.Claimed then
		Interface.toast("Already claimed!")
		return
	end
	if quest.Progress < quest.Target then
		Interface.toast(`{Format.number(quest.Target - quest.Progress)} to go!`)
		return
	end
	pending = true
	local response = Net.invoke(if field == "Weekly" then "ClaimWeekly" else "ClaimQuest", id)
	pending = false
	if response.Ok and response.Reward then
		local extra = if response.Focus then ` · +{response.Focus} Focus` else ""
		celebrate(id, `Quest reward: {Format.reward(response.Reward)}{extra}`, if field == "Weekly" then GOLD else GREEN)
	else
		Interface.toastError(response)
	end
end

local function claimGrand()
	if pending then return end
	local weekly = weeklyState()
	if weekly.Grand then
		Interface.toast("Already claimed this week!")
		return
	end
	if not allClaimed(weekly.List) then
		Interface.toast("Claim all three weekly goals first!")
		return
	end
	pending = true
	local response = Net.invoke("ClaimGrandFocus")
	pending = false
	if response.Ok and response.Reward then
		celebrate(GRAND, `GRAND FOCUS: {Format.reward(response.Reward)}`, GOLD)
		Juice.flash(GOLD, 0.3, 0.5)
	else
		Interface.toastError(response)
	end
end

local function buy(item: any)
	if pending then return end
	local bought = State.get("FocusBought")
	local n = if typeof(bought) == "table" then bought[item.Id] or 0 else 0
	if item.Limit and n >= item.Limit then
		Interface.toast("Sold out!")
		return
	end
	if focus() < item.Cost then
		Interface.toast(`{item.Cost - focus()} more Focus Points needed`)
		return
	end
	pending = true
	local response = Net.invoke("BuyFocus", item.Id)
	pending = false
	if response.Ok then
		celebrate("Shop:" .. item.Id, `Bought {item.Name}!`, GOLD)
	else
		Interface.toastError(response)
	end
end

local function header(key: string, text: string, order: number)
	Kit.header(items, text, order)
	for _, child in items:GetChildren() do
		if child.Name == "Header" and child:IsA("Frame") and child.LayoutOrder == order then
			headers[key] = child
		end
	end
end

local function questCards(field: string, order: number): number
	for index, quest in listOf(field) do
		local def = QuestDefs.ById[quest.Id]
		if def then
			local card = Kit.card({
				Title = QuestDefs.text(def, quest.Target, Format.number),
				Description = `Reward: {Format.reward(def.Reward)} · +{if field == "Weekly" then Config.Focus.WeeklyPoints else Config.Focus.PointsPerQuest} Focus`,
				Icon = ICONS[def.Kind] or "⭐",
				Color = if field == "Weekly" then "Orange" else COLORS[(index - 1) % #COLORS + 1],
			})
			cards[quest.Id] = card
			local id = quest.Id
			Interface.bindButton(card, function()
				claimQuest(field, id)
			end, 0.97, 0.93)
			order += 1
			Kit.row(items, card, 2.8, order)
		end
	end
	return order
end

local function rebuild()
	Kit.list(items)
	table.clear(cards)
	table.clear(headers)
	local order = 0

	-- Daily
	order += 1
	header("Daily", dailyText(), order)
	order += 1
	Kit.paragraph(items, `Every quest also pays Focus Points: +{Config.Focus.PointsPerQuest} each, +{Config.Focus.DailyBonus} more for all three.`, order, GREY)
	order = questCards("Quests", order)

	-- Weekly
	order += 1
	header("Weekly", weeklyText(), order)
	order = questCards("Weekly", order)
	local grand = Kit.card({
		Title = "Grand Focus",
		Description = `Claim all three for: {Format.reward(Config.Focus.Grand)}`,
		Icon = "🏆",
		Color = "Sunset",
	})
	cards[GRAND] = grand
	Interface.bindButton(grand, claimGrand, 0.97, 0.93)
	order += 1
	Kit.row(items, grand, 2.8, order)

	-- Shop: two cards a row
	order += 1
	header("Shop", shopText(), order)
	local row: Frame? = nil
	for index, item in Config.Focus.Shop do
		if (index - 1) % 2 == 0 then
			row = Kit.gridRow(2)
			order += 1
			Kit.row(items, row :: Frame, 3.2, order)
		end
		local card = Kit.card({
			Title = item.Name,
			Description = if item.Limit then `Up to {item.Limit} times` else "Any time",
			Icon = "🎯",
			Color = "Purple",
		})
		cards["Shop:" .. item.Id] = card
		Interface.bindButton(card, function()
			buy(item)
		end, 0.97, 0.93)
		Kit.addCell(row :: Frame, card, index)
	end

	refreshAll()
end

-- Finished, unclaimed quests (daily + weekly + the Grand Focus): the HUD
-- button's badge.
function QuestsMenu.claimable(): number
	local n = 0
	for _, field in { "Quests", "Weekly" } do
		for _, quest in listOf(field) do
			if not quest.Claimed and quest.Progress >= quest.Target then
				n += 1
			end
		end
	end
	local weekly = weeklyState()
	if not weekly.Grand and allClaimed(weekly.List) then
		n += 1
	end
	return n
end

-- Same quests as the cards on screen? (else the day / week changed)
local function sameQuests(): boolean
	for _, field in { "Quests", "Weekly" } do
		local list = listOf(field)
		if #list == 0 then return false end
		for _, quest in list do
			if not cards[quest.Id] then return false end
		end
	end
	return true
end

local WATCHED = { Quests = true, Weekly = true, FocusPoints = true, FocusBought = true }

function QuestsMenu.start()
	Interface.setup()
	local window = Interface.window(MENU)
	items = window:WaitForChild("Main"):WaitForChild("Items") :: ScrollingFrame

	Interface.MenuOpened:Connect(function(name)
		if name == MENU then
			rebuild()
		end
	end)
	State.Changed:Connect(function(field)
		if not WATCHED[field] or not Interface.isOpen(MENU) then return end
		if sameQuests() then
			refreshAll()
		else
			rebuild()
		end
	end)

	while true do
		task.wait(1)
		if Interface.isOpen(MENU) then
			setHeader("Daily", dailyText())
			setHeader("Weekly", weeklyText())
		end
	end
end

return QuestsMenu
