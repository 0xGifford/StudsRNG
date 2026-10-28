--[[

UpgradeTree
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/UpgradeTree

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The full-screen upgrade tree (HUD's Upgrades button). A honeycomb of
-- Shared/Upgrades nodes:
--   drag (mouse or finger) to pan, scroll wheel or pinch to zoom,
--   click / tap a node to buy its next level (a press that turned into a
--   drag never buys), hover or press to see its details below.
--
-- Nodes are hexagons made of three rotated rectangles, so no image assets
-- are needed. Colours: gold = maxed, green = affordable, blue = available,
-- grey = locked (buy a neighbour first).

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
local Kit = require(UI.Kit)
local Format = require(UI.Format)
local UIConfig = require(UI.UIConfig)

type UpgradeDef = Upgrades.UpgradeDef

local UpgradeTree = {}

local MENU = "Upgrades"
local SINK_ACTION = "UpgradeTreeSinkWheel"
local SQRT3 = math.sqrt(3)

local CELL = 64 -- layout radius: distance between neighbours is CELL * sqrt(3)
local RADIUS = 56 -- drawn hex radius
local BORDER = 5
local MIN_ZOOM, MAX_ZOOM = 0.45, 1.8
local DRAG_THRESHOLD = 10 -- pixels before a press counts as a drag
local MARGIN = 140

local COLORS: { [string]: Color3 } = {
	Maxed = Color3.fromRGB(255, 196, 64),
	Affordable = Color3.fromRGB(90, 220, 110),
	Available = Color3.fromRGB(70, 140, 255),
	Locked = Color3.fromRGB(70, 70, 82),
	Border = Color3.fromRGB(25, 25, 25),
	LineOn = Color3.fromRGB(255, 220, 110),
	LineAvailable = Color3.fromRGB(200, 200, 215),
	LineOff = Color3.fromRGB(55, 55, 65),
	Background = Color3.fromRGB(22, 18, 34),
}

local player = Players.LocalPlayer

type Node = {
	def: UpgradeDef,
	frame: Frame,
	fills: { Frame },
	shines: { Frame },
	icon: TextLabel,
	level: TextLabel,
	cost: TextLabel,
	scale: UIScale,
}

type Line = { frame: Frame, from: string, to: string }

local gui: ScreenGui? = nil
local world: Frame
local worldScale: UIScale
local viewport: Frame
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

-- A pointy-top hexagon as three rectangles (0°, 60°, -60°). Returns the rects.
local function hexagon(parent: GuiObject, radius: number, color: Color3, zIndex: number, name: string): { Frame }
	local rects: { Frame } = {}
	for _, rotation in { 0, 60, -60 } do
		local rect = Instance.new("Frame")
		rect.Name = name
		rect.BorderSizePixel = 0
		rect.AnchorPoint = Vector2.new(0.5, 0.5)
		rect.Position = UDim2.fromScale(0.5, 0.5)
		rect.Size = UDim2.fromOffset(SQRT3 * radius, radius)
		rect.Rotation = rotation
		rect.BackgroundColor3 = color
		rect.ZIndex = zIndex
		rect.Parent = parent
		table.insert(rects, rect)
	end
	return rects
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
		infoCost.TextColor3 = Color3.fromRGB(255, 120, 120)
	else
		local cost = Upgrades.cost(def, level)
		infoCost.Text = `Cost: {Format.number(cost)} Clacks`
		infoCost.TextColor3 = if state == "Affordable" then COLORS.Affordable else Color3.fromRGB(255, 120, 120)
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
		for _, rect in node.shines do
			rect.BackgroundTransparency = if state == "Locked" then 0.9 else 0.72
		end
		node.icon.TextTransparency = if state == "Locked" then 0.5 else 0
		local level = Upgrades.level(current, id)
		node.level.Text = if def.Format == "Unlock" then (if level > 0 then "✓" else "") else `{level}/{def.MaxLevel}`
		if state == "Maxed" or state == "Locked" then
			node.cost.Visible = false
		else
			node.cost.Visible = true
			node.cost.Text = Format.number(Upgrades.cost(def, level))
			node.cost.TextColor3 = if state == "Affordable" then COLORS.Affordable else Color3.fromRGB(255, 140, 140)
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
		Interface.toast(`Buy {requiresText(def)} first`, Color3.fromRGB(255, 110, 110))
		return
	elseif state == "Available" then
		renderInfo()
		local cost = Upgrades.cost(def, Upgrades.level(levels(), id))
		Interface.toast(`You need {Format.number(cost)} Clacks`, Color3.fromRGB(255, 110, 110))
		return
	end

	buying = true
	local response = State.buyUpgrade(id)
	buying = false
	if response.Ok then
		pop(node)
		Interface.play("Click", 1.25)
		Interface.toast(`{def.Name} → {Upgrades.effectText(def, response.Level or 0)}`, COLORS.Affordable)
	else
		Interface.toastError(response)
	end
	renderNodes()
end

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

local function textLabel(text: string, size: UDim2, position: UDim2, zIndex: number): TextLabel
	local label = Kit.label(text)
	label.Size = size
	label.Position = position
	label.ZIndex = zIndex
	return label
end

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

local function buildNode(def: UpgradeDef, parent: Frame): Node
	local position = worldPosition(def)
	local frame = Instance.new("Frame")
	frame.Name = def.Id
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset(position.X, position.Y)
	frame.Size = UDim2.fromOffset(RADIUS * 2, RADIUS * 2)
	frame.ZIndex = 5
	frame.Parent = parent

	local scale = Instance.new("UIScale")
	scale.Parent = frame

	hexagon(frame, RADIUS + BORDER, COLORS.Border, 5, "Border")
	local fills = hexagon(frame, RADIUS, COLORS.Locked, 6, "Fill")
	-- A lighter, smaller hex nudged up reads as a bevel.
	local shineHolder = Instance.new("Frame")
	shineHolder.Name = "Shine"
	shineHolder.BackgroundTransparency = 1
	shineHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	shineHolder.Position = UDim2.new(0.5, 0, 0.5, -RADIUS * 0.12)
	shineHolder.Size = UDim2.fromScale(1, 1)
	shineHolder.ZIndex = 7
	shineHolder.Parent = frame
	local shines = hexagon(shineHolder, RADIUS * 0.72, Color3.new(1, 1, 1), 7, "Shine")
	for _, rect in shines do
		rect.BackgroundTransparency = 0.72
	end

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.42)
	icon.Size = UDim2.fromScale(0.55, 0.55)
	icon.TextScaled = true
	icon.Font = Enum.Font.GothamBold
	icon.Text = def.Icon
	icon.ZIndex = 9
	icon.Parent = frame

	local level = textLabel("", UDim2.fromScale(0.62, 0.22), UDim2.fromScale(0.5, 0.78), 9)
	level.Name = "Level"
	level.Parent = frame

	local cost = textLabel("", UDim2.fromScale(1.1, 0.26), UDim2.new(0.5, 0, 1, 14), 9)
	cost.Name = "Cost"
	cost.Parent = frame

	local button = Instance.new("TextButton")
	button.Name = "Button"
	button.Text = ""
	button.BackgroundTransparency = 1
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = UDim2.fromScale(0.95, 0.95)
	button.ZIndex = 10
	button.AutoButtonColor = false
	button.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = button

	button.InputBegan:Connect(function(input)
		beginPress(input, def.Id)
	end)
	button.MouseEnter:Connect(function()
		if dragInput then return end
		Interface.play("Hover", 1.1)
		selected = def.Id
		renderInfo()
		TweenService:Create(scale, Interface.FAST, { Scale = 1.08 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, Interface.FAST, { Scale = 1 }):Play()
	end)

	return { def = def, frame = frame, fills = fills, shines = shines, icon = icon, level = level, cost = cost, scale = scale }
end

local function buildLine(fromDef: UpgradeDef, toDef: UpgradeDef, parent: Frame): Line
	local a = worldPosition(fromDef)
	local b = worldPosition(toDef)
	local mid = (a + b) / 2
	local delta = b - a
	local frame = Instance.new("Frame")
	frame.Name = `{fromDef.Id}->{toDef.Id}`
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset(mid.X, mid.Y)
	frame.Size = UDim2.fromOffset(delta.Magnitude, 12)
	frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	frame.BackgroundColor3 = COLORS.LineOff
	frame.ZIndex = 2
	frame.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.Border
	stroke.Thickness = 3
	stroke.Parent = frame
	return { frame = frame, from = fromDef.Id, to = toDef.Id }
end

local function makeTopBar(root: Frame)
	local bar = Instance.new("Frame")
	bar.Name = "Top"
	bar.BackgroundColor3 = Color3.new(0, 0, 0)
	bar.BackgroundTransparency = 0.45
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(1, 0, 0.11, 0)
	bar.ZIndex = 20
	bar.Parent = root

	local title = textLabel("Upgrade Tree", UDim2.fromScale(0.4, 0.6), UDim2.fromScale(0.5, 0.5), 21)
	title.Parent = bar

	local clacks = Kit.label("0 Clacks")
	local hudAmount = Interface.HUD:FindFirstChild("Labels")
	hudAmount = hudAmount and hudAmount:FindFirstChild("Amounts")
	hudAmount = hudAmount and hudAmount:FindFirstChild("Clacks")
	hudAmount = hudAmount and hudAmount:FindFirstChild("Amount")
	if hudAmount and hudAmount:IsA("TextLabel") then
		clacks = hudAmount:Clone()
	end
	clacks.Name = "Clacks"
	clacks.AnchorPoint = Vector2.new(0, 0.5)
	clacks.Position = UDim2.fromScale(0.02, 0.5)
	clacks.Size = UDim2.fromScale(0.3, 0.55)
	clacks.TextXAlignment = Enum.TextXAlignment.Left
	clacks.ZIndex = 21
	clacks.Parent = bar
	clacksLabel = clacks

	-- The kit's red X, borrowed from a menu window.
	local exitSource = Interface.Canva:FindFirstChild("Store")
	exitSource = exitSource and exitSource:FindFirstChild("Top")
	exitSource = exitSource and exitSource:FindFirstChild("Exit")
	local exit: Frame
	if exitSource and exitSource:IsA("Frame") then
		exit = exitSource:Clone()
	else
		exit = Kit.button("Sunset", "X")
	end
	exit.Name = "Exit"
	exit.AnchorPoint = Vector2.new(1, 0.5)
	exit.Position = UDim2.fromScale(0.985, 0.5)
	exit.Size = UDim2.fromScale(0.75, 0.75)
	for _, child in exit:GetDescendants() do
		if child:IsA("GuiObject") then
			child.ZIndex += 21
		end
	end
	exit.ZIndex = 21
	exit.Parent = bar
	if not exit:FindFirstChildOfClass("UIAspectRatioConstraint") then
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.Parent = exit
	end
	Interface.bindButton(exit, function()
		Interface.close(MENU)
	end)
end

local function makeInfoPanel(root: Frame)
	local panel = Instance.new("Frame")
	panel.Name = "Info"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.fromScale(0.5, 0.97)
	panel.Size = UDim2.fromScale(0.6, 0.2)
	panel.BackgroundColor3 = Color3.new(0, 0, 0)
	panel.BackgroundTransparency = 0.4
	panel.ZIndex = 20
	panel.Parent = root
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.7
	stroke.Thickness = 2
	stroke.Parent = panel
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 4.6
	ratio.Parent = panel

	infoTitle = textLabel("", UDim2.fromScale(0.94, 0.26), UDim2.fromScale(0.5, 0.18), 21)
	infoTitle.Parent = panel

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.53)
	body.Size = UDim2.fromScale(0.94, 0.38)
	body.TextScaled = true
	body.TextWrapped = true
	body.Font = Enum.Font.GothamMedium
	body.TextColor3 = Color3.new(1, 1, 1)
	body.TextStrokeTransparency = 0.5
	body.ZIndex = 21
	body.Parent = panel
	infoBody = body

	infoCost = textLabel("", UDim2.fromScale(0.94, 0.2), UDim2.fromScale(0.5, 0.86), 21)
	infoCost.Parent = panel
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "UpgradeTree"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 8
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Enabled = false

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = COLORS.Background
	root.BorderSizePixel = 0
	root.Active = true
	root.Parent = screen

	local studs = Instance.new("ImageLabel")
	studs.Name = "Studs"
	studs.BackgroundTransparency = 1
	studs.Size = UDim2.fromScale(1, 1)
	studs.Image = "rbxassetid://18878365966"
	studs.ScaleType = Enum.ScaleType.Tile
	studs.TileSize = UDim2.fromOffset(96, 96)
	studs.ImageTransparency = 0.93
	studs.ZIndex = 1
	studs.Parent = root

	viewport = Instance.new("Frame")
	viewport.Name = "Viewport"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.ClipsDescendants = true
	viewport.Active = true
	viewport.ZIndex = 2
	viewport.Parent = root

	world = Instance.new("Frame")
	world.Name = "World"
	world.BackgroundTransparency = 1
	world.AnchorPoint = Vector2.new(0.5, 0.5)
	world.Size = UDim2.new()
	world.Position = UDim2.fromScale(0.5, 0.5)
	world.ZIndex = 2
	world.Parent = viewport
	worldScale = Instance.new("UIScale")
	worldScale.Parent = world

	local lineLayer = Instance.new("Frame")
	lineLayer.Name = "Lines"
	lineLayer.Size = UDim2.new()
	lineLayer.BackgroundTransparency = 1
	lineLayer.ZIndex = 2
	lineLayer.Parent = world
	local nodeLayer = Instance.new("Frame")
	nodeLayer.Name = "Nodes"
	nodeLayer.Size = UDim2.new()
	nodeLayer.BackgroundTransparency = 1
	nodeLayer.ZIndex = 5
	nodeLayer.Parent = world

	for _, def in Upgrades.List do
		local position = worldPosition(def)
		bounds.minX = math.min(bounds.minX, position.X)
		bounds.maxX = math.max(bounds.maxX, position.X)
		bounds.minY = math.min(bounds.minY, position.Y)
		bounds.maxY = math.max(bounds.maxY, position.Y)
		nodes[def.Id] = buildNode(def, nodeLayer)
		for _, requiredId in def.Requires do
			local required = Upgrades.ById[requiredId]
			if required then
				table.insert(lines, buildLine(required, def, lineLayer))
			end
		end
	end

	makeTopBar(root)
	makeInfoPanel(root)

	viewport.InputBegan:Connect(function(input)
		beginPress(input, nil)
	end)

	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
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

local function setControls(enabled: boolean)
	-- Stop the character walking off while the tree is open.
	local ok, controls = pcall(function()
		local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any
		return playerModule:GetControls()
	end)
	if ok and controls then
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
	local screen = gui
	return screen ~= nil and screen.Enabled
end

function UpgradeTree.open()
	if not gui then build() end
	local screen = gui :: ScreenGui
	if screen.Enabled then return end
	screen.Enabled = true
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

function UpgradeTree.close()
	local screen = gui
	if not screen or not screen.Enabled then return end
	screen.Enabled = false
	dragInput = nil
	pressedNode = nil
	setControls(true)
	ContextActionService:UnbindAction(SINK_ACTION)
end

function UpgradeTree.start()
	Interface.setup()
	Interface.registerMenu(MENU, {
		open = UpgradeTree.open,
		close = UpgradeTree.close,
		isOpen = UpgradeTree.isOpen,
	})
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
