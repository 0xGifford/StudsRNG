--[[

TutorialGuide
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/TutorialGuide

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Shows the current tutorial step (Shared/Tutorial) after the intro:
-- a panel with the instruction and progress, plus a pointer:
--   world targets ("Keys", "Tile")  a beam from the player and a bouncing
--                                    arrow over the nearest key / +1 tile
--   HUD targets (button names)      a pulsing outline + arrow on the button
-- When a step's check passes locally it asks the server (AdvanceTutorial),
-- which re-checks against saved data before moving on.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local TutorialDefs = require(Shared.Tutorial)
local Tags = require(Shared.Tags)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local StudsMenu = require(Controllers.StudsMenu)
local Intro = require(Controllers.Intro)
local Interface = require(UI.Interface)
local Juice = require(UI.Juice)
local Format = require(UI.Format)

local TutorialGuide = {}

local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local ACCENT = Color3.fromRGB(255, 220, 90)

local player = Players.LocalPlayer
local gui: ScreenGui
local panel: Frame
local stepLabel: TextLabel
local textLabel: TextLabel
local bar: Frame
local highlight: Frame
local arrow: TextLabel

local beam: Beam
local fromAttachment: Attachment
local toAttachment: Attachment
local worldArrow: BillboardGui

local shownStep = -1
local lastAsk = 0
local lastSearch = 0
local cachedTarget: Vector3? = nil

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

local function label(parent: Instance, text: string, size: UDim2, position: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Size = size
	l.Position = position
	l.TextScaled = true
	l.FontFace = FONT
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Text = text
	l.ZIndex = 3
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(15, 15, 20)
	stroke.Parent = l
	l.Parent = parent
	return l
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Tutorial"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 15
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.fromScale(0.5, 0.115)
	panel.Size = UDim2.fromScale(0.36, 0.1)
	panel.BackgroundColor3 = Color3.fromRGB(20, 18, 30)
	panel.BackgroundTransparency = 0.25
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT
	stroke.Thickness = 2.5
	stroke.Parent = panel
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 6
	ratio.Parent = panel

	stepLabel = label(panel, "", UDim2.fromScale(0.5, 0.26), UDim2.fromScale(0.5, 0.2))
	stepLabel.TextColor3 = ACCENT
	textLabel = label(panel, "", UDim2.fromScale(0.92, 0.36), UDim2.fromScale(0.5, 0.52))

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.5, 0.84)
	track.Size = UDim2.fromScale(0.8, 0.12)
	track.BackgroundColor3 = Color3.new(0, 0, 0)
	track.BackgroundTransparency = 0.4
	track.Parent = panel
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track
	bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(0, 1)
	bar.BackgroundColor3 = ACCENT
	bar.Parent = track
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar

	-- HUD highlight
	highlight = Instance.new("Frame")
	highlight.BackgroundTransparency = 1
	highlight.Visible = false
	highlight.ZIndex = 4
	highlight.Parent = gui
	local ring = Instance.new("UIStroke")
	ring.Color = ACCENT
	ring.Thickness = 4
	ring.Parent = highlight
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(0.2, 0)
	ringCorner.Parent = highlight
	arrow = label(gui, "▼", UDim2.fromOffset(44, 44), UDim2.new())
	arrow.TextColor3 = ACCENT
	arrow.Visible = false

	-- World pointer
	fromAttachment = Instance.new("Attachment")
	fromAttachment.Name = "TutorialFrom"
	toAttachment = Instance.new("Attachment")
	toAttachment.Name = "TutorialTo"
	toAttachment.Parent = workspace.Terrain
	beam = Instance.new("Beam")
	beam.Attachment0 = fromAttachment
	beam.Attachment1 = toAttachment
	beam.Color = ColorSequence.new(ACCENT)
	beam.Transparency = NumberSequence.new(0.2, 0.6)
	beam.Width0 = 0.8
	beam.Width1 = 0.8
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Segments = 1
	beam.Enabled = false
	beam.Parent = workspace.Terrain

	worldArrow = Instance.new("BillboardGui")
	worldArrow.Name = "TutorialArrow"
	worldArrow.Size = UDim2.fromScale(3, 3)
	worldArrow.AlwaysOnTop = true
	worldArrow.Adornee = toAttachment
	worldArrow.Enabled = false
	local worldLabel = label(worldArrow, "▼", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5))
	worldLabel.TextColor3 = ACCENT
	worldArrow.Parent = gui
end

--------------------------------------------------------------------------
-- Targets
--------------------------------------------------------------------------

local function dataView(): { [string]: any }
	return {
		TotalPresses = State.get("TotalPresses"),
		TotalRolls = State.get("TotalRolls"),
		Equipped = State.get("Equipped"),
		TilesClaimed = State.get("TilesClaimed"),
		Upgrades = State.get("Upgrades"),
		Clacks = State.get("Clacks"),
	}
end

local function hudTarget(name: string): GuiObject?
	if name == "Roll" or name == "Studs" then
		local top = Interface.HUD:FindFirstChild("Top")
		local frame = top and top:FindFirstChild("Frame")
		local target = frame and frame:FindFirstChild(name)
		if name == "Studs" and Interface.isOpen("Studs") then
			target = StudsMenu.equipBestButton()
		end
		return if target and target:IsA("GuiObject") then target else nil
	end
	if Interface.isOpen(name) then return nil end
	-- Side buttons can sit in either column or the bottom bar (HudLayout).
	local target = Interface.HUD:FindFirstChild(name, true)
	return if target and target:IsA("GuiObject") then target else nil
end

local function nearestKey(root: Vector3, wantTile: boolean): Vector3?
	local best: Vector3? = nil
	local bestDistance = math.huge
	local unlocked = State.get("UnlockedWorlds") or {}
	for _, hitbox in CollectionService:GetTagged(Config.Press.HitboxTag) do
		if hitbox:IsA("BasePart") then
			local model = hitbox.Parent
			local isTile = model ~= nil and model:GetAttribute(Config.KeyRewards.Attribute) ~= nil
			local world = Tags.keyZone(hitbox)
			local enabled = model ~= nil and Tags.read(model, Tags.Attr.Enabled, true)
			local owned = enabled and (world == nil or unlocked[world] == true)
			if owned and (not wantTile or isTile) then
				local distance = (hitbox.Position - root).Magnitude
				if distance < bestDistance then
					bestDistance = distance
					best = hitbox.Position
				end
			end
		end
	end
	return best
end

local function setWorldTarget(position: Vector3?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if position and root and root:IsA("BasePart") then
		if fromAttachment.Parent ~= root then
			fromAttachment.Parent = root
		end
		toAttachment.WorldPosition = position + Vector3.new(0, 1.5, 0)
		beam.Enabled = true
		worldArrow.Enabled = true
		worldArrow.StudsOffsetWorldSpace = Vector3.new(0, 2.5 + math.sin(os.clock() * 5) * 0.6, 0)
	else
		beam.Enabled = false
		worldArrow.Enabled = false
	end
end

local function setHudTarget(target: GuiObject?)
	if target and target.Visible then
		local pad = 6
		highlight.Visible = true
		highlight.Position = UDim2.fromOffset(target.AbsolutePosition.X - pad, target.AbsolutePosition.Y - pad)
		highlight.Size = UDim2.fromOffset(target.AbsoluteSize.X + pad * 2, target.AbsoluteSize.Y + pad * 2)
		local stroke = highlight:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0.5 - math.sin(os.clock() * 6) * 0.5
		end
		arrow.Visible = true
		arrow.Position = UDim2.fromOffset(
			target.AbsolutePosition.X + target.AbsoluteSize.X / 2,
			target.AbsolutePosition.Y - 30 + math.sin(os.clock() * 6) * 8
		)
	else
		highlight.Visible = false
		arrow.Visible = false
	end
end

--------------------------------------------------------------------------
-- Loop
--------------------------------------------------------------------------

local function showStep(index: number)
	local step = TutorialDefs.Steps[index]
	stepLabel.Text = `STEP {index}/{#TutorialDefs.Steps}`
	textLabel.Text = step.Text
	if shownStep > 0 then
		Interface.play("Click", 1.4)
		Juice.pop(panel, 1.15)
		Juice.confetti(25, Vector2.new(panel.AbsolutePosition.X + panel.AbsoluteSize.X / 2, panel.AbsolutePosition.Y + panel.AbsoluteSize.Y))
	end
	shownStep = index
end

local function update()
	local index = State.get("Tutorial") or 0
	if not Intro.hasFinished() or index < 1 or index >= TutorialDefs.Finished or Intro.isPlaying() then
		gui.Enabled = false
		beam.Enabled = false
		return
	end
	gui.Enabled = true
	if index ~= shownStep then
		showStep(index)
	end

	local step = TutorialDefs.Steps[index]
	local data = dataView()
	local progress = step.Progress
	if progress then
		local value, goal = progress(data)
		bar.Size = UDim2.fromScale(math.clamp(value / math.max(goal, 1), 0, 1), 1)
		textLabel.Text = `{step.Text} ({Format.number(value)}/{Format.number(goal)})`
	else
		bar.Size = UDim2.fromScale(if step.Done(data) then 1 else 0, 1)
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local rootPosition = if root and root:IsA("BasePart") then root.Position else nil
	if step.Target == "Keys" or step.Target == "Tile" then
		-- Scanning every key is too much per frame: refresh a few times a second.
		if os.clock() - lastSearch > 0.3 then
			lastSearch = os.clock()
			cachedTarget = if rootPosition then nearestKey(rootPosition, step.Target == "Tile") else nil
		end
		local target = cachedTarget
		-- Close enough: stop pointing at the floor under their feet.
		if target and rootPosition and step.Target == "Keys" and (target - rootPosition).Magnitude < 6 then
			target = nil
		end
		setWorldTarget(target)
		setHudTarget(nil)
	else
		setWorldTarget(nil)
		setHudTarget(hudTarget(step.Target))
	end

	if step.Done(data) and os.clock() - lastAsk > 1 then
		lastAsk = os.clock()
		task.spawn(function()
			Net.invoke("AdvanceTutorial")
		end)
	end
end

function TutorialGuide.start()
	Interface.setup()
	build()
	State.Notified:Connect(function(payload)
		if payload.Kind == "TutorialDone" then
			Juice.banner("TUTORIAL COMPLETE!", "+5 Free Rolls and a Jackpot Spin", Color3.fromRGB(120, 255, 140), 2.2)
			Juice.confetti(80)
			Juice.shake(0.6, 0.4)
		end
	end)
	RunService.RenderStepped:Connect(function()
		if State.isReady() then
			update()
		end
	end)
end

return TutorialGuide
