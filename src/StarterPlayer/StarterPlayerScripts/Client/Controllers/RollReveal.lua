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
--   * in the middle of the screen a vertical reel scrolls down: studs, each
--     with its tilted "1 / X" odds and name and a glow, and between them the
--     green "2X" clover (your luck) and, while a boost or event runs, BONUS.
--     The centre one is big, its neighbours a little smaller, then tiny;
--     white dashes mark the centre
--   * the reel eases out onto the result, which pops and glows
--   * a manual roll's result then flies up to rest small at the top centre,
--     and the next roll zooms it back to the middle and spins on from it.
--     On Auto the reel stays in the middle between rolls
-- HIDE (Auto only): no dim, the HUD stays, and the same reel spins small at
-- the top centre, with AUTO / HIDE tucked under it. Faster rolling = faster
-- reels. The server decided the results before the reel starts: it's pure
-- theatre.
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

local player = Players.LocalPlayer
local busy = false
local auto = false
local hidden = false -- HIDE: the small top display instead of the reel (Auto only)

local gui: ScreenGui
local dim: GuiObject
local dimTransparency = 0.45
local stage: GuiObject -- holds the reels: screen centre, or small at the top
local stageScale: UIScale
local pose = "Centre" -- where the stage is: "Centre" or "Top"
local controls: GuiObject
local controlsLayout: { anchor: Vector2, position: UDim2, size: UDim2, hiddenSize: UDim2 }
local autoButton: GuiButton
local autoPosition: UDim2
local hideButton: GuiButton
local onColor = Color3.fromRGB(120, 255, 140)
local offColor = Color3.fromRGB(255, 120, 120)
local designHeight = 100 -- the reel cell height the templates are drawn for
local cinematic = false

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
	stageScale = stage:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", stage)
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)

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

	-- The old HIDE display (before build 4): no longer used.
	local oldMini = Roles.find(gui, "RevealRole", "Mini")
	if oldMini and oldMini:IsA("GuiObject") then
		oldMini.Visible = false
	end

	local templates = gui:FindFirstChild("Templates")
	local height = templates and templates:GetAttribute("DesignHeight")
	if typeof(height) == "number" and height > 0 then designHeight = height end
end

-- AUTO (where it was designed, alone or not), and HIDE while Auto is on. In
-- HIDE mode they sit under the small reel at the top.
local function layoutControls()
	hideButton.Visible = auto
	autoButton.Position = autoPosition
	if auto and hidden then
		controls.AnchorPoint = Vector2.new(0.5, 0)
		controls.Position = UDim2.new(0.5, 0, 0.15, math.clamp(gui.AbsoluteSize.Y * 0.3, 90, 330) * 0.42 * 0.75)
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
	setCinematic((busy or auto) and not hideMode)
	controls.Visible = busy or auto
	layoutControls()
end

--------------------------------------------------------------------------
-- Stage poses: big at the screen centre, small at the top centre
--------------------------------------------------------------------------

local TOP_Y = 0.15 -- the resting / HIDE reel's centre, as a share of the screen height
local TOP_SCALE = 0.42
local REST_TIME = 3 -- seconds a manual roll's result rests at the top

local function moveTo(name: string, duration: number)
	pose = name
	local position = if name == "Top" then UDim2.fromScale(0.5, TOP_Y) else UDim2.fromScale(0.5, 0.5)
	local scale = if name == "Top" then TOP_SCALE else 1
	if duration <= 0 then
		stage.Position = position
		stageScale.Scale = scale
		return
	end
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(stage, info, { Position = position }):Play()
	TweenService:Create(stageScale, info, { Scale = scale }):Play()
end

-- Runs fn(u) every frame for duration seconds (u from 0 to 1).
local function animate(duration: number, fn: (number) -> ())
	local start = os.clock()
	while true do
		local u = math.clamp((os.clock() - start) / duration, 0, 1)
		fn(u)
		if u >= 1 then break end
		RunService.RenderStepped:Wait()
	end
end

--------------------------------------------------------------------------
-- Fading a piece (every transparency inside it, from its own base value)
--------------------------------------------------------------------------

type Fader = { items: { { object: Instance, property: string, base: number } }, last: number }

