--[[
	Moves the game's UI onto MenuSystem's attribute / tag conventions.

	  lune run tools/ui/migrate.luau place <in.rbxl> <out.rbxl>
	      your place: its StarterGui is migrated in place (do this once on a
	      copy of your Studio place, then keep editing the result)
	  lune run tools/ui/migrate.luau repo
	      src/StarterGui/*.rbxm (the repo's copy of the UI)

	What it does (anything already migrated is left alone):
	  * Menu.Canva's windows (Store, Index, Zones...) each become their own
	    ScreenGui named like the window: tagged "Menu", the window marked
	    MenuPanel = true, Scale = false (the windows are sized in scale, with
	    the Canva's aspect ratio, which a "Canva" frame keeps), the window's
	    Top.Exit button gets MenuAction = "close". A window's old Blur = false
	    becomes Backdrop = false on its ScreenGui, HideHUD = false becomes
	    KeepHud = true. The empty Menu ScreenGui is removed.
	  * Menu / MenuAction / Tab / Toggle attributes on a kit button Frame move
	    to its "Button" (MenuSystem binds GuiButtons; the kit Frame still
	    bounces, see Core/ButtonBounce).
	  * The HUD ScreenGui is tagged "HudSlide" (it slides away while a menu is
	    open).
	  * The HUD gets what code used to do to it at runtime: the Slime RNG
	    layout (right column, LeftButtons grid, bottom bar; HudArranged =
	    true), side buttons for the Pass and Badges menus, and the combo
	    meter label under the Clacks counter (HudRole = "Combo") and the layer
	    the Clacks popups fly across (HudRole = "ClackPopups").
	  * Menus whose UI used to be built in code (Index, ...) get the repo's
	    StarterGui build in place of the kit pack's old window (REPLACED).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local UDim2 = roblox.UDim2
local Vector2 = roblox.Vector2
local UDim = roblox.UDim
local Color3 = roblox.Color3
local Enum = roblox.Enum

local BUTTON_ATTRIBUTES = { "Menu", "MenuAction", "Tab", "TabGroup", "Toggle" }

local function splitMenu(starterGui: any, log: { string })
	local menu = starterGui:FindFirstChild("Menu")
	local canva = menu and menu:FindFirstChild("Canva")
	if not canva then return end
	local aspects = {}
	for _, child in canva:GetChildren() do
		if child:IsA("UIAspectRatioConstraint") then
			table.insert(aspects, child)
		end
	end
	for _, window in canva:GetChildren() do
		if not window:IsA("GuiObject") then continue end
		if starterGui:FindFirstChild(window.Name) then
			table.insert(log, `skipped {window.Name}: a ScreenGui by that name exists`)
			continue
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = window.Name
		for _, property in { "IgnoreGuiInset", "ZIndexBehavior", "DisplayOrder", "ScreenInsets", "SafeAreaCompatibility" } do
			pcall(function()
				gui[property] = menu[property]
			end)
		end
		gui.ResetOnSpawn = false
		gui.Enabled = false
		gui:AddTag("Menu")
		gui:SetAttribute("Scale", false)
		if window:GetAttribute("Blur") == false then
			gui:SetAttribute("Backdrop", false)
		end
		if window:GetAttribute("HideHUD") == false then
			gui:SetAttribute("KeepHud", true)
		end
		window:SetAttribute("Blur", nil)
		window:SetAttribute("HideHUD", nil)

		local holder = Instance.new("Frame")
		holder.Name = "Canva"
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.5)
		holder.Size = UDim2.fromScale(1, 1)
		for _, aspect in aspects do
			aspect:Clone().Parent = holder
		end
		window.Visible = true
		window:SetAttribute("MenuPanel", true)
		local top = window:FindFirstChild("Top")
		local exit = top and top:FindFirstChild("Exit")
		local button = exit and exit:FindFirstChild("Button")
		if button and button:IsA("GuiButton") then
			button:SetAttribute("MenuAction", "close")
		end
		window.Parent = holder
		holder.Parent = gui
		gui.Parent = starterGui
		table.insert(log, `menu {window.Name}`)
	end
	local left = 0
	for _, child in canva:GetChildren() do
		if child:IsA("GuiObject") then left += 1 end
	end
	if left == 0 then
		menu:Destroy()
		table.insert(log, "removed the old Menu ScreenGui")
	end
end

local function moveButtonAttributes(root: any, log: { string })
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") and not d:IsA("GuiButton") then
			local button = d:FindFirstChild("Button")
			if button and button:IsA("GuiButton") then
				for _, name in BUTTON_ATTRIBUTES do
					local value = d:GetAttribute(name)
					if value ~= nil then
						if button:GetAttribute(name) == nil then
							button:SetAttribute(name, value)
						end
						d:SetAttribute(name, nil)
						table.insert(log, `{d:GetFullName()}: {name} -> Button`)
					end
				end
			end
		end
	end
end

-- The Slime RNG style HUD layout (what Controllers/HudLayout used to do at
-- runtime), baked in once: HudArranged = true on the HUD marks it done.
--   bottom centre   BACKPACK · ROLL · UPGRADE (and AUTO)
--   right column    SHOP · REBIRTH · INDEX · TELEPORT
--   left column     LeftButtons: everything else, plus Pass and Badges
local RIGHT = { "Store", "Rebirth", "Index", "Zones" }
local LABELS = { Store = "SHOP", Rebirth = "REBIRTH", Index = "INDEX", Zones = "TELEPORT", Upgrades = "UPGRADE" }
-- Side buttons for menus that have no kit button of their own.
local EXTRA_BUTTONS = {
	{ Menu = "StudPass", Label = "Pass", Emoji = "🎟️" },
	{ Menu = "Achievements", Label = "Badges", Emoji = "🏅" },
}

local function setText(frame: any, text: string)
	for _, name in { "Title", "TitleShadow" } do
		local label = frame:FindFirstChild(name)
		if label and label:IsA("TextLabel") then
			label.Text = text
		end
	end
end

local function arrangeHud(hud: any, log: { string })
	if hud:GetAttribute("HudArranged") == true then return end
	local side = hud:FindFirstChild("Side")
	local buttons = side and side:FindFirstChild("Buttons")
	local top = hud:FindFirstChild("Top")
	local bar = top and top:FindFirstChild("Frame")
	if not (buttons and bar) then
		table.insert(log, "HUD has no Side.Buttons / Top.Frame: layout left as it is")
		return
	end

	-- Right column.
	buttons.AnchorPoint = Vector2.new(1, 0.5)
	buttons.Position = UDim2.new(1, -8, 0.52, 0)
	buttons.Size = UDim2.fromScale(0.08, 0.62)
	local ratio = buttons:FindFirstChildOfClass("UIAspectRatioConstraint")
	if ratio then ratio:Destroy() end
	local list = buttons:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0.025, 0)
	list.Wraps = false
	list.Parent = buttons

	-- Left column for the rest.
	local left = Instance.new("Frame")
	left.Name = "LeftButtons"
	left.BackgroundTransparency = 1
	left.AnchorPoint = Vector2.new(0, 0)
	left.Position = UDim2.new(0, 8, 0.56, 0)
	left.Size = UDim2.fromScale(0.13, 0.3)
	left.Parent = side
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromScale(0.46, 0.46)
	grid.CellPadding = UDim2.fromScale(0.04, 0.04)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirectionMaxCells = 2
	grid.Parent = left
	local leftRatio = Instance.new("UIAspectRatioConstraint")
	leftRatio.AspectRatio = 1
	leftRatio.Parent = left

	-- A kit side button to copy for the extra ones.
	local template = nil
	for _, name in { "Quests", "Rewards", "Zones", "Store" } do
		local frame = buttons:FindFirstChild(name)
		if frame and frame:FindFirstChild("Button") then
			template = frame
			break
		end
	end

	-- UPGRADE joins the bottom bar, right of ROLL.
	local upgrades = buttons:FindFirstChild("Upgrades")
	if upgrades and upgrades:IsA("Frame") then
		upgrades.Parent = bar
		upgrades.Size = UDim2.fromScale(0.12, 1.2)
		local upgradeRatio = upgrades:FindFirstChildOfClass("UIAspectRatioConstraint")
		if upgradeRatio then
			upgradeRatio.DominantAxis = Enum.DominantAxis.Height
		end
		setText(upgrades, LABELS.Upgrades)
	end

	for _, child in buttons:GetChildren() do
		if child:IsA("Frame") and child:FindFirstChild("Button") then
			local order = table.find(RIGHT, child.Name)
			if order then
				child.LayoutOrder = order
				child.Size = UDim2.fromScale(1, 0.22)
				local square = child:FindFirstChildOfClass("UIAspectRatioConstraint") or Instance.new("UIAspectRatioConstraint")
				square.AspectRatio = 1
				square.DominantAxis = Enum.DominantAxis.Height
				square.Parent = child
				if LABELS[child.Name] then
					setText(child, LABELS[child.Name])
				end
			else
				child.Parent = left
			end
		end
	end

	-- Pass, Badges...: copies of a kit side button, opening their menus.
	if template then
		for i, extra in EXTRA_BUTTONS do
			if not hud:FindFirstChild(extra.Menu, true) then
				local frame = template:Clone()
				frame.Name = extra.Menu
				frame.Visible = true
				frame.LayoutOrder = 100 + i
				local hit = frame:FindFirstChild("Button")
				hit:SetAttribute("Menu", extra.Menu)
				setText(frame, extra.Label)
				local alert = frame:FindFirstChild("Alert")
				if alert then alert.Visible = false end
				local icon = frame:FindFirstChild("Icon", true)
				if icon and icon:IsA("ImageLabel") then
					icon.ImageTransparency = 1
					local emoji = Instance.new("TextLabel")
					emoji.Name = "Emoji"
					emoji.BackgroundTransparency = 1
					emoji.AnchorPoint = Vector2.new(0.5, 0.5)
					emoji.Position = UDim2.fromScale(0.5, 0.5)
					emoji.Size = UDim2.fromScale(0.8, 0.8)
					emoji.TextScaled = true
					emoji.TextColor3 = Color3.new(1, 1, 1)
					emoji.Text = extra.Emoji
					emoji.ZIndex = icon.ZIndex + 1
					emoji.Parent = icon
				end
				frame.Parent = left
			end
		end
	end

	-- Bottom bar: BACKPACK · ROLL · UPGRADE · AUTO.
	local order = { Studs = 1, Roll = 2, Upgrades = 3, Auto = 4 }
	for name, index in order do
		local frame = bar:FindFirstChild(name)
		if frame then
			frame.LayoutOrder = index
		end
	end
	local barLayout = bar:FindFirstChildOfClass("UIListLayout")
	if barLayout then
		barLayout.SortOrder = Enum.SortOrder.LayoutOrder
		barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		barLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	end
	local studs = bar:FindFirstChild("Studs")
	if studs then
		setText(studs, "Backpack")
	end
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.fromScale(0.5, 0.975)

	hud:SetAttribute("HudArranged", true)
	table.insert(log, "HUD: arranged (right column, LeftButtons, bottom bar, Pass and Badges buttons)")
end

-- The combo meter ("x1.25 COMBO") under the Clacks counter.
local function addCombo(hud: any, log: { string })
	for _, d in hud:GetDescendants() do
		if d:GetAttribute("HudRole") == "Combo" then return end
	end
	local labels = hud:FindFirstChild("Labels")
	local amounts = labels and labels:FindFirstChild("Amounts")
	local clacks = amounts and amounts:FindFirstChild("Clacks")
	local source = clacks and clacks:FindFirstChild("Amount")
	if not (amounts and source) then
		table.insert(log, "HUD has no Labels.Amounts.Clacks.Amount: no combo label added")
		return
	end
	local label = source:Clone()
	label.Name = "Combo"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(amounts.Position.X.Scale, 0, amounts.Position.Y.Scale + amounts.Size.Y.Scale * 0.55, 0)
	label.Size = UDim2.fromScale(amounts.Size.X.Scale * 0.8, amounts.Size.Y.Scale * 0.38)
	label.Text = "x1.25 COMBO"
	label.TextTransparency = 1
	label.Rotation = -4
	label.ZIndex = 10
	label:SetAttribute("HudRole", "Combo")
	for _, child in label:GetChildren() do
		if child:IsA("UIScale") then child:Destroy() end
	end
	local scale = Instance.new("UIScale")
	scale.Parent = label
	label.Parent = hud
	table.insert(log, "HUD: added the combo label (HudRole = Combo)")
end

-- The full-screen layer the "+123" Clacks popups fly across.
local function addPopupLayer(hud: any, log: { string })
	for _, d in hud:GetDescendants() do
		if d:GetAttribute("HudRole") == "ClackPopups" then return end
	end
	local layer = Instance.new("Frame")
	layer.Name = "ClackPopups"
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 50
	layer:SetAttribute("HudRole", "ClackPopups")
	layer.Parent = hud
	table.insert(log, "HUD: added the Clacks popup layer (HudRole = ClackPopups)")
end

-- The Daily window's week-streak line under the days.
local function addDailyStreak(starterGui: any, log: { string })
	local daily = starterGui:FindFirstChild("Daily")
	if not daily then return end
	for _, d in daily:GetDescendants() do
		if d:GetAttribute("DailyRole") == "WeekStreak" then return end
	end
	local main = daily:FindFirstChild("Main", true)
	if not main then return end
	local label = Instance.new("TextLabel")
	label.Name = "WeekStreak"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 1.01)
	label.Size = UDim2.fromScale(0.9, 0.07)
	label.FontFace = roblox.Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 170, 60)
	label.Text = "🔥 Week 1"
	label:SetAttribute("DailyRole", "WeekStreak")
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(15, 15, 20)
	stroke.Parent = label
	label.Parent = main
	table.insert(log, "Daily: added the week streak label (DailyRole = WeekStreak)")
end

-- Menus whose code-built UI moved into StarterGui: the repo's build
-- (src/StarterGui/<name>.rbxm) replaces a ScreenGui of that name that has
-- none of the role attribute (the kit pack's unused placeholder window), or
-- is added when there's none. Keyed by the role attribute its code finds.
local REPLACED = {
	Index = "IndexRole",
	Achievements = "AchievementRole",
	StudPass = "PassRole",
	Studs = "BackpackRole",
	Upgrades = "UpgradeRole",
}

local function hasRole(root: any, attribute: string): boolean
	for _, d in root:GetDescendants() do
		if d:GetAttribute(attribute) ~= nil then return true end
	end
	return false
end

local function replaceBuilt(starterGui: any, log: { string })
	for name, attribute in REPLACED do
		local old = starterGui:FindFirstChild(name)
		if old and hasRole(old, attribute) then continue end
		local path = `src/StarterGui/{name}.rbxm`
		if not fs.isFile(path) then continue end
		local built = roblox.deserializeModel(fs.readFile(path))[1]
		if old then
			old:Destroy()
		end
		built.Parent = starterGui
		table.insert(log, `{name}: {if old then "replaced the old window with" else "added"} the repo build ({attribute})`)
	end
end

local function migrate(starterGui: any): { string }
	local log = {}
	splitMenu(starterGui, log)
	replaceBuilt(starterGui, log)
	for _, gui in starterGui:GetChildren() do
		if gui:IsA("ScreenGui") then
			moveButtonAttributes(gui, log)
		end
	end
	addDailyStreak(starterGui, log)
	local hud = starterGui:FindFirstChild("HUD")
	if hud and not hud:HasTag("HudSlide") then
		hud:AddTag("HudSlide")
		table.insert(log, "HUD tagged HudSlide")
	end
	if hud then
		arrangeHud(hud, log)
		addCombo(hud, log)
		addPopupLayer(hud, log)
	end
	return log
end

local mode = process.args[1]
if mode == "place" then
	local input, output = process.args[2], process.args[3]
	assert(input and output, "usage: lune run tools/ui/migrate.luau place <in.rbxl> <out.rbxl>")
	local game = roblox.deserializePlace(fs.readFile(input))
	local log = migrate(game:GetService("StarterGui"))
	for _, line in log do print("  " .. line) end
	fs.writeFile(output, roblox.serializePlace(game))
	print(`{#log} change(s) → {output}`)
elseif mode == "repo" then
	local folder = Instance.new("Folder")
	local files = {}
	for _, entry in fs.readDir("src/StarterGui") do
		if string.match(entry, "%.rbxm$") then
			for _, item in roblox.deserializeModel(fs.readFile("src/StarterGui/" .. entry)) do
				item.Parent = folder
				files[item.Name] = entry
			end
		end
	end
	local log = migrate(folder)
	for _, line in log do print("  " .. line) end
	-- One file per ScreenGui; files of removed guis go.
	local kept = {}
	for _, gui in folder:GetChildren() do
		fs.writeFile(`src/StarterGui/{gui.Name}.rbxm`, roblox.serializeModel({ gui }))
		kept[`{gui.Name}.rbxm`] = true
	end
	for _, entry in files do
		if not kept[entry] and fs.isFile("src/StarterGui/" .. entry) then
			fs.removeFile("src/StarterGui/" .. entry)
			print(`  removed src/StarterGui/{entry}`)
		end
	end
	print(`{#log} change(s) in src/StarterGui`)
else
	print("usage: lune run tools/ui/migrate.luau place <in.rbxl> <out.rbxl> | repo")
	process.exit(1)
end
