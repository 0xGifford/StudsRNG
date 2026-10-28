--[[

ZonesMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/ZonesMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The Teleporter window (numbered zone rows, Slime RNG style: teleport to
-- owned zones, buy the next one with Clacks) and the zones in the world:
--   workspace.Zones.<Id>.Barrier  opens (locally) once the zone is owned,
--                                 shows a price sign, and opens this menu
--                                 when the player bumps into it.
-- The server decides ownership (Systems/ZoneShop); barriers are cosmetic,
-- keys in unowned zones never pay anyway.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Zones = require(Shared.Zones)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Kit = require(UI.Kit)
local Format = require(UI.Format)

local ZonesMenu = {}

local MENU = "Zones"
local ROW_COLOR = Color3.fromRGB(36, 38, 50)
local TOUCH_COOLDOWN = 3

local player = Players.LocalPlayer
local items: ScrollingFrame
local cards: { [string]: Frame } = {}
local pending = false

-- Barrier parts we've changed, with their original look.
type Saved = { Transparency: number, CanCollide: boolean }
local barrierParts: { [BasePart]: { zone: string, saved: Saved } } = {}
local signs: { [string]: BillboardGui } = {}
local lastTouch = 0

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

	local info = Kit.label(`x{def.KeyMultiplier} Clacks per key · {Zones.studCount(def.Id)} zone studs`)
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
-- World barriers
--------------------------------------------------------------------------

local function applyBarrier(part: BasePart, zone: string)
	local entry = barrierParts[part]
	if not entry then
		entry = { zone = zone, saved = { Transparency = part.Transparency, CanCollide = part.CanCollide } }
		barrierParts[part] = entry
	end
	local open = owned(zone)
	part.CanCollide = if open then false else entry.saved.CanCollide
	part.Transparency = if open then 1 else entry.saved.Transparency
end

local function signText(def: Zones.ZoneDef): string
	return `🔒 {def.Name}\n{Format.number(priceOf(def))} Clacks`
end

local function ensureSign(def: Zones.ZoneDef, part: BasePart)
	if signs[def.Id] then return end
	local gui = Instance.new("BillboardGui")
	gui.Name = "ZoneSign"
	gui.Size = UDim2.fromScale(8, 3)
	gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 2, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 120
	gui.Adornee = part
	local label = Kit.label(signText(def))
	label.TextColor3 = def.Color
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	signs[def.Id] = gui
end

local function refreshWorld()
	for part, entry in barrierParts do
		if part.Parent then
			applyBarrier(part, entry.zone)
		else
			barrierParts[part] = nil
		end
	end
	for id, gui in signs do
		local def = Zones.ById[id]
		gui.Enabled = def ~= nil and not owned(id)
		local label = gui:FindFirstChild("Label")
		if def and label and label:IsA("TextLabel") then
			label.Text = signText(def)
		end
	end
end

local function onBarrierTouched(zone: string, hit: BasePart)
	local character = player.Character
	if not character or not hit:IsDescendantOf(character) or owned(zone) then return end
	if os.clock() - lastTouch < TOUCH_COOLDOWN then return end
	lastTouch = os.clock()
	if not Interface.isOpen(MENU) then
		Interface.open(MENU)
	end
end

local function trackBarrier(zoneFolder: Instance, barrier: Instance)
	local def = Zones.ById[zoneFolder.Name]
	if not def then return end
	local parts: { BasePart } = {}
	if barrier:IsA("BasePart") then
		table.insert(parts, barrier)
	end
	for _, descendant in barrier:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	for _, part in parts do
		if not barrierParts[part] then
			applyBarrier(part, def.Id)
			part.Touched:Connect(function(hit)
				onBarrierTouched(def.Id, hit)
			end)
		end
	end
	if parts[1] then
		ensureSign(def, parts[1])
	end
	refreshWorld()
end

local function watchZones(folder: Instance)
	local function scan(zone: Instance)
		local barrier = zone:FindFirstChild("Barrier")
		if barrier then
			trackBarrier(zone, barrier)
		end
	end
	for _, zone in folder:GetChildren() do
		scan(zone)
	end
	-- StreamingEnabled: barriers can arrive later.
	folder.DescendantAdded:Connect(function(descendant)
		if descendant.Name == "Barrier" and descendant.Parent and descendant.Parent.Parent == folder then
			trackBarrier(descendant.Parent, descendant)
		elseif descendant:IsA("BasePart") then
			local node: Instance? = descendant
			while node and node.Parent ~= folder do
				if node.Name == "Barrier" and node.Parent and node.Parent.Parent == folder then
					trackBarrier(node.Parent, node)
					return
				end
				node = node.Parent
			end
		end
	end)
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
		elseif field == "Clacks" and Interface.isOpen(MENU) then
			refreshCards()
		end
	end)

	local folder = workspace:FindFirstChild(Config.ZoneFolder)
	if folder then
		watchZones(folder)
	else
		workspace.ChildAdded:Connect(function(child)
			if child.Name == Config.ZoneFolder then
				watchZones(child)
			end
		end)
	end
end

return ZonesMenu
