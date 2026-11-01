--[[
	Offers: the contextual offer card (Controllers/Offers). It rests where it
	sits here and slides in from the left; OfferRole marks what the code fills:
	  Card   the card (what slides)       Icon   the product's icon
	  Title  "Lucky Drops!"               Body   the description
	  Buy    the buy button               Price  "BUY  R$ 99" (inside Buy)
	  Close  the ✕
]]

local Kit = require("../Kit")
local UDim2, UDim, Vector2, Color3, Enum = Kit.UDim2, Kit.UDim, Kit.Vector2, Kit.Color3, Kit.Enum

local GOLD = Color3.fromRGB(255, 205, 60)
local FONT = Kit.Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)

local gui = Kit.new("ScreenGui", { Name = "Offers", ResetOnSpawn = false, DisplayOrder = 6, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })

local card = Kit.new("Frame", {
	Name = "Card",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 14, 0.56, 0),
	Size = UDim2.fromOffset(320, 128),
	BackgroundColor3 = Color3.fromRGB(30, 28, 46),
	Visible = false,
}, gui)
card:SetAttribute("OfferRole", "Card")
Kit.new("UICorner", { CornerRadius = UDim.new(0, 14) }, card)
Kit.new("UIStroke", { Thickness = 3, Color = GOLD, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)

local function text(name: string, parent: any, size: any, position: any, color: any, align: any): any
	local l = Kit.new("TextLabel", {
		Name = name, BackgroundTransparency = 1, Size = size, Position = position, FontFace = FONT,
		TextScaled = true, TextWrapped = true, TextColor3 = color, TextXAlignment = align, Text = "",
	}, parent)
	Kit.new("UIStroke", { Thickness = 1.5, Color = Color3.fromRGB(10, 10, 14) }, l)
	l:SetAttribute("OfferRole", name)
	return l
end

local icon = Kit.new("ImageLabel", {
	Name = "Icon", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 14), Size = UDim2.fromOffset(64, 64),
	ScaleType = Enum.ScaleType.Fit,
}, card)
icon:SetAttribute("OfferRole", "Icon")
text("Title", card, UDim2.fromOffset(196, 26), UDim2.fromOffset(86, 10), GOLD, Enum.TextXAlignment.Left)
text("Body", card, UDim2.fromOffset(222, 48), UDim2.fromOffset(86, 38), Color3.new(1, 1, 1), Enum.TextXAlignment.Left)

local buy = Kit.new("TextButton", {
	Name = "Buy", Text = "", Position = UDim2.fromOffset(86, 90), Size = UDim2.fromOffset(150, 30),
	BackgroundColor3 = Color3.fromRGB(60, 180, 90), AutoButtonColor = false,
}, card)
buy:SetAttribute("OfferRole", "Buy")
Kit.new("UICorner", { CornerRadius = UDim.new(0.3, 0) }, buy)
text("Price", buy, UDim2.fromScale(0.9, 0.75), UDim2.fromScale(0.05, 0.12), Color3.new(1, 1, 1), Enum.TextXAlignment.Center)

local close = Kit.new("TextButton", {
	Name = "Close", Text = "✕", FontFace = FONT, TextScaled = true, TextColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 1, Position = UDim2.fromOffset(286, 6), Size = UDim2.fromOffset(26, 26),
}, card)
close:SetAttribute("OfferRole", "Close")
close:AddTag("Bounce")

Kit.save(gui)
