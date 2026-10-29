--[[

StudsMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/StudsMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The Backpack (custom menu "Studs", built in code, Slime RNG style):
--   * a big "Backpack" title, SORT / EQUIP BEST / X up top
--   * "4/7 Equipped · 956K DMG" and your equipped studs in a row
--   * every stud you own below: odds, how many, its level, a size / Shiny /
--     Inverted badge
--   * tap one for its card: name, rarity, Clacks, Strength, Health, level
--     and XP, and EQUIP / UNEQUIP, FUSE x/5, DELETE
--   * storage used, and AUTO DELETE (Off → Common → ... → Epic, applied by
--     the server to Base-size rolls)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Variants = require(Shared.Variants)
local Studs = require(Shared.Studs)
local Types = require(Shared.Types)
local RollLogic = require(Shared.Util.RollLogic)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local StudCell = require(UI.StudCell)
local Format = require(UI.Format)
local Juice = require(UI.Juice)
local CombatFx = require(UI.CombatFx)

type StudDef = Types.StudDef
type VariantDef = Types.VariantDef

local StudsMenu = {}

local MENU = "Studs"
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local PANEL = Color3.fromRGB(30, 31, 40)
local CARD = Color3.fromRGB(44, 46, 58)
local EDGE = Color3.fromRGB(12, 12, 16)
local GREEN = Color3.fromRGB(70, 200, 90)
local BLUE = Color3.fromRGB(60, 140, 255)
local RED = Color3.fromRGB(230, 50, 50)
local ODDS = Color3.fromRGB(150, 210, 255)
local SORTS = { "RARITY", "STRENGTH", "COUNT" }
local BADGES: { [string]: { string } } = {
	Big = { "BIG", "#FFA040" },
	Huge = { "HUGE", "#FF7A2E" },
	Jumbo = { "JUMBO", "#FF4E2E" },
	Shiny = { "✨", "#FFE070" },
	Inverted = { "INV", "#C8A0FF" },
}

local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local header: TextLabel
local equippedRow: Frame
local grid: ScrollingFrame
local card: Frame
local storageText: TextLabel
local autoButton: TextButton
local sortButton: TextButton
local bestButton: TextButton? = nil
local cardParts: { [string]: any } = {}

local selected: string? = nil
local sortIndex = 1
local pending = false
local cells: { [string]: Frame } = {}

-- Rarities the player can auto-delete, lowest first.
local deletable: { string } = {}
for _, rarity in Config.Rarities.Order do
	if Config.Rarities.AutoDeletable[rarity] then
		table.insert(deletable, rarity)
	end
end

--------------------------------------------------------------------------
-- Small builders
--------------------------------------------------------------------------

local function text(parent: Instance, value: string, color: Color3, size: UDim2, position: UDim2, align: Enum.TextXAlignment?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.FontFace = FONT
	label.TextScaled = true
	label.TextColor3 = color
	label.TextXAlignment = align or Enum.TextXAlignment.Center
	label.RichText = true
	label.Text = value
	label.ZIndex = 4
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = EDGE
	stroke.Parent = label
	label.Parent = parent
	return label
end

local function round(object: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = object
end

local function outline(object: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = object
	return stroke
end

local function button(parent: Instance, value: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Text = ""
	b.AutoButtonColor = true
	b.BackgroundColor3 = color
	b.ZIndex = 3
	round(b, 0.18)
	outline(b, EDGE, 3)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
	gradient.Rotation = 90
	gradient.Parent = b
	local label = text(b, value, Color3.new(1, 1, 1), UDim2.fromScale(0.9, 0.72), UDim2.fromScale(0.05, 0.14))
	label.Name = "Label"
	label.ZIndex = 5
	b.Parent = parent
	return b
end

local function setButtonText(b: TextButton, value: string)
	local label = b:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = value
	end
end

--------------------------------------------------------------------------
-- Data helpers
--------------------------------------------------------------------------

local function equippedList(): { string }
	return State.get("Equipped") or {}
end

local function equippedCount(key: string): number
	return RollLogic.countInList(equippedList(), key)
end

local function owned(key: string): number
	return (State.get("Studs") or {})[key] or 0
end

local function levelOf(def: StudDef): number
	return RollLogic.levelOf((State.get("StudXP") or {})[def.Id])
end

local function autoDeleteThreshold(): string?
	local settings = State.get("AutoDelete") or {}
	local threshold: string? = nil
	for _, rarity in deletable do
		if settings[rarity] then
			threshold = rarity
		end
	end
	return threshold
end

local function oddsText(def: StudDef, variant: VariantDef): string
	return "1/" .. Format.number(def.OneIn * variant.OneIn)
end

local function rarityColor(def: StudDef): Color3
	return if def.Rarity == "Secret" then Color3.new(1, 1, 1) else Config.Rarities.Colors[def.Rarity] or Color3.new(1, 1, 1)
end

-- Owned keys in the current sort order.
local function sortedKeys(): { string }
	local studs = State.get("Studs") or {}
	local keys = RollLogic.sortedOwned(studs) -- rarest first
	local mode = SORTS[sortIndex]
	if mode == "STRENGTH" then
		local strength: { [string]: number } = {}
		for _, key in keys do
			local def, variant = RollLogic.decodeKey(key)
			strength[key] = if def and variant then (RollLogic.statsOf(def, variant, levelOf(def))) else 0
		end
		table.sort(keys, function(a, b)
			return strength[a] > strength[b]
		end)
	elseif mode == "COUNT" then
		table.sort(keys, function(a, b)
			return (studs[a] or 0) > (studs[b] or 0)
		end)
	end
	return keys
end

--------------------------------------------------------------------------
-- Cells
--------------------------------------------------------------------------

local function makeCell(parent: Instance, key: string, count: number?, order: number): Frame?
	local def, variant = RollLogic.decodeKey(key)
	if not (def and variant) then return nil end
	local frame = Instance.new("Frame")
	frame.Name = key
	frame.LayoutOrder = order
	frame.BackgroundColor3 = CARD
	round(frame, 0.1)
	local stroke = outline(frame, EDGE, 2)
	stroke.Name = "Edge"

	local viewport = StudCell.viewport(def, variant)
	viewport.Position = UDim2.fromScale(0.5, 0.46)
	viewport.Size = UDim2.fromScale(0.82, 0.82)
	viewport.ZIndex = 2
	viewport.Parent = frame

	text(frame, oddsText(def, variant), rarityColor(def):Lerp(Color3.new(1, 1, 1), 0.25), UDim2.fromScale(0.95, 0.22), UDim2.fromScale(0.025, 0.76))
	if count and count > 1 then
		text(frame, `x{count}`, Color3.new(1, 1, 1), UDim2.fromScale(0.36, 0.18), UDim2.fromScale(0.62, 0.03), Enum.TextXAlignment.Right)
	end
	local level = levelOf(def)
	if level > 1 then
		text(frame, `Lv. {level}`, Color3.fromRGB(120, 200, 255), UDim2.fromScale(0.5, 0.18), UDim2.fromScale(0.25, 0.03))
	end
	local badge = BADGES[variant.Name]
	if badge then
		text(frame, `<font color="{badge[2]}">{badge[1]}</font>`, Color3.new(1, 1, 1), UDim2.fromScale(0.42, 0.17), UDim2.fromScale(0.03, 0.03), Enum.TextXAlignment.Left)
	end

	local hit = Instance.new("TextButton")
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 6
	hit.Parent = frame
	hit.Activated:Connect(function()
		Interface.play("Click")
		StudsMenu.select(if selected == key then nil else key)
	end)
	frame.Parent = parent
	return frame
end

local function clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

--------------------------------------------------------------------------
-- Selected stud card
--------------------------------------------------------------------------

local function renderCard()
	local key = selected
	local def, variant = RollLogic.decodeKey(key)
	if not (key and def and variant) then
		card.Visible = false
		return
	end
	card.Visible = true
	local level = levelOf(def)
	local xp = (State.get("StudXP") or {})[def.Id] or 0
	local strength, health = RollLogic.statsOf(def, variant, level)
	StudCell.setViewport(cardParts.viewport, def, variant)
	cardParts.name.Text = string.upper(Format.studName(def, variant))
	cardParts.name.TextColor3 = rarityColor(def):Lerp(Color3.new(1, 1, 1), 0.2)
	cardParts.odds.Text = `{oddsText(def, variant)} · {def.Rarity}`
	cardParts.stats.Text = `💪 {Format.number(strength)}   ❤️ {Format.number(health)}   💰 {Format.multiplier(RollLogic.multiplierOf(def, variant))}`
	cardParts.level.Text = if level >= Config.Levels.Max
		then `⭐ Lv. {level} (MAX)`
		else `⭐ Lv. {level} · {Format.number(xp - RollLogic.xpForLevel(level))}/{Format.number(RollLogic.xpForLevel(level + 1) - RollLogic.xpForLevel(level))} XP`
	cardParts.owned.Text = `{owned(key)} owned · {equippedCount(key)} equipped`

	local canEquipMore = equippedCount(key) < owned(key) and #equippedList() < State.stats().Slots
	local equipping = canEquipMore or equippedCount(key) == 0
	setButtonText(cardParts.equip, if equipping then "EQUIP" else "UNEQUIP")
	cardParts.equip.BackgroundColor3 = if equipping then GREEN else Color3.fromRGB(220, 140, 40)
	local fuseCost = State.stats().FuseCost
	if Variants.Next[variant.Name] then
		setButtonText(cardParts.fuse, `FUSE {math.min(owned(key), fuseCost)}/{fuseCost}`)
		cardParts.fuse.Visible = true
	else
		cardParts.fuse.Visible = false
	end
end

--------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------

local function render()
	if not gui then return end
	local stats = State.stats()
	local equipped = equippedList()
	local strength = RollLogic.teamStats(equipped, State.get("StudXP")) * (stats.TeamStrength or 1)
	header.Text = `{#equipped}/{stats.Slots} Equipped  •  {Format.number(strength)} DMG  •  {Format.multiplier(stats.ClackMultiplier)} Clacks`

	clear(equippedRow)
	for i, key in equipped do
		makeCell(equippedRow, key, nil, i)
	end

	clear(grid)
	table.clear(cells)
	local studs = State.get("Studs") or {}
	for order, key in sortedKeys() do
		local cell = makeCell(grid, key, studs[key], order)
		if cell then
			cells[key] = cell
			if equippedCount(key) > 0 then
				local check = text(cell, "✓", GREEN, UDim2.fromScale(0.3, 0.22), UDim2.fromScale(0.68, 0.55), Enum.TextXAlignment.Right)
				check.ZIndex = 5
			end
		end
	end
	if selected and not cells[selected] then
		selected = nil
	end
	if selected and cells[selected] then
		local edge = cells[selected]:FindFirstChild("Edge")
		if edge and edge:IsA("UIStroke") then
			edge.Color = Color3.new(1, 1, 1)
			edge.Thickness = 3
		end
	end
	renderCard()

	storageText.Text = `🎒 {stats.StudCount}/{stats.MaxStuds}`
	storageText.TextColor3 = if stats.StudCount >= stats.MaxStuds then RED else Color3.new(1, 1, 1)
	local threshold = autoDeleteThreshold()
	setButtonText(autoButton, if threshold then `AUTO DELETE: {string.upper(threshold)}` else "AUTO DELETE: OFF")
	setButtonText(sortButton, `SORT: {SORTS[sortIndex]}`)
end

function StudsMenu.select(key: string?)
	selected = key
	render()
end

--------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------

local function run(action: () -> any)
	if pending then return end
	pending = true
	local ok, response = pcall(action)
	pending = false
	if not ok then
		warn("[StudsMenu]", response)
		return
	end
	if typeof(response) == "table" then
		Interface.toastError(response)
	end
end

local function onEquip()
	local key = selected
	if not key then return end
	local canEquipMore = equippedCount(key) < owned(key) and #equippedList() < State.stats().Slots
	if canEquipMore or equippedCount(key) == 0 then
		run(function()
			return State.equip(key)
		end)
	else
		run(function()
			return State.unequip(key)
		end)
	end
end

local function onFuse()
	local key = selected
	if not key then return end
	run(function()
		local from = cells[key]
		local response = State.fuse(key)
		if response.Ok and response.Key then
			local def, variant = RollLogic.decodeKey(response.Key)
			if def and variant then
				local color = rarityColor(def)
				if from and from.Parent then
					Juice.pop(from, 1.35)
					Juice.confetti(45, from.AbsolutePosition + from.AbsoluteSize / 2)
				end
				Juice.flash(color, 0.25, 0.35)
				Juice.banner("FUSED!", Format.studName(def, variant), color, 1.1)
				CombatFx.sound("Coin", nil, 0.8, 0.6)
				task.delay(0.3, function()
					StudsMenu.select(response.Key)
					if cells[response.Key] then
						Juice.pop(cells[response.Key], 1.3)
					end
				end)
			end
		end
		return response
	end)
end

local function onDelete()
	local key = selected
	if not key then return end
	run(function()
		return State.delete(key, 1)
	end)
end

local function onAutoDelete()
	local current = autoDeleteThreshold()
	local nextIndex = if current then (table.find(deletable, current) or 0) + 1 else 1
	local threshold = deletable[nextIndex] -- nil wraps back to Off
	local thresholdRank = if threshold then RollLogic.rarityRank(threshold) else 0
	local settings = State.get("AutoDelete") or {}
	run(function()
		for _, rarity in deletable do
			local want = RollLogic.rarityRank(rarity) <= thresholdRank
			if (settings[rarity] == true) ~= want then
				local response = State.setAutoDelete(rarity, want)
				if not response.Ok then
					return response
				end
			end
		end
		return { Ok = true }
	end)
end

--------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "Backpack"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.IgnoreGuiInset = true
	screen.Enabled = false
	gui = screen

	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.5
	shade.Parent = screen

	local root = Instance.new("Frame")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.52)
	root.Size = UDim2.fromScale(0.62, 0.68)
	root.BackgroundTransparency = 1
	root.Parent = screen
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.55
	aspect.Parent = root
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(1100, 710)
	limit.Parent = root

	-- Title and top buttons.
	text(root, "Backpack", Color3.new(1, 1, 1), UDim2.fromScale(0.42, 0.12), UDim2.fromScale(0, -0.02), Enum.TextXAlignment.Left)
	sortButton = button(root, "SORT: RARITY", GREEN)
	sortButton.Position = UDim2.fromScale(0.5, 0.0)
	sortButton.Size = UDim2.fromScale(0.2, 0.075)
	sortButton.Activated:Connect(function()
		Interface.play("Click")
		sortIndex = sortIndex % #SORTS + 1
		render()
	end)
	local best = button(root, "EQUIP BEST", BLUE)
	best.Position = UDim2.fromScale(0.715, 0.0)
	best.Size = UDim2.fromScale(0.19, 0.075)
	bestButton = best
	best.Activated:Connect(function()
		Interface.play("Click")
		run(State.equipBest)
	end)
	local close = button(root, "X", RED)
	close.Position = UDim2.fromScale(0.92, -0.01)
	close.Size = UDim2.fromScale(0.075, 0.1)
	close.Activated:Connect(function()
		Interface.play("Click")
		Interface.close(MENU)
	end)

	-- Main panel.
	local panel = Instance.new("Frame")
	panel.Position = UDim2.fromScale(0, 0.1)
	panel.Size = UDim2.fromScale(1, 0.9)
	panel.BackgroundColor3 = PANEL
	panel.Parent = root
	round(panel, 0.035)
	outline(panel, EDGE, 4)

	header = text(panel, "", Color3.new(1, 1, 1), UDim2.fromScale(0.7, 0.06), UDim2.fromScale(0.15, 0.02))

	equippedRow = Instance.new("Frame")
	equippedRow.BackgroundTransparency = 1
	equippedRow.Position = UDim2.fromScale(0.02, 0.09)
	equippedRow.Size = UDim2.fromScale(0.96, 0.17)
	equippedRow.Parent = panel
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.Padding = UDim.new(0.012, 0)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = equippedRow
	-- Row cells are square, sized off the row's height.
	equippedRow.ChildAdded:Connect(function(child)
		if child:IsA("Frame") then
			child.Size = UDim2.fromScale(0.105, 1)
			local square = Instance.new("UIAspectRatioConstraint")
			square.AspectRatio = 1
			square.Parent = child
		end
	end)

	local divider = Instance.new("Frame")
	divider.Position = UDim2.fromScale(0.08, 0.285)
	divider.Size = UDim2.fromScale(0.84, 0.006)
	divider.BackgroundColor3 = Color3.fromRGB(70, 72, 86)
	divider.BorderSizePixel = 0
	divider.Parent = panel

	grid = Instance.new("ScrollingFrame")
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromScale(0.02, 0.31)
	grid.Size = UDim2.fromScale(0.96, 0.59)
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ScrollBarThickness = 6
	grid.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = grid
	local function sizeCells()
		local width = grid.AbsoluteSize.X * 0.148
		layout.CellSize = UDim2.fromOffset(width, width)
		layout.CellPadding = UDim2.fromOffset(width * 0.08, width * 0.08)
	end
	grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(sizeCells)
	sizeCells()

	-- Footer: storage and auto delete.
	storageText = text(panel, "", Color3.new(1, 1, 1), UDim2.fromScale(0.25, 0.06), UDim2.fromScale(0.03, 0.915), Enum.TextXAlignment.Left)
	autoButton = button(panel, "AUTO DELETE: OFF", Color3.fromRGB(90, 90, 110))
	autoButton.Position = UDim2.fromScale(0.66, 0.905)
	autoButton.Size = UDim2.fromScale(0.31, 0.075)
	autoButton.Activated:Connect(function()
		Interface.play("Click")
		onAutoDelete()
	end)

	-- Selected stud card (slides over the right of the grid).
	card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(1, 0)
	card.Position = UDim2.fromScale(1.015, 0.29)
	card.Size = UDim2.fromScale(0.3, 0.62)
	card.BackgroundColor3 = Color3.fromRGB(24, 25, 32)
	card.Visible = false
	card.ZIndex = 8
	card.Parent = panel
	round(card, 0.06)
	outline(card, EDGE, 4)
	local viewport = StudCell.viewport(Studs.List[1], Variants.ById.Normal)
	viewport.Position = UDim2.fromScale(0.5, 0.18)
	viewport.Size = UDim2.fromScale(0.5, 0.5)
	viewport.ZIndex = 9
	viewport.Parent = card
	cardParts.viewport = viewport
	cardParts.name = text(card, "", Color3.new(1, 1, 1), UDim2.fromScale(0.92, 0.08), UDim2.fromScale(0.04, 0.37))
	cardParts.odds = text(card, "", ODDS, UDim2.fromScale(0.9, 0.06), UDim2.fromScale(0.05, 0.45))
	cardParts.stats = text(card, "", Color3.new(1, 1, 1), UDim2.fromScale(0.92, 0.06), UDim2.fromScale(0.04, 0.52))
	cardParts.level = text(card, "", Color3.fromRGB(120, 200, 255), UDim2.fromScale(0.9, 0.055), UDim2.fromScale(0.05, 0.585))
	cardParts.owned = text(card, "", Color3.fromRGB(190, 195, 215), UDim2.fromScale(0.9, 0.05), UDim2.fromScale(0.05, 0.645))
	for _, label in { cardParts.name, cardParts.odds, cardParts.stats, cardParts.level, cardParts.owned } do
		label.ZIndex = 9
	end
	cardParts.equip = button(card, "EQUIP", GREEN)
	cardParts.equip.Position = UDim2.fromScale(0.06, 0.71)
	cardParts.equip.Size = UDim2.fromScale(0.88, 0.085)
	cardParts.fuse = button(card, "FUSE", Color3.fromRGB(160, 90, 230))
	cardParts.fuse.Position = UDim2.fromScale(0.06, 0.805)
	cardParts.fuse.Size = UDim2.fromScale(0.56, 0.085)
	local delete = button(card, "DELETE", RED)
	delete.Position = UDim2.fromScale(0.64, 0.805)
	delete.Size = UDim2.fromScale(0.3, 0.085)
	local deselect = button(card, "CLOSE", Color3.fromRGB(70, 72, 86))
	deselect.Position = UDim2.fromScale(0.06, 0.9)
	deselect.Size = UDim2.fromScale(0.88, 0.075)
	for _, b in { cardParts.equip, cardParts.fuse, delete, deselect } do
		b.ZIndex = 9
		for _, child in b:GetDescendants() do
			if child:IsA("GuiObject") then
				child.ZIndex = 10
			end
		end
	end
	cardParts.equip.Activated:Connect(function()
		Interface.play("Click")
		onEquip()
	end)
	cardParts.fuse.Activated:Connect(function()
		Interface.play("Click")
		onFuse()
	end)
	delete.Activated:Connect(function()
		Interface.play("Click")
		onDelete()
	end)
	deselect.Activated:Connect(function()
		Interface.play("Click")
		StudsMenu.select(nil)
	end)

	screen.Parent = player:WaitForChild("PlayerGui")
end

--------------------------------------------------------------------------
-- Menu
--------------------------------------------------------------------------

function StudsMenu.open()
	if not gui then build() end
	local screen = gui :: ScreenGui
	if screen.Enabled then return end
	screen.Enabled = true
	render()
end

function StudsMenu.close()
	if gui then
		gui.Enabled = false
	end
	selected = nil
end

-- For the tutorial's pointer.
function StudsMenu.equipBestButton(): GuiObject?
	return bestButton
end

function StudsMenu.isOpen(): boolean
	return gui ~= nil and gui.Enabled
end

function StudsMenu.start()
	Interface.setup()
	-- Replaces the kit's Studs window: every "Studs" button opens this.
	Interface.registerMenu(MENU, {
		open = StudsMenu.open,
		close = StudsMenu.close,
		isOpen = StudsMenu.isOpen,
	})

	-- Studs, Equipped and Stats usually change together: one render a patch.
	local queued = false
	State.Changed:Connect(function(field)
		if not StudsMenu.isOpen() or queued then return end
		if field == "Studs" or field == "Equipped" or field == "Stats" or field == "StudXP" or field == "AutoDelete" then
			queued = true
			task.defer(function()
				queued = false
				render()
			end)
		end
	end)
end

return StudsMenu