local function makeFader(root: Instance): Fader
	local items = {}
	local function add(object: Instance)
		if object:IsA("TextLabel") or object:IsA("TextButton") then
			table.insert(items, { object = object, property = "TextTransparency", base = object.TextTransparency })
		end
		if object:IsA("ImageLabel") or object:IsA("ViewportFrame") then
			table.insert(items, { object = object, property = "ImageTransparency", base = (object :: any).ImageTransparency })
		end
		if object:IsA("GuiObject") and not object:IsA("ViewportFrame") then
			table.insert(items, { object = object, property = "BackgroundTransparency", base = object.BackgroundTransparency })
		end
		if object:IsA("UIStroke") then
			table.insert(items, { object = object, property = "Transparency", base = object.Transparency })
		end
	end
	add(root)
	for _, d in root:GetDescendants() do
		add(d)
	end
	return { items = items, last = -1 }
end

local function setFade(fader: Fader, f: number)
	if math.abs(fader.last - f) < 0.01 then return end
	fader.last = f
	for _, item in fader.items do
		(item.object :: any)[item.property] = item.base + (1 - item.base) * f
	end
end

--------------------------------------------------------------------------
-- Reel
--------------------------------------------------------------------------

-- What a reel slot shows: a stud, or a filler that rides between them like
-- in Slime RNG ("2X": your luck; "BONUS": a boost or event is running).
type Entry = { kind: string, def: StudDef? }

type Slot = {
	frame: GuiObject, -- container, scaled with a UIScale
	scale: UIScale,
	stud: GuiObject, -- the ReelCell
	viewport: ViewportFrame,
	odds: TextLabel,
	name: TextLabel,
	luck: GuiObject,
	bonus: GuiObject,
	rays: GuiObject,
	fades: { [string]: Fader },
	index: number, -- which entry of the sequence it shows
}

type Reel = {
	holder: GuiObject,
	slots: { Slot },
	sequence: { Entry },
	result: RollResult,
	cellHeight: number,
	target: number, -- sequence index of the result
	tease: boolean, -- a rarer stud sits just past the result (near miss)
	creep: number, -- extra scroll towards the tease, added while drawing
}

local VISIBLE = 5 -- slots drawn per reel (centre ± 2)
local FILLER_CHANCE = 0.4

-- The reel showing (spinning, or its result resting), and its dashes.
local current: { reels: { Reel }, extras: { Instance } }? = nil
local lastResult: StudDef? = nil
local restToken = 0

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

local function rarityColor(def: StudDef): Color3
	return if def.Rarity == "Secret" then Color3.new(1, 1, 1) else Config.Rarities.Colors[def.Rarity] or Color3.new(1, 1, 1)
end

-- Any temporary luck / speed source running (the BONUS filler).
local function bonusActive(): boolean
	local stats = State.stats()
	if stats.ServerLuck > 1 then return true end
	local now = State.serverNow()
	for _, ends in State.get("BoostEnds") or {} do
		if typeof(ends) == "number" and ends > now then
			return true
		end
	end
	local eventId = ReplicatedStorage:GetAttribute("EventId")
	return typeof(eventId) == "string" and eventId ~= ""
end

local function luckText(): string
	return (string.gsub(string.format("%.1f", State.stats().Luck), "%.0$", "")) .. "X"
end

local function makeSlot(parent: Instance, cellHeight: number): Slot
	local frame = Instance.new("Frame")
	frame.Name = "Slot"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(cellHeight * 1.6, cellHeight)
	local scale = Instance.new("UIScale")
	scale.Parent = frame

	local rays = copy("Rays") :: GuiObject
	rays.Size = UDim2.fromOffset(cellHeight * 1.05, cellHeight * 1.05)
	rays.Position = UDim2.fromScale(0.5, 0.5)
	rays.ZIndex = 0
	rays.Parent = frame

	local stud = copy("ReelCell", cellHeight) :: GuiObject
	stud.Position = UDim2.fromScale(0.5, 0.5)
	stud.Parent = frame
	local luck = copy("LuckBadge", cellHeight) :: GuiObject
	luck.Position = UDim2.fromScale(0.5, 0.5)
	luck.Parent = frame
	local bonus = copy("BonusTag", cellHeight) :: GuiObject
	bonus.Position = UDim2.fromScale(0.5, 0.5)
	bonus.Parent = frame
	frame.Parent = parent

	return {
		frame = frame,
		scale = scale,
		stud = stud,
		viewport = viewportIn(stud),
		odds = child(stud, "Odds"),
		name = child(stud, "Name"),
		luck = luck,
		bonus = bonus,
		rays = rays,
		fades = { stud = makeFader(stud), luck = makeFader(luck), bonus = makeFader(bonus), rays = makeFader(rays) },
		index = 0,
	}
