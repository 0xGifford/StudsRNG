--[[ 

Client
LocalScript
/StarterPlayer/StarterPlayerScripts/Client

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The only client LocalScript. Same two-phase boot as the server:
-- init() on every controller, then start() on each in its own thread.

local ORDER = {
	"State",
	"MenuSystem", -- boots ReplicatedStorage.MenuSystem in its init()
	"AutoSliceScale",
	"StudFollowers",
	"RollReveal",
	"Hud",
	"EventsHud",
	"KeyLabels",
	"ZoneAmbience",
	"GameFeel",
	"Intro",
	"TutorialGuide",
	"IndexMenu",
	"StudsMenu",
	"OptionsMenu",
	"ShopMenu",
	"RebirthMenu",
	"RewardsMenu",
	"DailyMenu",
	"WheelMenu",
	"ZonesMenu",
	"UpgradeTree",
	"UpdatesMenu",
	"OddsMenu",
	"QuestsMenu",
	"TopbarIcons",
	"ChatTags",
	"DevKeys",
}

local controllers: { { name: string, module: any } } = {}
local seen: { [string]: boolean } = {}

local function load(module: Instance)
	if not module:IsA("ModuleScript") or seen[module.Name] then return end
	seen[module.Name] = true
	table.insert(controllers, { name = module.Name, module = require(module) :: any })
end

local folder = script:WaitForChild("Controllers")
for _, name in ORDER do
	local module = folder:FindFirstChild(name)
	if module then
		load(module)
	end
end
for _, module in folder:GetChildren() do
	load(module)
end

for _, controller in controllers do
	if typeof(controller.module.init) == "function" then
		local ok, err = pcall(controller.module.init)
		if not ok then
			warn(`[Client] {controller.name}.init failed: {err}`)
		end
	end
end

for _, controller in controllers do
	if typeof(controller.module.start) == "function" then
		task.spawn(controller.module.start)
	end
end
