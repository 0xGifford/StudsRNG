--[[

EventsHud
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/EventsHud

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Bottom-right timers. HUD.Events.Started lists everything running (the
-- global event, Server Luck, your boosts) as Templates.Events icons with a
-- countdown; HUD.Events.NextEvent shows when the next global event starts.
-- Server-wide timers come from ReplicatedStorage attributes set by
-- Systems/ServerEffects; boosts from the "BoostEnds" state field.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local RollLogic = require(Shared.Util.RollLogic)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Kit = require(UI.Kit)
local Format = require(UI.Format)
local UIConfig = require(UI.UIConfig)

local EventsHud = {}

type Timer = { Key: string, Title: string, Ends: number, Icon: string, Color: Color3, Order: number }

local started: Frame
local nextEvent: Frame?
local cells: { [string]: Frame } = {}

local function attr(name: string): any
	return ReplicatedStorage:GetAttribute(name)
end

local function activeTimers(now: number): { Timer }
	local timers: { Timer } = {}

	local eventId = attr("EventId")
	local eventEnds = attr("EventEnds")
	if typeof(eventId) == "string" and eventId ~= "" and typeof(eventEnds) == "number" and eventEnds > now then
		local def = RollLogic.eventById(eventId)
		if def then
			table.insert(timers, { Key = "Event", Title = def.Name, Ends = eventEnds,
				Icon = UIConfig.Icons.Event, Color = def.Color, Order = 1 })
		end
	end

	local luckEnds = attr("ServerLuckEnds")
	if typeof(luckEnds) == "number" and luckEnds > now then
		table.insert(timers, { Key = "ServerLuck", Title = `Server x{Config.ServerLuck.Multiplier}`, Ends = luckEnds,
			Icon = UIConfig.Icons.ServerLuck, Color = Color3.fromRGB(120, 255, 140), Order = 2 })
	end

	local boostEnds = State.get("BoostEnds") or {}
	for order, id in Config.BoostOrder do
		local ends = boostEnds[id]
		local def = Config.Boosts[id]
		if def and typeof(ends) == "number" and ends > now then
			table.insert(timers, { Key = `Boost:{id}`, Title = def.Short, Ends = ends,
				Icon = UIConfig.Icons.Boost, Color = def.Color, Order = 10 + order })
		end
	end
	return timers
end

local function makeCell(timer: Timer): Frame
	local cell = Kit.template("Events") :: Frame
	cell.Name = timer.Key
	cell.LayoutOrder = timer.Order
	local icon = cell:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		Kit.setIcon(icon, timer.Icon)
		icon.ImageColor3 = timer.Color
	end

	-- A small name above the icon, styled like the timer.
	local amount = cell:FindFirstChild("Amount")
	if amount and amount:IsA("TextLabel") then
		local title = amount:Clone()
		title.Name = "Title"
		title.Text = timer.Title
		title.Position = UDim2.fromScale(0.5, 0.1)
		title.Size = UDim2.fromScale(1.3, 0.3)
		title.TextColor3 = timer.Color
		title.Parent = cell
	end
	cell.Parent = started
	return cell
end

local function refresh()
	local now = State.serverNow()
	local timers = activeTimers(now)

	local alive: { [string]: boolean } = {}
	for _, timer in timers do
		alive[timer.Key] = true
		local cell = cells[timer.Key]
		if not cell then
			cell = makeCell(timer)
			cells[timer.Key] = cell
		end
		Interface.setText(cell, Format.duration(timer.Ends - now), "Amount", "AmountShadow")
	end
	for key, cell in cells do
		if not alive[key] then
			cell:Destroy()
			cells[key] = nil
		end
	end

	local frame = nextEvent
	if frame then
		local eventId = attr("EventId")
		local def = if typeof(eventId) == "string" then RollLogic.eventById(eventId) else nil
		local ends = attr("EventEnds")
		local nextAt = attr("NextEventAt")
		local text: string
		if def and typeof(ends) == "number" and ends > now then
			text = `{def.Name}! Ends In: {Format.duration(ends - now)}`
		elseif typeof(nextAt) == "number" then
			text = `Next Event In: {Format.duration(nextAt - now)}`
		else
			text = ""
		end
		Interface.setText(frame, text, "Timer", "TimerShadow")
	end
end

function EventsHud.start()
	Interface.setup()
	local events = Interface.HUD:WaitForChild("Events")
	started = events:WaitForChild("Started") :: Frame
	local nextFrame = events:FindFirstChild("NextEvent")
	nextEvent = if nextFrame and nextFrame:IsA("Frame") then nextFrame else nil

	State.Changed:Connect(function(field)
		if field == "BoostEnds" then
			refresh()
		end
	end)

	while true do
		if State.isReady() then
			refresh()
		end
		task.wait(0.25)
	end
end

return EventsHud
