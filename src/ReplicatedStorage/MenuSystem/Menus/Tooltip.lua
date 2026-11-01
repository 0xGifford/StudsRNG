--!strict
-- ModuleScript -> ReplicatedStorage/MenuSystem/Menus/Tooltip
--
-- Hover tooltips built from a template you design in Studio.
--
-- Mark the FRAME you designed with TooltipTemplate = true, not the
-- ScreenGui around it. It gets cloned into a private layer; the original's
-- ScreenGui is disabled so the design stays editable.
--
-- Content fields are filled by name, so what a tooltip can show is a
-- Studio decision rather than a code change:
--
--   TooltipTitle        -> a label named Title, or TitleContainer's labels
--   TooltipDescription  -> Description / DescriptionContainer
--   TooltipIcon         -> Icon / IconContainer
--
-- Add a Cost label to the template and a TooltipCost attribute to a card,
-- and it works with nothing changed here.
--
-- Styling and behaviour:
--
--   TooltipColor        = "40,120,255"  or a Color3
--   TooltipStrokeColor  = "80,160,255"
--   TooltipShadowColor  = "20,60,140"
--   TooltipSide         = "right" | "left" | "top" | "bottom" | "auto"
--   TooltipDelay        = 0.4
--   TooltipGroup        = false          bind only this instance

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MenuSystem = script.Parent.Parent
local Config = require(MenuSystem.Config)

local ATTR = Config.Attributes
local TIP = Config.Tooltip

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Hover doesn't exist on touch. Showing on tap would cover the thing you
-- just pressed, which is worse than showing nothing.
local TOUCH_ONLY = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

local Tooltip = {}

--------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------

local layer: ScreenGui?
local panel: GuiObject?
local scale: UIScale?
local template: GuiObject?

local current: GuiObject? = nil
local pending: thread? = nil
local bound: { [GuiObject]: boolean } = {}

--------------------------------------------------------------------
-- BUILD
--------------------------------------------------------------------

local function findTemplate(): GuiObject?
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:GetAttribute(ATTR.TooltipTemplate) == true then
			if descendant:IsA("GuiObject") then
				return descendant
			end

			-- Marked on the ScreenGui by mistake: take its first frame
			-- rather than failing silently forever.
			if descendant:IsA("ScreenGui") then
				for _, child in ipairs(descendant:GetChildren()) do
					if child:IsA("GuiObject") then
						warn(("[Tooltip] %s is marked on the ScreenGui; using %s")
							:format(ATTR.TooltipTemplate, child.Name))
						return child
					end
				end
			end
		end
	end

	return nil
end

local function build(): boolean
	if panel then return true end

	local source = template or findTemplate()
	if not source then return false end
	template = source

	-- Hide the original rather than destroy it: it's your design, and you
	-- may want to keep editing it in Studio.
	local sourceGui = source:FindFirstAncestorWhichIsA("ScreenGui")
	if sourceGui and sourceGui:GetAttribute(ATTR.TooltipTemplateGui) ~= false then
		sourceGui.Enabled = false
	end

	local newLayer = Instance.new("ScreenGui")
	newLayer.Name = "TooltipLayer"
	newLayer.ResetOnSpawn = false
	newLayer.IgnoreGuiInset = true
	newLayer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	newLayer.DisplayOrder = TIP.DisplayOrder
	newLayer.Parent = playerGui
	layer = newLayer

	local clone = source:Clone()
	clone.Name = "Tooltip"
	clone.AnchorPoint = Vector2.new(0, 0)
	clone.Visible = false
	clone.Parent = newLayer
	panel = clone

	local existingScale = clone:FindFirstChildOfClass("UIScale")
	if existingScale then
		scale = existingScale
	else
		local created = Instance.new("UIScale")
		created.Parent = clone
		scale = created
	end

	-- Nothing inside should take the pointer, or moving toward the tooltip
	-- counts as leaving the thing that opened it and it flickers.
	clone.Active = false
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("GuiObject") then d.Active = false end
	end

	if Config.Behaviour.Verbose then
		print("[Tooltip] built from " .. source:GetFullName())
		Tooltip.Describe()
	end

	return true
end

