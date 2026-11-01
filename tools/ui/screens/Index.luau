--[[
	Index: the Stud Index, Slime RNG style (Controllers/IndexMenu), a
	MenuSystem menu (MenuPanel = the "Index" frame). IndexRole marks what the
	code fills; templates (UITemplate) are copied per variant / per stud:
	  Tabs            the tab column (a layout); copies of IndexTab go here
	  IndexTab        template: a variant tab: Viewport, Label (the variant);
	                  StatePreset = "Selected": its MainStroke shows the open tab
	  Grid            the stud grid (a ScrollingFrame + UIGridLayout); copies of
	                  IndexCell: Name, Viewport, Odds, Button (select)
	  Detail*         the selected stud: DetailViewport, DetailName, DetailOdds,
	                  DetailRarity, DetailStrength, DetailHealth, DetailRolls
	  ProgressFill / ProgressText   "Unlocks Needed" bar (the fill's Progress
	                attribute sizes it: MenuSystem ProgressBar)
	  RewardLuck / RewardClacks     the tab reward amounts
	  Claim           the claim button (kit button; KitColor = its colour)
	Viewports carry Stud / StudVariant / ViewSilhouette (MenuSystem StudView).
	The ✕ has MenuAction = "close".
]]

local Kit = require("../Kit")
local UDim2, UDim, Vector2, Color3, Enum = Kit.UDim2, Kit.UDim, Kit.Vector2, Kit.Color3, Kit.Enum

local FONT = Kit.Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local PANEL = Color3.fromRGB(24, 25, 31)
local CARD = Color3.fromRGB(38, 40, 50)
local DARK = Color3.fromRGB(12, 12, 16)
local ODDS = Color3.fromRGB(150, 210, 255)

local function round(parent: any, radius: number)
	Kit.new("UICorner", { CornerRadius = UDim.new(radius, 0) }, parent)
end
local function outline(parent: any, color: any, thickness: number): any
	return Kit.new("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end
local function box(parent: any, name: string, size: any, position: any, color: any, anchor: any?): any
	return Kit.new("Frame", {
		Name = name, AnchorPoint = anchor or Vector2.new(0, 0), Size = size, Position = position, BackgroundColor3 = color, BorderSizePixel = 0,
	}, parent)
end
local function text(parent: any, name: string, value: string, color: any, size: any, position: any, align: any?): any
	local l = Kit.new("TextLabel", {
		Name = name, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = size, Position = position, FontFace = FONT,
		TextScaled = true, TextWrapped = false, TextXAlignment = align or Enum.TextXAlignment.Center, TextColor3 = color, Text = value, ZIndex = 3,
	}, parent)
	outline(l, DARK, 2).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	return l
end
local function role(instance: any, name: string): any
	instance:SetAttribute("IndexRole", name)
	return instance
end

-- The window (the MenuPanel), centred.
local root = Kit.new("Frame", {
	Name = "Index", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.53), Size = UDim2.fromScale(0.8, 0.74),
	BackgroundTransparency = 1,
})
Kit.new("UIAspectRatioConstraint", { AspectRatio = 1.75 }, root)
Kit.new("UISizeConstraint", { MaxSize = Vector2.new(1240, 710) }, root)
local gui = Kit.panelMenu("Index", root)

-- Tabs down the left.
local tabColumn = role(box(root, "Tabs", UDim2.fromScale(0.085, 0.92), UDim2.fromScale(0, 0.06), Color3.new()), "Tabs")
tabColumn.BackgroundTransparency = 1
Kit.new("UIListLayout", { Padding = UDim.new(0.018, 0), SortOrder = Enum.SortOrder.LayoutOrder }, tabColumn)
local tab = Kit.new("TextButton", {
	Name = "IndexTab", Text = "", AutoButtonColor = false, BackgroundColor3 = CARD, Size = UDim2.fromScale(1, 0.15), Visible = false,
}, tabColumn)
tab:SetAttribute("UITemplate", "IndexTab")
tab:SetAttribute("StatePreset", "Selected") -- MenuSystem's StateStyle: its MainStroke turns white when picked
round(tab, 0.12)
outline(tab, DARK, 2).Name = "MainStroke"
local tabView = Kit.viewport({ Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.72, 0.72) })
tabView.Parent = tab
text(tab, "Label", "Normal", Color3.new(1, 1, 1), UDim2.fromScale(0.95, 0.26), UDim2.fromScale(0.5, 0.85))

