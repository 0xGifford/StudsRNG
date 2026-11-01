--[[
	ZoneBoss: the Titan countdown chip and the raid panel (Controllers/
	ZoneBossHud). BossRole marks what the code fills:
	  Chip   "👹 TITANS IN 12:34"           Panel  the raid panel (shown near a Titan)
	  Name   the Titan's name               Time   time left
	  Fill   the health bar's fill (its Progress attribute = health share)
	  Hp     "1.2M / 4M"                     Mine   your rank / damage
	  Row    the top-damage rows, BossRow = 1..5
	The panel's UIScale is set to fit the screen width.
]]

local Kit = require("../Kit")
local UDim2, UDim, Vector2, Color3, Enum = Kit.UDim2, Kit.UDim, Kit.Vector2, Kit.Color3, Kit.Enum

local FONT = Kit.Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local RED = Color3.fromRGB(255, 70, 60)
local GOLD = Color3.fromRGB(255, 205, 60)

local gui = Kit.new("ScreenGui", { Name = "ZoneBoss", ResetOnSpawn = false, DisplayOrder = 4, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })

local function text(name: string, parent: any, value: string, color: any, size: any, position: any, align: any?): any
	local label = Kit.new("TextLabel", {
		Name = name, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = size, Position = position,
		FontFace = FONT, TextScaled = true, TextColor3 = color, TextXAlignment = align or Enum.TextXAlignment.Center, Text = value,
	}, parent)
	Kit.new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(12, 12, 18) }, label)
	return label
end

local chip = text("Chip", gui, "👹 TITANS IN 0:00", Color3.new(1, 1, 1), UDim2.fromOffset(210, 30), UDim2.new(1, -120, 0, 24))
chip.BackgroundTransparency = 0.25
chip.BackgroundColor3 = Color3.fromRGB(30, 14, 18)
chip:SetAttribute("BossRole", "Chip")
Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, chip)
Kit.new("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5) }, chip)

local panel = Kit.new("Frame", {
	Name = "Raid", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 46), Size = UDim2.fromOffset(420, 200),
	BackgroundColor3 = Color3.fromRGB(22, 14, 20), BackgroundTransparency = 0.15, Visible = false,
}, gui)
panel:SetAttribute("BossRole", "Panel")
Kit.new("UICorner", { CornerRadius = UDim.new(0.08, 0) }, panel)
Kit.new("UIStroke", { Color = RED, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
Kit.new("UIScale", {}, panel)

text("Name", panel, "👹 TITAN", RED, UDim2.new(1, -20, 0, 26), UDim2.new(0.5, 0, 0, 20)):SetAttribute("BossRole", "Name")
text("Time", panel, "", Color3.fromRGB(255, 220, 200), UDim2.new(0.3, 0, 0, 18), UDim2.new(0.85, 0, 0, 20), Enum.TextXAlignment.Right):SetAttribute("BossRole", "Time")

local back = Kit.new("Frame", {
	Name = "Bar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 38), Size = UDim2.new(1, -24, 0, 22),
	BackgroundColor3 = Color3.fromRGB(12, 8, 12),
}, panel)
Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, back)
local fill = Kit.new("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = RED }, back)
fill:SetAttribute("BossRole", "Fill")
fill:SetAttribute("Progress", 1) -- MenuSystem's ProgressBar sizes it
Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, fill)
local hp = text("Hp", back, "", Color3.new(1, 1, 1), UDim2.fromScale(0.9, 0.85), UDim2.fromScale(0.5, 0.5))
hp.ZIndex = 3
hp:SetAttribute("BossRole", "Hp")

text("Heading", panel, "TOP DAMAGE", GOLD, UDim2.new(1, -24, 0, 16), UDim2.new(0.5, 0, 0, 74))
for i = 1, 5 do
	local row = text(`Row{i}`, panel, "", Color3.new(1, 1, 1), UDim2.new(1, -40, 0, 16), UDim2.new(0.5, 0, 0, 74 + i * 18), Enum.TextXAlignment.Left)
	row:SetAttribute("BossRole", "Row")
	row:SetAttribute("BossRow", i)
end
text("Mine", panel, "", Color3.fromRGB(120, 255, 140), UDim2.new(1, -40, 0, 18), UDim2.new(0.5, 0, 0, 186), Enum.TextXAlignment.Left):SetAttribute("BossRole", "Mine")

Kit.save(gui)
