--!strict
-- ModuleScript -> ReplicatedStorage/MenuSystem/Menus/Focus
--
-- Gamepad focus for menus. MenuController calls Enter when a menu opens and
-- Leave when it closes.
--
--   Enter   traps directional navigation inside the panel (SelectionGroup,
--           Stop on every edge), remembers what was selected underneath,
--           and — only while the player's preferred input is a gamepad —
--           selects the menu's first safe control once it is rendered.
--   Leave   gives the selection back to what was selected before, or
--           clears it, so focus never sits on a closed panel.
--
-- First safe control: a GuiButton with MenuFocus = true wins. Otherwise the
-- top-most, then left-most, visible on-screen button of the panel, skipping
-- the close button (MenuAction = "close") and anything marked
-- MenuDestructive = true.

local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Focus = {}

local previous: { [GuiObject]: GuiObject? } = {} -- panel -> selection before it opened

function Focus.UsesGamepad(): boolean
	local ok, value = pcall(function()
		return (UserInputService :: any).PreferredInput
	end)
	if ok and value then
		return value.Name == "Gamepad" or value.Name == "MicroGamepad"
	end
	return UserInputService.GamepadEnabled and not UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- Visible all the way up to the panel, and actually inside it (pages of a
-- UIPageLayout stay Visible while parked off to the side).
local function reachable(object: GuiObject, panel: GuiObject): boolean
	local node: Instance? = object
	while node and node ~= panel do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	local p, s = object.AbsolutePosition, object.AbsoluteSize
	local pp, ps = panel.AbsolutePosition, panel.AbsoluteSize
	if s.X < 2 or s.Y < 2 then
		return false
	end
	local cx, cy = p.X + s.X / 2, p.Y + s.Y / 2
	return cx >= pp.X and cx <= pp.X + ps.X and cy >= pp.Y and cy <= pp.Y + ps.Y
end

function Focus.FirstControl(panel: GuiObject): GuiObject?
	local best: GuiObject? = nil
	for _, d in panel:GetDescendants() do
		if not d:IsA("GuiButton") or not d.Selectable then
			continue
		end
		if d:GetAttribute("MenuFocus") == true and reachable(d, panel) then
			return d
		end
		if d:GetAttribute("MenuAction") == "close" or d:GetAttribute("MenuDestructive") == true then
			continue
		end
		if not reachable(d, panel) then
			continue
		end
		if best == nil then
			best = d
		else
			local a, b = d.AbsolutePosition, (best :: GuiObject).AbsolutePosition
			if a.Y < b.Y - 4 or (math.abs(a.Y - b.Y) <= 4 and a.X < b.X) then
				best = d
			end
		end
	end
	return best
end

local function trap(panel: GuiObject)
	panel.SelectionGroup = true
	panel.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
end

--- Selects the panel's first safe control if the player is on a gamepad and
--- nothing inside the panel is selected yet.
function Focus.Select(panel: GuiObject)
	task.spawn(function()
		-- selection needs the opened panel rendered and laid out
		RunService.RenderStepped:Wait()
		RunService.RenderStepped:Wait()
		if not panel.Parent or not Focus.UsesGamepad() then
			return
		end
		local gui = panel:FindFirstAncestorWhichIsA("ScreenGui")
		if gui and not gui.Enabled then
			return
		end
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(panel) then
			return
		end
		local target = Focus.FirstControl(panel)
		if target then
			GuiService.SelectedObject = target
		end
	end)
end

function Focus.Enter(panel: GuiObject)
	trap(panel)
	local selected = GuiService.SelectedObject
	previous[panel] = if selected and not selected:IsDescendantOf(panel) then selected else nil
	Focus.Select(panel)
end

function Focus.Leave(panel: GuiObject)
	local before = previous[panel]
	previous[panel] = nil
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(panel) then
		if before and before.Parent and before.Visible and before:IsDescendantOf(game) then
			GuiService.SelectedObject = before
		else
			GuiService.SelectedObject = nil
		end
	end
end

return Focus