end

local function tintRays(rays: GuiObject, color: Color3)
	for _, d in rays:GetDescendants() do
		if d:IsA("Frame") then
			d.BackgroundColor3 = if d.Name == "Glow" then color else color:Lerp(Color3.new(1, 1, 1), 0.6)
		end
	end
end

local function showStud(slot: Slot, def: StudDef, variant: VariantDef)
	StudCell.setViewport(slot.viewport, def, variant)
	local color = rarityColor(def)
	slot.odds.Text = oddsText(def, variant)
	slot.odds.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
	slot.name.Text = Format.studName(def, variant)
	slot.name.TextColor3 = Color3.new(1, 1, 1)
	tintRays(slot.rays, color)
end

local function showEntry(slot: Slot, entry: Entry)
	slot.stud.Visible = entry.kind == "Stud"
	slot.rays.Visible = entry.kind == "Stud"
	slot.luck.Visible = entry.kind == "Luck"
	slot.bonus.Visible = entry.kind == "Bonus"
	if entry.kind == "Stud" and entry.def then
		showStud(slot, entry.def, Variants.ById.Normal)
	elseif entry.kind == "Luck" then
		local label = slot.luck:FindFirstChild("Text", true)
		if label and label:IsA("TextLabel") then
			label.Text = luckText()
		end
	end
end

