--[[

ZonesMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/ZonesMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The Teleporter window (numbered zone rows, Slime RNG style: teleport to
-- owned zones, buy the next one with Clacks) and the zone barriers in the
-- world (Shared/Tags):
--   ZoneBarrier  opens (locally) once its zone is owned. Until then, walking
--                up to it shows the buy prompt (a ScreenGui): the zone's
--                title, its price in Clacks and a Buy button. Attributes:
--                ZoneId, ShowPrompt, PromptDistance, Title, OpenOnTouch.
--   ZoneGate     hidden (locally) once owned when HideWhenOwned is set.
-- The server decides ownership (Systems/ZoneShop); barriers are cosmetic,
-- keys in unowned zones never pay anyway.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Zones)
local Tags = require(Shared.Tags)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Kit = require(UI.Kit)
local Format = require(UI.Format)
local UIConfig = require(UI.UIConfig)

local ZonesMenu = {}

local MENU = "Zones"
local ROW_COLOR = Color3.fromRGB(36, 38, 50)
local TOUCH_COOLDOWN = 3
local PROMPT_DISTANCE = 30 -- studs from a locked barrier
local PROMPT_RATE = 0.15 -- seconds between proximity checks

local player = Players.LocalPlayer
local items: ScrollingFrame
local cards: { [string]: Frame } = {}
local pending = false

-- Tagged barriers and gates we manage, with their parts' original look.
type Saved = { Transparency: number, CanCollide: boolean }
type Blocker = {
	root: Instance,
	tag: string,
	parts: { [BasePart]: Saved },
	connections: { RBXScriptConnection },
}
type Prompt = { gui: ScreenGui, title: TextLabel, price: TextLabel, note: TextLabel, button: Frame }
local blockers: { [Instance]: Blocker } = {}
local lastTouch = 0
local prompt: Prompt? = nil
local promptZone: string? = nil

local function owned(id: string): boolean
	local unlocked = State.get("UnlockedWorlds") or {}
	return unlocked[id] == true
end

local function priceOf(def: Zones.ZoneDef): number
	return Zones.price(def, State.stats().ZoneDiscount)
end

local function previousOf(def: Zones.ZoneDef): Zones.ZoneDef?
	return Zones.List[def.Order - 1]
end

--------------------------------------------------------------------------
-- Menu
--------------------------------------------------------------------------

local function updateCard(def: Zones.ZoneDef)
	local row = cards[def.Id]
	if not row then return end
	local button = row:FindFirstChild("Action")
	if not (button and button:IsA("Frame")) then return end
	local nextZone = Zones.nextFor(State.get("UnlockedWorlds") or {})
	if owned(def.Id) then
		Kit.paint(button, "Green")
		Interface.setText(button, "Teleport")
	elseif nextZone and nextZone.Id == def.Id then
		local short = (State.get("Clacks") or 0) < priceOf(def)
		Kit.paint(button, if short then "Sunset" else "Orange")
		Interface.setText(button, Format.number(priceOf(def)))
	else
		Kit.paint(button, "Purple")
		Interface.setText(button, "Locked")
	end
end

local function onZone(def: Zones.ZoneDef)
	if pending then return end
	if owned(def.Id) then
		pending = true
		local response = State.teleportZone(def.Id)
		pending = false
		if response.Ok then
			Interface.close(MENU)
		else
			Interface.toastError(response)
		end
		return
	end

	local nextZone = Zones.nextFor(State.get("UnlockedWorlds") or {})
	if not nextZone or nextZone.Id ~= def.Id then
		local previous = previousOf(def)
		Interface.toast(`Unlock {if previous then previous.Name else "the previous zone"} first!`)
		return
	end
	local price = priceOf(def)
	if (State.get("Clacks") or 0) < price then
		Interface.toast(`You need {Format.number(price)} Clacks`, Color3.fromRGB(255, 110, 110))
		return
	end

	pending = true
	local response = State.buyZone(def.Id)
	pending = false
	if response.Ok then
		Interface.toast(`{def.Name} unlocked!`, def.Color)
		Interface.close(MENU)
	else
		Interface.toastError(response)
	end
end

-- One Teleporter row: "3  Polar ............ [Teleport]".
local function makeRow(def: Zones.ZoneDef): Frame
	local row = Instance.new("Frame")
	row.Name = def.Id
	row.BackgroundColor3 = ROW_COLOR
	row.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.18, 0)
	corner.Parent = row
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(12, 12, 18)
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = row

	local number = Kit.label(tostring(def.Order))
	number.Name = "Number"
	number.AnchorPoint = Vector2.new(0.5, 0.5)
	number.Position = UDim2.fromScale(0.065, 0.5)
	number.Size = UDim2.fromScale(0.07, 0.5)
	number.Parent = row

	local name = Kit.label(`{def.Emoji} {def.Name}`)
	name.Name = "ZoneName"
	name.AnchorPoint = Vector2.new(0, 0.5)
	name.Position = UDim2.fromScale(0.13, 0.4)
	name.Size = UDim2.fromScale(0.52, 0.46)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row

	local studs = Zones.studCount(def.Id)
	local info = Kit.label(`x{Format.number(def.KeyMultiplier)} Clacks per key` .. (if studs > 0 then ` · {studs} zone studs` else ""))
	info.Name = "Info"
	info.AnchorPoint = Vector2.new(0, 0.5)
	info.Position = UDim2.fromScale(0.13, 0.78)
	info.Size = UDim2.fromScale(0.52, 0.24)
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextColor3 = def.Color
	info.Parent = row

	local button = Kit.button("Green", "Teleport")
	button.Name = "Action"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.fromScale(0.97, 0.5)
	button.Size = UDim2.fromScale(0.27, 0.62)
	button.Parent = row
	Interface.bindButton(button, function()
		onZone(def)
	end)
	return row
