--!strict
-- ModuleScript -> ReplicatedStorage/MenuSystem/Menus/PackShared
--
-- The UI pack's "Shared" module (ReplicatedStorage.UIPack.Shared), ported to
-- run every menu in the game. Replaces the old Backdrop (dim sheet, drifting
-- icons) and the Menu rise/overshoot/cascade.
--
-- What the pack does, and what this keeps:
--   blur     the world blurs to Size 50 over 0.125s (Quad Out) while a menu
--            is open, and back to 0 when the last one closes. A menu with
--            Backdrop = false is left unblurred.
--   motion   a menu scales 0.92 -> 1 opening and 1 -> 0.92 closing, both
--            0.125s Quad Out (PlayOpen / PlayClose, used by Menu).
--   HUD      the pack slides every HUD frame off to its nearest screen edge;
--            HudSlide does that here, on the pack's timings.
--
-- What it changes from the pack, and why:
--   * The pack hard-wires its own Menu.Canva tree and allows one menu at a
--     time. This runs off MenuController, so it covers every ScreenGui menu
--     and menus stacked over each other (a reel over the chest menu).
--   * The pack fades its menus through one CanvasGroup's GroupTransparency.
--     Our windows break out of their bounds (header overhang, tilted icons),
--     which a CanvasGroup would clip, so only the scale is animated.
--   * The pack reuses whatever BlurEffect Lighting already has. That fights
--     any other system using one, so this owns its own ("MenuBlur").
--   * Stacking: the newest open menu is lifted above the others through
--     DisplayOrder, so it always draws on top.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local MenuSystem = script.Parent.Parent
local Config = require(MenuSystem.Config)

local PACK = Config.Pack
local ATTR = Config.Attributes

local PackShared = {}

PackShared.TweenInfo = TweenInfo.new(PACK.Tween, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
PackShared.TweenInfoSlow = TweenInfo.new(PACK.SlowTween, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
PackShared.OpenFrom = PACK.OpenFrom

--------------------------------------------------------------------
-- MOTION
--------------------------------------------------------------------

--- The pack's playOpen on a menu's UIScale. Returns the tween.
function PackShared.PlayOpen(scale: UIScale): Tween
	scale.Scale = PACK.OpenFrom
	local tween = TweenService:Create(scale, PackShared.TweenInfo, { Scale = 1 })
	tween:Play()
	return tween
end

--- The pack's playClose on a menu's UIScale. Returns the tween.
function PackShared.PlayClose(scale: UIScale): Tween
	local tween = TweenService:Create(scale, PackShared.TweenInfo, { Scale = PACK.OpenFrom })
	tween:Play()
	return tween
end

--------------------------------------------------------------------
-- BLUR
--------------------------------------------------------------------

local blur: BlurEffect? = nil

local function getBlur(): BlurEffect
	if blur and blur.Parent then
		return blur
	end
	local b = Instance.new("BlurEffect")
	b.Name = "MenuBlur"
	b.Size = 0
	b.Parent = Lighting
	blur = b
	return b
end

function PackShared.BlurIn()
	TweenService:Create(getBlur(), PackShared.TweenInfo, { Size = PACK.Blur }):Play()
end

function PackShared.BlurOut()
	TweenService:Create(getBlur(), PackShared.TweenInfo, { Size = 0 }):Play()
end

--------------------------------------------------------------------
-- STACKING
--------------------------------------------------------------------

-- Every lifted menu and the DisplayOrder to give back when it closes.
local restoreOrder: { [ScreenGui]: number } = {}

local function topLiftedOrder(except: ScreenGui?): number?
	local top: number? = nil
	for gui in pairs(restoreOrder) do
		if gui ~= except and gui.Parent and (top == nil or gui.DisplayOrder > top) then
			top = gui.DisplayOrder
		end
	end
	return top
end

local function lift(gui: ScreenGui)
	if restoreOrder[gui] == nil then
		restoreOrder[gui] = gui.DisplayOrder
	end
	local beneath = topLiftedOrder(gui)
	gui.DisplayOrder = beneath and math.max(PACK.MenuDisplayOrder, beneath + 1) or PACK.MenuDisplayOrder
end

local function drop(gui: ScreenGui)
	local original = restoreOrder[gui]
	if original ~= nil then
		gui.DisplayOrder = original
		restoreOrder[gui] = nil
	end
end

--------------------------------------------------------------------

function PackShared.Start()
	local MenuController = require(script.Parent.MenuController) :: any
	local Registry = require(script.Parent.Registry) :: any

	local function wantsBlur(): boolean
		for _, name in MenuController.OpenMenus() do
			local gui = Registry.Get(name)
			if gui and gui:GetAttribute(ATTR.Backdrop) ~= false then
				return true
			end
		end
		return false
	end

	local blurred = false
	local function syncBlur()
		local want = wantsBlur()
		if want ~= blurred then
			blurred = want
			if want then PackShared.BlurIn() else PackShared.BlurOut() end
		end
	end

	MenuController.Opened:Connect(function(name: string)
		local gui = Registry.Get(name)
		if gui then lift(gui) end
		syncBlur()
	end)

	MenuController.Closed:Connect(function(name: string)
		local gui = Registry.Get(name)
		if gui then drop(gui) end
		-- deferred: an exclusive switch closes one menu and opens the next in the
		-- same frame, and the blur should not dip between them
		task.defer(syncBlur)
	end)
end

return PackShared
