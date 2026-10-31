--[[

DailyMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/DailyMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The 7-day streak (Daily window, opened from the HUD's Daily Rewards
-- label). Claim once per UTC day; missing a day restarts at Day 1; Day 7
-- loops back to Day 1. Past days show Claimed, future days are locked, and
-- the next day counts down to the reset. Day 7 is a jackpot bundle (its
-- mega roll plays the roll reel); every full week kept boosts the rewards
-- (Rewards.dailyReward), shown under the days. Opens by itself on join when
-- today's reward is waiting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RewardDefs = require(Shared.Rewards)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Kit = require(UI.Kit)
local Format = require(UI.Format)
local UIConfig = require(UI.UIConfig)
local Juice = require(UI.Juice)
local RollReveal = require(Controllers.RollReveal)

local DailyMenu = {}

local MENU = "Daily"

local days: { [number]: Frame } = {}
local pending = false
local weekLabel: TextLabel? = nil

local function today(): number
	return RewardDefs.dayNumber(State.serverNow())
end

-- Full weeks kept as of the next claim (that's what boosts the rewards).
local function weeksForNextClaim(): number
	local state = State.get("Daily")
	local canClaim, day = RewardDefs.dailyState(state, today())
	if canClaim then
		return RewardDefs.weeksAfterClaim(state, today(), day)
	end
	return if typeof(state) == "table" and typeof(state.Weeks) == "number" then state.Weeks else 0
end

local function shownReward(index: number): { [string]: any }
	local reward = RewardDefs.dailyReward(index, weeksForNextClaim())
	local shown: { [string]: any } = { Kind = reward.Kind, Amount = reward.Amount, Boost = reward.Boost, Minutes = reward.Minutes, Items = reward.Items }
	if reward.Kind == "Clacks" then
		shown.Amount = math.floor(reward.Amount * RewardDefs.scale({
			Rebirths = State.get("Rebirths"),
			UnlockedWorlds = State.get("UnlockedWorlds"),
		}))
	end
	return shown
end

local function setOverlay(frame: Frame, name: string, on: boolean)
	local overlay = frame:FindFirstChild(name)
	if overlay and overlay:IsA("GuiObject") then
		overlay.Visible = on
	end
end

local function render()
	local canClaim, day = RewardDefs.dailyState(State.get("Daily"), today())
	local secondsLeft = (today() + 1) * RewardDefs.DaySeconds - State.serverNow()
	local nextDay = if canClaim then day else day % #RewardDefs.Daily + 1

	for index, frame in days do
		local claimed = if canClaim then index < day else index <= day
		local isNext = index == nextDay
		setOverlay(frame, "Claimed", claimed and not (isNext and not canClaim))
		setOverlay(frame, "Lock", not claimed and not (canClaim and index == day))

		local top = frame:FindFirstChild("Top")
		if top then
			local text = `Day {index}`
			if canClaim and index == day then
				text = "Claim!"
			elseif not canClaim and isNext then
				text = Format.duration(secondsLeft)
			end
			Interface.setText(top, text)
		end
	end

	if weekLabel then
		local weeks = weeksForNextClaim()
		weekLabel.Text = if weeks > 0
			then `🔥 Week {weeks + 1} streak: x{RewardDefs.weekMultiplier(weeks)} Clacks & Rolls`
			else `🔥 Keep a full week for x{RewardDefs.weekMultiplier(1)} rewards next week!`
	end
end

local function setup()
	for index, frame in days do
		if RewardDefs.Daily[index] then
			frame.Visible = true
			local shown = shownReward(index)
			Interface.setText(frame, Format.reward(shown))
			local icon = frame:FindFirstChild("Icon")
			if icon and icon:IsA("ImageLabel") then
				Kit.setIcon(icon, UIConfig.Icons[shown.Kind] or UIConfig.Icons.Clacks)
			end
		else
			frame.Visible = false
		end
	end
	render()
end

local function onDay(index: number)
	if pending then return end
	local canClaim, day = RewardDefs.dailyState(State.get("Daily"), today())
	if not canClaim or index ~= day then
		if canClaim then
			Interface.toast(`Claim Day {day} first!`)
		else
			local secondsLeft = (today() + 1) * RewardDefs.DaySeconds - State.serverNow()
			Interface.toast(`Come back in {Format.duration(secondsLeft)}!`)
		end
		return
	end
	pending = true
	local response = State.claimDaily()
	pending = false
	if response.Ok and response.Reward then
		Interface.toast(`Day {response.Day}: {Format.reward(response.Reward)}`, Color3.fromRGB(120, 255, 140))
		local frame = days[index]
		if frame then
			Juice.pop(frame, 1.2)
			Juice.confetti(50, frame.AbsolutePosition + frame.AbsoluteSize / 2)
		end
		-- Day 7: the jackpot.
		if response.Reward.Kind == "Bundle" then
			Juice.banner("DAY 7 JACKPOT!", Format.reward(response.Reward), Color3.fromRGB(255, 205, 60), 2)
			Juice.confetti(140)
			Juice.shake(0.6, 0.4)
		end
		if typeof(response.Reward.Results) == "table" then
			Interface.close(MENU)
			RollReveal.showResults(response.Reward.Results)
		end
	else
		Interface.toastError(response)
	end
	render()
end

function DailyMenu.start()
	Interface.setup()
	local window = Interface.Canva:WaitForChild(MENU)
	local main = window:WaitForChild("Main")
	local folder = main:WaitForChild("Days")

	-- Week streak line under the days.
	local label = Instance.new("TextLabel")
	label.Name = "WeekStreak"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 1.01)
	label.Size = UDim2.fromScale(0.9, 0.07)
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 170, 60)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(15, 15, 20)
	stroke.Parent = label
	label.Parent = main
	weekLabel = label
	for _, child in folder:GetChildren() do
		local index = tonumber(child.Name)
		if index and child:IsA("Frame") then
			days[index] = child
			Interface.bindButton(child, function()
				onDay(index)
			end, 0.95, 0.88)
		end
	end

	Interface.MenuOpened:Connect(function(name)
		if name == MENU then
			setup()
		end
	end)
	State.Changed:Connect(function(field)
		if field == "Daily" and Interface.isOpen(MENU) then
			render()
		end
	end)

	-- Today's reward is waiting: open by itself once, after the first-join
	-- intro, when nothing else is open.
	task.spawn(function()
		if not State.isReady() then
			State.Ready:Wait()
		end
		Interface.waitForLoadingScreen()
		task.wait(5)
		if not State.get("SeenIntro") then return end
		local canClaim = RewardDefs.dailyState(State.get("Daily"), today())
		if canClaim and not Interface.isOpen() then
			Interface.open(MENU)
		end
	end)

	while true do
		task.wait(1)
		if Interface.isOpen(MENU) then
			render()
		end
	end
end

return DailyMenu
