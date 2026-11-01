--!nonstrict
--[[
	ReplicatedStorage/MenuSystem/Menus/Effects

	Idle motion and entrances for any GuiObject in PlayerGui, driven by
	attributes. The Framewisp juice runtime, ported into MenuSystem: one module
	watching the whole PlayerGui instead of a script copied into every ScreenGui.

	TRIGGERS  — a TAG or an ATTRIBUTE, whichever suits; both do the same thing
	  Idle        FxPulse  FxWiggle  FxShake  FxJelly  FxGlow  FxRays  FxPixels  FxGleam
	  Entrances   FxPop  FxCascade  FxReveal  FxSwing  FxDrop
	  As a tag:        tag the element "FxPulse" (CollectionService / Tag Editor)
	  As an attribute: FxPulse = true — or FigmaPulse, so Framewisp exports keep working
	  A tag gives the effect its defaults; tune it with the attributes below either way.
	  FxDrop beside FxPop: Drop wins, the two would fight over the same scale.
	  FxIgnore (tag or attribute) on an element, or on its ScreenGui, opts it out.

	TUNING  (FxName, then Name, then FigmaName — the first one found wins)
	  Pulse    PulseSpeed 1   PulseAmp 5 (%)
	  Jelly    JellySpeed 1.2   JellyAmp 3 (deg)
	  Wiggle   WiggleEvery 4 (s)   WiggleAngle 12 (deg)
	  Rays     RaysSpeed 25 (deg/s)   RaysPulse 6 (%)
	  Shake    ShakeEvery 3 (s)   ShakeTime 0.5 (s)   ShakeAmp 6 (px)
	  Glow     GlowColor (Color3 or 0xRRGGBB)   GlowSpeed 0.8   GlowSize 12 (px)
	           GlowSW / GlowSH 1 (ring scale)   GlowRot 0 (deg)   GlowRad 0 (ring corner, scale)
	  Pixels   PixColor   PixAlpha 0.35   PixCell 14 (px)   PixRate 8 (/s)   PixVary 0
	  Gleam    GleamWidth 0.22   GleamSpeed 0.8 (s)   GleamCooldown 2 (s)
	  Pop      PopFrom 0.8   PopTime 0.3 (s)
	  Cascade  CascadeGap 70 (ms)
	  Reveal   RevealTime 0.7   RevealAngle 35   RevealDir 0 (deg)   RevealFrom 0.55
	  Swing    SwingTime 1.2   SwingAngle 20   SwingCount 4   SwingFrom 0.5
	  Drop     DropHeight 160 (px)   DropTime 0.6   DropBounce 12 (%)   DropSquash 10 (%)
	           DropFade 1   DropDelay 0   DropKids 0   DropStep 0.06   DropSound 0 (asset id)
	  Idle effects read their tuning every frame, so they can be tuned live in Play.

	WHEN ENTRANCES PLAY
	  Whenever the element becomes visible to the player: every ancestor Visible
	  AND its ScreenGui Enabled. MenuSystem opens a menu by enabling its
	  ScreenGui, so entrances replay on every open. Effects.Play(el) replays them
	  by hand. Idle effects pause while their element is hidden.

	SHARED SCALE AND ROTATION
	  Roblox honours one UIScale per object, and ButtonBounce, menu motion and
	  these effects all want it. Effects keeps named channels and writes their
	  product once. Anyone else writing UIScale.Scale or Rotation directly is
	  taken as the base and the channels ride on top of it, so ButtonBounce and
	  menu motion need no changes. Other modules can join in:
	      Effects.SetScale(el, "myKey", 1.1)
	      Effects.SetRotation(el, "myKey", 5)

	LAYOUTS
	  An entrance or shake on an element whose parent has a layout needs room to
	  move, so the element is wrapped once in a transparent "<Name>_FxSlot" that
	  takes its place, mirrors its Visible and LayoutOrder, and unwraps itself if
	  the element is moved elsewhere. Look such elements up by attribute, or with
	  FindFirstChild(name, true), rather than as a direct child of the layout.
	  Elements not in a layout are animated in place, with no wrapper.

	CLONES
	  Wiring is tracked in tables, not attributes, so a template cloned after it
	  was wired is wired fresh and its entrance still plays. Helper instances
	  copied along with a clone are cleared and rebuilt, and a clone taken
	  mid-animation is put back to its resting geometry.

	LOADING SCREENS
	  Tag your loading screen FxBlocker (or set the attribute FxBlocker = true)
	  — the ScreenGui itself, or the frame that gets hidden or destroyed when
	  loading ends. While any blocker is on screen, entrances are FROZEN on
	  their first frame: a drop waits lifted and faded out, a pop waits small.
	  The moment the last blocker is disabled, hidden or destroyed, they all
	  play. A blocker left up for more than 20 s is ignored, with a warning, so
	  a forgotten one can't freeze the UI for good.
	  From code instead: Effects.Hold("Intro") ... Effects.Release("Intro").

	REDUCED MOTION
	  Effects.SetReduced(true) stops idle motion and skips entrances.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)

local Effects = {}

local IDLE_KINDS = { "Pulse", "Wiggle", "Shake", "Jelly", "Glow", "Rays", "Pixels", "Gleam" }
local ENTRANCE_KINDS = { "Pop", "Cascade", "Reveal", "Swing", "Drop" }

local started = false
local reduced = false
local playerGui: Instance? = nil

local weak = { __mode = "k" }
local entries = {}                            -- everything ticking
local owned = setmetatable({}, weak)          -- instances Effects created
local wired = setmetatable({}, weak)          -- elements already set up
local dead = setmetatable({}, weak)           -- destroyed elements
local entrances = setmetatable({}, weak)      -- el -> { Kind = play }
local watchers = setmetatable({}, weak)       -- el -> visibility watcher
local visible = setmetatable({}, weak)        -- el -> cached shown()
local rest = setmetatable({}, weak)           -- el -> resting geometry during a pose
local active = setmetatable({}, weak)         -- el -> poses in flight
local scaleState = setmetatable({}, weak)
local rotState = setmetatable({}, weak)

local BLOCK_TIMEOUT = 20                      -- seconds before a stuck blocker is ignored
local blockers = setmetatable({}, weak)       -- loading screens etc. (FxBlocker)
local holds = {}                              -- Effects.Hold keys
local frozen = false                          -- entrances wait on their first frame
local frozenSince = 0
local gaveUp = false

-- ================================================================ attributes

local function raw(el: Instance, name: string): any
	local v = el:GetAttribute("Fx" .. name)
	if v == nil then
		v = el:GetAttribute(name)
	end
	if v == nil then
		v = el:GetAttribute("Figma" .. name)
	end
	return v
end

local function num(el: Instance, name: string, default: number): number
	local v = raw(el, name)
	if type(v) == "number" then
		return v
	end
	if type(v) == "boolean" then
		return v and 1 or 0
	end
	return default
end

local function colour(el: Instance, name: string, default: Color3): Color3
	local v = raw(el, name)
	if typeof(v) == "Color3" then
		return v
	end
	if type(v) == "number" then
		return Color3.fromRGB(math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256)
	end
	return default
end

--- Triggers only take the Fx or Figma prefix: a bare "Glow" or "Drop" is too
--- likely to mean something else in another system. A tag "FxName" counts the
--- same as the attribute.
local function flag(el: Instance, name: string): boolean
	if el:HasTag("Fx" .. name) then
		return true
	end
	local v = el:GetAttribute("Fx" .. name)
	if v == nil then
		v = el:GetAttribute("Figma" .. name)
	end
	return v ~= nil and v ~= false
end

local function own<T>(inst: T): T
	owned[inst] = true;
	(inst :: any):SetAttribute("FxOwned", true)
	return inst
end

local function warnFor(el: Instance, err: any)
	warn(("[Effects] %s: %s"):format(el:GetFullName(), tostring(err)))
end

-- ================================================================ visibility

--- Visible to the PLAYER: every ancestor counts, and so does the ScreenGui's
--- Enabled, which is how MenuSystem opens and closes menus.
local function shown(el: Instance): boolean
	local n = el
	while n do
		if n:IsA("GuiObject") then
			if not n.Visible then
				return false
			end
		elseif n:IsA("LayerCollector") then
			return n.Enabled and playerGui ~= nil and n:IsDescendantOf(playerGui)
		end
		n = n.Parent
	end
	return false
end

--- Is anything (a loading screen, an Effects.Hold) still covering the UI?
local function isBlocked(): boolean
	if next(holds) then
		return true
	end
	for b in blockers do
		if b.Parent and playerGui and b:IsDescendantOf(playerGui) then
			if b:IsA("LayerCollector") then
				if b.Enabled then
					return true
				end
			elseif shown(b) then
				return true
			end
		end
	end
	return false
end

local function updateFrozen()
	local blocked = isBlocked()
	if not blocked then
		frozen, gaveUp = false, false
		return
	end
	if gaveUp then
		return
	end
	if not frozen then
		frozen = true
		frozenSince = os.clock()
	elseif os.clock() - frozenSince > BLOCK_TIMEOUT then
		frozen, gaveUp = false, true
		warn(("[Effects] a blocker has been up for %ds — playing entrances anyway. Hide or destroy the FxBlocker when loading ends."):format(BLOCK_TIMEOUT))
	end
end

local function considerBlocker(inst: Instance)
	if inst:HasTag("FxBlocker") or inst:GetAttribute("FxBlocker") == true then
		blockers[inst] = true
		updateFrozen()
	end
end

local function playEntrances(el: Instance)
	local list = entrances[el]
	if not list then
		return
	end
	for _, play in list do
		local ok, err = pcall(play)
		if not ok then
			warnFor(el, err)
		end
	end
end

--- One watcher per element, rebuilt when its ancestry changes, torn down when
--- it is destroyed. Fires the entrances on every hidden -> shown transition.
local function watch(el: GuiObject)
	if watchers[el] then
		return watchers[el]
	end
	local w = { conns = {}, was = false }
	watchers[el] = w

	function w.check()
		local now = shown(el)
		visible[el] = now
		if now and not w.was then
			playEntrances(el)
		end
		w.was = now
	end

	local function rebuild()
		for _, c in w.conns do
			c:Disconnect()
		end
		table.clear(w.conns)
		local n = el
		while n do
			if n:IsA("GuiObject") then
				table.insert(w.conns, n:GetPropertyChangedSignal("Visible"):Connect(w.check))
			elseif n:IsA("LayerCollector") then
				table.insert(w.conns, n:GetPropertyChangedSignal("Enabled"):Connect(w.check))
				break
			end
			n = n.Parent
		end
	end

	rebuild()
	w.ancestry = el.AncestryChanged:Connect(function()
		rebuild()
		w.check()
	end)

	function w.stop()
		for _, c in w.conns do
			c:Disconnect()
		end
		table.clear(w.conns)
		w.ancestry:Disconnect()
	end

	return w
end

-- ================================================================ channels

local function productOf(s): number
	local p = s.base
	for _, v in s.ch do
		p *= v
	end
	return p
end

--- The element's one UIScale, shared. An existing UIScale is adopted, not
--- replaced, so ButtonBounce and menu motion keep theirs.
local function scaleOf(el: GuiObject)
	local s = scaleState[el]
	if s and s.host.Parent == el then
		return s
	end

	local host = el:FindFirstChildWhichIsA("UIScale")
	local base
	if host and host:GetAttribute("FxOwned") and not owned[host] then
		-- Ours, copied along with a clone, possibly mid-pulse: start it clean.
		own(host)
		base = 1
	elseif host then
		local saved = host:GetAttribute("FxScaleBase")
		base = type(saved) == "number" and saved or host.Scale
	else
		host = own(Instance.new("UIScale"))
		host.Name = "FxScale"
		host.Parent = el
		base = 1
	end

	s = { host = host, base = base, ch = {}, last = base }
	scaleState[el] = s
	host:SetAttribute("FxScaleBase", base)

	-- A write that isn't ours is someone else's factor: it becomes the base,
	-- and the channels are applied on top of it straight away.
	host:GetPropertyChangedSignal("Scale"):Connect(function()
		if scaleState[el] ~= s then
			return
		end
		local now = host.Scale
		if math.abs(now - s.last) > 1e-4 then
			s.base = now
			host:SetAttribute("FxScaleBase", now)
			local p = productOf(s)
			s.last = p
			if math.abs(p - now) > 1e-6 then
				host.Scale = p
			end
		end
	end)

	return s
end

local function setScale(el: GuiObject, key: string, value: number)
	local s = scaleOf(el)
	if math.abs(value - 1) < 1e-6 then
		if s.ch[key] == nil then
			return
		end
		s.ch[key] = nil
	else
		s.ch[key] = value
	end
	local p = productOf(s)
	s.last = p
	s.host.Scale = p
end

local function rotOf(el: GuiObject)
	local r = rotState[el]
	if r then
		return r
	end
	local saved = el:GetAttribute("FxRotBase") -- copied with a clone: survives a mid-wiggle copy
	local base = type(saved) == "number" and saved or el.Rotation
	r = { base = base, ch = {}, last = base }
	rotState[el] = r
	el:SetAttribute("FxRotBase", base)

	el:GetPropertyChangedSignal("Rotation"):Connect(function()
		local now = el.Rotation
		if math.abs(now - r.last) > 1e-3 then
			r.base = now
			el:SetAttribute("FxRotBase", now)
			local sum = 0
			for _, v in r.ch do
				sum += v
			end
			r.last = now + sum
			if sum ~= 0 then
				el.Rotation = r.last
			end
		end
	end)
	return r
end

local function setRotation(el: GuiObject, key: string, deg: number)
	local r = rotOf(el)
	if deg == 0 then
		if r.ch[key] == nil then
			return
		end
		r.ch[key] = nil
	else
		r.ch[key] = deg
	end
	local sum = 0
	for _, v in r.ch do
		sum += v
	end
	r.last = r.base + sum
	el.Rotation = r.last
end

-- ================================================================ geometry

local function hasLayout(parent: Instance?): boolean
	return parent ~= nil and parent:FindFirstChildWhichIsA("UIGridStyleLayout") ~= nil
end

local slotWired = setmetatable({}, weak)

local function attachSlot(slot: Frame, el: GuiObject)
	if slotWired[slot] then
		return
	end
	slotWired[slot] = true
	local conns = {}
	slot.Visible = el.Visible
	slot.LayoutOrder = el.LayoutOrder
	table.insert(conns, el:GetPropertyChangedSignal("Visible"):Connect(function()
		slot.Visible = el.Visible
	end))
	table.insert(conns, el:GetPropertyChangedSignal("LayoutOrder"):Connect(function()
		slot.LayoutOrder = el.LayoutOrder
	end))
	table.insert(conns, slot.ChildRemoved:Connect(function(child)
		if child ~= el then
			return
		end
		for _, c in conns do
			c:Disconnect()
		end
		-- Moved out by something else (a controller parking its template):
		-- hand back its own geometry, then the empty slot goes.
		pcall(function()
			el.Size = slot.Size
			el.Position = slot.Position
			el.AnchorPoint = slot.AnchorPoint
		end)
		rest[el] = nil
		slot:Destroy()
	end))
end

--- Wraps the element only when a layout would otherwise fight its motion.
local function slotFor(el: GuiObject): Frame?
	local p = el.Parent
	if not p then
		return nil
	end
	if p:GetAttribute("FxSlot") then
		own(p) -- a slot copied with a clone is adopted, not doubled
		attachSlot(p :: Frame, el)
		return p :: Frame
	end
	if not hasLayout(p) then
		return nil
	end

	local slot = own(Instance.new("Frame"))
	slot.Name = el.Name .. "_FxSlot"
	slot.BackgroundTransparency = 1
	slot.Size = el.Size
	slot.Position = el.Position -- the wrapper stands exactly where the element stood
	slot.AnchorPoint = el.AnchorPoint
	slot.ZIndex = el.ZIndex
	slot.LayoutOrder = el.LayoutOrder
	slot.SizeConstraint = el.SizeConstraint
	slot.AutomaticSize = el.AutomaticSize
	slot:SetAttribute("FxSlot", true)
	slot.Parent = p

	el.Size = UDim2.fromScale(1, 1)
	el.Position = UDim2.fromScale(0.5, 0.5)
	el.AnchorPoint = Vector2.new(0.5, 0.5)
	el.Parent = slot
	attachSlot(slot, el)
	return slot
end

--- Captures the resting geometry for the first pose in flight. Stored in
--- attributes too, so a clone taken mid-animation can be put back.
local function beginPose(el: GuiObject)
	local n = (active[el] or 0) + 1
	active[el] = n
	if n == 1 or not rest[el] then
		local savedSize = el:GetAttribute("FxRestSize")
		local savedPos = el:GetAttribute("FxRestPos")
		local r = {
			size = typeof(savedSize) == "UDim2" and savedSize or el.Size,
			pos = typeof(savedPos) == "UDim2" and savedPos or el.Position,
			anchor = el.AnchorPoint,
		}
		rest[el] = r
		el:SetAttribute("FxRestSize", r.size)
		el:SetAttribute("FxRestPos", r.pos)
	end
	return rest[el]
end

local function endPose(el: GuiObject)
	local n = (active[el] or 1) - 1
	if n > 0 then
		active[el] = n
		return
	end
	active[el] = nil
	local r = rest[el]
	if r then
		el.Size = r.size
		el.Position = r.pos
	end
	el:SetAttribute("FxRestSize", nil)
	el:SetAttribute("FxRestPos", nil)
end

--- The resting box in pixels, from the parent rather than the element, so it
--- stays steady while the element itself is being squashed.
local function box(el: GuiObject, r): (number, number)
	local parent = el.Parent
	local pw, ph = 0, 0
	if parent and parent:IsA("GuiBase2d") then
		pw, ph = parent.AbsoluteSize.X, parent.AbsoluteSize.Y
	end
	return r.size.X.Scale * pw + r.size.X.Offset, r.size.Y.Scale * ph + r.size.Y.Offset
end

--- The resting box scaled about its centre (whatever its AnchorPoint) and
--- nudged by dx, dy pixels.
local function posePx(el: GuiObject, r, kx: number, ky: number, dx: number, dy: number)
	local w, h = box(el, r)
	local sz, po, a = r.size, r.pos, r.anchor
	el.Size = UDim2.new(sz.X.Scale * kx, sz.X.Offset * kx, sz.Y.Scale * ky, sz.Y.Offset * ky)
	el.Position = po + UDim2.fromOffset((0.5 - a.X) * w * (1 - kx) + dx, (0.5 - a.Y) * h * (1 - ky) + dy)
end

--- Design px -> rendered px, for exports that record their design height.
local function pxScale(el: Instance): number
	local gui = el:FindFirstAncestorWhichIsA("LayerCollector")
	if not gui then
		return 1
	end
	local designH = gui:GetAttribute("BB_DesignH")
	local root = gui:FindFirstChildWhichIsA("GuiObject")
	if type(designH) == "number" and designH > 0 and root and root.AbsoluteSize.Y > 1 then
		return root.AbsoluteSize.Y / designH
	end
	return 1
end

local function backOut(p: number, c1: number?): number
	local c = c1 or 1.70158
	return 1 + (c + 1) * (p - 1) ^ 3 + c * (p - 1) ^ 2
end

local function addEntry(e)
	table.insert(entries, e)
	return e
end

-- ================================================================ pop / cascade

local popLive = setmetatable({}, weak)

local function startPop(el: GuiObject, from: number, time: number, delay: number?)
	if reduced then
		setScale(el, "pop", 1)
		return
	end
	local e = popLive[el]
	if not e then
		e = { kind = "pop", el = el }
		popLive[el] = e
	end
	e.t = -(delay or 0)
	e.T = math.max(0.02, time)
	e.from = from
	setScale(el, "pop", from)
	if not e.on then
		e.on = true
		addEntry(e)
	end
end

local function popPlayer(el: GuiObject)
	return function()
		startPop(el, num(el, "PopFrom", 0.8), num(el, "PopTime", 0.3))
	end
end

local function cascadeIn(el: GuiObject)
	local gap = num(el, "CascadeGap", 70) / 1000

	-- A card is something you CLICK, not decoration that animates.
	local function cardish(c: Instance): boolean
		return c:IsA("GuiButton") or c:GetAttribute("FigmaAction") ~= nil
	end

	local kids, actors = {}, {}
	local function sweep(host: Instance, depth: number)
		for _, c in host:GetChildren() do
			if c:IsA("GuiObject") then
				local target = c
				if c:GetAttribute("FxSlot") then
					target = c:FindFirstChildWhichIsA("GuiObject") -- a slot stands in for its element
				elseif owned[c] then
					target = nil
				end
				if target then
					if depth == 0 then
						table.insert(kids, target)
					end
					if cardish(target) then
						table.insert(actors, target)
					elseif depth < 3 then
						sweep(target, depth + 1) -- a plain container is not a card: look inside it
					end
				end
			end
		end
	end
	sweep(el, 0)

	if #actors > 1 then
		kids = actors -- stagger the CARDS, not the plate behind them
	end
	if #kids == 0 then
		startPop(el, 0.8, 0.3) -- nothing to stagger: at least make it arrive
		return
	end
	if #kids == 1 and #kids[1]:GetChildren() > 1 then
		local n = kids[1].Name
		if n:sub(-7) == "Content" or n:sub(-4) == "Mask" or n:sub(-6) == "Masked" then
			return cascadeIn(kids[1])
		end
	end

	local laid = false -- design order; a layout's own order still wins
	for _, c in kids do
		if c.LayoutOrder ~= 0 then
			laid = true
			break
		end
	end
	if laid then
		table.sort(kids, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
	end
	for i, c in kids do
		startPop(c, 0.001, 0.35, (i - 1) * gap)
	end
end

local function cascadePlayer(el: GuiObject)
	return function()
		if not reduced then
			cascadeIn(el)
		end
	end
end

-- ================================================================ swing / reveal

local function swingPlayer(el: GuiObject)
	slotFor(el)
	local e = { kind = "swing", el = el }
	return function()
		if reduced then
			return
		end
		e.t = 0
		e.T = math.max(0.02, num(el, "SwingTime", 1.2))
		e.A = num(el, "SwingAngle", 20)
		e.n = num(el, "SwingCount", 4)
		e.from = num(el, "SwingFrom", 0.5)
		if not e.on then
			e.on = true
			e.r = beginPose(el)
			addEntry(e)
		end
	end
end

local function revealPlayer(el: GuiObject)
	slotFor(el)
	local e = { kind = "reveal", el = el }
	return function()
		if reduced then
			return
		end
		e.t = 0
		e.T = math.max(0.02, num(el, "RevealTime", 0.7))
		e.A = math.rad(num(el, "RevealAngle", 35))
		e.dir = math.rad(num(el, "RevealDir", 0))
		e.from = num(el, "RevealFrom", 0.55)
		if not e.on then
			e.on = true
			e.r = beginPose(el)
			addEntry(e)
		end
	end
end

-- ================================================================ drop

local DROP_FADE = {
	ImageLabel = { "ImageTransparency", "BackgroundTransparency" },
	ImageButton = { "ImageTransparency", "BackgroundTransparency" },
	TextLabel = { "TextTransparency", "BackgroundTransparency", "TextStrokeTransparency" },
	TextButton = { "TextTransparency", "BackgroundTransparency", "TextStrokeTransparency" },
	TextBox = { "TextTransparency", "BackgroundTransparency" },
	Frame = { "BackgroundTransparency" },
	ScrollingFrame = { "BackgroundTransparency" },
	CanvasGroup = { "GroupTransparency" },
	UIStroke = { "Transparency" },
}

--- Read ONCE: a replay mid-fade must not take a faded value for the resting one.
local function dropParts(root: Instance)
	local parts = {}
	local function add(inst: Instance)
		for _, prop in DROP_FADE[inst.ClassName] or {} do
			local ok, value = pcall(function()
				return (inst :: any)[prop]
			end)
			if ok and type(value) == "number" then
				table.insert(parts, { inst = inst, prop = prop, rest = value })
			end
		end
	end
	add(root)
	local function under(inst: Instance)
		for _, c in inst:GetChildren() do
			-- An arrow or a card shows and hides itself: never faded from here.
			if not (c:GetAttribute("FigmaPointer") or c:GetAttribute("FigmaCard")) then
				add(c)
				under(c)
			end
		end
	end
	under(root)
	return parts
end

local function dropAlpha(parts, a: number)
	for _, part in parts do
		if part.inst.Parent then
			pcall(function()
				part.inst[part.prop] = part.rest + (1 - part.rest) * (1 - a)
			end)
		end
	end
end

--- y px (up is negative), scale x, scale y, alpha.
local function dropAt(t: number, H: number, T: number, bounce: number, squash: number, fade: boolean)
	local Tf = 0.55 * T
	local Tb = math.max(0.1, T - Tf - 0.08)
	if t < 0 then
		return -H, 1, 1, fade and 0 or 1
	end
	local y, q = 0, 0
	if t < Tf then
		local p = t / Tf
		y = -H * (1 - p * p) -- speeds up like a weight
	elseif t < Tf + 0.08 then
		q = math.sin((t - Tf) / 0.08 * math.pi / 2) -- squashes where it lands
	else
		local r = t - Tf - 0.08
		y = -H * bounce * math.sin(math.pi * math.min(1, r / Tb)) -- one soft bounce
		local x = math.min(1, r / 0.2)
		q = 1 - (1 + 3.2 * (x - 1) ^ 3 + 2.2 * (x - 1) ^ 2) -- a small stretch, then rest
	end
	return y, 1 + 0.6 * squash * q, 1 - squash * q, fade and math.min(1, t / (0.3 * Tf)) or 1
end

local function dropLen(T: number): number
	local Tf = 0.55 * T
	return Tf + 0.08 + math.max(math.max(0.1, T - Tf - 0.08), 0.2)
end

--- The element itself, or its children in reading order. A shadow rides with
--- the label it belongs to: "XShadow" with "X", and MenuSystem's "Shadow"
--- with its sibling "Title" or "Label".
local function dropTargets(el: GuiObject)
	if num(el, "DropKids", 0) < 0.5 then
		return { { el } }
	end
	local kids, byName = {}, {}
	for _, c in el:GetChildren() do
		local target = c
		if c:GetAttribute("FxSlot") then
			target = c:FindFirstChildWhichIsA("GuiObject")
		elseif owned[c] then
			target = nil
		end
		if target and target:IsA("GuiObject") and target.Visible
			and target.Name ~= "Background" and target.Name ~= "TextureClip" then
			table.insert(kids, target)
			byName[target.Name] = target
		end
	end

	local laid = el:FindFirstChildWhichIsA("UIGridStyleLayout") ~= nil
	local main, shadows = {}, {}
	for i, c in kids do
		local base
		if c.Name == "Shadow" then
			base = byName.Title or byName.Label
		elseif c.Name:sub(-6) == "Shadow" then
			base = byName[c.Name:sub(1, -7)]
		end
		if base and base ~= c then
			shadows[base] = shadows[base] or {}
			table.insert(shadows[base], c)
		else
			table.insert(main, { c = c, i = i })
		end
	end

	local measured = el.AbsoluteSize.Y > 1
	local function at(c: GuiObject, axis: string): number
		if measured then
			return c.AbsolutePosition[axis]
		end
		return c.Position[axis].Scale * 1e4 + c.Position[axis].Offset
	end
	table.sort(main, function(a, b)
		if laid then
			if a.c.LayoutOrder ~= b.c.LayoutOrder then
				return a.c.LayoutOrder < b.c.LayoutOrder
			end
			return a.i < b.i
		end
		local ay, by = at(a.c, "Y"), at(b.c, "Y")
		if math.abs(ay - by) > 1 then
			return ay < by -- reading order: top to bottom, then left to right
		end
		local ax, bx = at(a.c, "X"), at(b.c, "X")
		if ax ~= bx then
			return ax < bx
		end
		return a.i < b.i
	end)

	local out = {}
	for _, m in main do
		local group = { m.c }
		for _, s in shadows[m.c] or {} do
			table.insert(group, s)
		end
		table.insert(out, group)
	end
	if #out == 0 then
		return { { el } } -- flat: nothing inside to stagger, so it falls whole
	end
	return out
end

local function dropPlayer(el: GuiObject)
	local groups = nil
	local live = setmetatable({}, weak)
	return function()
		if reduced then
			return
		end
		groups = groups or dropTargets(el)
		local kidsMode = num(el, "DropKids", 0) >= 0.5
		local step = kidsMode and num(el, "DropStep", 0.06) or 0
		local delay = num(el, "DropDelay", 0)
		local T = math.max(0.1, num(el, "DropTime", 0.6))
		local H = num(el, "DropHeight", 160) * pxScale(el)
		local fade = num(el, "DropFade", 1) >= 0.5

		for i, group in groups do
			for gi, target in group do
				if target.Parent then
					local e = live[target]
					if not e then
						slotFor(target)
						e = { kind = "drop", el = target, src = el, parts = dropParts(target), voice = (i == 1 and gi == 1) }
						live[target] = e
					end
					e.t = -(delay + (i - 1) * step)
					e.T, e.H, e.fade = T, H, fade
					e.bounce = num(el, "DropBounce", 12) / 100
					e.squash = num(el, "DropSquash", 10) / 100
					e.sound = num(el, "DropSound", 0)
					e.landed = false
					if not e.on then
						e.on = true
						e.r = beginPose(target)
						addEntry(e)
					end
					posePx(target, e.r, 1, 1, 0, -H) -- the first pose now: no frame shows it at rest
					if fade then
						dropAlpha(e.parts, 0)
					end
				end
			end
		end
	end
end

-- ================================================================ glow

local function wireGlow(el: GuiObject)
	local host: GuiObject = el
	local sw, sh, rot = num(el, "GlowSW", 1), num(el, "GlowSH", 1), num(el, "GlowRot", 0)
	if math.abs(sw - 1) > 0.001 or math.abs(sh - 1) > 0.001 or math.abs(rot) > 0.05 then
		local ring = own(Instance.new("Frame"))
		ring.Name = "FxGlowRing"
		ring.BackgroundTransparency = 1
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(sw, sh)
		ring.Rotation = rot
		local rad = num(el, "GlowRad", 0)
		if rad > 0 then
			local uc = Instance.new("UICorner")
			uc.CornerRadius = UDim.new(rad, 0)
			uc.Parent = ring
		end
		ring.Parent = el
		host = ring
	end

	-- A glow stroke an export made for this is reused; a DESIGNED border never is.
	local stroke, frac = nil, false
	for _, c in host:GetChildren() do
		if c:IsA("UIStroke") and c:GetAttribute("FW_Owned") == true then
			stroke = c
			frac = c:GetAttribute("FW_StrokeScaled") == true
			break
		end
	end
	if not stroke then
		stroke = own(Instance.new("UIStroke"))
		stroke.Name = "FxGlow"
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- on text, Contextual would outline the glyphs
		stroke.Color = colour(el, "GlowColor", WHITE)
		stroke.Thickness = 0
		stroke.Parent = host
	end
	addEntry({ kind = "glow", idle = true, el = el, stroke = stroke, base = stroke.Thickness, frac = frac, t = math.random() * 7 })
end

-- ================================================================ pixels

local function wirePixels(el: GuiObject)
	local wrap = own(Instance.new("Frame"))
	wrap.Name = "FxPixels"
	wrap.BackgroundTransparency = 1
	wrap.Size = UDim2.fromScale(1, 1)
	wrap.ClipsDescendants = true
	local corner = el:FindFirstChildWhichIsA("UICorner")
	if corner then
		corner:Clone().Parent = wrap
	end
	local top = el.ZIndex
	for _, d in el:GetChildren() do
		if d:IsA("GuiObject") and d.ZIndex > top then
			top = d.ZIndex
		end
	end
	wrap.ZIndex = top + 1 -- the mosaic draws OVER the layer's contents
	wrap.Parent = el

	local e = { kind = "pixels", idle = true, el = el, t = 0, cells = {}, acc = 0, cw = 0, ch = 0 }

	-- Built from the real box, and rebuilt when it changes, so cells stay square.
	local function build()
		for _, c in e.cells do
			c:Destroy()
		end
		table.clear(e.cells)
		local w, h = el.AbsoluteSize.X, el.AbsoluteSize.Y
		if w <= 2 or h <= 2 then
			return
		end
		local col = colour(el, "PixColor", WHITE)
		local cellPx = math.max(1, num(el, "PixCell", 14)) * pxScale(el)
		local k = math.max(1, math.ceil(math.sqrt((math.ceil(w / cellPx) * math.ceil(h / cellPx)) / 1600)))
		local cw = cellPx * k
		e.cw, e.ch = cw / w, cw / h
		local y = 0
		while y < h do
			local x = 0
			while x < w do
				local f = Instance.new("Frame")
				f.BorderSizePixel = 0
				f.BackgroundColor3 = col
				f.BackgroundTransparency = 1
				f.AnchorPoint = Vector2.new(0.5, 0.5)
				f.Size = UDim2.fromScale(e.cw, e.ch)
				f.Position = UDim2.fromScale((x + cw / 2) / w, (y + cw / 2) / h)
				f.ZIndex = wrap.ZIndex
				f.Parent = wrap
				table.insert(e.cells, f)
				x += cw
			end
			y += cw
		end
	end

	build()
	local pending = false
	el:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if pending then
			return
		end
		pending = true
		task.delay(0.3, function()
			pending = false
			if el.Parent and wrap.Parent then
				build()
			end
		end)
	end)
	addEntry(e)
end

-- ================================================================ gleam

local GLEAM_TILT = -14
local GLEAM_TAN = 0.25 -- tan(14 deg): below this aspect the tilt eats the sweep
local warnedSheen = setmetatable({}, weak)

local function gleamSeq(w: number, peak: number?): NumberSequence
	local h = math.clamp(w * 0.5, 0.04, 0.46)
	if peak then
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5 - h, 1),
			NumberSequenceKeypoint.new(0.5, peak),
			NumberSequenceKeypoint.new(0.5 + h, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5 - h, 1),
		NumberSequenceKeypoint.new(0.5 - h * 0.4, 0.45),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.5 + h * 0.4, 0.45),
		NumberSequenceKeypoint.new(0.5 + h, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

--- Two white copies of the layer — a wide soft halo and a sharp core — each
--- masked by a moving gradient band. Shown only while the light travels.
local function gleamShine(el: GuiObject, w: number)
	local grads = {}
	local size = el.AbsoluteSize
	local tilt = (size.Y >= size.X * GLEAM_TAN) and GLEAM_TILT or 0
	local isText = el:IsA("TextLabel") or el:IsA("TextButton")

	-- Text keeps its glyph outline; prefer that over a box stroke.
	local st = nil
	for _, c in el:GetChildren() do
		if c:IsA("UIStroke") and not owned[c] then
			if not st or (isText and c.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual) then
				st = c
			end
		end
	end

	local function band(host: Instance, width: number, peak: number?)
		local g = own(Instance.new("UIGradient"))
		g.Transparency = gleamSeq(width, peak)
		g.Rotation = tilt
		g.Offset = Vector2.new(-2, 0)
		g.Parent = host
		table.insert(grads, g)
	end

	local function whiteCopy(z: number): GuiObject
		local ov
		if isText then
			local t = el :: TextLabel
			ov = Instance.new("TextLabel")
			ov.Text = t.Text
			ov.RichText = t.RichText
			ov.FontFace = t.FontFace
			ov.TextScaled = t.TextScaled
			ov.TextSize = t.TextSize
			ov.TextWrapped = t.TextWrapped
			ov.LineHeight = t.LineHeight
			ov.TextXAlignment = t.TextXAlignment
			ov.TextYAlignment = t.TextYAlignment
			ov.TextColor3 = WHITE
			ov.TextStrokeTransparency = 1
		elseif (el:IsA("ImageLabel") or el:IsA("ImageButton")) and not el:FindFirstChild(el.Name .. "_Sheen")
			and (el:FindFirstChildWhichIsA("UICorner") or num(el, "GleamBox", 0) >= 0.5 or num(el, "GleamCorner", -1) >= 0) then
			-- Roblox can only darken an image (ImageColor3 multiplies), so a "white" copy of
			-- coloured art is just the art again. With no _Sheen silhouette, a white box in
			-- the button's own shape gives a true white light instead.
			ov = Instance.new("Frame")
			ov.BackgroundColor3 = WHITE
			local radius = num(el, "GleamCorner", -1)
			if radius >= 0 and not el:FindFirstChildWhichIsA("UICorner") then
				local uc = Instance.new("UICorner")
				uc.CornerRadius = UDim.new(0, radius)
				uc.Parent = ov
			end
		elseif el:IsA("ImageLabel") or el:IsA("ImageButton") then
			local img = el :: ImageLabel
			ov = Instance.new("ImageLabel")
			-- The white silhouette an export made for this picture, if there is one.
			local sheen = el:FindFirstChild(el.Name .. "_Sheen")
			if sheen and sheen:IsA("ImageLabel") and sheen.Image ~= "" then
				ov.Image = sheen.Image
			else
				ov.Image = img.Image
				if not warnedSheen[el] then
					warnedSheen[el] = true
					warn(("[Effects] Gleam on '%s': no '%s_Sheen' white silhouette, so a tinted copy is used and the sweep may not show"):format(el.Name, el.Name))
				end
			end
			ov.ImageColor3 = WHITE
			ov.ScaleType = img.ScaleType
			ov.SliceCenter = img.SliceCenter
			ov.SliceScale = img.SliceScale
			ov.TileSize = img.TileSize
			ov.ImageRectOffset = img.ImageRectOffset
			ov.ImageRectSize = img.ImageRectSize
		else
			ov = Instance.new("Frame")
			ov.BackgroundColor3 = WHITE
		end
		ov.Name = "FxGleam"
		ov.Visible = false
		if not ov:IsA("Frame") then
			ov.BackgroundTransparency = 1
		end
		ov.Size = UDim2.fromScale(1, 1)
		ov.Position = UDim2.fromScale(0.5, 0.5)
		ov.AnchorPoint = Vector2.new(0.5, 0.5)
		ov.ZIndex = el.ZIndex + z
		own(ov)
		local corner = el:FindFirstChildWhichIsA("UICorner")
		if corner then
			corner:Clone().Parent = ov
		end
		ov.Parent = el
		return ov
	end

	local function whiteStroke(host: GuiObject, extra: number)
		local c = st and st:Clone() or Instance.new("UIStroke")
		for _, k in c:GetChildren() do
			k:Destroy() -- a stroke gradient measures in stroke space and would desync
		end
		c.Name = "FxGleamStroke"
		c.Color = WHITE
		pcall(function()
			c.BorderStrokePosition = Enum.BorderStrokePosition.Outer
		end)
		if host:IsA("TextLabel") then
			c.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual -- Border mode would box each letter
		end
		if st and st:GetAttribute("FW_StrokeScaled") then
			c.Thickness = st.Thickness * (extra > 0 and 1.7 or 1)
		else
			c.Thickness = (st and st.Thickness or 0) + extra
		end
		own(c)
		c.Parent = host
	end

	local halo = whiteCopy(1) -- wide and soft: Roblox has no blur, a fatter outline stands in
	if isText then
		whiteStroke(halo, 3)
	end
	band(halo, w * 1.6, 0.4)

	local core = whiteCopy(2)
	if st and isText then
		whiteStroke(core, 0)
	end
	band(core, w)
	return grads
end

local function wireGleam(el: GuiObject)
	local w = num(el, "GleamWidth", 0.22)
	if el:IsA("TextLabel") or el:IsA("TextButton") or el:IsA("ImageLabel") or el:IsA("ImageButton") then
		addEntry({ kind = "gleam", idle = true, el = el, t = 0, grads = gleamShine(el, w) })
	else
		-- A group: its letters may not exist yet, so they are collected on the first ticks.
		addEntry({ kind = "gleamGroup", idle = true, el = el, t = 0, parts = nil, waited = 0 })
	end
end

-- ================================================================ ticking

local idleScale, idleRot = {}, {}
local RUN = {}

RUN.pop = function(e)
	if e.t < 0 then
		return
	end
	local p = math.min(1, e.t / e.T)
	if p >= 1 then
		setScale(e.el, "pop", 1)
		return false
	end
	setScale(e.el, "pop", e.from + (1 - e.from) * backOut(p))
end

RUN.swing = function(e)
	local p = math.min(1, e.t / e.T)
	if p >= 1 then
		endPose(e.el)
		return false
	end
	local th = math.rad(e.A * math.exp(-4 * p) * math.cos(p * math.pi * 2 * e.n))
	local rise = math.min(1, e.t / (e.T * 0.3))
	local sc = e.from + (1 - e.from) * backOut(rise, 2.2)
	local _, h = box(e.el, e.r)
	posePx(e.el, e.r, sc, sc * math.abs(math.cos(th)), 0, -math.sin(th) * 0.09 * h)
end

RUN.reveal = function(e)
	local p = math.min(1, e.t / e.T)
	if p >= 1 then
		endPose(e.el)
		return false
	end
	local th = e.A * math.exp(-5 * p) * math.cos(p * math.pi * 5)
	local rise = math.min(1, e.t / (e.T * 0.45))
	local sc = e.from + (1 - e.from) * backOut(rise, 2.2)
	local fore = 1 - math.cos(th)
	local drift = math.sin(th) * 0.07
	local w, h = box(e.el, e.r)
	posePx(e.el, e.r,
		sc * (1 - fore * math.abs(math.sin(e.dir))),
		sc * (1 - fore * math.abs(math.cos(e.dir))),
		math.sin(e.dir) * drift * w,
		-math.cos(e.dir) * drift * h)
end

RUN.drop = function(e)
	local y, sx, sy, alpha = dropAt(e.t, e.H, e.T, e.bounce, e.squash, e.fade)
	local _, h = box(e.el, e.r)
	posePx(e.el, e.r, sx, sy, 0, y + (1 - sy) / 2 * h) -- the bottom edge stays put while it squashes
	dropAlpha(e.parts, alpha)

	if not e.landed and e.t >= 0.55 * e.T then
		e.landed = true
		if e.sound > 0 and e.voice then -- one landing sound per drop, not one per child
			local snd = e.src:FindFirstChild("FxDropSound")
			if not snd then
				snd = own(Instance.new("Sound"))
				snd.Name = "FxDropSound"
				snd.Parent = e.src
			end
			snd.SoundId = "rbxassetid://" .. string.format("%d", e.sound)
			pcall(function()
				SoundService:PlayLocalSound(snd)
			end)
		end
	end

	if e.t >= dropLen(e.T) then
		endPose(e.el)
		dropAlpha(e.parts, 1)
		return false
	end
end

RUN.pulse = function(e)
	local el = e.el
	local sp = num(el, "PulseSpeed", 1)
	local w = (1 - math.cos(e.t * math.pi * 2 * sp)) * 0.5
	local amp = num(el, "PulseAmp", 5) / 100
	-- UI lays out on whole pixels: a tiny pulse on a small element steps
	-- visibly, so it is given more travel (up to 10px) to move smoothly.
	local px = math.min(el.AbsoluteSize.X, el.AbsoluteSize.Y)
	if px > 1 and amp * px < 10 then
		amp = math.min(amp * 4, 10 / px)
	end
	idleScale[el] = (idleScale[el] or 1) * (1 + amp * w)
end

RUN.jelly = function(e)
	local el = e.el
	local sp = num(el, "JellySpeed", 1.2)
	idleRot[el] = (idleRot[el] or 0) + math.sin(e.t * math.pi * 2 * sp) * num(el, "JellyAmp", 3)
	idleScale[el] = (idleScale[el] or 1) * (1 + 0.01 * math.sin(e.t * math.pi * 4 * sp + 1))
end

RUN.wiggle = function(e)
	local el = e.el
	local every = num(el, "WiggleEvery", 4)
	local tt = e.t % (every + 0.7)
	local add = 0
	if tt < 0.7 then
		local p = tt / 0.7
		add = math.sin(p * math.pi * 6) * num(el, "WiggleAngle", 12) * (1 - p)
	end
	idleRot[el] = (idleRot[el] or 0) + add
end

RUN.rays = function(e)
	local el = e.el
	e.ang = ((e.ang or 0) + num(el, "RaysSpeed", 25) * e.dt) % 360
	idleRot[el] = (idleRot[el] or 0) + e.ang
	idleScale[el] = (idleScale[el] or 1) * (1 + num(el, "RaysPulse", 6) / 100 * (0.5 + 0.5 * math.sin(e.t * 2)))
end

RUN.shake = function(e)
	local el = e.el
	local every = num(el, "ShakeEvery", 3)
	local dur = num(el, "ShakeTime", 0.5)
	local tt = e.t % (every + dur)
	if tt < dur then
		-- The base is taken at the start of each shake, so anything that moved
		-- the element between shakes is respected rather than snapped back.
		if not e.shaking then
			e.shaking = true
			e.base = el.Position
		end
		local amp = num(el, "ShakeAmp", 6) * (1 - tt / dur)
		el.Position = e.base + UDim2.fromOffset(math.sin(e.t * 53) * amp, math.cos(e.t * 47) * amp)
	elseif e.shaking then
		e.shaking = false
		el.Position = e.base
	end
end

RUN.glow = function(e)
	local el = e.el
	local breathe = 0.5 + 0.5 * math.sin(e.t * math.pi * 2 * num(el, "GlowSpeed", 0.8))
	local size = num(el, "GlowSize", 12)
	if e.frac then -- a scaled stroke is a FRACTION of the short side, not pixels
		local short = math.max(1, math.min(el.AbsoluteSize.X, el.AbsoluteSize.Y))
		e.stroke.Thickness = e.base + (size * 0.5 * breathe) / short
	else
		e.stroke.Thickness = math.max(e.base + size * 0.5 * breathe, 1.5)
	end
	e.stroke.Transparency = 0.15 -- only the SIZE breathes
end

local function syncText(host: Instance, src: Instance)
	if host:IsA("TextLabel") and (src:IsA("TextLabel") or src:IsA("TextButton")) then
		if host.TextSize ~= src.TextSize then
			host.TextSize = src.TextSize
		end
		if host.TextScaled ~= src.TextScaled then
			host.TextScaled = src.TextScaled
		end
		if host.Text ~= src.Text then
			host.Text = src.Text
		end
	end
end

RUN.gleam = function(e)
	local el = e.el
	local dur = math.max(0.02, num(el, "GleamSpeed", 0.8))
	local cool = num(el, "GleamCooldown", 2)
	local w = num(el, "GleamWidth", 0.22)
	local tt = e.t % (dur + cool)
	local live = tt < dur
	local off = -2
	if live then
		local span = 0.5 + w
		off = -span + (tt / dur) * span * 2
	end
	for _, g in e.grads do
		g.Offset = Vector2.new(off, 0)
		local host = g.Parent
		if host and host:IsA("GuiObject") then
			if host.Visible ~= live then
				host.Visible = live
			end
			if live then
				syncText(host, el)
			end
		end
	end
end

RUN.gleamGroup = function(e)
	local el = e.el
	if e.parts == nil then
		local w0 = num(el, "GleamWidth", 0.22)
		local gw0 = math.max(1, el.AbsoluteSize.X)
		local found = {}
		if gw0 > 1 then
			for _, d in el:GetDescendants() do
				local isText = d:IsA("TextLabel") or d:IsA("TextButton")
				if (isText or d:IsA("ImageLabel") or d:IsA("ImageButton")) and not owned[d] and d.Name ~= "Background" then
					local dw = d.AbsoluteSize.X
					local pad = d:FindFirstChild("FW_TextPad")
					if pad and pad:IsA("UIPadding") then
						dw *= math.max(0, 1 - pad.PaddingLeft.Scale - pad.PaddingRight.Scale)
					end
					-- Only a group-sized IMAGE is a backdrop; a full-width title is still text.
					if dw > 0 and (isText or dw < gw0 * 0.95) then
						-- Capped: an uncapped band lights each letter whole, a flash instead of a sheen.
						local wl = math.clamp(w0 * gw0 / math.max(1, dw), 0.05, 0.6)
						table.insert(found, { el = d, grads = gleamShine(d, wl) })
					end
				end
			end
		end
		if #found > 0 then
			e.parts = found
		else
			e.waited += e.dt
			if e.waited > 2 then -- genuinely nothing inside: one sheen over the whole group
				e.kind = "gleam"
				e.grads = gleamShine(el, w0)
			end
			return
		end
	end

	local dur = math.max(0.02, num(el, "GleamSpeed", 0.8))
	local cool = num(el, "GleamCooldown", 2)
	local w = num(el, "GleamWidth", 0.22)
	local tt = e.t % (dur + cool)
	local live = tt < dur
	local gp = el.AbsolutePosition.X
	local gw = math.max(1, el.AbsoluteSize.X)
	local m = 0.5 + w
	local c = -m + (tt / dur) * (1 + 2 * m) -- the band's centre, in GROUP fractions

	for _, part in e.parts do
		if part.el.Parent then
			for _, g in part.grads do
				local host = g.Parent
				if host and host:IsA("GuiObject") then
					local px = (host.AbsolutePosition.X - gp) / gw
					local pw = math.max(0.001, host.AbsoluteSize.X / gw)
					g.Offset = Vector2.new(live and ((c - px) / pw - 0.5) or -10, 0) -- ONE light across every letter
					if host.Visible ~= live then
						host.Visible = live
					end
					if live then
						syncText(host, part.el)
					end
				end
			end
		end
	end
end

RUN.pixels = function(e)
	if #e.cells == 0 then
		return
	end
	local el = e.el
	e.acc += e.dt * num(el, "PixRate", 8)
	local alpha = num(el, "PixAlpha", 0.35)
	local vary = num(el, "PixVary", 0) >= 0.5
	while e.acc >= 1 do
		e.acc -= 1
		local f = e.cells[math.random(#e.cells)]
		if vary then
			local k = 0.3 + math.random() * 1.4
			f.Size = UDim2.fromScale(e.cw * k, e.ch * k)
		else
			f.Size = UDim2.fromScale(e.cw, e.ch)
		end
		local lit = 1 - alpha * (0.55 + 0.45 * math.random()) -- each twinkle its own brightness
		TweenService:Create(f, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = lit }):Play()
		local hold = 0.16 + math.random() * 0.48
		local fall = 0.35 + math.random() * 0.45
		task.delay(hold, function()
			if f.Parent then
				TweenService:Create(f, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ BackgroundTransparency = 1 }):Play()
			end
		end)
	end
end

local visTimer = 0

local function finish(e)
	e.on = false
end

local function tick(dt: number)
	visTimer += dt
	local refresh = visTimer >= 0.2 -- visibility is re-read 5x a second, not per effect per frame
	if refresh then
		visTimer = 0
	end
	-- Every frame while frozen, so entrances start the moment loading ends.
	if frozen or refresh then
		updateFrozen()
	end
	table.clear(idleScale)
	table.clear(idleRot)

	local i = 1
	while i <= #entries do
		local e = entries[i]
		local el = e.el
		local keep = true

		if dead[el] then
			keep = false
		elseif el.Parent ~= nil then
			local run = true
			if e.idle then
				if refresh or visible[el] == nil then
					visible[el] = shown(el)
				end
				run = visible[el] and not reduced -- hidden or reduced: idle motion pauses
			end
			if run then
				-- While a blocker is up, entrances still pose (lifted, faded,
				-- small) but time stands still, so nothing plays unseen.
				local step = (frozen and not e.idle) and 0 or dt
				e.t += step
				e.dt = step
				-- Each effect isolated: one bad element can't stop the rest this frame.
				local ok, result = pcall(RUN[e.kind], e)
				if not ok then
					warnFor(el, result)
					keep = false
				elseif result == false then
					keep = false
				end
			end
		end

		if keep then
			i += 1
		else
			finish(e)
			entries[i] = entries[#entries]
			entries[#entries] = nil
		end
	end

	-- One write per property: effects multiply and add, never overwrite.
	for el, v in idleScale do
		setScale(el, "idle", v)
	end
	for el, v in idleRot do
		setRotation(el, "idle", v)
	end
end

-- ================================================================ wiring

local function ignored(el: Instance): boolean
	if el:GetAttribute("FxIgnore") or el:HasTag("FxIgnore") or el:GetAttribute("FigmaTimeline") ~= nil then
		return true -- a Framewisp timeline owns its layer
	end
	local gui = el:FindFirstAncestorWhichIsA("LayerCollector")
	return gui ~= nil and (gui:GetAttribute("FxIgnore") == true or gui:HasTag("FxIgnore"))
end

local function wantsAny(el: Instance): boolean
	for _, k in IDLE_KINDS do
		if flag(el, k) then
			return true
		end
	end
	for _, k in ENTRANCE_KINDS do
		if flag(el, k) then
			return true
		end
	end
	return false
end

local function wire(el: Instance)
	if not el:IsA("GuiObject") or wired[el] or owned[el] then
		return
	end
	if el:GetAttribute("FxOwned") then
		return -- a copy of one of our helpers; its element's wiring clears it
	end
	if not wantsAny(el) or ignored(el) then
		return
	end
	wired[el] = true

	-- Helpers copied along with a clone are stale: clear them and rebuild.
	for _, c in el:GetChildren() do
		if c:GetAttribute("FxOwned") and not owned[c] and not c:IsA("UIScale") then
			c:Destroy()
		end
	end
	-- A clone taken mid-entrance goes back to its resting geometry.
	if not active[el] then
		local s, p = el:GetAttribute("FxRestSize"), el:GetAttribute("FxRestPos")
		if typeof(s) == "UDim2" then
			el.Size = s
		end
		if typeof(p) == "UDim2" then
			el.Position = p
		end
		el:SetAttribute("FxRestSize", nil)
		el:SetAttribute("FxRestPos", nil)
	end

	el.Destroying:Connect(function()
		dead[el] = true
		local w = watchers[el]
		if w then
			w.stop()
		end
	end)

	local function try(fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then
			warnFor(el, err)
		end
		return ok and err or nil
	end

	local list = {}
	if flag(el, "Gleam") then
		try(wireGleam, el)
	end
	if flag(el, "Swing") then
		list.Swing = try(swingPlayer, el)
	end
	if flag(el, "Reveal") then
		list.Reveal = try(revealPlayer, el)
	end
	if flag(el, "Drop") then
		list.Drop = try(dropPlayer, el) -- Drop plays the entrance: a Pop beside it would fight it
	elseif flag(el, "Pop") then
		list.Pop = popPlayer(el)
	end
	if flag(el, "Cascade") then
		list.Cascade = cascadePlayer(el)
	end
	if flag(el, "Glow") then
		try(wireGlow, el)
	end
	if flag(el, "Pixels") then
		try(wirePixels, el)
	end
	if flag(el, "Pulse") then
		addEntry({ kind = "pulse", idle = true, el = el, t = math.random() * 7 })
	end
	if flag(el, "Jelly") then
		addEntry({ kind = "jelly", idle = true, el = el, t = math.random() * 7 })
	end
	if flag(el, "Wiggle") then
		addEntry({ kind = "wiggle", idle = true, el = el, t = 0 })
	end
	if flag(el, "Rays") then
		addEntry({ kind = "rays", idle = true, el = el, t = math.random() * 7 })
	end
	if flag(el, "Shake") then
		try(slotFor, el)
		addEntry({ kind = "shake", idle = true, el = el, t = 0 })
	end

	if next(list) then
		entrances[el] = list
		local w = watch(el)
		w.was = false
		w.check() -- already on screen: play now
	end
end

-- ================================================================ public

--- Replays an element's entrances, or just one kind ("Pop", "Swing", ...).
function Effects.Play(el: GuiObject, kind: string?): boolean
	local list = entrances[el]
	if not list then
		return false
	end
	for k, play in list do
		if kind == nil or k == kind then
			local ok, err = pcall(play)
			if not ok then
				warnFor(el, err)
			end
		end
	end
	return true
end

--- A named scale factor on the element's shared UIScale. 1 removes it.
function Effects.SetScale(el: GuiObject, key: string, value: number)
	setScale(el, key, value)
end

--- A named rotation offset in degrees. 0 removes it.
function Effects.SetRotation(el: GuiObject, key: string, deg: number)
	setRotation(el, key, deg)
end

--- Wires an element by hand, e.g. after setting Fx attributes at runtime.
function Effects.Refresh(el: GuiObject)
	wired[el] = nil
	wire(el)
end

--- Reduced motion: idle effects stop and settle, entrances are skipped.
function Effects.SetReduced(on: boolean)
	reduced = on == true
	if not reduced then
		return
	end
	for _, e in entries do
		if not e.idle then
			e.t = math.huge -- finish in-flight entrances on the next frame
		elseif e.kind == "gleam" or e.kind == "gleamGroup" then
			for _, g in e.grads or {} do
				if g.Parent and g.Parent:IsA("GuiObject") then
					g.Parent.Visible = false
				end
			end
			for _, part in e.parts or {} do
				for _, g in part.grads do
					if g.Parent and g.Parent:IsA("GuiObject") then
						g.Parent.Visible = false
					end
				end
			end
		end
	end
	for el in scaleState do
		setScale(el, "idle", 1)
	end
	for el in rotState do
		setRotation(el, "idle", 0)
	end
end

function Effects.IsReduced(): boolean
	return reduced
end

--- Freezes entrances on their first frame until every key is released — for
--- a loading screen or intro driven from code rather than an FxBlocker tag.
function Effects.Hold(key: string)
	holds[key] = true
	updateFrozen()
end

function Effects.Release(key: string)
	holds[key] = nil
	updateFrozen()
end

--- True while entrances are waiting for a blocker or a hold.
function Effects.IsHeld(): boolean
	return frozen
end

-- ================================================================ start

function Effects.Start()
	if started then
		return
	end
	started = true

	task.spawn(function()
		playerGui = player:WaitForChild("PlayerGui")

		-- Blockers first, so entrances already on screen start frozen.
		for _, d in playerGui:GetDescendants() do
			considerBlocker(d)
		end
		for _, d in playerGui:GetDescendants() do
			wire(d)
		end
		playerGui.DescendantAdded:Connect(function(d)
			considerBlocker(d) -- immediately: a loading screen must freeze before anything plays
			-- Attributes are often set a frame after parenting.
			task.defer(function()
				if d.Parent then
					considerBlocker(d)
					wire(d)
				end
			end)
		end)
		CollectionService:GetInstanceAddedSignal("FxBlocker"):Connect(considerBlocker)

		-- A tag added at runtime wires an element that had no effect before.
		-- Tags come from StarterGui on clone anyway; this covers code that tags
		-- things after they are already on screen.
		local function onTagged(inst: Instance)
			if playerGui and inst:IsDescendantOf(playerGui) then
				task.defer(wire, inst)
			end
		end
		for _, kind in IDLE_KINDS do
			CollectionService:GetInstanceAddedSignal("Fx" .. kind):Connect(onTagged)
		end
		for _, kind in ENTRANCE_KINDS do
			CollectionService:GetInstanceAddedSignal("Fx" .. kind):Connect(onTagged)
		end

		local told = false
		RunService.RenderStepped:Connect(function(dt)
			local ok, err = pcall(tick, dt)
			if not ok and not told then
				told = true
				warn("[Effects] tick: " .. tostring(err))
			end
		end)

		task.delay(1, function()
			local elements = {}
			local count = 0
			for _, e in entries do
				elements[e.el] = true
			end
			for el in entrances do
				elements[el] = true
			end
			for _ in elements do
				count += 1
			end
			print(("[Effects] %d running effect(s) across %d element(s)"):format(#entries, count))
		end)
	end)
end

return Effects