-- Main panel.
local main = box(root, "Main", UDim2.fromScale(0.9, 0.92), UDim2.fromScale(0.1, 0.06), PANEL)
round(main, 0.04)
outline(main, Color3.fromRGB(10, 10, 14), 4)
local title = text(root, "Title", "Stud Index", Color3.new(1, 1, 1), UDim2.fromScale(0.36, 0.12), UDim2.fromScale(0.105, 0.06), Enum.TextXAlignment.Left)
title.AnchorPoint = Vector2.new(0, 0.5)
title.ZIndex = 6

-- Grid.
local gridBack = box(main, "GridBack", UDim2.fromScale(0.625, 0.7), UDim2.fromScale(0.02, 0.06), Color3.fromRGB(18, 18, 24))
round(gridBack, 0.04)
local grid = role(Kit.new("ScrollingFrame", {
	Name = "Grid", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(0.96, 0.94), Position = UDim2.fromScale(0.02, 0.03),
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 6,
}, gridBack), "Grid")
Kit.new("UIGridLayout", { CellSize = UDim2.new(0.18, 0, 0, 100), CellPadding = UDim2.new(0.02, 0, 0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
local cell = Kit.new("Frame", { Name = "IndexCell", BackgroundColor3 = CARD, BorderSizePixel = 0, Visible = false }, grid)
cell:SetAttribute("UITemplate", "IndexCell")
cell:SetAttribute("StatePreset", "Selected")
round(cell, 0.1)
outline(cell, DARK, 2).Name = "MainStroke"
text(cell, "Name", "???", Color3.new(1, 1, 1), UDim2.fromScale(0.92, 0.17), UDim2.fromScale(0.5, 0.13))
local cellView = Kit.viewport({ Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromScale(0.62, 0.62) })
cellView.Parent = cell
local odds = text(cell, "Odds", "1/2", ODDS, UDim2.fromScale(0.6, 0.17), UDim2.fromScale(0.95, 0.88), Enum.TextXAlignment.Right)
odds.AnchorPoint = Vector2.new(1, 0.5)
Kit.new("TextButton", { Name = "Button", BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 5 }, cell)

-- Unlocks needed.
text(main, "Book", "📘", Color3.new(1, 1, 1), UDim2.fromScale(0.07, 0.13), UDim2.fromScale(0.05, 0.875)).ZIndex = 5
text(main, "UnlocksLabel", "Unlocks Needed:", Color3.new(1, 1, 1), UDim2.fromScale(0.25, 0.06), UDim2.fromScale(0.085, 0.81), Enum.TextXAlignment.Left).AnchorPoint = Vector2.new(0, 0.5)
local barBack = box(main, "Progress", UDim2.fromScale(0.55, 0.075), UDim2.fromScale(0.08, 0.84), Color3.fromRGB(14, 14, 18))
round(barBack, 1)
outline(barBack, Color3.fromRGB(8, 8, 10), 3)
local fill = role(box(barBack, "Fill", UDim2.fromScale(0, 1), UDim2.new(), Color3.fromRGB(40, 150, 255)), "ProgressFill")
fill:SetAttribute("Progress", 0) -- MenuSystem's ProgressBar sizes it
round(fill, 1)
Kit.new("UIGradient", { Color = Kit.ColorSequence.new(Color3.fromRGB(40, 220, 210), Color3.fromRGB(40, 120, 255)) }, fill)
role(text(barBack, "Text", "0/0", Color3.new(1, 1, 1), UDim2.fromScale(0.5, 0.85), UDim2.fromScale(0.5, 0.5)), "ProgressText").ZIndex = 4

-- Detail card.
local card = box(main, "Detail", UDim2.fromScale(0.31, 0.5), UDim2.fromScale(0.665, 0.06), Color3.fromRGB(18, 18, 24))
round(card, 0.06)
role(Kit.viewport({ Position = UDim2.fromScale(0.5, 0.25), Size = UDim2.fromScale(0.55, 0.55), Parent = card }), "DetailViewport")
local white = Color3.new(1, 1, 1)
role(text(card, "Name", "???", white, UDim2.fromScale(0.9, 0.11), UDim2.fromScale(0.5, 0.53)), "DetailName")
role(text(card, "Odds", "1 / 2", white, UDim2.fromScale(0.6, 0.1), UDim2.fromScale(0.5, 0.64)), "DetailOdds")
role(text(card, "Rarity", "Common", white, UDim2.fromScale(0.6, 0.09), UDim2.fromScale(0.5, 0.74)), "DetailRarity")
role(text(card, "Strength", "💪 0", white, UDim2.fromScale(0.4, 0.09), UDim2.fromScale(0.28, 0.84)), "DetailStrength")
role(text(card, "Health", "❤️ 0", white, UDim2.fromScale(0.4, 0.09), UDim2.fromScale(0.72, 0.84)), "DetailHealth")
role(text(card, "Rolls", "🎲 Rolls: 0", white, UDim2.fromScale(0.7, 0.09), UDim2.fromScale(0.5, 0.94)), "DetailRolls")

-- Tab reward.
local rewards = box(main, "Rewards", UDim2.fromScale(0.31, 0.33), UDim2.fromScale(0.665, 0.6), Color3.fromRGB(18, 18, 24))
round(rewards, 0.08)
text(rewards, "Heading", "Rewards:", white, UDim2.fromScale(0.4, 0.15), UDim2.fromScale(0.05, 0.13), Enum.TextXAlignment.Left).AnchorPoint = Vector2.new(0, 0.5)
for i, reward in { { "Luck", "🍀" }, { "Clacks", "" } } do
	local tile = box(rewards, `{reward[1]}Tile`, UDim2.fromScale(0.24, 0.42), UDim2.fromScale(0.25 + (i - 1) * 0.27, 0.25), CARD)
	round(tile, 0.12)
	outline(tile, DARK, 2)
	if reward[2] == "" then
		Kit.new("ImageLabel", {
			Name = "Icon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4),
			Size = UDim2.fromScale(0.6, 0.6), ScaleType = Enum.ScaleType.Fit, Image = "rbxassetid://117187305699068",
		}, tile)
	else
		text(tile, "Icon", reward[2], white, UDim2.fromScale(0.7, 0.55), UDim2.fromScale(0.5, 0.4))
	end
	role(text(tile, "Amount", "+5%", white, UDim2.fromScale(0.9, 0.3), UDim2.fromScale(0.5, 0.85)), `Reward{reward[1]}`)
end
local claim = Kit.button("Green", "CLAIM", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.83), Size = UDim2.fromScale(0.7, 0.26) })
claim.Name = "Claim"
claim:SetAttribute("KitColor", "Green") -- MenuSystem's KitColor paints it
role(claim, "Claim").Parent = rewards

-- Close.
local close = Kit.new("TextButton", {
	Name = "Close", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.985, 0.06), Size = UDim2.fromScale(0.065, 0.115),
	BackgroundColor3 = Color3.fromRGB(230, 40, 40), Text = "", ZIndex = 6,
}, root)
close:SetAttribute("MenuAction", "close")
round(close, 0.15)
outline(close, white, 3)
text(close, "X", "X", white, UDim2.fromScale(0.7, 0.75), UDim2.fromScale(0.5, 0.5)).ZIndex = 7

Kit.save(gui)