--------------------------------------------------------------------
-- INSPECTION
--------------------------------------------------------------------

-- Prints what the current template can show and what it can be styled
-- with, so a field that never appears is obvious without guesswork.
--
--   require(...Tooltip).Describe()
function Tooltip.Describe()
	if not panel then
		warn("[Tooltip] nothing built yet")
		return
	end

	local root = panel:FindFirstChild(TIP.StyleRootName, true) or panel

	print("[Tooltip] template: " .. panel:GetFullName())

	local fields: { [string]: { string } } = {}

	for _, d in ipairs(panel:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("ImageLabel") then
			local field = d.Name
			local parent = d.Parent

			if parent and parent:IsA("GuiObject") then
				local stem = parent.Name:match("^(.-)" .. TIP.ContainerSuffix .. "$")
				if stem then field = stem end
			end

			fields[field] = fields[field] or {}
			table.insert(fields[field], d.Name .. " (" .. d.ClassName .. ")")
		end
	end

	local names = {}
	for field in pairs(fields) do table.insert(names, field) end
	table.sort(names)

	for _, field in ipairs(names) do
		print(("    %s%-14s -> %s"):format(
			TIP.Prefix, field, table.concat(fields[field], ", ")))
	end

	local function describeChild(name: string): string
		local child = root:FindFirstChild(name)
		if not child then return "nothing named '" .. name .. "'" end
		return child.Name .. " (" .. child.ClassName .. ")"
	end

	print("    TooltipColor       -> " .. root.Name .. " (" .. root.ClassName .. ")")
	print("    TooltipStrokeColor -> " .. describeChild(TIP.StrokeName))
	print("    TooltipShadowColor -> " .. describeChild(TIP.ShadowName))
end

--------------------------------------------------------------------
-- FIELDS
--------------------------------------------------------------------

-- "TooltipDescription" -> "Description". Everything after the prefix is a
-- field name, except the reserved words that configure behaviour.
local function fieldName(attribute: string): string?
	if attribute:sub(1, #TIP.Prefix) ~= TIP.Prefix then return nil end

	local field = attribute:sub(#TIP.Prefix + 1)
	if field == "" or TIP.Reserved[field] then return nil end
	return field
end

local function isWritable(instance: Instance): boolean
	return instance:IsA("TextLabel")
		or instance:IsA("TextButton")
		or instance:IsA("ImageLabel")
		or instance:IsA("ImageButton")
end

-- Everything a field should write to. Three shapes all work: a label named
-- after the field, a plain frame named after it holding labels, or a
-- "<Field>Container" holding labels — the last being how a text label and
-- its drop shadow usually live together.
local function targetsFor(root: GuiObject, field: string): { GuiObject }
	local targets = {}

	local function collectInside(container: Instance)
		for _, child in ipairs(container:GetDescendants()) do
			if child:IsA("TextLabel") or child:IsA("ImageLabel") then
				table.insert(targets, child)
			end
		end
	end

	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("GuiObject") then
			if d.Name == field then
				if isWritable(d) then
					table.insert(targets, d)
				else
					collectInside(d)
				end

			elseif d.Name == field .. TIP.ContainerSuffix then
				collectInside(d)
			end
		end
	end

	return targets
end

local function writeField(root: GuiObject, field: string, value: any): { GuiObject }
	local targets = targetsFor(root, field)

	local text = tostring(value)
	local empty = text == ""

	for _, target in ipairs(targets) do
		if target:IsA("TextLabel") or target:IsA("TextButton") then
			target.Text = text
		elseif target:IsA("ImageLabel") or target:IsA("ImageButton") then
			target.Image = text
		end

		-- A field with nothing to say shouldn't leave a gap in the layout
		target.Visible = not empty
	end

	return targets
end

--------------------------------------------------------------------
-- COLOUR
--------------------------------------------------------------------

-- Accepts "255,80,40" or a real Color3, so the attribute can be either
-- type in Studio without the caller caring.
local function parseColor(value: any): Color3?
	if typeof(value) == "Color3" then return value end
	if type(value) ~= "string" then return nil end

	local rs, gs, bs = value:match(
		"^%s*(%-?[%d%.]+)%s*,%s*(%-?[%d%.]+)%s*,%s*(%-?[%d%.]+)%s*$")
	if not (rs and gs and bs) then return nil end

	local r, g, b = tonumber(rs), tonumber(gs), tonumber(bs)
	if not (r and g and b) then return nil end

	return Color3.fromRGB(
		math.round(math.clamp(r, 0, 255)),
		math.round(math.clamp(g, 0, 255)),
		math.round(math.clamp(b, 0, 255)))
end

-- Colour properties in preference order. The first one an instance
-- actually has wins, so this works for any class without needing a branch
-- per type: UIStroke, image-based shadows, frames, plugin-made effects.
local COLOUR_PROPERTIES = {
	"Color",             -- UIStroke and most UI modifiers
	"ImageColor3",       -- ImageLabel, ImageButton
	"BackgroundColor3",  -- Frame, TextLabel, TextButton
	"TextColor3",
}

local function tintInstance(instance: Instance, colour: Color3): boolean
	-- A gradient is a sequence, not a colour. Assigning a flat one would
	-- collapse the fade, so shift every keypoint's hue and keep its
	-- brightness — a dark-to-light shadow stays dark-to-light.
	if instance:IsA("UIGradient") then
		local hue, saturation = Color3.toHSV(colour)
		local keypoints = {}

		for _, point in ipairs(instance.Color.Keypoints) do
			local _, _, value = Color3.toHSV(point.Value)
			table.insert(keypoints,
				ColorSequenceKeypoint.new(point.Time, Color3.fromHSV(hue, saturation, value)))
		end

		instance.Color = ColorSequence.new(keypoints)
		return true
	end

	-- Read before writing, and check the value really is a Color3: a class
	-- with an unrelated property of the same name gets skipped rather than
	-- throwing.
	for _, property in ipairs(COLOUR_PROPERTIES) do
		local ok, current = pcall(function()
			return (instance :: any)[property]
		end)

		if ok and typeof(current) == "Color3" then
			local written = pcall(function()
				(instance :: any)[property] = colour
			end)
			if written then return true end
		end
	end

	return false
end

-- The frame carrying the tooltip's own styling. build() renames the clone
-- to "Tooltip", so looking for a child called MainFrame finds nothing when
-- the template WAS the MainFrame, which is the usual case.
local function styleRoot(): GuiObject?
	if not panel then return nil end

	local nested = panel:FindFirstChild(TIP.StyleRootName, true)
	if nested and nested:IsA("GuiObject") then return nested end

	return panel
end

local function applyColours(source: GuiObject)
	local root = styleRoot()
	if not root then return end

	-- Panel
	local main = parseColor(source:GetAttribute(ATTR.TooltipColor))
	if main and not tintInstance(root, main) and Config.Behaviour.Verbose then
		warn(("[Tooltip] %s (%s) has no tintable property")
			:format(root.Name, root.ClassName))
	end

	-- Stroke and shadow are matched by exact name, and only as DIRECT
	-- children of the styled frame. A title's own drop shadow is usually
	-- called "Shadow" and lives deeper in the tree, so a recursive search
	-- or a class check would recolour it along with the panel's.
	local function tintChild(name: string, attribute: string, label: string)
		local colour = parseColor(source:GetAttribute(attribute))
		if not colour then return end

		local child = root:FindFirstChild(name)
		if not child then
			if Config.Behaviour.Verbose then
				warn(("[Tooltip] no child named '%s' under %s for %s")
					:format(name, root.Name, label))
			end
			return
		end

		-- Warned unconditionally: a colour attribute that silently does
		-- nothing is the hardest kind of problem to spot.
		if not tintInstance(child, colour) then
			warn(("[Tooltip] %s is a %s with no writable colour property; %s ignored")
				:format(child.Name, child.ClassName, label))
		end
	end

	tintChild(TIP.StrokeName, ATTR.TooltipStrokeColor, "TooltipStrokeColor")
	tintChild(TIP.ShadowName, ATTR.TooltipShadowColor, "TooltipShadowColor")
end

--------------------------------------------------------------------
-- FILL
--------------------------------------------------------------------

local function fill(source: GuiObject): boolean
	if not panel then return false end

	-- Tracked by instance rather than name, since a container's children
	-- are rarely named after the field they belong to
	local written: { [GuiObject]: boolean } = {}
	local any = false

	for attribute, value in pairs(source:GetAttributes()) do
		local field = fieldName(attribute)
		if field then
			local targets = writeField(panel, field, value)

			if #targets > 0 then
				for _, target in ipairs(targets) do
					written[target] = true
				end
				any = true

			elseif Config.Behaviour.Verbose then
				print(("[Tooltip] nothing named '%s' or '%s%s' in the template")
					:format(field, field, TIP.ContainerSuffix))
			end
		end
	end

	-- Fields the template has but this instance didn't supply are hidden,
	-- or they show whatever the last hover left behind. Only labels some
	-- field could reach are touched, so static decoration survives.
	for _, d in ipairs(panel:GetDescendants()) do
		if (d:IsA("TextLabel") or d:IsA("ImageLabel")) and not written[d] then
			local reachable = fieldName(TIP.Prefix .. d.Name) ~= nil

			local parent = d.Parent
			if not reachable and parent and parent:IsA("GuiObject") then
				local stem = parent.Name:match("^(.-)" .. TIP.ContainerSuffix .. "$")
					or parent.Name
				reachable = fieldName(TIP.Prefix .. stem) ~= nil
			end

			if reachable then d.Visible = false end
		end
	end

	applyColours(source)
	return any
end

--------------------------------------------------------------------
-- PLACEMENT
--------------------------------------------------------------------

-- Tries the requested side, then the opposite, then top and bottom. A
-- tooltip half off-screen is worse than one on the wrong side.
local function place(source: GuiObject)
	if not (panel and layer) then return end

	local viewport = layer.AbsoluteSize
	local size = panel.AbsoluteSize
	local origin = source.AbsolutePosition
	local extent = source.AbsoluteSize

	local requested = source:GetAttribute(ATTR.TooltipSide)
	if type(requested) ~= "string" then requested = TIP.DefaultSide end
	requested = requested:lower()

	local function positionFor(side: string): Vector2
		if side == "left" then
			return Vector2.new(
				origin.X - size.X - TIP.Gap,
				origin.Y + extent.Y / 2 - size.Y / 2)

		elseif side == "top" then
			return Vector2.new(
				origin.X + extent.X / 2 - size.X / 2,
				origin.Y - size.Y - TIP.Gap)

		elseif side == "bottom" then
			return Vector2.new(
				origin.X + extent.X / 2 - size.X / 2,
				origin.Y + extent.Y + TIP.Gap)
		end

		return Vector2.new(
			origin.X + extent.X + TIP.Gap,
			origin.Y + extent.Y / 2 - size.Y / 2)
	end

	local function fits(p: Vector2): boolean
		return p.X >= TIP.Edge
			and p.Y >= TIP.Edge
			and p.X + size.X <= viewport.X - TIP.Edge
			and p.Y + size.Y <= viewport.Y - TIP.Edge
	end

	local OPPOSITE = { right = "left", left = "right", top = "bottom", bottom = "top" }

	local order
	if requested == "auto" then
		order = { "right", "left", "top", "bottom" }
	else
		order = { requested, OPPOSITE[requested] or "left", "top", "bottom" }
	end

	local chosen: Vector2? = nil
	for _, side in ipairs(order) do
		local candidate = positionFor(side)
		if fits(candidate) then
			chosen = candidate
			break
		end
	end

	-- Nothing fitted, so take the first and clamp it on screen
	local final = chosen or positionFor(order[1])
	final = Vector2.new(
		math.clamp(final.X, TIP.Edge, math.max(viewport.X - size.X - TIP.Edge, TIP.Edge)),
		math.clamp(final.Y, TIP.Edge, math.max(viewport.Y - size.Y - TIP.Edge, TIP.Edge)))

	panel.Position = UDim2.fromOffset(math.floor(final.X), math.floor(final.Y))
end

--------------------------------------------------------------------
-- SHOW / HIDE
--------------------------------------------------------------------

function Tooltip.Hide()
	current = nil

	if pending then
		task.cancel(pending)
		pending = nil
	end

	if not (panel and scale) then return end

	TweenService:Create(scale,
		TweenInfo.new(TIP.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = TIP.HiddenScale }
	):Play()

	task.delay(TIP.FadeTime, function()
		if not current and panel then panel.Visible = false end
	end)
end

function Tooltip.Show(source: GuiObject)
	if not build() then
		if Config.Behaviour.Verbose then
			warn("[Tooltip] no frame marked " .. ATTR.TooltipTemplate)
		end
		return
	end
	if not (panel and scale) then return end

	if not fill(source) then return end
	current = source

	panel.Visible = true

	-- One frame for the layout to settle, or an auto-sizing panel is
	-- measured at its previous size and lands in the wrong place
	RunService.Heartbeat:Wait()
	if current ~= source then return end

	place(source)

	scale.Scale = TIP.HiddenScale
	TweenService:Create(scale,
		TweenInfo.new(TIP.FadeTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

--------------------------------------------------------------------
-- BINDING
--------------------------------------------------------------------

local function delayFor(source: GuiObject): number
	local value = source:GetAttribute(ATTR.TooltipDelay)
	return type(value) == "number" and value or TIP.Delay
end

-- A tooltip on a container with interactive children needs both bound, or
-- moving onto the child fires MouseLeave on the parent and it flickers.
local function group(source: GuiObject): { GuiObject }
	local members = { source }

	if source:GetAttribute(ATTR.TooltipGroup) ~= false then
		for _, d in ipairs(source:GetDescendants()) do
			if d:IsA("GuiButton") then table.insert(members, d) end
		end
	end

	return members
end

function Tooltip.Bind(source: GuiObject)
	if bound[source] or TOUCH_ONLY then return end
	bound[source] = true

	local members = group(source)
	local count = 0

	local function enter()
		count += 1
		if current == source then return end

		if pending then task.cancel(pending) end
		pending = task.delay(delayFor(source), function()
			pending = nil
			if count > 0 then Tooltip.Show(source) end
		end)
	end

	local function leave()
		count = math.max(count - 1, 0)

		-- Moving between a container and its child fires leave then enter
		-- in that order, so wait a frame before calling it a real exit
		task.defer(function()
			if count <= 0 then
				if pending then
					task.cancel(pending)
					pending = nil
				end
				if current == source then Tooltip.Hide() end
			end
		end)
	end

	for _, member in ipairs(members) do
		member.MouseEnter:Connect(enter)
		member.MouseLeave:Connect(leave)
	end

	source.Destroying:Connect(function()
		bound[source] = nil
		if current == source then Tooltip.Hide() end
	end)

	-- Attributes changing while hovered update what's on screen, so a card
	-- can rewrite its own tooltip as data comes in
	source.AttributeChanged:Connect(function(name)
		if current ~= source then return end

		if fieldName(name)
			or name == ATTR.TooltipColor
			or name == ATTR.TooltipStrokeColor
			or name == ATTR.TooltipShadowColor
		then
			fill(source)
		end
	end)
end

--------------------------------------------------------------------

local function isTooltipped(instance: Instance): boolean
	if not instance:IsA("GuiObject") then return false end

	for attribute in pairs(instance:GetAttributes()) do
		if fieldName(attribute) then return true end
	end
	return false
end

function Tooltip.Start()
	if TOUCH_ONLY then return end

	-- Built up front so a missing template is reported at startup rather
	-- than the first time someone hovers something
	if not build() and Config.Behaviour.Verbose then
		warn("[Tooltip] no frame marked " .. ATTR.TooltipTemplate .. " yet")
	end

	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if isTooltipped(descendant) then
			Tooltip.Bind(descendant :: GuiObject)
		end
	end

	playerGui.DescendantAdded:Connect(function(instance)
		-- Attributes are usually set a frame after parenting
		task.defer(function()
			if instance.Parent and isTooltipped(instance) then
				Tooltip.Bind(instance :: GuiObject)
			end
		end)
	end)

	-- A menu closing shouldn't leave a tooltip floating over the HUD
	local MenuController = require(script.Parent.MenuController)
	MenuController.Closed:Connect(function()
		Tooltip.Hide()
	end)
end

return Tooltip