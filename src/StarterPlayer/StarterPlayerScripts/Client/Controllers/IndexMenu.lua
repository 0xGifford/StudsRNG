--[[

IndexMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/IndexMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The Stud Index, Slime RNG style, built in code as a custom menu ("Index"):
--   * left: one tab per variant (Base, Big, Huge, Jumbo, Shiny, Inverted)
--   * middle: every stud in that variant (name, model, 1 / X odds);
--     undiscovered ones are dark silhouettes named "???"
--   * right: the selected stud (odds, rarity, Strength, Health, how many
--     times you've rolled it) and the tab's reward, claimable once every
--     stud in the tab is found (Systems/IndexRewards)
--   * bottom: "Unlocks Needed" for the tab

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Studs = require(Shared.Studs)
local Variants = require(Shared.Variants)
local Zones = require(Shared.Zones)
local Types = require(Shared.Types)
local RollLogic = require(Shared.Util.RollLogic)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Kit = require(UI.Kit)
local StudCell = require(UI.StudCell)
local Format = require(UI.Format)
local UIConfig = require(UI.UIConfig)

type StudDef = Types.StudDef

local IndexMenu = {}

local MENU = "Index"
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local PANEL = Color3.fromRGB(24, 25, 31)
local CARD = Color3.fromRGB(38, 40, 50)
local ODDS = Color3.fromRGB(150, 210, 255)

local player = Players.LocalPlayer

local sortedStuds: { StudDef } = table.clone(Studs.List)
table.sort(sortedStuds, function(a, b)
	return a.OneIn < b.OneIn
end)

type Cell = { frame: Frame, viewport: ViewportFrame, name: TextLabel, odds: TextLabel, stroke: UIStroke, def: StudDef }

local gui: ScreenGui? = nil
local grid: ScrollingFrame
local cells: { Cell } = {}
local tabs: { [string]: { frame: TextButton, stroke: UIStroke } } = {}
local detail: { viewport: ViewportFrame, name: TextLabel, odds: TextLabel, rarity: TextLabel, strength: TextLabel, health: TextLabel, rolls: TextLabel }
local claimButton: Frame
local progressFill: Frame
local progressText: TextLabel

local activeVariant = "Normal"
local selected: StudDef = sortedStuds[1]

--------------------------------------------------------------------------
-- Builders
--------------------------------------------------------------------------

local function round(parent: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = parent
end

local function outline(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function box(parent: Instance, size: UDim2, position: UDim2, color: Color3, anchor: Vector2?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = anchor or Vector2.zero
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function text(parent: Instance, value: string, color: Color3, size: UDim2, position: UDim2, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Size = size
	l.Position = position
	l.FontFace = FONT
	l.TextScaled = true
	l.TextWrapped = false
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.TextColor3 = color
	l.Text = value
	l.ZIndex = 3
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(12, 12, 16)
	stroke.Parent = l
	l.Parent = parent
	return l
end

local function oddsText(def: StudDef): string
	if def.Drop then return if def.World == "Pass" then "Stud Pass" else "Boss drop" end
	local variant = Variants.ById[activeVariant]
	local oneIn = RollLogic.displayOneIn(def.OneIn * variant.OneIn, State.stats().Luck)
	return (string.gsub(Format.oneIn(oneIn), "^1 in ", "1/"))
end

local function isFound(def: StudDef, variant: string?): boolean
	local index = State.get("Index") or {}
	return index[RollLogic.encodeKey(def.Id, variant or activeVariant)] == true
end

--------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------

local function renderDetail()
	local def = selected
	local variant = Variants.ById[activeVariant]
	local found = isFound(def)
	StudCell.setViewport(detail.viewport, def, variant)
	StudCell.setSilhouette(detail.viewport, not found)
	local color = Config.Rarities.Colors[def.Rarity] or Color3.new(1, 1, 1)
	detail.name.Text = if found then string.upper(Format.studName(def, variant)) else "???"
	detail.name.TextColor3 = if found and def.Rarity ~= "Secret" then color:Lerp(Color3.new(1, 1, 1), 0.25) else Color3.new(1, 1, 1)
	detail.odds.Text = (string.gsub(oddsText(def), "/", " / "))
	detail.rarity.Text = def.Rarity
	detail.rarity.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
	local level = RollLogic.levelOf((State.get("StudXP") or {})[def.Id])
	local strength, health = RollLogic.statsOf(def, variant, level)
	detail.strength.Text = `💪 {Format.number(strength)}`
	detail.health.Text = `❤️ {Format.number(health)}`
	local counts = State.get("RollCounts") or {}
	detail.rolls.Text = `🎲 Rolls: {Format.number(counts[RollLogic.encodeKey(def.Id, activeVariant)] or 0)} · ⭐ Lv {level}`
	for _, cell in cells do
		cell.stroke.Color = if cell.def == def then Color3.new(1, 1, 1) else Color3.fromRGB(12, 12, 16)
		cell.stroke.Thickness = if cell.def == def then 3 else 2
	end
end

local function renderReward()
	local found, total = RollLogic.tabProgress(State.get("Index") or {}, activeVariant)
	local claims = State.get("IndexClaims") or {}
	local claimed = claims[activeVariant] == true
	TweenService:Create(progressFill, Interface.FAST, { Size = UDim2.fromScale(math.clamp(found / math.max(total, 1), 0, 1), 1) }):Play()
	progressText.Text = `{found}/{total}`
	if claimed then
		Kit.paint(claimButton, "Purple")
		Interface.setText(claimButton, "CLAIMED")
	elseif found >= total then
		Kit.paint(claimButton, "Green")
		Interface.setText(claimButton, "CLAIM")
	else
		Kit.paint(claimButton, "Sunset")
		Interface.setText(claimButton, "CLAIM")
	end
end

local function renderGrid()
	local variant = Variants.ById[activeVariant]
	local unlocked = State.get("UnlockedWorlds") or {}
	for _, cell in cells do
		local def = cell.def
		local found = isFound(def)
		StudCell.setViewport(cell.viewport, def, variant)
		StudCell.setSilhouette(cell.viewport, not found)
		cell.name.Text = if found then string.upper(def.Name) else "???"
		if unlocked[def.World] then
			cell.odds.Text = oddsText(def)
			cell.odds.TextColor3 = ODDS
		else
			local zone = Zones.ById[def.World]
			cell.odds.Text = `🔒 {if zone then zone.Name else def.World}`
			cell.odds.TextColor3 = Color3.fromRGB(255, 140, 140)
		end
	end
	for name, tab in tabs do
		tab.stroke.Color = if name == activeVariant then Color3.new(1, 1, 1) else Color3.fromRGB(12, 12, 16)
		tab.stroke.Thickness = if name == activeVariant then 3 else 2
	end
	renderDetail()
	renderReward()
end

--------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------

local function makeCell(def: StudDef, order: number): Cell
	local frame = Instance.new("Frame")
	frame.Name = def.Id
	frame.LayoutOrder = order
	frame.BackgroundColor3 = CARD
	frame.BorderSizePixel = 0
	round(frame, 0.1)
	local stroke = outline(frame, Color3.fromRGB(12, 12, 16), 2)
	local name = text(frame, "", Color3.new(1, 1, 1), UDim2.fromScale(0.92, 0.17), UDim2.fromScale(0.5, 0.13))
	local viewport = StudCell.viewport(def, Variants.ById.Normal)
	viewport.Position = UDim2.fromScale(0.5, 0.52)
	viewport.Size = UDim2.fromScale(0.62, 0.62)
	viewport.Parent = frame
	local odds = text(frame, "", ODDS, UDim2.fromScale(0.6, 0.17), UDim2.fromScale(0.95, 0.88), Enum.TextXAlignment.Right)
	odds.AnchorPoint = Vector2.new(1, 0.5)
	local button = Instance.new("TextButton")
	button.BackgroundTransparency = 1
	button.Text = ""
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = 5
	button.Parent = frame
	button.Activated:Connect(function()
		Interface.play("Click")
		selected = def
		renderDetail()
	end)
	frame.Parent = grid
	return { frame = frame, viewport = viewport, name = name, odds = odds, stroke = stroke, def = def }
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "StudIndex"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.IgnoreGuiInset = true
	screen.Enabled = false
	gui = screen

	local shade = box(screen, UDim2.fromScale(1, 1), UDim2.new(), Color3.new(0, 0, 0))
	shade.BackgroundTransparency = 0.45

	local root = box(screen, UDim2.fromScale(0.8, 0.74), UDim2.fromScale(0.5, 0.53), Color3.new(), Vector2.new(0.5, 0.5))
	root.BackgroundTransparency = 1
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.75
	aspect.Parent = root
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(1240, 710)
	limit.Parent = root

	-- Tabs down the left.
	local tabColumn = box(root, UDim2.fromScale(0.085, 0.92), UDim2.fromScale(0, 0.06), Color3.new())
	tabColumn.BackgroundTransparency = 1
	local tabList = Instance.new("UIListLayout")
	tabList.Padding = UDim.new(0.018, 0)
	tabList.SortOrder = Enum.SortOrder.LayoutOrder
	tabList.Parent = tabColumn
	for order, name in Variants.Order do
		local variant = Variants.ById[name]
		local tab = Instance.new("TextButton")
		tab.Name = name
		tab.LayoutOrder = order
		tab.Text = ""
		tab.AutoButtonColor = false
		tab.BackgroundColor3 = CARD
		tab.Size = UDim2.fromScale(1, 0.15)
		round(tab, 0.12)
		local stroke = outline(tab, Color3.fromRGB(12, 12, 16), 2)
		local icon = StudCell.viewport(sortedStuds[1], variant)
		icon.Position = UDim2.fromScale(0.5, 0.42)
		icon.Size = UDim2.fromScale(0.72, 0.72)
		icon.Parent = tab
		text(tab, Variants.label(variant), Color3.new(1, 1, 1), UDim2.fromScale(0.95, 0.26), UDim2.fromScale(0.5, 0.85))
		tab.Parent = tabColumn
		tabs[name] = { frame = tab, stroke = stroke }
		tab.Activated:Connect(function()
			Interface.play("Click")
			activeVariant = name
			renderGrid()
		end)
	end

	-- Main panel.
	local main = box(root, UDim2.fromScale(0.9, 0.92), UDim2.fromScale(0.1, 0.06), PANEL)
	round(main, 0.04)
	outline(main, Color3.fromRGB(10, 10, 14), 4)
	local title = text(root, "Stud Index", Color3.new(1, 1, 1), UDim2.fromScale(0.36, 0.12), UDim2.fromScale(0.105, 0.06), Enum.TextXAlignment.Left)
	title.AnchorPoint = Vector2.new(0, 0.5)
	title.ZIndex = 6

	-- Grid
	local gridBack = box(main, UDim2.fromScale(0.625, 0.7), UDim2.fromScale(0.02, 0.06), Color3.fromRGB(18, 18, 24))
	round(gridBack, 0.04)
	grid = Instance.new("ScrollingFrame")
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Size = UDim2.fromScale(0.96, 0.94)
	grid.Position = UDim2.fromScale(0.02, 0.03)
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ScrollBarThickness = 6
	grid.Parent = gridBack
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromScale(0.02, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local function sizeCells()
		local width = grid.AbsoluteSize.X * 0.18
		layout.CellSize = UDim2.new(0.18, 0, 0, width * 1.02)
		layout.CellPadding = UDim2.new(0.02, 0, 0, width * 0.1)
	end
	grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(sizeCells)
	sizeCells()
	for order, def in sortedStuds do
		table.insert(cells, makeCell(def, order))
	end

	-- Unlocks needed
	local book = text(main, "📘", Color3.new(1, 1, 1), UDim2.fromScale(0.07, 0.13), UDim2.fromScale(0.05, 0.875))
	book.ZIndex = 5
	text(main, "Unlocks Needed:", Color3.new(1, 1, 1), UDim2.fromScale(0.25, 0.06), UDim2.fromScale(0.085, 0.81), Enum.TextXAlignment.Left).AnchorPoint = Vector2.new(0, 0.5)
	local barBack = box(main, UDim2.fromScale(0.55, 0.075), UDim2.fromScale(0.08, 0.84), Color3.fromRGB(14, 14, 18))
	round(barBack, 1)
	outline(barBack, Color3.fromRGB(8, 8, 10), 3)
	progressFill = box(barBack, UDim2.fromScale(0, 1), UDim2.new(), Color3.fromRGB(40, 150, 255))
	round(progressFill, 1)
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Color = ColorSequence.new(Color3.fromRGB(40, 220, 210), Color3.fromRGB(40, 120, 255))
	fillGradient.Parent = progressFill
	progressText = text(barBack, "", Color3.new(1, 1, 1), UDim2.fromScale(0.5, 0.85), UDim2.fromScale(0.5, 0.5))
	progressText.ZIndex = 4

	-- Detail card
	local card = box(main, UDim2.fromScale(0.31, 0.5), UDim2.fromScale(0.665, 0.06), Color3.fromRGB(18, 18, 24))
	round(card, 0.06)
	local viewport = StudCell.viewport(selected, Variants.ById.Normal)
	viewport.Position = UDim2.fromScale(0.5, 0.25)
	viewport.Size = UDim2.fromScale(0.55, 0.55)
	viewport.Parent = card
	detail = {
		viewport = viewport,
		name = text(card, "", Color3.new(1, 1, 1), UDim2.fromScale(0.9, 0.11), UDim2.fromScale(0.5, 0.53)),
		odds = text(card, "", Color3.new(1, 1, 1), UDim2.fromScale(0.6, 0.1), UDim2.fromScale(0.5, 0.64)),
		rarity = text(card, "", Color3.new(1, 1, 1), UDim2.fromScale(0.6, 0.09), UDim2.fromScale(0.5, 0.74)),
		strength = text(card, "", Color3.new(1, 1, 1), UDim2.fromScale(0.4, 0.09), UDim2.fromScale(0.28, 0.84)),
		health = text(card, "", Color3.new(1, 1, 1), UDim2.fromScale(0.4, 0.09), UDim2.fromScale(0.72, 0.84)),
		rolls = text(card, "", Color3.new(1, 1, 1), UDim2.fromScale(0.7, 0.09), UDim2.fromScale(0.5, 0.94)),
	}

	-- Tab reward
	local rewards = box(main, UDim2.fromScale(0.31, 0.33), UDim2.fromScale(0.665, 0.6), Color3.fromRGB(18, 18, 24))
	round(rewards, 0.08)
	text(rewards, "Rewards:", Color3.new(1, 1, 1), UDim2.fromScale(0.4, 0.15), UDim2.fromScale(0.05, 0.13), Enum.TextXAlignment.Left).AnchorPoint = Vector2.new(0, 0.5)
	local luckPct = math.floor(Config.IndexTabReward.Luck * 100 + 0.5)
	local clackPct = math.floor(Config.IndexTabReward.Clacks * 100 + 0.5)
	for i, reward in { { "🍀", `+{luckPct}%` }, { "", `+{clackPct}%` } } do
		local tile = box(rewards, UDim2.fromScale(0.24, 0.42), UDim2.fromScale(0.25 + (i - 1) * 0.27, 0.25), CARD)
		round(tile, 0.12)
		outline(tile, Color3.fromRGB(12, 12, 16), 2)
		if reward[1] == "" then
			local icon = Instance.new("ImageLabel")
			icon.BackgroundTransparency = 1
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.4)
			icon.Size = UDim2.fromScale(0.6, 0.6)
			icon.ScaleType = Enum.ScaleType.Fit
			icon.Parent = tile
			Kit.setIcon(icon, UIConfig.Icons.Clacks)
		else
			text(tile, reward[1], Color3.new(1, 1, 1), UDim2.fromScale(0.7, 0.55), UDim2.fromScale(0.5, 0.4))
		end
		text(tile, reward[2], Color3.new(1, 1, 1), UDim2.fromScale(0.9, 0.3), UDim2.fromScale(0.5, 0.85))
	end
	claimButton = Kit.button("Green", "CLAIM")
	claimButton.AnchorPoint = Vector2.new(0.5, 0.5)
	claimButton.Position = UDim2.fromScale(0.5, 0.83)
	claimButton.Size = UDim2.fromScale(0.7, 0.26)
	claimButton.Parent = rewards
	Interface.bindButton(claimButton, function()
		local response = State.claimIndexTab(activeVariant)
		if response.Ok then
			Interface.toast(`{Variants.label(Variants.ById[activeVariant])} tab complete! +{luckPct}% luck, +{clackPct}% Clacks`, Color3.fromRGB(120, 255, 140))
		else
			Interface.toastError(response)
		end
	end)

	-- Close
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.fromScale(0.985, 0.06)
	close.Size = UDim2.fromScale(0.065, 0.115)
	close.BackgroundColor3 = Color3.fromRGB(230, 40, 40)
	close.Text = ""
	close.ZIndex = 6
	round(close, 0.15)
	outline(close, Color3.new(1, 1, 1), 3)
	text(close, "X", Color3.new(1, 1, 1), UDim2.fromScale(0.7, 0.75), UDim2.fromScale(0.5, 0.5)).ZIndex = 7
	close.Parent = root
	close.Activated:Connect(function()
		Interface.play("Click")
		Interface.close(MENU)
	end)

	screen.Parent = player:WaitForChild("PlayerGui")
end

--------------------------------------------------------------------------
-- Menu
--------------------------------------------------------------------------

function IndexMenu.open()
	if not gui then build() end
	local screen = gui :: ScreenGui
	if screen.Enabled then return end
	screen.Enabled = true
	renderGrid()
end

function IndexMenu.close()
	if gui then
		gui.Enabled = false
	end
end

function IndexMenu.isOpen(): boolean
	return gui ~= nil and gui.Enabled
end

function IndexMenu.start()
	Interface.setup()
	Interface.registerMenu(MENU, {
		open = IndexMenu.open,
		close = IndexMenu.close,
		isOpen = IndexMenu.isOpen,
	})
	State.Changed:Connect(function(field)
		if not IndexMenu.isOpen() then return end
		if field == "Index" or field == "UnlockedWorlds" or field == "Stats" then
			renderGrid()
		elseif field == "RollCounts" or field == "StudXP" then
			renderDetail()
		elseif field == "IndexClaims" then
			renderReward()
		end
	end)
end

return IndexMenu
