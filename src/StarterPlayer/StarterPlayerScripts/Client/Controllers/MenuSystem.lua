--[[

MenuSystem
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/MenuSystem

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Boots ReplicatedStorage.MenuSystem (the attribute / tag driven UI system:
-- menus, buttons, tabs, toggles, purchases, tooltips, data labels, motion,
-- effects, HUD slide, admin panel, announcements) and plugs the game's client
-- State into it (MenuSystem/Data). Runs in init(), before any controller's
-- start(), so every menu is registered by the time controllers open them.
--
-- Order matters in one direction: the Registry watches PlayerGui before
-- anything binds to what it finds, and menus are registered before tab
-- groups scan for them. A module that fails to start warns and the rest
-- carry on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MenuSystem = ReplicatedStorage:WaitForChild("MenuSystem")
local Menus = MenuSystem:WaitForChild("Menus")
local Data = require(MenuSystem:WaitForChild("Data"))

local State = require(script.Parent.State)

local BOOT = {
	"ConfigOverrides",
	"Scale",
	"Registry",
	"MenuController",
	"AdminPanel",
	"Announcements",
	"Effects",
	"HudSlide",
	"ButtonBinder",
	"TabController",
	"ToggleController",
	"PurchaseController",
	"Tooltip",
	"PackShared",
	"PriceTag",
	"DataLabel",
	"Motion",
}

local MenuSystemController = {}

function MenuSystemController.init()
	Data.Provide({
		isReady = State.isReady,
		get = State.get,
		changed = State.Changed,
	})

	local failed = {}
	for _, name in BOOT do
		local module = Menus:FindFirstChild(name)
		if not module then
			table.insert(failed, `{name} (missing)`)
			continue
		end
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" and type(result.Start) == "function" then
			ok, result = pcall(result.Start)
		end
		if not ok then
			warn(`[MenuSystem] {name} failed: {result}`)
			table.insert(failed, name)
		end
	end
	if #failed > 0 then
		warn(`[MenuSystem] did not start: {table.concat(failed, ", ")}`)
	end
end

return MenuSystemController
