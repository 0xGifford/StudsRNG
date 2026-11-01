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
--   ZoneBarrier  opens (locally) once its zone is owned. With
--                Config.ZoneUnlock.BarrierSigns (or ShowPrompt on it) a sign
--                (SurfaceGui, both faces of its biggest part) shows the
--                zone's title, its price in Clacks and a BUY button you click
--                right on the barrier. Buying never teleports: the barrier
--                opens and you walk in. Attributes: ZoneId, ShowPrompt (show
--                the sign), PromptDistance (how far it renders), Title.
--   ZoneGate     hidden (locally) once owned when HideWhenOwned is set.
-- Buying a zone dissolves its barrier in front of you: it flashes, bursts
-- into sparks with a shockwave and fades away.
-- The server decides ownership (Systems/ZoneShop); barriers are cosmetic,
-- keys in unowned zones never pay anyway.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Zones = require(Shared.Zones)
local Tags = require(Shared.Tags)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Roles = require(UI.Roles)
local Kit = require(UI.Kit)
local Format = require(UI.Format)
local UIConfig = require(UI.UIConfig)
local CombatFx = require(UI.CombatFx)

local ZoneView = require(ReplicatedStorage:WaitForChild("MenuSystem"):WaitForChild("Menus"):WaitForChild("ZoneView"))

local ZonesMenu = {}

local MENU = "Zones"
local SIGN_DISTANCE = 150 -- studs the barrier sign renders from
local SIGN_SIZE = Vector2.new(22, 12) -- studs the sign is designed at (WorldUI.BarrierSign)
local SIGN_LIFT = 8 -- studs from the barrier's bottom to the sign's centre

local player = Players.LocalPlayer
local items: ScrollingFrame
local cards: { [string]: Frame } = {}
local pending = false

-- Tagged barriers and gates we manage, with their parts' original look.
type Saved = { Transparency: number, CanCollide: boolean }
type Face = { gui: SurfaceGui, panel: Frame, title: TextLabel, price: TextLabel, note: TextLabel, button: Frame }
type Blocker = {
	root: Instance,
	tag: string,
	parts: { [BasePart]: Saved },
	connections: { RBXScriptConnection },
	sign: { Face }?,
	signPart: BasePart?,
	hidden: boolean?, -- nil until first refreshed (no dissolve on join)
}
local blockers: { [Instance]: Blocker } = {}

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
	-- The row's zone viewport (ZoneView): dark until the zone is yours.
	local view = Roles.find(row, "ZoneRole", "View")
	if view then
		ZoneView.Set(view, { Zone = def.Id, ViewSilhouette = not owned(def.Id) })
	end
	if owned(def.Id) then
		Kit.paint(button, "Green")
		Interface.setText(button, "Teleport")
	elseif nextZone and nextZone.Id == def.Id then
		local short = (State.get("Clacks") or 0) < priceOf(def)
		Kit.paint(button, if short then "Sunset" else "Orange")
		Interface.setText(button, Format.number(priceOf(def)))
		-- Prices are one word: never let the kit's label wrap them.
		for _, name in { "Title", "TitleShadow" } do
			local title = button:FindFirstChild(name, true)
			if title and title:IsA("TextLabel") then
				title.TextWrapped = false
			end
		end
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

-- One Teleporter row: a copy of StarterGui.Templates.ZoneRow (ZoneRole:
-- Number, View (a ZoneView viewport), ZoneName, Info, Action).
local function makeRow(def: Zones.ZoneDef): Frame
	local row = Kit.template("ZoneRow") :: Frame
	row.Name = def.Id
	local number = Roles.find(row, "ZoneRole", "Number")
	if number then number.Text = tostring(def.Order) end
	local name = Roles.find(row, "ZoneRole", "ZoneName")
	if name then name.Text = Zones.title(def) end
	local info = Roles.find(row, "ZoneRole", "Info")
	if info then
		local studs = Zones.studCount(def.Id)
		info.Text = `x{Format.number(def.KeyMultiplier)} Clacks per key` .. (if studs > 0 then ` · {studs} zone studs` else "")
		info.TextColor3 = def.Color
	end
	local button = Roles.get(row, "ZoneRole", "Action") :: Frame
	button.Name = "Action"
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
-- Barrier signs (SurfaceGui on the barrier)
--------------------------------------------------------------------------

local playerGui: PlayerGui

-- The part the sign goes on: the one with the biggest face.
local function signPartOf(blocker: Blocker): BasePart?
	local best: BasePart?, bestArea = nil, 0
	for part in blocker.parts do
		if part.Parent then
			local size = part.Size
			local area = math.max(size.X * size.Y, size.Z * size.Y)
			if area > bestArea then
				best, bestArea = part, area
			end
		end
	end
	return best
end

local function makeFace(part: BasePart, face: Enum.NormalId, maxDistance: number): Face
	-- Front/Back faces span X, Left/Right faces span Z.
	local alongX = face == Enum.NormalId.Front or face == Enum.NormalId.Back
	local width = if alongX then part.Size.X else part.Size.Z
	local height = part.Size.Y
	local scale = math.min(1, width * 0.9 / SIGN_SIZE.X, height * 0.9 / SIGN_SIZE.Y)
	local lift = math.min(SIGN_LIFT, height / 2)

	-- A copy of StarterGui.WorldUI's BarrierSign, parented to PlayerGui
	-- (adorned to the part) so the button takes clicks.
	local gui = Roles.template(Roles.gui("WorldUI"), "BarrierSign") :: SurfaceGui
	gui.Name = "ZoneSign"
	gui.Adornee = part
	gui.Face = face
	gui.MaxDistance = maxDistance + Roles.distanceBonus -- from you, not the far-off camera
	local pixels = gui.PixelsPerStud
	local panel = Roles.get(gui, "SignRole", "Panel") :: Frame
	-- Lifted off the barrier's bottom, scaled down to fit a narrow barrier.
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0, (height - lift) * pixels)
	local fit = panel:FindFirstChildOfClass("UIScale")
	if fit then
		fit.Scale = scale
	end
	local title = Roles.get(gui, "SignRole", "Title") :: TextLabel
	local price = Roles.get(gui, "SignRole", "Amount") :: TextLabel
	local icon = Roles.find(gui, "SignRole", "Icon")
	if icon and icon:IsA("ImageLabel") then
		Kit.setIcon(icon, UIConfig.Icons.Clacks)
	end
	local button = Roles.get(gui, "SignRole", "Buy") :: Frame
	local note = Roles.get(gui, "SignRole", "Note") :: TextLabel
	note.Visible = false

	gui.Parent = playerGui
	return { gui = gui, panel = panel, title = title, price = price, note = note, button = button }
