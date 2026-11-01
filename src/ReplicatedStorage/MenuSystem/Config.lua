--!strict
-- ModuleScript -> ReplicatedStorage/MenuSystem/Config
--
-- Every string and number the system looks for, in one place. Rename an
-- attribute here and the whole system follows.

local Config = {}

--------------------------------------------------------------------
-- ATTRIBUTES
--------------------------------------------------------------------

Config.Attributes = {
	-- On a GuiButton
	Menu = "Menu",                   -- string: which menu it targets
	MenuAction = "MenuAction",       -- "toggle" (default) | "open" | "close" | "closeAll"
	Bounce = "Bounce",               -- false to opt out of scaling
	BounceHover = "BounceHover",     -- false for press-only
	HoverSound = "HoverSound",       -- "" silences just this button
	ClickSound = "ClickSound",

	-- On a menu ScreenGui
	MenuPanel = "MenuPanel",         -- true on the frame that animates
	MenuExclusive = "MenuExclusive", -- false to allow stacking
	MenuKey = "MenuKey",             -- KeyCode name, e.g. "Tab"
	MenuOpenSound = "MenuOpenSound",
	MenuCloseSound = "MenuCloseSound",

	MenuMusic = "MenuMusic",              -- looping track, stops on close
	MenuMusicVolume = "MenuMusicVolume",  -- overrides Config.Sound.MusicVolume

	-- Idle motion. Number, or "min,max" for an asymmetric range.
	Sway = "Sway",                   -- degrees, rocks back and forth
	Bob = "Bob",                     -- pixels, moves up and down
	Pulse = "Pulse",                 -- scale, 0.08 means 1 to 1.08
	Spin = "Spin",                   -- degrees per second, continuous

	MotionSpeed = "MotionSpeed",     -- cycles per second, default 0.5
	MotionOffset = "MotionOffset",   -- phase 0 to 1, to stagger a row
	MotionRandom = "MotionRandom",   -- true for a random phase

	-- Tabs
	Tab = "Tab",                     -- on a button: page name to show
	TabGroup = "TabGroup",           -- name a group, or target one explicitly
	TabDefault = "TabDefault",       -- true on the page shown first
	TabRemember = "TabRemember",     -- true on a menu: keep the tab on reopen

	-- Toggles
	Toggle = "Toggle",               -- id string, or true to use the button's name
	ToggleDefault = "ToggleDefault", -- true to start toggled on

	-- Purchase buttons
	Gamepass = "Gamepass",                     -- true
	GamepassID = "GamepassID",                 -- number
	DeveloperProduct = "DeveloperProduct",     -- true
	DeveloperProductID = "DeveloperProductID", -- number
	RobloxPlus = "RobloxPlus",                 -- true, no id needed

	-- Price labels anywhere, no button required
	GamepassPrice = "GamepassPrice",           -- number: price, or owned text
	ProductPrice = "ProductPrice",             -- number: price
	PlusPrice = "PlusPrice",                   -- true: the Plus text

	-- Shared by both
	PriceFormat = "PriceFormat",               -- overrides Config, e.g. "R$ %s"
	OwnedText = "OwnedText",                   -- overrides Config
	HideWhenOwned = "HideWhenOwned",           -- remove instead of restyle

	-- Two-state styling
	StateActive = "StateActive",     -- written by the system, readable by you
	StateTarget = "StateTarget",     -- prefer this child when resolving a property
	StatePreset = "StatePreset",
	StateTweenTime = "StateTweenTime",

	-- Blur behind a menu (PackShared)
	Backdrop = "Backdrop",           -- false to opt out

	-- Tooltip
	TooltipTemplate = "TooltipTemplate",       -- true on the frame you designed
	TooltipTemplateGui = "TooltipTemplateGui", -- false to leave its ScreenGui enabled
	TooltipSide = "TooltipSide",               -- right | left | top | bottom | auto
	TooltipColor = "TooltipColor",             -- "R,G,B" or a Color3
	TooltipStrokeColor = "TooltipStrokeColor",
	TooltipShadowColor = "TooltipShadowColor",
	TooltipDelay = "TooltipDelay",
	TooltipGroup = "TooltipGroup",             -- false to bind only the instance

	-- Components: set these on an instance and it draws itself; change
	-- them and it redraws (Menus/Component and the modules named below).
	Stud = "Stud",                   -- ViewportFrame: a stud's Id (StudView)
	StudVariant = "StudVariant",     --   Normal | Big | Huge | Jumbo | Shiny | Inverted
	StudFit = "StudFit",             --   size it draws at, default by variant
	Zone = "Zone",                   -- ViewportFrame: a zone's Id (ZoneView)
	ZoneShow = "ZoneShow",           --   Preview | Enemy | Stud, default first found
	ViewTurn = "ViewTurn",           -- both views: Vector3 degrees
	ViewSpin = "ViewSpin",           -- both views: degrees per second
	ViewZoom = "ViewZoom",           -- ZoneView: 1 = snug, less = closer
	ViewSilhouette = "ViewSilhouette", -- both views: dark shape ("not found yet")
	ViewSilhouetteColor = "ViewSilhouetteColor",
	Progress = "Progress",           -- a bar's fill: 0 to 1 (ProgressBar)
	ProgressAxis = "ProgressAxis",   --   X | Y
	ProgressTween = "ProgressTween", --   seconds, 0 = instant
	KitColor = "KitColor",           -- kit button / card: palette name (KitColor)
	Icon = "Icon",                   -- ImageLabel: Config.Icons name, asset or emoji (IconImage)
	Rarity = "Rarity",               -- anything: tinted by a stud rarity (RarityColor)
	RarityMode = "RarityMode",       --   Gradient | Background | Stroke | Text | Image
	UITemplate = "UITemplate",       -- a template the code copies (Roles.template)
}

