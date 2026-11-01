--[[
	The Announcement ScreenGui: the banner admin announcements slide in on
	(MenuSystem's Announcements). Found by attribute, so restyle freely:
	  ScreenGui  AnnouncementBanner = true, Duration (seconds), Sound (asset id)
	  Banner     AnnouncementRole = "Banner"   what slides; rests where it sits
	  Title      AnnouncementRole = "Title"    "ANNOUNCEMENT"
	  Text       AnnouncementRole = "Text"     the message
	  Sender     AnnouncementRole = "Sender"   "— Shane"
]]

local Kit = require("../Kit")
local UDim2, Vector2, Color3, Enum = Kit.UDim2, Kit.Vector2, Kit.Color3, Kit.Enum

local gui = Kit.new("ScreenGui", {
	Name = "Announcement",
	DisplayOrder = 950,
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false,
})
gui:SetAttribute("AnnouncementBanner", true)
gui:SetAttribute("Duration", 6)

local banner = Kit.panel({
	Name = "Banner",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.09),
	Size = UDim2.fromScale(0.42, 0.13),
	BackgroundColor3 = Color3.fromRGB(28, 26, 40),
	BackgroundTransparency = 0.08,
})
banner:SetAttribute("AnnouncementRole", "Banner")
Kit.new("UIAspectRatioConstraint", { AspectRatio = 5.2 }, banner)
Kit.new("UIPadding", {
	PaddingLeft = Kit.UDim.new(0.04, 0), PaddingRight = Kit.UDim.new(0.04, 0),
	PaddingTop = Kit.UDim.new(0.1, 0), PaddingBottom = Kit.UDim.new(0.1, 0),
}, banner)
Kit.new("UIGradient", {
	Rotation = 90,
	Color = Kit.ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 190, 205)),
}, banner)
banner.Parent = gui

local title = Kit.label("ANNOUNCEMENT", {
	Name = "Title",
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.fromScale(0, 0),
	Size = UDim2.fromScale(1, 0.3),
	TextColor3 = Color3.fromRGB(255, 205, 60),
	TextXAlignment = Enum.TextXAlignment.Left,
})
title:SetAttribute("AnnouncementRole", "Title")
title.Parent = banner

local text = Kit.label("", {
	Name = "Text",
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.fromScale(0, 0.32),
	Size = UDim2.fromScale(1, 0.44),
	FontFace = Kit.FONT_BODY,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
})
text:SetAttribute("AnnouncementRole", "Text")
text.Parent = banner

local sender = Kit.label("", {
	Name = "Sender",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.fromScale(1, 1),
	Size = UDim2.fromScale(1, 0.22),
	FontFace = Kit.FONT_BODY,
	TextColor3 = Color3.fromRGB(205, 205, 220),
	TextXAlignment = Enum.TextXAlignment.Right,
})
sender:SetAttribute("AnnouncementRole", "Sender")
sender.Parent = banner

Kit.save(gui)
