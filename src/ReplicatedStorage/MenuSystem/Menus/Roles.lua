--!strict
--[[
	ReplicatedStorage/MenuSystem/Menus/Roles

	Finds the pieces of a StarterGui-built UI by role attribute, so they can
	be renamed, restyled and moved around in Studio without touching code
	(the same idea as AdminRole / AnnouncementRole).

		local gui = Roles.gui("Offers")                    -- PlayerGui.Offers (waits)
		local card = Roles.get(gui, "OfferRole", "Card")    -- errors if missing
		local close = Roles.find(gui, "OfferRole", "Close") -- nil if missing
		local row = Roles.template(gui, "QuestRow")         -- a hidden template's copy

	Templates: anything with UITemplate = "<name>" is a template: it's hidden
	in place, and Roles.template returns a visible copy (attribute cleared).
	Copies keep every other attribute, so components (StudView, ZoneView,
	ProgressBar...) inside a template draw themselves in each copy.
]]

local Players = game:GetService("Players")

local Roles = {}

local player = Players.LocalPlayer

-- A ScreenGui from StarterGui, once it has replicated into PlayerGui.
function Roles.gui(name: string, timeout: number?): ScreenGui
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(name, timeout or 30)
	assert(gui and gui:IsA("ScreenGui"), `PlayerGui.{name} is missing (it lives in StarterGui)`)
	return gui :: ScreenGui
end

function Roles.find(root: Instance, attribute: string, value: string): any
	if root:GetAttribute(attribute) == value then
		return root
	end
	for _, d in root:GetDescendants() do
		if d:GetAttribute(attribute) == value then
			return d
		end
	end
	return nil
end

function Roles.get(root: Instance, attribute: string, value: string): any
	local found = Roles.find(root, attribute, value)
	assert(found, `{root:GetFullName()} has nothing with {attribute} = "{value}"`)
	return found
end

-- Every descendant carrying the attribute, by its value.
function Roles.all(root: Instance, attribute: string): { [string]: any }
	local found = {}
	for _, d in root:GetDescendants() do
		local value = d:GetAttribute(attribute)
		if type(value) == "string" and not found[value] then
			found[value] = d
		end
	end
	return found
end

local templates: { [Instance]: { [string]: Instance } } = setmetatable({}, { __mode = "k" }) :: any

-- Studs added to a copied BillboardGui / SurfaceGui's MaxDistance (0 by
-- default). MaxDistance is measured from the camera: a game whose camera
-- sits far from the player sets this to that distance.
Roles.distanceBonus = 0

-- A visible copy of the template UITemplate = name under root.
function Roles.template(root: Instance, name: string): any
	local cache = templates[root]
	if not cache then
		cache = {}
		templates[root] = cache
	end
	local template = cache[name]
	if not template or not template.Parent then
		template = Roles.find(root, "UITemplate", name)
		assert(template, `{root:GetFullName()} has no template UITemplate = "{name}"`)
		-- BillboardGui / SurfaceGui templates have no Visible (they live in a
		-- disabled ScreenGui, where they never draw in 3D anyway).
		if template:IsA("GuiObject") then
			template.Visible = false
		end
		cache[name] = template
	end
	local copy = (template :: Instance):Clone()
	copy:SetAttribute("UITemplate", nil)
	if copy:IsA("GuiObject") then
		copy.Visible = true
	elseif (copy:IsA("BillboardGui") or copy:IsA("SurfaceGui")) and copy.MaxDistance > 0 then
		copy.MaxDistance += Roles.distanceBonus
	end
	return copy
end

return Roles
