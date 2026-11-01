--[[
	Achievements: every achievement with its progress and reward
	(Controllers/AchievementsMenu), a MenuSystem menu (MenuPanel = the
	"Achievements" frame). AchievementRole marks what the code fills:
	  Header        "🏅 Achievements  3/40"
	  Title         the worn title line (its colour follows the title's)
	  RemoveTitle   button: take the title off
	  List          the ScrollingFrame (a UIListLayout) the cards go in
	  Card          template (UITemplate = "AchievementCard"): Name, Text,
	                Reward, Fill (the bar), Progress, Wear (a button with a
	                Label). The card's DoneColor attribute is its colour once
	                finished; Wear's WearingColor is its colour while worn.
	The ✕ has MenuAction = "close".
]]

local Kit = require("../Kit")
local UDim2, UDim, Vector2, Color3, Enum = Kit.UDim2, Kit.UDim, Kit.Vector2, Kit.Color3, Kit.Enum

local FONT = Kit.Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local PANEL = Color3.fromRGB(30, 32, 44)
local CARD = Color3.fromRGB(40, 43, 58)
local DONE = Color3.fromRGB(34, 60, 44)
local GOLD = Color3.fromRGB(255, 205, 60)
local GREEN = Color3.fromRGB(120, 255, 140)
local DARK = Color3.fromRGB(10, 10, 14)
local WHITE = Color3.new(1, 1, 1)

local function round(parent: any, radius: number)
	Kit.new("UICorner", { CornerRadius = UDim.new(radius, 0) }, parent)
end
local function text(parent: any, name: string, value: string, color: any, size: any, position: any, align: any?): any
	local label = Kit.new("TextLabel", {
		Name = name, BackgroundTransparency = 1, Size = size, Position = position, FontFace = FONT, TextScaled = true,
		TextColor3 = color, TextXAlignment = align or Enum.TextXAlignment.Left, Text = value, ZIndex = 3,
	}, parent)
	Kit.new("UIStroke", { Thickness = 1.5, Color = DARK }, label)
	return label
end
local function pill(parent: any, name: string, value: string, color: any): any
	local button = Kit.new("TextButton", { Name = name, AutoButtonColor = true, Text = "", BackgroundColor3 = color, ZIndex = 3 }, parent)
	round(button, 0.3)
	Kit.new("UIStroke", { Thickness = 2, Color = DARK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
	text(button, "Label", value, WHITE, UDim2.fromScale(0.86, 0.7), UDim2.fromScale(0.07, 0.15), Enum.TextXAlignment.Center).ZIndex = 4
	return button
end
local function role(instance: any, name: string): any
	instance:SetAttribute("AchievementRole", name)
	return instance
end

local root = Kit.new("Frame", {
	Name = "Achievements", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.53), Size = UDim2.fromScale(0.6, 0.76),
	BackgroundColor3 = PANEL,
})
round(root, 0.04)
Kit.new("UIStroke", { Thickness = 4, Color = DARK }, root)
Kit.new("UIAspectRatioConstraint", { AspectRatio = 1.2 }, root)
Kit.new("UISizeConstraint", { MaxSize = Vector2.new(860, 720) }, root)
local gui = Kit.panelMenu("Achievements", root)

role(text(root, "Header", "🏅 Achievements  0/0", WHITE, UDim2.new(0.7, 0, 0, 40), UDim2.new(0, 20, 0, 14)), "Header")
role(text(root, "Title", "Unlock achievements to earn titles", GOLD, UDim2.new(0.6, 0, 0, 22), UDim2.new(0, 20, 0, 58)), "Title")
local remove = role(pill(root, "RemoveTitle", "REMOVE TITLE", Color3.fromRGB(200, 60, 60)), "RemoveTitle")
remove.AnchorPoint = Vector2.new(1, 0)
remove.Size = UDim2.new(0.24, 0, 0, 28)
remove.Position = UDim2.new(1, -70, 0, 55)

local list = role(Kit.new("ScrollingFrame", {
	Name = "List", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.new(0, 14, 0, 92), Size = UDim2.new(1, -28, 1, -106),
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 6,
}, root), "List")
Kit.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)

-- The card template.
local card = Kit.new("Frame", { Name = "AchievementCard", Size = UDim2.new(1, -14, 0, 84), BackgroundColor3 = CARD, Visible = false }, list)
card:SetAttribute("UITemplate", "AchievementCard")
card:SetAttribute("DoneColor", DONE)
round(card, 0.12)
text(card, "Name", "Achievement", WHITE, UDim2.new(0.5, 0, 0, 24), UDim2.new(0, 14, 0, 8))
text(card, "Text", "Do the thing 100 times", Color3.fromRGB(190, 195, 215), UDim2.new(0.55, 0, 0, 18), UDim2.new(0, 14, 0, 34))
text(card, "Reward", "🎁 100 Clacks", GOLD, UDim2.new(0.4, -14, 0, 20), UDim2.new(0.6, 0, 0, 8), Enum.TextXAlignment.Right)
local back = Kit.new("Frame", {
	Name = "Bar", Size = UDim2.new(0.55, 0, 0, 14), Position = UDim2.new(0, 14, 0, 60), BackgroundColor3 = Color3.fromRGB(18, 18, 24), ZIndex = 2,
}, card)
round(back, 0.5)
round(Kit.new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.4, 1), BackgroundColor3 = GREEN, ZIndex = 2 }, back), 0.5)
text(card, "Progress", "40 / 100", WHITE, UDim2.new(0.2, 0, 0, 16), UDim2.new(0.58, 0, 0, 59))
local wear = pill(card, "Wear", "WEAR « Title »", Color3.fromRGB(70, 130, 255))
wear:SetAttribute("WearingColor", Color3.fromRGB(60, 170, 90))
wear.AnchorPoint = Vector2.new(1, 0)
wear.Size = UDim2.new(0.3, 0, 0, 34)
wear.Position = UDim2.new(1, -14, 0, 38)

-- Close.
local close = Kit.new("TextButton", {
	Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(46, 46),
	BackgroundColor3 = Color3.fromRGB(230, 40, 40), Text = "", ZIndex = 4,
}, root)
close:SetAttribute("MenuAction", "close")
round(close, 0.2)
Kit.new("UIStroke", { Thickness = 3, Color = WHITE, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, close)
text(close, "X", "X", WHITE, UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.15, 0.15), Enum.TextXAlignment.Center).ZIndex = 5

Kit.save(gui)
