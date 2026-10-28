--[[

QuestsMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/QuestsMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Daily Quests window: today's three quests with progress, tap a finished
-- one to claim it. Resets at midnight UTC (countdown in the header).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local QuestDefs = require(Shared.Quests)
local RewardDefs = require(Shared.Rewards)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Kit = require(UI.Kit)
local Format = require(UI.Format)
local Juice = require(UI.Juice)

local QuestsMenu = {}

local MENU = "Quests"
local ICONS = { Press = "⌨️", Roll = "🎲", Earn = "💰", Tiles = "✨", Rare = "🌟", Upgrade = "⬆️" }
local COLORS = { "Green", "Blue", "Purple" }

local items: ScrollingFrame
local cards: { [string]: Frame } = {}
local header: Frame? = nil
local pending = false

local function quests(): { any }
	local state = State.get("Quests")
	return if typeof(state) == "table" and typeof(state.List) == "table" then state.List else {}
end

local function resetText(): string
	local now = State.serverNow()
	local left = (RewardDefs.dayNumber(now) + 1) * RewardDefs.DaySeconds - now
	return `Daily Quests · new in {Format.duration(left)}`
end

local function updateCard(quest: any)
	local card = cards[quest.Id]
	if not card then return end
	local price = card:FindFirstChild("Price", true)
	if quest.Claimed then
		Kit.setPrice(card, "Claimed ✓", nil)
	elseif quest.Progress >= quest.Target then
		Kit.setPrice(card, "CLAIM!", nil)
	else
		Kit.setPrice(card, `{Format.number(quest.Progress)}/{Format.number(quest.Target)}`, nil)
	end
	if price and price:IsA("TextLabel") then
		price.TextColor3 = if quest.Claimed then Color3.fromRGB(170, 170, 170)
			elseif quest.Progress >= quest.Target then Color3.fromRGB(120, 255, 140)
			else Color3.new(1, 1, 1)
	end
end

local function current(id: string): any
	for _, quest in quests() do
		if quest.Id == id then
			return quest
		end
	end
	return nil
end

local function claim(id: string)
	local quest = current(id)
	if pending or not quest then return end
	if quest.Claimed then
		Interface.toast("Already claimed!")
		return
	end
	if quest.Progress < quest.Target then
		Interface.toast(`{Format.number(quest.Target - quest.Progress)} to go!`)
		return
	end
	pending = true
	local response = Net.invoke("ClaimQuest", quest.Id)
	pending = false
	if response.Ok and response.Reward then
		local card = cards[quest.Id]
		Interface.toast(`Quest reward: {Format.reward(response.Reward)}`, Color3.fromRGB(120, 255, 140))
		if card then
			Juice.pop(card, 1.1)
			Juice.confetti(40, card.AbsolutePosition + card.AbsoluteSize / 2)
		end
	else
		Interface.toastError(response)
	end
end

local function rebuild()
	Kit.list(items)
	table.clear(cards)
	Kit.header(items, resetText(), 1)
	local first = items:FindFirstChild("Header")
	header = if first and first:IsA("Frame") then first else nil

	for index, quest in quests() do
		local def = QuestDefs.ById[quest.Id]
		if def then
			local card = Kit.card({
				Title = QuestDefs.text(def, quest.Target, Format.number),
				Description = `Reward: {Format.reward(def.Reward)}`,
				Icon = ICONS[def.Kind] or "⭐",
				Color = COLORS[(index - 1) % #COLORS + 1],
			})
			cards[quest.Id] = card
			local id = quest.Id
			Interface.bindButton(card, function()
				claim(id)
			end, 0.97, 0.93)
			Kit.row(items, card, 2.8, index + 1)
			updateCard(quest)
		end
	end
end

function QuestsMenu.claimable(): number
	local n = 0
	for _, quest in quests() do
		if not quest.Claimed and quest.Progress >= quest.Target then
			n += 1
		end
	end
	return n
end

function QuestsMenu.start()
	Interface.setup()
	local window = Interface.Canva:WaitForChild(MENU)
	items = window:WaitForChild("Main"):WaitForChild("Items") :: ScrollingFrame

	Interface.MenuOpened:Connect(function(name)
		if name == MENU then
			rebuild()
		end
	end)
	State.Changed:Connect(function(field)
		if field ~= "Quests" or not Interface.isOpen(MENU) then return end
		-- A new day means new quests: rebuild; otherwise just refresh progress.
		local list = quests()
		local same = #list > 0
		for _, quest in list do
			if not cards[quest.Id] then
				same = false
			end
		end
		if same then
			for _, quest in list do
				updateCard(quest)
			end
		else
			rebuild()
		end
	end)

	while true do
		task.wait(1)
		local frame = header
		if frame and Interface.isOpen(MENU) then
			Interface.setText(frame, resetText())
			local text = frame:FindFirstChild("Label")
			if text and text:IsA("TextLabel") then
				text.Text = resetText()
			end
		end
	end
end

return QuestsMenu
