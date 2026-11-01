--[[

IndexMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/IndexMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The Stud Index, Slime RNG style (StarterGui.Index, a MenuSystem menu;
-- its pieces are found by IndexRole, see tools/ui/screens/Index.luau):
--   * left: one tab per variant (Base, Big, Huge, Jumbo, Shiny, Inverted)
--   * middle: every stud in that variant (name, model, 1 / X odds);
--     undiscovered ones are dark silhouettes named "???"
--   * right: the selected stud (odds, rarity, Strength, Health, how many
--     times you've rolled it) and the tab's reward, claimable once every
--     stud in the tab is found (Systems/IndexRewards)
--   * bottom: "Unlocks Needed" for the tab

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local Roles = require(UI.Roles)
local Kit = require(UI.Kit)
local StudCell = require(UI.StudCell)
local Format = require(UI.Format)

local Menus = ReplicatedStorage:WaitForChild("MenuSystem"):WaitForChild("Menus")
local ProgressBar = require(Menus:WaitForChild("ProgressBar"))
local StateStyle = require(Menus:WaitForChild("StateStyle"))

type StudDef = Types.StudDef

local IndexMenu = {}

local MENU = "Index"
local ROLE = "IndexRole"
local LOCKED = Color3.fromRGB(255, 140, 140)

local sortedStuds: { StudDef } = table.clone(Studs.List)
table.sort(sortedStuds, function(a, b)
	return a.OneIn < b.OneIn
end)

type Cell = { frame: GuiObject, viewport: ViewportFrame, name: TextLabel, odds: TextLabel, def: StudDef }
type Tab = { frame: GuiObject }

local cells: { Cell } = {}
local tabs: { [string]: Tab } = {}
local detail: { viewport: ViewportFrame, name: TextLabel, odds: TextLabel, rarity: TextLabel, strength: TextLabel, health: TextLabel, rolls: TextLabel }
local claimButton: GuiObject
local progressFill: GuiObject
local progressText: TextLabel


local activeVariant = "Normal"
local selected: StudDef = sortedStuds[1]
local built = false

-- Picked or not: MenuSystem's StateStyle paints it (StatePreset =
-- "Selected" on the template, its outline a UIStroke named MainStroke).
local function highlight(frame: GuiObject, on: boolean)
	StateStyle.Apply(frame, on)
end

local function viewportOf(frame: Instance): ViewportFrame
	local viewport = (if frame:IsA("ViewportFrame") then frame else frame:FindFirstChildWhichIsA("ViewportFrame", true)) :: ViewportFrame
	assert(viewport, `{frame:GetFullName()} needs a ViewportFrame`)
	return viewport
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
		highlight(cell.frame, cell.def == def)
	end
end

local function renderReward()
	local found, total = RollLogic.tabProgress(State.get("Index") or {}, activeVariant)
	local claims = State.get("IndexClaims") or {}
	local claimed = claims[activeVariant] == true
	ProgressBar.Set(progressFill, { Progress = found / math.max(total, 1) })
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
			cell.odds.TextColor3 = cell.odds:GetAttribute("IdleColor") :: Color3? or cell.odds.TextColor3
		else
			local zone = Zones.ById[def.World]
			cell.odds.Text = `🔒 {if zone then zone.Name else def.World}`
			cell.odds.TextColor3 = LOCKED
		end
	end
	for name, tab in tabs do
		highlight(tab.frame, name == activeVariant)
	end
	renderDetail()
	renderReward()
end

--------------------------------------------------------------------------
-- Bind (StarterGui.Index)
--------------------------------------------------------------------------

local function bind()
	if built then return end
	built = true
	local gui = Roles.gui(MENU)
	local function part(role: string): any
		return Roles.get(gui, ROLE, role)
	end

	-- Tabs: one copy of IndexTab per variant.
	local tabColumn = part("Tabs")
	for order, name in Variants.Order do
		local variant = Variants.ById[name]
		local tab = Roles.template(gui, "IndexTab") :: GuiObject
		tab.Name = name
		tab.LayoutOrder = order
		local label = tab:FindFirstChild("Label", true)
		if label and label:IsA("TextLabel") then
			label.Text = Variants.label(variant)
		end
		StudCell.setViewport(viewportOf(tab), sortedStuds[1], variant)
		tab.Parent = tabColumn
		tabs[name] = { frame = tab }
		local button = if tab:IsA("GuiButton") then tab else tab:FindFirstChildWhichIsA("GuiButton", true)
		if button then
			(button :: GuiButton).Activated:Connect(function()
				Interface.play("Click")
				activeVariant = name
				renderGrid()
			end)
		end
	end

	-- Grid: one copy of IndexCell per stud; cells stay square-ish at any size.
	local grid = part("Grid") :: ScrollingFrame
	local layout = grid:FindFirstChildOfClass("UIGridLayout")
	if layout then
		local cellScale = layout.CellSize.X.Scale
		local padScale = layout.CellPadding.X.Scale
		local function sizeCells()
			local width = grid.AbsoluteSize.X * cellScale
			layout.CellSize = UDim2.new(cellScale, 0, 0, width * 1.02)
			layout.CellPadding = UDim2.new(padScale, 0, 0, width * 0.1)
		end
		grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(sizeCells)
		sizeCells()
	end
	for order, def in sortedStuds do
		local frame = Roles.template(gui, "IndexCell") :: GuiObject
		frame.Name = def.Id
		frame.LayoutOrder = order
		local odds = frame:FindFirstChild("Odds", true) :: TextLabel
		odds:SetAttribute("IdleColor", odds.TextColor3)
		local cell: Cell = {
			frame = frame,
			viewport = viewportOf(frame),
			name = frame:FindFirstChild("Name", true) :: TextLabel,
			odds = odds,
			def = def,
		}
		local button = frame:FindFirstChildWhichIsA("GuiButton", true)
		if button then
			button.Activated:Connect(function()
				Interface.play("Click")
				selected = def
				renderDetail()
			end)
		end
		frame.Parent = grid
		table.insert(cells, cell)
	end

	detail = {
		viewport = viewportOf(part("DetailViewport")),
		name = part("DetailName"),
		odds = part("DetailOdds"),
		rarity = part("DetailRarity"),
		strength = part("DetailStrength"),
		health = part("DetailHealth"),
		rolls = part("DetailRolls"),
	}
	progressFill = part("ProgressFill")
	progressText = part("ProgressText")

	-- Tab reward.
	local luckPct = math.floor(Config.IndexTabReward.Luck * 100 + 0.5)
	local clackPct = math.floor(Config.IndexTabReward.Clacks * 100 + 0.5)
	local luckLabel = Roles.find(gui, ROLE, "RewardLuck")
	if luckLabel then luckLabel.Text = `+{luckPct}%` end
	local clackLabel = Roles.find(gui, ROLE, "RewardClacks")
	if clackLabel then clackLabel.Text = `+{clackPct}%` end

	claimButton = part("Claim")
	Interface.bindButton(claimButton, function()
		local response = State.claimIndexTab(activeVariant)
		if response.Ok then
			Interface.toast(`{Variants.label(Variants.ById[activeVariant])} tab complete! +{luckPct}% luck, +{clackPct}% Clacks`, Color3.fromRGB(120, 255, 140))
		else
			Interface.toastError(response)
		end
	end)
end

--------------------------------------------------------------------------
-- Menu
--------------------------------------------------------------------------

function IndexMenu.open()
	Interface.open(MENU)
end

function IndexMenu.close()
	Interface.close(MENU)
end

function IndexMenu.isOpen(): boolean
	return Interface.isOpen(MENU)
end

function IndexMenu.start()
	Interface.setup()
	local gui = Roles.gui(MENU)
	if not Roles.find(gui, ROLE, "Grid") then
		warn('[IndexMenu] StarterGui.Index is the old window (no IndexRole pieces); run tools/ui/migrate.luau on your place')
		return
	end
	bind()
	Interface.MenuOpened:Connect(function(name)
		if name == MENU then
			renderGrid()
		end
	end)
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
