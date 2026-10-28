--[[ 

StudsMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/StudsMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The stud inventory. Owned studs best-first; tap one to select it, then
-- Equip / Unequip, Fuse or Delete from the side buttons. Equip Best fills
-- every slot, and Auto Delete cycles a rarity threshold (Off → Common →
-- Uncommon → Rare → Epic) that the server applies to Normal-variant rolls.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Variants = require(Shared.Variants)
local RollLogic = require(Shared.Util.RollLogic)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local StudCell = require(UI.StudCell)
local Format = require(UI.Format)

local StudsMenu = {}

local MENU = "Studs"

local window: Frame
local main: CanvasGroup
local items: ScrollingFrame
local progress: Frame
local progressBar: Frame
local actionFrames: { [string]: Frame } = {}

local selected: string? = nil
local cells: { [string]: Frame } = {}
local pending = false -- an action is waiting on the server

-- Rarities the player can auto-delete, lowest first.
local deletable: { string } = {}
for _, rarity in Config.Rarities.Order do
	if Config.Rarities.AutoDeletable[rarity] then
		table.insert(deletable, rarity)
	end
end

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function equippedCount(key: string): number
	return RollLogic.countInList(State.get("Equipped") or {}, key)
end

local function owned(key: string): number
	return (State.get("Studs") or {})[key] or 0
end

-- Highest rarity currently auto-deleted (thresholds are contiguous), or nil.
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

local function setInfo(text: string)
	Interface.setText(main, text)
end

local function defaultInfo()
	local stats = State.stats()
	local equipped = #(State.get("Equipped") or {})
	if stats.StudCount == 0 then
		setInfo("Roll to get your first stud!")
	else
		setInfo(`Equipped {equipped}/{stats.Slots} · {Format.multiplier(stats.ClackMultiplier)} Clacks`)
	end
end

local function selectedInfo(key: string)
	local def, variant = RollLogic.decodeKey(key)
	if not def or not variant then return end
	local mult = Format.multiplier(RollLogic.multiplierOf(def, variant))
	setInfo(`{Format.studName(def, variant)} · {def.Rarity} · {mult} · {owned(key)} owned, {equippedCount(key)} equipped`)
end

local function updateActions()
	local key = selected
	local equipFrame = actionFrames.Equip
	local fuseFrame = actionFrames.Fuse

	if key then
		local canEquipMore = equippedCount(key) < owned(key)
			and #(State.get("Equipped") or {}) < State.stats().Slots
		if equipFrame then
			Interface.setText(equipFrame, if canEquipMore or equippedCount(key) == 0 then "Equip" else "Unequip")
		end
		local _, variant = RollLogic.decodeKey(key)
		if fuseFrame then
			local fuseCost = State.stats().FuseCost
			if variant and Variants.Next[variant.Name] then
				Interface.setText(fuseFrame, `Fuse {math.min(owned(key), fuseCost)}/{fuseCost}`)
			else
				Interface.setText(fuseFrame, "Fuse")
			end
		end
	else
		if equipFrame then Interface.setText(equipFrame, "Equip") end
		if fuseFrame then Interface.setText(fuseFrame, "Fuse") end
	end

	local autoFrame = actionFrames.AutoDelete
	if autoFrame then
		local threshold = autoDeleteThreshold()
		Interface.setText(autoFrame, if threshold then `Auto Delete: {threshold}` else "Auto Delete: Off")
	end
end

local function updateProgress()
	local stats = State.stats()
	Interface.setText(progress, `{stats.StudCount}/{stats.MaxStuds}`, "Amount", "AmountShadow")
	local fraction = math.clamp(stats.StudCount / stats.MaxStuds, 0, 1)
	TweenService:Create(progressBar, Interface.FAST, { Size = UDim2.fromScale(fraction, 1) }):Play()
end

--------------------------------------------------------------------------
-- Grid
--------------------------------------------------------------------------

local function clearCells()
	for _, cell in cells do
		cell:Destroy()
	end
	table.clear(cells)
end

local function select(key: string?)
	if selected and cells[selected] then
		StudCell.setSelected(cells[selected], false)
	end
	selected = key
	if key and cells[key] then
		StudCell.setSelected(cells[key], true)
		selectedInfo(key)
	else
		defaultInfo()
	end
	updateActions()
end

local function rebuild()
	clearCells()
	local studs = State.get("Studs") or {}

	for order, key in RollLogic.sortedOwned(studs) do
		local def, variant = RollLogic.decodeKey(key)
		if def and variant then
			local cell = StudCell.new(def, variant)
			cell.LayoutOrder = order
			cell.Size = UDim2.new()
			Interface.setText(cell, Format.studName(def, variant))
			Interface.setText(cell, `x{studs[key]}`, "Count", "Count")
			local equipped = equippedCount(key)
			if equipped > 0 then
				Interface.setText(cell, if equipped > 1 then `E{equipped}` else "E", "Badge", "Badge")
			end
			Interface.bindButton(cell, function()
				select(if selected == key then nil else key)
			end, 0.95, 0.88)
			cell.Parent = items
			cells[key] = cell
		end
	end

	if selected and not cells[selected] then
		selected = nil
	end
	select(selected)
	updateProgress()
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
	if not key then
		Interface.toast("Select a stud first")
		return
	end
	local canEquipMore = equippedCount(key) < owned(key)
		and #(State.get("Equipped") or {}) < State.stats().Slots
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
	if not key then
		Interface.toast("Select a stud first")
		return
	end
	run(function()
		local response = State.fuse(key)
		if response.Ok and response.Key then
			local def, variant = RollLogic.decodeKey(response.Key)
			if def and variant then
				Interface.toast(`Fused into {Format.studName(def, variant)}!`, Color3.fromRGB(255, 230, 90))
			end
		end
		return response
	end)
end

local function onDelete()
	local key = selected
	if not key then
		Interface.toast("Select a stud first")
		return
	end
	run(function()
		return State.delete(key, 1)
	end)
end

local function onAutoDelete()
	local current = autoDeleteThreshold()
	local nextIndex = 1
	if current then
		nextIndex = (table.find(deletable, current) or 0) + 1
	end
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
-- Lifecycle
--------------------------------------------------------------------------

function StudsMenu.start()
	Interface.setup()

	window = Interface.Canva:WaitForChild(MENU) :: Frame
	main = window:WaitForChild("Main") :: CanvasGroup
	items = main:WaitForChild("Items") :: ScrollingFrame
	progress = main:WaitForChild("Progress") :: Frame
	progressBar = progress:WaitForChild("Bar") :: Frame

	local handlers: { [string]: () -> () } = {
		Equip = onEquip,
		EquipBest = function()
			run(State.equipBest)
		end,
		Fuse = onFuse,
		Delete = onDelete,
		AutoDelete = onAutoDelete,
	}
	local side = window:WaitForChild("Side")
	for name, handler in handlers do
		local frame = side:FindFirstChild(name)
		if frame and frame:IsA("Frame") then
			actionFrames[name] = frame
			Interface.bindButton(frame, handler, 0.95, 0.85)
		end
	end

	Interface.MenuOpened:Connect(function(name)
		if name == MENU then
			rebuild()
		end
	end)
	Interface.MenuClosed:Connect(function(name)
		if name == MENU then
			clearCells()
			selected = nil
		end
	end)

	-- Studs and Equipped usually change together: rebuild once per patch.
	local rebuildQueued = false
	local function queueRebuild()
		if rebuildQueued then return end
		rebuildQueued = true
		task.defer(function()
			rebuildQueued = false
			if Interface.isOpen(MENU) then
				rebuild()
			end
		end)
	end

	State.Changed:Connect(function(field)
		if not Interface.isOpen(MENU) then return end
		if field == "Studs" or field == "Equipped" or field == "Stats" then
			queueRebuild()
		elseif field == "AutoDelete" then
			updateActions()
		end
	end)
end

return StudsMenu