end

local function rebuild()
	Kit.list(items)
	table.clear(cards)
	for index, def in Zones.List do
		local row = makeRow(def)
		cards[def.Id] = row
		Kit.row(items, row, 6.2, index)
		updateCard(def)
	end
end

local function refreshCards()
	for _, def in Zones.List do
		updateCard(def)
	end
end

--------------------------------------------------------------------------
-- World barriers and gates
--------------------------------------------------------------------------

local function onBarrierTouched(blocker: Blocker, hit: BasePart)
	local zone = Tags.zoneOf(blocker.root)
	local character = player.Character
	if not zone or not character or not hit:IsDescendantOf(character) or owned(zone) then return end
	if not Tags.read(blocker.root, Tags.Attr.OpenOnTouch, false) then return end
	if os.clock() - lastTouch < TOUCH_COOLDOWN then return end
	lastTouch = os.clock()
	if not Interface.isOpen(MENU) then
		Interface.open(MENU)
	end
end

--------------------------------------------------------------------------
-- Buy prompt (ScreenGui)
--------------------------------------------------------------------------

-- Title, Clack icon + price and a Buy button, at the bottom of the screen.
local function makePrompt(): Prompt
	local gui = Instance.new("ScreenGui")
	gui.Name = "ZonePrompt"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Enabled = false

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.fromScale(0.5, 0.76)
	panel.Size = UDim2.fromScale(0.34, 0.2)
	panel.BackgroundColor3 = ROW_COLOR
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 2.3
	aspect.Parent = panel
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(520, 230)
	limit.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Outline"
	stroke.Thickness = 4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = panel

	local title = Kit.label("")
	title.Name = "Title"
	title.Position = UDim2.fromScale(0.5, 0.2)
	title.Size = UDim2.fromScale(0.9, 0.3)
	title.Parent = panel

	local priceRow = Instance.new("Frame")
	priceRow.Name = "Price"
	priceRow.BackgroundTransparency = 1
	priceRow.AnchorPoint = Vector2.new(0.5, 0.5)
	priceRow.Position = UDim2.fromScale(0.5, 0.47)
	priceRow.Size = UDim2.fromScale(0.9, 0.22)
	priceRow.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.02, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = priceRow
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(1, 1)
	icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	icon.ScaleType = Enum.ScaleType.Fit
	icon.LayoutOrder = 1
	icon.Parent = priceRow
	Kit.setIcon(icon, UIConfig.Icons.Clacks)
	local price = Kit.label("")
	price.Name = "Amount"
	price.AnchorPoint = Vector2.zero
	price.Position = UDim2.new()
	price.Size = UDim2.fromScale(0.5, 1)
	price.TextXAlignment = Enum.TextXAlignment.Left
	price.LayoutOrder = 2
	price.Parent = priceRow

	local button = Kit.button("Green", "BUY")
	button.Name = "Buy"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.78)
	button.Size = UDim2.fromScale(0.42, 0.3)
	button.Parent = panel
	Interface.bindButton(button, function()
		local def = if promptZone then Zones.ById[promptZone] else nil
		if def then
			onZone(def)
		end
	end)

	-- Shown instead of the button when an earlier zone is still locked.
	local note = Kit.label("")
	note.Name = "Note"
	note.Position = UDim2.fromScale(0.5, 0.78)
	note.Size = UDim2.fromScale(0.9, 0.2)
	note.TextColor3 = Color3.fromRGB(255, 120, 120)
	note.Visible = false
	note.Parent = panel

	gui.Parent = player:WaitForChild("PlayerGui")
	return { gui = gui, title = title, price = price, note = note, button = button }
end

-- How far a point is from a part's box.
local function distanceTo(part: BasePart, position: Vector3): number
	local localPoint = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local clamped = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)
	return (localPoint - clamped).Magnitude
end

