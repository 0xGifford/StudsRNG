--[[

ZonePrompt
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/ZonePrompt

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Unlocking zones by walking up to them: within
-- Config.ZoneUnlock.PromptDistance studs of a locked zone's barrier (or of
-- the zone itself when it has no ZoneBarrier), a small panel slides up at
-- the bottom of the screen (StarterGui.ZonePrompt, ZonePromptRole pieces):
-- the zone in 3D, its name, its price and UNLOCK. The next zone in line can
-- be bought right there (the same purchase as the Teleporter's row,
-- ZonesMenu.buy; the barrier then dissolves in front of you); a zone
-- further on says which one to unlock first. Walk away and it slides down.

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
local ZonesMenu = require(Controllers.ZonesMenu)
local Intro = require(Controllers.Intro)
local Interface = require(UI.Interface)
local Roles = require(UI.Roles)
local Format = require(UI.Format)
local Kit = require(UI.Kit)
local Juice = require(UI.Juice)

local Menus = ReplicatedStorage:WaitForChild("MenuSystem"):WaitForChild("Menus")
local ZoneView = require(Menus:WaitForChild("ZoneView"))

local ZonePrompt = {}

local ROLE = "ZonePromptRole"
local CHECK = 0.2 -- seconds between distance checks
local SLIDE = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local player = Players.LocalPlayer

local panel: GuiObject
local shownPosition: UDim2
local hiddenPosition: UDim2
local parts: { [string]: GuiObject } = {}
local shownZone: string? = nil
local slide: Tween? = nil

--------------------------------------------------------------------------
-- How far you are from each locked zone
--------------------------------------------------------------------------

-- Distance from a point to a part's box (0 inside it).
local function distanceToPart(part: BasePart, point: Vector3): number
	local here = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	local outside = Vector3.new(
		math.max(math.abs(here.X) - half.X, 0),
		math.max(math.abs(here.Y) - half.Y, 0),
		math.max(math.abs(here.Z) - half.Z, 0)
	)
	return outside.Magnitude
end

local function distanceToBox(cframe: CFrame, size: Vector3, point: Vector3): number
	local here = cframe:PointToObjectSpace(point)
	local half = size / 2
	return Vector3.new(
		math.max(math.abs(here.X) - half.X, 0),
		math.max(math.abs(here.Y) - half.Y, 0),
		math.max(math.abs(here.Z) - half.Z, 0)
	).Magnitude
end

-- The barrier parts of each zone (refreshed as barriers stream in / out).
local barriers: { [string]: { BasePart } } = {}
local barriersDirty = true

local function rebuildBarriers()
	barriersDirty = false
	table.clear(barriers)
	for _, root in CollectionService:GetTagged(Tags.ZoneBarrier) do
		local id = Tags.zoneOf(root)
		if id then
			local list = barriers[id] or {}
			barriers[id] = list
			if root:IsA("BasePart") then
				table.insert(list, root)
			end
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(list, d)
				end
			end
		end
	end
end

local function distanceTo(def: Zones.ZoneDef, point: Vector3): number
	local list = barriers[def.Id]
	if list and #list > 0 then
		local best = math.huge
		for _, part in list do
			if part.Parent then
				best = math.min(best, distanceToPart(part, point))
			end
		end
		return best
	end
	-- No barrier: the zone itself.
	local zone = Tags.forZone(Tags.Zone, def.Id)[1]
	if not zone then return math.huge end
	local cframe, size = Tags.zoneBox(zone)
	return if cframe and size then distanceToBox(cframe, size, point) else math.huge
end

-- The nearest locked zone within reach, if any.
local function nearestLocked(point: Vector3): Zones.ZoneDef?
	local unlocked = State.get("UnlockedWorlds") or {}
	local reach = Config.ZoneUnlock.PromptDistance
	local best: Zones.ZoneDef? = nil
	local bestDistance = reach
	for _, def in Zones.List do
		if not unlocked[def.Id] then
			local distance = distanceTo(def, point)
			if distance <= bestDistance then
				best, bestDistance = def, distance
			end
		end
	end
	return best
end

--------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------

local function setText(name: string, value: string)
	local label = parts[name]
	if label and label:IsA("TextLabel") then
		label.Text = value
	end
end

local function fill(def: Zones.ZoneDef)
	local unlocked = State.get("UnlockedWorlds") or {}
	local nextZone = Zones.nextFor(unlocked)
	local isNext = nextZone ~= nil and nextZone.Id == def.Id
	local price = ZonesMenu.priceOf(def)
	local short = (State.get("Clacks") or 0) < price

	setText("Title", Zones.title(def))
	local studs = Zones.studCount(def.Id)
	setText("Info", `x{Format.number(def.KeyMultiplier)} Clacks per key` .. (if studs > 0 then ` · {studs} new studs` else ""))
	setText("Price", Format.number(price))
	local title = parts.Title
	if title and title:IsA("TextLabel") then
		title.TextColor3 = def.Color
	end

	local view = parts.View
	if view then
		ZoneView.Set(view, { Zone = def.Id, ViewSilhouette = true })
	end
	local buy = parts.Buy
	local note = parts.Note
	if buy then
		buy.Visible = isNext
		if isNext then
			Kit.paint(buy, if short then "Sunset" else "Green")
		end
	end
	if note then
		note.Visible = not isNext
		local previous = Zones.List[def.Order - 1]
		setText("Note", `Unlock {if previous then previous.Name else "the zone before"} first`)
	end
end

local function show(def: Zones.ZoneDef)
	local first = shownZone == nil
	shownZone = def.Id
	fill(def)
	if not first then return end
	panel.Visible = true
	panel.Position = hiddenPosition
	if slide then slide:Cancel() end
	local tween = TweenService:Create(panel, SLIDE, { Position = shownPosition })
	slide = tween
	tween:Play()
	Interface.play("Click", 1.1)
end

local function hide()
	if shownZone == nil then return end
	shownZone = nil
	if slide then slide:Cancel() end
	local tween = TweenService:Create(panel, SLIDE_OUT, { Position = hiddenPosition })
	slide = tween
	tween:Play()
	tween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and shownZone == nil then
			panel.Visible = false
		end
	end)
