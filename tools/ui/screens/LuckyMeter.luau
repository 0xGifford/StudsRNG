--[[
	LuckyMeter: the Lucky Roll meter above the bottom bar
	(Controllers/LuckyMeter, Config.LuckyMeter). Every roll fills it; when
	it's full the next roll is a LUCKY ROLL (x10 luck). LuckyRole marks what
	the code fills:
	  Meter   the whole bar (pulses when the next roll is lucky; its
	          ReadyColor attribute tints the outline then)
	  Fill    the fill (MenuSystem ProgressBar: Progress = rolls / needed)
	  Label   "🍀 LUCKY ROLL 43/100" / "🍀 NEXT ROLL IS LUCKY!"
]]

local Kit = require("../Kit")
local UDim2, UDim, Vector2, Color3, Enum = Kit.UDim2, Kit.UDim, Kit.Vector2, Kit.Color3, Kit.Enum

local FONT = Kit.Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local DARK = Color3.fromRGB(12, 12, 16)

local function role(instance: any, name: string): any
	instance:SetAttribute("LuckyRole", name)
	return instance
end

local gui = Kit.new("ScreenGui", {
	Name = "LuckyMeter", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 3, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local meter = role(Kit.new("Frame", {
	Name = "Meter", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.893), Size = UDim2.fromScale(0.24, 0.03),
	BackgroundColor3 = Color3.fromRGB(20, 22, 30), BackgroundTransparency = 0.15,
}, gui), "Meter")
meter:SetAttribute("ReadyColor", Color3.fromRGB(120, 255, 140))
Kit.new("UISizeConstraint", { MinSize = Vector2.new(200, 20), MaxSize = Vector2.new(380, 34) }, meter)
Kit.new("UICorner", { CornerRadius = UDim.new(1, 0) }, meter)
Kit.new("UIStroke", { Name = "Outline", Thickness = 2.5, Color = DARK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, meter)

local fill = role(Kit.new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.4, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 2 }, meter), "Fill")
fill:SetAttribute("Progress", 0)
Kit.new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
Kit.new("UIGradient", { Color = Kit.ColorSequence.new(Color3.fromRGB(70, 210, 110), Color3.fromRGB(180, 255, 120)) }, fill)

local label = role(Kit.new("TextLabel", {
	Name = "Label", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0.9), Position = UDim2.fromScale(0, 0.05), FontFace = FONT,
	TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Text = "🍀 LUCKY ROLL 0/100", ZIndex = 3,
}, meter), "Label")
Kit.new("UIStroke", { Thickness = 2, Color = DARK }, label)

Kit.save(gui)
