--!strict
-- Single responsibility: the shared look. Every metric, colour and
-- "make a styled primitive" helper the other components build on.
-- No layout logic, no behaviour, no state.
--
-- Colours come from the Studio theme wherever one fits, so the panel follows
-- the user's dark/light setting instead of hardcoding a palette.

local Theme = {}

Theme.ROW_HEIGHT = 26
Theme.PADDING = 8
Theme.GAP = 8
-- Rows are two columns (label | control). Anything below ~0.40 truncates the
-- longer labels at the panel's 320px width.
Theme.LABEL_WIDTH = 0.42
Theme.CORNER = 8
Theme.TEXT_SIZE = 14
Theme.FONT = Enum.Font.Gotham
Theme.FONT_BOLD = Enum.Font.GothamBold

Theme.ACCENT = Color3.fromRGB(64, 150, 255)
Theme.ACCENT_TEXT = Color3.new(1, 1, 1)
Theme.DANGER = Color3.fromRGB(205, 78, 66)
Theme.OK = Color3.fromRGB(58, 168, 110)

function Theme.Color(item: Enum.StudioStyleGuideColor, modifier: Enum.StudioStyleGuideModifier?): Color3
	return settings().Studio.Theme:GetColor(item, modifier)
end

-- Studio's own Border colour sits within a few percent of MainBackground in
-- the dark theme, so anything outlined with it has no visible edge at all.
-- Deriving the outline from the surface's OWN fill instead guarantees
-- contrast in either Studio theme: lighten a dark fill, darken a light one.
function Theme.Outline(fill: Color3): Color3
	local _, _, value = fill:ToHSV()
	return value < 0.5
		and fill:Lerp(Color3.new(1, 1, 1), 0.45)
		or fill:Lerp(Color3.new(0, 0, 0), 0.35)
end

-- Nudges a fill away from the surface behind it, in whichever direction the
-- theme makes visible. Used for floating surfaces, which must never read as
-- part of the panel they cover.
function Theme.Elevate(fill: Color3, amount: number?): Color3
	return fill:Lerp(Theme.Outline(fill), amount or 0.18)
end

-- Studio's LIGHT theme returns pure white (255,255,255) for MainBackground,
-- Item, Button AND InputFieldBackground alike — measured, not guessed. Every
-- surface in the panel therefore came out the same white as the page behind
-- it: no card edges, no field wells, and controls that read as plain text
-- rather than as things you can click. The DARK theme does separate those
-- four (25/25/53/40), so it needs none of this.
--
-- Hence the ladder below: in the light theme the panel provides its own
-- surface tones, and in the dark theme every helper hands back exactly the
-- Studio colour the code used before, so the dark look is untouched.
function Theme.IsLight(): boolean
	local _, _, value = Theme.Color(Enum.StudioStyleGuideColor.MainBackground):ToHSV()
	return value > 0.5
end

-- A raised card (Section). Returns fill AND transparency: the dark theme's
-- card is a translucent Item, the light theme's is an opaque off-white.
function Theme.CardFill(): (Color3, number)
	if Theme.IsLight() then
		return Color3.fromRGB(246, 247, 250), 0
	end
	return Theme.Color(Enum.StudioStyleGuideColor.Item), 0.55
end

-- A pressable surface (dropdowns, small action buttons).
function Theme.ButtonFill(): Color3
	if Theme.IsLight() then
		return Color3.fromRGB(237, 239, 245)
	end
	return Theme.Color(Enum.StudioStyleGuideColor.Button)
end

-- An input well (text boxes, slider tracks, the segmented pill, toggles):
-- deliberately a step deeper than ButtonFill, so "type/drag in me" and
-- "press me" don't read as the same surface.
function Theme.FieldFill(): Color3
	if Theme.IsLight() then
		return Color3.fromRGB(226, 229, 237)
	end
	return Theme.Color(Enum.StudioStyleGuideColor.InputFieldBackground)
end

-- The hairline that makes a surface an object. Studio's Border is a usable
-- grey in the light theme (188,190,200) and near-invisible in the dark one,
-- so the light theme leans on it and the dark theme keeps its old faintness.
function Theme.Edge(gui: GuiObject, darkTransparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Color(Enum.StudioStyleGuideColor.Border)
	stroke.Thickness = 1
	-- Border is a strong enough grey in the light theme that a fully opaque
	-- hairline reads as a heavy box; softened so it delimits without shouting.
	stroke.Transparency = Theme.IsLight() and 0.3 or (darkTransparency or 0.6)
	stroke.Parent = gui
	return stroke
end

-- Reuses an existing UICorner rather than adding a second one. A GuiObject
-- accepts any number of them but obeys only the first, so calling this twice
-- on the same object silently kept the FIRST radius and dropped the caller's.
-- That is why the selected segment of a Segmented control looked squarer than
-- the pill around it: Theme.Button had already cornered it at 8, and the 11 it
-- asked for afterwards was never applied.
function Theme.Corner(gui: GuiObject, radius: number?): UICorner
	local corner = gui:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or Theme.CORNER)
	corner.Parent = gui
	return corner
end

-- A plain text line. Used for row labels, section titles and the status line.
function Theme.Text(text: string, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Text = text
	label.BackgroundTransparency = 1
	label.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.MainText)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Font = Theme.FONT
	label.TextSize = Theme.TEXT_SIZE
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = parent
	return label
end

