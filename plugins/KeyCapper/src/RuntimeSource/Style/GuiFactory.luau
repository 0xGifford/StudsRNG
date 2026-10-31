--!strict
-- Single responsibility: build a key's UI by code.
-- The published mesh is now BARE (no SurfaceGui baked in): it's the
-- plugin/runtime that must build it dynamically at placement time. This
-- module is the single reference for what a key's UI should look like.
--
-- Spec taken as-is from the original prototype (inspected by hand):
-- SurfaceGui Face=Top, CanvasSize 150x150, PixelsPerStud=70.
-- Centered TextLabel, TextScaled, FredokaOne font, black outline.
-- The UIStroke is created DISABLED: it's a lever reserved for the future
-- "GUI customization" phase (see docs/PLAN.md), not enabled here.

local GuiFactory = {}

function GuiFactory.BuildLabel(cap: BasePart, text: string, maxDistance: number?): SurfaceGui
	local existing = cap:FindFirstChild("SurfaceGui")
	if existing then existing:Destroy() end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceGui"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(150, 150)
	gui.PixelsPerStud = 70
	gui.LightInfluence = 1
	gui.Brightness = 1
	gui.ClipsDescendants = true
	gui.MaxDistance = maxDistance or 150

	local label = Instance.new("TextLabel")
	label.Name = "TextLabel"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.5, 0)
	label.Size = UDim2.new(0.5, 0, 0.5, 0)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.TextScaled = true
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextColor3 = Color3.new(0, 0, 0)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 1
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
	label.Text = text
	label.Parent = gui

	-- Reserved for later (GUI customization): created but disabled, same as
	-- in the original prototype. Not enabled until that phase.
	local stroke = Instance.new("UIStroke")
	stroke.Name = "UIStroke"
	stroke.Enabled = false
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 1
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label

	gui.Parent = cap
	return gui
end

return GuiFactory
