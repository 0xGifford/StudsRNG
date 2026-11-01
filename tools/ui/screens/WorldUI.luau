--[[
	WorldUI: templates for UI that floats in the world (BillboardGuis,
	SurfaceGuis). This ScreenGui stays disabled; the code shows copies
	(UITemplate = name) where they belong. Restyle the templates freely:
	the code only looks for the role attributes listed with each.

	Enemies (Controllers/Enemies), EnemyRole:
	  EnemyBar / BossBar   Name, Fill (Size X = health), Amount; BossBar: Tag
	  DamagePopup / CritPopup   Text (floats up and fades)
	  AggroPop             Text ("!")

	Studs (Controllers/StudFollowers), NametagRole:
	  StudNametag          Odds ("1/3.07M"), Name (tinted by rarity)

	Level ups (Controllers/GameFeel), PopupRole:
	  LevelUpPopup         Text ("⭐ EMBER LV 5"), rises off your head

	Keys (Controllers/KeyLabels), KeyRole:
	  KeyReward            Text ("+1"), a SurfaceGui on the key's top (pulses)

	Zone barriers (Controllers/ZonesMenu), SignRole:
	  BarrierSign          a SurfaceGui put on both faces of a locked zone's
	                       barrier: Panel (centred near the bottom, scaled to
	                       fit the barrier; its UIStroke "Outline" is tinted),
	                       Title, Icon, Amount (the price), Buy (kit button),
	                       Note ("Unlock Zone 3 first", instead of Buy)

	Titles (Systems/Achievements, on the server: read from StarterGui), TitleRole:
	  TitleTag             Text ("« Voyager »", tinted by the title's colour)

	Leaderboards (Controllers/LeaderboardBoards), BoardRole:
	  LeaderboardBoard     Title, Row + Value (BoardRow = 1..10), Footer
]]

local Kit = require("../Kit")
local UDim2, UDim, Vector2, Vector3, Color3, Enum = Kit.UDim2, Kit.UDim, Kit.Vector2, require("@lune/roblox").Vector3, Kit.Color3, Kit.Enum

local FONT = Kit.Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local HP_GREEN = Color3.fromRGB(90, 230, 100)
local BOSS_GOLD = Color3.fromRGB(255, 205, 60)
local CRIT_ORANGE = Color3.fromRGB(255, 140, 40)
local AGGRO_RED = Color3.fromRGB(255, 70, 60)

local gui = Kit.new("ScreenGui", { Name = "WorldUI", Enabled = false, ResetOnSpawn = false })

local function template(class: string, name: string, props: { [string]: any }): any
	local t = Kit.new(class, props, gui)
	t.Name = name
	t:SetAttribute("UITemplate", name)
	return t
end

local function text(parent: any, name: string, value: string, color: any, size: any, position: any, role: string): any
	local l = Kit.new("TextLabel", {
		Name = name, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = size, Position = position,
		FontFace = FONT, TextScaled = true, TextWrapped = false, TextColor3 = color, Text = value,
	}, parent)
	Kit.new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(15, 15, 20) }, l)
	l:SetAttribute(role, name)
	return l
end

local function bar(parent: any, size: any, position: any, role: string): (any, any)
	local back = Kit.new("Frame", {
		Name = "Bar", AnchorPoint = Vector2.new(0.5, 0.5), Size = size, Position = position,
		BackgroundColor3 = Color3.fromRGB(25, 25, 32), BorderSizePixel = 0,
	}, parent)
	Kit.new("UICorner", { CornerRadius = UDim.new(1, 0) }, back)
	Kit.new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(10, 10, 14) }, back)
	local fill = Kit.new("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = HP_GREEN, BorderSizePixel = 0 }, back)
	Kit.new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
	fill:SetAttribute(role, "Fill")
	local amount = text(back, "Amount", "", Color3.new(1, 1, 1), UDim2.fromScale(0.9, 0.85), UDim2.fromScale(0.5, 0.5), role)
	amount.ZIndex = 3
	return back, fill
end

local function billboard(name: string, size: any, extra: { [string]: any }?): any
	local props = { Size = size, LightInfluence = 0, AlwaysOnTop = false, ResetOnSpawn = false }
	for k, v in extra or {} do
		props[k] = v
	end
	return template("BillboardGui", name, props)
end

---------------------------------------------------------------- Enemies

local enemyBar = billboard("EnemyBar", UDim2.fromOffset(150, 46), { MaxDistance = 90 })
text(enemyBar, "Name", "Grub  Lv.1", Color3.new(1, 1, 1), UDim2.fromScale(1, 0.45), UDim2.fromScale(0.5, 0.22), "EnemyRole")
bar(enemyBar, UDim2.fromScale(0.95, 0.4), UDim2.fromScale(0.5, 0.72), "EnemyRole")

local bossBar = billboard("BossBar", UDim2.fromOffset(220, 76), { MaxDistance = 160 })
local tag = text(bossBar, "Tag", "👑 MINI BOSS", BOSS_GOLD, UDim2.fromScale(1, 0.3), UDim2.fromScale(0.5, 0.15), "EnemyRole")
Kit.new("UIGradient", { Rotation = 90, Color = Kit.ColorSequence.new(Color3.fromRGB(255, 240, 150), BOSS_GOLD) }, tag)
text(bossBar, "Name", "Mini Boss Grub  Lv.1", Color3.new(1, 1, 1), UDim2.fromScale(1, 0.28), UDim2.fromScale(0.5, 0.45), "EnemyRole")
local bossBack = bar(bossBar, UDim2.fromScale(0.98, 0.3), UDim2.fromScale(0.5, 0.8), "EnemyRole")
bossBack:FindFirstChildOfClass("UIStroke").Color = BOSS_GOLD

local function popup(name: string, size: any, color: any, value: string)
	local pop = billboard(name, size, { AlwaysOnTop = true })
	local label = text(pop, "Text", value, color, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), "EnemyRole")
	Kit.new("UIScale", {}, label)
