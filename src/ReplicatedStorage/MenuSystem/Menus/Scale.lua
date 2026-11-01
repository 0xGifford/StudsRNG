--!nonstrict
--[[
	ReplicatedStorage/MenuSystem/Menus/Scale

	Fits fixed-size menus onto any screen without touching their layout.

	Your panels are authored in pixels (800 x 450). Rather than reflow them per
	device, each one is wrapped in a ScaleRoot frame carrying a UIScale, and that
	scale is set so the panel fits the viewport with a margin. Everything inside
	shrinks together — text, padding, icons, spacing — so a phone sees exactly
	the layout you designed, smaller.

	WHY A WRAPPER, NOT THE PANEL ITSELF
	Menu.new already puts a UIScale on the panel and animates it 0 -> 1 to open.
	Roblox applies only ONE UIScale per object, so a second would be ignored.
	Nested ones multiply, so the wrapper holds the responsive scale and the panel
	keeps its open animation: a panel opening on a phone plays 0 -> 1 inside a
	root already at 0.55.

	AUTOMATIC
	Every MenuSystem menu is scaled, using its panel's authored pixel size as the
	design size. Nothing needs marking.

	ATTRIBUTES — on the menu's ScreenGui or its panel
		Scale         false    opt this menu out entirely
		ScaleDesign   Vector2  design size, if the panel is not sized in pixels
		ScaleMin      number   never shrink below this
		ScaleMax      number   never grow above this (1 = never bigger than authored)
		ScaleMargin   number   pixels to keep clear left and right of the panel
		                       (room for a side tab column); top and bottom
		                       keep the device margin
		ScaleMinHeight number  design height the panel may shrink to on a
		                       short screen. Its body must flex (scroll areas
		                       sized in scale) — the window gets shorter at a
		                       larger scale instead of uniformly tiny.

	ANYTHING ELSE
		ScaleTarget = true on any fixed-size GuiObject — a HUD hotbar, say —
		scales it the same way.

	WHOLE OVERLAYS (death screen, duel HUD, notifications...)
		ScaleScreen = Vector2(960, 540) on a ScreenGui that is not a menu.
		Below that design resolution the whole overlay shrinks to fit; at or
		above it nothing changes (never scaled up).

		Its children are moved into one "ScreenFit" frame sized 1/s of the
		screen with a UIScale of s, so after scaling it covers the screen
		exactly. Scale positions and every offset animation keep working in
		the same coordinate space, and nothing is reparented away from the
		ScreenGui's descendants, so lookups by role/attribute still find them.
		Children marked ScaleScreen = false (full-screen shades and curtains)
		stay put and keep covering the real screen.

		Code converting REAL pixels (AbsoluteSize, ViewportSize) into offsets
		inside such a gui divides by Scale.ScreenFactor(instance).

	Written back: DeviceClass and MenuScale on each scaled root, so styling or
	other code can react.

	API
		Scale.Device() -> "Phone" | "Tablet" | "Desktop" | "Console"
		Scale.Factor() -> number      the scale currently applied
		Scale.Changed:Connect(function(device, factor) end)
		Scale.Refresh()
		Scale.ScreenFactor(instance) -> number   the ScaleScreen factor over it
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Signal = require(script.Parent.Parent.Core.Signal)

local Scale = {}

Scale.Changed = Signal.new() -- (device, factor)

--- Per device. Margin is the breathing room kept around a panel; a phone gets
--- less because every pixel spent on margin is taken off the panel itself.
Scale.DEVICES = {
	Desktop = { Margin = 40, Min = 0.6, Max = 1.18 }, -- Stud UI MAX_SCALE for large monitors
	Console = { Margin = 64, Min = 0.6, Max = 1.18 }, -- TV overscan
	Tablet = { Margin = 28, Min = 0.5, Max = 1 },
	Phone = { Margin = 10, Min = 0.35, Max = 1 },
}

--- A touch screen this narrow is treated as a phone. Roblox reports pixels,
--- not inches, so this is the honest limit of what can be detected.
Scale.PHONE_MAX_SIDE = 500

--- A window with ScaleMinHeight starts trading height for scale once the
--- whole window would fit only below this factor.
Scale.FLEX_BELOW = 0.85

local roots: { [Instance]: { panel: GuiObject, design: Vector2 } } = {}
local screens: { [ScreenGui]: { fit: Frame, scale: UIScale, design: Vector2 } } = {}
local watchedScreens: { [Instance]: boolean } = {}
local currentDevice = "Desktop"
local currentFactor = 1
local started = false

local camera = Workspace.CurrentCamera

-- ---------------------------------------------------------------- device

-- The player's primary input. TouchEnabled alone is a capability (touch
-- laptops report it), so it is only the fallback.
local function preferredInput(): string
	local ok, value = pcall(function()
		return (UserInputService :: any).PreferredInput
	end)
	if ok and value then
		return value.Name
	end
	return (UserInputService.TouchEnabled and not UserInputService.MouseEnabled) and "Touch" or "KeyboardAndMouse"
end

function Scale.Device(): string
	if not camera then
		return "Desktop"
	end
	local input = preferredInput()
	if input == "Gamepad" or input == "MicroGamepad" then
		return "Console"
	end
	if input ~= "Touch" then
		return "Desktop"
	end
	local viewport = camera.ViewportSize
	return math.min(viewport.X, viewport.Y) <= Scale.PHONE_MAX_SIDE and "Phone" or "Tablet"
end

function Scale.Factor(): number
	return currentFactor
end

local function inherit(instance: Instance, attribute: string, default: any): any
	local node: Instance? = instance
	while node do
		local value = node:GetAttribute(attribute)
		if value ~= nil then
			return value
		end
		node = node.Parent
	end
	return default
end

-- ---------------------------------------------------------------- roots

--- The frame that carries the responsive scale, created between the panel and
--- its parent. Runtime only — your Studio tree is untouched.
---
--- The wrapper TAKES OVER the panel's geometry — size, position and anchor —
--- and the panel fills it. That is the whole trick: a UIScale shrinks an element
--- about its ANCHOR POINT, so the wrapper must be anchored where the panel was.
--- A full-screen wrapper at anchor (0, 0) pivots on the top-left of the screen,
--- and a centred panel visibly slides towards that corner as the scale drops —
--- fine at 1.0 on desktop, badly wrong at 0.49 on a phone.
---
--- Inheriting the anchor also means a panel pinned somewhere else stays pinned:
--- a hotbar anchored (0.5, 1) shrinks towards the bottom edge, not the middle.
local function rootFor(panel: GuiObject): GuiObject?
	local parent = panel.Parent
	if not parent then
		return nil
	end
	if parent:IsA("GuiObject") and parent.Name == "ScaleRoot" then
		return parent
	end

	local root = Instance.new("Frame")
	root.Name = "ScaleRoot"
	root.Size = panel.Size
	root.Position = panel.Position
	root.AnchorPoint = panel.AnchorPoint
	root.LayoutOrder = panel.LayoutOrder
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	-- Must not eat clicks meant for whatever sits behind the menu.
	root.Active = false
	root.ZIndex = panel.ZIndex
	root.Parent = parent

	panel.Parent = root

	-- The panel now fills the wrapper. Kept anchored at its centre so Menu's
	-- open animation still grows from the middle rather than a corner.
	panel.Size = UDim2.fromScale(1, 1)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)

	-- Menu.findPanel takes the first GuiObject child when nothing is marked —
	-- which would now be this wrapper. Marking the real panel keeps Menu
	-- animating the panel, including for menus bound after this runs.
	panel:SetAttribute("MenuPanel", true)

	return root