--------------------------------------------------------------------
-- ICONS (IconImage: Icon = "<name>")
--------------------------------------------------------------------
-- An asset id shows as the image; anything else (an emoji) is drawn as
-- text. Add your own and use them anywhere with the Icon attribute.
Config.Icons = {
	Clacks = "rbxassetid://117187305699068",
	FreeRolls = "🎲",
	Spins = "rbxassetid://72974128962815",
	Luck = "🍀",
	MegaRoll = "🎰",
	Bundle = "🎁",
	Boost = "rbxassetid://131975246594329",
	Event = "rbxassetid://119611914627070",
	ServerLuck = "rbxassetid://119611914627070",
}

--------------------------------------------------------------------
-- COLLECTIONSERVICE TAGS
--------------------------------------------------------------------
-- For bulk-marking in Studio's tag editor rather than per-instance
-- attributes. Either works; tags are faster for many instances at once.

Config.Tags = {
	Menu = "Menu",                   -- on a ScreenGui
	MenuButton = "MenuButton",       -- on a GuiButton
	Bounce = "Bounce",               -- scaling only, no menu behaviour

	-- Price labels are found by attribute anyway; this tag is only for
	-- bulk-marking in the tag editor when a batch of labels is added at
	-- runtime and you'd rather not wait for the DescendantAdded pass.
	Price = "Price",
}

--------------------------------------------------------------------
-- IDLE MOTION
--------------------------------------------------------------------
-- Every value can be a number or a "min,max" string. A bare number is
-- symmetric around the resting value, so Sway = 5 rocks between -5 and +5.

Config.Motion = {
	-- Full cycles per second when MotionSpeed isn't set. Slow on purpose:
	-- idle motion should be noticed peripherally, not watched.
	Speed = 0.5,

	-- Attributes that trigger a rebuild when edited during a playtest
	Attributes = {
		Sway = true,
		Bob = true,
		Pulse = true,
		Spin = true,
		MotionSpeed = true,
		MotionOffset = true,
		MotionRandom = true,
	},
}

--------------------------------------------------------------------
-- SOUND
--------------------------------------------------------------------
-- Defined ONCE. A second Config.Sound further down the file silently
-- replaces this whole table — which is what dropped the music settings and
-- produced "[Menu] Config.Sound is missing MusicVolume..." on every run.

