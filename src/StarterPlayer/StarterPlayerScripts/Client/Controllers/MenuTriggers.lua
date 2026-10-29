--[[

MenuTriggers
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/MenuTriggers

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Parts tagged MenuTrigger (Shared/Tags) open a menu: by touch, or through a
-- ProximityPrompt when Prompt is set. Menu / MenuAction / Prompt /
-- PromptText are read live, so a trigger can be retargeted while running.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tags = require(Shared.Tags)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local Interface = require(UI.Interface)

local MenuTriggers = {}

local TOUCH_COOLDOWN = 2
local PROMPT_NAME = "MenuPrompt"

local player = Players.LocalPlayer
local lastTouch = 0
local tracked: { [Instance]: { RBXScriptConnection } } = {}

local function run(part: BasePart)
	local menu = Tags.read(part, Tags.Attr.Menu, "")
	local action = Tags.string(part, Tags.Attr.MenuAction)
	if menu == "" and action ~= "Close" then return end
	-- Touch toggling would close a menu the player just opened; default to Open.
	Interface.runMenuAction(menu, action or "Open")
end

-- Adds, updates or removes the part's ProximityPrompt to match Prompt / PromptText.
local function syncPrompt(part: BasePart)
	local existing = part:FindFirstChild(PROMPT_NAME)
	if not Tags.read(part, Tags.Attr.Prompt, false) then
		if existing then existing:Destroy() end
		return
	end
	local prompt: ProximityPrompt
	if existing and existing:IsA("ProximityPrompt") then
		prompt = existing
	else
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = PROMPT_NAME
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 12
		prompt.Triggered:Connect(function()
			run(part)
		end)
		prompt.Parent = part
	end
	prompt.ActionText = Tags.read(part, Tags.Attr.PromptText, "Open")
	prompt.ObjectText = Tags.read(part, Tags.Attr.Menu, "")
end

local function track(instance: Instance)
	if tracked[instance] or not instance:IsA("BasePart") then return end
	local part = instance
	local connections: { RBXScriptConnection } = {}
	tracked[part] = connections
	syncPrompt(part)
	table.insert(connections, part.AttributeChanged:Connect(function()
		syncPrompt(part)
	end))
	table.insert(connections, part.Touched:Connect(function(hit)
		if Tags.read(part, Tags.Attr.Prompt, false) then return end
		local character = player.Character
		if not character or not hit:IsDescendantOf(character) then return end
		if os.clock() - lastTouch < TOUCH_COOLDOWN then return end
		lastTouch = os.clock()
		run(part)
	end))
end

local function untrack(instance: Instance)
	local connections = tracked[instance]
	if not connections then return end
	tracked[instance] = nil
	for _, connection in connections do
		connection:Disconnect()
	end
	local prompt = instance:FindFirstChild(PROMPT_NAME)
	if prompt then prompt:Destroy() end
end

function MenuTriggers.start()
	Interface.setup()
	for _, instance in CollectionService:GetTagged(Tags.MenuTrigger) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(Tags.MenuTrigger):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Tags.MenuTrigger):Connect(untrack)
end

return MenuTriggers
