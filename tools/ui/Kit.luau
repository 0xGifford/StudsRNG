--[[
	The Lune side of the UI kit: builds GUI the way the game's own UI looks,
	from the game's own pieces, so screens built here match the ones made in
	Studio. Used by the screen scripts in tools/ui/screens (run them with
	tools/build_ui.luau). Nothing here runs in the game.

	  Kit.window(name, title)        a menu window, cloned from the Menu
	                                 ScreenGui's own window frame (Top bar,
	                                 Exit button, Main panel)
	  Kit.button(color, text)        a kit button (Assets.UI.Templates.Buttons:
	                                 Green, Blue, Orange, Purple, Sunset)
	  Kit.label(text, props)         white kit text with a dark outline
	  Kit.textbox(placeholder)       an input box
	  Kit.panel(props)               a dark rounded panel
	  Kit.list(props)                a ScrollingFrame with a list or grid layout
	  Kit.new(class, props, parent)  any instance, props applied
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local UDim2 = roblox.UDim2
local UDim = roblox.UDim
local Vector2 = roblox.Vector2
local Color3 = roblox.Color3
local Enum = roblox.Enum
local Font = roblox.Font

local Kit = {}

Kit.Instance = Instance
Kit.UDim2 = UDim2
Kit.UDim = UDim
Kit.Vector2 = Vector2
Kit.Color3 = Color3
Kit.Enum = Enum
Kit.Font = Font
Kit.ColorSequence = roblox.ColorSequence
Kit.NumberSequence = roblox.NumberSequence

Kit.FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.ExtraBold)
Kit.FONT_BODY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
Kit.DARK = Color3.fromRGB(25, 25, 25)
Kit.PANEL = Color3.fromRGB(18, 18, 24)
Kit.ROW = Color3.fromRGB(32, 32, 42)

local uiAssets = roblox.deserializeModel(fs.readFile("src/ReplicatedStorage/Assets/UI.rbxm"))[1]
local menu = roblox.deserializeModel(fs.readFile("src/StarterGui/Menu.rbxm"))[1]

function Kit.new(className: string, props: { [string]: any }?, parent: any?): any
	local instance = Instance.new(className)
	for key, value in props or {} do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function stroke(parent: any, thickness: number?, color: any?)
	return Kit.new("UIStroke", {
		Thickness = thickness or 2,
		Color = color or Kit.DARK,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, parent)
end
Kit.stroke = stroke

function Kit.corner(parent: any, radius: number?)
	return Kit.new("UICorner", { CornerRadius = UDim.new(radius or 0.15, 0) }, parent)
end

-- Kit text: white with a dark outline, scaled to fit.
function Kit.label(text: string, props: { [string]: any }?): any
	local label = Kit.new("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		FontFace = Kit.FONT,
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		TextWrapped = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	})
	stroke(label, 2)
	Kit.new("UITextSizeConstraint", { MaxTextSize = 28, MinTextSize = 8 }, label)
	for key, value in props or {} do
		label[key] = value
	end
	return label
end

function Kit.textbox(placeholder: string, props: { [string]: any }?): any
	local box = Kit.new("TextBox", {
		Name = "Input",
		BackgroundColor3 = Kit.ROW,
		BackgroundTransparency = 0.1,
		FontFace = Kit.FONT_BODY,
		PlaceholderText = placeholder,
		PlaceholderColor3 = Color3.fromRGB(150, 150, 165),
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	})
	Kit.corner(box, 0.2)
	stroke(box, 2)
	Kit.new("UIPadding", { PaddingLeft = UDim.new(0.03, 0), PaddingRight = UDim.new(0.03, 0), PaddingTop = UDim.new(0.18, 0), PaddingBottom = UDim.new(0.18, 0) }, box)
	Kit.new("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 8 }, box)
	for key, value in props or {} do
		box[key] = value
	end
	return box
end

function Kit.panel(props: { [string]: any }?): any
	local panel = Kit.new("Frame", {
		Name = "Panel",
		BackgroundColor3 = Kit.PANEL,
		BackgroundTransparency = 0.35,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	})
	Kit.corner(panel, 0.04)
	stroke(panel, 2)
	for key, value in props or {} do
		panel[key] = value
	end
	return panel
end

-- A kit button frame (with its transparent TextButton named "Button"),
-- cloned from Assets.UI.Templates.Buttons.
function Kit.button(color: string, text: string, props: { [string]: any }?): any
	local folder = uiAssets.Templates.Buttons
	local template = folder:FindFirstChild(color) or folder.Blue
	local button = template:Clone()
	button.Name = text:gsub("%s", "")
	for _, child in button:GetChildren() do
		if child.Name == "Title" or child.Name == "TitleShadow" then
			child.Text = text
		end
	end
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = UDim2.fromScale(1, 1)
	for key, value in props or {} do
		button[key] = value
	end
	return button
end

-- A ScrollingFrame with a list (or, with Cell set, a grid) layout.
function Kit.list(props: { [string]: any }?): any
	local options = props or {}
	local scroll = Kit.new("ScrollingFrame", {
		Name = options.Name or "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Color3.fromRGB(200, 200, 210),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AnchorPoint = options.AnchorPoint or Vector2.new(0.5, 0.5),
		Position = options.Position or UDim2.fromScale(0.5, 0.5),
		Size = options.Size or UDim2.fromScale(1, 1),
	})
	if options.Cell then
		Kit.new("UIGridLayout", {
			CellSize = options.Cell,
			CellPadding = options.Padding or UDim2.new(0.02, 0, 0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}, scroll)
	else
		Kit.new("UIListLayout", {
			Padding = UDim.new(0, options.Gap or 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}, scroll)
	end
	Kit.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, scroll)
	return scroll
end

-- A full-screen container shaped like the Menu ScreenGui's Canva (same
-- aspect ratio), so windows built here size exactly like the game's menus.
function Kit.canvas(name: string): any
	local source = menu:FindFirstChild("Canva")
	local canvas = Kit.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	})
	local aspect = source and source:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aspect then
		aspect:Clone().Parent = canvas
	end
	return canvas
end

-- A menu window: the Menu ScreenGui's own window frame (Top bar with title,
-- Exit button, Main panel), emptied. Its Main.Items is removed: fill Main.
function Kit.window(name: string, title: string): any
	local source = menu.Canva:FindFirstChild("Zones")
	assert(source, "Menu.Canva.Zones (the window to copy) is missing")
	local window = source:Clone()
	window.Name = name
	window.Visible = false
	for _, attribute in { "Blur", "HideHUD" } do
		window:SetAttribute(attribute, nil)
	end
	local top = window:FindFirstChild("Top")
	for _, child in top:GetChildren() do
		if child.Name == "Title" or child.Name == "TitleShadow" then
			child.Text = title
		end
	end
	local main = window:FindFirstChild("Main")
	local items = main:FindFirstChild("Items")
	if items then items:Destroy() end
	return window
end

-- Writes a ScreenGui to src/StarterGui/<name>.rbxm.
function Kit.save(gui: any)
	local path = `src/StarterGui/{gui.Name}.rbxm`
	fs.writeFile(path, roblox.serializeModel({ gui }))
	print(`built {path}`)
end

return Kit