end

local function scaleObject(root: GuiObject): UIScale
	local existing = root:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "ResponsiveScale"
	scale.Parent = root
	return scale
end

--- The size the panel was designed at: its authored pixel size, or an explicit
--- ScaleDesign for a panel sized in scale rather than offsets.
local function designSizeOf(panel: GuiObject): Vector2?
	local declared = inherit(panel, "ScaleDesign", nil)
	if typeof(declared) == "Vector2" and declared.X > 0 and declared.Y > 0 then
		return declared
	end

	local size = panel.Size
	if size.X.Offset > 0 and size.Y.Offset > 0 then
		return Vector2.new(size.X.Offset, size.Y.Offset)
	end
	return nil
end

function Scale.Add(panel: GuiObject)
	if inherit(panel, "Scale", true) == false then
		return
	end

	-- Already wrapped by an earlier pass: its design size is stored on the root,
	-- and the panel itself now reads 1,1 scale.
	local existing = panel.Parent
	if existing and existing:IsA("GuiObject") and existing.Name == "ScaleRoot" and roots[existing] then
		return
	end

	-- Read BEFORE wrapping: rootFor rewrites the panel's size to fill the root,
	-- so the authored pixel size is only available up to this point.
	local design = designSizeOf(panel)
	if not design then
		warn(("[Scale] %s is not sized in pixels; set a ScaleDesign Vector2 to scale it")
			:format(panel:GetFullName()))
		return
	end

	local root = rootFor(panel)
	if not root or roots[root] then
		return
	end

	roots[root] = { panel = panel, design = design }

	-- The ScreenGui's own area is what the panel must fit (it already has
	-- the topbar, notch and other insets taken off); it changes with them.
	local screen = root:FindFirstAncestorWhichIsA("ScreenGui")
	if screen and not watchedScreens[screen] then
		watchedScreens[screen] = true
		screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(Scale.Refresh)
		screen.Destroying:Connect(function()
			watchedScreens[screen] = nil
		end)
	end
	Scale.Refresh()