local function makeReel(result: RollResult, offsetX: number, length: number, cellHeight: number): Reel
	local holder = copy("ReelHolder") :: GuiObject
	holder.Position = UDim2.fromOffset(offsetX, 0)
	holder.Size = UDim2.fromOffset(cellHeight * 1.6, cellHeight * VISIBLE)
	holder.Parent = stage

	local pool = spinPool()
	local bonus = bonusActive()
	local function filler(): Entry
		return { kind = if bonus and math.random() < 0.3 then "Bonus" else "Luck" }
	end
	local sequence: { Entry } = {}
	-- It starts on the last result (it zooms back in from the top).
	sequence[1] = { kind = "Stud", def = lastResult or randomStud(pool) }
	for i = 2, length - 1 do
		local previous = sequence[i - 1]
		sequence[i] = if previous.kind == "Stud" and math.random() < FILLER_CHANCE then filler() else { kind = "Stud", def = randomStud(pool) }
	end
	local landed = Studs.ById[result.Id]
	sequence[length] = { kind = "Stud", def = landed }

	-- Near miss: sometimes a much rarer stud sits right past the result.
	local tease = false
	local rarer = {}
	for _, def in pool do
		if def.OneIn >= landed.OneIn * 20 then
			table.insert(rarer, def)
		end
	end
	if #rarer > 0 and math.random() < UIConfig.Reveal.NearMissChance then
		sequence[length + 1] = { kind = "Stud", def = rarer[math.random(1, #rarer)] }
		tease = true
	else
		sequence[length + 1] = if math.random() < FILLER_CHANCE then filler() else { kind = "Stud", def = randomStud(pool) }
	end
	sequence[length + 2] = { kind = "Stud", def = randomStud(pool) }

	local slots: { Slot } = {}
	for _ = 1, VISIBLE do
		table.insert(slots, makeSlot(holder, cellHeight))
	end
	return { holder = holder, slots = slots, sequence = sequence, result = result, cellHeight = cellHeight, target = length, tease = tease, creep = 0 }
end

-- Where an entry sits `o` slots from the centre: the centre one big, its
-- neighbours a little smaller and close, the next ones tiny and faded.
local function placement(o: number): (number, number, number)
	local d = math.abs(o)
	local y = if d <= 1 then d * 0.78 else 0.78 + (d - 1) * 0.55
	local scale = if d <= 1 then 1 - 0.25 * d else math.max(0.3, 0.75 - 0.35 * (d - 1))
	local fade = if d <= 1 then 0 else math.clamp((d - 1) * 0.75, 0, 1)
	return math.sign(o) * y, scale, fade
end

-- p = how far the reel has scrolled (0 … target - 1). Entry k sits
-- (p - (k - 1)) slots from the centre: later entries come from above.
local function drawReel(reel: Reel, p: number)
	local base = math.floor(p) + 1
	local spin = os.clock() * 50
	for i, slot in reel.slots do
		local k = base + i - 3 -- base-2 … base+2
		local entry = reel.sequence[k]
		if not entry then
			slot.frame.Visible = false
			continue
		end
		slot.frame.Visible = true
		if slot.index ~= k then
			slot.index = k
			showEntry(slot, entry)
		end
		local o = p - (k - 1)
		local y, scale, fade = placement(o)
		slot.frame.Position = UDim2.new(0.5, 0, 0.5, y * reel.cellHeight)
		slot.scale.Scale = scale
		local part = if entry.kind == "Stud" then "stud" elseif entry.kind == "Luck" then "luck" else "bonus"
		setFade(slot.fades[part], fade)
		-- The glow: bright in the centre, softer on the neighbours.
		setFade(slot.fades.rays, math.clamp(0.15 + 0.45 * math.min(math.abs(o), 1) + fade, 0, 1))
		slot.rays.Rotation = spin
	end
end

--------------------------------------------------------------------------
-- Centre dashes
--------------------------------------------------------------------------

local function dashes(spread: number, cellHeight: number): { Instance }
	local made: { Instance } = {}
	local length = cellHeight * 0.28
	for _, side in { -1, 1 } do
		local dash = copy("ReelDash") :: GuiObject
		dash.Size = UDim2.fromOffset(length, math.max(3, cellHeight * 0.02))
		dash.Position = UDim2.fromOffset(side * (spread / 2 + cellHeight * 0.7 + length / 2), 0)
		if side > 0 then
			dash.Rotation += 180
		end
		dash.Parent = stage
		table.insert(made, dash)
	end
	return made
end

--------------------------------------------------------------------------
-- Landing
--------------------------------------------------------------------------

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

local function land(reel: Reel, quiet: boolean)
	local result = reel.result
	local def = Studs.ById[result.Id]
	local variant = Variants.ById[result.Variant]
	local color = rarityColor(def)
	local center: Slot? = nil
	for _, slot in reel.slots do
		if slot.index == reel.target then
			center = slot
		end
	end
	if not center then return end

	showStud(center, def, variant)
	if result.New then
		center.odds.Text = `NEW! {center.odds.Text}`
	end
	if not result.Kept then
		center.name.Text ..= if result.Reason == "Full" then " (FULL)" else " (DELETED)"
	end
	center.name.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.2)

	-- The result pops and glows; everything else gets out of the way.
	center.scale.Scale = 1.5
	TweenService:Create(center.scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.25 }):Play()
	setFade(center.fades.rays, 0)
	TweenService:Create(center.rays, TweenInfo.new(6, Enum.EasingStyle.Linear), { Rotation = center.rays.Rotation + 240 }):Play()
	for _, slot in reel.slots do
		if slot ~= center then
			slot.frame.Visible = false
		end
	end
	Interface.play("Click", 1.2)

	-- Rarer = louder (HIDE mode keeps it to the rarest).
	local rank = RollLogic.rarityRank(def.Rarity)
	local screenPoint = center.frame.AbsolutePosition + center.frame.AbsoluteSize / 2
	if not quiet and rank >= 3 then
		Juice.shake(0.15 * rank, 0.25 + 0.05 * rank)
	end
	if not quiet and rank >= 4 then
		Juice.confetti(10 * rank, screenPoint)
		Interface.play("Click", 1.5)
	end
	if rank >= 5 then
		if not quiet then
			Juice.flash(color, 0.35 + 0.08 * (rank - 5), 0.6)
			Juice.fov(6 + 3 * (rank - 5), 0.7)
		end
		Juice.banner(string.upper(def.Rarity) .. "!", Format.studName(def, variant), color, 1.2)
	end
end

--------------------------------------------------------------------------
-- The reveal
--------------------------------------------------------------------------

local function clearCurrent()
	restToken += 1
	local showing = current
	current = nil
	if not showing then return end
	for _, reel in showing.reels do
		reel.holder:Destroy()
	end
	for _, extra in showing.extras do
		extra:Destroy()
	end
end

-- A manual roll's result rests at the top for a while, then shrinks away
-- (unless another roll starts first).
local function scheduleFade()
	restToken += 1
	local token = restToken
	task.delay(REST_TIME, function()
		if token ~= restToken or busy or not current then return end
		local tween = TweenService:Create(stageScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
		tween:Play()
		tween.Completed:Wait()
		if token ~= restToken then return end
		clearCurrent()
		moveTo(pose, 0)
	end)
end

-- After a roll (or when Auto / HIDE change): the result goes where it
-- belongs. Auto (shown): stays big in the centre for the next roll. Else it
-- flies to the top to rest; without Auto it fades out after a while.
local function settle()
	if busy or not current then return end
	if auto and not hidden then
		if pose ~= "Centre" then moveTo("Centre", 0.25) end
		return
	end
	if pose ~= "Top" then
		moveTo("Top", 0.35)
	end
	if not auto then
		scheduleFade()
	end
end

function RollReveal.setHidden(value: boolean)
	hidden = value
	setPill(hideButton, if value then "HIDE - ON" else "HIDE - OFF", value)
	refreshCinematic()
	settle()
end

local function reveal(results: { RollResult }, quick: boolean)
	-- A Lucky Meter roll (Config.LuckyMeter): announce it before the reel.
	for _, result in results do
		if result.Lucky then
			local green = Color3.fromRGB(120, 255, 140)
			Juice.banner("🍀 LUCKY ROLL!", `x{Config.LuckyMeter.Luck} luck on this one`, green, 1.1)
			Juice.flash(green, 0.3, 0.45)
			Juice.confetti(45)
			Interface.play("Click", 1.6)
			break
		end
	end
	local hideMode = auto and hidden

	local speed = math.max(State.stats().RollSpeed, 1)
	local spinTime = (if quick then UIConfig.Reveal.AutoSpinTime else UIConfig.Reveal.SpinTime) / speed + 0.35
	local holdTime = (if quick then UIConfig.Reveal.AutoHoldTime else UIConfig.Reveal.HoldTime) / speed
	local length = if quick then 10 else 18

	local resting = current ~= nil
	clearCurrent()
	local cellHeight = math.clamp(gui.AbsoluteSize.Y * 0.3, 90, 330)
	local gap = cellHeight * 1.05
	local reels: { Reel } = {}
	for i, result in results do
		local offsetX = (i - (#results + 1) / 2) * gap
		table.insert(reels, makeReel(result, offsetX, length, cellHeight))
	end
	local extras = dashes(gap * (#results - 1), cellHeight)
	current = { reels = reels, extras = extras }
	for _, reel in reels do
		drawReel(reel, 0)
	end

	-- Into position: the reel zooms from its resting spot at the top to the
	-- centre (HIDE mode: it spins up there, small).
	stage.Visible = true
	if not resting then
		-- Nothing on screen yet: pop in where it belongs.
		local target = if hideMode then "Top" else "Centre"
		moveTo(target, 0)
		local full = stageScale.Scale
		stageScale.Scale = full * 0.5
		TweenService:Create(stageScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = full }):Play()
	elseif hideMode then
		moveTo("Top", if pose == "Top" then 0 else 0.2)
	elseif pose ~= "Centre" then
		moveTo("Centre", 0.22)
		task.wait(0.22)
	end

	-- Anything rarer than DramaOneIn crawls the last few slots.
	local dramatic = false
	for _, result in results do
		if result.OneIn >= UIConfig.Reveal.DramaOneIn and not quick then
			dramatic = true
		end
	end
	local total = spinTime + (if dramatic then 0.9 else 0)

	local start = os.clock()
	local lastTick = -1
	local connection = RunService.RenderStepped:Connect(function()
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
		Interface.play("Hover", 0.7)
		animate(0.7, function(u)
			for _, reel in reels do
				if reel.tease then
					reel.creep = 0.48 * math.sin(math.pi * u) ^ 0.7
				end
			end
		end)
		for _, reel in reels do
			if reel.tease then
				reel.creep = 0
				soClose(reel)
			end
		end
	end
	connection:Disconnect()

	for _, reel in reels do
		drawReel(reel, reel.target - 1)
		land(reel, hideMode)
		task.wait(if quick then 0.04 else 0.12)
	end
	lastResult = Studs.ById[results[#results].Id]

	task.wait(holdTime)
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
		clearCurrent()
		moveTo("Centre", 0)
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
	settle()
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
	settle()
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
	if not value then
		settle()
		return
	end

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
