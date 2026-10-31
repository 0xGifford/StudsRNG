--[[

Templates
ModuleScript
/ServerScriptService/Server/Systems/Templates

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Your own models for studs and enemies, kept in ServerStorage (or
-- ServerStorage.Assets) where you edit them. Clients draw studs and enemies
-- and can't see ServerStorage, so at boot they're copied to
-- ReplicatedStorage.Assets, replacing any copy already there:
--
--   StudTemplate     ONE Model (or Part / MeshPart) every stud is built from
--                    (Util/StudVisuals: recoloured, scaled for Big / Huge /
--                    Jumbo, Shiny sparkles and outline...)
--   EnemyTemplates   a Folder with up to three Models (EnemyVisuals):
--                      Enemy      every normal enemy
--                      MiniBoss   Mini Bosses (else Enemy)
--                      Titan      Zone Boss Titans (else MiniBoss, else Enemy)
--                    Without any, enemies stay the built-in brick monsters.
--
-- Names come from Config.Visuals. Templates placed straight in
-- ReplicatedStorage.Assets work too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Templates = {}

local function find(name: string): Instance?
	local assets = ServerStorage:FindFirstChild("Assets")
	return ServerStorage:FindFirstChild(name) or (assets and assets:FindFirstChild(name))
end

local function publish(source: Instance, name: string)
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
	for _, d in copy:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	if copy:IsA("BasePart") then
		copy.Anchored = true
	end
	copy.Parent = folder
end

function Templates.init()
	local studName = Config.Visuals.TemplateName
	local stud = find(studName)
	if stud then
		if stud:IsA("BasePart") or stud:IsA("Model") then
			publish(stud, studName)
		else
			warn(`[Templates] ServerStorage.{studName} must be a Model, Part or MeshPart, not a {stud.ClassName}`)
		end
	end

	local enemyName = Config.Visuals.EnemyTemplateFolder
	local enemies = find(enemyName)
	if enemies then
		for _, child in enemies:GetChildren() do
			if not child:IsA("Model") then
				warn(`[Templates] {enemyName}.{child.Name} must be a Model, not a {child.ClassName}`)
			elseif not (child.Name == "Enemy" or child.Name == "MiniBoss" or child.Name == "Titan") then
				warn(`[Templates] {enemyName}.{child.Name} isn't used: name it Enemy, MiniBoss or Titan`)
			end
		end
		publish(enemies, enemyName)
	end
end

return Templates