end

-- ---------------------------------------------------------------- whole overlays

local function moveIntoFit(screen: ScreenGui, fit: Frame, child: Instance)
	if child == fit or not child:IsA("GuiObject") or child:GetAttribute("ScaleScreen") == false then
		return
	end
	child.Parent = fit
end

function Scale.AddScreen(screen: ScreenGui)
	if screens[screen] then
		return
	end
	local design = screen:GetAttribute("ScaleScreen")
	if typeof(design) ~= "Vector2" or design.X <= 0 or design.Y <= 0 then
		return
	end

	local fit = Instance.new("Frame")
	fit.Name = "ScreenFit"
	fit.BackgroundTransparency = 1
	fit.BorderSizePixel = 0
	fit.Size = UDim2.fromScale(1, 1)
	-- Must not eat clicks meant for the world behind the overlay.
	fit.Active = false
	fit.Parent = screen
	local scale = Instance.new("UIScale")
	scale.Name = "ScreenScale"
	scale.Parent = fit

	for _, child in screen:GetChildren() do
		moveIntoFit(screen, fit, child)
	end
	-- Anything a controller adds at runtime joins it, once it has settled.
	screen.ChildAdded:Connect(function(child)
		task.defer(function()
			if child.Parent == screen then
				moveIntoFit(screen, fit, child)
			end
		end)
	end)

	screens[screen] = { fit = fit, scale = scale, design = design }
	if not watchedScreens[screen] then
		watchedScreens[screen] = true
		screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(Scale.Refresh)
		screen.Destroying:Connect(function()
			watchedScreens[screen] = nil
			screens[screen] = nil
		end)
	end
	Scale.Refresh()
end

--- The ScaleScreen factor applying to an instance (1 when none does). Real
--- pixels divided by this are offsets inside the overlay.
function Scale.ScreenFactor(instance: Instance): number
	local screen = instance:IsA("ScreenGui") and instance or instance:FindFirstAncestorWhichIsA("ScreenGui")
	local entry = screen and screens[screen :: ScreenGui]
	return entry and entry.scale.Scale or 1
end

-- ---------------------------------------------------------------- applying

local function usableViewport(root: GuiObject): Vector2
	-- The ScreenGui's area honours its ScreenInsets (topbar, notch, home
	-- bar), so a panel fitted to it never ends up under the core UI.
	local screen = root:FindFirstAncestorWhichIsA("ScreenGui")
	if screen and screen.AbsoluteSize.X > 0 and screen.AbsoluteSize.Y > 0 then
		return screen.AbsoluteSize
	end

	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	return Vector2.new(viewport.X, viewport.Y - inset.Y)
end

