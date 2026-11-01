--[[
	StudPass: the season pass track (Controllers/StudPassMenu), a MenuSystem
	menu (MenuPanel = the "StudPass" frame). PassRole marks what the code
	fills:
	  Season        "🎟️ STUD PASS · <season>"
	  Tier          "Tier 3 → 4"
	  Points        "120 / 300 points"
	  ProgressFill  the bar's fill (its X scale is set)
	  ClaimAll      button: claim every reached reward
	  Unlock        button: buy premium (hidden once owned)
	  Track         the ScrollingFrame (a horizontal UIListLayout) the tier
	                columns go in
	  Column        template (UITemplate = "PassColumn"): Number, and two
	                cards, Free and Premium, each with Icon, Reward, State
	                and a UIStroke (it glows while the reward is claimable).
	                Colour attributes: the column's ReachedColor (tier number
	                once reached); each card's ClaimedColor, LockedColor and
	                ReadyColor (stroke + "CLAIM!" text).
	The ✕ has MenuAction = "close".
]]

local Kit = require("../Kit")
local UDim2, UDim, Vector2, Color3, Enum = Kit.UDim2, Kit.UDim, Kit.Vector2, Kit.Color3, Kit.Enum

local FONT = Kit.Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local PANEL = Color3.fromRGB(28, 26, 44)
local CARD = Color3.fromRGB(44, 42, 64)
local CLAIMED = Color3.fromRGB(34, 64, 46)
local LOCKED = Color3.fromRGB(32, 30, 44)
local GOLD = Color3.fromRGB(255, 205, 60)
local PREMIUM = Color3.fromRGB(120, 70, 200)
local DARK = Color3.fromRGB(10, 10, 14)
local WHITE = Color3.new(1, 1, 1)
local COLUMN = 118

local function round(parent: any, radius: number)
	Kit.new("UICorner", { CornerRadius = UDim.new(radius, 0) }, parent)
end
local function text(parent: any, name: string, value: string, color: any, size: any, position: any, align: any?): any
	local label = Kit.new("TextLabel", {
		Name = name, BackgroundTransparency = 1, Size = size, Position = position, FontFace = FONT, TextScaled = true,
		TextColor3 = color, TextXAlignment = align or Enum.TextXAlignment.Center, Text = value, ZIndex = 3,
	}, parent)
	Kit.new("UIStroke", { Thickness = 1.5, Color = DARK }, label)
	return label
end
local function button(parent: any, name: string, value: string, color: any): any
	local b = Kit.new("TextButton", { Name = name, Text = "", AutoButtonColor = true, BackgroundColor3 = color, ZIndex = 3 }, parent)
	round(b, 0.3)
	Kit.new("UIStroke", { Thickness = 2, Color = DARK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	text(b, "Label", value, WHITE, UDim2.fromScale(0.86, 0.66), UDim2.fromScale(0.07, 0.17)).ZIndex = 4
	return b
end
local function role(instance: any, name: string): any
	instance:SetAttribute("PassRole", name)
	return instance
end

local root = Kit.new("Frame", {
	Name = "StudPass", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.53), Size = UDim2.fromScale(0.86, 0.66),
	BackgroundColor3 = PANEL,
})
round(root, 0.04)
Kit.new("UIStroke", { Thickness = 4, Color = DARK }, root)
Kit.new("UIGradient", { Color = Kit.ColorSequence.new(Color3.fromRGB(60, 40, 100), Color3.fromRGB(26, 24, 40)), Rotation = 90 }, root)
Kit.new("UISizeConstraint", { MaxSize = Vector2.new(1200, 600) }, root)
local gui = Kit.panelMenu("StudPass", root)

role(text(root, "Season", "🎟️ STUD PASS · Season 1", GOLD, UDim2.new(0.6, 0, 0, 34), UDim2.new(0, 20, 0, 12), Enum.TextXAlignment.Left), "Season")
role(text(root, "Tier", "Tier 0 → 1", WHITE, UDim2.new(0.3, 0, 0, 24), UDim2.new(0, 20, 0, 50), Enum.TextXAlignment.Left), "Tier")
role(text(root, "Points", "0 / 100 points", Color3.fromRGB(200, 200, 230), UDim2.new(0.25, 0, 0, 18), UDim2.new(0.3, 0, 0, 54), Enum.TextXAlignment.Left), "Points")

local barBack = Kit.new("Frame", { Name = "Progress", Position = UDim2.new(0, 20, 0, 80), Size = UDim2.new(0.55, 0, 0, 12), BackgroundColor3 = Color3.fromRGB(14, 14, 20) }, root)
round(barBack, 0.5)
local fill = role(Kit.new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.3, 1), BackgroundColor3 = GOLD }, barBack), "ProgressFill")
fill:SetAttribute("Progress", 0.3) -- MenuSystem's ProgressBar sizes it
round(fill, 0.5)

