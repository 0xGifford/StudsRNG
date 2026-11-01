--[[

RollReveal
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/RollReveal

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Owns the roll flow on the client: decides free vs paid, asks the server,
-- then plays the reveal. Also runs auto-roll (unlocked by the Auto Roll
-- upgrade) and turns server announcements into chat messages.
--
-- The reveal (Slime RNG style):
--   * the screen dims and the HUD steps aside; AUTO sits at the bottom
--     while rolling (and for as long as Auto is on), HIDE next to it only
--     while Auto is on
--   * above the player's head a vertical reel of studs scrolls down, each
--     with its "1 / X" odds above and name below; white dashes mark the
--     centre slot and a clover badge shows the player's luck
--   * the reel eases out onto the result, which pops with light rays
--   * the result's odds and name then float over the player in the world
-- HIDE (Auto only) hides the whole reveal: no dim, the HUD stays, and a small
-- roll display at the top of the screen flicks through studs and lands on
-- each result instead, with AUTO / HIDE tucked under it. Faster rolling =
-- faster reels. The server decided the results before the reel
-- starts: it's pure theatre.
--
-- Everything shown is StarterGui.RollReveal (RevealRole pieces and the
-- templates in its Templates frame, see tools/ui/screens/RollReveal.luau).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Studs = require(Shared.Studs)
local Variants = require(Shared.Variants)
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)
local RollLogic = require(Shared.Util.RollLogic)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local StudCell = require(UI.StudCell)
local Format = require(UI.Format)
local UIConfig = require(UI.UIConfig)
local Roles = require(UI.Roles)
local Juice = require(UI.Juice)

type RollResult = Types.RollResult
type StudDef = Types.StudDef
type VariantDef = Types.VariantDef

local RollReveal = {}

RollReveal.AutoChanged = Signal.new() :: Signal.Signal<boolean>
RollReveal.BusyChanged = Signal.new() :: Signal.Signal<boolean>
-- Fired when the player tries Auto without the upgrade.
RollReveal.AutoLocked = Signal.new() :: Signal.Signal<>

local VISIBLE = 5 -- cells drawn per reel (centre ± 2)

local player = Players.LocalPlayer
local busy = false
local auto = false
local hidden = false -- HIDE: the small top display instead of the reel (Auto only)

local gui: ScreenGui
local dim: GuiObject
local dimTransparency = 0.45
local stage: GuiObject -- follows the player's head on screen
local controls: GuiObject
local controlsLayout: { anchor: Vector2, position: UDim2, size: UDim2, hiddenSize: UDim2 }
local autoButton: GuiButton
local autoPosition: UDim2
local hideButton: GuiButton
local onColor = Color3.fromRGB(120, 255, 140)
local offColor = Color3.fromRGB(255, 120, 120)
local designHeight = 100 -- the reel cell height the templates are drawn for
local cinematic = false

-- The small roll display at the top (HIDE mode).
local mini: GuiObject
local miniStroke: UIStroke
local miniViewport: ViewportFrame
local miniOdds: TextLabel
local miniName: TextLabel
local miniScale: UIScale
local hudWasEnabled = true

--------------------------------------------------------------------------
-- StarterGui.RollReveal
--------------------------------------------------------------------------

local function child(root: Instance, name: string): any
	local found = root:FindFirstChild(name, true)
	assert(found, `{root:GetFullName()} needs a "{name}"`)
	return found
end

-- A copy of a template, offset sizes scaled from the design cell height.
local function copy(name: string, cellHeight: number?): any
	local object = Roles.template(gui, name)
	if cellHeight and object:IsA("GuiObject") then
		local k = cellHeight / designHeight
		local size = object.Size
		object.Size = UDim2.new(size.X.Scale, size.X.Offset * k, size.Y.Scale, size.Y.Offset * k)
	end
	return object
end

local function viewportIn(root: Instance): ViewportFrame
	local viewport = (if root:IsA("ViewportFrame") then root else root:FindFirstChildWhichIsA("ViewportFrame", true)) :: ViewportFrame
	assert(viewport, `{root:GetFullName()} needs a ViewportFrame`)
	return viewport
end

local function setPill(button: GuiButton, value: string, on: boolean)
	local label = button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = value
		label.TextColor3 = if on then onColor else offColor
	end
end

local function bindGui()
	gui = Roles.gui("RollReveal")
	local function part(name: string): any
		return Roles.get(gui, "RevealRole", name)
	end
	dim = part("Dim")
	local dimAttr = dim:GetAttribute("DimTransparency")
	if typeof(dimAttr) == "number" then dimTransparency = dimAttr end
	dim.BackgroundTransparency = 1
	stage = part("Stage")

	controls = part("Controls")
	controls.Visible = false
	local hiddenSize = controls:GetAttribute("HiddenSize")
	controlsLayout = {
		anchor = controls.AnchorPoint,
		position = controls.Position,
		size = controls.Size,
		hiddenSize = if typeof(hiddenSize) == "UDim2" then hiddenSize else UDim2.fromScale(0.26, 0.08),
	}
	local on, off = controls:GetAttribute("OnColor"), controls:GetAttribute("OffColor")
	if typeof(on) == "Color3" then onColor = on end
	if typeof(off) == "Color3" then offColor = off end
	autoButton = part("Auto")
	autoPosition = autoButton.Position
	hideButton = part("Hide")
	for _, button in { autoButton, hideButton } do
		button.MouseButton1Down:Connect(function()
			Interface.play("Click")
		end)
	end
	autoButton.Activated:Connect(function()
		RollReveal.setAuto(not auto)
	end)
	hideButton.Activated:Connect(function()
		RollReveal.setHidden(not hidden)
	end)
	hideButton.Visible = false
	setPill(autoButton, "AUTO - OFF", false)
	setPill(hideButton, "HIDE - OFF", false)

	mini = part("Mini")
	mini.Visible = false
	miniStroke = mini:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", mini)
	miniScale = mini:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", mini)
	miniViewport = viewportIn(mini)
	StudCell.setViewport(miniViewport, Studs.List[1], Variants.ById.Normal)
	miniOdds = child(mini, "Odds")
	miniName = child(mini, "Name")

	local templates = gui:FindFirstChild("Templates")
	local height = templates and templates:GetAttribute("DesignHeight")
	if typeof(height) == "number" and height > 0 then designHeight = height end
end

-- AUTO alone, or AUTO + HIDE while Auto is on. In HIDE mode they sit under
-- the small display at the top; otherwise where they were designed.
local function layoutControls()
	hideButton.Visible = auto
	autoButton.Position = if auto then autoPosition else UDim2.new(0.5, 0, autoPosition.Y.Scale, autoPosition.Y.Offset)
	if auto and hidden then
		controls.AnchorPoint = Vector2.new(0.5, 0)
		controls.Position = UDim2.new(0.5, 0, 0, mini.AbsolutePosition.Y + mini.AbsoluteSize.Y + 6)
		controls.Size = controlsLayout.hiddenSize
	else
		controls.AnchorPoint = controlsLayout.anchor
		controls.Position = controlsLayout.position
		controls.Size = controlsLayout.size
	end
end

--------------------------------------------------------------------------
-- Roll mode: dim + HUD out while rolling or on Auto
--------------------------------------------------------------------------

local function setCinematic(on: boolean)
	if cinematic == on then return end
	cinematic = on
	if on then
		hudWasEnabled = Interface.HUD.Enabled
		Interface.HUD.Enabled = false
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = dimTransparency }):Play()
	else
		Interface.HUD.Enabled = hudWasEnabled
		TweenService:Create(dim, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	end
end

-- HIDE mode keeps the HUD and the view clear; only the small display shows.
local function refreshCinematic()
	local hideMode = auto and hidden
	mini.Visible = hideMode
	setCinematic((busy or auto) and not hideMode)
	controls.Visible = busy or auto
	layoutControls()
end

function RollReveal.setHidden(value: boolean)
	hidden = value
	setPill(hideButton, if value then "HIDE - ON" else "HIDE - OFF", value)
	refreshCinematic()
end

--------------------------------------------------------------------------
-- Following the player's head
--------------------------------------------------------------------------

local function headScreenPosition(): Vector2
	local camera = workspace.CurrentCamera
	local character = player.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	local size = gui.AbsoluteSize
	if camera and head and head:IsA("BasePart") then
		local point, onScreen = camera:WorldToViewportPoint(head.Position + Vector3.new(0, 2, 0))
		if onScreen then
			return Vector2.new(point.X, point.Y)
		end
	end
	return Vector2.new(size.X / 2, size.Y * 0.45)
end

--------------------------------------------------------------------------
-- Reel
--------------------------------------------------------------------------

type Cell = {
	frame: GuiObject,
	viewport: ViewportFrame,
	odds: TextLabel,
	name: TextLabel,
	index: number, -- which entry of the sequence it shows
}

type Reel = {
	holder: GuiObject,
	cells: { Cell },
	sequence: { StudDef },
	result: RollResult,
	cellHeight: number,
	target: number, -- sequence index of the result
	tease: boolean, -- a rarer stud sits just past the result (near miss)
	creep: number, -- extra scroll towards the tease, added while drawing
}

local function spinPool(): { StudDef }
	local unlocked = State.get("UnlockedWorlds") or {}
	local pool = {}
	for _, def in Studs.List do
		if unlocked[def.World] then
			table.insert(pool, def)
		end
	end
	if #pool == 0 then
		pool = table.clone(Studs.List)
	end
	return pool
end

-- Common studs show up more in the reel, like they do in real rolls.
local function randomStud(pool: { StudDef }): StudDef
	local total = 0
	for _, def in pool do
		total += 1 / math.sqrt(def.OneIn)
	end
	local pick = math.random() * total
	for _, def in pool do
		pick -= 1 / math.sqrt(def.OneIn)
		if pick <= 0 then
			return def
		end
	end
	return pool[#pool]
end

local function oddsText(def: StudDef, variant: VariantDef): string
	return (string.gsub(Format.oneIn(def.OneIn * variant.OneIn), "^1 in ", "1 / "))
end

local function makeCell(parent: Instance, height: number): Cell
	local frame = copy("ReelCell", height) :: GuiObject
	if not frame:FindFirstChildOfClass("UIScale") then
		Instance.new("UIScale").Parent = frame
	end
	frame.Parent = parent
	return { frame = frame, viewport = viewportIn(frame), odds = child(frame, "Odds"), name = child(frame, "Name"), index = 0 }
end

local function showInCell(cell: Cell, def: StudDef, variant: VariantDef)
	StudCell.setViewport(cell.viewport, def, variant)
	cell.odds.Text = oddsText(def, variant)
	cell.name.Text = Format.studName(def, variant)
	cell.name.TextColor3 = Color3.new(1, 1, 1)
end

local function makeReel(result: RollResult, offsetX: number, length: number, cellHeight: number): Reel
	local cellWidth = cellHeight * 1.6
	local holder = copy("ReelHolder") :: GuiObject
	holder.Position = UDim2.fromOffset(offsetX, 0)
	holder.Size = UDim2.fromOffset(cellWidth, cellHeight * VISIBLE)
	holder.Parent = stage

	local pool = spinPool()
	local sequence: { StudDef } = {}
	for i = 1, length - 1 do
		sequence[i] = randomStud(pool)
	end
	local landed = Studs.ById[result.Id]
	sequence[length] = landed

	-- Near miss: sometimes a much rarer stud sits right past the result.
	local tease = false
	local rarer = {}
	for _, def in pool do
		if def.OneIn >= landed.OneIn * 20 then
			table.insert(rarer, def)
		end
	end
	if #rarer > 0 and math.random() < UIConfig.Reveal.NearMissChance then
		sequence[length + 1] = rarer[math.random(1, #rarer)]
		tease = true
	else
		sequence[length + 1] = randomStud(pool)
	end

	local cells: { Cell } = {}
	for _ = 1, VISIBLE do
		table.insert(cells, makeCell(holder, cellHeight))
	end
	return { holder = holder, cells = cells, sequence = sequence, result = result, cellHeight = cellHeight, target = length, tease = tease, creep = 0 }
end

-- p = how far the reel has scrolled (0 … target - 1). Entry k sits at
-- y = (p - (k - 1)) cells from the centre: later entries come from above.
local function drawReel(reel: Reel, p: number)
	local normal = Variants.ById.Normal
	local base = math.floor(p) + 1
	for slot, cell in reel.cells do
		local k = base + slot - 3 -- base-2 … base+2
		local def = reel.sequence[k]
		if not def then
			cell.frame.Visible = false
		else
			cell.frame.Visible = true
			if cell.index ~= k then
				cell.index = k
				showInCell(cell, def, normal)
			end
			local offset = p - (k - 1)
			local distance = math.abs(offset)
			cell.frame.Position = UDim2.new(0.5, 0, 0.5, offset * reel.cellHeight)
			local scale = cell.frame:FindFirstChildOfClass("UIScale")
			if scale then
				scale.Scale = math.max(0.45, 1 - distance * 0.28)
			end
			local fade = math.clamp(distance * 0.35, 0, 1)
			cell.viewport.ImageTransparency = fade
			cell.odds.TextTransparency = fade
			cell.name.TextTransparency = fade
			for _, label in { cell.odds, cell.name } do
				local stroke = label:FindFirstChildOfClass("UIStroke")
				if stroke then stroke.Transparency = fade end
			end
		end
	end
end

--------------------------------------------------------------------------
-- Centre decorations: dashes, clover badge, bonus pill, clover rain
--------------------------------------------------------------------------

local function decorations(width: number, cellHeight: number): { Instance }
	local made: { Instance } = {}
	for _, side in { -1, 1 } do
		local dash = copy("ReelDash", cellHeight) :: GuiObject
		dash.Position = UDim2.fromOffset(side * (width / 2 + cellHeight * 0.55), 0)
		if side > 0 then
			dash.Rotation += 180
		end
		dash.Parent = stage
		table.insert(made, dash)
	end

	local stats = State.stats()
	local badge = copy("LuckBadge", cellHeight) :: GuiObject
	badge.Position = UDim2.fromOffset(-(width / 2 + cellHeight * 0.05), 0)
	local luck = string.gsub(string.format("%.1f", stats.Luck), "%.0$", "")
	local badgeText = badge:FindFirstChild("Text", true)
	if badgeText and badgeText:IsA("TextLabel") then
		badgeText.Text = `{luck}X`
	end
	badge.Parent = stage
	table.insert(made, badge)
	Juice.pop(badge, 1.4)

	-- BONUS: any temporary luck/speed source running.
	local boosts = State.get("BoostEnds") or {}
	local now = State.serverNow()
	local bonus = stats.ServerLuck > 1
	for _, ends in boosts do
		if typeof(ends) == "number" and ends > now then
			bonus = true
		end
	end
	local eventId = ReplicatedStorage:GetAttribute("EventId")
	if typeof(eventId) == "string" and eventId ~= "" then
		bonus = true
	end
	if bonus then
		local tag = copy("BonusTag", cellHeight) :: GuiObject
		tag.Position = UDim2.fromOffset(-(width / 2 + cellHeight * 0.05), cellHeight * 0.62)
		tag.Parent = stage
		table.insert(made, tag)
	end
	return made
end

local function cloverRain(count: number)
	local size = gui.AbsoluteSize
	for _ = 1, count do
		local clover = copy("Clover") :: TextLabel
		local s = clover.Size.X.Offset * (0.75 + math.random() * 0.5)
		clover.Size = UDim2.fromOffset(s, s)
		clover.Position = UDim2.fromOffset(math.random() * size.X, -40)
		clover.Rotation = math.random(-30, 30)
		clover.Parent = gui
		local fall = TweenService:Create(clover, TweenInfo.new(math.random(110, 190) / 100, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromOffset(clover.Position.X.Offset + math.random(-80, 80), size.Y * (0.5 + math.random() * 0.4)),
			Rotation = math.random(-200, 200),
			TextTransparency = 1,
		})
		fall:Play()
		fall.Completed:Once(function()
			clover:Destroy()
		end)
	end
end

--------------------------------------------------------------------------
-- Landing
--------------------------------------------------------------------------

local function rays(parent: Instance, color: Color3, cellHeight: number): GuiObject
	local holder = copy("Rays", cellHeight) :: GuiObject
	for _, d in holder:GetDescendants() do
		if d:IsA("Frame") then
			d.BackgroundColor3 = if d.Name == "Glow" then color else color:Lerp(Color3.new(1, 1, 1), 0.6)
		end
	end
	holder.Parent = parent
	return holder
end

-- "SO CLOSE!" over the rarer stud the reel almost landed on.
local function soClose(reel: Reel)
	local label = copy("SoClose") :: TextLabel
	label.Position = UDim2.new(0.5, 0, 0.5, -reel.cellHeight * 1.05)
	label.Parent = reel.holder
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.9, function()
		TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	end)
end

local function land(reel: Reel)
	local result = reel.result
	local def = Studs.ById[result.Id]
	local variant = Variants.ById[result.Variant]
	local rarityColor = Config.Rarities.Colors[def.Rarity] or Color3.new(1, 1, 1)
	local center: Cell? = nil
	for _, cell in reel.cells do
		if cell.index == reel.target then
			center = cell
		end
	end
	if not center then return end

	showInCell(center, def, variant)
	center.name.TextColor3 = if def.Rarity == "Secret" then Color3.new(1, 1, 1) else rarityColor:Lerp(Color3.new(1, 1, 1), 0.2)
	if result.New then
		center.odds.Text = `NEW! {center.odds.Text}`
	end
	if not result.Kept then
		center.name.Text ..= if result.Reason == "Full" then " (FULL)" else " (DELETED)"
	end

	local burst = rays(center.frame, rarityColor, reel.cellHeight)
	local spin = TweenService:Create(burst, TweenInfo.new(4, Enum.EasingStyle.Linear), { Rotation = 180 })
	spin:Play()
	local scale = center.frame:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 1.9
		TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.35 }):Play()
	end
	-- The neighbours get out of the way.
	for _, cell in reel.cells do
		if cell ~= center then
			for _, item: any in { cell.viewport, cell.odds, cell.name } do
				local property = if item:IsA("ViewportFrame") then "ImageTransparency" else "TextTransparency"
				TweenService:Create(item, TweenInfo.new(0.2), { [property] = 1 }):Play()
			end
		end
	end
	Interface.play("Click", 1.2)

	-- Rarer = louder.
	local rank = RollLogic.rarityRank(def.Rarity)
	local screenPoint = center.frame.AbsolutePosition + center.frame.AbsoluteSize / 2
	if rank >= 3 then
		Juice.shake(0.15 * rank, 0.25 + 0.05 * rank)
	end
	if rank >= 4 then
		Juice.confetti(10 * rank, screenPoint)
		Interface.play("Click", 1.5)
	end
	if rank >= 5 then
		Juice.flash(rarityColor, 0.35 + 0.08 * (rank - 5), 0.6)
		Juice.fov(6 + 3 * (rank - 5), 0.7)
		Juice.banner(string.upper(def.Rarity) .. "!", Format.studName(def, variant), rarityColor, 1.2)
	end
end

--------------------------------------------------------------------------
-- World label: odds + name floating over the player after a roll
--------------------------------------------------------------------------

local worldLabels: { BillboardGui } = {}

local function floatResult(result: RollResult, order: number)
	local character = player.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not (head and head:IsA("BasePart")) then return end
	local def = Studs.ById[result.Id]
	local variant = Variants.ById[result.Variant]
	local color = Config.Rarities.Colors[def.Rarity] or Color3.new(1, 1, 1)

	local board = copy("ResultBoard") :: BillboardGui
	board.Name = "RollResult"
	board.Adornee = head
	board.StudsOffset += Vector3.new(0, 4.2 + (order - 1) * 2.4, 0)
	local odds = child(board, "Odds") :: TextLabel
	odds.Text = oddsText(def, variant)
	local name = child(board, "Name") :: TextLabel
	name.Text = Format.studName(def, variant)
	name.TextColor3 = if def.Rarity == "Secret" then Color3.new(1, 1, 1) else color
	board.Parent = gui.Parent -- PlayerGui: a BillboardGui inside a ScreenGui won't draw in 3D

	-- Older labels drift up out of the way.
	for _, other in worldLabels do
		if other.Parent then
			other.StudsOffset += Vector3.new(0, 2.4, 0)
		end
	end
	table.insert(worldLabels, board)

	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = odds
	local nameScale = scale:Clone()
	nameScale.Parent = name
	for _, s in { scale, nameScale } do
		TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	task.delay(2.6, function()
		for _, label in { odds, name } do
			TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			end
		end
		task.wait(0.55)
		board:Destroy()
		local index = table.find(worldLabels, board)
		if index then table.remove(worldLabels, index) end
	end)
end

--------------------------------------------------------------------------
-- The reveal
--------------------------------------------------------------------------

-- HIDE mode: the small top display flicks through studs, then lands on
-- each result in turn.
local function miniReveal(results: { RollResult }, quick: boolean)
	local speed = math.max(State.stats().RollSpeed, 1)
	local spinTime = (if quick then UIConfig.Reveal.AutoSpinTime else UIConfig.Reveal.SpinTime) / speed
	local holdTime = math.max(0.35, (if quick then UIConfig.Reveal.AutoHoldTime else UIConfig.Reveal.HoldTime) / speed)
	local pool = spinPool()
	local normal = Variants.ById.Normal

	for _, result in results do
		local def = Studs.ById[result.Id]
		local variant = Variants.ById[result.Variant]
		if not (def and variant) then continue end

		-- Flick: quick at first, slowing into the result.
		miniStroke.Color = Color3.new(1, 1, 1)
		miniStroke.Transparency = 0.5
		miniName.TextColor3 = Color3.new(1, 1, 1)
		local start = os.clock()
		local gap = 0.05
		while os.clock() - start < spinTime do
			local shown = randomStud(pool)
			StudCell.setViewport(miniViewport, shown, normal)
			miniOdds.Text = oddsText(shown, normal)
			miniName.Text = Format.studName(shown, normal)
			Interface.play("Hover", 1.1)
			task.wait(gap)
			gap = math.min(gap * 1.18, 0.2)
		end

		-- Land.
		local rarityColor = Config.Rarities.Colors[def.Rarity] or Color3.new(1, 1, 1)
		StudCell.setViewport(miniViewport, def, variant)
		miniOdds.Text = (if result.New then "NEW! " else "") .. oddsText(def, variant)
		miniName.Text = Format.studName(def, variant)
			.. (if result.Kept then "" elseif result.Reason == "Full" then " (FULL)" else " (DELETED)")
		miniName.TextColor3 = if def.Rarity == "Secret" then Color3.new(1, 1, 1) else rarityColor:Lerp(Color3.new(1, 1, 1), 0.2)
		miniStroke.Color = rarityColor
		miniStroke.Transparency = 0
		miniScale.Scale = 1.15
		TweenService:Create(miniScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		Interface.play("Click", 1.2)
		-- Only the rarest still get the big moment.
		local rank = RollLogic.rarityRank(def.Rarity)
		if rank >= 5 then
			Juice.banner(string.upper(def.Rarity) .. "!", Format.studName(def, variant), rarityColor, 1.2)
		end
		task.wait(holdTime)
	end
end

local function reveal(results: { RollResult }, quick: boolean)
	if auto and hidden then
		miniReveal(results, quick)
		return
	end

	local speed = math.max(State.stats().RollSpeed, 1)
	local spinTime = (if quick then UIConfig.Reveal.AutoSpinTime else UIConfig.Reveal.SpinTime) / speed + 0.35
	local holdTime = (if quick then UIConfig.Reveal.AutoHoldTime else UIConfig.Reveal.HoldTime) / speed
	local length = if quick then 10 else 18

	local viewportSize = gui.AbsoluteSize
	local cellHeight = math.clamp(viewportSize.Y * 0.11, 56, 130)
	local width = cellHeight * 1.6
	local gap = width * 1.15
	local reels: { Reel } = {}
	for i, result in results do
		local offsetX = (i - (#results + 1) / 2) * gap
		table.insert(reels, makeReel(result, offsetX, length, cellHeight))
	end
	local extras = decorations(width * #results + gap * (#results - 1) - width * (#results - 1) * 0.15, cellHeight)

	-- Lucky players get clover rain while the reel spins.
	local luck = State.stats().Luck
	if luck >= 2 and not quick then
		cloverRain(math.clamp(math.floor(luck * 4), 8, 40))
	end

	-- Anything rarer than DramaOneIn crawls the last few cells.
	local dramatic = false
	for _, result in results do
		if result.OneIn >= UIConfig.Reveal.DramaOneIn and not quick then
			dramatic = true
		end
	end
	local total = spinTime + (if dramatic then 0.9 else 0)

	stage.Visible = true
	local start = os.clock()
	local lastTick = -1
	local connection = RunService.RenderStepped:Connect(function()
		local head = headScreenPosition()
		stage.Position = UDim2.fromOffset(head.X, head.Y - cellHeight * 1.2)
		local t = math.clamp((os.clock() - start) / total, 0, 1)
		local eased = 1 - (1 - t) ^ (if dramatic then 5 else 4)
		for _, reel in reels do
			local p = eased * (reel.target - 1) + reel.creep
			drawReel(reel, p)
			local step = math.floor(p + 0.5)
			if step ~= lastTick then
				lastTick = step
				Interface.play("Hover", 0.9 + t * 0.6)
			end
		end
	end)

	while os.clock() - start < total do
		task.wait()
	end

	-- Near miss: creep towards the rarer stud past the result... and back.
	local teasing = false
	for _, reel in reels do
		if reel.tease and not quick then
			teasing = true
		end
	end
	if teasing then
		local creepStart = os.clock()
		local duration = 0.7
		Interface.play("Hover", 0.7)
		while os.clock() - creepStart < duration do
			local u = (os.clock() - creepStart) / duration
			for _, reel in reels do
				if reel.tease then
					reel.creep = 0.48 * math.sin(math.pi * u) ^ 0.7
				end
			end
			task.wait()
		end
		for _, reel in reels do
			if reel.tease then
				reel.creep = 0
				soClose(reel)
			end
		end
	end

	for _, reel in reels do
		drawReel(reel, reel.target - 1)
		land(reel)
		task.wait(if quick then 0.04 else 0.12)
	end

	task.wait(holdTime)
	connection:Disconnect()
	for i, reel in reels do
		floatResult(reel.result, i)
		reel.holder:Destroy()
	end
	for _, extra in extras do
		extra:Destroy()
	end
end

--------------------------------------------------------------------------
-- Rolling
--------------------------------------------------------------------------

local function setBusy(value: boolean)
	busy = value
	RollReveal.BusyChanged:Fire(value)
	refreshCinematic()
end

function RollReveal.isBusy(): boolean
	return busy
end

function RollReveal.isAuto(): boolean
	return auto
end

-- What the Roll button would do right now: "free", "paid" or nil (can't).
function RollReveal.nextRollKind(): string?
	if (State.get("FreeRolls") or 0) > 0 then
		return "free"
	end
	if (State.get("Clacks") or 0) >= State.stats().RollCost then
		return "paid"
	end
	return nil
end

local function play(results: { RollResult }, quick: boolean)
	local ok, err = pcall(reveal, results, quick)
	if not ok then
		warn("[RollReveal]", err)
		for _, child in stage:GetChildren() do
			child:Destroy()
		end
	end
end

-- Plays the reveal for results the server already granted (jackpot wheel).
function RollReveal.showResults(results: { RollResult })
	if #results == 0 then return end
	while busy do
		task.wait(0.1)
	end
	setBusy(true)
	play(results, false)
	setBusy(false)
end

-- One roll (free first, then paid). Returns true if a roll happened.
function RollReveal.roll(quick: boolean?): boolean
	if busy or not State.isReady() then return false end
	local kind = RollReveal.nextRollKind()
	if not kind then
		if not auto then
			Interface.toast(`Walk the keys for free rolls, or earn {Format.number(State.stats().RollCost)} Clacks`)
		end
		return false
	end

	setBusy(true)
	local response = State.roll(1, kind == "free")
	if not response.Ok then
		setBusy(false)
		Interface.toastError(response)
		return false
	end
	play(response.Results, quick == true)
	setBusy(false)
	return true
end

function RollReveal.setAuto(value: boolean)
	if auto == value then return end
	if value and not State.stats().AutoRoll then
		RollReveal.AutoLocked:Fire()
		return
	end
	auto = value
	setPill(autoButton, if value then "AUTO - ON" else "AUTO - OFF", value)
	RollReveal.AutoChanged:Fire(value)
	refreshCinematic()
	if not value then return end

	task.spawn(function()
		while auto do
			if not RollReveal.roll(true) then
				task.wait(0.5) -- nothing to spend yet; check again shortly
			else
				task.wait(State.stats().RollCooldown * 0.2)
			end
		end
	end)
end

--------------------------------------------------------------------------
-- Announcements → chat
--------------------------------------------------------------------------

local function postToRolls(message: string)
	-- Only ever the Rolls tab (Systems/ChatChannels), never the main chat.
	local channels = TextChatService:FindFirstChild("TextChannels")
	local rolls = channels and channels:FindFirstChild(Config.Announce.Channel)
	if rolls and rolls:IsA("TextChannel") then
		rolls:DisplaySystemMessage(message)
	end
end

local function announce(payload: any)
	if payload.Summon then
		postToRolls(`<font color="#FFCD3C"><b>{tostring(payload.Player)} summoned a {tostring(payload.Name)}!</b></font>`)
		return
	end
	local def = Studs.ById[payload.Id]
	local variant = Variants.ById[payload.Variant]
	if not def or not variant then return end
	-- Secret's colour is near-black: unreadable in chat.
	local rarityColor = if def.Rarity == "Secret" then Color3.new(1, 1, 1) else Config.Rarities.Colors[def.Rarity] or Color3.new(1, 1, 1)
	local message = string.format(
		if payload.Drop then '<font color="%s"><b>%s got a boss drop: %s (%s)!</b></font>' else '<font color="%s"><b>%s just rolled %s (%s)!</b></font>',
		Format.hex(rarityColor),
		tostring(payload.Player),
		Format.studName(def, variant),
		Format.oneIn(payload.OneIn)
	)
	postToRolls(message)
end

function RollReveal.start()
	Interface.setup()
	bindGui()
	-- Chat tabs on, so the Rolls channel is its own tab instead of mixing
	-- into the main chat window.
	local tabs = TextChatService:FindFirstChildOfClass("ChannelTabsConfiguration")
	if tabs then
		tabs.Enabled = true
	end
	State.Announced:Connect(announce)
end

return RollReveal
