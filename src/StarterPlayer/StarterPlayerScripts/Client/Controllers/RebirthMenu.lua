--[[

RebirthMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/RebirthMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The Rebirth window: current → next Clacks multiplier, progress towards the
-- cost, Rebirth (Clacks) and Skip (Robux, SkipRebirth product).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Upgrades = require(Shared.Upgrades)
local RollLogic = require(Shared.Util.RollLogic)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Format = require(UI.Format)
local Robux = require(UI.Robux)

local RebirthMenu = {}

local MENU = "Rebirth"

local main: Instance
local pending = false

local function multiplierText(value: number): string
	return `{Format.multiplier(value)} Clacks`
end

local function render()
	local rebirths = State.get("Rebirths") or 0
	local clacks = State.get("Clacks") or 0
	local cost = RollLogic.rebirthCost(rebirths)
	local perRebirth = Config.Rebirth.ClacksPerRebirth + (Upgrades.totals(State.get("Upgrades")).RebirthBonus or 0)

	local fromTitle = main:FindFirstChild("FromTitle")
	local toTitle = main:FindFirstChild("ToTitle")
	if fromTitle and fromTitle:IsA("TextLabel") then fromTitle.Text = `Rebirth {rebirths}` end
	if toTitle and toTitle:IsA("TextLabel") then toTitle.Text = `Rebirth {rebirths + 1}` end

	local from = main:FindFirstChild("From")
	local to = main:FindFirstChild("To")
	if from then Interface.setText(from, multiplierText(1 + rebirths * perRebirth)) end
	if to then Interface.setText(to, multiplierText(1 + (rebirths + 1) * perRebirth)) end

	local info = main:FindFirstChild("Info")
	if info then
		local luck = math.floor(Config.Rebirth.LuckPerRebirth * 100 + 0.5)
		local resets = if Config.Rebirth.ResetZones then "Clacks & zones" else "Clacks"
		Interface.setText(info, `Resets {resets}, keeps studs & upgrades. +{luck}% luck!`)
		local progress = info:FindFirstChild("Progress")
		local bar = progress and progress:FindFirstChild("Bar")
		if progress and bar and bar:IsA("GuiObject") then
			local fraction = math.clamp(clacks / cost, 0, 1)
			TweenService:Create(bar, Interface.FAST, { Size = UDim2.fromScale(fraction, 1) }):Play()
			local amount = progress:FindFirstChild("Amount")
			if amount and amount:IsA("TextLabel") then
				amount.Text = `Clacks: {Format.number(clacks)}/{Format.number(cost)}`
			end
		end
	end
end

local function rebirth()
	if pending then return end
	local cost = RollLogic.rebirthCost(State.get("Rebirths") or 0)
	if (State.get("Clacks") or 0) < cost then
		Interface.toast(`You need {Format.number(cost)} Clacks to rebirth`, Color3.fromRGB(255, 110, 110))
		return
	end
	pending = true
	local response = State.rebirth()
	pending = false
	Interface.toastError(response)
end

function RebirthMenu.start()
	Interface.setup()
	local window = Interface.Canva:WaitForChild(MENU)
	main = window:WaitForChild("Main")

	local buy = main:WaitForChild("Buy")
	local normal = buy:FindFirstChild("Normal")
	if normal and normal:IsA("GuiObject") then
		Interface.bindButton(normal, rebirth, 0.95, 0.85)
	end
	local robux = buy:FindFirstChild("Robux")
	if robux and robux:IsA("GuiObject") then
		local price = robux:FindFirstChild("Price")
		if price and price:IsA("TextLabel") then
			Robux.showPrice(price, false, "SkipRebirth")
		end
		local icon = robux:FindFirstChild("Robux")
		if icon and icon:IsA("GuiObject") then
			icon.Visible = Robux.available(false, "SkipRebirth")
		end
		Interface.bindButton(robux, function()
			if not Robux.prompt(false, "SkipRebirth") then
				Interface.toast("Coming soon!")
			end
		end, 0.95, 0.85)
	end

	Interface.MenuOpened:Connect(function(name)
		if name == MENU then
			render()
		end
	end)
	State.Changed:Connect(function(field)
		if Interface.isOpen(MENU) and (field == "Clacks" or field == "Rebirths" or field == "Upgrades") then
			render()
		end
	end)
end

return RebirthMenu
