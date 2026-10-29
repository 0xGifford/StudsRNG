--[[

Enemies
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/Enemies

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The client side of Systems/Combat: a name, level and health bar over every
-- enemy (gold and bigger for Mini Bosses), and on the enemy your studs are
-- fighting: damage numbers, CRIT popups, sparks, hit sounds and a white hit
-- flash. A "!" pops over enemies that start hunting you; a Mini Boss spawning
-- nearby gets a banner. Defeats burst the enemy into bricks with a
-- shockwave, and your kills shower Clack coins into you. The team bar (your
-- studs' Health and Strength, RETREAT) shows the kill streak and pulses red
-- when your studs are low. Fights start on their own when an enemy reaches
-- you; the server decides everything, this only shows it (UI/CombatFx).

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
local Juice = require(UI.Juice)
local CombatFx = require(UI.CombatFx)

local Enemies = {}

local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local HP_GREEN = Color3.fromRGB(90, 230, 100)
local HP_RED = Color3.fromRGB(255, 80, 80)
local BOSS_GOLD = Color3.fromRGB(255, 205, 60)
local CRIT_ORANGE = Color3.fromRGB(255, 140, 40)
local AGGRO_RED = Color3.fromRGB(255, 70, 60)
local BOSS_ALERT_RANGE = 160 -- studs: Mini Bosses spawning this close get a banner

local player = Players.LocalPlayer
local playerGui: PlayerGui

type Tracked = {
	gui: BillboardGui,
	fill: Frame,
	amount: TextLabel,
	body: BasePart,
	boss: boolean,
	color: Color3,
	last: number,
	crits: number,
	hunting: boolean,
	connections: { RBXScriptConnection },
}
local tracked: { [Model]: Tracked } = {}

-- When each enemy stopped being your target (to tell your kills apart).
local endedAt: { [number]: number } = {}
local currentTarget: number? = nil
local lastHitSound = 0

-- One shared Highlight, on whatever you're fighting, flashed white per hit.
local flash: Highlight

local teamGui: ScreenGui
local teamPanel: Frame
local teamFill: Frame
local teamText: TextLabel
local strengthText: TextLabel
local streakText: TextLabel
local lowPulse: Tween? = nil

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

-- "-123" floating up off the enemy when your studs land a hit; crits are
-- bigger, orange, punch in and read "CRIT!".
local function damagePopup(body: BasePart, value: string, crit: boolean)
	local pop = Instance.new("BillboardGui")
	pop.Adornee = body
	pop.Size = if crit then UDim2.fromScale(7, 2.4) else UDim2.fromScale(4, 1.4)
	pop.StudsOffsetWorldSpace = Vector3.new(math.random(-15, 15) / 10, body.Size.Y / 2 + (if crit then 2 else 1), 0)
	pop.AlwaysOnTop = true
	pop.LightInfluence = 0
	local text = label(pop, value, if crit then CRIT_ORANGE else Color3.fromRGB(255, 230, 90), UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5))
	text.Rotation = if crit then math.random(-12, 12) else 0
	local scale = Instance.new("UIScale")
	scale.Scale = if crit then 2.2 else 1.4
	scale.Parent = text
	pop.Parent = playerGui
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(pop, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = pop.StudsOffsetWorldSpace + Vector3.new(0, 2.5, 0),
	}):Play()
	TweenService:Create(text, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.35), { TextTransparency = 1 }):Play()
	task.delay(0.9, function()
		pop:Destroy()
	end)
end

-- Bright white flash over the enemy you're fighting.
local function hitFlash(model: Model, strength: number)
	flash.Adornee = model
	flash.FillTransparency = 1 - strength
	TweenService:Create(flash, TweenInfo.new(0.18), { FillTransparency = 1 }):Play()
end