end

local function check()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or Intro.isPlaying() or Interface.isOpen() then
		hide()
		return
	end
	if barriersDirty then
		rebuildBarriers()
	end
	local def = nearestLocked(root.Position)
	if def then
		show(def)
	else
		hide()
	end
end

--------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------

function ZonePrompt.start()
	Interface.setup()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("ZonePrompt", 15)
	local found = gui and Roles.find(gui, ROLE, "Panel")
	if not (gui and found) then
		warn("[ZonePrompt] StarterGui.ZonePrompt is missing (run tools/sync_scripts.luau on your place); no unlock prompt")
		return
	end
	panel = found
	for _, name in { "View", "Title", "Info", "Price", "Buy", "Note" } do
		local found = Roles.find(gui, ROLE, name)
		if found then
			parts[name] = found
		end
	end
	shownPosition = panel.Position
	local offset = panel:GetAttribute("HiddenOffset")
	local drop = if typeof(offset) == "UDim2" then offset else UDim2.fromScale(0, 0.35)
	hiddenPosition = shownPosition + drop
	panel.Visible = false
	panel.Position = hiddenPosition

	local buy = parts.Buy
	if buy then
		Interface.bindButton(buy, function()
			local def = if shownZone then Zones.ById[shownZone] else nil
			if not def then return end
			local before = State.get("UnlockedWorlds") or {}
			local had = before[def.Id] == true
			ZonesMenu.buy(def)
			local after = State.get("UnlockedWorlds") or {}
			if not had and after[def.Id] then
				Juice.pop(panel, 1.15)
				Juice.confetti(40, panel.AbsolutePosition + panel.AbsoluteSize / 2)
			end
		end)
	end

	for _, signal in {
		CollectionService:GetInstanceAddedSignal(Tags.ZoneBarrier),
		CollectionService:GetInstanceRemovedSignal(Tags.ZoneBarrier),
	} do
		signal:Connect(function()
			barriersDirty = true
		end)
	end
	State.Changed:Connect(function(field)
		if (field == "Clacks" or field == "UnlockedWorlds" or field == "Stats") and shownZone then
			local def = Zones.ById[shownZone]
			if def then
				fill(def)
			end
		end
	end)

	local sinceRebuild = 0
	while true do
		task.wait(CHECK)
		sinceRebuild += CHECK
		-- Barrier parts stream in and out without retagging: re-read now and then.
		if sinceRebuild >= 5 then
			sinceRebuild = 0
			barriersDirty = true
		end
		check()
	end
end

return ZonePrompt
