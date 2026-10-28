--[[

RewardsMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/RewardsMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Playtime rewards (Rewards window): the 12 kit slots count down this
-- session's playtime; tap a ready one to claim it. Skip All (Robux) claims
-- every remaining reward. Leaving the game resets progress.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RewardDefs = require(Shared.Rewards)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Kit = require(UI.Kit)
local Format = require(UI.Format)
local Robux = require(UI.Robux)
local UIConfig = require(UI.UIConfig)

local RewardsMenu = {}

local MENU = "Rewards"
local READY = Color3.fromRGB(120, 255, 140)
local WAITING = Color3.new(1, 1, 1)

local slots: { [number]: Frame } = {}
local pending = false

local function scaledReward(reward: any): { [string]: any }
	local shown: { [string]: any } = { Kind = reward.Kind, Amount = reward.Amount, Boost = reward.Boost, Minutes = reward.Minutes }
	if reward.Kind == "Clacks" then
		shown.Amount = math.floor(reward.Amount * RewardDefs.scale({
			Rebirths = State.get("Rebirths"),
			UnlockedWorlds = State.get("UnlockedWorlds"),
		}))
	end
	return shown
end

local function playtime(): (number, { [number]: boolean })
	local state = State.get("Playtime")
	if typeof(state) ~= "table" then
		return 0, {}
	end
	return State.serverNow() - state.Start, state.Claimed or {}
end

local function render()
	local elapsed, claimed = playtime()
	for index, slot in slots do
		local reward = RewardDefs.Playtime[index]
		local timer = slot:FindFirstChild("Timer")
		if reward and timer and timer:IsA("TextLabel") then
			local left = reward.At * 60 - elapsed
			if claimed[index] then
				timer.Text = "Claimed"
				timer.TextColor3 = WAITING
			elseif left <= 0 then
				timer.Text = "Claim!"
				timer.TextColor3 = READY
			else
				timer.Text = Format.duration(left)
				timer.TextColor3 = WAITING
			end
			-- Claimed rewards stay claimed for the session: dim them.
			local icon = slot:FindFirstChild("Icon")
			if claimed[index] and icon and icon:IsA("ImageLabel") then
				local emoji = icon:FindFirstChild("Emoji")
				if emoji and emoji:IsA("TextLabel") then
					emoji.TextTransparency = 0.6
				else
					icon.ImageTransparency = 0.6
				end
			end
		end
	end
end

local function setup()
	for index, slot in slots do
		local reward = RewardDefs.Playtime[index]
		if reward then
			slot.Visible = true
			local shown = scaledReward(reward)
			Interface.setText(slot, Format.reward(shown))
			local icon = slot:FindFirstChild("Icon")
			if icon and icon:IsA("ImageLabel") then
				Kit.setIcon(icon, UIConfig.Icons[reward.Kind] or UIConfig.Icons.Clacks)
			end
		else
			slot.Visible = false
		end
	end
	render()
end

local function claim(index: number)
	if pending then return end
	local elapsed, claimed = playtime()
	local reward = RewardDefs.Playtime[index]
	if not reward or claimed[index] then return end
	if elapsed < reward.At * 60 then
		Interface.toast(`Ready in {Format.duration(reward.At * 60 - elapsed)}`)
		return
	end
	pending = true
	local response = State.claimPlaytime(index)
	pending = false
	if response.Ok and response.Reward then
		Interface.toast(Format.reward(response.Reward), READY)
	else
		Interface.toastError(response)
	end
end

function RewardsMenu.start()
	Interface.setup()
	local window = Interface.Canva:WaitForChild(MENU)
	local main = window:WaitForChild("Main")
	local items = main:WaitForChild("Items")

	for _, child in items:GetChildren() do
		local index = tonumber(child.Name)
		if index and child:IsA("Frame") then
			slots[index] = child
			Interface.bindButton(child, function()
				claim(index)
			end, 0.95, 0.88)
		end
	end

	local skip = main:FindFirstChild("Skip")
	if skip and skip:IsA("GuiObject") then
		local price = skip:FindFirstChild("Price")
		if price and price:IsA("TextLabel") then
			Robux.showPrice(price, false, "SkipPlaytime")
		end
		local icon = skip:FindFirstChild("Robux")
		if icon and icon:IsA("GuiObject") then
			icon.Visible = Robux.available(false, "SkipPlaytime")
		end
		Interface.bindButton(skip, function()
			if not Robux.prompt(false, "SkipPlaytime") then
				Interface.toast("Coming soon!")
			end
		end, 0.95, 0.85)
	end

	Interface.MenuOpened:Connect(function(name)
		if name == MENU then
			setup()
		end
	end)
	State.Changed:Connect(function(field)
		if field == "Playtime" and Interface.isOpen(MENU) then
			render()
		end
	end)

	while true do
		task.wait(1)
		if Interface.isOpen(MENU) then
			render()
		end
	end
end

return RewardsMenu
