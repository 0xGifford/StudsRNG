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
	"World",
	"Modifiers",
	"PressTracker",
	"Inventory",
	"Economy",
	"Boosts",
	"ServerEffects",
	"Social",
	"Rolls",
	"UpgradeShop",
	"ZoneShop",
	"Rebirth",
	"RewardService",
	"QuestService",
	"KeyRewards",
	"Tutorial",
	"Products",
	"Session",
	"DevCommands",
}

-- Systems that were removed from the game. A place synced with Rojo keeps
-- old modules around ($ignoreUnknownInstances), so never load these.
local RETIRED = {
	MapBuilder = true, -- the generated map; the map is built by hand now (Systems/World)
	StudTemplate = true, -- now Systems/Templates (studs and enemies)
}

local systems: { { name: string, module: any } } = {}
local seen: { [string]: boolean } = table.clone(RETIRED)

local function load(module: Instance)
	if not module:IsA("ModuleScript") or seen[module.Name] then return end
	seen[module.Name] = true
	-- One broken module must not stop everything else from booting.
	local ok, result = pcall(require, module)
	if not ok then
		warn(`[Server] {module.Name} failed to load: {result}`)
		return
	end
	table.insert(systems, { name = module.Name, module = result :: any })
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
		task.spawn(function()
			local ok, err = xpcall(system.module.start, debug.traceback)
			if not ok then
				warn(`[Server] {system.name}.start failed: {err}`)
			end
		end)
	end
end

print(`[Server] booted {#systems} systems`)
