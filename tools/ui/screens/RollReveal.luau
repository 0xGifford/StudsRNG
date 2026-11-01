--[[
	RollReveal: the roll reveal (Controllers/RollReveal). Always enabled;
	pieces show while rolling. RevealRole marks what the code uses:
	  Dim        the screen dim while rolling (DimTransparency attribute: how
	             dark; it rests fully transparent)
	  Stage      follows the player's head; the reels and decorations go in it
	  Controls   AUTO / HIDE: Auto and Hide buttons, each with Icon + Label.
	             Their designed positions are the "Auto on" layout (AUTO alone
	             is centred). OnColor / OffColor attributes tint the Labels.
	             HiddenSize: its size under the small display in HIDE mode.
	  Mini       the small top display in HIDE mode: Viewport, Odds, Name,
	             a UIStroke (tinted by rarity on landing), a UIScale

	Templates (in the hidden "Templates" frame; UITemplate = name), designed
	for a reel cell 100 px tall (the Templates frame's DesignHeight): the code
	scales offset sizes by the real cell height.
	  ReelHolder  one reel (transparent)
	  ReelCell    a reel entry: Viewport, Odds, Name, a UIScale
	  ReelDash    the centre-line dashes (the right one is turned 180°)
	  LuckBadge   the clover badge: Text ("2X")
	  BonusTag    shown under the badge while any boost / event runs
	  SoClose     "SO CLOSE!" over a near miss
	  Rays        the light burst behind a landed stud (spins)
	  Clover      clover rain for lucky players
	  ResultBoard a BillboardGui over the player after a roll: Odds, Name
]]

local Kit = require("../Kit")
local roblox = require("@lune/roblox")
local UDim2, UDim, Vector2, Color3, Enum = Kit.UDim2, Kit.UDim, Kit.Vector2, Kit.Color3, Kit.Enum

local FONT = Kit.Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local ODDS = Color3.fromRGB(150, 210, 255)
local CLOVER = Color3.fromRGB(70, 220, 80)
local WHITE = Color3.new(1, 1, 1)
local PANEL = Color3.fromRGB(22, 22, 30)

local function text(parent: any, name: string, value: string, color: any, size: any, position: any, z: number): any
	local label = Kit.new("TextLabel", {
		Name = name, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = size, Position = position, TextScaled = true,
		FontFace = FONT, TextColor3 = color, Text = value, ZIndex = z,
	}, parent)
	Kit.new("UIStroke", { Color = Color3.fromRGB(15, 15, 22), Thickness = 2.5, LineJoinMode = Enum.LineJoinMode.Round }, label)
	return label
end
local function role(instance: any, name: string): any
	instance:SetAttribute("RevealRole", name)
	return instance
end
local function template(instance: any, name: string): any
	instance.Name = name
	instance:SetAttribute("UITemplate", name)
	return instance
end

local gui = Kit.new("ScreenGui", {
	Name = "RollReveal", ResetOnSpawn = false, DisplayOrder = 5, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local dim = role(Kit.new("Frame", {
	Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(5, 5, 12), BackgroundTransparency = 1, BorderSizePixel = 0,
}, gui), "Dim")
dim:SetAttribute("DimTransparency", 0.45)

role(Kit.new("Frame", { Name = "Stage", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(0, 0) }, gui), "Stage")

-- AUTO / HIDE.
local controls = role(Kit.new("Frame", {
	Name = "Controls", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.97),
	Size = UDim2.fromScale(0.45, 0.13), Visible = false,
}, gui), "Controls")
controls:SetAttribute("OnColor", Color3.fromRGB(120, 255, 140))
controls:SetAttribute("OffColor", Color3.fromRGB(255, 120, 120))
controls:SetAttribute("HiddenSize", UDim2.fromScale(0.26, 0.08))
Kit.new("UIAspectRatioConstraint", { AspectRatio = 4 }, controls)
for _, info in { { "Auto", "AUTO - OFF", 0.27, "🔁" }, { "Hide", "HIDE - OFF", 0.73, "👁" } } do
	local button = role(Kit.new("TextButton", {
		Name = info[1], AutoButtonColor = false, BackgroundColor3 = PANEL, BackgroundTransparency = 0.1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(info[3], 0.4), Size = UDim2.fromScale(1, 0.68), Text = "",
	}, controls), info[1])
	Kit.new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, button)
	Kit.new("UICorner", { CornerRadius = UDim.new(1, 0) }, button)
	Kit.new("UIStroke", { Color = WHITE, Transparency = 0.5, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
	text(button, "Icon", info[4], WHITE, UDim2.fromScale(0.62, 0.62), UDim2.fromScale(0.5, 0.48), 2)
	text(button, "Label", info[2], Color3.fromRGB(255, 120, 120), UDim2.fromScale(2.4, 0.42), UDim2.fromScale(0.5, 1.25), 2)
end

-- The small display (HIDE mode).
local mini = role(Kit.new("Frame", {
	Name = "MiniRoll", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 58), Size = UDim2.fromScale(0.24, 0.08),
	BackgroundColor3 = PANEL, BackgroundTransparency = 0.1, Visible = false,
}, gui), "Mini")
Kit.new("UIAspectRatioConstraint", { AspectRatio = 4 }, mini)
Kit.new("UISizeConstraint", { MinSize = Vector2.new(200, 50), MaxSize = Vector2.new(340, 85) }, mini)
Kit.new("UICorner", { CornerRadius = UDim.new(0.3, 0) }, mini)
Kit.new("UIStroke", { Thickness = 3, Color = WHITE, Transparency = 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, mini)
Kit.new("UIScale", {}, mini)
Kit.viewport({
	Position = UDim2.fromScale(0.14, 0.5), Size = UDim2.fromScale(0.85, 0.85), SizeConstraint = Enum.SizeConstraint.RelativeYY, ZIndex = 2, Parent = mini,
})
text(mini, "Odds", "AUTO ROLL", ODDS, UDim2.fromScale(0.68, 0.34), UDim2.fromScale(0.62, 0.3), 2)
text(mini, "Name", "", WHITE, UDim2.fromScale(0.68, 0.42), UDim2.fromScale(0.62, 0.68), 2)

-- Templates.
local templates = Kit.new("Frame", { Name = "Templates", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false }, gui)
templates:SetAttribute("DesignHeight", 100)

template(Kit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(160, 500) }, templates), "ReelHolder")

local cell = template(Kit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(160, 100) }, templates), "ReelCell")
Kit.new("UIScale", {}, cell)
Kit.viewport({ Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.62, 0.62), ZIndex = 2, Parent = cell })
text(cell, "Odds", "1 / 2", ODDS, UDim2.fromScale(1, 0.2), UDim2.fromScale(0.5, 0.1), 3)
text(cell, "Name", "Stud", WHITE, UDim2.fromScale(1.1, 0.22), UDim2.fromScale(0.5, 0.9), 3)