function Scale.Refresh()
	local device = Scale.Device()
	local settings = Scale.DEVICES[device] or Scale.DEVICES.Desktop
	local applied = 1

	for root, entry in roots do
		if not root.Parent or not entry.panel.Parent then
			roots[root] = nil
			continue
		end

		local marginX = math.max(inherit(entry.panel, "ScaleMargin", settings.Margin), settings.Margin)
		local marginY = settings.Margin
		local minScale = inherit(entry.panel, "ScaleMin", settings.Min)
		local maxScale = inherit(entry.panel, "ScaleMax", settings.Max)

		local viewport = usableViewport(root)
		local available = Vector2.new(
			math.max(viewport.X - marginX * 2, 1),
			math.max(viewport.Y - marginY * 2, 1)
		)

		-- The smaller of the two fits: a panel that fits on width but overflows
		-- on height has not fitted.
		local design = entry.design
		local factor = math.min(available.X / design.X, available.Y / design.Y)
		factor = math.clamp(factor, minScale, maxScale)

		-- Short screen: a window with a flexible body (ScaleMinHeight) keeps a
		-- readable scale and gives up height instead of shrinking every glyph.
		-- Only when the full window would get small, and never past 1 while
		-- shortened, so roomy screens still see the whole authored window.
		local minHeight = inherit(entry.panel, "ScaleMinHeight", nil)
		if type(minHeight) == "number" and minHeight < design.Y then
			local height = design.Y
			if factor < Scale.FLEX_BELOW then
				local flexed = math.min(available.X / design.X, available.Y / minHeight, 1, maxScale)
				factor = math.max(factor, math.clamp(flexed, minScale, maxScale))
				height = math.clamp(available.Y / factor, minHeight, design.Y)
			end
			root.Size = UDim2.fromOffset(design.X, math.floor(height + 0.5))
		end

		scaleObject(root).Scale = factor
		root:SetAttribute("MenuScale", factor)
		root:SetAttribute("DeviceClass", device)
		applied = factor
	end

	for screen, entry in screens do
		if not screen.Parent then
			screens[screen] = nil
			continue
		end
		local size = screen.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			continue
		end
		-- Never above 1: an overlay is only ever shrunk to fit, not enlarged.
		local factor = math.clamp(math.min(size.X / entry.design.X, size.Y / entry.design.Y), 0.35, 1)
		entry.scale.Scale = factor
		entry.fit.Size = UDim2.fromScale(1 / factor, 1 / factor)
		screen:SetAttribute("ScreenScale", factor)
	end

	if device ~= currentDevice or math.abs(applied - currentFactor) > 0.001 then
		currentDevice = device
		currentFactor = applied
		Scale.Changed:Fire(device, applied)
	end
end

-- ---------------------------------------------------------------- start

function Scale.Start()
	if started then
		return
	end
	started = true

	camera = Workspace.CurrentCamera
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local function consider(instance: Instance)
		if instance:IsA("ScreenGui") and typeof(instance:GetAttribute("ScaleScreen")) == "Vector2" then
			Scale.AddScreen(instance)
			return
		end
		if not instance:IsA("GuiObject") then
			return
		end
		-- A menu's panel, or anything explicitly marked.
		if instance:GetAttribute("MenuPanel") == true or instance:GetAttribute("ScaleTarget") == true then
			Scale.Add(instance)
		end
	end

	for _, descendant in playerGui:GetDescendants() do
		consider(descendant)
	end

	playerGui.DescendantAdded:Connect(function(descendant)
		task.defer(consider, descendant)
	end)

	-- Rotating a phone, resizing a window, or Studio's device emulator.
	local function watchCamera()
		camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(Scale.Refresh)
		end
	end
	watchCamera()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)

	-- Plugging in a keyboard or controller, or a device reporting touch late.
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(Scale.Refresh)
	UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(Scale.Refresh)
	pcall(function()
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(Scale.Refresh)
	end)

	-- StarterGui replicates over several frames, so a single pass at startup can
	-- miss panels entirely.
	task.spawn(function()
		for _ = 1, 5 do
			task.wait(0.2)
			for _, descendant in playerGui:GetDescendants() do
				consider(descendant)
			end
		end
		Scale.Refresh()
	end)

	Scale.Refresh()
end

return Scale