Config.Sound = {
	-- One id here covers every button in the game
	DefaultHover = "rbxassetid://92876108656319", -- UI pack "Hover"
	DefaultClick = "rbxassetid://6895079853",     -- UI pack "Click"

	-- One-shot stings on open and close. Short only: anything long put
	-- here can't be stopped, because nothing holds a reference to it.
	-- Use MenuMusic for a loop.
	DefaultOpen = "rbxassetid://109359226723492",  -- Stud UI "Ouverture"
	DefaultClose = "rbxassetid://117813075686953", -- Stud UI "Fermeture"

	HoverVolume = 0.25,   -- hover fires far more often, so it sits under
	ClickVolume = 0.5,
	Volume = 0.5,         -- menu open/close stings

	--------------------------------------------------------------------
	-- MUSIC
	--------------------------------------------------------------------
	-- Per menu, via MenuMusic on the ScreenGui. Looped, owned by the menu,
	-- faded both ways and stopped when the fade finishes.

	MusicVolume = 0.35,   -- under the effects; overridable per menu
	MusicFadeIn = 0.6,
	MusicFadeOut = 0.8,

	-- Resume where it left off rather than restarting. Flicking a menu
	-- shut and open again shouldn't jump back to the first bar.
	MusicResumes = true,

	-- Sweeping across a row of buttons fires a burst of hovers; one per id
	-- per interval keeps that from rattling
	Debounce = 0.06,

	-- Slight pitch wobble so repeated clicks don't sound machine-gunned
	PitchVariance = 0.08,

	MaxLifetime = 6,      -- Debris backstop for ids that never load
}

--------------------------------------------------------------------
-- TOOLTIP
--------------------------------------------------------------------

Config.Tooltip = {
	Prefix = "Tooltip",

	-- TitleContainer holds Title's labels, so a text label and its drop
	-- shadow both receive the same value from one attribute.
	ContainerSuffix = "Container",

	-- The frame carrying the tooltip's own styling. Only used when the
	-- template contains a child by this name; otherwise the template
	-- itself is the styled frame.
	StyleRootName = "MainFrame",

	-- Matched by exact name, as DIRECT children of the styled frame only.
	-- A title's own drop shadow is usually called "Shadow" and sits deeper
	-- in the tree; keeping this to direct children means it stays put.
	StrokeName = "MainStroke",
	ShadowName = "MainShadow",

	-- Attributes that configure the tooltip rather than fill a label
	Reserved = {
		Template = true,
		TemplateGui = true,
		Side = true,
		Color = true,
		StrokeColor = true,
		ShadowColor = true,
		Delay = true,
		Group = true,
	},

	DisplayOrder = 500,       -- above menus, which sit around 41
	DefaultSide = "right",
	Gap = 12,                 -- pixels between the source and the panel
	Edge = 8,                 -- keep this far from the screen edge

	Delay = 0.35,             -- before it appears
	FadeTime = 0.12,
	HiddenScale = 0.92,
}

--------------------------------------------------------------------
-- PURCHASES
--------------------------------------------------------------------

Config.Purchase = {
	-- A label by this name inside a button is filled with the price.
	-- "PriceContainer" holding labels works too, matching how the tooltip
	-- handles a text label plus its drop shadow.
	PriceName = "Price",

	-- Wraps the number. The %s is where the figure goes, so the currency
	-- mark, spacing and any suffix all live here:
	--
	--   "%s"        1,200
	--   "R$ %s"     R$ 1,200
	--   "%s Robux"  1,200 Robux
	--
	-- Overridable per instance with a PriceFormat attribute.
	PriceFormat = " %s",

	-- Shown instead of the price once a gamepass is owned. Developer
	-- products never reach this: Roblox records no ownership for them.
	OwnedText = "OWNED",

	-- While the lookup is in flight. "" leaves whatever Studio had.
	PriceLoadingText = "...",

	-- Off sale, or the lookup failed. Blanking it would look broken.
	PriceErrorText = "—",

	-- Roblox Plus has no Robux price: Roblox sets a money price that
	-- varies by region, so hardcoding one would be wrong nearly everywhere.
	PlusText = " PLUS",
	PlusOwnedText = "SUBSCRIBED",

	-- The prompt closing doesn't mean the property has updated yet
	PlusRecheckDelay = 1,

	-- Prices rarely change mid-session, so they're fetched once per id and
	-- shared. Ownership is re-checked whenever Invalidate is called.
	CachePrices = true,
}

--------------------------------------------------------------------
-- TWO-STATE STYLING
--------------------------------------------------------------------
-- A styled instance declares its look as colours against NAMED TARGETS
-- rather than property paths:
--
--   ActiveBackground = Color3   the button's own BackgroundColor3
--   ActiveStroke     = Color3   MainStroke.Color
--   ActiveShadow     = Color3   MainShadow.Color
--
-- Each has an Inactive counterpart and an optional Hover variant:
--
--   InactiveHoverStroke = Color3
--
-- Anything not listed in Targets falls back to being treated as a raw
-- property name, so ActiveImage and ActiveBackgroundTransparency still
-- work for the cases colours don't cover.

