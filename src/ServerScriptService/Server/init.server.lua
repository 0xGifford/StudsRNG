--[[ 

Server
Script
/ServerScriptService/Server

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The only server Script. Creates remotes, then boots every module in
-- Systems in two phases: init() on all (sync wiring), then start() on all
-- (long-running loops, each in its own thread).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

Net.setup()

-- Explicit order for init: dependencies first. Any module in Systems not
-- listed here still loads, after these.
local ORDER = {
	"PlayerData",
	"StateSync",
	"PressTracker",
	"Inventory",
	"Economy",
	"Rolls",
	"Session",
	"DevCommands",
}

local systems: { { name: string, module: any } } = {}
local seen: { [string]: boolean } = {}

local function load(module: Instance)
	if not module:IsA("ModuleScript") or seen[module.Name] then return end
	seen[module.Name] = true
	table.insert(systems, { name = module.Name, module = require(module) :: any })
end

local folder = script:WaitForChild("Systems")
for _, name in ORDER do
	local module = folder:FindFirstChild(name)
	if module then
		load(module)
	else
		warn(`[Server] system {name} not found`)
	end
end
for _, module in folder:GetChildren() do
	load(module)
end

for _, system in systems do
	if typeof(system.module.init) == "function" then
		local ok, err = pcall(system.module.init)
		if not ok then
			warn(`[Server] {system.name}.init failed: {err}`)
		end
	end
end

for _, system in systems do
	if typeof(system.module.start) == "function" then
		task.spawn(system.module.start)
	end
end

print(`[Server] booted {#systems} systems`)
