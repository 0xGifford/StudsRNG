--[[

StudTemplate
ModuleScript
/ServerScriptService/Server/Systems/StudTemplate

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Lets the stud model template live in ServerStorage. Clients draw every
-- stud (Util/StudVisuals) and can't see ServerStorage, so at boot a Part or
-- MeshPart named Config.Visuals.TemplateName in ServerStorage (or in
-- ServerStorage.Assets) is copied to ReplicatedStorage.Assets, replacing
-- any template already there. One placed straight in ReplicatedStorage.Assets
-- works too. StudVisuals recolours, resizes and decorates it per stud.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local StudTemplate = {}

function StudTemplate.init()
	local name = Config.Visuals.TemplateName
	local assets = ServerStorage:FindFirstChild("Assets")
	local source = ServerStorage:FindFirstChild(name) or (assets and assets:FindFirstChild(name))
	if not source then return end
	if not source:IsA("BasePart") then
		warn(`[StudTemplate] ServerStorage.{name} must be a Part or MeshPart, not a {source.ClassName}`)
		return
	end

	local folder = ReplicatedStorage:FindFirstChild(Config.Visuals.TemplateFolder)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Config.Visuals.TemplateFolder
		folder.Parent = ReplicatedStorage
	end
	local existing = (folder :: Instance):FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local copy = source:Clone()
	copy.Name = name
	copy.Anchored = true
	copy.Parent = folder
end

return StudTemplate
