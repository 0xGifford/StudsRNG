--[[

Enemies
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/Enemies

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The client side of Systems/Combat: a name, level and health bar over every
-- enemy, a "Fight" prompt (E, or tap / click the prompt) that sends your
-- equipped studs at it, damage numbers off the enemy you're fighting, and a
-- team bar (your studs' Health and Strength) with a RETREAT button while a
-- fight is on. The server decides everything; this only shows it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Kit = require(UI.Kit)
local Format = require(UI.Format)

local Enemies = {}

local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local HP_GREEN = Color3.fromRGB(90, 230, 100)
local HP_RED = Color3.fromRGB(255, 80, 80)

local player = Players.LocalPlayer
local playerGui: PlayerGui

type Tracked = { gui: BillboardGui, fill: Frame, amount: TextLabel, prompt: ProximityPrompt, last: number, connections: { RBXScriptConnection } }
local tracked: { [Model]: Tracked } = {}

local teamGui: ScreenGui
local teamFill: Frame
local teamText: TextLabel
local strengthText: TextLabel

local function label(parent: Instance, text: string, color: Color3, size: UDim2, position: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Size = size
	l.Position = position
	l.FontFace = FONT
	l.TextScaled = true
	l.TextWrapped = false
	l.TextColor3 = color
	l.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(15, 15, 20)
	stroke.Parent = l
	l.Parent = parent
	return l
end

local function bar(parent: Instance, size: UDim2, position: UDim2): (Frame, Frame)
	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 0.5)
	back.Size = size
	back.Position = position
	back.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	back.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(10, 10, 14)
	stroke.Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = HP_GREEN
	fill.BorderSizePixel = 0
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	fill.Parent = back
	back.Parent = parent
	return back, fill
end

local function hpColor(share: number): Color3
	return HP_RED:Lerp(HP_GREEN, math.clamp(share, 0, 1))
end

--------------------------------------------------------------------------
-- Enemies in the world
--------------------------------------------------------------------------

local function fighting(model: Model): boolean
	return player:GetAttribute("FightTarget") == model:GetAttribute("EnemyId")
end

-- "-123" floating up off the enemy when your studs land a hit.
local function damagePopup(model: Model, amount: number)
	local body = model.PrimaryPart
	if not body then return end
	local pop = Instance.new("BillboardGui")
	pop.Adornee = body
	pop.Size = UDim2.fromScale(4, 1.4)
	pop.StudsOffsetWorldSpace = Vector3.new(math.random(-15, 15) / 10, body.Size.Y / 2 + 1, 0)
	pop.AlwaysOnTop = true
	pop.LightInfluence = 0
	local text = label(pop, `-{Format.number(amount)}`, Color3.fromRGB(255, 230, 90), UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5))
	pop.Parent = playerGui
	TweenService:Create(pop, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = pop.StudsOffsetWorldSpace + Vector3.new(0, 2.5, 0),
	}):Play()
	TweenService:Create(text, TweenInfo.new(0.7), { TextTransparency = 1 }):Play()
	task.delay(0.75, function()
		pop:Destroy()
	end)
end

local function refresh(model: Model, entry: Tracked)
	local health = model:GetAttribute("Health")
	local max = model:GetAttribute("MaxHealth")
	if typeof(health) ~= "number" or typeof(max) ~= "number" or max <= 0 then return end
	local share = health / max
	TweenService:Create(entry.fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(math.clamp(share, 0, 1), 1), BackgroundColor3 = hpColor(share) }):Play()
	entry.amount.Text = `{Format.number(math.max(0, health))} / {Format.number(max)}`
	if health < entry.last and fighting(model) then
		damagePopup(model, entry.last - health)
	end
	entry.last = health
	-- Only enemies in zones you own can be fought.
	local zoneId = model:GetAttribute("ZoneId")
	local owned = (State.get("UnlockedWorlds") or {})[zoneId] == true
	entry.prompt.Enabled = owned and not fighting(model)
end

