--[[

KeyLabels
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/KeyLabels

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- What's written on the keys. KeyCapper bakes a letter SurfaceGui onto each
-- key's Cap; with Config.KeyRewards.HideLetters those are switched off here
-- (locally), so the only text on the board is reward tiles: keys whose
-- Model carries the RewardTile attribute (set by Systems/KeyRewards) show a
-- pulsing "+1" until someone claims it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local KeyLabels = {}

local Settings = Config.KeyRewards
local LETTER_GUI = "SurfaceGui" -- KeyCapper's GuiFactory name
local REWARD_GUI = "RewardLabel"
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)

-- hitbox → connections on its key Model
local tracked: { [Instance]: { RBXScriptConnection } } = {}

local function hideLetter(gui: Instance)
	if Settings.HideLetters and gui.Name == LETTER_GUI and gui:IsA("SurfaceGui") then
		gui.Enabled = false
	end
end

local function buildRewardGui(cap: BasePart, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Name = REWARD_GUI
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(150, 150)
	gui.LightInfluence = 0
	gui.MaxDistance = 150
	gui.AlwaysOnTop = false

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.85, 0.85)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = FONT
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	label.Parent = gui

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 245, 140), Color3.fromRGB(255, 180, 40))
	gradient.Rotation = 90
	gradient.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(25, 25, 25)
	stroke.Thickness = 6
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label

	-- Gentle pulse so tiles catch the eye.
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = label
	local appear = TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	appear:Play()
	appear.Completed:Once(function()
		if scale.Parent then
			TweenService:Create(scale, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
				Scale = 0.82,
			}):Play()
		end
	end)

	gui.Parent = cap
end

local function refresh(model: Instance)
	local cap = model:FindFirstChild("Cap")
	if not (cap and cap:IsA("BasePart")) then return end

	local letter = cap:FindFirstChild(LETTER_GUI)
	if letter then
		hideLetter(letter)
	end

	local reward = model:GetAttribute(Settings.Attribute)
	local existing = cap:FindFirstChild(REWARD_GUI)
	if typeof(reward) == "string" and reward ~= "" then
		if not existing then
			buildRewardGui(cap, reward)
		end
	elseif existing then
		existing:Destroy()
	end
end

local function track(hitbox: Instance)
	local model = hitbox.Parent
	if not model or tracked[hitbox] then return end
	local connections: { RBXScriptConnection } = {}
	tracked[hitbox] = connections

	table.insert(connections, model:GetAttributeChangedSignal(Settings.Attribute):Connect(function()
		refresh(model)
	end))
	-- Streaming: the Cap (and the plugin's label) can arrive after the hitbox.
	table.insert(connections, model.DescendantAdded:Connect(function(descendant)
		if descendant.Name == "Cap" then
			refresh(model)
		elseif descendant.Name == LETTER_GUI then
			hideLetter(descendant)
		end
	end))
	refresh(model)
end

local function untrack(hitbox: Instance)
	local connections = tracked[hitbox]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
		tracked[hitbox] = nil
	end
end

function KeyLabels.start()
	local tag = Config.Press.HitboxTag
	for _, hitbox in CollectionService:GetTagged(tag) do
		track(hitbox)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(track)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(untrack)
end

return KeyLabels
