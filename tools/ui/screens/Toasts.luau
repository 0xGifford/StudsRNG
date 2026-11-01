--[[
	Toasts: short messages under the top bar (Interface.toast). The template
	(UITemplate = "Toast") is a copy of the HUD's Clacks amount label, so
	toasts look like the HUD; its Amount / AmountShadow labels get the text.
	The UIListLayout stacks them.
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Kit = require("../Kit")
local UDim2, UDim, Enum = Kit.UDim2, Kit.UDim, Kit.Enum

local gui = Kit.new("ScreenGui", {
	Name = "Toasts", ResetOnSpawn = false, DisplayOrder = 20, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
Kit.new("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Top, Padding = UDim.new(0.005, 0),
}, gui)
Kit.new("UIPadding", { PaddingTop = UDim.new(0.2, 0) }, gui)

local hud = roblox.deserializeModel(fs.readFile("src/StarterGui/HUD.rbxm"))[1]
local labels = hud:FindFirstChild("Labels")
local amounts = labels and labels:FindFirstChild("Amounts")
local source = amounts and amounts:FindFirstChild("Clacks")
assert(source, "HUD.Labels.Amounts.Clacks (the toast's look) is missing")
local toast = source:Clone()
toast.Name = "Toast"
toast.Size = UDim2.fromScale(0.45, 0.045)
toast.Position = UDim2.new()
toast.Visible = false
toast:SetAttribute("UITemplate", "Toast")
toast.Parent = gui

Kit.save(gui)