end
popup("DamagePopup", UDim2.fromScale(4, 1.4), Color3.fromRGB(255, 230, 90), "-123")
popup("CritPopup", UDim2.fromScale(7, 2.4), CRIT_ORANGE, "CRIT! -123")
popup("AggroPop", UDim2.fromScale(2.4, 2.4), AGGRO_RED, "!")

---------------------------------------------------------------- Studs

local nametag = billboard("StudNametag", UDim2.fromOffset(150, 44), { MaxDistance = 90 })
local odds = text(nametag, "Odds", "1/100", Color3.fromRGB(150, 210, 255), UDim2.fromScale(1, 0.5), UDim2.fromScale(0.5, 0.25), "NametagRole")
odds.TextWrapped = false
text(nametag, "Name", "Stud", Color3.new(1, 1, 1), UDim2.fromScale(1, 0.5), UDim2.fromScale(0.5, 0.75), "NametagRole")

---------------------------------------------------------------- Level ups

local levelUp = billboard("LevelUpPopup", UDim2.fromScale(8, 1.6), { AlwaysOnTop = true })
local levelText = text(levelUp, "Text", "⭐ STUD LV 5", BOSS_GOLD, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), "PopupRole")
levelText:FindFirstChildOfClass("UIStroke").Thickness = 3
Kit.new("UIScale", {}, levelText)

---------------------------------------------------------------- Zone barriers

local sign = template("SurfaceGui", "BarrierSign", {
	SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 25, LightInfluence = 0, MaxDistance = 150,
	ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
-- Designed at 22 x 12 studs (550 x 300 px): the code scales it down on a
-- narrower barrier and lifts it 8 studs off the bottom.
local panel = Kit.new("Frame", {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.fromOffset(550, 300),
	BackgroundColor3 = Color3.fromRGB(36, 38, 50), BackgroundTransparency = 0.05, BorderSizePixel = 0,
}, sign)
panel:SetAttribute("SignRole", "Panel")
Kit.new("UICorner", { CornerRadius = UDim.new(0.12, 0) }, panel)
Kit.new("UIStroke", { Name = "Outline", Thickness = 8, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
Kit.new("UIScale", { Name = "Fit" }, panel)
local signTitle = Kit.kitLabel("Zone 2", { Name = "Title", Position = UDim2.fromScale(0.5, 0.19), Size = UDim2.fromScale(0.9, 0.26) })
signTitle:SetAttribute("SignRole", "Title")
signTitle.Parent = panel
local priceRow = Kit.new("Frame", {
	Name = "Price", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromScale(0.9, 0.22),
}, panel)
Kit.new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0.02, 0), SortOrder = Enum.SortOrder.LayoutOrder,
}, priceRow)
local icon = Kit.new("ImageLabel", {
	Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), SizeConstraint = Enum.SizeConstraint.RelativeYY,
	ScaleType = Enum.ScaleType.Fit, LayoutOrder = 1,
}, priceRow)
icon:SetAttribute("SignRole", "Icon")
icon.Image = "rbxassetid://117187305699068" -- the Clacks icon (UIConfig.Icons.Clacks)
local amount = Kit.new("TextLabel", {
	Name = "Amount", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1),
	FontFace = FONT, TextSize = 60, TextWrapped = false, TextColor3 = Color3.new(1, 1, 1), Text = "1.4K", LayoutOrder = 2,
}, priceRow)
amount:SetAttribute("SignRole", "Amount")
Kit.new("UIStroke", { Thickness = 4, Color = Color3.fromRGB(12, 12, 16) }, amount)
local buy = Kit.button("Green", "BUY", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.77), Size = UDim2.fromScale(0.5, 0.3) })
buy.Name = "Buy"
buy:SetAttribute("SignRole", "Buy")
buy.Parent = panel
local note = Kit.kitLabel("Unlock Zone 1 first", { Name = "Note", Position = UDim2.fromScale(0.5, 0.77), Size = UDim2.fromScale(0.9, 0.2), TextColor3 = Color3.fromRGB(255, 120, 120), Visible = false })
note:SetAttribute("SignRole", "Note")
note.Parent = panel

