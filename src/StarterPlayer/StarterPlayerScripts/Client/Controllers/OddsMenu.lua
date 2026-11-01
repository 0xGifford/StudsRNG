--[[

OddsMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/OddsMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The Luck & Odds window (Odds button on the shop's Lucky Roll card): how
-- luck works, the player's current luck, and every stud's odds now and with
-- one more Lucky Roll.
--
-- Rolls check studs rarest-first; a stud with odds "1 in X" hits with chance
-- luck / X. Flat luck (Lucky Rolls, Luck boosts) is added before every
-- multiplier, so +1 Lucky Roll is worth more the more multipliers you have.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Studs = require(Shared.Studs)
local Zones = require(Shared.Zones)
local Types = require(Shared.Types)
local RollLogic = require(Shared.Util.RollLogic)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Kit = require(UI.Kit)
local Format = require(UI.Format)

type StudDef = Types.StudDef

local OddsMenu = {}

local MENU = "Odds"

local items: ScrollingFrame

local sortedStuds: { StudDef } = table.clone(Studs.List)
table.sort(sortedStuds, function(a, b)
	return a.OneIn < b.OneIn
end)

-- Base luck before multipliers: 1 + Lucky Rolls + active Luck boosts.
local function flatLuck(): number
	local base = Config.Rolls.BaseLuck + (State.get("LuckyRolls") or 0)
	local now = State.serverNow()
	for id, ends in State.get("BoostEnds") or {} do
		local boost = Config.Boosts[id]
		if boost and boost.Luck and typeof(ends) == "number" and ends > now then
			base += boost.Luck
		end
	end
	return base
end

local function luckText(value: number): string
	local text = string.format("%.2f", value)
	text = string.gsub(text, "%.?0+$", "")
	return text
end

-- A copy of StarterGui.Templates.OddsRow, cells filled left to right.
local function oddsRow(cells: { string }, colors: { Color3 }?, order: number)
	local row = Kit.template("OddsRow") :: Frame
	row.Name = "Row"
	for _, cell in row:GetDescendants() do
		local index = cell:GetAttribute("OddsCell")
		if typeof(index) == "number" and cell:IsA("TextLabel") then
			cell.Text = cells[index] or ""
			if colors and colors[index] then
				cell.TextColor3 = colors[index]
			end
		end
	end
	Kit.row(items, row, 13, order)
end

local function rebuild()
	Kit.list(items)
	local stats = State.stats()
	local flat = flatLuck()
	local multipliers = stats.Luck / math.max(flat, 1e-6)
	local withLuckyRoll = (flat + 1) * multipliers
	local unlocked = State.get("UnlockedWorlds") or {}

	Kit.header(items, "How luck works", 1)
	Kit.paragraph(items, table.concat({
		"Every roll checks studs from rarest to most common. A stud shown as <b>1 in X</b> hits with chance <b>Luck ÷ X</b>, so 2 luck makes every stud twice as likely.",
		"Lucky Rolls and Luck boosts add to your <b>base luck</b>, before rebirth, upgrade, VIP, server and event multipliers. That makes each +1 worth more the more multipliers you have.",
		`Your luck: <b>{luckText(stats.Luck)}</b> = base {luckText(flat)} × multipliers {luckText(multipliers)}. One more Lucky Roll: <b>{luckText(withLuckyRoll)}</b>.`,
	}, "\n\n"), 2)

	Kit.header(items, "Stud odds", 3)
	oddsRow({ "Stud", "Base", "You", "+1 Lucky Roll" }, nil, 4)
	for index, def in sortedStuds do
		if def.Drop then continue end -- boss drops never roll
		local rarity = Config.Rarities.Colors[def.Rarity] or Color3.new(1, 1, 1)
		local locked = not unlocked[def.World]
		local zone = Zones.ById[def.World]
		local you = if locked then `🔒 {if zone then zone.Name else def.World}` else Format.oneIn(RollLogic.displayOneIn(def.OneIn, stats.Luck))
		local withRoll = if locked then "-" else Format.oneIn(RollLogic.displayOneIn(def.OneIn, withLuckyRoll))
		oddsRow({ def.Name, Format.oneIn(def.OneIn), you, withRoll }, { rarity }, 4 + index)
	end
end

function OddsMenu.start()
	Interface.setup()
	local window = Interface.window(MENU)
	items = window:WaitForChild("Main"):WaitForChild("Items") :: ScrollingFrame

	Interface.MenuOpened:Connect(function(name)
		if name == MENU then
			rebuild()
		end
	end)
end

return OddsMenu
