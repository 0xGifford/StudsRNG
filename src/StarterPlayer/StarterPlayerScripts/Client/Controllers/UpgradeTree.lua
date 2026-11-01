--[[

UpgradeTree
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/UpgradeTree

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The full-screen upgrade tree (HUD's Upgrades button; StarterGui.Upgrades,
-- a MenuSystem menu, pieces found by UpgradeRole, see
-- tools/ui/screens/Upgrades.luau). A honeycomb of Shared/Upgrades nodes:
--   drag (mouse or finger) to pan, scroll wheel or pinch to zoom,
--   click / tap a node to buy its next level (a press that turned into a
--   drag never buys), hover or press to see its details below.
--
-- Nodes and lines are copies of the UpgradeNode / UpgradeLine templates,
-- placed from each upgrade's Q, R. Colours (attributes on the Root): gold =
-- maxed, green = affordable, blue = available, grey = locked (buy a
-- neighbour first).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Upgrades = require(Shared.Upgrades)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Roles = require(UI.Roles)
local Format = require(UI.Format)
local UIConfig = require(UI.UIConfig)
local Juice = require(UI.Juice)

type UpgradeDef = Upgrades.UpgradeDef

local UpgradeTree = {}

local player = Players.LocalPlayer

local MENU = "Upgrades"
local SINK_ACTION = "UpgradeTreeSinkWheel"
local SQRT3 = math.sqrt(3)

local CELL = 64 -- layout radius: distance between neighbours is CELL * sqrt(3) (World's Spacing)
local MIN_ZOOM, MAX_ZOOM = 0.45, 1.8
local DRAG_THRESHOLD = 10 -- pixels before a press counts as a drag
local MARGIN = 140

-- Defaults; the Root's <Name>Color attributes override them.
local COLORS: { [string]: Color3 } = {
	Maxed = Color3.fromRGB(255, 196, 64),
	Affordable = Color3.fromRGB(90, 220, 110),
	Available = Color3.fromRGB(70, 140, 255),
	Locked = Color3.fromRGB(70, 70, 82),
	LineOn = Color3.fromRGB(255, 220, 110),
	LineAvailable = Color3.fromRGB(200, 200, 215),
	LineOff = Color3.fromRGB(55, 55, 65),
	Error = Color3.fromRGB(255, 120, 120),
}

type Node = {
	def: UpgradeDef,
	frame: GuiObject,
	fills: { GuiObject },
	shines: { { object: GuiObject, transparency: number } },
	icon: TextLabel,
	level: TextLabel,
	cost: TextLabel,
	scale: UIScale,
}

type Line = { frame: GuiObject, from: string, to: string }

local gui: ScreenGui? = nil
local world: GuiObject
local worldScale: UIScale
local viewport: GuiObject
local clacksLabel: TextLabel
local infoTitle: TextLabel
local infoBody: TextLabel
local infoCost: TextLabel

local nodes: { [string]: Node } = {}
local lines: { Line } = {}
local bounds = { minX = 0, maxX = 0, minY = 0, maxY = 0 }

local pan = Vector2.zero
local zoom = 1
local selected: string? = nil
local buying = false

-- Drag state: one pointer at a time (first finger / left mouse).
local dragInput: InputObject? = nil
local dragStart = Vector2.zero
local panStart = Vector2.zero
local dragMoved = false
local pressedNode: string? = nil
local pinchZoom = 1

--------------------------------------------------------------------------
-- Geometry
--------------------------------------------------------------------------

local function worldPosition(def: UpgradeDef): Vector2
	return Vector2.new(CELL * SQRT3 * (def.Q + def.R / 2), CELL * 1.5 * def.R)
end

local function viewportSize(): Vector2
	return viewport.AbsoluteSize
end

local function clampPan(value: Vector2): Vector2
	local size = viewportSize()
	local half = size / 2
	local minX = MARGIN - half.X - bounds.maxX * zoom
	local maxX = size.X - MARGIN - half.X - bounds.minX * zoom
	local minY = MARGIN - half.Y - bounds.maxY * zoom
	local maxY = size.Y - MARGIN - half.Y - bounds.minY * zoom
	return Vector2.new(math.clamp(value.X, math.min(minX, maxX), math.max(minX, maxX)),
		math.clamp(value.Y, math.min(minY, maxY), math.max(minY, maxY)))
end

local function applyView()
	pan = clampPan(pan)
	world.Position = UDim2.new(0.5, pan.X, 0.5, pan.Y)
	worldScale.Scale = zoom
end

-- Zoom keeping the world point under `focus` (viewport pixels) still.
local function zoomAt(newZoom: number, focus: Vector2)
	newZoom = math.clamp(newZoom, MIN_ZOOM, MAX_ZOOM)
	local center = viewport.AbsolutePosition + viewportSize() / 2
	local offset = focus - center
	pan = offset - (offset - pan) * (newZoom / zoom)
	zoom = newZoom
	applyView()
end

--------------------------------------------------------------------------
-- State → visuals
--------------------------------------------------------------------------

local function levels(): { [string]: number }
	return State.get("Upgrades") or {}
end

local function nodeState(def: UpgradeDef): string
	local current = levels()
	local level = Upgrades.level(current, def.Id)
	if level >= def.MaxLevel then return "Maxed" end
	if not Upgrades.isUnlocked(def, current) then return "Locked" end
	if (State.get("Clacks") or 0) >= Upgrades.cost(def, level) then return "Affordable" end
	return "Available"
end

local function requiresText(def: UpgradeDef): string
	local names = {}
	for _, id in def.Requires do
		local required = Upgrades.ById[id]
		table.insert(names, if required then required.Name else id)
	end
	return table.concat(names, ", ")
end

local function renderInfo()
	local id = selected
	local def = if id then Upgrades.ById[id] else nil
	if not def then
		infoTitle.Text = "Upgrades"
		infoBody.Text = "Spend Clacks on permanent upgrades. They're kept when you rebirth!"
		infoCost.Text = "Drag to look around · Scroll or pinch to zoom · Tap a node to buy"
		infoCost.TextColor3 = Color3.new(1, 1, 1)
		return
	end
	local level = Upgrades.level(levels(), def.Id)
	infoTitle.Text = `{def.Icon} {def.Name}`
	local effect = if def.Format == "Unlock"
		then def.Description
		else `{def.Description}\nLevel {level}/{def.MaxLevel}: {Upgrades.effectText(def, level)}`
			.. (if level < def.MaxLevel then ` → {Upgrades.effectText(def, level + 1)}` else "")
	infoBody.Text = effect

	local state = nodeState(def)
	if state == "Maxed" then
		infoCost.Text = if def.Format == "Unlock" then "Unlocked!" else "MAXED"
		infoCost.TextColor3 = COLORS.Maxed
	elseif state == "Locked" then
		infoCost.Text = `Requires {requiresText(def)}`
		infoCost.TextColor3 = COLORS.Error
	else
		local cost = Upgrades.cost(def, level)
		infoCost.Text = `Cost: {Format.number(cost)} Clacks`
		infoCost.TextColor3 = if state == "Affordable" then COLORS.Affordable else COLORS.Error
	end
end

local function renderNodes()
	local current = levels()
	for id, node in nodes do
		local def = node.def
		local state = nodeState(def)
		local color = COLORS[state]
		for _, rect in node.fills do
			rect.BackgroundColor3 = color
		end
		for _, shine in node.shines do
			shine.object.BackgroundTransparency = if state == "Locked" then 1 - (1 - shine.transparency) * 0.35 else shine.transparency
		end
		node.icon.TextTransparency = if state == "Locked" then 0.5 else 0
		local level = Upgrades.level(current, id)
		node.level.Text = if def.Format == "Unlock" then (if level > 0 then "✓" else "") else `{level}/{def.MaxLevel}`
		if state == "Maxed" or state == "Locked" then
			node.cost.Visible = false
		else
			node.cost.Visible = true
			node.cost.Text = Format.number(Upgrades.cost(def, level))
			node.cost.TextColor3 = if state == "Affordable" then COLORS.Affordable else COLORS.Error
		end
	end

	for _, line in lines do
		local childLevel = Upgrades.level(current, line.to)
		local parentLevel = Upgrades.level(current, line.from)
		line.frame.BackgroundColor3 = if childLevel > 0 then COLORS.LineOn
			elseif parentLevel > 0 then COLORS.LineAvailable
			else COLORS.LineOff
	end

	clacksLabel.Text = `{Format.number(State.get("Clacks") or 0)} Clacks`
	renderInfo()
end

--------------------------------------------------------------------------
-- Buying
--------------------------------------------------------------------------

local function pop(node: Node)
	node.scale.Scale = 1.22
	TweenService:Create(node.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function buy(id: string)
	local node = nodes[id]
	if not node or buying then return end
	selected = id
	local def = node.def
	local state = nodeState(def)
	if state == "Maxed" then
		renderInfo()
		Interface.toast("Already maxed!")
		return
	elseif state == "Locked" then
		renderInfo()
		Interface.toast(`Buy {requiresText(def)} first`, COLORS.Error)
		return
	elseif state == "Available" then
		renderInfo()
		local cost = Upgrades.cost(def, Upgrades.level(levels(), id))
		Interface.toast(`You need {Format.number(cost)} Clacks`, COLORS.Error)
		return
	end

	buying = true
	local response = State.buyUpgrade(id)
	buying = false
	if response.Ok then
		pop(node)
		Interface.play("Click", 1.25)
		Juice.confetti(24, node.frame.AbsolutePosition + node.frame.AbsoluteSize / 2)
		if (response.Level or 0) >= def.MaxLevel then
			Juice.shake(0.4, 0.3)
		end
		Interface.toast(`{def.Name} → {Upgrades.effectText(def, response.Level or 0)}`, COLORS.Affordable)
	else
		Interface.toastError(response)
	end
	renderNodes()
end

--------------------------------------------------------------------------
-- Building (copies of StarterGui.Upgrades' templates)
--------------------------------------------------------------------------

local function beginPress(input: InputObject, nodeId: string?)
	local t = input.UserInputType
	if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
	if dragInput then
		-- The same press reaching the node after the background: it's a node press.
		if input == dragInput and nodeId and not pressedNode then
			pressedNode = nodeId
			selected = nodeId
			renderInfo()
		end
		return -- a second finger: the pinch handles it
	end
	dragInput = input
	dragStart = Vector2.new(input.Position.X, input.Position.Y)
	panStart = pan
	dragMoved = false
	pressedNode = nodeId
	if nodeId then
		selected = nodeId
		renderInfo()
	end
end

local function named(root: Instance, name: string): { GuiObject }
	local found = {}
	for _, d in root:GetDescendants() do
		if d.Name == name and d:IsA("GuiObject") then
			table.insert(found, d)
		end
	end
	return found
end

local function buildNode(screen: ScreenGui, def: UpgradeDef, parent: Instance): Node
	local position = worldPosition(def)
	local frame = Roles.template(screen, "UpgradeNode") :: GuiObject
	frame.Name = def.Id
	frame.Position = UDim2.fromOffset(position.X, position.Y)

	local scale = frame:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = frame
	end
	local shines = {}
	for _, shine in named(frame, "Shine") do
		table.insert(shines, { object = shine, transparency = shine.BackgroundTransparency })
	end
	local icon = frame:FindFirstChild("Icon", true) :: TextLabel
	icon.Text = def.Icon
	local button = frame:FindFirstChildWhichIsA("GuiButton", true) :: GuiButton
	local nodeScale = scale :: UIScale

	button.InputBegan:Connect(function(input)
		beginPress(input, def.Id)
	end)
	button.MouseEnter:Connect(function()
		if dragInput then return end
		Interface.play("Hover", 1.1)
		selected = def.Id
		renderInfo()
		TweenService:Create(nodeScale, Interface.FAST, { Scale = 1.08 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(nodeScale, Interface.FAST, { Scale = 1 }):Play()
	end)
	frame.Parent = parent

	return {
		def = def,
		frame = frame,
		fills = named(frame, "Fill"),
		shines = shines,
		icon = icon,
		level = frame:FindFirstChild("Level", true) :: TextLabel,
		cost = frame:FindFirstChild("Cost", true) :: TextLabel,
		scale = nodeScale,
	}
end

local function buildLine(screen: ScreenGui, fromDef: UpgradeDef, toDef: UpgradeDef, parent: Instance): Line
	local a = worldPosition(fromDef)
	local b = worldPosition(toDef)
	local mid = (a + b) / 2
	local delta = b - a
	local frame = Roles.template(screen, "UpgradeLine") :: GuiObject
	frame.Name = `{fromDef.Id}->{toDef.Id}`
	frame.Position = UDim2.fromOffset(mid.X, mid.Y)
	frame.Size = UDim2.fromOffset(delta.Magnitude, frame.Size.Y.Offset)
	frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	frame.Parent = parent
	return { frame = frame, from = fromDef.Id, to = toDef.Id }
end

local function bind(): boolean
	if gui then return true end
	local screen = Roles.gui(MENU)
	local function part(name: string): any
		return Roles.get(screen, "UpgradeRole", name)
	end
	if not Roles.find(screen, "UpgradeRole", "Nodes") then
		warn('[UpgradeTree] StarterGui.Upgrades has no UpgradeRole pieces; run tools/ui/migrate.luau on your place')
		return false
	end

	-- State colours from the Root's attributes.
	for _, d in screen:GetDescendants() do
		if d:GetAttribute("MenuPanel") == true then
			for name in COLORS do
				local value = d:GetAttribute(`{name}Color`)
				if typeof(value) == "Color3" then
					COLORS[name] = value
				end
			end
			break
		end
	end

	viewport = part("Viewport")
	world = part("World")
	local spacing = world:GetAttribute("Spacing")
	if typeof(spacing) == "number" and spacing > 0 then
		CELL = spacing
	end
	local scale = world:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = world
	end
	worldScale = scale :: UIScale
	clacksLabel = part("Clacks")
	infoTitle = part("InfoTitle")
	infoBody = part("InfoBody")
	infoCost = part("InfoCost")

	local lineLayer = part("Lines")
	local nodeLayer = part("Nodes")
	for _, def in Upgrades.List do
		local position = worldPosition(def)
		bounds.minX = math.min(bounds.minX, position.X)
		bounds.maxX = math.max(bounds.maxX, position.X)
		bounds.minY = math.min(bounds.minY, position.Y)
		bounds.maxY = math.max(bounds.maxY, position.Y)
		nodes[def.Id] = buildNode(screen, def, nodeLayer)
		for _, requiredId in def.Requires do
			local required = Upgrades.ById[requiredId]
			if required then
				table.insert(lines, buildLine(screen, required, def, lineLayer))
			end
		end
	end

	viewport.InputBegan:Connect(function(input)
		beginPress(input, nil)
	end)
	gui = screen
	return true
end

--------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------

local function bindInput()
	UserInputService.InputChanged:Connect(function(input)
		if not UpgradeTree.isOpen() then return end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseWheel then
			local mouse = UserInputService:GetMouseLocation()
			zoomAt(zoom * (1 + 0.12 * input.Position.Z), Vector2.new(mouse.X, mouse.Y))
			return
		end
		local active = dragInput
		if not active then return end
		local matches = (t == Enum.UserInputType.MouseMovement and active.UserInputType == Enum.UserInputType.MouseButton1)
			or (t == Enum.UserInputType.Touch and input == active)
		if not matches then return end
		local current = Vector2.new(input.Position.X, input.Position.Y)
		local delta = current - dragStart
		if not dragMoved and delta.Magnitude >= DRAG_THRESHOLD then
			dragMoved = true
		end
		if dragMoved then
			pan = panStart + delta
			applyView()
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		local active = dragInput
		if not active then return end
		local t = input.UserInputType
		local ended = (t == Enum.UserInputType.MouseButton1 and active.UserInputType == Enum.UserInputType.MouseButton1)
			or (t == Enum.UserInputType.Touch and input == active)
		if not ended then return end
		local nodeId = pressedNode
		local wasDrag = dragMoved
		dragInput = nil
		pressedNode = nil
		dragMoved = false
		if nodeId and not wasDrag and UpgradeTree.isOpen() then
			task.spawn(buy, nodeId)
		end
	end)

	UserInputService.TouchPinch:Connect(function(positions, scale, _velocity, state)
		if not UpgradeTree.isOpen() then return end
		if state == Enum.UserInputState.Begin then
			pinchZoom = zoom
			-- A pinch is never a tap on a node.
			dragMoved = true
		end
		local focus = viewport.AbsolutePosition + viewportSize() / 2
		if #positions >= 2 then
			local a, b = positions[1], positions[2]
			focus = Vector2.new((a.X + b.X) / 2, (a.Y + b.Y) / 2)
		end
		zoomAt(pinchZoom * scale, focus)
	end)
end

--------------------------------------------------------------------------
-- Open / close
--------------------------------------------------------------------------

local controlsDisabled = false

-- Roblox's default PlayerModule, if this place has one (never waited on:
-- places with custom player scripts don't, and open/close must not yield).
local function findControls(): any
	local scripts = player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not (module and module:IsA("ModuleScript")) then return nil end
	local ok, controls = pcall(function()
		return (require(module) :: any):GetControls()
	end)
	return if ok then controls else nil
end

local function setControls(enabled: boolean)
	-- Stop the character walking off while the tree is open.
	local controls = findControls()
	if controls then
		if enabled and controlsDisabled then
			controls:Enable()
			controlsDisabled = false
		elseif not enabled then
			controls:Disable()
			controlsDisabled = true
		end
	end
end

function UpgradeTree.isOpen(): boolean
	return Interface.isOpen(MENU)
end

local function onOpened()
	selected = nil
	zoom = if viewportSize().X < 900 then 0.7 else 1
	pan = Vector2.zero
	applyView()
	renderNodes()
	worldScale.Scale = zoom * 0.85
	TweenService:Create(worldScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = zoom }):Play()
	setControls(false)
	-- The wheel zooms the tree, not the camera behind it.
	ContextActionService:BindActionAtPriority(SINK_ACTION, function()
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.MouseWheel)
end

local function onClosed()
	dragInput = nil
	pressedNode = nil
	setControls(true)
	ContextActionService:UnbindAction(SINK_ACTION)
end

function UpgradeTree.open()
	Interface.open(MENU)
end

function UpgradeTree.close()
	Interface.close(MENU)
end

function UpgradeTree.start()
	Interface.setup()
	if not bind() then return end
	Interface.MenuOpened:Connect(function(name)
		if name == MENU then
			onOpened()
		end
	end)
	Interface.MenuClosed:Connect(function(name)
		if name == MENU then
			onClosed()
		end
	end)
	bindInput()

	State.Changed:Connect(function(field)
		if not UpgradeTree.isOpen() then return end
		if field == "Upgrades" or field == "Clacks" or field == "Stats" then
			renderNodes()
		end
	end)

	if not UIConfig.Features.Upgrades then
		warn("[UpgradeTree] Upgrades feature is disabled in UIConfig")
	end
end

return UpgradeTree
