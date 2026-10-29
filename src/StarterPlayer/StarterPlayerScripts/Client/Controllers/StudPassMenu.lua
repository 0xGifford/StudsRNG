--[[

StudPassMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/StudPassMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The Stud Pass window (custom menu "StudPass", side button 🎟️): the season
-- name, your tier and progress, and a horizontal track of 30 tiers, each
-- with a free reward on top and a premium one below. Claimable rewards
-- glow; tap one to claim it, or CLAIM ALL. Premium rewards are locked until
-- the Stud Pass game pass is bought (UNLOCK PREMIUM). Stud and jackpot
-- rewards play the roll reel. A new tier pops a banner and an alert on the
-- side button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PassDefs = require(Shared.StudPass)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local RollReveal = require(Controllers.RollReveal)
local Interface = require(UI.Interface)
local Format = require(UI.Format)
local Juice = require(UI.Juice)
local Robux = require(UI.Robux)
local SideButtons = require(UI.SideButtons)

local StudPassMenu = {}

local MENU = "StudPass"
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local PANEL = Color3.fromRGB(28, 26, 44)
local CARD = Color3.fromRGB(44, 42, 64)
local CLAIMED = Color3.fromRGB(34, 64, 46)
local GOLD = Color3.fromRGB(255, 205, 60)
local PREMIUM = Color3.fromRGB(120, 70, 200)
local COLUMN = 118
local ICONS = { Clacks = "💰", FreeRolls = "🎲", Spins = "🎡", Luck = "🍀", Boost = "⚡", MegaRoll = "🎰", Bundle = "🎁", Stud = "💎" }

local player = Players.LocalPlayer

type Card = { button: TextButton, stroke: UIStroke, state: TextLabel, glow: Tween? }
type Column = { free: Card, premium: Card, number: TextLabel }

local gui: ScreenGui? = nil
local track: ScrollingFrame
local columns: { Column } = {}
local tierText: TextLabel
local pointsText: TextLabel
local progressFill: Frame
local unlockButton: TextButton
local sideButton: Frame? = nil
local pending = false

local function text(parent: Instance, value: string, color: Color3, size: UDim2, position: UDim2, align: Enum.TextXAlignment?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.FontFace = FONT
	label.TextScaled = true
	label.TextColor3 = color
	label.TextXAlignment = align or Enum.TextXAlignment.Center
	label.Text = value
	label.ZIndex = 3
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = Color3.fromRGB(10, 10, 14)
	stroke.Parent = label
	label.Parent = parent
	return label
end

local function round(object: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = object
end

local function button(parent: Instance, value: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Text = ""
	b.AutoButtonColor = true
	b.BackgroundColor3 = color
	b.ZIndex = 3
	round(b, 0.3)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(10, 10, 14)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	text(b, value, Color3.new(1, 1, 1), UDim2.fromScale(0.86, 0.66), UDim2.fromScale(0.07, 0.17)).ZIndex = 4
	b.Parent = parent
	return b
end

local function passState(): any
	local pass = State.get("Pass")
	if typeof(pass) ~= "table" or pass.Season ~= PassDefs.Season then
		return { Points = 0, Free = {}, Premium = {} }
	end
	return pass
end

local function ownsPremium(): boolean
	local passes = State.get("Passes")
	return typeof(passes) == "table" and passes.StudPass == true
end

local function claimable(): number
	local pass = passState()
	local reached = PassDefs.tierOf(pass.Points)
	local premium = ownsPremium()
	local n = 0
	for tier = 1, reached do
		if not pass.Free[tostring(tier)] then n += 1 end
		if premium and not pass.Premium[tostring(tier)] then n += 1 end
	end
	return n
end

local function refreshAlert()
	local n = claimable()
	SideButtons.setAlert(sideButton, n > 0, if n > 0 then tostring(n) else nil)
end

--------------------------------------------------------------------------
-- Claiming
--------------------------------------------------------------------------

local function claim(tier: number, premium: boolean)
	if pending then return end
	pending = true
	local response = State.claimPass(tier, premium)
	pending = false
	if not response.Ok then
		Interface.toastError(response)
		return
	end
	local results = {}
	local texts = {}
	for _, given in response.Rewards or {} do
		table.insert(texts, Format.reward(given))
		if typeof(given.Results) == "table" then
			for _, result in given.Results do
				table.insert(results, result)
			end
		end
	end
	Interface.toast(table.concat(texts, ", "), Color3.fromRGB(120, 255, 140))
	Juice.confetti(if tier == 0 then 80 else 40)
	if #results > 0 then
		Interface.close(MENU)
		RollReveal.showResults(results)
	end
end

--------------------------------------------------------------------------
-- Gui
--------------------------------------------------------------------------

local function makeCard(parent: Instance, tier: number, premium: boolean, y: number): Card
	local def = PassDefs.Tiers[tier]
	local reward = if premium then def.Premium else def.Free
	local b = Instance.new("TextButton")
	b.Text = ""
	b.AutoButtonColor = false
	b.BackgroundColor3 = CARD
	b.Size = UDim2.new(1, -10, 0.36, 0)
	b.Position = UDim2.new(0, 5, y, 0)
	b.ZIndex = 2
	round(b, 0.12)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = if premium then PREMIUM else Color3.fromRGB(12, 12, 18)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	text(b, ICONS[reward.Kind] or "🎁", Color3.new(1, 1, 1), UDim2.fromScale(0.6, 0.38), UDim2.fromScale(0.2, 0.06))
	text(b, Format.reward(reward), Color3.new(1, 1, 1), UDim2.fromScale(0.92, 0.3), UDim2.fromScale(0.04, 0.46))
	local state = text(b, "", Color3.fromRGB(120, 255, 140), UDim2.fromScale(0.9, 0.18), UDim2.fromScale(0.05, 0.79))
	b.Parent = parent
	b.Activated:Connect(function()
		Interface.play("Click")
		if premium and not ownsPremium() then
			if not Robux.prompt(true, "StudPass") then
				Interface.toast("Premium track coming soon!")
			end
			return
		end
		claim(tier, premium)
	end)
	return { button = b, stroke = stroke, state = state, glow = nil }
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "StudPass"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.IgnoreGuiInset = true
	screen.Enabled = false
	gui = screen

	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.Parent = screen

	local root = Instance.new("Frame")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.53)
	root.Size = UDim2.fromScale(0.86, 0.66)
	root.BackgroundColor3 = PANEL
	root.Parent = screen
	round(root, 0.04)
	local outline = Instance.new("UIStroke")
	outline.Thickness = 4
	outline.Color = Color3.fromRGB(10, 10, 14)
	outline.Parent = root
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(60, 40, 100), Color3.fromRGB(26, 24, 40))
	gradient.Rotation = 90
	gradient.Parent = root
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(1200, 600)
	limit.Parent = root

	text(root, `🎟️ STUD PASS · {PassDefs.Name}`, GOLD, UDim2.new(0.6, 0, 0, 34), UDim2.new(0, 20, 0, 12), Enum.TextXAlignment.Left)
	tierText = text(root, "", Color3.new(1, 1, 1), UDim2.new(0.3, 0, 0, 24), UDim2.new(0, 20, 0, 50), Enum.TextXAlignment.Left)
	pointsText = text(root, "", Color3.fromRGB(200, 200, 230), UDim2.new(0.25, 0, 0, 18), UDim2.new(0.3, 0, 0, 54), Enum.TextXAlignment.Left)

	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.new(0, 20, 0, 80)
	barBack.Size = UDim2.new(0.55, 0, 0, 12)
	barBack.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
	barBack.Parent = root
	round(barBack, 0.5)
	progressFill = Instance.new("Frame")
	progressFill.Size = UDim2.fromScale(0, 1)
	progressFill.BackgroundColor3 = GOLD
	progressFill.Parent = barBack
	round(progressFill, 0.5)

	local claimAll = button(root, "CLAIM ALL", Color3.fromRGB(60, 180, 90))
	claimAll.AnchorPoint = Vector2.new(1, 0)
	claimAll.Position = UDim2.new(1, -70, 0, 50)
	claimAll.Size = UDim2.new(0.14, 0, 0, 40)
	claimAll.Activated:Connect(function()
		Interface.play("Click")
		claim(0, false)
	end)

	unlockButton = button(root, "UNLOCK PREMIUM", Color3.fromRGB(150, 90, 230))
	unlockButton.AnchorPoint = Vector2.new(1, 0)
	unlockButton.Position = UDim2.new(0.86, -80, 0, 50)
	unlockButton.Size = UDim2.new(0.18, 0, 0, 40)
	unlockButton.Activated:Connect(function()
		Interface.play("Click")
		if not Robux.prompt(true, "StudPass") then
			Interface.toast("Premium track coming soon!")
		end
	end)

	text(root, "FREE", Color3.new(1, 1, 1), UDim2.new(0, 70, 0, 20), UDim2.new(0, 10, 0.36, 0))
	text(root, "PREMIUM", PREMIUM:Lerp(Color3.new(1, 1, 1), 0.4), UDim2.new(0, 70, 0, 20), UDim2.new(0, 10, 0.72, 0))

	track = Instance.new("ScrollingFrame")
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.Position = UDim2.new(0, 84, 0, 104)
	track.Size = UDim2.new(1, -100, 1, -116)
	track.CanvasSize = UDim2.fromOffset(COLUMN * #PassDefs.Tiers, 0)
	track.ScrollingDirection = Enum.ScrollingDirection.X
	track.ScrollBarThickness = 8
	track.Parent = root

	for tier = 1, #PassDefs.Tiers do
		local column = Instance.new("Frame")
		column.BackgroundTransparency = 1
		column.Position = UDim2.fromOffset((tier - 1) * COLUMN, 0)
		column.Size = UDim2.new(0, COLUMN, 1, -10)
		column.Parent = track
		local number = text(column, tostring(tier), Color3.new(1, 1, 1), UDim2.new(1, 0, 0.12, 0), UDim2.fromScale(0, 0.02))
		columns[tier] = {
			number = number,
			free = makeCard(column, tier, false, 0.16),
			premium = makeCard(column, tier, true, 0.58),
		}
	end

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(46, 46)
	close.BackgroundColor3 = Color3.fromRGB(230, 40, 40)
	close.Text = ""
	close.Parent = root
	round(close, 0.2)
	text(close, "X", Color3.new(1, 1, 1), UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.15, 0.15))
	close.Activated:Connect(function()
		Interface.play("Click")
		Interface.close(MENU)
	end)

	screen.Parent = player:WaitForChild("PlayerGui")
end

local function styleCard(card: Card, claimed: boolean, ready: boolean, locked: boolean, premium: boolean)
	card.button.BackgroundColor3 = if claimed then CLAIMED elseif locked then Color3.fromRGB(32, 30, 44) else CARD
	card.state.Text = if claimed then "✓ CLAIMED" elseif ready then "CLAIM!" elseif locked then "🔒" else ""
	card.state.TextColor3 = if ready then GOLD else Color3.fromRGB(120, 255, 140)
	if ready and not card.glow then
		card.stroke.Color = GOLD
		card.stroke.Thickness = 3
		local glow = TweenService:Create(card.stroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.6 })
		glow:Play()
		card.glow = glow
	elseif not ready and card.glow then
		card.glow:Cancel()
		card.glow = nil
		card.stroke.Transparency = 0
		card.stroke.Thickness = 2
		card.stroke.Color = if premium then PREMIUM else Color3.fromRGB(12, 12, 18)
	end
end

local function render()
	if not gui then return end
	local pass = passState()
	local reached = PassDefs.tierOf(pass.Points)
	local premium = ownsPremium()
	local perTier = PassDefs.PointsPerTier
	local into = if reached >= #PassDefs.Tiers then perTier else pass.Points - reached * perTier

	tierText.Text = if reached >= #PassDefs.Tiers then "MAX TIER!" else `Tier {reached} → {reached + 1}`
	pointsText.Text = `{Format.number(into)} / {Format.number(perTier)} points`
	TweenService:Create(progressFill, TweenInfo.new(0.3), { Size = UDim2.fromScale(math.clamp(into / perTier, 0, 1), 1) }):Play()
	unlockButton.Visible = not premium

	for tier, column in columns do
		local reachedTier = tier <= reached
		column.number.TextColor3 = if reachedTier then GOLD else Color3.fromRGB(150, 150, 170)
		local key = tostring(tier)
		styleCard(column.free, pass.Free[key] == true, reachedTier and not pass.Free[key], not reachedTier, false)
		styleCard(column.premium, pass.Premium[key] == true, premium and reachedTier and not pass.Premium[key], not premium or not reachedTier, true)
	end
end

function StudPassMenu.open()
	if not gui then build() end
	local screen = gui :: ScreenGui
	if screen.Enabled then return end
	screen.Enabled = true
	render()
	-- Scroll to the current tier.
	local reached = PassDefs.tierOf(passState().Points)
	track.CanvasPosition = Vector2.new(math.max(0, (reached - 2) * COLUMN), 0)
end

function StudPassMenu.close()
	if gui then
		gui.Enabled = false
	end
end

function StudPassMenu.isOpen(): boolean
	return gui ~= nil and gui.Enabled
end

function StudPassMenu.start()
	Interface.setup()
	Interface.registerMenu(MENU, {
		open = StudPassMenu.open,
		close = StudPassMenu.close,
		isOpen = StudPassMenu.isOpen,
	})
	sideButton = SideButtons.add(MENU, "Pass", "🎟️")

	State.Changed:Connect(function(field)
		if field == "Pass" or field == "Passes" then
			refreshAlert()
			if StudPassMenu.isOpen() then render() end
		end
	end)
	State.Notified:Connect(function(payload)
		if payload.Kind == "PassTier" then
			Juice.banner(`PASS TIER {payload.Tier}!`, "New Stud Pass rewards to claim", GOLD, 1.6)
			Juice.confetti(50)
		end
	end)
	if State.isReady() then refreshAlert() else State.Ready:Connect(refreshAlert) end
end

return StudPassMenu