function Theme.Button(text: string, parent: Instance): TextButton
	local button = Instance.new("TextButton")
	button.Text = text
	button.Size = UDim2.new(1, 0, 1, 0)
	button.BackgroundColor3 = Theme.ButtonFill()
	button.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.ButtonText)
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Theme.FONT
	button.TextSize = Theme.TEXT_SIZE
	button.Parent = parent
	Theme.Corner(button)
	return button
end

-- A bare container that grows with its children. The building block of every
-- vertical stack in the panel (sections, popups, the root list).
function Theme.Stack(parent: Instance, order: number?): (Frame, UIListLayout)
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order or 1
	frame.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, Theme.GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	return frame, layout
end

-- Walks up to the widget's root frame. Components that track a drag need a
-- surface that keeps receiving mouse movement once the cursor leaves the
-- small control it started on.
function Theme.SurfaceOf(gui: Instance): GuiObject?
	local node: Instance? = gui
	while node do
		local parent = node.Parent
		if parent and parent:IsA("PluginGui") and node:IsA("GuiObject") then
			return node
		end
		node = parent
	end
	return nil
end

function Theme.TextBox(text: string, parent: Instance): TextBox
	local box = Instance.new("TextBox")
	box.Text = text
	box.ClearTextOnFocus = false
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundColor3 = Theme.FieldFill()
	box.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.MainText)
	box.BorderSizePixel = 0
	box.Font = Theme.FONT
	box.TextSize = Theme.TEXT_SIZE
	-- Left-aligned with a small inset: a centred value in a full-width field
	-- reads as a button label rather than as something editable.
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = parent
	Theme.Corner(box)
	Theme.Edge(box, 1)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = box
	return box
end

-- Brand colours, for the handful of controls that represent something
-- outside the plugin and so cannot take their colour from the Studio theme.
Theme.DISCORD = Color3.fromRGB(88, 101, 242)

-- Icon slugs picked by Seb, one per icon slot in the panel. Chosen in
-- StarterGui.KeyCapperUIPreview (a throwaway instance tree used only to try
-- icons live) and copied here once locked in; that preview is not read at
-- runtime, this table is the only source of truth.
--
-- Sourced from Font Awesome 5 (see CREDITS.md at the repo root).
--
-- Discord's own logo, imported by Seb from the official brand assets
-- (converted from webp to preserve transparency — see CREDITS.md).
-- NOT Font Awesome like the rest of this table: everything else is chosen
-- glyph-by-glyph to fit the panel's own vocabulary, but a brand mark has to
-- be the real logo or it does not read as "Discord" at all.
local ICONS: { [string]: string } = {
	Brush = "rbxassetid://109497141679277",
	Group = "rbxassetid://79689480999850",
	Tool = "rbxassetid://116809567292796",
	Paint = "rbxassetid://119512564599460",
	Erase = "rbxassetid://106185541901173",
	["Cap color"] = "rbxassetid://105253450798448",
	Label = "rbxassetid://86256816009801",
	Sound = "rbxassetid://88707291849063",
	AddSound = "rbxassetid://137367508279349",
	Feel = "rbxassetid://138515805840658",
	Others = "rbxassetid://106070793531050",
	Discord = "rbxassetid://137626841590880",
}
-- Roblox's built-in "missing image" checker: shown for any slug not yet in
-- ICONS above, so a forgotten icon is obviously wrong rather than invisible.
local PLACEHOLDER = "rbxasset://textures/ui/GuiImagePlaceholder.png"

-- The glyphs are white artwork, which only works on a dark panel. In the
-- light theme they have to be inked the other way round or they wash out
-- against the pale chips they sit in. White in the dark theme is a no-op tint
-- (a multiply by 1), so this leaves that theme exactly as it was.
--
-- Two callers deliberately opt out by overriding ImageColor3 afterwards: the
-- brush icon (white on its own red/green fill) and the Discord mark (a real
-- brand logo, which must not be re-inked at all).
function Theme.IconTint(): Color3
	if Theme.IsLight() then
		return Color3.fromRGB(38, 40, 48)
	end
	return Color3.new(1, 1, 1)
end

-- name is a slug into ICONS (e.g. "Brush", "Cap color"), not a file path.
function Theme.Icon(parent: Instance, name: string, size: number?): ImageLabel
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon_" .. name
	icon.Image = ICONS[name] or PLACEHOLDER
	icon.ImageColor3 = Theme.IconTint()
	icon.ScaleType = Enum.ScaleType.Fit
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(size or 16, size or 16)
	icon.Parent = parent
	return icon
end

-- Icon inside a soft rounded, accent-tinted "chip" rather than a bare
-- floating square: reads as a deliberate badge (section/group identity)
-- instead of a stray icon. Segmented options (Paint/Erase) intentionally
-- use plain Theme.Icon, not this — a chip per segment would be noisy.
function Theme.IconChip(parent: Instance, name: string, chipSize: number, iconSize: number): Frame
	local chip = Instance.new("Frame")
	chip.Name = "Chip_" .. name
	chip.Size = UDim2.fromOffset(chipSize, chipSize)
	chip.BackgroundColor3 = Theme.ACCENT
	chip.BackgroundTransparency = 0.82
	chip.BorderSizePixel = 0
	chip.Parent = parent
	Theme.Corner(chip, chipSize / 2)

	local icon = Theme.Icon(chip, name, iconSize)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	return chip
end

return Theme