local claimAll = role(button(root, "ClaimAll", "CLAIM ALL", Color3.fromRGB(60, 180, 90)), "ClaimAll")
claimAll.AnchorPoint = Vector2.new(1, 0)
claimAll.Position = UDim2.new(1, -70, 0, 50)
claimAll.Size = UDim2.new(0.14, 0, 0, 40)

local unlock = role(button(root, "Unlock", "UNLOCK PREMIUM", Color3.fromRGB(150, 90, 230)), "Unlock")
unlock.AnchorPoint = Vector2.new(1, 0)
unlock.Position = UDim2.new(0.86, -80, 0, 50)
unlock.Size = UDim2.new(0.18, 0, 0, 40)

text(root, "FreeLabel", "FREE", WHITE, UDim2.new(0, 70, 0, 20), UDim2.new(0, 10, 0.36, 0))
text(root, "PremiumLabel", "PREMIUM", PREMIUM:Lerp(WHITE, 0.4), UDim2.new(0, 70, 0, 20), UDim2.new(0, 10, 0.72, 0))

local track = role(Kit.new("ScrollingFrame", {
	Name = "Track", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.new(0, 84, 0, 104), Size = UDim2.new(1, -100, 1, -116),
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 8,
}, root), "Track")
Kit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder }, track)

-- The column template: tier number, free card, premium card.
local column = Kit.new("Frame", { Name = "PassColumn", BackgroundTransparency = 1, Size = UDim2.new(0, COLUMN, 1, -10), Visible = false }, track)
column:SetAttribute("UITemplate", "PassColumn")
column:SetAttribute("ReachedColor", GOLD)
text(column, "Number", "1", Color3.fromRGB(150, 150, 170), UDim2.new(1, 0, 0.12, 0), UDim2.fromScale(0, 0.02))
for _, info in { { "Free", 0.16, DARK }, { "Premium", 0.58, PREMIUM } } do
	local card = Kit.new("TextButton", {
		Name = info[1], Text = "", AutoButtonColor = false, BackgroundColor3 = CARD, Size = UDim2.new(1, -10, 0.36, 0),
		Position = UDim2.new(0, 5, info[2], 0), ZIndex = 2,
	}, column)
	card:SetAttribute("ClaimedColor", CLAIMED)
	card:SetAttribute("LockedColor", LOCKED)
	card:SetAttribute("ReadyColor", GOLD)
	round(card, 0.12)
	Kit.new("UIStroke", { Thickness = 2, Color = info[3], ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	text(card, "Icon", "🎁", WHITE, UDim2.fromScale(0.6, 0.38), UDim2.fromScale(0.2, 0.06))
	text(card, "Reward", "100 Clacks", WHITE, UDim2.fromScale(0.92, 0.3), UDim2.fromScale(0.04, 0.46))
	text(card, "State", "", Color3.fromRGB(120, 255, 140), UDim2.fromScale(0.9, 0.18), UDim2.fromScale(0.05, 0.79))
end

-- Close.
local close = Kit.new("TextButton", {
	Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(46, 46),
	BackgroundColor3 = Color3.fromRGB(230, 40, 40), Text = "", ZIndex = 4,
}, root)
close:SetAttribute("MenuAction", "close")
round(close, 0.2)
text(close, "X", "X", WHITE, UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.15, 0.15)).ZIndex = 5

Kit.save(gui)