end

local function clearSign(blocker: Blocker)
	if blocker.sign then
		for _, face in blocker.sign do
			face.gui:Destroy()
		end
	end
	blocker.sign = nil
	blocker.signPart = nil
end

local function updateSign(blocker: Blocker)
	local zone = Tags.zoneOf(blocker.root)
	local def = if zone then Zones.ById[zone] else nil
	local part = signPartOf(blocker)
	if blocker.tag ~= Tags.ZoneBarrier or not def or owned(def.Id) or not part
		or not Tags.read(blocker.root, Tags.Attr.ShowPrompt, Config.ZoneUnlock.BarrierSigns) then
		clearSign(blocker)
		return
	end

	-- (Re)build when the part changed (streamed in, resized, replaced).
	if not blocker.sign or blocker.signPart ~= part then
		clearSign(blocker)
		local maxDistance = Tags.read(blocker.root, Tags.Attr.PromptDistance, SIGN_DISTANCE)
		local alongX = part.Size.Z <= part.Size.X
		local faces = if alongX then { Enum.NormalId.Front, Enum.NormalId.Back } else { Enum.NormalId.Left, Enum.NormalId.Right }
		local sign: { Face } = {}
		for _, normal in faces do
			local face = makeFace(part, normal, maxDistance)
			local zoneDef = def
			Interface.bindButton(face.button, function()
				onZone(zoneDef)
			end)
			table.insert(sign, face)
		end
		blocker.sign = sign
		blocker.signPart = part
	end

	local nextZone = Zones.nextFor(State.get("UnlockedWorlds") or {})
	local isNext = nextZone ~= nil and nextZone.Id == def.Id
	local price = priceOf(def)
	local clacks = State.get("Clacks") or 0
	local short = clacks < price
	for _, face in blocker.sign :: { Face } do
		face.title.Text = Tags.string(blocker.root, Tags.Attr.Title) or Zones.title(def)
		face.title.TextColor3 = def.Color
		local outline = face.panel:FindFirstChild("Outline")
		if outline and outline:IsA("UIStroke") then
			outline.Color = def.Color
		end
		face.price.Text = Format.number(price)
		-- Red price and "NEED 297K" when short, so it's clear what's missing.
		face.price.TextColor3 = if short and isNext then Color3.fromRGB(255, 120, 120) else Color3.new(1, 1, 1)
		face.button.Visible = isNext
		face.note.Visible = not isNext
		if isNext then
			Kit.paint(face.button, if short then "Sunset" else "Green")
			Interface.setText(face.button, if short then `NEED {Format.number(price - clacks)}` else "BUY")
		else
			local previous = previousOf(def)
			face.note.Text = `Unlock {if previous then previous.Name else "the previous zone"} first`
		end
	end
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
		end
	end

	local open = def ~= nil and owned(def.Id)
	local hide = open and (barrier or Tags.read(blocker.root, Tags.Attr.HideWhenOwned, false))
	-- Just bought (not on join): dissolve instead of vanishing.
	local dissolve = hide and blocker.hidden == false
	blocker.hidden = hide
	for part, saved in blocker.parts do
		if part.Parent then
			part.CanCollide = if hide then false else saved.CanCollide
			if dissolve then
				local color = if def then def.Color else Color3.new(1, 1, 1)
				part.Transparency = math.min(saved.Transparency, 0.2)
				TweenService:Create(part, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
				CombatFx.sparks(part, 40, color)
				CombatFx.shockwave(part.Position, color, math.min(part.Size.X, 30) * 0.4)
			else
				part.Transparency = if hide then 1 else saved.Transparency
			end
		else
			blocker.parts[part] = nil
		end
	end
	if dissolve then
		local first = next(blocker.parts)
		CombatFx.sound("Explode", if first then first.Position else nil, 0.7, 0.8)
	end
	updateSign(blocker)
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
	clearSign(blocker)
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
	playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	local window = Interface.window(MENU)
	-- The rows go in the window's list: ZoneRole = "List", else its Items.
	local list = Roles.find(window, "ZoneRole", "List")
	while not list do
		for _, d in window:GetDescendants() do
			if d.Name == "Items" and d:IsA("ScrollingFrame") then
				list = d
				break
			end
		end
		if not list then task.wait(0.2) end
	end
	items = list :: ScrollingFrame

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
			for _, blocker in blockers do
				updateSign(blocker)
			end
			if Interface.isOpen(MENU) then refreshCards() end
		end
	end)

	watchTag(Tags.ZoneBarrier)
	watchTag(Tags.ZoneGate)
end

-- For the unlock prompt (Controllers/ZonePrompt): the same buy / teleport
-- as a Teleporter row, and the price after discounts.
ZonesMenu.buy = onZone
ZonesMenu.priceOf = priceOf

return ZonesMenu
