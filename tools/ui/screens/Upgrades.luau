--[[
	Upgrades: the full-screen upgrade tree (Controllers/UpgradeTree), a
	MenuSystem menu (MenuPanel = Root; Backdrop = false). The honeycomb's
	node positions come from Shared/Upgrades (Q, R); everything you see is
	here. UpgradeRole marks what the code uses:
	  Viewport      the pannable area (drag / scroll / pinch)
	  World         what pans and zooms (a UIScale); Spacing attribute: the
	                distance unit between neighbouring nodes, in pixels
	  Lines / Nodes the layers the line and node copies go in
	  Clacks        "1.2K Clacks"
	  InfoTitle / InfoBody / InfoCost   the details panel
	Templates (UITemplate):
	  UpgradeNode   a node: Fill (any parts named Fill take the state
	                colour), Shine (parts dimmed while locked), Icon, Level,
	                Cost, Button, a UIScale
	  UpgradeLine   a connection (stretched and turned between two nodes)
	State colours are attributes on Root: MaxedColor, AffordableColor,
	AvailableColor, LockedColor, LineOnColor, LineAvailableColor,
	LineOffColor, ErrorColor.
	The ✕ (a kit button) has MenuAction = "close".
]]

local Kit = require("../Kit")
local UDim2, UDim, Vector2, Color3, Enum = Kit.UDim2, Kit.UDim, Kit.Vector2, Kit.Color3, Kit.Enum

local SQRT3 = math.sqrt(3)
local RADIUS = 56
local BORDER = 5
local BORDER_COLOR = Color3.fromRGB(25, 25, 25)

local function role(instance: any, name: string): any
	instance:SetAttribute("UpgradeRole", name)
	return instance
end

-- A pointy-top hexagon as three rectangles (0°, 60°, -60°).
local function hexagon(parent: any, radius: number, color: any, zIndex: number, name: string)
	for _, rotation in { 0, 60, -60 } do
		Kit.new("Frame", {
			Name = name, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(SQRT3 * radius, radius), Rotation = rotation, BackgroundColor3 = color, ZIndex = zIndex,
		}, parent)
	end
end

local root = Kit.new("Frame", {
	Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(22, 18, 34), BorderSizePixel = 0, Active = true,
})
for name, color in {
	MaxedColor = Color3.fromRGB(255, 196, 64),
	AffordableColor = Color3.fromRGB(90, 220, 110),
	AvailableColor = Color3.fromRGB(70, 140, 255),
	LockedColor = Color3.fromRGB(70, 70, 82),
	LineOnColor = Color3.fromRGB(255, 220, 110),
	LineAvailableColor = Color3.fromRGB(200, 200, 215),
	LineOffColor = Color3.fromRGB(55, 55, 65),
	ErrorColor = Color3.fromRGB(255, 120, 120),
} do
	root:SetAttribute(name, color)
end
local gui = Kit.panelMenu("Upgrades", root)
gui.DisplayOrder = 8
gui:SetAttribute("Backdrop", false)

Kit.new("ImageLabel", {
	Name = "Studs", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = "rbxassetid://18878365966",
	ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(96, 96), ImageTransparency = 0.93, ZIndex = 1,
}, root)

local viewport = role(Kit.new("Frame", {
	Name = "Viewport", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ClipsDescendants = true, Active = true, ZIndex = 2,
}, root), "Viewport")
local world = role(Kit.new("Frame", {
	Name = "World", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 2,
}, viewport), "World")
world:SetAttribute("Spacing", 64)
Kit.new("UIScale", {}, world)
local lines = role(Kit.new("Frame", { Name = "Lines", Size = UDim2.new(), BackgroundTransparency = 1, ZIndex = 2 }, world), "Lines")
local nodes = role(Kit.new("Frame", { Name = "Nodes", Size = UDim2.new(), BackgroundTransparency = 1, ZIndex = 5 }, world), "Nodes")

-- The line template.
local line = Kit.new("Frame", {
	Name = "UpgradeLine", BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(100, 12),
	BackgroundColor3 = Color3.fromRGB(55, 55, 65), ZIndex = 2, Visible = false,
}, lines)
line:SetAttribute("UITemplate", "UpgradeLine")
Kit.new("UIStroke", { Color = BORDER_COLOR, Thickness = 3 }, line)

