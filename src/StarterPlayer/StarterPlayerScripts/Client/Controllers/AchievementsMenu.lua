--[[

AchievementsMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/AchievementsMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The Achievements window (custom menu "Achievements", side button 🏅):
-- every achievement (Shared/Achievements) with its progress bar and reward,
-- closest to done first and finished ones last. Finished ones with a title
-- get a WEAR button; the worn title shows at the top with REMOVE. Unlocking
-- one pops a banner (GameFeel) and an alert on the side button until the
-- window is opened.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AchievementDefs = require(Shared.Achievements)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Format = require(UI.Format)
local SideButtons = require(UI.SideButtons)

local AchievementsMenu = {}

local MENU = "Achievements"
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local PANEL = Color3.fromRGB(30, 32, 44)
local CARD = Color3.fromRGB(40, 43, 58)
local DONE = Color3.fromRGB(34, 60, 44)
local GOLD = Color3.fromRGB(255, 205, 60)
local GREEN = Color3.fromRGB(120, 255, 140)

local player = Players.LocalPlayer

type Card = {
	frame: Frame,
	fill: Frame,
	progress: TextLabel,
	wear: TextButton,
	wearLabel: TextLabel,
	def: AchievementDefs.AchievementDef,
}

local gui: ScreenGui? = nil
local list: ScrollingFrame
local header: TextLabel
local titleLine: TextLabel
local removeButton: TextButton
local cards: { [string]: Card } = {}
local sideButton: Frame? = nil
local unseen = 0
local pending = false

local function text(parent: Instance, value: string, color: Color3, size: UDim2, position: UDim2, align: Enum.TextXAlignment?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.FontFace = FONT
	label.TextScaled = true
	label.TextColor3 = color
	label.TextXAlignment = align or Enum.TextXAlignment.Left
	label.Text = value
	label.ZIndex = 3
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = Color3.fromRGB(10, 10, 14)
	stroke.Parent = label
	label.Parent = parent
	return label
end

local function round(object: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = object
end

local function pill(parent: Instance, value: string, color: Color3): (TextButton, TextLabel)
	local button = Instance.new("TextButton")
	button.AutoButtonColor = true
	button.Text = ""
	button.BackgroundColor3 = color
	button.ZIndex = 3
	round(button, 0.3)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(10, 10, 14)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	local label = text(button, value, Color3.new(1, 1, 1), UDim2.fromScale(0.86, 0.7), UDim2.fromScale(0.07, 0.15), Enum.TextXAlignment.Center)
	label.ZIndex = 4
	button.Parent = parent
	return button, label
end

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

local function makeCard(def: AchievementDefs.AchievementDef): Card
	local frame = Instance.new("Frame")
	frame.Name = def.Id
	frame.Size = UDim2.new(1, -14, 0, 84)
	frame.BackgroundColor3 = CARD
	round(frame, 0.12)

	text(frame, def.Name, Color3.new(1, 1, 1), UDim2.new(0.5, 0, 0, 24), UDim2.new(0, 14, 0, 8))
	text(frame, def.Text, Color3.fromRGB(190, 195, 215), UDim2.new(0.55, 0, 0, 18), UDim2.new(0, 14, 0, 34))
	local reward = text(frame, `🎁 {Format.reward(def.Reward)}`, GOLD, UDim2.new(0.4, -14, 0, 20), UDim2.new(0.6, 0, 0, 8), Enum.TextXAlignment.Right)
	reward.Name = "Reward"

	local back = Instance.new("Frame")
	back.Size = UDim2.new(0.55, 0, 0, 14)
	back.Position = UDim2.new(0, 14, 0, 60)
	back.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	back.ZIndex = 2
	back.Parent = frame
	round(back, 0.5)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = GREEN
	fill.ZIndex = 2
	fill.Parent = back
	round(fill, 0.5)
	local progress = text(frame, "", Color3.new(1, 1, 1), UDim2.new(0.2, 0, 0, 16), UDim2.new(0.58, 0, 0, 59))

	local wear, wearLabel = pill(frame, "WEAR", Color3.fromRGB(70, 130, 255))
	wear.AnchorPoint = Vector2.new(1, 0)
	wear.Size = UDim2.new(0.3, 0, 0, 34)
	wear.Position = UDim2.new(1, -14, 0, 38)
	wear.Visible = false
	if def.Title then
		wearLabel.Text = `WEAR « {def.Title} »`
		wear.Activated:Connect(function()
			Interface.play("Click")
			setTitle(if State.get("Title") == def.Id then "" else def.Id)
		end)
	end

	frame.Parent = list
	return { frame = frame, fill = fill, progress = progress, wear = wear, wearLabel = wearLabel, def = def }
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "Achievements"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.IgnoreGuiInset = true
	screen.Enabled = false
	gui = screen

	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.Parent = screen

	local root = Instance.new("Frame")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.53)
	root.Size = UDim2.fromScale(0.6, 0.76)
	root.BackgroundColor3 = PANEL
	root.Parent = screen
	round(root, 0.04)
	local outline = Instance.new("UIStroke")
	outline.Thickness = 4
	outline.Color = Color3.fromRGB(10, 10, 14)
	outline.Parent = root
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.2
	aspect.Parent = root
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(860, 720)
	limit.Parent = root

	header = text(root, "🏅 Achievements", Color3.new(1, 1, 1), UDim2.new(0.7, 0, 0, 40), UDim2.new(0, 20, 0, 14))
	titleLine = text(root, "", GOLD, UDim2.new(0.6, 0, 0, 22), UDim2.new(0, 20, 0, 58))
	local remove, _ = pill(root, "REMOVE TITLE", Color3.fromRGB(200, 60, 60))
	removeButton = remove
	remove.AnchorPoint = Vector2.new(1, 0)
	remove.Size = UDim2.new(0.24, 0, 0, 28)
	remove.Position = UDim2.new(1, -70, 0, 55)
	remove.Activated:Connect(function()
		Interface.play("Click")
		setTitle("")
	end)

	list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 14, 0, 92)
	list.Size = UDim2.new(1, -28, 1, -106)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 6
	list.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	for _, def in AchievementDefs.List do
		cards[def.Id] = makeCard(def)
	end

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(46, 46)
	close.BackgroundColor3 = Color3.fromRGB(230, 40, 40)
	close.Text = ""
	close.Parent = root
	round(close, 0.2)
	local closeStroke = Instance.new("UIStroke")
	closeStroke.Thickness = 3
	closeStroke.Color = Color3.new(1, 1, 1)
	closeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	closeStroke.Parent = close
	text(close, "X", Color3.new(1, 1, 1), UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.15, 0.15), Enum.TextXAlignment.Center)
	close.Activated:Connect(function()
		Interface.play("Click")
		Interface.close(MENU)
	end)

	screen.Parent = player:WaitForChild("PlayerGui")
end

local function render()
	if not gui then return end
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
		card.frame.BackgroundColor3 = if row.finished then DONE else CARD
		TweenService:Create(card.fill, TweenInfo.new(0.25), { Size = UDim2.fromScale(row.share, 1) }):Play()
		local shown = if row.def.Stat == "BestRoll" then `1 in {Format.number(math.min(row.value, row.def.Target))}` else Format.number(math.min(row.value, row.def.Target))
		card.progress.Text = if row.finished then "✓ Done" else `{shown} / {Format.number(row.def.Target)}`
		card.wear.Visible = row.finished and row.def.Title ~= nil
		if row.def.Title then
			local wearing = worn == row.def.Id
			card.wearLabel.Text = if wearing then "✓ WEARING" else `WEAR « {row.def.Title} »`
			card.wear.BackgroundColor3 = if wearing then Color3.fromRGB(60, 170, 90) else Color3.fromRGB(70, 130, 255)
		end
	end

	header.Text = `🏅 Achievements  {done}/{total}`
	local wornDef = AchievementDefs.ById[worn]
	titleLine.Text = if wornDef and wornDef.Title then `Title: « {wornDef.Title} »` else "Unlock achievements to earn titles"
	if wornDef and wornDef.TitleColor then
		titleLine.TextColor3 = wornDef.TitleColor
	end
	removeButton.Visible = wornDef ~= nil
end

function AchievementsMenu.open()
	if not gui then build() end
	local screen = gui :: ScreenGui
	if screen.Enabled then return end
	screen.Enabled = true
	unseen = 0
	SideButtons.setAlert(sideButton, false)
	render()
	-- Progress moves while it's open (presses, rolls...).
	task.spawn(function()
		while gui and gui.Enabled do
			task.wait(1)
			render()
		end
	end)
end

function AchievementsMenu.close()
	if gui then
		gui.Enabled = false
	end
end

function AchievementsMenu.isOpen(): boolean
	return gui ~= nil and gui.Enabled
end

function AchievementsMenu.start()
	Interface.setup()
	Interface.registerMenu(MENU, {
		open = AchievementsMenu.open,
		close = AchievementsMenu.close,
		isOpen = AchievementsMenu.isOpen,
	})
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