-- "!" pops over an enemy that just started hunting you.
local function aggroPop(entry: Tracked)
	local pop = Instance.new("BillboardGui")
	pop.Adornee = entry.body
	pop.Size = UDim2.fromScale(2.4, 2.4)
	pop.StudsOffsetWorldSpace = Vector3.new(0, entry.body.Size.Y / 2 + (if entry.boss then 7 else 4.6), 0)
	pop.AlwaysOnTop = true
	pop.LightInfluence = 0
	local mark = label(pop, "!", AGGRO_RED, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5))
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = mark
	pop.Parent = playerGui
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	CombatFx.sound("Aggro", entry.body.Position, 1.4, 0.4)
	task.delay(0.9, function()
		TweenService:Create(mark, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		task.wait(0.35)
		pop:Destroy()
	end)
end

local function wasMine(id: number): boolean
	return currentTarget == id or os.clock() - (endedAt[id] or -math.huge) < 1.5
end

-- Defeat: bricks, shockwave, sound; your kills shower coins (and Mini Boss
-- kills get the full celebration).
local function defeated(model: Model, entry: Tracked)
	local body = entry.body
	local cframe = body.CFrame
	local size = body.Size.X
	CombatFx.debris(cframe, entry.color, size, if entry.boss then 22 else 12)
	CombatFx.shockwave(cframe.Position - Vector3.new(0, size * 0.35, 0), entry.color, size)
	CombatFx.impact(cframe.Position, Color3.new(1, 1, 1), size)
	CombatFx.sound("Explode", cframe.Position, if entry.boss then 0.6 else 0.85, 0.8)

	local id = model:GetAttribute("EnemyId")
	if typeof(id) ~= "number" or not wasMine(id) then return end
	Juice.shake(if entry.boss then 0.9 else 0.35, if entry.boss then 0.45 else 0.2)
	CombatFx.coins(cframe.Position, if entry.boss then 18 else 7)
	if entry.boss then
		Juice.flash(BOSS_GOLD, 0.35, 0.5)
		Juice.fov(8, 0.6)
		Juice.banner("MINI BOSS DEFEATED!", model.Name, BOSS_GOLD, 1.4)
		local camera = workspace.CurrentCamera
		if camera then
			local point = camera:WorldToViewportPoint(cframe.Position)
			Juice.confetti(50, Vector2.new(point.X, point.Y))
		end
	end
end

local function refresh(model: Model, entry: Tracked)
	local health = model:GetAttribute("Health")
	local max = model:GetAttribute("MaxHealth")
	if typeof(health) ~= "number" or typeof(max) ~= "number" or max <= 0 then return end
	local share = health / max
	TweenService:Create(entry.fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(math.clamp(share, 0, 1), 1), BackgroundColor3 = hpColor(share) }):Play()
	entry.amount.Text = `{Format.number(math.max(0, health))} / {Format.number(max)}`
	local mine = fighting(model)

	-- Crits (the server counts them on the model).
	local crits = model:GetAttribute("Crits")
	local critNow = typeof(crits) == "number" and crits > entry.crits
	if typeof(crits) == "number" then entry.crits = crits end

	if health < entry.last and health > 0 and mine then
		local dealt = entry.last - health
		if critNow then
			damagePopup(entry.body, `CRIT! -{Format.number(dealt)}`, true)
			CombatFx.sparks(entry.body, 24, CRIT_ORANGE)
			CombatFx.sound("Crit", entry.body.Position, 1, 0.7)
			hitFlash(model, 0.85)
			Juice.shake(0.25, 0.12)
		else
			damagePopup(entry.body, `-{Format.number(dealt)}`, false)
			CombatFx.sparks(entry.body, 10)
			hitFlash(model, 0.5)
			if os.clock() - lastHitSound > 0.12 then
				lastHitSound = os.clock()
				CombatFx.sound("Hit", entry.body.Position, 1.1, 0.35)
			end
		end
		Juice.pop(entry.fill.Parent :: GuiObject, 1.08)
	end
	entry.last = health

	-- "!" when it starts hunting you.
	local hunting = model:GetAttribute("Hunting") == player.UserId
	if hunting and not entry.hunting and not mine then
		aggroPop(entry)
	end
	entry.hunting = hunting
end

