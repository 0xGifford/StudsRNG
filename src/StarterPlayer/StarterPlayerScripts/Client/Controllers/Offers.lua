--[[

Offers
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/Offers

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Contextual offers: a small card that slides in from the left at the moment
-- an item is relevant, never more than one per item per session and never
-- more often than every MIN_GAP seconds, never over an open menu, no
-- countdowns. Tap BUY for the Roblox prompt, ✕ (or wait) to dismiss.
--   Starter Pack   a few minutes into a session, until bought
--   Lucky Drops    right after you defeat a Mini Boss
--   Stud Trainer   when one of your studs levels up
--   Stud Pass      when you reach pass tier 3 without the premium track
-- Items whose Id isn't set yet (Shared/Products) are never offered.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Products)
local PassDefs = require(Shared.StudPass)
local RollLogic = require(Shared.Util.RollLogic)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Robux = require(UI.Robux)
local Kit = require(UI.Kit)
local Juice = require(UI.Juice)

local Offers = {}

local MIN_GAP = 6 * 60
local SHOW_TIME = 12
local STARTER_DELAY = 150
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)

local player = Players.LocalPlayer

local shown: { [string]: boolean } = {}
local lastShown = -math.huge
local card: Frame
local title: TextLabel
local body: TextLabel
local price: TextLabel
local icon: ImageLabel
local current: { key: string, isPass: boolean }? = nil
local hideToken = 0

local function owns(isPass: boolean, key: string): boolean
	if isPass then
		local passes = State.get("Passes")
		return typeof(passes) == "table" and passes[key] == true
	end
	local bought = State.get("Bought")
	return typeof(bought) == "table" and bought[key] == true
end

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3, align: Enum.TextXAlignment): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.FontFace = FONT
	l.TextScaled = true
	l.TextWrapped = true
	l.TextColor3 = color
	l.TextXAlignment = align
	l.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = Color3.fromRGB(10, 10, 14)
	stroke.Parent = l
	l.Parent = parent
	return l
end

local function hide()
	current = nil
	TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Position = UDim2.new(0, -340, 0.56, 0) }):Play()
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Offers"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")

	card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0, 0.5)
	card.Position = UDim2.new(0, -340, 0.56, 0)
	card.Size = UDim2.fromOffset(320, 128)
	card.BackgroundColor3 = Color3.fromRGB(30, 28, 46)
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(255, 205, 60)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card

	icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromOffset(12, 14)
	icon.Size = UDim2.fromOffset(64, 64)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = card
	title = label(card, "", UDim2.fromOffset(196, 26), UDim2.fromOffset(86, 10), Color3.fromRGB(255, 205, 60), Enum.TextXAlignment.Left)
	body = label(card, "", UDim2.fromOffset(222, 48), UDim2.fromOffset(86, 38), Color3.new(1, 1, 1), Enum.TextXAlignment.Left)

	local buy = Instance.new("TextButton")
	buy.Text = ""
	buy.Position = UDim2.fromOffset(86, 90)
	buy.Size = UDim2.fromOffset(150, 30)
	buy.BackgroundColor3 = Color3.fromRGB(60, 180, 90)
	buy.Parent = card
	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0.3, 0)
	buyCorner.Parent = buy
	price = label(buy, "", UDim2.fromScale(0.9, 0.75), UDim2.fromScale(0.05, 0.12), Color3.new(1, 1, 1), Enum.TextXAlignment.Center)
	buy.Activated:Connect(function()
		Interface.play("Click")
		local offer = current
		if offer then
			Robux.prompt(offer.isPass, offer.key)
			hide()
		end
	end)

	local close = Instance.new("TextButton")
	close.Text = "✕"
	close.FontFace = FONT
	close.TextScaled = true
	close.TextColor3 = Color3.new(1, 1, 1)
	close.BackgroundTransparency = 1
	close.Position = UDim2.fromOffset(286, 6)
	close.Size = UDim2.fromOffset(26, 26)
	close.Parent = card
	close.Activated:Connect(function()
		Interface.play("Click")
		hide()
	end)
end

-- Shows the offer if it's allowed right now. Returns whether it showed.
local function offer(key: string, isPass: boolean, headline: string): boolean
	if shown[key] or current or owns(isPass, key) or not Robux.available(isPass, key) then return false end
	if os.clock() - lastShown < MIN_GAP or Interface.isOpen() then return false end
	local def = if isPass then Products.Passes[key] else Products.Products[key]
	if not def then return false end
	shown[key] = true
	lastShown = os.clock()
	current = { key = key, isPass = isPass }

	title.Text = headline
	body.Text = def.Description
	Kit.setIcon(icon, def.Icon)
	price.Text = "…"
	task.spawn(function()
		local robux = Robux.price(isPass, key)
		if current and current.key == key then
			price.Text = if robux then `BUY  R$ {robux}` else "BUY"
		end
	end)
	TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0, 14, 0.56, 0) }):Play()
	Juice.pop(card, 1.05)
	Interface.play("Hover", 1.3)

	hideToken += 1
	local token = hideToken
	task.delay(SHOW_TIME, function()
		if hideToken == token and current and current.key == key then
			hide()
		end
	end)
	return true
end

local function maxLevel(xp: any): number
	local best = 1
	if typeof(xp) == "table" then
		for _, amount in xp do
			best = math.max(best, RollLogic.levelOf(amount))
		end
	end
	return best
end

function Offers.start()
	Interface.setup()
	build()
	if not State.isReady() then
		State.Ready:Wait()
	end

	local bosses = State.get("BossesDefeated") or 0
	local level = maxLevel(State.get("StudXP"))
	local tier = PassDefs.tierOf((State.get("Pass") or {}).Points or 0)

	State.Changed:Connect(function(field, value)
		if field == "BossesDefeated" then
			if (value or 0) > bosses then
				task.delay(2.5, offer, "LuckyDrops", true, "Want more boss drops?")
			end
			bosses = value or 0
		elseif field == "StudXP" then
			local now = maxLevel(value)
			if now > level then
				task.delay(2.5, offer, "StudTrainer", true, "Level up twice as fast!")
			end
			level = now
		elseif field == "Pass" and typeof(value) == "table" then
			local now = PassDefs.tierOf(value.Points or 0)
			if now >= 3 and tier < 3 then
				task.delay(2.5, offer, "StudPass", true, "Unlock the premium track!")
			end
			tier = now
		end
	end)

	-- The Starter Pack, a few minutes in, for anyone who hasn't got it.
	task.delay(STARTER_DELAY, function()
		while not owns(false, "StarterPack") and not shown.StarterPack do
			if offer("StarterPack", false, "Starter Pack: one time only!") then break end
			task.wait(30)
		end
	end)
end

return Offers
