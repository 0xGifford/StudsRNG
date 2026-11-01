--[[
	Tutorial: the first-session guide (Controllers/TutorialGuide). Enabled
	while a step is shown; TutorialRole marks what the code moves and fills:
	  Panel      the step card (top centre)
	  Step       "STEP 2 / 6"           Text   what to do
	  Fill       the progress bar's fill (Size X = progress)
	  Highlight  the ring placed over the HUD button to press
	  Arrow      "▼" over that button
	  WorldArrow a BillboardGui over the spot to walk to (the code adorns it)
]]

local Kit = require("../Kit")
local UDim2, UDim, Vector2, Color3, Enum = Kit.UDim2, Kit.UDim, Kit.Vector2, Kit.Color3, Kit.Enum

local FONT = Kit.Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local ACCENT = Color3.fromRGB(255, 220, 90)

local gui = Kit.new("ScreenGui", {
	Name = "Tutorial", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 15, Enabled = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local function label(parent: any, name: string, value: string, size: any, position: any): any
	local l = Kit.new("TextLabel", {
		Name = name, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = size, Position = position,
		TextScaled = true, FontFace = FONT, TextColor3 = Color3.new(1, 1, 1), Text = value, ZIndex = 3,
	}, parent)
	Kit.new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(15, 15, 20) }, l)
	l:SetAttribute("TutorialRole", name)
	return l
end

local panel = Kit.new("Frame", {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.115), Size = UDim2.fromScale(0.36, 0.1),
	BackgroundColor3 = Color3.fromRGB(20, 18, 30), BackgroundTransparency = 0.25,
}, gui)
panel:SetAttribute("TutorialRole", "Panel")
Kit.new("UICorner", { CornerRadius = UDim.new(0.25, 0) }, panel)
Kit.new("UIStroke", { Color = ACCENT, Thickness = 2.5 }, panel)
Kit.new("UIAspectRatioConstraint", { AspectRatio = 6 }, panel)

label(panel, "Step", "STEP 1 / 6", UDim2.fromScale(0.5, 0.26), UDim2.fromScale(0.5, 0.2)).TextColor3 = ACCENT
label(panel, "Text", "Walk on the keys to earn Clacks", UDim2.fromScale(0.92, 0.36), UDim2.fromScale(0.5, 0.52))

local track = Kit.new("Frame", {
	Name = "Track", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.84), Size = UDim2.fromScale(0.8, 0.12),
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4,
}, panel)
Kit.new("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
local fill = Kit.new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = ACCENT }, track)
fill:SetAttribute("TutorialRole", "Fill")
Kit.new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)

local highlight = Kit.new("Frame", { Name = "Highlight", BackgroundTransparency = 1, Visible = false, ZIndex = 4 }, gui)
highlight:SetAttribute("TutorialRole", "Highlight")
Kit.new("UIStroke", { Color = ACCENT, Thickness = 4 }, highlight)
Kit.new("UICorner", { CornerRadius = UDim.new(0.2, 0) }, highlight)

local arrow = label(gui, "Arrow", "▼", UDim2.fromOffset(44, 44), UDim2.new())
arrow.TextColor3 = ACCENT
arrow.Visible = false

local worldArrow = Kit.new("BillboardGui", { Name = "WorldArrow", Size = UDim2.fromScale(3, 3), AlwaysOnTop = true, Enabled = false }, gui)
worldArrow:SetAttribute("TutorialRole", "WorldArrow")
label(worldArrow, "WorldArrowText", "▼", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5)).TextColor3 = ACCENT

Kit.save(gui)
