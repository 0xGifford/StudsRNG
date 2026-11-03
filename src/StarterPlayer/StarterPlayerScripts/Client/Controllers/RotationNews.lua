--[[

RotationNews
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/RotationNews

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Tells players which zones are boosted (Shared/ZoneRotation): a toast with
-- today's Favoured zones and this week's Vintage ones a little after
-- joining, and a banner when the day rolls over while they play. The zone
-- title card (ZoneAmbience) and the Teleporter rows show it too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Zones = require(Shared.Zones)
local ZoneRotation = require(Shared.ZoneRotation)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Juice = require(UI.Juice)

local RotationNews = {}

local FAVOURED_COLOR = Color3.fromRGB(255, 205, 90)
local VINTAGE_COLOR = Color3.fromRGB(200, 170, 255)

local function names(ids: { string }): string
	local list = {}
	for _, id in ids do
		local def = Zones.ById[id]
		if def then
			table.insert(list, def.Name)
		end
	end
	return table.concat(list, " & ")
end

local function favouredText(now: number): string
	local f = Config.ZoneRotation.Favoured
	return `🌟 Favoured today: {names(ZoneRotation.favoured(now))} (x{f.Luck} luck, x{f.Clacks} Clacks, Prismatic rolls)`
end

local function vintageText(now: number): string
	local v = Config.ZoneRotation.Vintage
	return `🕰️ Vintage this week: {names(ZoneRotation.vintage(now))} (x{v.Luck} luck, x{v.Clacks} Clacks)`
end

function RotationNews.start()
	Interface.setup()
	if not State.isReady() then
		State.Ready:Wait()
	end
	Interface.waitForLoadingScreen()
	task.wait(8)
	local now = State.serverNow()
	Interface.toast(favouredText(now), FAVOURED_COLOR)
	task.wait(3)
	Interface.toast(vintageText(now), VINTAGE_COLOR)

	-- New day while playing: new Favoured zones.
	local day = ZoneRotation.day(State.serverNow())
	while true do
		task.wait(math.clamp(ZoneRotation.untilNextDay(State.serverNow()) + 1, 1, 60))
		local today = ZoneRotation.day(State.serverNow())
		if today ~= day then
			day = today
			Juice.banner("NEW FAVOURED ZONES!", names(ZoneRotation.favoured(State.serverNow())), FAVOURED_COLOR, 2.4)
			Interface.toast(favouredText(State.serverNow()), FAVOURED_COLOR)
		end
	end
end

return RotationNews
