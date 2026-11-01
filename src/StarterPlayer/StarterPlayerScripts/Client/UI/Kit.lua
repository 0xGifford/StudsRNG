--[[

Kit
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/UI/Kit

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Builds kit-styled pieces at runtime from Assets.UI.Templates so menus
-- that list data (shop, zones, updates, odds) match the hand-made UI:
--   Kit.card      a "Store Item" card (icon, title, description, price)
--   Kit.button    one of Templates.Buttons (Orange, Green, Blue, Purple, Sunset)
--   Kit.label     a white outlined title label
--   Kit.setIcon   sets an image's Icon attribute (MenuSystem IconImage)
--   Kit.paint     sets a kit frame's KitColor attribute (MenuSystem KitColor)
--   Kit.list      prepares a window's Items ScrollingFrame; rows added with
--                 Kit.row keep their aspect ratio as the window scales

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Interface = require(script.Parent.Interface)

local Menus = ReplicatedStorage:WaitForChild("MenuSystem"):WaitForChild("Menus")
local IconImage = require(Menus:WaitForChild("IconImage"))
local KitColor = require(Menus:WaitForChild("KitColor"))

local Kit = {}

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

function Kit.template(name: string): Instance
	local template = Interface.Templates:FindFirstChild(name)
	assert(template, `StarterGui.Templates.{name} is missing`)
	return template:Clone()
end

local function buttonTemplate(color: string): Frame
	local folder = Interface.Templates:FindFirstChild("Buttons")
	assert(folder, "StarterGui.Templates.Buttons is missing")
	local template = folder:FindFirstChild(color) or folder:FindFirstChild("Blue")
	assert(template and template:IsA("Frame"), `StarterGui.Templates.Buttons.{color} is missing`)
	return template
end

--------------------------------------------------------------------------
-- Pieces
--------------------------------------------------------------------------

-- An icon on an image: a Config.Icons name, an asset id or an emoji
-- (MenuSystem's IconImage draws it from the Icon attribute).
function Kit.setIcon(image: ImageLabel, icon: string)
	IconImage.Set(image, { Icon = icon })
end

-- Recolours a kit frame (card or button) with a Templates.Buttons palette
-- (MenuSystem's KitColor draws it from the KitColor attribute).
function Kit.paint(frame: GuiObject, color: string)
	KitColor.Set(frame, { KitColor = color })
end

function Kit.button(color: string, text: string): Frame
	local frame = buttonTemplate(color):Clone()
	frame:SetAttribute("KitColor", color)
	frame.LayoutOrder = 0
	Interface.setText(frame, text)
	return frame
end

-- A white, outlined, gradient label in the kit's title font.
function Kit.label(text: string): TextLabel
	local label = Kit.template("Label") :: TextLabel
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 2
	label.Text = text
	return label
end

export type CardInfo = {
	Title: string,
	Description: string,
	Icon: string,
	Color: string,
}

-- A shop-style card. Price/priceIcon are set separately (Kit.setPrice).
function Kit.card(info: CardInfo): Frame
	local card = Kit.template("Store Item") :: Frame
	card.Name = info.Title
	card.AnchorPoint = Vector2.new(0, 0)
	card.Position = UDim2.new()
	-- Sized later by Kit.row / Kit.addCell; a zero size also makes
	-- Interface.bindButton animate with a UIScale instead of Size.
	card.Size = UDim2.new()
	card.LayoutOrder = 0
	Interface.setText(card, info.Title)
	local description = find(card, "Descriptions")
	if description and description:IsA("TextLabel") then
		description.Text = info.Description
	end
	for _, child in card:GetDescendants() do
		if child.Name == "Icon" and child:IsA("ImageLabel") then
			Kit.setIcon(child, info.Icon)
		end
	end
	Kit.paint(card, info.Color)
	return card
end

-- Price text with a currency icon (Robux, Clacks) or none (Owned, Soon...).
function Kit.setPrice(card: Instance, text: string, icon: string?)
	local price = find(card, "Price")
	if price and price:IsA("TextLabel") then
		price.Text = text
	end
	local robux = find(card, "Robux")
	if robux and robux:IsA("ImageLabel") then
		robux.Visible = icon ~= nil
		if icon then
			Kit.setIcon(robux, icon)
		end
	end
end

-- A small corner tag ("+50%", "4+1") on a card.
function Kit.badge(card: Frame, text: string)
	local tag = Kit.label(text)
	tag.Name = "Badge"
	tag.AnchorPoint = Vector2.new(1, 0)
	tag.Position = UDim2.fromScale(0.98, 0.04)
	tag.Size = UDim2.fromScale(0.2, 0.2)
	tag.Rotation = 8
	tag.TextColor3 = Color3.fromRGB(255, 240, 120)
	tag.ZIndex = 5
	tag.Parent = card
end

--------------------------------------------------------------------------
-- Lists
--------------------------------------------------------------------------

-- Clears a window's Items ScrollingFrame (keeping its layout) and switches
-- it to pixel padding + automatic height so rows can size themselves.
function Kit.list(items: ScrollingFrame)
	for _, child in items:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	items.CanvasSize = UDim2.new()
	items.AutomaticCanvasSize = Enum.AutomaticSize.Y
	items.ScrollingDirection = Enum.ScrollingDirection.Y
	items.CanvasPosition = Vector2.zero

	local layout = items:FindFirstChildOfClass("UIListLayout")
	if not layout then
		layout = Instance.new("UIListLayout")
		layout.Parent = items
	end
	local list = layout :: UIListLayout
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 10)
	list.Wraps = false

	local padding = items:FindFirstChildOfClass("UIPadding")
	if not padding then
		padding = Instance.new("UIPadding")
		padding.Parent = items
	end
	local pad = padding :: UIPadding
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new()
	pad.PaddingRight = UDim.new()

	if not items:GetAttribute("KitSized") then
		items:SetAttribute("KitSized", true)
		items:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			Kit.resize(items)
		end)
	end
end

-- Width scale of the list and width:height ratio for each row.
local WIDTH = 0.925

function Kit.resize(items: ScrollingFrame)
	local width = items.AbsoluteSize.X * WIDTH
	for _, child in items:GetChildren() do
		if child:IsA("GuiObject") then
			local aspect = child:GetAttribute("Aspect")
			if typeof(aspect) == "number" and aspect > 0 then
				child.Size = UDim2.new(WIDTH, 0, 0, math.floor(width / aspect))
			end
			local textScale = child:GetAttribute("TextScale")
			if typeof(textScale) == "number" and child:IsA("TextLabel") then
				child.TextSize = math.max(12, math.floor(width * textScale))
			end
		end
	end
end

-- Adds a row (any GuiObject) to a Kit.list, `aspect` = width / height.
function Kit.row(items: ScrollingFrame, row: GuiObject, aspect: number, order: number)
	row.AnchorPoint = Vector2.new(0, 0)
	row.Position = UDim2.new()
	row.LayoutOrder = order
	row:SetAttribute("Aspect", aspect)
	row.Parent = items
	local width = items.AbsoluteSize.X * WIDTH
	row.Size = UDim2.new(WIDTH, 0, 0, math.floor(width / aspect))
end

-- A row holding `count` equal cells side by side; returns the row.
function Kit.gridRow(count: number): Frame
	local row = Kit.template("GridRow") :: Frame
	row.Name = "Row"
	row:SetAttribute("Cells", count)
	return row
end

-- Puts a card into a gridRow made with Kit.gridRow.
function Kit.addCell(row: Frame, cell: GuiObject, order: number)
	local count = row:GetAttribute("Cells")
	local n = if typeof(count) == "number" then count else 2
	cell.AnchorPoint = Vector2.new(0, 0)
	cell.Position = UDim2.new()
	cell.LayoutOrder = order
	cell.Size = UDim2.fromScale((1 - 0.02 * (n - 1)) / n, 1)
	cell.Parent = row
end

-- A section title row for a Kit.list.
function Kit.header(items: ScrollingFrame, text: string, order: number)
	local holder = Kit.template("Header") :: Frame
	holder.Name = "Header"
	local label = holder:FindFirstChildWhichIsA("TextLabel", true)
	if label then
		label.Text = text
	end
	Kit.row(items, holder, 12, order)
end

-- Wrapped body text for a Kit.list (grows to fit; TextSize follows width).
function Kit.paragraph(items: ScrollingFrame, text: string, order: number, color: Color3?): TextLabel
	local label = Kit.template("Paragraph") :: TextLabel
	label.Name = "Paragraph"
	if color then
		label.TextColor3 = color
	end
	label.Text = text
	label.AnchorPoint = Vector2.new(0, 0)
	label.LayoutOrder = order
	label.Parent = items
	local width = items.AbsoluteSize.X * WIDTH
	label.Size = UDim2.new(WIDTH, 0, 0, 0)
	local textScale = label:GetAttribute("TextScale")
	label.TextSize = math.max(12, math.floor(width * (if typeof(textScale) == "number" then textScale else 0.032)))
	return label
end

return Kit
