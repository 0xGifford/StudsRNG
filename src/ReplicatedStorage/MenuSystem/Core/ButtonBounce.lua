--!strict
-- ModuleScript -> ReplicatedStorage/MenuSystem/Core/ButtonBounce
--
-- Hover and press feedback, ported from the UI pack's button scripts
-- (UIPack "HUD Scripts" / "Menu Scripts"): every one of them does the same
-- thing, so it lives here once.
--
--   hover    the hover sound plays, the button shrinks a little, and its icon
--            ("Icone" / "Icon") tilts 15 degrees one way or the other
--   leave    back to rest, icon straight
--   click    the click sound plays, the button shrinks further for 0.125s,
--            then eases back to its hover or rest size
--
-- All tweens are the pack's 0.125s Quad Out. The pack tweens Size; this tweens
-- a UIScale instead (the kit's "ButtonScale"), which looks the same but does
-- not fight UIListLayout or aspect ratios.
--
--   ButtonBounce.apply(button)            hover + press
--   ButtonBounce.apply(button, false)     press only, for grid tiles
--   ButtonBounce.applyAll(container)      every GuiButton inside
--   ButtonBounce.pop(anyGuiObject)        one-shot attention bounce
--
-- Sounds come from Config.Sound (the pack's Click / Hover), overridable per
-- button:
--
--   HoverSound = "rbxassetid://..."   or "" to silence just this one
--   ClickSound = "rbxassetid://..."
--
-- BounceStrength (read from the nearest ancestor that sets it) still scales
-- the movement: 1 = the pack's, 0 = none.
--
-- Kit buttons (StudsRNG's UI kit): the visible button is a Frame with a
-- transparent, full-size GuiButton named "Button" on top. Bouncing that
-- overlay would show nothing, so the Frame bounces instead (its own icon
-- tilts). Put Menu / MenuAction / Tab... on the "Button" as usual.

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MenuSystem = script.Parent.Parent
local Config = require(MenuSystem.Config)

local CONFIG = Config.Bounce
local SOUND = Config.Sound
local ATTR = Config.Attributes

local INFO = TweenInfo.new(CONFIG.HoverTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_INFO = TweenInfo.new(CONFIG.PopTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Touch devices fire MouseEnter on tap, which would leave buttons stuck
-- shrunk and fire a hover sound on every press.
local TOUCH_ONLY = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

local ButtonBounce = {}

local applied: { [GuiButton]: boolean } = {}

--------------------------------------------------------------------

local function inheritNumber(instance: Instance, attribute: string): number?
	local node: Instance? = instance
	while node do
		local value = node:GetAttribute(attribute)
		if type(value) == "number" then
			return value
		end
		node = node.Parent
	end
	return nil
end

export type Feel = {
	Rest: number,
	Hover: number,
	Press: number,
	Release: TweenInfo,
}

local function resolveFeel(instance: GuiObject): Feel
	local strength = inheritNumber(instance, "BounceStrength") or 1
	local rest = CONFIG.Rest
	return {
		Rest = rest,
		Hover = rest + (CONFIG.Hover - rest) * strength,
		Press = rest + (CONFIG.Press - rest) * strength,
		Release = INFO,
	}
end
ButtonBounce.resolveFeel = resolveFeel

--------------------------------------------------------------------

-- Parented to SoundService rather than the button: a click sound should
-- outlive the panel that closes on that same click.
local lastPlayed: { [string]: number } = {}
local function play(button: GuiButton, attribute: string, fallback: string, volume: number)
	local id = button:GetAttribute(attribute)
	-- An empty string is a deliberate silence, so only fall back on nil
	if id == nil then id = fallback end
	if type(id) ~= "string" or id == "" then return end

	-- Sweeping the cursor across a row fires a burst of hovers; one per id per
	-- interval keeps it from rattling.
	local now = os.clock()
	if now - (lastPlayed[id] or 0) < SOUND.Debounce then return end
	lastPlayed[id] = now

	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function() sound:Destroy() end)
	-- Ended never fires for an id that fails to load
	Debris:AddItem(sound, SOUND.MaxLifetime)
end

local function getScale(instance: GuiObject): UIScale
	local existing = instance:FindFirstChildOfClass("UIScale")
	if existing then return existing end
	local scale = Instance.new("UIScale")
	scale.Name = "UIScale"
	scale.Parent = instance
	return scale
end

local function tween(target: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local t = TweenService:Create(target, info, goal)
	t:Play()
	return t
end

local function iconOf(button: GuiObject): GuiObject?
	local icon = button:FindFirstChild("Icone") or button:FindFirstChild("Icon")
	return (icon and icon:IsA("GuiObject")) and icon or nil
end

-- What actually moves: the kit Frame for a transparent "Button" overlay,
-- else the button itself.
local function visualOf(button: GuiButton): GuiObject
	local parent = button.Parent
	if button.Name == "Button" and button.BackgroundTransparency >= 1
		and parent and parent:IsA("GuiObject") and not parent:IsA("GuiButton")
		and button.Size.X.Scale >= 0.99 and button.Size.Y.Scale >= 0.99 then
		return parent
	end
	return button
end
ButtonBounce.visualOf = visualOf

--------------------------------------------------------------------

function ButtonBounce.apply(button: GuiButton, hover: boolean?)
	if applied[button] then return end
	applied[button] = true

	local visual = visualOf(button)
	local scale = getScale(visual)
	local icon = iconOf(visual)
	local iconRest = icon and icon.Rotation or 0
	local hovering = false

	if button:IsA("ImageButton") or button:IsA("TextButton") then
		button.AutoButtonColor = false
	end

	if hover ~= false and not TOUCH_ONLY then
		button.MouseEnter:Connect(function()
			hovering = true
			play(button, ATTR.HoverSound, SOUND.DefaultHover, SOUND.HoverVolume)
			tween(scale, INFO, { Scale = resolveFeel(button).Hover })
			if icon then
				local tilt = CONFIG.IconTilt or 15
				tween(icon, INFO, { Rotation = iconRest + (math.random(0, 1) == 0 and -tilt or tilt) })
			end
		end)

		button.MouseLeave:Connect(function()
			hovering = false
			tween(scale, INFO, { Scale = resolveFeel(button).Rest })
			if icon then tween(icon, INFO, { Rotation = iconRest }) end
		end)
	end

	button.Activated:Connect(function()
		play(button, ATTR.ClickSound, SOUND.DefaultClick, SOUND.ClickVolume)
		local feel = resolveFeel(button)
		local press = tween(scale, INFO, { Scale = feel.Press })
		press.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				tween(scale, INFO, { Scale = (hovering and not TOUCH_ONLY) and feel.Hover or feel.Rest })
			end
		end)
	end)

	button.Destroying:Connect(function()
		applied[button] = nil
	end)
end

function ButtonBounce.applyAll(container: Instance, hover: boolean?)
	for _, child in ipairs(container:GetDescendants()) do
		if child:IsA("GuiButton") then
			ButtonBounce.apply(child, hover)
		end
	end
end

-- One-shot bounce to draw the eye: a claimable reward, a new unlock.
function ButtonBounce.pop(instance: GuiObject)
	local scale = getScale(instance)
	local feel = resolveFeel(instance)
	local strength = inheritNumber(instance, "BounceStrength") or 1
	scale.Scale = feel.Rest + (CONFIG.Pop - CONFIG.Rest) * strength
	tween(scale, POP_INFO, { Scale = feel.Rest })
end

return ButtonBounce