local dash = template(Kit.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(45, 4), BackgroundColor3 = WHITE, BorderSizePixel = 0,
}, templates), "ReelDash")
Kit.new("UIGradient", { Transparency = Kit.NumberSequence.new(1, 0) }, dash)

local badge = template(Kit.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(70, 70), BackgroundColor3 = CLOVER, Rotation = 45, ZIndex = 4,
}, templates), "LuckBadge")
Kit.new("UICorner", { CornerRadius = UDim.new(0.3, 0) }, badge)
Kit.new("UIStroke", { Color = Color3.fromRGB(20, 60, 20), Thickness = 3 }, badge)
text(badge, "Text", "2X", WHITE, UDim2.fromScale(0.9, 0.55), UDim2.fromScale(0.5, 0.5), 5).Rotation = -45

local bonus = template(Kit.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(85, 28), BackgroundColor3 = Color3.fromRGB(30, 22, 18), ZIndex = 4,
}, templates), "BonusTag")
Kit.new("UICorner", { CornerRadius = UDim.new(1, 0) }, bonus)
Kit.new("UIStroke", { Color = Color3.fromRGB(255, 150, 60), Thickness = 2 }, bonus)
text(bonus, "Text", "BONUS", Color3.fromRGB(255, 190, 90), UDim2.fromScale(0.85, 0.8), UDim2.fromScale(0.5, 0.5), 5)

template(text(templates, "SoClose", "SO CLOSE!", Color3.fromRGB(255, 90, 90), UDim2.fromScale(1.4, 0.12), UDim2.fromScale(0.5, 0.3), 6), "SoClose").Rotation = -6

local rays = template(Kit.new("Frame", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(240, 240), ZIndex = 1,
}, templates), "Rays")
for i = 1, 10 do
	local ray = Kit.new("Frame", {
		Name = "Ray", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.09, 1), Rotation = i * 18,
		BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 1,
	}, rays)
	Kit.new("UIGradient", {
		Rotation = 90,
		Transparency = Kit.NumberSequence.new({
			roblox.NumberSequenceKeypoint.new(0, 1),
			roblox.NumberSequenceKeypoint.new(0.5, 0.25),
			roblox.NumberSequenceKeypoint.new(1, 1),
		}),
	}, ray)
end
local glow = Kit.new("Frame", {
	Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.45, 0.45),
	BackgroundColor3 = WHITE, BackgroundTransparency = 0.45, ZIndex = 1,
}, rays)
Kit.new("UICorner", { CornerRadius = UDim.new(1, 0) }, glow)

template(Kit.new("TextLabel", {
	BackgroundTransparency = 1, Text = "🍀", TextScaled = true, Size = UDim2.fromOffset(30, 30), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 6,
}, templates), "Clover")

local board = template(Kit.new("BillboardGui", {
	Size = UDim2.fromScale(9, 2.6), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 200,
}, templates), "ResultBoard")
text(board, "Odds", "1 / 2", ODDS, UDim2.fromScale(1, 0.48), UDim2.fromScale(0.5, 0.27), 1)
text(board, "Name", "Stud", WHITE, UDim2.fromScale(1, 0.5), UDim2.fromScale(0.5, 0.75), 1)

Kit.save(gui)
