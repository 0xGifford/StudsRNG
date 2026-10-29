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
--   * near a Titan: a raid panel (top right) with its health, time left, the live damage
--     leaderboard (top 5) and your rank

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

local ZoneBossHud = {}

local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local RED = Color3.fromRGB(255, 70, 60)
local GOLD = Color3.fromRGB(255, 205, 60)
local PANEL_RANGE = 220 -- studs: the raid panel shows within this of a Titan

local player = Players.LocalPlayer
local settings = Config.ZoneBoss

local gui: ScreenGui
local chip: TextLabel
local panel: Frame
local panelName: TextLabel
local panelFill: Frame
local panelHp: TextLabel
local panelTime: TextLabel
local rows: { TextLabel } = {}
local mineRow: TextLabel

-- Latest "Board" per Titan id.
type Board = { Name: string, Board: { { Name: string, Damage: number } }, Mine: number, Rank: number?, Left: number, At: number }
local boards: { [number]: Board } = {}

local function text(parent: Instance, value: string, color: Color3, size: UDim2, position: UDim2, align: Enum.TextXAlignment?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = size
	label.Position = position
	label.FontFace = FONT
	label.TextScaled = true
	label.TextColor3 = color
	label.TextXAlignment = align or Enum.TextXAlignment.Center
	label.Text = value
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(12, 12, 18)
	stroke.Parent = label
	label.Parent = parent
	return label
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(radius, 0)
	c.Parent = parent
end

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

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "ZoneBoss"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Countdown chip, top right.
	chip = text(gui, "", Color3.new(1, 1, 1), UDim2.fromOffset(210, 30), UDim2.new(1, -120, 0, 24))
	chip.BackgroundTransparency = 0.25
	chip.BackgroundColor3 = Color3.fromRGB(30, 14, 18)
	corner(chip, 0.5)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 5)
	pad.Parent = chip

	-- Raid panel, top right under the chip (top centre is the roll display's).
	panel = Instance.new("Frame")
	panel.Name = "Raid"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -12, 0, 46)
	panel.Size = UDim2.fromOffset(420, 200)
	panel.BackgroundColor3 = Color3.fromRGB(22, 14, 20)
	panel.BackgroundTransparency = 0.15
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 0.08)
	local stroke = Instance.new("UIStroke")
	stroke.Color = RED
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = panel
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	-- (UIScale shrinks towards the anchor: top right stays put.)
	local function fit()
		scale.Scale = math.clamp(gui.AbsoluteSize.X / 1100, 0.6, 1)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	panelName = text(panel, "", RED, UDim2.new(1, -20, 0, 26), UDim2.new(0.5, 0, 0, 20))
	panelTime = text(panel, "", Color3.fromRGB(255, 220, 200), UDim2.new(0.3, 0, 0, 18), UDim2.new(0.85, 0, 0, 20), Enum.TextXAlignment.Right)

	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 0)
	back.Position = UDim2.new(0.5, 0, 0, 38)
	back.Size = UDim2.new(1, -24, 0, 22)
	back.BackgroundColor3 = Color3.fromRGB(12, 8, 12)
	back.Parent = panel
	corner(back, 0.5)
	panelFill = Instance.new("Frame")
	panelFill.Size = UDim2.fromScale(1, 1)
	panelFill.BackgroundColor3 = RED
	panelFill.Parent = back
	corner(panelFill, 0.5)
	panelHp = text(back, "", Color3.new(1, 1, 1), UDim2.fromScale(0.9, 0.85), UDim2.fromScale(0.5, 0.5))
	panelHp.ZIndex = 3

	text(panel, "TOP DAMAGE", GOLD, UDim2.new(1, -24, 0, 16), UDim2.new(0.5, 0, 0, 74))
	for i = 1, 5 do
		local row = text(panel, "", Color3.new(1, 1, 1), UDim2.new(1, -40, 0, 16), UDim2.new(0.5, 0, 0, 74 + i * 18), Enum.TextXAlignment.Left)
		rows[i] = row
	end
	mineRow = text(panel, "", Color3.fromRGB(120, 255, 140), UDim2.new(1, -40, 0, 18), UDim2.new(0.5, 0, 0, 186), Enum.TextXAlignment.Left)
end

-- The nearest Titan within PANEL_RANGE.
local function nearestTitan(): Model?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then return nil end
	local best: Model?, bestDistance = nil, PANEL_RANGE
	for _, instance in CollectionService:GetTagged(Tags.Enemy) do
		if instance:IsA("Model") and instance:GetAttribute("ZoneBoss") == true then
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
		Juice.banner("THE TITANS HAVE ARRIVED!", `{names} · teleport in and fight together!`, RED, 2.4)
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
	build()
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
