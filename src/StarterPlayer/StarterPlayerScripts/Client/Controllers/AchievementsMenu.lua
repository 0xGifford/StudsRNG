--[[

AchievementsMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/AchievementsMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The Achievements window (StarterGui.Achievements, a MenuSystem menu,
-- side button 🏅; pieces found by AchievementRole, see
-- tools/ui/screens/Achievements.luau):
-- every achievement (Shared/Achievements) with its progress bar and reward,
-- closest to done first and finished ones last. Finished ones with a title
-- get a WEAR button; the worn title shows at the top with REMOVE. Unlocking
-- one pops a banner (GameFeel) and an alert on the side button until the
-- window is opened.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AchievementDefs = require(Shared.Achievements)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Roles = require(UI.Roles)
local Format = require(UI.Format)
local SideButtons = require(UI.SideButtons)

local ProgressBar = require(ReplicatedStorage:WaitForChild("MenuSystem"):WaitForChild("Menus"):WaitForChild("ProgressBar"))

local AchievementsMenu = {}

local MENU = "Achievements"
local ROLE = "AchievementRole"

type Card = {
	frame: GuiObject,
	fill: GuiObject,
	progress: TextLabel,
	wear: GuiButton,
	wearLabel: TextLabel,
	color: Color3,
	doneColor: Color3,
	wearColor: Color3,
	wearingColor: Color3,
	def: AchievementDefs.AchievementDef,
}

local list: ScrollingFrame? = nil
local header: TextLabel
local titleLine: TextLabel
local titleColor: Color3
local removeButton: GuiObject
local cards: { [string]: Card } = {}
local sideButton: Frame? = nil
local unseen = 0
local pending = false

local function data(): { [string]: any }
	-- The client mirror of the fields Achievements.progress reads.
	return {
		TotalPresses = State.get("TotalPresses"),
		TotalRolls = State.get("TotalRolls"),
		EnemiesDefeated = State.get("EnemiesDefeated"),
		BossesDefeated = State.get("BossesDefeated"),
		TitansDefeated = State.get("TitansDefeated"),
		UnlockedWorlds = State.get("UnlockedWorlds"),
		Index = State.get("Index"),
		Rebirths = State.get("Rebirths"),
		BestRoll = State.get("BestRoll"),
		StudXP = State.get("StudXP"),
		LifetimeClacks = State.get("LifetimeClacks"),
	}
end

local function setTitle(id: string)
	if pending then return end
	pending = true
	local response = State.setTitle(id)
	pending = false
	if not response.Ok then
		Interface.toastError(response)
	end
end

local function child(root: Instance, name: string): any
	local found = root:FindFirstChild(name, true)
	assert(found, `{root:GetFullName()} needs a "{name}"`)
	return found
end

local function makeCard(gui: ScreenGui, def: AchievementDefs.AchievementDef): Card
	local frame = Roles.template(gui, "AchievementCard") :: GuiObject
	frame.Name = def.Id
	child(frame, "Name").Text = def.Name
	child(frame, "Text").Text = def.Text
	child(frame, "Reward").Text = `🎁 {Format.reward(def.Reward)}`
	local fill = child(frame, "Fill") :: GuiObject
	ProgressBar.Set(fill, { Progress = 0 })
	local wear = child(frame, "Wear") :: GuiButton
	local wearLabel = (wear:FindFirstChild("Label", true) or wear) :: any
	wear.Visible = false
	if def.Title then
		wear.Activated:Connect(function()
			Interface.play("Click")
			setTitle(if State.get("Title") == def.Id then "" else def.Id)
		end)
	end
	frame.Parent = list
	return {
		frame = frame,
		fill = fill,
		progress = child(frame, "Progress"),
		wear = wear,
		wearLabel = wearLabel,
		color = frame.BackgroundColor3,
		doneColor = frame:GetAttribute("DoneColor") :: Color3? or frame.BackgroundColor3,
		wearColor = wear.BackgroundColor3,
		wearingColor = wear:GetAttribute("WearingColor") :: Color3? or wear.BackgroundColor3,
		def = def,
	}
end

local function bind(): boolean
	if list then return true end
	local gui = Roles.gui(MENU)
	local found = Roles.find(gui, ROLE, "List")
	if not found then
		warn('[AchievementsMenu] StarterGui.Achievements has no AchievementRole pieces; run tools/ui/migrate.luau on your place')
		return false
	end
	list = found
	header = Roles.get(gui, ROLE, "Header")
	titleLine = Roles.get(gui, ROLE, "Title")
	titleColor = titleLine.TextColor3
	removeButton = Roles.get(gui, ROLE, "RemoveTitle")
	local removeClick = if removeButton:IsA("GuiButton") then removeButton else removeButton:FindFirstChildWhichIsA("GuiButton", true)
	if removeClick then
		(removeClick :: GuiButton).Activated:Connect(function()
			Interface.play("Click")
			setTitle("")
		end)
	end
	for _, def in AchievementDefs.List do
		cards[def.Id] = makeCard(gui, def)
	end
	return true
end

local function render()
	if not list then return end
	local unlocked = State.get("Achievements") or {}
	local worn = State.get("Title") or ""
	local snapshot = data()

	local done, total = 0, #AchievementDefs.List
	local order = {}
	for _, def in AchievementDefs.List do
		local finished = unlocked[def.Id] == true
		if finished then done += 1 end
		local value = AchievementDefs.progress(def, snapshot)
		local share = if finished then 1 else math.clamp(value / def.Target, 0, 1)
		table.insert(order, { def = def, finished = finished, share = share, value = value })
	end
	-- Closest to done first, finished last.
	table.sort(order, function(a, b)
		if a.finished ~= b.finished then return not a.finished end
		return a.share > b.share
	end)

	for position, row in order do
		local card = cards[row.def.Id]
		card.frame.LayoutOrder = position
		card.frame.BackgroundColor3 = if row.finished then card.doneColor else card.color
		ProgressBar.Set(card.fill, { Progress = row.share })
		local shown = if row.def.Stat == "BestRoll" then `1 in {Format.number(math.min(row.value, row.def.Target))}` else Format.number(math.min(row.value, row.def.Target))
		card.progress.Text = if row.finished then "✓ Done" else `{shown} / {Format.number(row.def.Target)}`
		card.wear.Visible = row.finished and row.def.Title ~= nil
		if row.def.Title then
			local wearing = worn == row.def.Id
			card.wearLabel.Text = if wearing then "✓ WEARING" else `WEAR « {row.def.Title} »`
			card.wear.BackgroundColor3 = if wearing then card.wearingColor else card.wearColor
		end
	end

	header.Text = `🏅 Achievements  {done}/{total}`
	local wornDef = AchievementDefs.ById[worn]
	titleLine.Text = if wornDef and wornDef.Title then `Title: « {wornDef.Title} »` else "Unlock achievements to earn titles"
	titleLine.TextColor3 = if wornDef and wornDef.TitleColor then wornDef.TitleColor else titleColor
	removeButton.Visible = wornDef ~= nil
end

local function onOpened()
	unseen = 0
	SideButtons.setAlert(sideButton, false)
	render()
	-- Progress moves while it's open (presses, rolls...).
	task.spawn(function()
		while Interface.isOpen(MENU) do
			task.wait(1)
			render()
		end
	end)
end

function AchievementsMenu.open()
	Interface.open(MENU)
end

function AchievementsMenu.close()
	Interface.close(MENU)
end

function AchievementsMenu.isOpen(): boolean
	return Interface.isOpen(MENU)
end

function AchievementsMenu.start()
	Interface.setup()
	if not bind() then return end
	Interface.MenuOpened:Connect(function(name)
		if name == MENU then
			onOpened()
		end
	end)
	sideButton = SideButtons.add(MENU, "Badges", "🏅")

	local known = 0
	local function countUnlocked(): number
		local n = 0
		for _, on in State.get("Achievements") or {} do
			if on then n += 1 end
		end
		return n
	end
	local function ready()
		known = countUnlocked()
	end
	if State.isReady() then ready() else State.Ready:Connect(ready) end

	State.Changed:Connect(function(field)
		if field == "Achievements" then
			local now = countUnlocked()
			if now > known and not AchievementsMenu.isOpen() then
				unseen += now - known
				SideButtons.setAlert(sideButton, true, tostring(unseen))
			end
			known = now
		end
		if AchievementsMenu.isOpen() and (field == "Achievements" or field == "Title") then
			render()
		end
	end)
end

return AchievementsMenu
