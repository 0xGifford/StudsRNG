--[[ 

IndexMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/IndexMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The stud index: one tab per variant, every stud shown with its odds,
-- undiscovered ones as dark silhouettes named "???". The progress bar counts
-- every stud × variant entry, and the line above it shows the next milestone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Studs = require(Shared.Studs)
local Variants = require(Shared.Variants)
local Types = require(Shared.Types)
local RollLogic = require(Shared.Util.RollLogic)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local StudCell = require(UI.StudCell)
local Format = require(UI.Format)

type StudDef = Types.StudDef

local IndexMenu = {}

local MENU = "Index"

local window: Frame
local main: CanvasGroup
local items: ScrollingFrame
local progressBar: Frame
local progress: Frame
local tabs: { [string]: Frame } = {}

local activeVariant = "Normal"
local cells: { Frame } = {}

local sortedStuds: { StudDef } = table.clone(Studs.List)
table.sort(sortedStuds, function(a, b)
	return a.OneIn < b.OneIn
end)

local function milestoneText(discovered: number): string
	for _, milestone in Config.IndexMilestones do
		if discovered < milestone.Count then
			local rewards = {}
			if milestone.Slots then
				table.insert(rewards, `+{milestone.Slots} slot`)
			end
			if milestone.Luck then
				table.insert(rewards, `+{math.floor(milestone.Luck * 100 + 0.5)}% luck`)
			end
			if milestone.Clacks then
				table.insert(rewards, `+{math.floor(milestone.Clacks * 100 + 0.5)}% Clacks`)
			end
			return `Next: {milestone.Count} found → {table.concat(rewards, ", ")}`
		end
	end
	return "Every milestone unlocked!"
end

local function setInfo(text: string)
	Interface.setText(main, text)
end

local function updateProgress()
	local stats = State.stats()
	Interface.setText(progress, `{stats.Discovered}/{stats.IndexTotal}`, "Amount", "AmountShadow")
	local fraction = if stats.IndexTotal > 0 then stats.Discovered / stats.IndexTotal else 0
	TweenService:Create(progressBar, Interface.FAST, { Size = UDim2.fromScale(fraction, 1) }):Play()
	setInfo(milestoneText(stats.Discovered))
end

local function clearCells()
	for _, cell in cells do
		cell:Destroy()
	end
	table.clear(cells)
end

local function rebuild()
	clearCells()

	local index = State.get("Index") or {}
	local variant = Variants.ById[activeVariant]
	local luck = State.stats().Luck

	for order, def in sortedStuds do
		local key = RollLogic.encodeKey(def.Id, variant.Name)
		local found = index[key] == true
		local cell = StudCell.new(def, variant)
		cell.LayoutOrder = order
		cell.Size = UDim2.new() -- the grid sizes cells

		local viewport = StudCell.getViewport(cell)
		if viewport then
			StudCell.setSilhouette(viewport, not found)
		end
		Interface.setText(cell, if found then def.Name else "???")
		local oneIn = RollLogic.displayOneIn(def.OneIn * variant.OneIn, luck)
		Interface.setText(cell, Format.oneIn(oneIn), "Count", "Count")

		Interface.bindButton(cell, function()
			local name = if found then Format.studName(def, variant) else "???"
			local mult = Format.multiplier(RollLogic.multiplierOf(def, variant))
			setInfo(`{name} · {def.Rarity} · {Format.oneIn(oneIn)} · {mult}`)
		end, 0.95, 0.88)

		cell.Parent = items
		table.insert(cells, cell)
	end

	updateProgress()
end

local function selectTab(name: string)
	activeVariant = name
	for tabName, tab in tabs do
		local stroke = tab:FindFirstChild("ActivatedStroke")
		if stroke and stroke:IsA("UIStroke") then
			stroke.Enabled = tabName == name
		end
	end
	rebuild()
end

function IndexMenu.start()
	Interface.setup()

	window = Interface.Canva:WaitForChild(MENU) :: Frame
	main = window:WaitForChild("Main") :: CanvasGroup
	items = main:WaitForChild("Items") :: ScrollingFrame
	progress = main:WaitForChild("Progress") :: Frame
	progressBar = progress:WaitForChild("Bar") :: Frame

	local side = window:WaitForChild("Side")
	for _, name in Variants.Order do
		local tab = side:FindFirstChild(name)
		if tab and tab:IsA("Frame") then
			tabs[name] = tab
			Interface.bindButton(tab, function()
				selectTab(name)
			end, 0.95, 0.85)
		end
	end

	Interface.MenuOpened:Connect(function(name)
		if name == MENU then
			selectTab(activeVariant)
		end
	end)
	Interface.MenuClosed:Connect(function(name)
		if name == MENU then
			clearCells() -- drop the viewports while hidden
		end
	end)

	State.Changed:Connect(function(field)
		if field == "Index" then
			if Interface.isOpen(MENU) then
				rebuild()
			end
		end
	end)
end

return IndexMenu
