--[[
	Builds the Studio plugins in plugins/ into .rbxmx files at the repo root.
	Save a built file into your Studio Plugins folder (Studio: Plugins tab →
	Plugins Folder) and restart Studio.

	  lune run tools/build_plugin.luau              builds every plugin
	  lune run tools/build_plugin.luau KeyCapper    builds one

	plugins/ZoneManager → ZoneManager.rbxmx
	  init.server.luau is the plugin Script; every other *.luau is a
	  ModuleScript under it (ZoneWiring is shared with tools/wire_zones.luau).

	plugins/KeyCapper → KeyCapper.rbxmx
	  KeyCapper.base.rbxmx holds the instances that aren't code (the key mesh,
	  remotes, folders). Every script in it takes its source from src/ at the
	  same path (Name.luau = ModuleScript, Name.server.luau = Script); a file
	  in src/ with no script in the base is added as a new ModuleScript.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance

local function classAndName(file: string): (string?, string?)
	local name = string.match(file, "^(.-)%.server%.luau$")
	if name then return "Script", name end
	name = string.match(file, "^(.-)%.client%.luau$")
	if name then return "LocalScript", name end
	name = string.match(file, "^(.-)%.luau$")
	if name then return "ModuleScript", name end
	return nil, nil
end

local function buildZoneManager(): any
	local source = "plugins/ZoneManager"
	local plugin = Instance.new("Script")
	plugin.Name = "ZoneManager"
	plugin.Source = fs.readFile(source .. "/init.server.luau")
	for _, entry in fs.readDir(source) do
		local className, name = classAndName(entry)
		if className == "ModuleScript" and not string.match(entry, "^init%.") then
			local module = Instance.new("ModuleScript")
			module.Name = name
			module.Source = fs.readFile(source .. "/" .. entry)
			module.Parent = plugin
		end
	end
	return plugin
end

local function buildKeyCapper(): any
	local base = "plugins/KeyCapper"
	local root = roblox.deserializeModel(fs.readFile(base .. "/KeyCapper.base.rbxmx"))[1]
	local used = {}
	local function apply(dir: string, target: any)
		for _, entry in fs.readDir(dir) do
			local path = dir .. "/" .. entry
			if fs.isDir(path) then
				local child = target:FindFirstChild(entry)
				if not child then
					child = Instance.new("Folder")
					child.Name = entry
					child.Parent = target
				end
				apply(path, child)
			else
				local className, name = classAndName(entry)
				if className then
					local script = target:FindFirstChild(name)
					if not script then
						script = Instance.new(className)
						script.Name = name
						script.Parent = target
					end
					assert(script.ClassName == className, `{path}: base has a {script.ClassName} named {name}`)
					script.Source = fs.readFile(path)
					used[script] = true
				end
			end
		end
	end
	apply(base .. "/src", root)
	for _, d in root:GetDescendants() do
		if d:IsA("LuaSourceContainer") and not used[d] then
			error(`{d:GetFullName()} is in the base but has no file in src/`)
		end
	end
	return root
end

local BUILDS = {
	ZoneManager = buildZoneManager,
	KeyCapper = buildKeyCapper,
}

local only = process.args[1]
for name, build in BUILDS do
	if only == nil or only == name then
		fs.writeFile(name .. ".rbxmx", roblox.serializeModel({ build() }, true))
		print(`built {name}.rbxmx`)
	end
end
