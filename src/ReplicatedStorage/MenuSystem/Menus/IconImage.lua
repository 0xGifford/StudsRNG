--!strict
--[[
	ReplicatedStorage/MenuSystem/Menus/IconImage

	An image that shows a named icon.

		Icon (ImageLabel)   Icon = "Clacks"

	ATTRIBUTES
		Icon   string   a name in MenuSystem Config.Icons ("Clacks", "Luck"...),
		                or an asset id, or an emoji; the marker
	An asset shows as the image. An emoji hides the image and shows in a
	TextLabel child named "Emoji" (a copy of Templates.Emoji when there's
	none yet).

	API
		IconImage.Start()
		IconImage.Set(image, { Icon = "Spins" })
]]

local Players = game:GetService("Players")

local Component = require(script.Parent.Component)
local Config = require(script.Parent.Parent.Config)

local function emojiLabel(image: GuiObject): TextLabel?
	local existing = image:FindFirstChild("Emoji")
	if existing and existing:IsA("TextLabel") then
		return existing
	end
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local templates = playerGui and playerGui:FindFirstChild("Templates")
	local template = templates and templates:FindFirstChild("Emoji")
	if not (template and template:IsA("TextLabel")) then
		warn("[IconImage] StarterGui.Templates.Emoji is missing (needed to show emoji icons)")
		return nil
	end
	local label = template:Clone()
	label.Name = "Emoji"
	label.Visible = true
	label.ZIndex = image.ZIndex + 1
	label.Parent = image
	return label
end

local function render(image: ImageLabel)
	local name = image:GetAttribute("Icon")
	if type(name) ~= "string" then return end
	local icon = (Config.Icons :: { [string]: string })[name] or name
	local emoji = image:FindFirstChild("Emoji")
	if icon == "" or string.find(icon, "^rbxasset") or string.find(icon, "^rbxthumb") then
		image.Image = icon
		image.ImageTransparency = 0
		if emoji then emoji:Destroy() end
		return
	end
	image.ImageTransparency = 1
	local label = emojiLabel(image)
	if label then
		label.Text = icon
	end
end

return Component.new({
	Marker = "Icon",
	Class = "ImageLabel",
	Render = render,
})
