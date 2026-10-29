--[[

HudLayout
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/HudLayout

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Arranges the kit HUD (StarterGui.HUD) Slime RNG style at runtime, so the
-- Studio file stays the source of truth for how each button looks:
--   bottom centre   BACKPACK · ROLL · UPGRADE (and AUTO)
--   right column    SHOP · REBIRTH · INDEX · TELEPORT
--   left column     everything else (quests, rewards, wheel, badges, pass...)
--   left middle     Clacks and the multiplier (where the kit puts them)
-- Buttons added later (UI/SideButtons) land in the left column.

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local Interface = require(UI.Interface)

local HudLayout = {}

-- Right column, top to bottom (kit side-button names).
local RIGHT = { "Store", "Rebirth", "Index", "Zones" }
local LABELS = { Store = "SHOP", Rebirth = "REBIRTH", Index = "INDEX", Zones = "TELEPORT", Upgrades = "UPGRADE" }

local function verticalList(frame: Frame, padding: number)
	local layout = frame:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(padding, 0)
	layout.Wraps = false
	layout.Parent = frame
end

local function square(frame: GuiObject, height: number)
	frame.Size = UDim2.fromScale(1, height)
	local ratio = frame:FindFirstChildOfClass("UIAspectRatioConstraint") or Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.DominantAxis = Enum.DominantAxis.Height
	ratio.Parent = frame
end

function HudLayout.start()
	Interface.setup()
	local hud = Interface.HUD
	local side = hud:WaitForChild("Side")
	local buttons = side:WaitForChild("Buttons") :: Frame
	local bar = hud:WaitForChild("Top"):WaitForChild("Frame") :: Frame

	-- Right column.
	buttons.AnchorPoint = Vector2.new(1, 0.5)
	buttons.Position = UDim2.new(1, -8, 0.52, 0)
	buttons.Size = UDim2.fromScale(0.08, 0.62)
	local ratio = buttons:FindFirstChildOfClass("UIAspectRatioConstraint")
	if ratio then
		ratio:Destroy()
	end
	verticalList(buttons, 0.025)

	-- Left column for the rest.
	local left = Instance.new("Frame")
	left.Name = "LeftButtons"
	left.BackgroundTransparency = 1
	left.AnchorPoint = Vector2.new(0, 0)
	left.Position = UDim2.new(0, 8, 0.56, 0)
	left.Size = UDim2.fromScale(0.13, 0.3)
	left.Parent = side
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromScale(0.46, 0.46)
	grid.CellPadding = UDim2.fromScale(0.04, 0.04)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirectionMaxCells = 2
	grid.Parent = left
	local leftRatio = Instance.new("UIAspectRatioConstraint")
	leftRatio.AspectRatio = 1
	leftRatio.Parent = left

	local function place(child: Instance)
		if not child:IsA("Frame") or not child:FindFirstChild("Button") then return end
		local order = table.find(RIGHT, child.Name)
		if order then
			child.LayoutOrder = order
			square(child, 0.22)
			if LABELS[child.Name] then
				Interface.setText(child, LABELS[child.Name])
			end
		elseif child.Name ~= "Upgrades" then
			child.Parent = left
		end
	end

	-- UPGRADE joins the bottom bar, right of ROLL.
	local upgrades = buttons:FindFirstChild("Upgrades")
	if upgrades and upgrades:IsA("Frame") then
		upgrades.Parent = bar
		upgrades.Size = UDim2.fromScale(0.12, 1.2)
		local upgradeRatio = upgrades:FindFirstChildOfClass("UIAspectRatioConstraint")
		if upgradeRatio then
			upgradeRatio.DominantAxis = Enum.DominantAxis.Height
		end
		Interface.setText(upgrades, LABELS.Upgrades)
	end

	for _, child in buttons:GetChildren() do
		place(child)
	end
	buttons.ChildAdded:Connect(function(child)
		task.defer(place, child)
	end)

	-- Bottom bar: BACKPACK · ROLL · UPGRADE · AUTO.
	local order = { Studs = 1, Roll = 2, Upgrades = 3, Auto = 4 }
	for name, index in order do
		local frame = bar:FindFirstChild(name)
		if frame and frame:IsA("GuiObject") then
			frame.LayoutOrder = index
		end
	end
	local listLayout = bar:FindFirstChildOfClass("UIListLayout")
	if listLayout then
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		listLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	end
	local studs = bar:FindFirstChild("Studs")
	if studs then
		Interface.setText(studs, "Backpack")
	end
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.fromScale(0.5, 0.975)
end

return HudLayout
