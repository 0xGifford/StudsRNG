--!strict
--[[
	ReplicatedStorage/MenuSystem/Menus/KitColor

	Recolours a kit button or card from the kit's palette.

		Claim (Frame, a kit button)   KitColor = "Green"

	ATTRIBUTES
		KitColor   string   a button in Templates.Buttons: Green, Blue,
		                    Orange, Purple, Sunset...; the marker
	Copies the palette button's background, its Gradient's UIGradient and
	its outline gradient. The palette is StarterGui.Templates.Buttons (or
	ReplicatedStorage.Assets.UI.Templates.Buttons in older places).

	API
		KitColor.Start()
		KitColor.Set(frame, { KitColor = "Purple" })
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Component = require(script.Parent.Component)

local function palette(name: string): GuiObject?
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local templates = playerGui and playerGui:FindFirstChild("Templates")
	local buttons = templates and templates:FindFirstChild("Buttons")
	if not buttons then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local ui = assets and assets:FindFirstChild("UI")
		local old = ui and ui:FindFirstChild("Templates")
		buttons = old and old:FindFirstChild("Buttons")
	end
	local found = buttons and buttons:FindFirstChild(name)
	return if found and found:IsA("GuiObject") then found else nil
end

local function render(frame: GuiObject)
	local name = frame:GetAttribute("KitColor")
	if type(name) ~= "string" or name == "" then return end
	local source = palette(name)
	if not source then
		warn(`[KitColor] no kit button named "{name}" in Templates.Buttons`)
		return
	end
	frame.BackgroundColor3 = source.BackgroundColor3

	local sourceGradient = source:FindFirstChild("Gradient")
	local targetGradient = frame:FindFirstChild("Gradient")
	if not (sourceGradient and targetGradient) then return end
	local fill = sourceGradient:FindFirstChildOfClass("UIGradient")
	local targetFill = targetGradient:FindFirstChildOfClass("UIGradient")
	if fill and targetFill then
		targetFill.Color = fill.Color
	end
	local stroke = sourceGradient:FindFirstChildOfClass("UIStroke")
	local targetStroke = targetGradient:FindFirstChildOfClass("UIStroke")
	local strokeGradient = stroke and stroke:FindFirstChildOfClass("UIGradient")
	local targetStrokeGradient = targetStroke and targetStroke:FindFirstChildOfClass("UIGradient")
	if strokeGradient and targetStrokeGradient then
		targetStrokeGradient.Color = strokeGradient.Color
	end
end

return Component.new({
	Marker = "KitColor",
	Class = "GuiObject",
	Render = render,
})
