--[[
	Intro: the first-join cinematic's overlay (Controllers/Intro). Disabled
	until the intro plays; IntroRole marks what the code moves and fills:
	  Bar       the two letterbox bars (they slide in from the edges they
	            rest against; IntroBar = "Top" | "Bottom")
	  Title     "STUDS RNG"        Subtitle  the tagline
	  Caption   each zone's name as the camera flies past it
	  Skip      the skip button
]]

local Kit = require("../Kit")
local UDim2, UDim, Vector2, Color3, Enum = Kit.UDim2, Kit.UDim, Kit.Vector2, Kit.Color3, Kit.Enum

local FONT = Kit.Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)

local gui = Kit.new("ScreenGui", {
	Name = "Intro", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40, Enabled = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

for _, top in { true, false } do
	local bar = Kit.new("Frame", {
		Name = if top then "TopBar" else "BottomBar",
		BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.fromScale(1, 0.12),
		AnchorPoint = Vector2.new(0, if top then 0 else 1), Position = UDim2.fromScale(0, if top then 0 else 1),
	}, gui)
	bar:SetAttribute("IntroRole", "Bar")
	bar:SetAttribute("IntroBar", if top then "Top" else "Bottom")
end

local function text(name: string, value: string, size: any, position: any, color: any)
	local label = Kit.new("TextLabel", {
		Name = name, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = size, Position = position,
		TextScaled = true, FontFace = FONT, TextColor3 = color, Text = value, ZIndex = 5,
	}, gui)
	Kit.new("UIStroke", { Thickness = 3, Color = Color3.fromRGB(15, 15, 20) }, label)
	label:SetAttribute("IntroRole", name)
end
text("Title", "STUDS RNG", UDim2.fromScale(0.6, 0.16), UDim2.fromScale(0.5, 0.42), Color3.fromRGB(255, 220, 90))
text("Subtitle", "Walk the keys. Roll the studs.", UDim2.fromScale(0.5, 0.06), UDim2.fromScale(0.5, 0.54), Color3.new(1, 1, 1))
text("Caption", "ZONE 1", UDim2.fromScale(0.5, 0.07), UDim2.fromScale(0.5, 0.82), Color3.new(1, 1, 1))

local skip = Kit.new("TextButton", {
	Name = "Skip", Text = "Skip ▶", FontFace = FONT, TextScaled = true, TextColor3 = Color3.new(1, 1, 1),
	BackgroundColor3 = Color3.fromRGB(30, 30, 40), BackgroundTransparency = 0.3, AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.fromScale(0.97, 0.965), Size = UDim2.fromScale(0.1, 0.05), ZIndex = 6,
}, gui)
skip:SetAttribute("IntroRole", "Skip")
skip:AddTag("Bounce")
Kit.new("UICorner", { CornerRadius = UDim.new(0.3, 0) }, skip)

Kit.save(gui)
