--[[

ShopMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The Store window, built from Shared/Products in Products.Sections order:
-- game passes and featured items get full-width cards, boosts / spins /
-- Clack packs sit two to a row. Prices are live from Roblox; passes you own
-- say "Owned"; unset ids say "Soon". Lucky Roll has an Odds button that
-- opens the Luck & Odds window.
-- Stud Club (a subscription) sits on top: JOIN while not a member; members
-- get a second card to claim the daily bundle. Milestone value packs only
-- show once their milestone is reached (PlayerData.Milestones).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Products = require(Shared.Products)
local RewardDefs = require(Shared.Rewards)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Kit = require(UI.Kit)
local Robux = require(UI.Robux)
local Format = require(UI.Format)
local Juice = require(UI.Juice)

local ShopMenu = {}

local MENU = "Store"
local ROBUX_ICON = "rbxassetid://93435714136691"

local items: ScrollingFrame
local passCards: { [string]: Frame } = {}
local clubClaim: Frame? = nil
local pending = false

type Entry = { Key: string, Def: any, IsPass: boolean, IsSubscription: boolean? }

local function member(): boolean
	return State.passes().Club == true
end

local function clubClaimedToday(): boolean
	return State.get("ClubClaimDay") == RewardDefs.dayNumber(State.serverNow())
end

local function reached(milestone: string?): boolean
	if not milestone then return true end
	local milestones = State.get("Milestones")
	return typeof(milestones) == "table" and milestones[milestone] == true
end

local function entriesFor(section: string): { Entry }
	local list: { Entry } = {}
	if section == "Club" then
		for key, def in Products.Subscriptions do
			table.insert(list, { Key = key, Def = { Name = def.Name, Description = def.Description, Icon = def.Icon, Color = def.Color, Order = 0 }, IsPass = false, IsSubscription = true })
		end
	elseif section == "Passes" then
		for key, def in Products.Passes do
			table.insert(list, { Key = key, Def = def, IsPass = true })
		end
	else
		local bought = State.get("Bought") or {}
		for key, def in Products.Products do
			-- One-time products (Starter Pack) disappear once bought; milestone
			-- packs appear once their milestone is reached.
			if def.Section == section and not (def.OneTime and bought[key]) and reached(def.Milestone) then
				table.insert(list, { Key = key, Def = def, IsPass = false })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Def.Order < b.Def.Order
	end)
	return list
end

local function setPassPrice(card: Frame, key: string)
	local price = card:FindFirstChild("Price", true)
	if not (price and price:IsA("TextLabel")) then return end
	if State.passes()[key] then
		Kit.setPrice(card, "Owned", nil)
	elseif not Robux.available(true, key) then
		Kit.setPrice(card, "Soon", nil)
	else
		Kit.setPrice(card, "…", ROBUX_ICON)
		Robux.showPrice(price, true, key)
	end
end

local function updateClubClaim()
	local card = clubClaim
	if not card then return end
	if clubClaimedToday() then
		local left = (RewardDefs.dayNumber(State.serverNow()) + 1) * RewardDefs.DaySeconds - State.serverNow()
		Kit.setPrice(card, `Next in {Format.duration(left)}`, nil)
	else
		Kit.setPrice(card, "CLAIM!", nil)
	end
end

local function claimClub()
	if pending then return end
	if clubClaimedToday() then
		Interface.toast("Come back tomorrow for the next one!")
		return
	end
	pending = true
	local response = Net.invoke("ClaimClub")
	pending = false
	if response.Ok and response.Reward then
		Interface.toast(`Stud Club: {Format.reward(response.Reward)}`, Config.Club.TagColor)
		local card = clubClaim
		if card then
			Juice.pop(card, 1.1)
			Juice.confetti(50, card.AbsolutePosition + card.AbsoluteSize / 2)
		end
	else
		Interface.toastError(response)
	end
	updateClubClaim()
end

local function buy(entry: Entry)
	if entry.IsSubscription then
		if member() then
			Interface.toast("You're in the club! Manage it in your Roblox settings.")
		elseif not Robux.promptSubscription(entry.Key) then
			Interface.toast("Coming soon!")
		end
		return
	end
	if entry.IsPass and State.passes()[entry.Key] then
		Interface.toast("You already own this!")
		return
	end
	if not Robux.prompt(entry.IsPass, entry.Key) then
		Interface.toast("Coming soon!")
	end
end

local function makeCard(entry: Entry): Frame
	local def = entry.Def
	local card = Kit.card({
		Title = def.Name,
		Description = def.Description,
		Icon = def.Icon,
		Color = def.Color,
	})
	if def.Badge then
		Kit.badge(card, def.Badge)
	end

	if entry.IsSubscription then
		Kit.setPrice(card, if member() then "Member ✓" elseif Robux.subscriptionAvailable(entry.Key) then "JOIN" else "Soon", nil)
	elseif entry.IsPass then
		passCards[entry.Key] = card
		setPassPrice(card, entry.Key)
	else
		local price = card:FindFirstChild("Price", true)
		if Robux.available(false, entry.Key) then
			Kit.setPrice(card, "…", ROBUX_ICON)
			if price and price:IsA("TextLabel") then
				Robux.showPrice(price, false, entry.Key)
			end
		else
			Kit.setPrice(card, "Soon", nil)
		end
	end

	Interface.bindButton(card, function()
		buy(entry)
	end, 0.97, 0.93)

	if entry.Key == "LuckyRoll" then
		local odds = Kit.button("Blue", "Odds")
		odds.Name = "Odds"
		odds.AnchorPoint = Vector2.new(0, 1)
		odds.Position = UDim2.fromScale(0.04, 0.94)
		odds.Size = UDim2.fromScale(0.24, 0.24)
		odds.ZIndex = 10
		for _, child in odds:GetDescendants() do
			if child:IsA("GuiObject") then
				child.ZIndex += 10
			end
		end
		odds.Parent = card
		Interface.bindButton(odds, function()
			Interface.open("Odds")
		end, 0.92, 0.85)
	end
	return card
end

local function rebuild()
	Kit.list(items)
	table.clear(passCards)
	clubClaim = nil

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	for _, section in Products.Sections do
		local entries = entriesFor(section.Id)
		if #entries > 0 then
			Kit.header(items, section.Title, nextOrder())
			local wide = section.Id == "Passes" or section.Id == "Featured" or section.Id == "Club"
			if wide then
				for _, entry in entries do
					Kit.row(items, makeCard(entry), 2.6, nextOrder())
				end
				-- Members: today's club bundle.
				if section.Id == "Club" and member() then
					local claim = Kit.card({
						Title = "Daily Club Bundle",
						Description = Format.reward(Config.Club.Daily),
						Icon = "🎁",
						Color = "Green",
					})
					clubClaim = claim
					Interface.bindButton(claim, claimClub, 0.97, 0.93)
					Kit.row(items, claim, 2.6, nextOrder())
					updateClubClaim()
				end
			else
				local row: Frame? = nil
				for i, entry in entries do
					if (i - 1) % 2 == 0 then
						row = Kit.gridRow(2)
						Kit.row(items, row :: Frame, 4.6, nextOrder())
					end
					Kit.addCell(row :: Frame, makeCard(entry), i)
				end
			end
		end
	end
end

function ShopMenu.start()
	Interface.setup()
	local window = Interface.window(MENU)
	items = window:WaitForChild("Main"):WaitForChild("Items") :: ScrollingFrame

	Interface.MenuOpened:Connect(function(name)
		if name == MENU then
			rebuild()
		end
	end)

	State.Changed:Connect(function(field)
		if field == "Passes" then
			for key, card in passCards do
				setPassPrice(card, key)
			end
			if Interface.isOpen(MENU) and (member() ~= (clubClaim ~= nil)) then
				rebuild() -- joined or left the club
			end
		elseif (field == "Bought" or field == "Milestones") and Interface.isOpen(MENU) then
			rebuild()
		elseif field == "ClubClaimDay" then
			updateClubClaim()
		end
	end)
end

return ShopMenu
