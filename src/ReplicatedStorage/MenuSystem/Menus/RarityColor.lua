--!strict
--[[
	ReplicatedStorage/MenuSystem/Menus/RarityColor

	Tints anything by a stud rarity (Shared Config.Rarities.Colors).

		Backdrop (Frame)   Rarity = "Legendary"

	ATTRIBUTES
		Rarity       string   Common, Uncommon, Rare, Epic, Legendary, Mythic,
		                      Secret; "" = not known yet (RarityHidden colour).
		                      The marker.
		RarityMode   string   what it colours:
		                      "Gradient"   (default) its UIGradient: the rarity
		                                   colour fading to RarityDark
		                      "Background" BackgroundColor3
		                      "Stroke"     its UIStroke
		                      "Text"       TextColor3
		                      "Image"      ImageColor3
		RarityDark   Color3   the gradient's far colour, default (24, 25, 32)
		RarityHidden Color3   the colour while Rarity is "", default (60, 62, 76)
		RarityLight  number   0 to 1: lighten the rarity colour (0)
	Secret's own colour is near black, so it shows white here.

	API
		RarityColor.Start()
		RarityColor.Set(frame, { Rarity = "Epic" })
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Component = require(script.Parent.Component)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config)

local WHITE = Color3.new(1, 1, 1)

local function colorOf(host: Instance): Color3
	local rarity = host:GetAttribute("Rarity")
	if type(rarity) ~= "string" or rarity == "" then
		local hidden = host:GetAttribute("RarityHidden")
		return if typeof(hidden) == "Color3" then hidden else Color3.fromRGB(60, 62, 76)
	end
	local color = if rarity == "Secret" then WHITE else GameConfig.Rarities.Colors[rarity] or WHITE
	local light = host:GetAttribute("RarityLight")
	if typeof(light) == "number" and light > 0 then
		color = color:Lerp(WHITE, math.clamp(light, 0, 1))
	end
	return color
end

local function render(host: GuiObject)
	local color = colorOf(host)
	local mode = host:GetAttribute("RarityMode")
	if mode == "Background" then
		host.BackgroundColor3 = color
	elseif mode == "Stroke" then
		local stroke = host:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Color = color end
	elseif mode == "Text" then
		if host:IsA("TextLabel") or host:IsA("TextButton") or host:IsA("TextBox") then
			host.TextColor3 = color
		end
	elseif mode == "Image" then
		if host:IsA("ImageLabel") or host:IsA("ImageButton") then
			host.ImageColor3 = color
		end
	else
		local gradient = host:FindFirstChildOfClass("UIGradient")
		if not gradient then
			host.BackgroundColor3 = color
			return
		end
		local dark = host:GetAttribute("RarityDark")
		gradient.Color = ColorSequence.new(color, if typeof(dark) == "Color3" then dark else Color3.fromRGB(24, 25, 32))
	end
end

return Component.new({
	Marker = "Rarity",
	Watch = { "RarityMode", "RarityDark", "RarityHidden", "RarityLight" },
	Class = "GuiObject",
	Render = render,
})
