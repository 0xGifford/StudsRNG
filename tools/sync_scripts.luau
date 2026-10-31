--[[
	Copies every script in src/ into a place file, following the Rojo layout
	in default.project.json (like a one-off `rojo serve` sync).

	  lune run tools/sync_scripts.luau <in.rbxl> <out.rbxl>

	  foo.lua         → ModuleScript "foo"
	  foo.server.lua  → Script "foo"        foo.client.lua → LocalScript "foo"
	  dir/init.lua    → "dir" itself is the script (init.server / init.client too)
	  dir/            → Folder "dir" (kept if it already exists)
	  *.rbxm          → model children, inserted only when missing (UI you
	                    edit in Studio is never overwritten)
	Existing scripts get the repo's source; missing ones are created.
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance

local input, output = process.args[1], process.args[2]
assert(input and output, "usage: lune run tools/sync_scripts.luau <in.rbxl> <out.rbxl>")

local game = roblox.deserializePlace(fs.readFile(input))
local project = serde.decode("json", fs.readFile("default.project.json"))

local updated, created, models, removed = 0, 0, 0, 0

local function scriptClass(file: string): (string?, string)
	local name, kind = string.match(file, "^(.-)%.(server)%.luau?$")
	if name then return "Script", name end
	name, kind = string.match(file, "^(.-)%.(client)%.luau?$")
	if name then return "LocalScript", name end
	name = string.match(file, "^(.-)%.luau?$")
	if name then return "ModuleScript", name end
	return nil, file
end

local function ensure(parent: any, className: string, name: string): any
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	if existing then
		-- Keep its children (e.g. a Folder turning into a script with init.lua).
		for _, child in existing:GetChildren() do
			child.Parent = instance
		end
		existing:Destroy()
	end
	instance.Parent = parent
	return instance
end

local function setSource(instance: any, path: string)
	local source = fs.readFile(path)
	if instance.Source ~= source then
		if instance.Source == "" then created += 1 else updated += 1 end
		instance.Source = source
	end
end

local function syncDir(dir: string, target: any)
	local keep = {}
	for _, entry in fs.readDir(dir) do
		local _, name = scriptClass(entry)
		keep[name] = true
		keep[entry] = true
	end
	for _, child in target:GetChildren() do
		if child:IsA("LuaSourceContainer") and not keep[child.Name] then
			print(`removed {child:GetFullName()} (no longer in src/)`)
			child:Destroy()
			removed += 1
		end
	end
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			-- A directory with an init script is that script.
			local initClass = nil
			for _, init in { "init.lua", "init.luau", "init.server.lua", "init.server.luau", "init.client.lua", "init.client.luau" } do
				if fs.isFile(path .. "/" .. init) then
					initClass = { (scriptClass(init)), path .. "/" .. init }
				end
			end
			local child
			if initClass then
				child = ensure(target, initClass[1], entry)
				setSource(child, initClass[2])
			else
				child = target:FindFirstChild(entry) or ensure(target, "Folder", entry)
			end
			syncDir(path, child)
		elseif not string.match(entry, "^init%.") then
			local className, name = scriptClass(entry)
			if className then
				setSource(ensure(target, className, name), path)
			elseif string.match(entry, "%.rbxm$") then
				for _, instance in roblox.deserializeModel(fs.readFile(path)) do
					if not target:FindFirstChild(instance.Name) then
						instance.Parent = target
						models += 1
					end
				end
			end
		end
	end
end

local function syncNode(node: any, target: any)
	if node["$path"] and fs.isDir(node["$path"]) then
		syncDir(node["$path"], target)
	end
	for key, child in node do
		if string.sub(key, 1, 1) ~= "$" and typeof(child) == "table" then
			local instance = target:FindFirstChild(key)
			if not instance then
				instance = game:GetService(child["$className"] or key)
			end
			syncNode(child, instance)
		end
	end
end

syncNode(project.tree, game)
fs.writeFile(output, roblox.serializePlace(game))
print(`{updated} scripts updated, {created} created, {removed} removed, {models} models added → {output}`)
