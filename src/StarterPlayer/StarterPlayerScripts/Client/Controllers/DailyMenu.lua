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
-- (Rewards.dailyReward), shown under the days with the streak length, the
-- Grace Day (one missed day a week is forgiven) and the welcome-back bonus
-- after a lost streak. Opens by itself on join when today's reward is waiting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RewardDefs = require(Shared.Rewards)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Roles = require(UI.Roles)
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

-- The streak as of the next claim: full weeks kept (they boost the
-- rewards), consecutive days, whether it uses the Grace Day, and whether
-- the welcome-back bonus applies.
local function nextClaim(): RewardDefs.ClaimInfo
	local state = State.get("Daily")
	local canClaim = RewardDefs.dailyState(state, today())
	if canClaim then
		local _, info = RewardDefs.afterClaim(state, today())
		return info
	end
	local recovery = if typeof(state) == "table" and typeof(state.Recovery) == "number" then state.Recovery else 0
	return {
		Day = 0,
		Weeks = if typeof(state) == "table" and typeof(state.Weeks) == "number" then state.Weeks else 0,
		Days = RewardDefs.days(state),
		Graced = false,
		Recovery = recovery > 0,
	}
end

local function shownReward(index: number): { [string]: any }
	local info = nextClaim()
	local reward = RewardDefs.dailyReward(index, info.Weeks, info.Recovery)
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
		local info = nextClaim()
		local state = State.get("Daily")
		local parts = {}
		if info.Recovery then
			table.insert(parts, `💖 Welcome back: x{RewardDefs.Recovery.Multiplier} rewards!`)
		end
		if info.Weeks > 0 then
			table.insert(parts, `🔥 {info.Days} day streak: x{RewardDefs.weekMultiplier(info.Weeks)} Clacks & Rolls`)
		else
			table.insert(parts, `🔥 Keep a full week for x{RewardDefs.weekMultiplier(1)} rewards!`)
		end
		if info.Graced then
			table.insert(parts, "🛟 Grace Day saved your streak")
		elseif RewardDefs.graceReady(state, today()) then
			table.insert(parts, "🛟 Grace Day ready")
		end
		weekLabel.Text = table.concat(parts, "  ·  ")
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
		if response.Graced then
			Interface.toast("🛟 Grace Day used: your streak lives on!", Color3.fromRGB(120, 200, 255))
		elseif response.Recovery then
			Interface.toast(`💖 Welcome back! x{RewardDefs.Recovery.Multiplier} daily rewards`, Color3.fromRGB(255, 140, 200))
		end
		if typeof(response.Days) == "number" and response.Days > 1 and response.Days % 7 == 0 then
			Juice.banner(`{response.Days} DAY STREAK!`, "Keep it going!", Color3.fromRGB(255, 150, 60), 2)
		end
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
	local window = Interface.window(MENU)
	local main = window:WaitForChild("Main")
	local folder = main:WaitForChild("Days")

	-- Week streak line under the days (DailyRole = "WeekStreak").
	local label = Roles.find(window, "DailyRole", "WeekStreak")
	if not label then
		warn('[DailyMenu] the Daily window has no label with DailyRole = "WeekStreak" (run tools/ui/migrate.luau on your place)')
	end
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
