--[[

SideButtons
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/UI/SideButtons

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Adds a button to the HUD's side menu for a code-built menu, by cloning one
-- of the side buttons made in Studio (so it matches the kit). The clone
-- carries the Menu attribute, so Interface wires it (Shared/Tags) and Hud
-- leaves it alone.
--   SideButtons.add(menu, label, icon, order?) -> Frame?
--   SideButtons.setAlert(frame, on, text?)

local Interface = require(script.Parent.Interface)
local Kit = require(script.Parent.Kit)
local Juice = require(script.Parent.Juice)

local SideButtons = {}

local TEMPLATES = { "Quests", "Rewards", "Zones", "Store" }

local function container(): Instance?
	local side = Interface.HUD:FindFirstChild("Side")
	return side and side:FindFirstChild("Buttons")
end

local function template(buttons: Instance): Frame?
	for _, name in TEMPLATES do
		local frame = buttons:FindFirstChild(name)
		if frame and frame:IsA("Frame") and frame:FindFirstChild("Button") then
			return frame
		end
	end
	for _, child in buttons:GetChildren() do
		if child:IsA("Frame") and child:FindFirstChild("Button") then
			return child
		end
	end
	return nil
end

function SideButtons.add(menu: string, label: string, icon: string, order: number?): Frame?
	Interface.setup()
	local buttons = container()
	if not buttons then
		warn(`[SideButtons] HUD.Side.Buttons not found; no button for {menu}`)
		return nil
	end
	local existing = buttons:FindFirstChild(menu)
	if existing and existing:IsA("Frame") then
		return existing
	end
	local source = template(buttons)
	if not source then return nil end

	local frame = source:Clone()
	frame.Name = menu
	frame.Visible = true
	frame.LayoutOrder = order or (source.LayoutOrder + 50)
	frame:SetAttribute("Menu", menu)
	Interface.setText(frame, label)
	local alert = frame:FindFirstChild("Alert")
	if alert and alert:IsA("GuiObject") then
		alert.Visible = false
	end
	local image = frame:FindFirstChild("Icon", true)
	if image and image:IsA("ImageLabel") then
		Kit.setIcon(image, icon)
	end
	frame.Parent = buttons
	Interface.bindMenuButton(frame)
	return frame
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
