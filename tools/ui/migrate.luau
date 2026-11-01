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
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local UDim2 = roblox.UDim2
local Vector2 = roblox.Vector2

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

local function migrate(starterGui: any): { string }
	local log = {}
	splitMenu(starterGui, log)
	for _, gui in starterGui:GetChildren() do
		if gui:IsA("ScreenGui") then
			moveButtonAttributes(gui, log)
		end
	end
	local hud = starterGui:FindFirstChild("HUD")
	if hud and not hud:HasTag("HudSlide") then
		hud:AddTag("HudSlide")
		table.insert(log, "HUD tagged HudSlide")
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
