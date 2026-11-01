--[[
	Builds the StarterGui screens from tools/ui/screens into src/StarterGui
	(one .rbxm per ScreenGui). Edit them in Studio afterwards as much as you
	like: the game only looks things up by name, and syncing
	(tools/sync_scripts.luau, Rojo) never overwrites a ScreenGui the place
	already has. Rebuild one only to start it over from here.

	  lune run tools/build_ui.luau            every screen
	  lune run tools/build_ui.luau AdminPanel one screen
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local only = process.args[1]
local built = 0
for _, entry in fs.readDir("tools/ui/screens") do
	local name = string.match(entry, "^(.-)%.luau$")
	if name and (only == nil or only == name) then
		require(`./ui/screens/{name}`)
		built += 1
	end
end
if built == 0 then
	print(if only then `no screen named {only} in tools/ui/screens` else "no screens")
	process.exit(1)
end