---------------------------------------------------------------- Titles

local title = billboard("TitleTag", UDim2.fromScale(6, 0.9), { MaxDistance = 80, StudsOffset = Vector3.new(0, 2.6, 0) })
text(title, "Text", "« Voyager »", Color3.new(1, 1, 1), UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), "TitleRole")

---------------------------------------------------------------- Keys

local reward = template("SurfaceGui", "KeyReward", {
	Face = Enum.NormalId.Top, SizingMode = Enum.SurfaceGuiSizingMode.FixedSize, CanvasSize = Vector2.new(150, 150),
	LightInfluence = 0, MaxDistance = 150, AlwaysOnTop = false, ResetOnSpawn = false,
})
local rewardText = Kit.new("TextLabel", {
	Name = "Text", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.85, 0.85),
	BackgroundTransparency = 1, TextScaled = true, FontFace = FONT, TextColor3 = Color3.new(1, 1, 1), Text = "+1",
}, reward)
rewardText:SetAttribute("KeyRole", "Text")
Kit.new("UIGradient", { Rotation = 90, Color = Kit.ColorSequence.new(Color3.fromRGB(255, 245, 140), Color3.fromRGB(255, 180, 40)) }, rewardText)
Kit.new("UIStroke", { Color = Color3.fromRGB(25, 25, 25), Thickness = 6, LineJoinMode = Enum.LineJoinMode.Round }, rewardText)
Kit.new("UIScale", {}, rewardText)

---------------------------------------------------------------- Leaderboards

local board = template("SurfaceGui", "LeaderboardBoard", {
	SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 40, LightInfluence = 0, MaxDistance = 250,
	ResetOnSpawn = false,
})
local back = Kit.new("Frame", { Name = "Back", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(18, 18, 26) }, board)
Kit.new("UIGradient", { Rotation = 90, Color = Kit.ColorSequence.new(Color3.fromRGB(40, 36, 60), Color3.fromRGB(14, 14, 20)) }, back)
local function boardText(name: string, value: string, color: any, size: any, position: any, align: any): any
	local l = Kit.new("TextLabel", {
		Name = name, BackgroundTransparency = 1, Size = size, Position = position, FontFace = FONT, TextScaled = true,
		TextColor3 = color, TextXAlignment = align, Text = value,
	}, back)
	Kit.new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(10, 10, 16) }, l)
	return l
end
boardText("Title", "🏆 TOP CLACKS", BOSS_GOLD, UDim2.fromScale(0.92, 0.1), UDim2.fromScale(0.04, 0.02), Enum.TextXAlignment.Center)
	:SetAttribute("BoardRole", "Title")
for i = 1, 10 do
	local y = 0.14 + (i - 1) * 0.074
	local row = boardText(`Row{i}`, "", Color3.new(1, 1, 1), UDim2.fromScale(0.6, 0.06), UDim2.fromScale(0.05, y), Enum.TextXAlignment.Left)
	row:SetAttribute("BoardRole", "Row")
	row:SetAttribute("BoardRow", i)
	local value = boardText(`Value{i}`, "", Color3.new(1, 1, 1), UDim2.fromScale(0.32, 0.06), UDim2.fromScale(0.63, y), Enum.TextXAlignment.Right)
	value:SetAttribute("BoardRole", "Value")
	value:SetAttribute("BoardRow", i)
end
boardText("Footer", "", Color3.fromRGB(120, 255, 140), UDim2.fromScale(0.9, 0.06), UDim2.fromScale(0.05, 0.9), Enum.TextXAlignment.Center)
	:SetAttribute("BoardRole", "Footer")

Kit.save(gui)
