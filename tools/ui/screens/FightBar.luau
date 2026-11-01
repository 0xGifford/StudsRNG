--[[
	FightBar: your studs' team bar while they fight (Controllers/Enemies).
	The code shows it during a fight; FightRole marks what it fills:
	  Panel     what throbs when Health is low
	  Strength  "💪 1.2K / sec"         Fill   the Health fill (Size X)
	  Hp        "❤ 300 / 500"            Streak "🔥 STREAK x4 ..." (hidden at < 2)
	  Retreat   the RETREAT button (calls the studs back)
]]

local Kit = require("../Kit")
local UDim2, UDim, Vector2, Color3, Enum = Kit.UDim2, Kit.UDim, Kit.Vector2, Kit.Color3, Kit.Enum

local FONT = Kit.Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)

local gui = Kit.new("ScreenGui", { Name = "FightBar", ResetOnSpawn = false, DisplayOrder = 4, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })

local panel = Kit.new("Frame", {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.11), Size = UDim2.fromScale(0.3, 0.08),
	BackgroundTransparency = 1,
}, gui)
panel:SetAttribute("FightRole", "Panel")
Kit.new("UIAspectRatioConstraint", { AspectRatio = 6 }, panel)

local function text(parent: any, name: string, value: string, color: any, size: any, position: any): any
	local l = Kit.new("TextLabel", {
		Name = name, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = size, Position = position,
		FontFace = FONT, TextScaled = true, TextWrapped = false, TextColor3 = color, Text = value,
	}, parent)
	Kit.new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(15, 15, 20) }, l)
	l:SetAttribute("FightRole", name)
	return l
end

text(panel, "Heading", "YOUR STUDS", Color3.new(1, 1, 1), UDim2.fromScale(0.5, 0.36), UDim2.fromScale(0.3, 0.18))
text(panel, "Strength", "💪 0 / sec", Color3.fromRGB(255, 200, 90), UDim2.fromScale(0.4, 0.36), UDim2.fromScale(0.78, 0.18))

local back = Kit.new("Frame", {
	Name = "Bar", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(0.78, 0.5), Position = UDim2.fromScale(0.39, 0.72),
	BackgroundColor3 = Color3.fromRGB(25, 25, 32), BorderSizePixel = 0,
}, panel)
Kit.new("UICorner", { CornerRadius = UDim.new(1, 0) }, back)
Kit.new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(10, 10, 14) }, back)
local fill = Kit.new("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(90, 230, 100), BorderSizePixel = 0 }, back)
Kit.new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
fill:SetAttribute("FightRole", "Fill")
text(back, "Hp", "❤ 0 / 0", Color3.new(1, 1, 1), UDim2.fromScale(0.9, 0.8), UDim2.fromScale(0.5, 0.5)).ZIndex = 3

local streak = text(panel, "Streak", "🔥 STREAK x2", Color3.fromRGB(255, 150, 60), UDim2.fromScale(0.6, 0.4), UDim2.fromScale(0.39, 1.25))
streak.Visible = false

local retreat = Kit.button("Sunset", "RETREAT", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.9, 0.72), Size = UDim2.fromScale(0.2, 0.62),
})
retreat.Name = "Retreat"
retreat:SetAttribute("FightRole", "Retreat")
retreat.Parent = panel

Kit.save(gui)
