--[[

SideButtons
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/UI/SideButtons

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The HUD's side buttons for code-driven menus (Pass, Badges...). They are
-- part of StarterGui.HUD (made by tools/ui/migrate.luau, edit them in
-- Studio): a kit side button named after the menu, whose Button carries
-- Menu = <menu>, so MenuSystem opens it.
--   SideButtons.add(menu, label, icon, order?) -> Frame?   finds it
--   SideButtons.setAlert(frame, on, text?)

local Interface = require(script.Parent.Interface)
local Juice = require(script.Parent.Juice)

local SideButtons = {}

local function container(): Instance?
	return Interface.HUD:FindFirstChild("Side")
end

-- label / icon / order describe the button for the migration; at runtime
-- the HUD's own button is used as it was made.
function SideButtons.add(menu: string, _label: string, _icon: string, _order: number?): Frame?
	Interface.setup()
	local side = container() or Interface.HUD
	local existing = side:FindFirstChild(menu, true)
	if existing and existing:IsA("Frame") then
		return existing
	end
	warn(`[SideButtons] the HUD has no side button named {menu} (run tools/ui/migrate.luau on your place)`)
	return nil
end

function SideButtons.setAlert(frame: Frame?, on: boolean, text: string?)
	local alert = frame and frame:FindFirstChild("Alert")
	if not (alert and alert:IsA("GuiObject")) then return end
	if on and not alert.Visible then
		Juice.pop(alert, 1.6)
	end
	alert.Visible = on
	if text then
		Interface.setText(alert, text)
	end
end

return SideButtons
