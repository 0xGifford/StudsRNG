--[[

StudPassMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/StudPassMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The Stud Pass window (StarterGui.StudPass, a MenuSystem menu, side button
-- 🎟️; pieces found by PassRole, see tools/ui/screens/StudPass.luau): the season
-- name, your tier and progress, and a horizontal track of 30 tiers, each
-- with a free reward on top and a premium one below. Claimable rewards
-- glow; tap one to claim it, or CLAIM ALL. Premium rewards are locked until
-- the Stud Pass game pass is bought (UNLOCK PREMIUM). Stud and jackpot
-- rewards play the roll reel. A new tier pops a banner and an alert on the
-- side button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PassDefs = require(Shared.StudPass)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local RollReveal = require(Controllers.RollReveal)
local Interface = require(UI.Interface)
local Roles = require(UI.Roles)
local Format = require(UI.Format)
local Juice = require(UI.Juice)
local Robux = require(UI.Robux)
local SideButtons = require(UI.SideButtons)

local StudPassMenu = {}

local MENU = "StudPass"
local ROLE = "PassRole"
local GOLD = Color3.fromRGB(255, 205, 60)
local ICONS = { Clacks = "💰", FreeRolls = "🎲", Spins = "🎡", Luck = "🍀", Boost = "⚡", MegaRoll = "🎰", Bundle = "🎁", Stud = "💎" }

type Card = {
	button: GuiButton,
	stroke: UIStroke?,
	state: TextLabel,
	glow: Tween?,
	color: Color3,
	claimedColor: Color3,
	lockedColor: Color3,
	readyColor: Color3,
	stateColor: Color3,
	strokeColor: Color3,
	strokeThickness: number,
}
type Column = { frame: GuiObject, free: Card, premium: Card, number: TextLabel, numberColor: Color3, reachedColor: Color3 }

local track: ScrollingFrame? = nil
local columns: { Column } = {}
local tierText: TextLabel
local pointsText: TextLabel
local progressFill: GuiObject
local unlockButton: GuiObject
local sideButton: Frame? = nil
local pending = false

local function child(root: Instance, name: string): any
	local found = root:FindFirstChild(name, true)
	assert(found, `{root:GetFullName()} needs a "{name}"`)
	return found
end

local function onClick(object: GuiObject, fn: () -> ())
	local target = if object:IsA("GuiButton") then object else object:FindFirstChildWhichIsA("GuiButton", true)
	assert(target, `{object:GetFullName()} needs a button`)
	;(target :: GuiButton).Activated:Connect(function()
		Interface.play("Click")
		fn()
	end)
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
-- Gui (StarterGui.StudPass)
--------------------------------------------------------------------------

local function makeCard(frame: GuiButton, tier: number, premium: boolean): Card
	local def = PassDefs.Tiers[tier]
	local reward = if premium then def.Premium else def.Free
	child(frame, "Icon").Text = ICONS[reward.Kind] or "🎁"
	child(frame, "Reward").Text = Format.reward(reward)
	local state = child(frame, "State") :: TextLabel
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	onClick(frame, function()
		if premium and not ownsPremium() then
			if not Robux.prompt(true, "StudPass") then
				Interface.toast("Premium track coming soon!")
			end
			return
		end
		claim(tier, premium)
	end)
	local function color(name: string, fallback: Color3): Color3
		local value = frame:GetAttribute(name)
		return if typeof(value) == "Color3" then value else fallback
	end
	return {
		button = frame,
		stroke = stroke,
		state = state,
		glow = nil,
		color = frame.BackgroundColor3,
		claimedColor = color("ClaimedColor", frame.BackgroundColor3),
		lockedColor = color("LockedColor", frame.BackgroundColor3),
		readyColor = color("ReadyColor", GOLD),
		stateColor = state.TextColor3,
		strokeColor = if stroke then stroke.Color else Color3.new(),
		strokeThickness = if stroke then stroke.Thickness else 2,
	}
end

local function bind(): boolean
	if track then return true end
	local gui = Roles.gui(MENU)
	local found = Roles.find(gui, ROLE, "Track")
	if not found then
		warn('[StudPassMenu] StarterGui.StudPass has no PassRole pieces; run tools/ui/migrate.luau on your place')
		return false
	end
	track = found
	local season = Roles.find(gui, ROLE, "Season")
	if season then
		season.Text = `🎟️ STUD PASS · {PassDefs.Name}`
	end
	tierText = Roles.get(gui, ROLE, "Tier")
	pointsText = Roles.get(gui, ROLE, "Points")
	progressFill = Roles.get(gui, ROLE, "ProgressFill")
	onClick(Roles.get(gui, ROLE, "ClaimAll"), function()
		claim(0, false)
	end)
	unlockButton = Roles.get(gui, ROLE, "Unlock")
	onClick(unlockButton, function()
		if not Robux.prompt(true, "StudPass") then
			Interface.toast("Premium track coming soon!")
		end
	end)

	for tier = 1, #PassDefs.Tiers do
		local frame = Roles.template(gui, "PassColumn") :: GuiObject
		frame.Name = tostring(tier)
		frame.LayoutOrder = tier
		local number = child(frame, "Number") :: TextLabel
		number.Text = tostring(tier)
		local reached = frame:GetAttribute("ReachedColor")
		columns[tier] = {
			frame = frame,
			number = number,
			numberColor = number.TextColor3,
			reachedColor = if typeof(reached) == "Color3" then reached else GOLD,
			free = makeCard(child(frame, "Free"), tier, false),
			premium = makeCard(child(frame, "Premium"), tier, true),
		}
		frame.Parent = track
	end
	return true
end

local function styleCard(card: Card, claimed: boolean, ready: boolean, locked: boolean)
	card.button.BackgroundColor3 = if claimed then card.claimedColor elseif locked then card.lockedColor else card.color
	card.state.Text = if claimed then "✓ CLAIMED" elseif ready then "CLAIM!" elseif locked then "🔒" else ""
	card.state.TextColor3 = if ready then card.readyColor else card.stateColor
	local stroke = card.stroke
	if not stroke then return end
	if ready and not card.glow then
		stroke.Color = card.readyColor
		stroke.Thickness = card.strokeThickness + 1
		local glow = TweenService:Create(stroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.6 })
		glow:Play()
		card.glow = glow
	elseif not ready and card.glow then
		card.glow:Cancel()
		card.glow = nil
		stroke.Transparency = 0
		stroke.Thickness = card.strokeThickness
		stroke.Color = card.strokeColor
	end
end

local function render()
	if not track then return end
	local pass = passState()
	local reached = PassDefs.tierOf(pass.Points)
	local premium = ownsPremium()
	local perTier = PassDefs.PointsPerTier
	local into = if reached >= #PassDefs.Tiers then perTier else pass.Points - reached * perTier

	tierText.Text = if reached >= #PassDefs.Tiers then "MAX TIER!" else `Tier {reached} → {reached + 1}`
	pointsText.Text = `{Format.number(into)} / {Format.number(perTier)} points`
	local size = progressFill.Size
	TweenService:Create(progressFill, TweenInfo.new(0.3), {
		Size = UDim2.new(math.clamp(into / perTier, 0, 1), 0, size.Y.Scale, size.Y.Offset),
	}):Play()
	unlockButton.Visible = not premium

	for tier, column in columns do
		local reachedTier = tier <= reached
		column.number.TextColor3 = if reachedTier then column.reachedColor else column.numberColor
		local key = tostring(tier)
		styleCard(column.free, pass.Free[key] == true, reachedTier and not pass.Free[key], not reachedTier)
		styleCard(column.premium, pass.Premium[key] == true, premium and reachedTier and not pass.Premium[key], not premium or not reachedTier)
	end
end

local function onOpened()
	render()
	-- Scroll to the current tier.
	local reached = PassDefs.tierOf(passState().Points)
	local first = columns[1]
	if track and first then
		local width = first.frame.AbsoluteSize.X
		track.CanvasPosition = Vector2.new(math.max(0, (reached - 2) * width), 0)
	end
end

function StudPassMenu.open()
	Interface.open(MENU)
end

function StudPassMenu.close()
	Interface.close(MENU)
end

function StudPassMenu.isOpen(): boolean
	return Interface.isOpen(MENU)
end

function StudPassMenu.start()
	Interface.setup()
	if not bind() then return end
	Interface.MenuOpened:Connect(function(name)
		if name == MENU then
			onOpened()
		end
	end)
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