-- The node template.
local node = Kit.new("Frame", {
	Name = "UpgradeNode", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(RADIUS * 2, RADIUS * 2),
	ZIndex = 5, Visible = false,
}, nodes)
node:SetAttribute("UITemplate", "UpgradeNode")
Kit.new("UIScale", {}, node)
hexagon(node, RADIUS + BORDER, BORDER_COLOR, 5, "Border")
hexagon(node, RADIUS, Color3.fromRGB(70, 70, 82), 6, "Fill")
-- A lighter, smaller hex nudged up reads as a bevel.
local shine = Kit.new("Frame", {
	Name = "ShineHolder", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -RADIUS * 0.12),
	Size = UDim2.fromScale(1, 1), ZIndex = 7,
}, node)
hexagon(shine, RADIUS * 0.72, Color3.new(1, 1, 1), 7, "Shine")
for _, rect in shine:GetChildren() do
	rect.BackgroundTransparency = 0.72
end
Kit.new("TextLabel", {
	Name = "Icon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42),
	Size = UDim2.fromScale(0.55, 0.55), TextScaled = true, FontFace = Kit.FONT, Text = "🍀", ZIndex = 9,
}, node)
Kit.label("3/10", { Name = "Level", Size = UDim2.fromScale(0.62, 0.22), Position = UDim2.fromScale(0.5, 0.78), ZIndex = 9, Parent = node })
Kit.label("1.2K", { Name = "Cost", Size = UDim2.fromScale(1.1, 0.26), Position = UDim2.new(0.5, 0, 1, 14), ZIndex = 9, Parent = node })
local hit = Kit.new("TextButton", {
	Name = "Button", Text = "", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.95, 0.95), ZIndex = 10, AutoButtonColor = false,
}, node)
hit:SetAttribute("Bounce", false)
Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, hit)

-- Top bar.
local bar = Kit.new("Frame", {
	Name = "Top", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0.11, 0),
	ZIndex = 20,
}, root)
Kit.label("Upgrade Tree", { Name = "Title", Size = UDim2.fromScale(0.4, 0.6), ZIndex = 21, Parent = bar })
role(Kit.label("0 Clacks", {
	Name = "Clacks", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.02, 0.5), Size = UDim2.fromScale(0.3, 0.55),
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 220, 90), ZIndex = 21, Parent = bar,
}), "Clacks")
local close = Kit.button("Sunset", "X", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.985, 0.5), Size = UDim2.fromScale(0.75, 0.75) })
close.Name = "Exit"
close.ZIndex = 21
for _, d in close:GetDescendants() do
	if d:IsA("GuiObject") then d.ZIndex += 21 end
end
if not close:FindFirstChildOfClass("UIAspectRatioConstraint") then
	Kit.new("UIAspectRatioConstraint", {}, close)
end
local closeButton = close:FindFirstChild("Button") or close
closeButton:SetAttribute("MenuAction", "close")
close.Parent = bar

-- Info panel.
local info = Kit.new("Frame", {
	Name = "Info", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.97), Size = UDim2.fromScale(0.6, 0.2),
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4, ZIndex = 20,
}, root)
Kit.new("UICorner", { CornerRadius = UDim.new(0.12, 0) }, info)
Kit.new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.7, Thickness = 2 }, info)
Kit.new("UIAspectRatioConstraint", { AspectRatio = 4.6 }, info)
role(Kit.label("Upgrades", { Name = "Title", Size = UDim2.fromScale(0.94, 0.26), Position = UDim2.fromScale(0.5, 0.18), ZIndex = 21, Parent = info }), "InfoTitle")
role(Kit.new("TextLabel", {
	Name = "Body", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.53),
	Size = UDim2.fromScale(0.94, 0.38), TextScaled = true, TextWrapped = true, FontFace = Kit.FONT_BODY, TextColor3 = Color3.new(1, 1, 1),
	TextStrokeTransparency = 0.5, ZIndex = 21, Text = "Spend Clacks on permanent upgrades. They're kept when you rebirth!",
}, info), "InfoBody")
role(Kit.label("Drag to look around · Scroll or pinch to zoom · Tap a node to buy", {
	Name = "Cost", Size = UDim2.fromScale(0.94, 0.2), Position = UDim2.fromScale(0.5, 0.86), ZIndex = 21, Parent = info,
}), "InfoCost")

Kit.save(gui)