Config.State = {
	States = { "Inactive", "Active" },
	HoverInfix = "Hover",

	Aliases = {
		Default = "Inactive",
		Toggled = "Active",
		Selected = "Active",
		Unselected = "Inactive",
	},

	-- Child name plus the property to write. Child = nil means the styled
	-- instance itself. Deep = false restricts the search to direct
	-- children, which matters when a name repeats deeper in the tree.
	Targets = {
		Background = { Child = nil, Property = "BackgroundColor3" },
		Stroke     = { Child = "MainStroke", Property = "Color", Deep = false },
		Shadow     = { Child = "MainShadow", Property = "Color", Deep = false },
		Text       = { Child = "Text", Property = "TextColor3" },

		-- Child image element named "Icon"
		Icon       = { Child = "Icon", Property = "ImageColor3" },

		-- The button's own image (e.g. ImageButton), for art that is tinted
		Tint       = { Child = nil, Property = "ImageColor3" },
	},

	-- Named sets, so a tab strip doesn't need six attributes per button.
	-- Per-instance attributes override whatever the preset declares.
	Presets = {
		-- Plain (non-Stud) tabs and toggles: slate idle, blue selected, lime
		-- on. Stud UI buttons use the StudTab preset / Theme.Paint instead.

		-- Standard Frame/TextButton Tab
		Tab = {
			InactiveBackground = Color3.fromRGB(43, 69, 82),
			InactiveStroke     = Color3.fromRGB(12, 20, 26),
			InactiveShadow     = Color3.fromRGB(12, 20, 26),
			InactiveText       = Color3.fromRGB(200, 215, 222),

			InactiveHoverBackground = Color3.fromRGB(58, 92, 108),
			InactiveHoverText       = Color3.fromRGB(255, 255, 255),

			ActiveBackground = Color3.fromRGB(0, 190, 255),
			ActiveStroke     = Color3.fromRGB(12, 20, 26),
			ActiveShadow     = Color3.fromRGB(0, 50, 110),
			ActiveText       = Color3.fromRGB(255, 255, 255),

			ActiveHoverBackground = Color3.fromRGB(60, 215, 255),
		},


		-- A selectable card or slot (Index tabs and cells, Backpack cells):
		-- its outline (a UIStroke named MainStroke) turns white when picked.
		Selected = {
			InactiveStroke = Color3.fromRGB(12, 12, 16),
			InactiveHoverStroke = Color3.fromRGB(110, 110, 125),
			ActiveStroke = Color3.fromRGB(255, 255, 255),
			ActiveHoverStroke = Color3.fromRGB(255, 255, 255),
		},

		-- Stud UI tab: inactive tabs tint their Face CanvasGroup grey
		-- (kit motion-and-sound: #9696A6), the active one shows full colour
		StudTab = {
			InactiveGroupColor3 = Color3.fromRGB(150, 150, 166),
			InactiveHoverGroupColor3 = Color3.fromRGB(205, 205, 215),
			ActiveGroupColor3 = Color3.fromRGB(255, 255, 255),
			ActiveHoverGroupColor3 = Color3.fromRGB(255, 255, 255),
		},

		-- ImageButton Tab (Tints the button's own image)
		ImageTab = {
			InactiveTint = Color3.fromRGB(140, 138, 155),
			InactiveHoverTint = Color3.fromRGB(200, 198, 215),

			ActiveTint = Color3.fromRGB(255, 255, 255),
			ActiveHoverTint = Color3.fromRGB(255, 255, 255),
		},

		-- Tab with a child ImageLabel named "Icon"
		IconTab = {
			InactiveBackground = Color3.fromRGB(43, 69, 82),
			InactiveIcon       = Color3.fromRGB(170, 190, 200),
			InactiveText       = Color3.fromRGB(200, 215, 222),

			InactiveHoverBackground = Color3.fromRGB(58, 92, 108),
			InactiveHoverIcon       = Color3.fromRGB(255, 255, 255),
			InactiveHoverText       = Color3.fromRGB(255, 255, 255),

			ActiveBackground = Color3.fromRGB(0, 190, 255),
			ActiveIcon       = Color3.fromRGB(255, 255, 255),
			ActiveText       = Color3.fromRGB(255, 255, 255),

			ActiveHoverBackground = Color3.fromRGB(60, 215, 255),
		},

		-- Combined Image + Background Tab
		FullTab = {
			InactiveBackground = Color3.fromRGB(43, 69, 82),
			InactiveTint       = Color3.fromRGB(170, 190, 200),
			InactiveHoverBackground = Color3.fromRGB(58, 92, 108),
			InactiveHoverTint       = Color3.fromRGB(255, 255, 255),

			ActiveBackground   = Color3.fromRGB(0, 190, 255),
			ActiveTint         = Color3.fromRGB(255, 255, 255),
			ActiveHoverBackground = Color3.fromRGB(60, 215, 255),
		},

		Toggle = {
			InactiveBackground = Color3.fromRGB(43, 69, 82),
			InactiveStroke     = Color3.fromRGB(12, 20, 26),
			InactiveShadow     = Color3.fromRGB(12, 20, 26),

			InactiveHoverBackground = Color3.fromRGB(58, 92, 108),

			ActiveBackground = Color3.fromRGB(160, 245, 20),
			ActiveStroke     = Color3.fromRGB(12, 20, 26),
			ActiveShadow     = Color3.fromRGB(15, 120, 15),

			ActiveHoverBackground = Color3.fromRGB(190, 255, 70),
		},

		Purchase = {
			InactiveBackground = Color3.fromRGB(160, 245, 20),
			InactiveStroke     = Color3.fromRGB(12, 20, 26),
			InactiveShadow     = Color3.fromRGB(15, 120, 15),

			InactiveHoverBackground = Color3.fromRGB(190, 255, 70),

			ActiveBackground = Color3.fromRGB(200, 208, 218),
			ActiveStroke     = Color3.fromRGB(12, 20, 26),
			ActiveShadow     = Color3.fromRGB(72, 82, 96),
			ActiveText       = Color3.fromRGB(255, 255, 255),
		},
	},

	TweenTime = 0.18,
	TweenStyle = Enum.EasingStyle.Quad,
	TweenDirection = Enum.EasingDirection.Out,

	Instant = {
		Image = true,
		Text = true,
		Visible = true,
		ZIndex = true,
	},
}

--------------------------------------------------------------------
-- UI PACK MOTION (ported from ReplicatedStorage.UIPack scripts)
--------------------------------------------------------------------
-- The pack's Shared module: one quick Quad tween for everything, the world
-- blurred hard behind an open menu, the HUD slid off to its nearest edge.

Config.Pack = {
	Tween = 0.125,          -- the pack's tweenInfo: menus, buttons, tabs, HUD return
	SlowTween = 0.35,       -- the pack's tweenInfoSlow: HUD leaving
	Blur = 50,              -- BlurEffect.Size while a menu is open
	OpenFrom = 0.92,        -- a menu scales 0.92 -> 1 opening, 1 -> 0.92 closing
	MenuDisplayOrder = 41,  -- the first open menu is lifted here; stacked ones go above it
	SwitchTween = 0.2,      -- the pack's switch knob
}

Config.Animation = {
	OpenTime = Config.Pack.Tween,
	OpenStyle = Enum.EasingStyle.Quad,
	OpenDirection = Enum.EasingDirection.Out,

	CloseTime = Config.Pack.Tween,
	CloseStyle = Enum.EasingStyle.Quad,
	CloseDirection = Enum.EasingDirection.Out,
}

-- The pack's button feel: a button shrinks a little under the cursor (its icon
-- tilts 15 degrees either way), shrinks further when clicked, and eases back.
Config.Bounce = {
	Rest = 1.00,
	Hover = 0.95,
	Press = 0.88,
	Pop = 1.12,
	IconTilt = 15,

	HoverTime = 0.125,
	PressTime = 0.125,
	ReleaseTime = 0.125,
	PopTime = 0.25,
}

--------------------------------------------------------------------
-- BEHAVIOUR
--------------------------------------------------------------------

Config.Behaviour = {
	ExclusiveByDefault = true,   -- opening one menu closes the others
	CloseOnEscape = true,        -- Escape closes the most recently opened
	WarnOnMissingPanel = true,
	WarnOnMissingMenu = true,
	Verbose = false,             -- log every open, close, bind and group
}


--------------------------------------------------------------------
-- MODULE SETTINGS
--------------------------------------------------------------------
-- Every menu module's tuning in one place. ConfigOverrides (booted first)
-- copies each entry onto its module before it starts. Edit values here.
Config.Modules = {
	Scale = {
		DEVICES = { Desktop = { Margin = 40, Max = 1, Min = 0.6 }, Phone = { Margin = 10, Max = 1, Min = 0.35 }, Tablet = { Margin = 28, Max = 1, Min = 0.5 } },
		PHONE_MAX_SIDE = 500,
	},
}

return Config
