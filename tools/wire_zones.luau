--[[
	Wires the hand-built zones in a place file (see
	plugins/ZoneManager/ZoneWiring.luau for what that means). The ZoneManager
	plugin's "Wire all zones" button does the same thing inside Studio.

	  lune run tools/wire_zones.luau <in.rbxl> <out.rbxl>

	Prints what it did and anything you should fix by hand.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local input, output = process.args[1], process.args[2]
assert(input and output, "usage: lune run tools/wire_zones.luau <in.rbxl> <out.rbxl>")

local Wiring = require("../plugins/ZoneManager/ZoneWiring")({
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
})

local game = roblox.deserializePlace(fs.readFile(input))
local report = Wiring.wire(game:GetService("Workspace"))
for _, line in report.lines do
	print("  " .. line)
end
for _, problem in report.problems do
	print("✗ " .. problem)
end
fs.writeFile(output, roblox.serializePlace(game))
print(`→ {output}`)
