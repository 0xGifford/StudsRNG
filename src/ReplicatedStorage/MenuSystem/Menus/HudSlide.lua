--!nonstrict
--[[
	ReplicatedStorage/MenuSystem/Menus/HudSlide

	While any menu is open, the HUD gets out of the way: every element swipes
	off through the screen edge nearest to it — left, right, top or bottom — and
	comes back the way it left when the last menu closes.

	This is the UI pack's animateHUD (UIPack.Shared): out over 0.35s, back over
	0.125s, both Quad Out, each element carried half a screen past its nearest
	edge. The pack's version takes every frame under its one HUD and trusts a
	single open/close; the rules below (tags, KeepHud, the reality check) keep it
	working across all of our HUDs and stacked menus.

	WHAT SLIDES
	  Tag a ScreenGui "HudSlide" and each of its top-level elements slides on
	  its own, each to its own nearest edge. A single element can be tagged
	  instead. Never tag menus or TopbarPlus — the topbar stays put.

	WHAT STAYS
	  HudStay       (tag or attribute) on an element keeps it on screen
	  Full-screen   elements covering 90%+ of the screen (glows, backgrounds)
	                stay automatically: sliding one off a side looks wrong
	  KeepHud       (tag or attribute) on a menu's ScreenGui: opening that menu
	                leaves the HUD alone — for small popups

	DIRECTION
	  Nearest edge by default. HudSlideDir = "Left" | "Right" | "Top" | "Bottom"
	  on an element, or on its ScreenGui, forces one.

	WHAT COUNTS AS "A MENU IS OPEN"
	  MenuController.Opened adds a menu and Closed removes it — but a menu can
	  also go away without a Closed (a reel hidden directly, an exclusive
	  switch), and one missed Closed would keep the HUD out forever. So the
	  list is checked against the screen: on every change, and twice a second
	  while the HUD is out, a listed menu that is no longer shown is dropped.
	  "Shown" = its ScreenGui is enabled, its MenuPanel is visible, and the
	  panel isn't scaled to nothing. A menu opened under a second ago is never
	  dropped (its open animation may start at scale 0), and a menu whose
	  ScreenGui can't be found by name is left to its Closed signal.

	DUMP
	  Live state is mirrored on the local player:
	    HudSlideOut    true while the HUD is out
	    HudSlideMenus  the menus it believes are open, comma-separated
	    HudSlideLast   the last thing it did, and why

	HOME POSITION
	  Taken when an element leaves, not once at startup, so code that moves HUD
	  elements around between menus is respected.

	SCALED HUDS
	  A HUD with ScaleScreen (Scale.lua) keeps its elements inside one
	  "ScreenFit" frame; that frame is looked through, so its children slide
	  as top-level elements. Distances are measured in real pixels and divided
	  by Scale.ScreenFactor, since an offset there is worth fewer pixels.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local MenuController = require(script.Parent.MenuController)

local Scale = nil
do
	local ok, result = pcall(require, script.Parent.Scale)
	Scale = ok and result or nil
end

--- How many real pixels one offset pixel is worth for this element.
local function factorOf(el: Instance): number
	return (Scale and Scale.ScreenFactor) and Scale.ScreenFactor(el) or 1
end

--- A gui's top-level elements, looking through Scale's ScreenFit wrapper.
local function topLevel(gui: Instance): { Instance }
	local out = {}
	for _, child in gui:GetChildren() do
		if child.Name == "ScreenFit" and child:IsA("GuiObject") then
			for _, inner in child:GetChildren() do
				table.insert(out, inner)
			end
		else
			table.insert(out, child)
		end
	end
	return out
end

local player = Players.LocalPlayer

local HudSlide = {}

HudSlide.TAG = "HudSlide"
HudSlide.OUT_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- the pack's tweenInfoSlow
HudSlide.IN_INFO = TweenInfo.new(0.125, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- the pack's tweenInfo
HudSlide.MARGIN = 24          -- px past the edge, so strokes and shadows clear it too
HudSlide.OVERSHOOT = 0.5      -- and then this much of the screen further, as the pack does
HudSlide.FULLSCREEN = 0.9     -- elements this much of the screen (both ways) stay
HudSlide.OPEN_GRACE = 1       -- seconds a newly opened menu is trusted without checking
HudSlide.RECHECK = 0.5        -- seconds between reality checks while the HUD is out

local DIRECTIONS = { Left = true, Right = true, Top = true, Bottom = true }

local started = false
local playerGui: Instance? = nil
local isOut = false
local openMenus: { [string]: number } = {}               -- menu name -> os.clock() when opened
-- el -> { home, offset, out, away, tween }. A STRONG table on purpose: a weak
-- key holding only an Instance can be collected while the Instance is still on
-- screen (Roblox may drop and remake its Lua reference), which emptied this
-- table while a menu was open and left the HUD stranded off-screen. Entries are
-- removed explicitly when their element is destroyed instead.
local state = {}
local watchedGuis = setmetatable({}, { __mode = "k" })
local panelCache = setmetatable({}, { __mode = "k" })    -- menu ScreenGui -> its MenuPanel

-- Effects is optional: reduced motion makes the slide instant.
local Effects = nil
do
	local module = script.Parent:FindFirstChild("Effects")
	if module then
		local ok, result = pcall(require, module)
		if ok then
			Effects = result
		end
	end
end

local function reduced(): boolean
	return Effects ~= nil and Effects.IsReduced ~= nil and Effects.IsReduced()
end

local function flagged(inst: Instance, name: string): boolean
	return inst:HasTag(name) or inst:GetAttribute(name) == true
end

local function mirror(reason: string?)
	local names = {}
	for name in openMenus do
		table.insert(names, name)
	end
	table.sort(names)
	pcall(function()
		player:SetAttribute("HudSlideOut", isOut)
		player:SetAttribute("HudSlideMenus", table.concat(names, ","))
		if reason then
			player:SetAttribute("HudSlideLast", reason)
		end
	end)
end

-- ================================================================ targets

local function isFullscreen(el: GuiObject, gui: LayerCollector): boolean
	local g, a = gui.AbsoluteSize, el.AbsoluteSize
	return g.X > 0 and a.X >= g.X * HudSlide.FULLSCREEN and a.Y >= g.Y * HudSlide.FULLSCREEN
end

local function eligible(el: Instance): boolean
	if not el:IsA("GuiObject") or flagged(el, "HudStay") then
		return false
	end
	local gui = el:FindFirstAncestorWhichIsA("LayerCollector")
	return gui ~= nil and not isFullscreen(el, gui)
end

local function collect(): { GuiObject }
	local seen, list = {}, {}
	local function add(el: Instance)
		if not seen[el] and eligible(el) then
			seen[el] = true
			table.insert(list, el)
		end
	end
	for _, tagged in CollectionService:GetTagged(HudSlide.TAG) do
		if playerGui and tagged:IsDescendantOf(playerGui) then
			if tagged:IsA("LayerCollector") then
				for _, child in topLevel(tagged) do
					add(child)
				end
			else
				add(tagged)
			end
		end
	end
	return list
end

-- ================================================================ direction

--- The offset that carries the element fully past its nearest edge, measured
--- in its ScreenGui's own space.
local function offsetFor(el: GuiObject): UDim2
	local gui = el:FindFirstAncestorWhichIsA("LayerCollector") :: LayerCollector
	local W, H = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
	local pos = el.AbsolutePosition - gui.AbsolutePosition
	local size = el.AbsoluteSize
	local f = factorOf(el)

	local dir = el:GetAttribute("HudSlideDir") or gui:GetAttribute("HudSlideDir")
	if not (type(dir) == "string" and DIRECTIONS[dir]) then
		local cx, cy = pos.X + size.X / 2, pos.Y + size.Y / 2
		if size.X <= 0 and size.Y <= 0 then
			-- Not laid out (hidden): judge by its authored Position instead.
			local p = el.Position
			cx = p.X.Scale * W + p.X.Offset * f
			cy = p.Y.Scale * H + p.Y.Offset * f
		end
		local best, distance = "Left", cx
		if W - cx < distance then
			best, distance = "Right", W - cx
		end
		if cy < distance then
			best, distance = "Top", cy
		end
		if H - cy < distance then
			best = "Bottom"
		end
		dir = best
	end

	-- Measured in real pixels; offsets inside a scaled HUD are worth f of them.
	local horizontal = dir == "Left" or dir == "Right"
	local m = HudSlide.MARGIN + (horizontal and W or H) * HudSlide.OVERSHOOT
	if dir == "Left" then
		return UDim2.fromOffset(-(pos.X + size.X + m) / f, 0)
	elseif dir == "Right" then
		return UDim2.fromOffset((W - pos.X + m) / f, 0)
	elseif dir == "Top" then
		return UDim2.fromOffset(0, -(pos.Y + size.Y + m) / f)
	end
	return UDim2.fromOffset(0, (H - pos.Y + m) / f)
end

-- ================================================================ motion

local function tweenTo(el: GuiObject, s, goal: UDim2, info: TweenInfo)
	if s.tween then
		s.tween:Cancel()
		s.tween = nil
	end
	if reduced() then
		el.Position = goal
		if not s.out then
			s.away = false
		end
		return
	end
	local tween = TweenService:Create(el, info, { Position = goal })
	s.tween = tween
	tween.Completed:Connect(function()
		if s.tween == tween then
			s.tween = nil
			if not s.out then
				s.away = false -- home again: the next exit measures afresh
			end
		end
	end)
	tween:Play()
end

local function slideOut(el: GuiObject, instant: boolean?)
	local s = state[el]
	if not s then
		s = { out = false, away = false }
		state[el] = s
		el.Destroying:Once(function()
			state[el] = nil
		end)
	end
	if s.out then
		return
	end
	-- Measured only from rest. Caught mid-return, it goes back out from where
	-- it is, toward the same edge, and still comes home to the same place.
	if not s.away then
		s.home = el.Position
		s.offset = offsetFor(el)
	end
	s.out, s.away = true, true

	local goal = s.home + s.offset
	if instant then
		if s.tween then
			s.tween:Cancel()
			s.tween = nil
		end
		el.Position = goal
	else
		tweenTo(el, s, goal, HudSlide.OUT_INFO)
	end
end

local function slideIn(el: GuiObject)
	local s = state[el]
	if not s or not s.out then
		return
	end
	s.out = false
	if el.Parent then
		tweenTo(el, s, s.home, HudSlide.IN_INFO)
	end
end

local function apply()
	if isOut then
		for _, el in collect() do
			slideOut(el)
		end
	else
		local moved = 0
		for el, s in state do
			if not el.Parent then
				state[el] = nil -- removed without being destroyed: nothing to bring back
			elseif s.out then
				slideIn(el)
				moved += 1
			end
		end
		pcall(function()
			player:SetAttribute("HudSlideMoved", moved)
		end)
	end
end

-- ================================================================ menus

local function panelOf(gui: Instance): Instance?
	local cached = panelCache[gui]
	if cached and cached.Parent and cached:IsDescendantOf(gui) then
		return cached
	end
	for _, d in gui:GetDescendants() do
		if d:GetAttribute("MenuPanel") then
			panelCache[gui] = d
			return d
		end
	end
	return nil
end

--- true / false when the menu can be checked, nil when it can't be found by
--- name (then only its Closed signal can remove it).
local function menuShown(name: string): boolean?
	local gui = playerGui and playerGui:FindFirstChild(name)
	if not (gui and gui:IsA("LayerCollector")) then
		return nil
	end
	if not gui.Enabled then
		return false
	end
	local panel = panelOf(gui)
	if panel and panel:IsA("GuiObject") then
		if not panel.Visible then
			return false
		end
		local scale = panel:FindFirstChildWhichIsA("UIScale")
		if scale and scale.Scale < 0.02 then
			return false
		end
	end
	return true
end

--- Drops listed menus that are no longer on screen. Returns what it dropped.
local function prune(): { string }
	local dropped = {}
	local now = os.clock()
	for name, openedAt in openMenus do
		if now - openedAt > HudSlide.OPEN_GRACE and menuShown(name) == false then
			openMenus[name] = nil
			table.insert(dropped, name)
		end
	end
	return dropped
end

local pending = false

--- Deferred, so a close-then-open (an exclusive menu switch) in the same frame
--- reads as "still a menu open" and the HUD doesn't bounce.
local function evaluate(why: string)
	if pending then
		return
	end
	pending = true
	task.defer(function()
		pending = false
		local dropped = prune()
		if #dropped > 0 then
			why ..= " (dropped, no longer shown: " .. table.concat(dropped, ",") .. ")"
		end
		local any = next(openMenus) ~= nil
		if any ~= isOut then
			isOut = any
			apply()
			mirror((isOut and "out: " or "in: ") .. why)
		else
			mirror()
		end
	end)
end

local function keepsHud(menuName: string): boolean
	local gui = playerGui and playerGui:FindFirstChild(menuName)
	return gui ~= nil and flagged(gui, "KeepHud")
end

-- ================================================================ new HUD while out

local function watchGui(gui: Instance)
	if watchedGuis[gui] or not gui:IsA("LayerCollector") then
		return
	end
	watchedGuis[gui] = true
	-- New elements arrive in the gui, or in its ScreenFit (Scale moves them
	-- there a frame later), so both containers are watched.
	local function watchContainer(container: Instance)
		container.ChildAdded:Connect(function(child)
			if child.Name == "ScreenFit" and child:IsA("GuiObject") then
				watchContainer(child)
				return
			end
			if isOut then
				task.defer(function()
					if child.Parent == container and eligible(child) then
						slideOut(child, true)
					end
				end)
			end
		end)
	end
	watchContainer(gui)
	local fit = gui:FindFirstChild("ScreenFit")
	if fit and fit:IsA("GuiObject") then
		watchContainer(fit)
	end
end

local function onTagged(inst: Instance)
	if not (playerGui and inst:IsDescendantOf(playerGui)) then
		return
	end
	watchGui(inst)
	if isOut then
		-- A whole HUD arriving while a menu is open (e.g. respawn): out at once.
		task.defer(function()
			if inst:IsA("LayerCollector") then
				for _, child in topLevel(inst) do
					if eligible(child) then
						slideOut(child, true)
					end
				end
			elseif eligible(inst) then
				slideOut(inst, true)
			end
		end)
	end
end

-- ================================================================ public

function HudSlide.IsOut(): boolean
	return isOut
end

--- The menus HudSlide currently believes are open.
function HudSlide.OpenMenus(): { string }
	local names = {}
	for name in openMenus do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

--- Re-checks everything now, e.g. after tagging something by hand.
function HudSlide.Refresh()
	evaluate("refresh")
end

function HudSlide.Start()
	if started then
		return
	end
	started = true

	task.spawn(function()
		playerGui = player:WaitForChild("PlayerGui")

		for _, inst in CollectionService:GetTagged(HudSlide.TAG) do
			if inst:IsDescendantOf(playerGui) then
				watchGui(inst)
			end
		end
		CollectionService:GetInstanceAddedSignal(HudSlide.TAG):Connect(onTagged)

		MenuController.Opened:Connect(function(name: string)
			if not keepsHud(name) then
				openMenus[name] = os.clock()
				evaluate("opened " .. name)
			end
		end)
		MenuController.Closed:Connect(function(name: string)
			if openMenus[name] then
				openMenus[name] = nil
				evaluate("closed " .. name)
			end
		end)

		-- The safety net: while the HUD is out, keep checking that a menu is
		-- really still up, so a missed Closed can't strand it.
		task.spawn(function()
			while true do
				task.wait(HudSlide.RECHECK)
				if isOut then
					evaluate("recheck")
				end
			end
		end)

		mirror("ready")
		print(("[HudSlide] watching %d tagged HUD root(s)"):format(#CollectionService:GetTagged(HudSlide.TAG)))
	end)
end

return HudSlide
