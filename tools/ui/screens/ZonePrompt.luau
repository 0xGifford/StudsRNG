--[[
	ZonePrompt: the small unlock panel that slides up at the bottom of the
	screen when you walk up to a locked zone (Controllers/ZonePrompt,
	Config.ZoneUnlock.PromptDistance). Always enabled; the panel hides
	itself. ZonePromptRole marks what the code fills:
	  Panel   the panel; where you put it is where it slides up to (it rests
	          HiddenOffset below, an attribute: a UDim2 added to its Position)
	  View    a ZoneView viewport (MenuSystem: Zone = the zone's Id; dark
	          while locked)
	  Title   "Zone 3"
	  Info    "x2 Clacks per key · 6 zone studs"
	  Price   the price ("1.2K"), next to an Icon = "Clacks" image
	  Buy     the kit button (KitColor: Green when you can afford it, Sunset
	          when you can't yet); its label reads UNLOCK
	  Note    "Unlock Zone 2 first" instead of Buy for a zone further on
]]

local Kit = require("../Kit")
local UDim2, UDim, Vector2, Color3, Enum = Kit.UDim2, Kit.UDim, Kit.Vector2, Kit.Color3, Kit.Enum

local FONT = Kit.Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local DARK = Color3.fromRGB(12, 12, 16)
local WHITE = Color3.new(1, 1, 1)

local function text(parent: any, name: string, value: string, color: any, size: any, position: any, align: any?): any
	local label = Kit.new("TextLabel", {
		Name = name, BackgroundTransparency = 1, Size = size, Position = position, FontFace = FONT, TextScaled = true,
		TextColor3 = color, TextXAlignment = align or Enum.TextXAlignment.Left, Text = value, ZIndex = 3,
	}, parent)
	Kit.new("UIStroke", { Thickness = 2, Color = DARK }, label)
	return label
end
local function role(instance: any, name: string): any
	instance:SetAttribute("ZonePromptRole", name)
	return instance
end

local gui = Kit.new("ScreenGui", {
	Name = "ZonePrompt", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 4, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

-- Above the HUD's bottom bar (Roll / Backpack / Upgrade).
local panel = role(Kit.new("Frame", {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.8), Size = UDim2.fromScale(0.36, 0.12),
	BackgroundColor3 = Color3.fromRGB(28, 30, 40), Visible = false,
}, gui), "Panel")
panel:SetAttribute("HiddenOffset", UDim2.fromScale(0, 0.35))
Kit.new("UIAspectRatioConstraint", { AspectRatio = 4.2 }, panel)
Kit.new("UISizeConstraint", { MinSize = Vector2.new(300, 72), MaxSize = Vector2.new(560, 135) }, panel)
Kit.new("UICorner", { CornerRadius = UDim.new(0.18, 0) }, panel)
Kit.new("UIStroke", { Thickness = 3, Color = DARK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
Kit.new("UIGradient", { Color = Kit.ColorSequence.new(Color3.fromRGB(60, 64, 86), Color3.fromRGB(28, 30, 40)), Rotation = 90 }, panel)

-- The zone, in 3D (dark until it's yours).
local view = role(Kit.zoneViewport({
	AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.02, 0.5), Size = UDim2.fromScale(0.24, 0.92), ZIndex = 2,
}), "View")
view:SetAttribute("ViewSilhouette", true)
view:SetAttribute("ViewSpin", 25)
view.Parent = panel

role(text(panel, "Title", "Zone 2", WHITE, UDim2.fromScale(0.42, 0.34), UDim2.fromScale(0.27, 0.1)), "Title")
role(text(panel, "Info", "x2 Clacks per key", Color3.fromRGB(190, 200, 225), UDim2.fromScale(0.42, 0.2), UDim2.fromScale(0.27, 0.46)), "Info")

-- Price with the Clacks icon (MenuSystem IconImage).
local icon = Kit.new("ImageLabel", {
	Name = "PriceIcon", BackgroundTransparency = 1, Position = UDim2.fromScale(0.27, 0.68), Size = UDim2.fromScale(0.06, 0.24),
	ScaleType = Enum.ScaleType.Fit, ZIndex = 3,
}, panel)
icon:SetAttribute("Icon", "Clacks")
Kit.new("UIAspectRatioConstraint", { AspectRatio = 1 }, icon)
role(text(panel, "Price", "1,000", Color3.fromRGB(255, 220, 90), UDim2.fromScale(0.34, 0.24), UDim2.fromScale(0.34, 0.68)), "Price")

-- UNLOCK (a kit button; MenuSystem KitColor paints it).
local buy = Kit.button("Green", "UNLOCK", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.97, 0.5), Size = UDim2.fromScale(0.27, 0.62),
})
buy.Name = "Buy"
buy:SetAttribute("KitColor", "Green")
role(buy, "Buy").Parent = panel

role(text(panel, "Note", "Unlock Zone 1 first", Color3.fromRGB(255, 150, 150), UDim2.fromScale(0.27, 0.5), UDim2.fromScale(0.71, 0.25), Enum.TextXAlignment.Center), "Note").Visible = false

Kit.save(gui)
