--[[
	Compiles every Luau file under src/ and tools/ and reports syntax errors.
	Run from the project root:  lune run tools/check.luau
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local checked, failed = 0, 0

local function walk(dir: string)
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path)
		elseif string.match(name, "%.luau?$") then
			checked += 1
			local ok, err = pcall(luau.compile, fs.readFile(path))
			if not ok then
				failed += 1
				print(`FAIL {path}: {err}`)
			end
		end
	end
end

for _, root in { "src", "tools" } do
	if fs.isDir(root) then
		walk(root)
	end
end
print(`{checked} files, {failed} failed`)
process.exit(if failed > 0 then 1 else 0)
