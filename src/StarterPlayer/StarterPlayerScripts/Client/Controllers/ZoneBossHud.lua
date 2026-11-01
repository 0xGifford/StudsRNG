--[[

ZoneBossHud
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/ZoneBossHud

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The client side of Zone Bosses (Systems/Combat, Config.ZoneBoss):
--   * a chip under the top bar counting down to the next Titans ("👹 TITANS
--     IN 12:34"), or the time left while they're out
--   * banners: the warning, the spawn, your placing, escapes
--   * near a Titan (or a Mega Boss): a raid panel (top right) with its
--     health, time left, the live damage leaderboard (top 5) and your rank
--
-- The chip and panel are StarterGui.ZoneBoss (tools/ui/screens/ZoneBoss.luau),
-- found by BossRole: Chip, Panel, Name, Time, Fill, Hp, Mine, and Row with
-- BossRow = 1..5.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Tags = require(Shared.Tags)
local Zones = require(Shared.Zones)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Format = require(UI.Format)
local Juice = require(UI.Juice)
local CombatFx = require(UI.CombatFx)
local Roles = require(UI.Roles)

local ZoneBossHud = {}

local RED = Color3.fromRGB(255, 70, 60)
local GOLD = Color3.fromRGB(255, 205, 60)
local PANEL_RANGE = 220 -- studs: the raid panel shows within this of a Titan

local player = Players.LocalPlayer
local settings = Config.ZoneBoss

local gui: ScreenGui
local chip: TextLabel
local panel: GuiObject
local panelName: TextLabel
local panelFill: GuiObject
local panelHp: TextLabel
local panelTime: TextLabel
local rows: { TextLabel } = {}
local mineRow: TextLabel

-- Latest "Board" per Titan id.
type Board = { Name: string, Board: { { Name: string, Damage: number } }, Mine: number, Rank: number?, Left: number, At: number }
local boards: { [number]: Board } = {}

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function milestoneNames(): string
	local names = {}
	for _, def in Zones.List do
		if def.Order % settings.Every == 0 then
			table.insert(names, def.Name)
		end
	end
	return table.concat(names, ", ")
end

--------------------------------------------------------------------------
-- Gui
--------------------------------------------------------------------------

local function bind()
	gui = Roles.gui("ZoneBoss")
	chip = Roles.get(gui, "BossRole", "Chip")
	panel = Roles.get(gui, "BossRole", "Panel")
	panelName = Roles.get(gui, "BossRole", "Name")
	panelTime = Roles.get(gui, "BossRole", "Time")
	panelFill = Roles.get(gui, "BossRole", "Fill")
	panelHp = Roles.get(gui, "BossRole", "Hp")
	mineRow = Roles.get(gui, "BossRole", "Mine")
	for _, d in gui:GetDescendants() do
		local index = d:GetAttribute("BossRow")
		if d:GetAttribute("BossRole") == "Row" and typeof(index) == "number" and d:IsA("TextLabel") then
			rows[index] = d
		end
	end
	panel.Visible = false

	-- Shrink the panel on narrow screens (towards its anchor: top right stays put).
	local scale = panel:FindFirstChildOfClass("UIScale")
	if scale then
		local function fit()
			scale.Scale = math.clamp(gui.AbsoluteSize.X / 1100, 0.6, 1)
		end
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
	end
end

-- The nearest Titan within PANEL_RANGE.
local function nearestTitan(): Model?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then return nil end
	local best: Model?, bestDistance = nil, PANEL_RANGE
	for _, instance in CollectionService:GetTagged(Tags.Enemy) do
		if instance:IsA("Model") and (instance:GetAttribute("ZoneBoss") == true or instance:GetAttribute("MegaBoss") == true) then
			local body = instance.PrimaryPart or instance:FindFirstChild("Body")
			if body and body:IsA("BasePart") then
				local distance = (body.Position - root.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = instance, distance
				end
			end
		end
	end
	return best
end

local function updatePanel()
	local titan = nearestTitan()
	if not titan then
		panel.Visible = false
		return
	end
	panel.Visible = true
	panelName.Text = `👹 {string.upper(titan.Name)}`
	local health = titan:GetAttribute("Health")
	local max = titan:GetAttribute("MaxHealth")
	if typeof(health) == "number" and typeof(max) == "number" and max > 0 then
		local share = math.clamp(health / max, 0, 1)
		TweenService:Create(panelFill, TweenInfo.new(0.2), { Size = UDim2.fromScale(share, 1) }):Play()
		panelHp.Text = `{Format.number(math.max(0, health))} / {Format.number(max)}`
	end

	local id = titan:GetAttribute("EnemyId")
	local board = if typeof(id) == "number" then boards[id] else nil
	if board then
		local left = board.Left - (os.clock() - board.At)
		panelTime.Text = `⏱ {clock(left)}`
		panelTime.TextColor3 = if left < 30 then RED else Color3.fromRGB(255, 220, 200)
		for i, row in rows do
			local entry = board.Board[i]
			if entry then
				row.Text = `#{i}  {entry.Name}  ·  {Format.number(entry.Damage)}`
				row.TextColor3 = if i == 1 then GOLD elseif entry.Name == player.DisplayName then Color3.fromRGB(120, 255, 140) else Color3.new(1, 1, 1)
			else
				row.Text = ""
			end
		end
		mineRow.Text = if board.Rank then `You: #{board.Rank} · {Format.number(board.Mine)} damage` else "Hit it to get on the board!"
	else
		panelTime.Text = ""
		for _, row in rows do
			row.Text = ""
		end
		mineRow.Text = "Hit it to get on the board!"
	end
end

-- Next spawn time, and whether Titans are (probably) out right now.
local function updateChip()
	local now = State.serverNow()
	local slot = math.floor(now / settings.Interval)
	local since = now - slot * settings.Interval
	local anyTitan = false
	for _, instance in CollectionService:GetTagged(Tags.Enemy) do
		if instance:GetAttribute("ZoneBoss") == true then
			anyTitan = true
			break
		end
	end
	if anyTitan and since < settings.Lifetime then
		chip.Text = `👹 TITANS OUT · {clock(settings.Lifetime - since)}`
		chip.TextColor3 = RED
	else
		local untilNext = settings.Interval - since
		chip.Text = `👹 TITANS IN {clock(untilNext)}`
		chip.TextColor3 = if untilNext <= settings.Warning then RED else Color3.new(1, 1, 1)
	end
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------

local function onEvent(payload: any)
	if typeof(payload) ~= "table" then return end
	local phase = payload.Phase
	if phase == "Warning" then
		Juice.banner("TITANS INCOMING!", `Zone Bosses in {payload.In or settings.Warning}s · {milestoneNames()}`, RED, 2)
		CombatFx.sound("Aggro", nil, 0.7, 0.6)
		Juice.pop(chip, 1.4)
	elseif phase == "Spawn" then
		local names = if typeof(payload.Zones) == "table" then table.concat(payload.Zones, ", ") else ""
		if payload.Mega then
			Juice.banner("A MEGA BOSS HAS APPEARED!", `{names} · everyone together!`, Color3.fromRGB(190, 110, 255), 2.6)
		else
			Juice.banner("THE TITANS HAVE ARRIVED!", `{names} · teleport in and fight together!`, RED, 2.4)
		end
		Juice.shake(0.8, 0.5)
		CombatFx.sound("Explode", nil, 0.45, 0.8)
	elseif phase == "Board" then
		if typeof(payload.Id) == "number" then
			boards[payload.Id] = {
				Name = payload.Name,
				Board = payload.Board or {},
				Mine = payload.Mine or 0,
				Rank = payload.Rank,
				Left = payload.Left or 0,
				At = os.clock(),
			}
		end
	elseif phase == "Result" then
		local rank = payload.Rank or 0
		local title = if rank == 1 then "#1 DAMAGE!" elseif rank <= 3 then `TOP 3! #{rank}` else `YOU PLACED #{rank}`
		Juice.banner(title, `{payload.Name} · +{Format.number(payload.Amount or 0)} Clacks`, if rank <= 3 then GOLD else Color3.new(1, 1, 1), 2)
		Juice.confetti(if rank == 1 then 120 elseif rank <= 3 then 70 else 30)
		if rank == 1 then
			Juice.flash(GOLD, 0.4, 0.6)
		end
	elseif phase == "Defeated" then
		local top = payload.Board and payload.Board[1]
		Interface.toast(`{payload.Name} was defeated!` .. (if top then ` Top damage: {top.Name}` else ""), GOLD)
	elseif phase == "Escaped" then
		Interface.toast(`{payload.Name} escaped! Next time...`, RED)
	end
end

function ZoneBossHud.start()
	Interface.setup()
	bind()
	Net.on("ZoneBoss", onEvent)
	task.spawn(function()
		while true do
			updateChip()
			updatePanel()
			task.wait(0.25)
		end
	end)
end

return ZoneBossHud
