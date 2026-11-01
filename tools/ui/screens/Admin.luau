--[[
	The Admin ScreenGui: your admin panel design (tools/ui/designs/Admin.rbxm,
	from your menu system place) with the stat rows of the inspected player
	set to this game's. Everything else is read by name / attribute by
	MenuSystem's AdminPanel, so restyle it freely in Studio.
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Kit = require("../Kit")

-- AdminField = key in Systems/Admin's inspect(), and the row's caption.
local ROWS = {
	{ "Role", "Role" },
	{ "Clacks", "Clacks" },
	{ "FreeRolls", "Free Rolls" },
	{ "Spins", "Jackpot Spins" },
	{ "LuckyRolls", "Lucky Rolls" },
	{ "Rebirths", "Rebirths" },
	{ "Zones", "Zones owned" },
	{ "Studs", "Studs owned" },
	{ "Enemies", "Enemies defeated" },
	{ "BestRoll", "Rarest roll" },
	{ "AccountAge", "Account age" },
}

local gui = roblox.deserializeModel(fs.readFile("tools/ui/designs/Admin.rbxm"))[1]
local fields = gui:FindFirstChild("Fields", true)
assert(fields, "Admin design has no Fields list")

-- One row, as designed, is the template for all of them.
local template
for _, row in fields:GetChildren() do
	if row:IsA("Frame") then
		template = template or row:Clone()
		row:Destroy()
	end
end
assert(template, "Admin design has no field rows")

for order, entry in ROWS do
	local row = template:Clone()
	row.Name = entry[1]
	row.LayoutOrder = order
	row:FindFirstChild("Key").Text = entry[2]
	local value = row:FindFirstChild("Value")
	value.Text = "—"
	value:SetAttribute("AdminField", entry[1])
	row.Parent = fields
end

Kit.save(gui)
