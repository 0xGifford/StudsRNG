--[[
	Templates: every reusable UI piece the code copies (UI/Kit,
	Interface.Templates). A disabled ScreenGui in StarterGui, so the pieces
	are edited in Studio like everything else; the code clones them by name.

	From the UI kit (ReplicatedStorage.Assets.UI.Templates, moved here):
	  Buttons (Green, Blue, Orange, Purple, Sunset), Store Item (cards),
	  StudCell (Index / Backpack cells), Events (HUD event timer), Studs
	List pieces (UI/Kit):
	  Label      a kit title label (Kit.label, badges)
	  Emoji      the label drawn over an icon when the icon is an emoji
	  Header     a section title row (Kit.header)
	  Paragraph  wrapped body text (Kit.paragraph)
	  GridRow    a row of side-by-side cells (Kit.gridRow)
	  OddsRow    a row of the Odds menu's table: 4 cells (OddsCell = 1..4)
	  ZoneRow    a Teleporter row (ZonesMenu), ZoneRole: Number, ZoneName,
	             Info, Action (the kit button: Teleport / price / Locked)
	  StudViewport  the 3D stud preview (UI/StudCell): a ViewportFrame with its
	             Camera (keep the stud centred at the origin in front of it)
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Kit = require("../Kit")
local CAMERA_DISTANCE = 3.4 -- UI/StudCell's
local UDim2, UDim, Vector2, Color3, Enum = Kit.UDim2, Kit.UDim, Kit.Vector2, Kit.Color3, Kit.Enum

local gui = Kit.new("ScreenGui", { Name = "Templates", Enabled = false, ResetOnSpawn = false })

local assets = roblox.deserializeModel(fs.readFile("src/ReplicatedStorage/Assets/UI.rbxm"))[1]
for _, template in assets.Templates:GetChildren() do
	template:Clone().Parent = gui
end

-- Kit.label: the StudCell's title look.
local title = gui:FindFirstChild("StudCell"):FindFirstChild("Title")
local label = title:Clone()
label.Name = "Label"
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.fromScale(0.5, 0.5)
label.Size = UDim2.fromScale(1, 1)
label.ZIndex = 2
label.Text = "Label"
label.Parent = gui

Kit.new("TextLabel", {
	Name = "Emoji", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.8, 0.8), TextScaled = true, FontFace = Kit.Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold), TextColor3 = Color3.new(1, 1, 1),
	Text = "⭐", ZIndex = 3,
}, gui)

local header = Kit.new("Frame", { Name = "Header", BackgroundTransparency = 1, Size = UDim2.fromScale(0.925, 0.08) }, gui)
local headerLabel = label:Clone()
headerLabel.Size = UDim2.fromScale(1, 0.9)
headerLabel.Text = "Section"
headerLabel.Parent = header

Kit.new("TextLabel", {
	Name = "Paragraph", BackgroundTransparency = 1, TextWrapped = true, TextScaled = false, RichText = true,
	AutomaticSize = Enum.AutomaticSize.Y, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	FontFace = Kit.Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium), TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.6, TextSize = 18,
	Text = "Body text", Size = UDim2.new(0.925, 0, 0, 0),
}, gui):SetAttribute("TextScale", 0.032)

local row = Kit.new("Frame", { Name = "GridRow", BackgroundTransparency = 1, Size = UDim2.fromScale(0.925, 0.2) }, gui)
Kit.new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0.02, 0),
}, row)

-- The Odds table's row (OddsMenu): four cells left to right.
local odds = Kit.new("Frame", { Name = "OddsRow", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.55, Size = UDim2.fromScale(0.925, 0.07) }, gui)
Kit.new("UICorner", { CornerRadius = UDim.new(0.25, 0) }, odds)
local widths = { 0.34, 0.2, 0.2, 0.26 }
local x = 0.01
for i, width in widths do
	local cell = label:Clone()
	cell.Name = `Cell{i}`
	cell.AnchorPoint = Vector2.new(0, 0.5)
	cell.Position = UDim2.fromScale(x, 0.5)
	cell.Size = UDim2.fromScale(width - 0.02, 0.7)
	cell.Text = ""
	cell:SetAttribute("OddsCell", i)
	cell.Parent = odds
	x += width
end

-- A Teleporter row (ZonesMenu).
local zoneRow = Kit.new("Frame", { Name = "ZoneRow", BackgroundColor3 = Color3.fromRGB(36, 38, 50), BorderSizePixel = 0, Size = UDim2.fromScale(0.925, 0.15) }, gui)
Kit.new("UICorner", { CornerRadius = UDim.new(0.18, 0) }, zoneRow)
Kit.new("UIStroke", { Color = Color3.fromRGB(12, 12, 18), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, zoneRow)
local function zoneText(name: string, value: string, props: { [string]: any })
	local l = Kit.kitLabel(value, props)
	l.Name = name
	l:SetAttribute("ZoneRole", name)
	l.Parent = zoneRow
end
zoneText("Number", "1", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.065, 0.5), Size = UDim2.fromScale(0.07, 0.5) })
zoneText("ZoneName", "Zone 1", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.13, 0.4), Size = UDim2.fromScale(0.52, 0.46), TextXAlignment = Enum.TextXAlignment.Left })
zoneText("Info", "x1 Clacks per key", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.13, 0.78), Size = UDim2.fromScale(0.52, 0.24), TextXAlignment = Enum.TextXAlignment.Left })
local action = Kit.button("Green", "Teleport", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.97, 0.5), Size = UDim2.fromScale(0.27, 0.62) })
action.Name = "Action"
action:SetAttribute("ZoneRole", "Action")
action.Parent = zoneRow

-- The 3D stud preview (StudCell.viewport).
local viewport = Kit.new("ViewportFrame", {
	Name = "StudViewport", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42),
	Size = UDim2.fromScale(0.72, 0.72), Ambient = Color3.fromRGB(170, 170, 170), LightColor = Color3.new(1, 1, 1),
	LightDirection = require("@lune/roblox").Vector3.new(-1, -1.5, -1), ZIndex = 1,
}, gui)
Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }, viewport)
local roblox2 = require("@lune/roblox")
local camera = Kit.new("Camera", {
	Name = "Camera", FieldOfView = 30,
	CFrame = roblox2.CFrame.lookAt(roblox2.Vector3.new(0, 0, CAMERA_DISTANCE), roblox2.Vector3.new(0, 0, 0)),
}, viewport)
viewport.CurrentCamera = camera

Kit.save(gui)