local function track(instance: Instance)
	if not instance:IsA("Model") or tracked[instance] then return end
	local model = instance
	local body = model.PrimaryPart or model:WaitForChild("Body", 5)
	if not (body and body:IsA("BasePart")) or not model.Parent then return end

	local gui = Instance.new("BillboardGui")
	gui.Name = "EnemyBar"
	gui.Adornee = body
	gui.Size = UDim2.fromOffset(150, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, body.Size.Y / 2 + 2.2, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	local level = model:GetAttribute("Level")
	label(gui, `{model.Name}  Lv.{if typeof(level) == "number" then level else 1}`, Color3.new(1, 1, 1), UDim2.fromScale(1, 0.45), UDim2.fromScale(0.5, 0.22))
	local _, fill = bar(gui, UDim2.fromScale(0.95, 0.4), UDim2.fromScale(0.5, 0.72))
	local amount = label(fill.Parent :: Instance, "", Color3.new(1, 1, 1), UDim2.fromScale(0.9, 0.85), UDim2.fromScale(0.5, 0.5))
	amount.ZIndex = 3
	gui.Parent = playerGui

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Fight"
	prompt.ActionText = "Fight"
	prompt.ObjectText = model.Name
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = Config.Combat.FightRange - 4
	prompt.Parent = body

	local entry: Tracked = { gui = gui, fill = fill, amount = amount, prompt = prompt, last = math.huge, connections = {} }
	tracked[model] = entry
	table.insert(entry.connections, prompt.Triggered:Connect(function()
		local id = model:GetAttribute("EnemyId")
		if typeof(id) ~= "number" then return end
		local response = State.fightEnemy(id)
		if not response.Ok then
			Interface.toastError(response)
		end
	end))
	table.insert(entry.connections, model.AttributeChanged:Connect(function()
		refresh(model, entry)
	end))
	entry.last = (model:GetAttribute("Health") :: number?) or 0
	refresh(model, entry)
end

local function untrack(instance: Instance)
	local entry = tracked[instance :: Model]
	if not entry then return end
	tracked[instance :: Model] = nil
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	entry.gui:Destroy()
	entry.prompt:Destroy()
end

local function refreshAll()
	for model, entry in tracked do
		refresh(model, entry)
	end
end

--------------------------------------------------------------------------
-- Team bar while fighting
--------------------------------------------------------------------------

local function buildTeamBar()
	teamGui = Instance.new("ScreenGui")
	teamGui.Name = "FightBar"
	teamGui.ResetOnSpawn = false
	teamGui.DisplayOrder = 4
	teamGui.Enabled = false

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.fromScale(0.5, 0.11)
	panel.Size = UDim2.fromScale(0.3, 0.08)
	panel.BackgroundTransparency = 1
	panel.Parent = teamGui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 6
	aspect.Parent = panel

	label(panel, "YOUR STUDS", Color3.new(1, 1, 1), UDim2.fromScale(0.5, 0.36), UDim2.fromScale(0.3, 0.18))
	strengthText = label(panel, "", Color3.fromRGB(255, 200, 90), UDim2.fromScale(0.4, 0.36), UDim2.fromScale(0.78, 0.18))
	local _, fill = bar(panel, UDim2.fromScale(0.78, 0.5), UDim2.fromScale(0.39, 0.72))
	teamFill = fill
	teamText = label(fill.Parent :: Instance, "", Color3.new(1, 1, 1), UDim2.fromScale(0.9, 0.8), UDim2.fromScale(0.5, 0.5))
	teamText.ZIndex = 3

	local retreat = Kit.button("Sunset", "RETREAT")
	retreat.AnchorPoint = Vector2.new(0.5, 0.5)
	retreat.Position = UDim2.fromScale(0.9, 0.72)
	retreat.Size = UDim2.fromScale(0.2, 0.62)
	retreat.Parent = panel
	Interface.bindButton(retreat, function()
		State.stopFight()
	end)

	teamGui.Parent = playerGui
end

local function refreshTeam()
	local team = State.get("Team")
	if typeof(team) ~= "table" or not team.Fighting then
		teamGui.Enabled = false
		return
	end
	teamGui.Enabled = true
	local share = if team.MaxHp > 0 then team.Hp / team.MaxHp else 0
	TweenService:Create(teamFill, TweenInfo.new(0.15), { Size = UDim2.fromScale(math.clamp(share, 0, 1), 1), BackgroundColor3 = hpColor(share) }):Play()
	teamText.Text = `❤ {Format.number(team.Hp)} / {Format.number(team.MaxHp)}`
	strengthText.Text = `💪 {Format.number(team.Strength)} / sec`
end

--------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------

function Enemies.start()
	Interface.setup()
	playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	buildTeamBar()

	for _, model in CollectionService:GetTagged(Tags.Enemy) do
		task.spawn(track, model)
	end
	CollectionService:GetInstanceAddedSignal(Tags.Enemy):Connect(function(model)
		task.spawn(track, model)
	end)
	CollectionService:GetInstanceRemovedSignal(Tags.Enemy):Connect(untrack)

	player:GetAttributeChangedSignal("FightTarget"):Connect(refreshAll)
	State.Changed:Connect(function(field)
		if field == "Team" then
			refreshTeam()
		elseif field == "UnlockedWorlds" then
			refreshAll()
		end
	end)
	refreshTeam()
end

return Enemies
