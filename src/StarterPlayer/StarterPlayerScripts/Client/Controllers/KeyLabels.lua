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
-- pulsing label in its kind's colour ("+1", 💰, 🍀, ⚡) until someone
-- claims it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Roles = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Roles"))

local KeyLabels = {}

local Settings = Config.KeyRewards
local LETTER_GUI = "SurfaceGui" -- KeyCapper's GuiFactory name
local REWARD_GUI = "RewardLabel"

-- hitbox → connections on its key Model
local tracked: { [Instance]: { RBXScriptConnection } } = {}

local function hideLetter(gui: Instance)
	if Settings.HideLetters and gui.Name == LETTER_GUI and gui:IsA("SurfaceGui") then
		gui.Enabled = false
	end
end

-- The tile's kind (Config.KeyRewards.Kinds) from the key Model.
local function kindOf(model: Instance): any
	local id = model:GetAttribute(Settings.KindAttribute)
	for _, kind in Settings.Kinds do
		if kind.Id == id then
			return kind
		end
	end
	return nil
end

-- A copy of StarterGui.WorldUI's KeyReward on the key's cap, in the kind's
-- colour; the rarer kinds pulse harder.
local function buildRewardGui(cap: BasePart, text: string, kind: any)
	local gui = Roles.template(Roles.gui("WorldUI"), "KeyReward") :: SurfaceGui
	gui.Name = REWARD_GUI
	local label = Roles.get(gui, "KeyRole", "Text") :: TextLabel
	label.Text = text
	if kind and typeof(kind.Color) == "Color3" then
		label.TextColor3 = kind.Color
	end
	local rare = kind ~= nil and kind.Id ~= Settings.Kinds[1].Id

	-- Gentle pulse so tiles catch the eye.
	local scale = label:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", label)
	scale.Scale = 0
	local appear = TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	appear:Play()
	appear.Completed:Once(function()
		if scale.Parent then
			TweenService:Create(scale, TweenInfo.new(if rare then 0.35 else 0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
				Scale = if rare then 0.7 else 0.82,
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
			buildRewardGui(cap, reward, kindOf(model))
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
