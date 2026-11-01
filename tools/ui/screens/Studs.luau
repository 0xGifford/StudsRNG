--[[
	Studs: the Backpack, Slime RNG style (Controllers/StudsMenu), a MenuSystem
	menu (MenuPanel = the "Studs" frame). BackpackRole marks what the code
	fills:
	  Header        "4/7 Equipped • 956K DMG • x3 Clacks"
	  Sort          button (its Label shows the sort)
	  EquipBest     button
	  Equipped      the equipped row (a horizontal UIListLayout); copies of
	                the EquippedCell template go here
	  Grid          every stud owned (a ScrollingFrame + UIGridLayout; cells
	                stay square, sized off the grid's width and the layout's
	                CellSize X scale); copies of BackpackCell go here
	  Storage       "🎒 120/200" (FullColor attribute: its colour when full)
	  AutoDelete    button (its Label shows the setting)
	  Card          the selected stud's card, with CardViewport, CardName,
	                CardOdds, CardStats, CardLevel, CardOwned and the buttons
	                Equip (UnequipColor attribute: its colour as UNEQUIP),
	                Fuse, Delete, Deselect
	Cell templates (UITemplate = "BackpackCell" / "EquippedCell"): Viewport,
	Odds, Count, Level, Badge (rich text), Check (equipped tick), Button,
	and a UIStroke named MainStroke (StatePreset = "Selected": white while
	picked, MenuSystem StateStyle). Viewports: StudView (Stud attribute).
	The ✕ has MenuAction = "close".
]]

local Kit = require("../Kit")
local UDim2, UDim, Vector2, Color3, Enum = Kit.UDim2, Kit.UDim, Kit.Vector2, Kit.Color3, Kit.Enum

local FONT = Kit.Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local PANEL = Color3.fromRGB(30, 31, 40)
local CARD = Color3.fromRGB(44, 46, 58)
local EDGE = Color3.fromRGB(12, 12, 16)
local GREEN = Color3.fromRGB(70, 200, 90)
local BLUE = Color3.fromRGB(60, 140, 255)
local RED = Color3.fromRGB(230, 50, 50)
local ODDS = Color3.fromRGB(150, 210, 255)
local WHITE = Color3.new(1, 1, 1)

local function round(parent: any, radius: number)
	Kit.new("UICorner", { CornerRadius = UDim.new(radius, 0) }, parent)
