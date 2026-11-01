--[[
	The TooltipTemplate ScreenGui: your tooltip design (tools/ui/designs). Its
	MainFrame (TooltipTemplate = true) is what MenuSystem's Tooltip clones;
	anything with TooltipTitle / TooltipDescription attributes shows it.
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Kit = require("../Kit")

local gui = roblox.deserializeModel(fs.readFile("tools/ui/designs/TooltipTemplate.rbxm"))[1]
Kit.save(gui)
