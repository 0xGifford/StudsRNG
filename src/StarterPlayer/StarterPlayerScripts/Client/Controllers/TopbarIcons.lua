--[[

TopbarIcons
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/TopbarIcons

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Settings and Updates live in the Roblox top bar via TopbarPlus instead of
-- HUD buttons. Install TopbarPlus (the "Icon" module) at
-- ReplicatedStorage.Packages.Icon or ReplicatedStorage.Icon.
--
-- Without TopbarPlus the HUD's Options button comes back, and an unread
-- update log opens once on join, so nothing becomes unreachable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local UpdatesMenu = require(Controllers.UpdatesMenu)
local Interface = require(UI.Interface)
local UIConfig = require(UI.UIConfig)

local TopbarIcons = {}

local SEARCH_TIME = 5

local function findIconModule(): ModuleScript?
	local deadline = os.clock() + SEARCH_TIME
	repeat
		local packages = ReplicatedStorage:FindFirstChild("Packages")
		for _, candidate in {
			packages and packages:FindFirstChild("Icon"),
			packages and packages:FindFirstChild("TopbarPlus"),
			ReplicatedStorage:FindFirstChild("Icon"),
			ReplicatedStorage:FindFirstChild("TopbarPlus"),
		} do
			if candidate and candidate:IsA("ModuleScript") then
				return candidate
			end
		end
		task.wait(0.25)
	until os.clock() > deadline
	return nil
end

-- TopbarPlus methods differ a little between versions: call what exists.
local function call(icon: any, method: string, ...: any)
	local fn = icon[method]
	if typeof(fn) == "function" then
		local ok, err = pcall(fn, icon, ...)
		if not ok then
			warn(`[TopbarIcons] {method} failed: {err}`)
		end
	end
end

local function onSelected(icon: any, handler: () -> ())
	local signal = icon.selected
	if typeof(signal) == "table" and typeof(signal.Connect) == "function" then
		signal:Connect(handler)
	elseif typeof(icon.bindEvent) == "function" then
		icon:bindEvent("selected", handler)
	end
end

local function makeIcon(Icon: any, label: string, image: string, order: number, menu: string): any
	local icon = Icon.new()
	if image ~= "" then
		call(icon, "setImage", image)
		call(icon, "setCaption", label)
	else
		call(icon, "setLabel", label)
	end
	call(icon, "setOrder", order)
	call(icon, "oneClick", true)
	onSelected(icon, function()
		Interface.toggle(menu)
	end)
	return icon
end

local function fallback()
	warn("[TopbarIcons] TopbarPlus not found (ReplicatedStorage.Packages.Icon); showing the HUD Options button instead")
	local side = Interface.HUD:FindFirstChild("Side")
	local buttons = side and side:FindFirstChild("Buttons")
	local options = buttons and buttons:FindFirstChild("Options")
	if options and options:IsA("GuiObject") then
		options.Visible = true
	end
	local function openUnread()
		if UpdatesMenu.hasUnread() then
			Interface.open("Updates")
		end
	end
	if State.isReady() then
		openUnread()
	else
		State.Ready:Connect(openUnread)
	end
end

function TopbarIcons.start()
	Interface.setup()

	local module = findIconModule()
	if not module then
		fallback()
		return
	end
	local ok, Icon = pcall(require, module)
	if not ok or typeof(Icon) ~= "table" then
		warn(`[TopbarIcons] couldn't load TopbarPlus: {Icon}`)
		fallback()
		return
	end

	makeIcon(Icon, "Settings", UIConfig.Topbar.SettingsImage, 1, "Options")
	local updates = makeIcon(Icon, "Updates", UIConfig.Topbar.UpdatesImage, 2, "Updates")

	-- Notification dot until the newest update has been read.
	local notified = false
	local function refreshNotice()
		if UpdatesMenu.hasUnread() and not notified then
			notified = true
			call(updates, "notify")
		elseif not UpdatesMenu.hasUnread() and notified then
			notified = false
			call(updates, "clearNotices")
		end
	end
	State.Changed:Connect(function(field)
		if field == "SeenUpdate" then
			refreshNotice()
		end
	end)
	if State.isReady() then
		refreshNotice()
	else
		State.Ready:Connect(refreshNotice)
	end
end

return TopbarIcons