end
local function outline(parent: any, color: any, thickness: number): any
	return Kit.new("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end
local function text(parent: any, name: string, value: string, color: any, size: any, position: any, align: any?): any
	local label = Kit.new("TextLabel", {
		Name = name, BackgroundTransparency = 1, Size = size, Position = position, FontFace = FONT, TextScaled = true, RichText = true,
		TextColor3 = color, TextXAlignment = align or Enum.TextXAlignment.Center, Text = value, ZIndex = 3,
	}, parent)
	Kit.new("UIStroke", { Thickness = 2, Color = EDGE }, label)
	return label
end
local function button(parent: any, name: string, value: string, color: any): any
	local b = Kit.new("TextButton", { Name = name, Text = "", AutoButtonColor = true, BackgroundColor3 = color, ZIndex = 3 }, parent)
	round(b, 0.18)
	outline(b, EDGE, 3)
	Kit.new("UIGradient", { Color = Kit.ColorSequence.new(WHITE, Color3.fromRGB(190, 190, 190)), Rotation = 90 }, b)
	text(b, "Label", value, WHITE, UDim2.fromScale(0.9, 0.72), UDim2.fromScale(0.05, 0.14)).ZIndex = 5
	return b
end
local function role(instance: any, name: string): any
	instance:SetAttribute("BackpackRole", name)
	return instance
end

-- A stud cell (both templates share the look).
local function cell(parent: any, template: string, size: any): any
	local frame = Kit.new("Frame", { Name = template, BackgroundColor3 = CARD, Size = size, Visible = false }, parent)
	frame:SetAttribute("UITemplate", template)
	frame:SetAttribute("StatePreset", "Selected") -- MenuSystem's StateStyle: MainStroke turns white when picked
	round(frame, 0.1)
	outline(frame, EDGE, 2).Name = "MainStroke"
	Kit.rarityBackdrop().Parent = frame -- tinted by the stud's rarity
	Kit.viewport({ Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromScale(0.82, 0.82), ZIndex = 2, Parent = frame })
	text(frame, "Odds", "1/2", ODDS, UDim2.fromScale(0.95, 0.22), UDim2.fromScale(0.025, 0.76))
	text(frame, "Count", "x2", WHITE, UDim2.fromScale(0.36, 0.18), UDim2.fromScale(0.62, 0.03), Enum.TextXAlignment.Right)
	text(frame, "Level", "Lv. 2", Color3.fromRGB(120, 200, 255), UDim2.fromScale(0.5, 0.18), UDim2.fromScale(0.25, 0.03))
	text(frame, "Badge", '<font color="#FFE070">✨</font>', WHITE, UDim2.fromScale(0.42, 0.17), UDim2.fromScale(0.03, 0.03), Enum.TextXAlignment.Left)
	text(frame, "Check", "✓", GREEN, UDim2.fromScale(0.3, 0.22), UDim2.fromScale(0.68, 0.55), Enum.TextXAlignment.Right).ZIndex = 5
	Kit.new("TextButton", { Name = "Button", Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 6 }, frame)
	return frame
end

local root = Kit.new("Frame", {
	Name = "Studs", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromScale(0.62, 0.68),
	BackgroundTransparency = 1,
})
Kit.new("UIAspectRatioConstraint", { AspectRatio = 1.55 }, root)
Kit.new("UISizeConstraint", { MaxSize = Vector2.new(1100, 710) }, root)
local gui = Kit.panelMenu("Studs", root)

-- Title and top buttons.
text(root, "Title", "Backpack", WHITE, UDim2.fromScale(0.42, 0.12), UDim2.fromScale(0, -0.02), Enum.TextXAlignment.Left)
local sort = role(button(root, "Sort", "SORT: RARITY", GREEN), "Sort")
sort.Position = UDim2.fromScale(0.5, 0)
sort.Size = UDim2.fromScale(0.2, 0.075)
local best = role(button(root, "EquipBest", "EQUIP BEST", BLUE), "EquipBest")
best.Position = UDim2.fromScale(0.715, 0)
best.Size = UDim2.fromScale(0.19, 0.075)
local close = button(root, "Close", "X", RED)
close:SetAttribute("MenuAction", "close")
close.Position = UDim2.fromScale(0.92, -0.01)
close.Size = UDim2.fromScale(0.075, 0.1)

-- Main panel.
local panel = Kit.new("Frame", { Name = "Main", Position = UDim2.fromScale(0, 0.1), Size = UDim2.fromScale(1, 0.9), BackgroundColor3 = PANEL }, root)
round(panel, 0.035)
outline(panel, EDGE, 4)
role(text(panel, "Header", "0/3 Equipped  •  0 DMG  •  x1 Clacks", WHITE, UDim2.fromScale(0.7, 0.06), UDim2.fromScale(0.15, 0.02)), "Header")

local row = role(Kit.new("Frame", {
	Name = "Equipped", BackgroundTransparency = 1, Position = UDim2.fromScale(0.02, 0.09), Size = UDim2.fromScale(0.96, 0.17),
}, panel), "Equipped")
Kit.new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0.012, 0),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, row)
local equippedCell = cell(row, "EquippedCell", UDim2.fromScale(0.105, 1))
Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }, equippedCell)

Kit.new("Frame", {
	Name = "Divider", Position = UDim2.fromScale(0.08, 0.285), Size = UDim2.fromScale(0.84, 0.006), BackgroundColor3 = Color3.fromRGB(70, 72, 86),
	BorderSizePixel = 0,
}, panel)