-- The locked zone whose barrier the player is standing at, if any.
local function promptTarget(): (Zones.ZoneDef?, Blocker?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or Interface.isOpen() then return nil, nil end
	local best: Zones.ZoneDef?, bestBlocker: Blocker?, bestDistance = nil, nil, math.huge
	for _, blocker in blockers do
		if blocker.tag == Tags.ZoneBarrier and Tags.read(blocker.root, Tags.Attr.ShowPrompt, true) then
			local zone = Tags.zoneOf(blocker.root)
			local def = if zone then Zones.ById[zone] else nil
			if def and not owned(def.Id) then
				local reach = Tags.read(blocker.root, Tags.Attr.PromptDistance, PROMPT_DISTANCE)
				for part in blocker.parts do
					local distance = distanceTo(part, root.Position)
					if distance <= reach and distance < bestDistance then
						best, bestBlocker, bestDistance = def, blocker, distance
					end
				end
			end
		end
	end
	return best, bestBlocker
end

local function updatePrompt()
	local def, blocker = promptTarget()
	if not def or not blocker then
		promptZone = nil
		if prompt then prompt.gui.Enabled = false end
		return
	end
	local p = prompt or makePrompt()
	prompt = p
	promptZone = def.Id

	local nextZone = Zones.nextFor(State.get("UnlockedWorlds") or {})
	local isNext = nextZone ~= nil and nextZone.Id == def.Id
	local price = priceOf(def)
	local clacks = State.get("Clacks") or 0
	local short = clacks < price
	p.title.Text = Tags.string(blocker.root, Tags.Attr.Title) or `{def.Emoji} {def.Name}`
	p.title.TextColor3 = def.Color
	local outline = p.gui:FindFirstChild("Outline", true)
	if outline and outline:IsA("UIStroke") then
		outline.Color = def.Color
	end
	p.price.Text = Format.number(price)
	-- Red price and "NEED 297K" when short, so it's clear what's missing.
	p.price.TextColor3 = if short and isNext then Color3.fromRGB(255, 120, 120) else Color3.new(1, 1, 1)
	p.button.Visible = isNext
	p.note.Visible = not isNext
	if isNext then
		Kit.paint(p.button, if short then "Sunset" else "Green")
		Interface.setText(p.button, if short then `NEED {Format.number(price - clacks)}` else "BUY")
	else
		local previous = previousOf(def)
		p.note.Text = `Unlock {if previous then previous.Name else "the previous zone"} first`
	end
	p.gui.Enabled = true
end

--------------------------------------------------------------------------
-- Barriers and gates in the world
--------------------------------------------------------------------------

local function partsOf(root: Instance): { BasePart }
	local parts: { BasePart } = {}
	if root:IsA("BasePart") then
		table.insert(parts, root)
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function refreshBlocker(blocker: Blocker)
	local zone = Tags.zoneOf(blocker.root)
	local def = if zone then Zones.ById[zone] else nil
	local barrier = blocker.tag == Tags.ZoneBarrier

	for _, part in partsOf(blocker.root) do
		if not blocker.parts[part] then
			blocker.parts[part] = { Transparency = part.Transparency, CanCollide = part.CanCollide }
			if barrier then
				table.insert(blocker.connections, part.Touched:Connect(function(hit)
					onBarrierTouched(blocker, hit)
				end))
			end
		end
	end

	local open = def ~= nil and owned(def.Id)
	local hide = open and (barrier or Tags.read(blocker.root, Tags.Attr.HideWhenOwned, false))
	for part, saved in blocker.parts do
		if part.Parent then
			part.CanCollide = if hide then false else saved.CanCollide
			part.Transparency = if hide then 1 else saved.Transparency
		else
			blocker.parts[part] = nil
		end
	end

end

local function refreshWorld()
	for _, blocker in blockers do
		refreshBlocker(blocker)
	end
end

local function track(root: Instance, tag: string)
	if blockers[root] then return end
	local blocker: Blocker = { root = root, tag = tag, parts = {}, connections = {} }
	blockers[root] = blocker
	-- Attributes are live; parts can stream in later.
	table.insert(blocker.connections, root.AttributeChanged:Connect(function()
		refreshBlocker(blocker)
	end))
	table.insert(blocker.connections, root.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			refreshBlocker(blocker)
		end
	end))
	refreshBlocker(blocker)
end

local function untrack(root: Instance)
	local blocker = blockers[root]
	if not blocker then return end
	blockers[root] = nil
	for _, connection in blocker.connections do
		connection:Disconnect()
	end
	for part, saved in blocker.parts do
		part.CanCollide = saved.CanCollide
		part.Transparency = saved.Transparency
	end
end

local function watchTag(tag: string)
	for _, root in CollectionService:GetTagged(tag) do
		track(root, tag)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(root)
		track(root, tag)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(untrack)
end

--------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------

function ZonesMenu.start()
	Interface.setup()
	local window = Interface.Canva:WaitForChild(MENU)
	items = window:WaitForChild("Main"):WaitForChild("Items") :: ScrollingFrame

	Interface.MenuOpened:Connect(function(name)
		if name == MENU then
			rebuild()
		end
	end)

	State.Changed:Connect(function(field)
		if field == "UnlockedWorlds" then
			refreshWorld()
			if Interface.isOpen(MENU) then refreshCards() end
		elseif field == "Stats" then
			refreshWorld()
			if Interface.isOpen(MENU) then refreshCards() end
		elseif field == "Clacks" then
			if Interface.isOpen(MENU) then refreshCards() end
		end
	end)

	watchTag(Tags.ZoneBarrier)
	watchTag(Tags.ZoneGate)

	task.spawn(function()
		while true do
			updatePrompt()
			task.wait(PROMPT_RATE)
		end
	end)
end

return ZonesMenu
