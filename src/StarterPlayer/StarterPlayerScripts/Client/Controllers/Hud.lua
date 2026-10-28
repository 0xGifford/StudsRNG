--[[

Hud
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/Hud

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The always-on HUD: Studs / Roll / Auto buttons, the free-roll meter under
-- Roll, Clacks + multiplier labels, the side menu buttons (with "!" alerts),
-- the Premium / Friend / Daily boost labels and server toasts.
--
-- Clacks gained arrive as "+x" popups that fly from the player's character
-- into the Clacks counter; the counter only counts up when they land.

local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Upgrades = require(Shared.Upgrades)
local Zones = require(Shared.Zones)
local RewardDefs = require(Shared.Rewards)
local RollLogic = require(Shared.Util.RollLogic)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local RollReveal = require(Controllers.RollReveal)
local Interface = require(UI.Interface)
local Format = require(UI.Format)
local UIConfig = require(UI.UIConfig)
local Juice = require(UI.Juice)

local player = Players.LocalPlayer

local Hud = {}

local rollFrame: Frame
local autoFrame: Frame
local meter: Frame
local meterBar: Frame
local clacksFrame: Frame
local multiplierFrame: Frame
local sideButtons: Frame
local boosts: Frame?
local popupLayer: Frame

-- Count-up display for Clacks: only moves when popups land (or on spends).
local shownClacks = Instance.new("NumberValue")
local clacksTween: Tween? = nil
local lastClacks = 0
local inFlight = 0
local clacksScale: UIScale

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function side(name: string): Frame?
	local frame = sideButtons:FindFirstChild(name)
	return if frame and frame:IsA("Frame") then frame else nil
end

local function setAlert(name: string, on: boolean, text: string?)
	local frame = side(name)
	local alert = frame and frame:FindFirstChild("Alert")
	if alert and alert:IsA("GuiObject") then
		if on and not alert.Visible then
			Juice.pop(alert, 1.6)
		end
		alert.Visible = on
		if text then
			Interface.setText(alert, text)
		end
	end
end

local function boostLabel(name: string): Frame?
	local frame = boosts and boosts:FindFirstChild(name)
	return if frame and frame:IsA("Frame") then frame else nil
end

local function applyFeatures()
	local features = UIConfig.Features :: { [string]: boolean }
	for _, name in { "Store", "Rebirth", "Rewards", "Wheel", "Upgrades", "Zones", "Quests" } do
		local frame = side(name)
		if frame then
			frame.Visible = features[name] == true
		end
	end

	local store = side("Store")
	if store then
		for _, name in { "Sale", "SaleShadow" } do
			local tag = store:FindFirstChild(name)
			if tag and tag:IsA("GuiObject") then
				tag.Visible = UIConfig.StoreSale
			end
		end
	end

	if boosts then
		boosts.Visible = features.Boosts
	end

	local events = Interface.HUD:FindFirstChild("Events")
	if events then
		for _, frame in events:GetChildren() do
			if frame:IsA("GuiObject") then
				frame.Visible = features.Events
			end
		end
	end
end

--------------------------------------------------------------------------
-- Top bar
--------------------------------------------------------------------------

local function updateRollButton()
	local free = State.get("FreeRolls") or 0
	if free > 0 then
		Interface.setText(rollFrame, `Free Roll ({free})`)
	else
		Interface.setText(rollFrame, `Roll · {Format.number(State.stats().RollCost)}`)
	end
end

local function updateMeter()
	local stats = State.stats()
	local perRoll = stats.PressesPerFreeRoll
	local value = State.get("RollMeter") or 0
	local free = State.get("FreeRolls") or 0
	local fraction = math.clamp(value / perRoll, 0, 1)
	local text = if free >= stats.MaxBankedFreeRolls then "Bank full" else `{math.min(value, perRoll)}/{perRoll}`
	Interface.setText(meter, text, "Amount", "AmountShadow")
	TweenService:Create(meterBar, Interface.FAST, { Size = UDim2.fromScale(fraction, 1) }):Play()
end

local function updateAuto()
	if not State.stats().AutoRoll then
		Interface.setText(autoFrame, "Auto: Locked")
	else
		Interface.setText(autoFrame, if RollReveal.isAuto() then "Auto: On" else "Auto: Off")
	end
end

--------------------------------------------------------------------------
-- Amounts
--------------------------------------------------------------------------

local function renderClacks(value: number)
	Interface.setText(clacksFrame, `{Format.number(value)} Clacks`, "Amount", "AmountShadow")
end

local function tweenClacksTo(target: number)
	if clacksTween then clacksTween:Cancel() end
	local tween = TweenService:Create(shownClacks, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Value = target })
	clacksTween = tween
	tween:Play()
end

local function punchClacks()
	clacksScale.Scale = 1.18
	TweenService:Create(clacksScale, TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function updateMultiplier()
	local stats = State.stats()
	local luck = string.format("%.2f", stats.Luck)
	luck = string.gsub(luck, "%.?0+$", "")
	Interface.setText(multiplierFrame, `{Format.multiplier(stats.ClackMultiplier)} Clacks · {luck} Luck`, "Amount", "AmountShadow")
end

--------------------------------------------------------------------------
-- "+x Clacks" popups: player → counter
--------------------------------------------------------------------------

-- Viewport → HUD coordinates (the HUD may or may not cover the top bar).
local function hudOrigin(): Vector2
	local insets = Interface.HUD.ScreenInsets
	if insets == Enum.ScreenInsets.CoreUISafeInsets or insets == Enum.ScreenInsets.TopbarSafeInsets then
		local inset = GuiService:GetGuiInset()
		return inset
	end
	return Vector2.zero
end

local function counterCenter(): Vector2
	local amount = clacksFrame:FindFirstChild("Amount")
	local target: GuiObject = if amount and amount:IsA("GuiObject") then amount else clacksFrame
	return target.AbsolutePosition + target.AbsoluteSize / 2 - popupLayer.AbsolutePosition
end

local function characterPoint(): Vector2?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not (root and root:IsA("BasePart") and camera) then return nil end
	local point, onScreen = camera:WorldToViewportPoint(root.Position)
	if not onScreen then return nil end
	return Vector2.new(point.X, point.Y) - hudOrigin() - popupLayer.AbsolutePosition
end

local function backOut(x: number): number
	local c1 = 1.70158
	local p = x - 1
	return 1 + (c1 + 1) * p * p * p + c1 * p * p
end

local function flyPopup(amount: number, start: Vector2, onLand: () -> ())
	local source = clacksFrame:FindFirstChild("Amount")
	if not (source and source:IsA("TextLabel")) then
		onLand()
		return
	end
	local height = math.max(clacksFrame.AbsoluteSize.Y * 0.8, 18)

	local popup = source:Clone()
	popup.Name = "Popup"
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Size = UDim2.fromOffset(height * 5, height)
	popup.Position = UDim2.fromOffset(start.X, start.Y)
	popup.Text = `+{Format.number(amount)}`
	popup.ZIndex = 20
	popup.Parent = popupLayer
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = popup

	local strokes: { UIStroke } = {}
	for _, child in popup:GetChildren() do
		if child:IsA("UIStroke") then
			table.insert(strokes, child)
		end
	end

	local duration = UIConfig.ClackPopups.Duration
	local bow = if math.random() < 0.5 then -1 else 1
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local t = math.clamp(elapsed / duration, 0, 1)
		local target = counterCenter()
		local mid = (start + target) / 2 + Vector2.new(bow * 80, -60)
		local travel = t ^ 1.6
		local a = start:Lerp(mid, travel)
		local b = mid:Lerp(target, travel)
		local position = a:Lerp(b, travel)
		popup.Position = UDim2.fromOffset(position.X, position.Y)

		if t < 0.3 then
			scale.Scale = backOut(t / 0.3)
		elseif t > 0.75 then
			scale.Scale = 1 - 0.55 * (t - 0.75) / 0.25
		else
			scale.Scale = 1
		end
		local fade = if t > 0.8 then (t - 0.8) / 0.2 else 0
		popup.TextTransparency = fade
		for _, stroke in strokes do
			stroke.Transparency = fade
		end

		if t >= 1 then
			connection:Disconnect()
			popup:Destroy()
			onLand()
		end
	end)
end

local function onClacksChanged()
	local value = State.get("Clacks") or 0
	local delta = value - lastClacks
	lastClacks = value

	if delta <= 0 then
		-- Spending (or a reset): show it straight away.
		tweenClacksTo(value)
		return
	end

	local start = characterPoint()
	if not start or inFlight >= UIConfig.ClackPopups.MaxInFlight then
		tweenClacksTo(value)
		return
	end

	inFlight += 1
	flyPopup(delta, start, function()
		inFlight -= 1
		-- Land on whatever the total is NOW (more may have arrived meanwhile).
		tweenClacksTo(State.get("Clacks") or 0)
		punchClacks()
		Interface.play("Click", 1.3 + math.random() * 0.2)
	end)
end

--------------------------------------------------------------------------
-- Alerts and boost labels
--------------------------------------------------------------------------

local function updateAlerts()
	local stats = State.stats()
	local clacks = State.get("Clacks") or 0

	setAlert("Rebirth", clacks >= RollLogic.rebirthCost(State.get("Rebirths") or 0))

	local unlocked = State.get("UnlockedWorlds") or {}
	local nextZone = Zones.nextFor(unlocked)
	setAlert("Zones", nextZone ~= nil and clacks >= Zones.price(nextZone, stats.ZoneDiscount))

	local levels = State.get("Upgrades") or {}
	local canUpgrade = false
	for _, def in Upgrades.List do
		local level = Upgrades.level(levels, def.Id)
		if level < def.MaxLevel and Upgrades.isUnlocked(def, levels) and clacks >= Upgrades.cost(def, level) then
			canUpgrade = true
			break
		end
	end
	setAlert("Upgrades", canUpgrade)

	local quests = State.get("Quests")
	local claimable = 0
	if typeof(quests) == "table" and typeof(quests.List) == "table" then
		for _, quest in quests.List do
			if not quest.Claimed and quest.Progress >= quest.Target then
				claimable += 1
			end
		end
	end
	setAlert("Quests", claimable > 0, tostring(claimable))

	local wheel = side("Wheel")
	if wheel then
		local spins = State.get("Spins") or 0
		Interface.setText(wheel, if spins > 0 then `Wheel ({spins})` else "Wheel")
	end
end

local function updatePlaytimeAlert()
	local playtime = State.get("Playtime")
	if typeof(playtime) ~= "table" then
		setAlert("Rewards", false)
		return
	end
	local elapsed = State.serverNow() - playtime.Start
	local ready = 0
	for index, reward in RewardDefs.Playtime do
		if not playtime.Claimed[index] and elapsed >= reward.At * 60 then
			ready += 1
		end
	end
	setAlert("Rewards", ready > 0, tostring(ready))
end

local function updateBoostLabels()
	local stats = State.stats()
	local premium = boostLabel("Premium")
	if premium then
		Interface.setText(premium, `+{Format.percent(stats.PremiumBonus)}`, "Amount", "AmountShadow")
	end
	local friends = boostLabel("FriendBoost")
	if friends then
		Interface.setText(friends, `+{Format.percent(stats.FriendBonus)}`, "Amount", "AmountShadow")
	end
	local daily = boostLabel("DailyRewards")
	local alert = daily and daily:FindFirstChild("Alert")
	if alert and alert:IsA("GuiObject") then
		local today = RewardDefs.dayNumber(State.serverNow())
		local canClaim = RewardDefs.dailyState(State.get("Daily"), today)
		alert.Visible = canClaim
	end
end

local function bindBoostLabel(name: string, onClick: () -> ())
	local frame = boostLabel(name)
	if not frame then return end
	local info = frame:FindFirstChild("Info")
	local button = frame:FindFirstChild("Button")
	if not (button and button:IsA("GuiButton")) then return end
	button.MouseEnter:Connect(function()
		if info and info:IsA("GuiObject") then info.Visible = true end
	end)
	button.MouseLeave:Connect(function()
		if info and info:IsA("GuiObject") then info.Visible = false end
	end)
	Interface.bindButton(frame, onClick, 0.92, 0.85)
end

--------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------

function Hud.start()
	Interface.setup()

	local top = Interface.HUD:WaitForChild("Top"):WaitForChild("Frame")
	local studsFrame = top:WaitForChild("Studs") :: Frame
	rollFrame = top:WaitForChild("Roll") :: Frame
	autoFrame = top:WaitForChild("Auto") :: Frame
	meter = rollFrame:WaitForChild("Meter") :: Frame
	meterBar = meter:WaitForChild("Bar") :: Frame

	local labels = Interface.HUD:WaitForChild("Labels")
	local amounts = labels:WaitForChild("Amounts")
	clacksFrame = amounts:WaitForChild("Clacks") :: Frame
	multiplierFrame = amounts:WaitForChild("Multiplier") :: Frame
	local boostsFrame = labels:FindFirstChild("Boosts")
	boosts = if boostsFrame and boostsFrame:IsA("Frame") then boostsFrame else nil
	sideButtons = Interface.HUD:WaitForChild("Side"):WaitForChild("Buttons") :: Frame

	clacksScale = clacksFrame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	clacksScale.Parent = clacksFrame

	popupLayer = Instance.new("Frame")
	popupLayer.Name = "ClackPopups"
	popupLayer.BackgroundTransparency = 1
	popupLayer.Size = UDim2.fromScale(1, 1)
	popupLayer.ZIndex = 50
	popupLayer.Parent = Interface.HUD

	applyFeatures()

	Interface.bindButton(studsFrame, function()
		Interface.toggle("Studs")
	end)
	Interface.bindButton(rollFrame, function()
		RollReveal.roll(false)
	end)
	Interface.bindButton(autoFrame, function()
		RollReveal.setAuto(not RollReveal.isAuto())
	end)

	-- Side buttons open the menu of the same name (Upgrades is the
	-- full-screen tree, registered by UpgradeTree as a custom menu).
	for _, frame in sideButtons:GetChildren() do
		if frame:IsA("Frame") and frame:FindFirstChild("Button") then
			local name = frame.Name
			Interface.bindButton(frame, function()
				Interface.toggle(name)
			end, 0.9, 0.8)
		end
	end

	bindBoostLabel("DailyRewards", function()
		Interface.toggle("Daily")
	end)
	bindBoostLabel("Premium", function()
		if player.MembershipType == Enum.MembershipType.Premium then
			Interface.toast(`Premium: +{Format.percent(Config.Social.PremiumBonus)} Clacks. Thanks for being Premium!`)
		else
			pcall(MarketplaceService.PromptPremiumPurchase, MarketplaceService, player)
		end
	end)
	bindBoostLabel("FriendBoost", function()
		Interface.toast(`+{Format.percent(Config.Social.FriendBonus)} Clacks per friend in the server (max {Config.Social.MaxFriends})`)
		task.spawn(function()
			local ok, canInvite = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
			if ok and canInvite then
				pcall(SocialService.PromptGameInvite, SocialService, player)
			end
		end)
	end)

	shownClacks.Changed:Connect(renderClacks)
	RollReveal.AutoChanged:Connect(updateAuto)
	RollReveal.AutoLocked:Connect(function()
		Interface.toast("Unlock Auto Roll in the Upgrades tree!", Color3.fromRGB(255, 230, 90))
		Interface.open("Upgrades")
	end)

	State.Notified:Connect(function(payload)
		Interface.toast(payload.Text, payload.Color)
	end)

	local function renderAll()
		lastClacks = State.get("Clacks") or 0
		shownClacks.Value = lastClacks
		renderClacks(lastClacks)
		updateRollButton()
		updateMeter()
		updateMultiplier()
		updateAuto()
		updateAlerts()
		updatePlaytimeAlert()
		updateBoostLabels()
	end

	State.Changed:Connect(function(field)
		if not State.isReady() then return end
		if field == "Clacks" then
			onClacksChanged()
			updateRollButton()
			updateAlerts()
		elseif field == "FreeRolls" then
			updateRollButton()
			updateMeter()
		elseif field == "RollMeter" then
			updateMeter()
		elseif field == "Stats" then
			updateMultiplier()
			updateRollButton()
			updateMeter()
			updateAuto()
			updateAlerts()
			updateBoostLabels()
		elseif field == "Upgrades" or field == "UnlockedWorlds" or field == "Rebirths" or field == "Spins" or field == "Quests" then
			updateAlerts()
		elseif field == "Playtime" then
			updatePlaytimeAlert()
		elseif field == "Daily" then
			updateBoostLabels()
		end
	end)

	if State.isReady() then
		renderAll()
	else
		State.Ready:Connect(renderAll)
	end

	-- Time-based alerts (playtime unlocks, the daily reset).
	task.spawn(function()
		while true do
			task.wait(1)
			if State.isReady() then
				updatePlaytimeAlert()
				updateBoostLabels()
			end
		end
	end)
end

return Hud
