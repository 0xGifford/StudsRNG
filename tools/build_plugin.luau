--[[
	Builds the ZoneManager Studio plugin from plugins/ZoneManager into
	ZoneManager.rbxmx (repo root). Save that file into your Studio Plugins
	folder (Studio: Plugins tab → Plugins Folder) and restart Studio.

	  lune run tools/build_plugin.luau

	  init.server.luau → the plugin Script "ZoneManager"
	  *.luau           → ModuleScripts under it (ZoneWiring, shared with
	                     tools/wire_zones.luau)
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local SOURCE = "plugins/ZoneManager"
local OUTPUT = "ZoneManager.rbxmx"

local plugin = roblox.Instance.new("Script")
plugin.Name = "ZoneManager"
plugin.Source = fs.readFile(SOURCE .. "/init.server.luau")

for _, entry in fs.readDir(SOURCE) do
	local name = string.match(entry, "^(.-)%.luau$")
	if name and not string.match(entry, "^init%.") then
		local module = roblox.Instance.new("ModuleScript")
		module.Name = name
		module.Source = fs.readFile(SOURCE .. "/" .. entry)
		module.Parent = plugin
	end
end

fs.writeFile(OUTPUT, roblox.serializeModel({ plugin }, true))
print(`built {OUTPUT}`)