local grid = role(Kit.new("ScrollingFrame", {
	Name = "Grid", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromScale(0.02, 0.31), Size = UDim2.fromScale(0.96, 0.59),
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 6,
}, panel), "Grid")
Kit.new("UIGridLayout", {
	CellSize = UDim2.new(0.148, 0, 0, 100), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, grid)
cell(grid, "BackpackCell", UDim2.fromOffset(100, 100))

-- Footer.
local storage = role(text(panel, "Storage", "🎒 0/100", WHITE, UDim2.fromScale(0.25, 0.06), UDim2.fromScale(0.03, 0.915), Enum.TextXAlignment.Left), "Storage")
storage:SetAttribute("FullColor", RED)
local auto = role(button(panel, "AutoDelete", "AUTO DELETE: OFF", Color3.fromRGB(90, 90, 110)), "AutoDelete")
auto.Position = UDim2.fromScale(0.66, 0.905)
auto.Size = UDim2.fromScale(0.31, 0.075)

-- The selected stud's card (over the right of the grid).
local card = role(Kit.new("Frame", {
	Name = "Card", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1.015, 0.29), Size = UDim2.fromScale(0.3, 0.62),
	BackgroundColor3 = Color3.fromRGB(24, 25, 32), Visible = false, ZIndex = 8,
}, panel), "Card")
round(card, 0.06)
outline(card, EDGE, 4)
role(Kit.viewport({ Position = UDim2.fromScale(0.5, 0.18), Size = UDim2.fromScale(0.5, 0.5), ZIndex = 9, Parent = card }), "CardViewport")
for _, info in {
	{ "CardName", "STUD", WHITE, UDim2.fromScale(0.92, 0.08), UDim2.fromScale(0.04, 0.37) },
	{ "CardOdds", "1/2 · Common", ODDS, UDim2.fromScale(0.9, 0.06), UDim2.fromScale(0.05, 0.45) },
	{ "CardStats", "💪 1   ❤️ 1   💰 x1", WHITE, UDim2.fromScale(0.92, 0.06), UDim2.fromScale(0.04, 0.52) },
	{ "CardLevel", "⭐ Lv. 1 · 0/10 XP", Color3.fromRGB(120, 200, 255), UDim2.fromScale(0.9, 0.055), UDim2.fromScale(0.05, 0.585) },
	{ "CardOwned", "1 owned · 0 equipped", Color3.fromRGB(190, 195, 215), UDim2.fromScale(0.9, 0.05), UDim2.fromScale(0.05, 0.645) },
} do
	role(text(card, string.sub(info[1], 5), info[2], info[3], info[4], info[5]), info[1]).ZIndex = 9
end
for _, info in {
	{ "Equip", "EQUIP", GREEN, UDim2.fromScale(0.06, 0.71), UDim2.fromScale(0.88, 0.085) },
	{ "Fuse", "FUSE 0/5", Color3.fromRGB(160, 90, 230), UDim2.fromScale(0.06, 0.805), UDim2.fromScale(0.56, 0.085) },
	{ "Delete", "DELETE", RED, UDim2.fromScale(0.64, 0.805), UDim2.fromScale(0.3, 0.085) },
	{ "Deselect", "CLOSE", Color3.fromRGB(70, 72, 86), UDim2.fromScale(0.06, 0.9), UDim2.fromScale(0.88, 0.075) },
} do
	local b = role(button(card, info[1], info[2], info[3]), info[1])
	b.Position = info[4]
	b.Size = info[5]
	b.ZIndex = 9
	for _, d in b:GetDescendants() do
		if d:IsA("GuiObject") then d.ZIndex = 10 end
	end
	if info[1] == "Equip" then
		b:SetAttribute("UnequipColor", Color3.fromRGB(220, 140, 40))
	end
end

Kit.save(gui)
