--[[

StudsMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/StudsMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The Backpack (StarterGui.Studs, a MenuSystem menu, Slime RNG style; pieces
-- found by BackpackRole, see tools/ui/screens/Studs.luau):
--   * a big "Backpack" title, SORT / EQUIP BEST / X up top
--   * "4/7 Equipped · 956K DMG" and your equipped studs in a row
--   * every stud you own below: odds, how many, its level, a size / Shiny /
--     Inverted badge
--   * tap one for its card: name, rarity, Clacks, Strength, Health, level
--     and XP, and EQUIP / UNEQUIP, FUSE x/5, DELETE
--   * storage used, and AUTO DELETE (Off → Common → ... → Epic, applied by
--     the server to Base-size rolls)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Variants = require(Shared.Variants)
local Types = require(Shared.Types)
local RollLogic = require(Shared.Util.RollLogic)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Roles = require(UI.Roles)
local StudCell = require(UI.StudCell)
local Format = require(UI.Format)
local Juice = require(UI.Juice)
local CombatFx = require(UI.CombatFx)

type StudDef = Types.StudDef
type VariantDef = Types.VariantDef

local StudsMenu = {}

local MENU = "Studs"
local ROLE = "BackpackRole"
local SORTS = { "RARITY", "STRENGTH", "COUNT" }
local BADGES: { [string]: { string } } = {
	Big = { "BIG", "#FFA040" },
	Huge = { "HUGE", "#FF7A2E" },
	Jumbo = { "JUMBO", "#FF4E2E" },
	Shiny = { "✨", "#FFE070" },
	Inverted = { "INV", "#C8A0FF" },
}

local gui: ScreenGui? = nil
local header: TextLabel
local equippedRow: GuiObject
local grid: ScrollingFrame
local card: GuiObject
local storageText: TextLabel
local storageColor: Color3
local autoButton: GuiObject
local sortButton: GuiObject
local bestButton: GuiObject? = nil
local equipColor: Color3
local cardParts: { [string]: any } = {}

local selected: string? = nil
local sortIndex = 1
local pending = false
local cells: { [string]: GuiObject } = {}

-- Rarities the player can auto-delete, lowest first.
local deletable: { string } = {}
for _, rarity in Config.Rarities.Order do
	if Config.Rarities.AutoDeletable[rarity] then
		table.insert(deletable, rarity)
	end
end

local function setButtonText(b: GuiObject, value: string)
	local label = b:FindFirstChild("Label", true)
	if label and label:IsA("TextLabel") then
		label.Text = value
	elseif b:IsA("TextButton") then
		b.Text = value
	end
end

local function onClick(object: GuiObject, fn: () -> ())
	local target = if object:IsA("GuiButton") then object else object:FindFirstChildWhichIsA("GuiButton", true)
	assert(target, `{object:GetFullName()} needs a button`)
	;(target :: GuiButton).Activated:Connect(function()
		Interface.play("Click")
		fn()
	end)
end

local function show(frame: Instance, name: string, value: string?)
	local label = frame:FindFirstChild(name, true)
	if label and label:IsA("TextLabel") then
		label.Visible = value ~= nil
		if value then
			label.Text = value
		end
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
-- Cells (copies of BackpackCell / EquippedCell)
--------------------------------------------------------------------------

local function makeCell(parent: Instance, template: string, key: string, count: number?, order: number): GuiObject?
	local def, variant = RollLogic.decodeKey(key)
	if not (def and variant) then return nil end
	local frame = Roles.template(gui :: ScreenGui, template) :: GuiObject
	frame.Name = key
	frame.LayoutOrder = order
	frame:SetAttribute("BackpackCell", true)

	local viewport = frame:FindFirstChildWhichIsA("ViewportFrame", true)
	if viewport then
		if not viewport.CurrentCamera then
			viewport.CurrentCamera = viewport:FindFirstChildOfClass("Camera")
		end
		StudCell.setViewport(viewport, def, variant)
	end
	local odds = frame:FindFirstChild("Odds", true)
	if odds and odds:IsA("TextLabel") then
		odds.Text = oddsText(def, variant)
		odds.TextColor3 = rarityColor(def):Lerp(Color3.new(1, 1, 1), 0.25)
	end
	show(frame, "Count", if count and count > 1 then `x{count}` else nil)
	local level = levelOf(def)
	show(frame, "Level", if level > 1 then `Lv. {level}` else nil)
	local badge = BADGES[variant.Name]
	show(frame, "Badge", if badge then `<font color="{badge[2]}">{badge[1]}</font>` else nil)
	show(frame, "Check", if template == "BackpackCell" and equippedCount(key) > 0 then "✓" else nil)

	local hit = frame:FindFirstChildWhichIsA("GuiButton", true)
	if hit then
		hit.Activated:Connect(function()
			Interface.play("Click")
			StudsMenu.select(if selected == key then nil else key)
		end)
	end
	frame.Parent = parent
	return frame
end

local function clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:GetAttribute("BackpackCell") then
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
	local unequipColor = cardParts.equip:GetAttribute("UnequipColor")
	cardParts.equip.BackgroundColor3 = if equipping or typeof(unequipColor) ~= "Color3" then equipColor else unequipColor
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
		makeCell(equippedRow, "EquippedCell", key, nil, i)
	end

	clear(grid)
	table.clear(cells)
	local studs = State.get("Studs") or {}
	for order, key in sortedKeys() do
		local cell = makeCell(grid, "BackpackCell", key, studs[key], order)
		if cell then
			cells[key] = cell
		end
	end
	if selected and not cells[selected] then
		selected = nil
	end
	if selected and cells[selected] then
		local edge = cells[selected]:FindFirstChild("Edge")
		if edge and edge:IsA("UIStroke") then
			edge.Color = Color3.new(1, 1, 1)
			edge.Thickness += 1
		end
	end
	renderCard()

	storageText.Text = `🎒 {stats.StudCount}/{stats.MaxStuds}`
	local full = storageText:GetAttribute("FullColor")
	storageText.TextColor3 = if stats.StudCount >= stats.MaxStuds and typeof(full) == "Color3" then full else storageColor
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
-- Bind (StarterGui.Studs)
--------------------------------------------------------------------------

local function bind(): boolean
	if gui then return true end
	local screen = Roles.gui(MENU)
	if not Roles.find(screen, ROLE, "Grid") then
		warn('[StudsMenu] StarterGui.Studs is the old window (no BackpackRole pieces); run tools/ui/migrate.luau on your place')
		return false
	end
	gui = screen
	local function part(name: string): any
		return Roles.get(screen, ROLE, name)
	end

	header = part("Header")
	equippedRow = part("Equipped")
	grid = part("Grid")
	card = part("Card")
	card.Visible = false
	storageText = part("Storage")
	storageColor = storageText.TextColor3
	autoButton = part("AutoDelete")
	sortButton = part("Sort")
	bestButton = part("EquipBest")

	-- Grid cells stay square, sized off the grid's width.
	local layout = grid:FindFirstChildOfClass("UIGridLayout")
	if layout then
		local cellScale = layout.CellSize.X.Scale
		if cellScale <= 0 then cellScale = 0.148 end
		local function sizeCells()
			local width = grid.AbsoluteSize.X * cellScale
			layout.CellSize = UDim2.fromOffset(width, width)
			layout.CellPadding = UDim2.fromOffset(width * 0.08, width * 0.08)
		end
		grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(sizeCells)
		sizeCells()
	end

	local viewport = part("CardViewport") :: ViewportFrame
	if not viewport:IsA("ViewportFrame") then
		viewport = viewport:FindFirstChildWhichIsA("ViewportFrame", true) :: ViewportFrame
	end
	if not viewport.CurrentCamera then
		viewport.CurrentCamera = viewport:FindFirstChildOfClass("Camera")
	end
	cardParts.viewport = viewport
	cardParts.name = part("CardName")
	cardParts.odds = part("CardOdds")
	cardParts.stats = part("CardStats")
	cardParts.level = part("CardLevel")
	cardParts.owned = part("CardOwned")
	cardParts.equip = part("Equip")
	cardParts.fuse = part("Fuse")
	equipColor = cardParts.equip.BackgroundColor3

	onClick(sortButton, function()
		sortIndex = sortIndex % #SORTS + 1
		render()
	end)
	onClick(bestButton :: GuiObject, function()
		run(State.equipBest)
	end)
	onClick(autoButton, onAutoDelete)
	onClick(cardParts.equip, onEquip)
	onClick(cardParts.fuse, onFuse)
	onClick(part("Delete"), onDelete)
	onClick(part("Deselect"), function()
		StudsMenu.select(nil)
	end)
	return true
end

--------------------------------------------------------------------------
-- Menu
--------------------------------------------------------------------------

function StudsMenu.open()
	Interface.open(MENU)
end

function StudsMenu.close()
	Interface.close(MENU)
end

-- For the tutorial's pointer.
function StudsMenu.equipBestButton(): GuiObject?
	return bestButton
end

function StudsMenu.isOpen(): boolean
	return Interface.isOpen(MENU)
end

function StudsMenu.start()
	Interface.setup()
	if not bind() then return end
	Interface.MenuOpened:Connect(function(name)
		if name == MENU then
			render()
		end
	end)
	Interface.MenuClosed:Connect(function(name)
		if name == MENU then
			selected = nil
		end
	end)

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
