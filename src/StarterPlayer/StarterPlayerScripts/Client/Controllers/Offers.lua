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
--
-- The card is StarterGui.Offers (tools/ui/screens/Offers.luau), found by
-- OfferRole: Card (rests where it sits in Studio, slides in from the left),
-- Icon, Title, Body, Buy, Price, Close.

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
local Roles = require(UI.Roles)

local Offers = {}

local MIN_GAP = 6 * 60
local SHOW_TIME = 12
local STARTER_DELAY = 150

local shown: { [string]: boolean } = {}
local lastShown = -math.huge
local card: GuiObject
local home: UDim2 -- where the card rests (its Studio position)
local away: UDim2 -- off the left edge
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

local function hide()
	current = nil
	TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Position = away }):Play()
end

local function bind()
	local gui = Roles.gui("Offers")
	card = Roles.get(gui, "OfferRole", "Card")
	icon = Roles.get(gui, "OfferRole", "Icon")
	title = Roles.get(gui, "OfferRole", "Title")
	body = Roles.get(gui, "OfferRole", "Body")
	price = Roles.get(gui, "OfferRole", "Price")
	home = card.Position
	away = UDim2.new(home.X.Scale - 1, home.X.Offset - 40, home.Y.Scale, home.Y.Offset)
	card.Position = away
	card.Visible = true

	local buy = Roles.get(gui, "OfferRole", "Buy") :: GuiButton
	buy.Activated:Connect(function()
		Interface.play("Click")
		local offer = current
		if offer then
			Robux.prompt(offer.isPass, offer.key)
			hide()
		end
	end)
	local close = Roles.find(gui, "OfferRole", "Close")
	if close and close:IsA("GuiButton") then
		close.Activated:Connect(function()
			Interface.play("Click")
			hide()
		end)
	end
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
	TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = home }):Play()
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
	bind()
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