local function track(instance: Instance)
	if not instance:IsA("Model") or tracked[instance] then return end
	local model = instance
	local body = model.PrimaryPart or model:WaitForChild("Body", 5)
	if not (body and body:IsA("BasePart")) or not model.Parent then return end

	local boss = model:GetAttribute("Boss") == true
	local gui = Instance.new("BillboardGui")
	gui.Name = "EnemyBar"
	gui.Adornee = body
	gui.Size = if boss then UDim2.fromOffset(220, 76) else UDim2.fromOffset(150, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, body.Size.Y / 2 + (if boss then 4 else 2.2), 0)
	gui.MaxDistance = if boss then 160 else 90
	gui.LightInfluence = 0
	local level = model:GetAttribute("Level")
	local levelText = `Lv.{if typeof(level) == "number" then level else 1}`
	local fill: Frame
	if boss then
		local tag = label(gui, "👑 MINI BOSS", BOSS_GOLD, UDim2.fromScale(1, 0.3), UDim2.fromScale(0.5, 0.15))
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), BOSS_GOLD)
		gradient.Rotation = 90
		gradient.Parent = tag
		label(gui, `{model.Name}  {levelText}`, Color3.new(1, 1, 1), UDim2.fromScale(1, 0.28), UDim2.fromScale(0.5, 0.45))
		local back
		back, fill = bar(gui, UDim2.fromScale(0.98, 0.3), UDim2.fromScale(0.5, 0.8))
		local stroke = back:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = BOSS_GOLD
		end
	else
		label(gui, `{model.Name}  {levelText}`, Color3.new(1, 1, 1), UDim2.fromScale(1, 0.45), UDim2.fromScale(0.5, 0.22))
		_, fill = bar(gui, UDim2.fromScale(0.95, 0.4), UDim2.fromScale(0.5, 0.72))
	end
	local amount = label(fill.Parent :: Instance, "", Color3.new(1, 1, 1), UDim2.fromScale(0.9, 0.85), UDim2.fromScale(0.5, 0.5))
	amount.ZIndex = 3
	gui.Parent = playerGui

	local crits = model:GetAttribute("Crits")
	local entry: Tracked = {
		gui = gui,
		fill = fill,
		amount = amount,
		body = body,
		boss = boss,
		color = body.Color,
		last = math.huge,
		crits = if typeof(crits) == "number" then crits else 0,
		hunting = false,
		connections = {},
	}
	tracked[model] = entry

	-- A Mini Boss spawning near you gets an entrance.
	local health, max = model:GetAttribute("Health"), model:GetAttribute("MaxHealth")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if boss and health == max and root and root:IsA("BasePart") and (root.Position - body.Position).Magnitude < BOSS_ALERT_RANGE then
		Juice.banner("A MINI BOSS APPEARS!", model.Name, AGGRO_RED, 1.2)
		Juice.shake(0.5, 0.35)
		CombatFx.shockwave(body.Position, BOSS_GOLD, body.Size.X)
		CombatFx.sound("Explode", body.Position, 0.5, 0.7)
	end
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
	if flash.Adornee == instance then
		flash.Adornee = nil
	end
	-- The server zeroes Health right before it removes a defeated enemy.
	if entry.last <= 0 or instance:GetAttribute("Health") == 0 then
		defeated(instance :: Model, entry)
	end
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
	teamPanel = panel
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

	-- Kill streak, under the bar.
	streakText = label(panel, "", Color3.fromRGB(255, 150, 60), UDim2.fromScale(0.6, 0.4), UDim2.fromScale(0.39, 1.25))
	streakText.Visible = false

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

	-- Low on Health: the bar throbs.
	local low = share < 0.3
	if low and not lowPulse then
		local pulse = TweenService:Create(teamPanel, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 1.5 })
		pulse:Play()
		lowPulse = pulse
	elseif not low and lowPulse then
		lowPulse:Cancel()
		lowPulse = nil
		teamPanel.Rotation = 0
	end
end

local function refreshStreak()
	local streak = player:GetAttribute("KillStreak")
	if typeof(streak) ~= "number" or streak < 2 then
		streakText.Visible = false
		return
	end
	local bonus = math.floor((streak - 1) * Config.Combat.StreakBonus * 100 + 0.5)
	streakText.Text = `🔥 STREAK x{streak}  +{bonus}% Clacks`
	streakText.TextColor3 = Color3.fromRGB(255, 200, 60):Lerp(Color3.fromRGB(255, 60, 40), math.min(1, streak / Config.Combat.StreakMax))
	streakText.Visible = true
	Juice.pop(streakText, 1.35)
end

local function onFightTarget()
	local id = player:GetAttribute("FightTarget")
	local nextTarget = if typeof(id) == "number" then id else nil
	if currentTarget and currentTarget ~= nextTarget then
		endedAt[currentTarget] = os.clock()
	end
	if nextTarget and nextTarget ~= currentTarget then
		-- The studs peel off: a whoosh as they go.
		CombatFx.sound("Dash", nil, 0.9, 0.35)
	end
	currentTarget = nextTarget
	refreshAll()
end

--------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------

function Enemies.start()
	Interface.setup()
	playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	buildTeamBar()
	flash = Instance.new("Highlight")
	flash.Name = "HitFlash"
	flash.FillColor = Color3.new(1, 1, 1)
	flash.FillTransparency = 1
	flash.OutlineTransparency = 1
	flash.DepthMode = Enum.HighlightDepthMode.Occluded
	flash.Parent = workspace -- client-made: only this player sees it

	for _, model in CollectionService:GetTagged(Tags.Enemy) do
		task.spawn(track, model)
	end
	CollectionService:GetInstanceAddedSignal(Tags.Enemy):Connect(function(model)
		task.spawn(track, model)
	end)
	CollectionService:GetInstanceRemovedSignal(Tags.Enemy):Connect(untrack)

	player:GetAttributeChangedSignal("FightTarget"):Connect(onFightTarget)
	player:GetAttributeChangedSignal("KillStreak"):Connect(refreshStreak)
	onFightTarget()
	refreshStreak()
	State.Changed:Connect(function(field)
		if field == "Team" then
			refreshTeam()
		end
	end)
	refreshTeam()
end

return Enemies
