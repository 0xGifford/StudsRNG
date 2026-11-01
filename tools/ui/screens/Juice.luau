--[[
	Juice: the screen layer for UI/Juice's effects. Its templates
	(UITemplate = name, hidden; the code shows copies):
	  Flash        a full-screen frame; colour and transparency set per flash
	  ConfettiBit  one piece of confetti (size and colour randomised)
	  Banner       the big centre title card (a CanvasGroup):
	                 JuiceRole = "Title"     the title (its UIGradient is tinted)
	                 JuiceRole = "Subtitle"  the line under it (hidden when empty)
]]

local Kit = require("../Kit")
local UDim2, Vector2, Color3, Enum = Kit.UDim2, Kit.Vector2, Kit.Color3, Kit.Enum

local FONT = Kit.Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)

local gui = Kit.new("ScreenGui", {
	Name = "Juice", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 25,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local templates = Kit.new("Folder", { Name = "Templates" }, gui)

local flash = Kit.new("Frame", {
	Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1,
	BorderSizePixel = 0, ZIndex = 1, Visible = false,
}, templates)
flash:SetAttribute("UITemplate", "Flash")

local bit = Kit.new("Frame", {
	Name = "ConfettiBit", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(9, 14), BorderSizePixel = 0,
	ZIndex = 5, Visible = false,
}, templates)
bit:SetAttribute("UITemplate", "ConfettiBit")

local banner = Kit.new("CanvasGroup", {
	Name = "Banner", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3),
	Size = UDim2.fromScale(0.7, 0.2), ZIndex = 10, Visible = false,
}, templates)
banner:SetAttribute("UITemplate", "Banner")
Kit.new("UIAspectRatioConstraint", { AspectRatio = 4.2 }, banner)
Kit.new("UIScale", { Name = "BannerScale" }, banner)

local function line(name: string, size: any, position: any, zindex: number)
	local l = Kit.new("TextLabel", {
		Name = name, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = size, Position = position,
		TextScaled = true, FontFace = FONT, TextColor3 = Color3.new(1, 1, 1), Text = name, ZIndex = zindex,
	}, banner)
	Kit.new("UIGradient", { Rotation = 90 }, l)
	Kit.new("UIStroke", { Color = Color3.fromRGB(20, 20, 25), Thickness = 3, LineJoinMode = Enum.LineJoinMode.Round }, l)
	l:SetAttribute("JuiceRole", name)
end
line("Title", UDim2.fromScale(1, 0.62), UDim2.fromScale(0.5, 0.35), 10)
line("Subtitle", UDim2.fromScale(0.8, 0.26), UDim2.fromScale(0.5, 0.82), 11)

Kit.save(gui)
