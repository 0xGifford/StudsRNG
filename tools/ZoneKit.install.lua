-- StudsRNG ZoneKit installer: run once (and again after any kit update).
local source = [====[
-- ZoneKit: builds one StudsRNG zone from Parts (SmoothPlastic, solid
-- colours, studded tops) from a short config, in Studio edit mode.
-- Installed into ServerStorage.ZoneKit by the installer command; each zone
-- command calls require(ServerStorage.ZoneKit:Clone()).build({...}).
--
-- Everything it makes goes in workspace.Zones.<Name>.Generated and is
-- rebuilt on every run; anything else in the zone folder (a hand-built
-- keyboard, your own props) is kept. Tags and attributes match
-- Shared/Tags, so the game needs nothing else.
--
-- Zones are all the same size and sit edge to edge along +Z. Each zone
-- builds its own entrance: a gate arch over the whole boundary, the
-- ZoneBarrier filling it, and a stud mosaic blending the previous zone's
-- ground, trail and cliffs (cfg.From) into its own.
--
-- Flat layers never share a height (no z-fighting): floor top 0, patches
-- 0.1, mosaic 0.15, trail 0.2, trail mosaic 0.25, keyboard 0.6 / 0.8.

local CollectionService = game:GetService("CollectionService")

local Kit = {}

-- Layout: zone 1's floor centre, zones edge to edge along +Z.
Kit.ORIGIN = Vector3.new(15, 1, -28)
Kit.WIDTH = 170
Kit.DEPTH = 150
Kit.WALL = 44 -- cliff height, the same everywhere so cliffs line up
Kit.BLEND = 12 -- mosaic reaches this far either side of a boundary

local PITCH = 3.15
local KEY = Vector3.new(3, 1.37, 3)
local HITBOX = 0.8123
local UP = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X

local rng = Random.new(1)

local function color(value)
	if typeof(value) == "Color3" then return value end
	return Color3.fromHex(value)
end

local function colors(list)
	local out = {}
	for i, value in ipairs(list) do
		out[i] = color(value)
	end
	return out
end

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

local function shade(c, amount)
	if amount >= 0 then
		return c:Lerp(Color3.new(1, 1, 1), amount)
	end
	return c:Lerp(Color3.new(0, 0, 0), -amount)
end

function Kit.center(index)
	return Kit.ORIGIN + Vector3.new(0, 0, (index - 1) * Kit.DEPTH)
end

--------------------------------------------------------------------------
-- Parts
--------------------------------------------------------------------------

local function part(parent, size, cframe, c, collide)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color(c)
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Studs
	p.BottomSurface = Enum.SurfaceType.Inlet
	p.CanCollide = collide == true
	p.CanTouch = false
	p.CanQuery = collide == true
	p.Parent = parent
	return p
end

-- A block resting on `at` (its bottom centre), optionally turned.
local function block(parent, at, size, c, yaw, collide)
	return part(parent, size, CFrame.new(at + Vector3.new(0, size.Y / 2, 0)) * CFrame.Angles(0, yaw or 0, 0), c, collide)
end

local function ball(parent, at, d, c)
	local p = part(parent, Vector3.one * d, CFrame.new(at), c)
	p.Shape = Enum.PartType.Ball
	return p
end

-- Upright cylinder resting on `at`.
local function cyl(parent, at, height, d, c, collide)
	local p = part(parent, Vector3.new(height, d, d), CFrame.new(at + Vector3.new(0, height / 2, 0)) * UP, c, collide)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function invisible(parent, size, cframe)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Transparency = 1
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Name = "Wall"
	p.Parent = parent
	return p
end

local function label(p, face, text, c)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.Text = text
	t.TextColor3 = c
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.fromRGB(20, 20, 25)
	stroke.Parent = t
	t.Parent = gui
	gui.Parent = p
end

--------------------------------------------------------------------------
-- Props: fn(parent, at, cfg). `at` is the ground point.
--------------------------------------------------------------------------

local P = {}
local BROWN = color("#7A5234")
local DARK = color("#3B2A20")
local WHITE = color("#F5F5F5")
local GOLD = color("#F2C230")
local GREY = color("#8C8C94")

local function leaves(cfg)
	return cfg.Leaves or { color("#4FA83D"), color("#62BE4A"), color("#3E9233") }
end

P.Tree = function(m, at, cfg)
	local h = rng:NextInteger(6, 9)
	block(m, at, Vector3.new(2, h, 2), BROWN, 0, true)
	local yaw = rng:NextNumber(0, math.pi)
	block(m, at + Vector3.new(0, h - 1, 0), Vector3.new(8, 4, 8), pick(leaves(cfg)), yaw)
	block(m, at + Vector3.new(0, h + 3, 0), Vector3.new(5, 3, 5), pick(leaves(cfg)), yaw + 0.4)
end

P.Pine = function(m, at, cfg)
	block(m, at, Vector3.new(1.6, 3, 1.6), BROWN, 0, true)
	local y = 2
	for tier = 1, 3 do
		local w = 9 - tier * 2
		local yaw = rng:NextNumber(0, math.pi)
		block(m, at + Vector3.new(0, y, 0), Vector3.new(w, 3, w), pick(leaves(cfg)), yaw)
		if cfg.Snow then
			block(m, at + Vector3.new(0, y + 3, 0), Vector3.new(w - 1.5, 0.6, w - 1.5), WHITE, yaw)
		end
		y += 3
	end
end

P.Palm = function(m, at, cfg)
	local x = 0
	for i = 0, 5 do
		x += 0.35
		block(m, at + Vector3.new(x, i * 2, 0), Vector3.new(1.6, 2, 1.6), color("#B88A55"), 0, true)
	end
	local top = at + Vector3.new(x, 12, 0)
	for k = 0, 3 do
		local a = k * math.pi / 2 + rng:NextNumber(-0.2, 0.2)
		part(m, Vector3.new(7, 0.6, 2.2), CFrame.new(top + Vector3.new(math.cos(a) * 3, -0.6, math.sin(a) * 3)) * CFrame.Angles(0, -a, math.rad(-15)),
			pick(leaves(cfg)))
	end
	ball(m, top + Vector3.new(0.6, -1, 0.6), 1.2, BROWN)
end

P.Bush = function(m, at, cfg)
	block(m, at, Vector3.new(5, 3, 4), pick(leaves(cfg)), rng:NextNumber(0, math.pi), true)
	block(m, at + Vector3.new(1, 0, 1), Vector3.new(3, 4, 3), pick(leaves(cfg)), rng:NextNumber(0, math.pi))
end

P.Flowers = function(m, at, cfg)
	for _ = 1, 5 do
		local o = at + Vector3.new(rng:NextNumber(-2.5, 2.5), 0, rng:NextNumber(-2.5, 2.5))
		local h = rng:NextNumber(1.3, 1.9)
		block(m, o, Vector3.new(0.4, h, 0.4), color("#3E9233"))
		block(m, o + Vector3.new(0, h, 0), Vector3.new(1.2, 0.8, 1.2), pick(cfg.Palette), rng:NextNumber(0, math.pi))
	end
end

P.Boulder = function(m, at, cfg)
	local s = rng:NextNumber(3, 6)
	block(m, at, Vector3.new(s * 1.3, s, s), pick(cfg.Rock), rng:NextNumber(0, math.pi), true)
	block(m, at + Vector3.new(s * 0.5, 0, s * 0.3), Vector3.new(s * 0.6, s * 0.6, s * 0.6), pick(cfg.Rock), rng:NextNumber(0, math.pi), true)
end

P.Crystal = function(m, at, cfg)
	for k = 1, 3 do
		local h = rng:NextNumber(4, 9)
		local w = rng:NextNumber(1.2, 2)
		part(m, Vector3.new(w, h, w), CFrame.new(at + Vector3.new(k - 2, h / 2 - 0.5, rng:NextNumber(-1, 1)))
			* CFrame.Angles(math.rad(rng:NextNumber(-15, 15)), math.rad(45), math.rad(rng:NextNumber(-15, 15))), pick(cfg.Palette), true)
	end
end

P.Mushroom = function(m, at, cfg)
	local h = rng:NextNumber(3, 6)
	block(m, at, Vector3.new(1.4, h, 1.4), color("#F0E6D0"), 0, true)
	local cap = pick(cfg.Palette)
	block(m, at + Vector3.new(0, h, 0), Vector3.new(6, 1.6, 6), cap, rng:NextNumber(0, math.pi), true)
	block(m, at + Vector3.new(0, h + 1.6, 0), Vector3.new(3.6, 1, 3.6), cap, rng:NextNumber(0, math.pi))
	for k = 1, 3 do
		block(m, at + Vector3.new(rng:NextNumber(-2, 2), h + 1.6, rng:NextNumber(-2, 2)), Vector3.new(0.8, 0.25 + k * 0.08, 0.8), WHITE)
	end
end

P.Cactus = function(m, at, cfg)
	local green = color("#4C9A3A")
	local h = rng:NextInteger(6, 9)
	block(m, at, Vector3.new(1.8, h, 1.8), green, 0, true)
	for _, side in { -1, 1 } do
		local y = rng:NextNumber(2, h - 3)
		block(m, at + Vector3.new(side * 1.6, y + 0.5, 0), Vector3.new(1.4, 1, 1), green)
		block(m, at + Vector3.new(side * 2, y, 0), Vector3.new(1.2, 3, 1.2), green)
	end
end

P.IceSpike = function(m, at, cfg)
	for k = 1, 3 do
		local h = rng:NextNumber(5, 10)
		part(m, Vector3.new(1.6, h, 1.6), CFrame.new(at + Vector3.new(k - 2, h / 2 - 0.5, 0)) * CFrame.Angles(0, math.rad(45), math.rad(rng:NextNumber(-12, 12))),
			pick({ "#BFE6FF", "#9FD4F5", "#E6F6FF" }), true)
	end
end

P.Snowman = function(m, at, cfg)
	block(m, at, Vector3.new(4, 3.4, 4), WHITE, 0, true)
	block(m, at + Vector3.new(0, 3.4, 0), Vector3.new(3, 2.6, 3), WHITE)
	block(m, at + Vector3.new(0, 6, 0), Vector3.new(2.2, 2, 2.2), WHITE)
	block(m, at + Vector3.new(0, 6.8, -1.3), Vector3.new(0.5, 0.5, 1), color("#F08A24"))
	block(m, at + Vector3.new(0, 8, 0), Vector3.new(2.4, 0.4, 2.4), DARK)
	block(m, at + Vector3.new(0, 8.4, 0), Vector3.new(1.6, 1.6, 1.6), DARK)
	block(m, at + Vector3.new(0, 5.5, 0), Vector3.new(3.2, 0.6, 3.2), color("#D63C3C"))
end

P.DeadTree = function(m, at, cfg)
	local h = rng:NextInteger(6, 10)
	block(m, at, Vector3.new(1.6, h, 1.6), DARK, 0, true)
	for _ = 1, 3 do
		local y = rng:NextNumber(3, h - 1)
		local a = rng:NextNumber(0, math.pi * 2)
		part(m, Vector3.new(4, 0.8, 0.8), CFrame.new(at + Vector3.new(math.cos(a) * 1.5, y, math.sin(a) * 1.5)) * CFrame.Angles(0, -a, math.rad(25)), DARK)
	end
end

P.Pillar = function(m, at, cfg)
	local h = rng:NextInteger(8, 14)
	local stone = cfg.Stone or color("#F2EEE4")
	block(m, at, Vector3.new(4, 1, 4), stone, 0, true)
	block(m, at + Vector3.new(0, 1, 0), Vector3.new(2.6, h, 2.6), stone, 0, true)
	block(m, at + Vector3.new(0, h + 1, 0), Vector3.new(4, 1, 4), cfg.Trim)
end

P.Cloud = function(m, at, cfg)
	local y = rng:NextNumber(0, 2)
	block(m, at + Vector3.new(0, y, 0), Vector3.new(8, 3, 5), WHITE)
	block(m, at + Vector3.new(1, y + 2, 0), Vector3.new(5, 2.5, 4), WHITE)
end

P.Lamp = function(m, at, cfg)
	block(m, at, Vector3.new(0.8, 7, 0.8), DARK, 0, true)
	block(m, at + Vector3.new(0, 7, 0), Vector3.new(1.8, 1.8, 1.8), pick(cfg.Palette))
	block(m, at + Vector3.new(0, 8.8, 0), Vector3.new(2.2, 0.5, 2.2), DARK)
end

P.Coral = function(m, at, cfg)
	local c = pick(cfg.Palette)
	block(m, at, Vector3.new(1.4, 4, 1.4), c, 0, true)
	for _ = 1, 3 do
		local a = rng:NextNumber(0, math.pi * 2)
		local o = at + Vector3.new(math.cos(a) * 1.2, rng:NextNumber(1, 3), math.sin(a) * 1.2)
		block(m, o, Vector3.new(1, rng:NextNumber(2, 4), 1), c)
	end
end

P.Seaweed = function(m, at, cfg)
	for i = 0, rng:NextInteger(4, 7) do
		block(m, at + Vector3.new(math.sin(i) * 0.5, i * 1.4, 0), Vector3.new(0.8, 1.4, 0.8), pick({ "#2E8B57", "#3CB371" }))
	end
end

P.Lollipop = function(m, at, cfg)
	block(m, at, Vector3.new(0.6, 7, 0.6), WHITE, 0, true)
	local disc = part(m, Vector3.new(0.8, 5, 5), CFrame.new(at + Vector3.new(0, 9, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), pick(cfg.Palette))
	disc.Shape = Enum.PartType.Cylinder
end

P.CandyCane = function(m, at, cfg)
	for i = 0, 6 do
		block(m, at + Vector3.new(0, i * 1.2, 0), Vector3.new(1.2, 1.2, 1.2), if i % 2 == 0 then "#E03C3C" else WHITE, 0, i == 0)
	end
	block(m, at + Vector3.new(1.2, 7.2, 0), Vector3.new(1.2, 1.2, 1.2), "#E03C3C")
	block(m, at + Vector3.new(2.4, 6, 0), Vector3.new(1.2, 1.2, 1.2), WHITE)
end

P.Gift = function(m, at, cfg)
	local s = rng:NextNumber(2.5, 4)
	local yaw = rng:NextNumber(0, math.pi)
	block(m, at, Vector3.new(s, s, s), pick(cfg.Palette), yaw, true)
	block(m, at, Vector3.new(s + 0.1, s + 0.1, 0.6), GOLD, yaw)
	block(m, at, Vector3.new(0.6, s + 0.16, s + 0.1), GOLD, yaw)
end

P.Pumpkin = function(m, at, cfg)
	local s = rng:NextNumber(2.5, 4)
	block(m, at, Vector3.new(s * 1.3, s, s * 1.3), "#E8771E", rng:NextNumber(0, math.pi), true)
	block(m, at + Vector3.new(0, s, 0), Vector3.new(0.6, 1, 0.6), "#3E7A2C")
end

P.Tombstone = function(m, at, cfg)
	local yaw = rng:NextNumber(-0.3, 0.3)
	block(m, at, Vector3.new(3.6, 0.6, 2), GREY, yaw, true)
	block(m, at + Vector3.new(0, 0.6, 0), Vector3.new(2.6, 3.6, 0.8), shade(GREY, 0.15), yaw, true)
end

P.Torch = function(m, at, cfg)
	block(m, at, Vector3.new(0.8, 5, 0.8), BROWN, 0, true)
	block(m, at + Vector3.new(0, 5, 0), Vector3.new(1.2, 1.2, 1.2), "#FF8A1E")
	block(m, at + Vector3.new(0, 6.2, 0), Vector3.new(0.7, 0.8, 0.7), "#FFD23C")
end

P.Chest = function(m, at, cfg)
	local yaw = rng:NextNumber(0, math.pi)
	block(m, at, Vector3.new(4, 2.4, 2.6), BROWN, yaw, true)
	block(m, at + Vector3.new(0, 2.4, 0), Vector3.new(4.1, 1, 2.7), shade(BROWN, -0.2), yaw)
	block(m, at, Vector3.new(4.2, 0.5, 2.8), GOLD, yaw)
	block(m, at + Vector3.new(0, 2, 0), Vector3.new(0.8, 0.8, 2.9), GOLD, yaw)
end

P.Coins = function(m, at, cfg)
	for k = 1, 3 do
		local o = at + Vector3.new(k * 1.6 - 3, 0, rng:NextNumber(-1, 1))
		cyl(m, o, rng:NextInteger(1, 4) * 0.5, 1.4, GOLD, k == 2)
	end
end

P.Gear = function(m, at, cfg)
	local c = pick(cfg.Palette)
	local center = at + Vector3.new(0, 4, 0)
	local yaw = rng:NextNumber(0, math.pi)
	local disc = part(m, Vector3.new(1.2, 6, 6), CFrame.new(center) * CFrame.Angles(0, yaw, 0), c, true)
	disc.Shape = Enum.PartType.Cylinder
	for k = 0, 7 do
		local a = k * math.pi / 4
		part(m, Vector3.new(1.2, 1.4, 1.4), CFrame.new(center) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(a, 0, 0) * CFrame.new(0, 3.2, 0), c)
	end
end

P.Pipe = function(m, at, cfg)
	local c = pick(cfg.Palette)
	block(m, at, Vector3.new(2, 6, 2), c, 0, true)
	block(m, at + Vector3.new(2, 3.5, 0), Vector3.new(4, 1.8, 1.8), c)
	block(m, at, Vector3.new(2.6, 0.6, 2.6), shade(c, -0.2))
end

P.Tower = function(m, at, cfg)
	local h = rng:NextInteger(10, 20)
	local c = pick(cfg.Palette)
	local yaw = rng:NextInteger(0, 3) * math.pi / 2
	block(m, at, Vector3.new(6, h, 6), c, yaw, true)
	for y = 2, h - 2, 3 do
		block(m, at + Vector3.new(0, y, 0), Vector3.new(6.2, 1, 4), color("#BFE3FF"), yaw)
	end
	block(m, at + Vector3.new(0, h, 0), Vector3.new(4, 1, 4), shade(c, -0.25), yaw)
end

P.Bamboo = function(m, at, cfg)
	for k = 1, 3 do
		local o = at + Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
		local h = rng:NextInteger(3, 5)
		-- Each stalk its own segment length, so neighbouring stalks never end level.
		local seg = 2.1 + k * 0.17
		for i = 0, h - 1 do
			-- Alternating shades read as the stalk's joints.
			block(m, o + Vector3.new(0, i * seg, 0), Vector3.new(0.9, seg, 0.9), if (i + k) % 2 == 0 then "#6DB33F" else "#5EA034", 0, i == 0)
		end
	end
end

P.Spire = function(m, at, cfg)
	local w = rng:NextNumber(3, 5)
	local y = 0
	for _ = 1, rng:NextInteger(3, 5) do
		local h = rng:NextNumber(2, 4)
		block(m, at + Vector3.new(0, y, 0), Vector3.new(w, h, w), pick(cfg.Rock), rng:NextNumber(0, math.pi), true)
		y += h
		w *= 0.75
	end
end

P.Bones = function(m, at, cfg)
	local yaw = rng:NextNumber(0, math.pi)
	block(m, at, Vector3.new(5, 0.8, 0.8), "#EFE8D8", yaw, true)
	block(m, at, Vector3.new(0.8, 0.8, 5), "#EFE8D8", yaw)
	block(m, at + Vector3.new(0, 0.8, 0), Vector3.new(2, 1.6, 2), "#EFE8D8", yaw)
end

P.Barrel = function(m, at, cfg)
	cyl(m, at, 3, 2.6, BROWN, true)
	cyl(m, at + Vector3.new(0, 0.5, 0), 0.4, 2.7, DARK)
	cyl(m, at + Vector3.new(0, 2.1, 0), 0.4, 2.7, DARK)
end

P.Fence = function(m, at, cfg)
	local yaw = rng:NextInteger(0, 3) * math.pi / 2
	local cf = CFrame.new(at) * CFrame.Angles(0, yaw, 0)
	for k = -2, 2 do
		block(m, (cf * CFrame.new(k * 2, 0, 0)).Position, Vector3.new(0.6, 3, 0.6), color("#E8E2D0"), yaw, true)
	end
	for _, y in { 1, 2.2 } do
		block(m, (cf * CFrame.new(0, y, 0)).Position, Vector3.new(9, 0.4, 0.3), color("#E8E2D0"), yaw)
	end
end

P.Antenna = function(m, at, cfg)
	block(m, at, Vector3.new(3, 1, 3), GREY, 0, true)
	block(m, at + Vector3.new(0, 1, 0), Vector3.new(0.6, 8, 0.6), GREY, 0, true)
	block(m, at + Vector3.new(0, 9, 0), Vector3.new(1, 1, 1), pick(cfg.Palette))
	part(m, Vector3.new(4, 0.4, 4), CFrame.new(at + Vector3.new(0, 6, 0)) * CFrame.Angles(math.rad(35), 0, 0), WHITE)
end

P.Orb = function(m, at, cfg)
	block(m, at, Vector3.new(2, 2, 2), GREY, 0, true)
	ball(m, at + Vector3.new(0, rng:NextNumber(5, 9), 0), rng:NextNumber(2, 4), pick(cfg.Palette))
end

P.HayBale = function(m, at, cfg)
	local yaw = rng:NextNumber(0, math.pi)
	block(m, at, Vector3.new(4, 2.4, 2.4), "#E3C15A", yaw, true)
	block(m, at, Vector3.new(4.1, 2.5, 0.3), "#B8902E", yaw)
end

P.Rubble = function(m, at, cfg)
	for _ = 1, 4 do
		local s = rng:NextNumber(1, 2.5)
		block(m, at + Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2)), Vector3.new(s, s, s), pick(cfg.Rock), rng:NextNumber(0, math.pi))
	end
end

P.Arch = function(m, at, cfg)
	local yaw = rng:NextInteger(0, 1) * math.pi / 2
	local stone = cfg.Stone or pick(cfg.Rock)
	local cf = CFrame.new(at) * CFrame.Angles(0, yaw, 0)
	for _, x in { -3, 3 } do
		block(m, (cf * CFrame.new(x, 0, 0)).Position, Vector3.new(2, 8, 2), stone, yaw, true)
	end
	block(m, (cf * CFrame.new(0, 8, 0)).Position, Vector3.new(8, 1.6, 2), stone, yaw)
end

P.Sign = function(m, at, cfg)
	block(m, at, Vector3.new(0.6, 4, 0.6), BROWN, 0, true)
	block(m, at + Vector3.new(0, 3, 0), Vector3.new(3.6, 2, 0.4), pick(cfg.Palette), rng:NextNumber(-0.4, 0.4))
end

Kit.Props = P


--------------------------------------------------------------------------
-- Zone pieces
--------------------------------------------------------------------------

-- A flat tile whose top sits `top` studs above the floor.
local function tile(parent, x, z, sx, sz, top, c, cy)
	return part(parent, Vector3.new(sx, top, sz), CFrame.new(x, cy + top / 2, z), c)
end

local function ground(z, c, cfg)
	local W, D = Kit.WIDTH, Kit.DEPTH
	-- Exactly the zone's depth so neighbouring floors meet without overlapping.
	part(z, Vector3.new(W + 44, 4, D), CFrame.new(c - Vector3.new(0, 2, 0)), cfg.Ground, true).Name = "Floor"
	-- Patches: one per cell of a grid, so they never overlap each other.
	local cell = 20
	for gx = -W / 2 + cell / 2, W / 2 - cell / 2, cell do
		for gz = -D / 2 + Kit.BLEND + cell / 2, D / 2 - Kit.BLEND - cell / 2, cell do
			local open = math.abs(gx) > 10 and not (cfg.Water and gx > W / 2 - 40)
			if open and rng:NextNumber() < 0.35 then
				local sx, sz = rng:NextInteger(3, 8) * 2, rng:NextInteger(3, 8) * 2
				tile(z, c.X + gx + rng:NextNumber(-(cell - sx) / 2, (cell - sx) / 2), c.Z + gz + rng:NextNumber(-(cell - sz) / 2, (cell - sz) / 2),
					sx, sz, 0.1, pick(cfg.Ground2), c.Y)
			end
		end
	end
	-- Trail from the entrance to the exit.
	tile(z, c.X, c.Z, 12, D, 0.2, cfg.Path, c.Y).Name = "Trail"
	if cfg.Water then
		-- Shallows over the floor, then open sea, kept to this zone's depth.
		local sea = part(z, Vector3.new(330, 1, D), CFrame.new(c + Vector3.new(W / 2 - 30 + 165, -0.4, 0)), cfg.Water)
		sea.Transparency = 0.2
		sea.Name = "Water"
		tile(z, c.X + W / 2 - 30, c.Z, 1.4, D, 0.3, WHITE, c.Y).Name = "Foam"
	end
end

-- Stepped rock along one edge from a to b (ground points), facing `out`.
-- Blocks are cut to fit exactly, so walls of neighbouring zones meet
-- without overlapping. Near `blendAt` (a ground point on the edge) rock
-- colours mix with cfg.From's.
local function wall(z, a, b, out, cfg, blendAt)
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local yaw = math.atan2(-dir.Z, dir.X)
	local x = 0
	while x < length - 0.01 do
		local w = math.min(rng:NextInteger(8, 14), length - x)
		local at = a + dir * (x + w / 2)
		local rocks = cfg.Rock
		local caps = cfg.Cap
		if blendAt and cfg.From then
			local d = (at - blendAt).Magnitude
			if d < 30 and rng:NextNumber() < (1 - d / 30) * 0.8 then
				rocks = cfg.From.Rock
				caps = cfg.From.Cap
			end
		end
		for row = 0, 1 do
			local h = Kit.WALL * (if row == 0 then rng:NextNumber(0.55, 0.8) else rng:NextNumber(0.9, 1.15))
			local o = at + out * (row * 10 + 5)
			block(z, o, Vector3.new(w, h, 10), pick(rocks), yaw, true)
			if caps then
				-- Exactly its rock's footprint, so no cap overlaps another.
				block(z, o + Vector3.new(0, h, 0), Vector3.new(w, 1.2, 10), caps, yaw)
			end
		end
		x += w
	end
end

local function walls(z, c, cfg, first, last)
	local W, D = Kit.WIDTH / 2, Kit.DEPTH / 2
	local high = 160
	local entrance = if first then nil else Vector3.new(0, 0, -D)
	local function side(a, b, out, blendAt)
		wall(z, a, b, out, cfg, blendAt)
		local size = Vector3.new(math.abs(b.X - a.X) + 1, high, math.abs(b.Z - a.Z) + 1)
		invisible(z, size, CFrame.new((a + b) / 2 + Vector3.new(0, high / 2, 0)))
	end
	-- Left cliff, and the right one unless the sea is there.
	side(c + Vector3.new(-W, 0, -D), c + Vector3.new(-W, 0, D), Vector3.new(-1, 0, 0), entrance and c + Vector3.new(-W, 0, -D))
	if cfg.Water then
		invisible(z, Vector3.new(1, high, Kit.DEPTH), CFrame.new(c + Vector3.new(W, high / 2, 0)))
	else
		side(c + Vector3.new(W, 0, -D), c + Vector3.new(W, 0, D), Vector3.new(1, 0, 0), entrance and c + Vector3.new(W, 0, -D))
	end
	-- Only the ends of the line are closed: zones are open to each other.
	if first then
		side(c + Vector3.new(-W - 20, 0, -D), c + Vector3.new(W + 20, 0, -D), Vector3.new(0, 0, -1))
	end
	if last then
		side(c + Vector3.new(-W - 20, 0, D), c + Vector3.new(W + 20, 0, D), Vector3.new(0, 0, 1))
	end
end

-- Roof zones sit inside a mountain: a grid of rock columns whose undersides
-- form a vaulted ceiling (low and craggy along the walls, a high dome in the
-- middle, dropping to a cave mouth at each end) and whose tops form the
-- mountain's slopes, carried on past the cliffs so neighbouring zones see a
-- mountain with a cave in it rather than a lid. Tile edges sit off the stud
-- grid and stop short of the zone's ends, so no face lines up with a cliff's.
local function cave(z, c, cfg)
	local W, D = Kit.WIDTH, Kit.DEPTH
	local mouth = Kit.WALL + 2 -- lowest ceiling: clear of the gate's caps
	local inner = (W + 44.6) / 2 -- the ceiling covers the floor and the cliffs
	local outer = inner + 34 -- slopes run on past the cliffs
	local cols, rows = 21, 15
	local tx = inner * 2 / cols
	local depth = D - 0.6
	local tz = depth / rows
	local mountain = Instance.new("Folder")
	mountain.Name = "Mountain"
	mountain.Parent = z

	-- 0 at the zone's ends, 1 in the middle (eased).
	local function inward(zz: number): number
		local e = math.clamp((D / 2 - math.abs(zz)) / (D / 2), 0, 1)
		return e * e * (3 - 2 * e)
	end
	-- Height of the mountain's surface above the floor.
	local function surface(x: number, zz: number): number
		local u = math.clamp(math.abs(x) / outer, 0, 1)
		return Kit.WALL + 14 + 46 * inward(zz) * (1 - u * u)
	end

	local function column(x: number, zz: number, sx: number, bottom: number)
		local top = math.max(bottom + 6, surface(x, zz) + rng:NextNumber(0, 5))
		local rock = pick(cfg.Rock)
		part(mountain, Vector3.new(sx, top - bottom, tz), CFrame.new(c.X + x, c.Y + (bottom + top) / 2, c.Z + zz), rock, true)
		-- A lighter crust on the slopes reads as the mountain's skin.
		local crust = cfg.Cap or shade(rock, 0.18)
		part(mountain, Vector3.new(sx - 0.4, 0.9, tz - 0.4), CFrame.new(c.X + x, c.Y + top + 0.45, c.Z + zz), crust)
		return bottom
	end

	local ceiling: { { x: number, z: number, y: number } } = {}
	for i = 0, cols - 1 do
		local x = -inner + tx * (i + 0.5)
		local u = math.abs(x) / inner
		for j = 0, rows - 1 do
			local zz = -depth / 2 + tz * (j + 0.5)
			local e = inward(zz)
			-- Dome: high in the middle of the cave, down to the mouth at the ends
			-- and down onto the cliffs at the sides.
			local dome = (1 - u * u) * 26 * (0.25 + 0.75 * e)
			local bottom = mouth + dome + rng:NextNumber(-2.5, 4)
			if math.abs(x) > W / 2 then
				bottom = Kit.WALL * rng:NextNumber(0.82, 0.98) -- rests on the cliffs
			end
			column(x, zz, tx, math.max(bottom, if math.abs(x) > W / 2 then 0 else mouth))
			if math.abs(x) < W / 2 - 8 and e > 0.35 then
				table.insert(ceiling, { x = x, z = zz, y = bottom })
			end
		end
	end
	-- Slopes beyond the cliffs, down to the ground.
	for _, side in { -1, 1 } do
		for k = 0, 2 do
			local sx = (outer - inner) / 3
			local x = side * (inner + sx * (k + 0.5))
			for j = 0, rows - 1 do
				local zz = -depth / 2 + tz * (j + 0.5)
				column(x, zz, sx, -1.9)
			end
		end
	end

	-- Stalactites: tapering stacks hanging from the vault.
	for _ = 1, 26 do
		local spot = ceiling[rng:NextInteger(1, #ceiling)]
		local at = c + Vector3.new(spot.x + rng:NextNumber(-3, 3), spot.y, spot.z + rng:NextNumber(-3, 3))
		local yaw = rng:NextNumber(0, math.pi)
		local w, y = rng:NextNumber(3, 4.5), 0.5
		for _ = 1, rng:NextInteger(2, 4) do
			local h = rng:NextNumber(3, 6)
			part(mountain, Vector3.new(w, h, w), CFrame.new(at + Vector3.new(0, y - h / 2, 0)) * CFrame.Angles(0, yaw, 0), pick(cfg.Rock))
			y -= h - 0.4
			w *= 0.62
		end
	end

	-- Crystals growing out of the cave walls.
	for _ = 1, 12 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local at = c + Vector3.new(side * (W / 2 - 0.5), rng:NextNumber(8, Kit.WALL * 0.6), rng:NextNumber(-D / 2 + 20, D / 2 - 20))
		for k = 1, 3 do
			local h = rng:NextNumber(3, 7)
			part(mountain, Vector3.new(1.4, h, 1.4), CFrame.new(at + Vector3.new(0, k - 2, k - 2))
				* CFrame.Angles(math.rad(rng:NextNumber(-20, 20)), math.rad(45), math.rad(side * rng:NextNumber(35, 70))), pick(cfg.Palette))
		end
	end
end

-- Stud mosaic across the entrance boundary: tiles change from the previous
-- zone's colours to this zone's the further in they are.
local function transition(z, c, cfg)
	local from = cfg.From
	if not from then return end
	local W = Kit.WIDTH
	local edge = c.Z - Kit.DEPTH / 2
	local size = 6
	for tz = edge - Kit.BLEND + size / 2, edge + Kit.BLEND - size / 2, size do
		local t = (tz - (edge - Kit.BLEND)) / (Kit.BLEND * 2) -- 0 = previous zone, 1 = this zone
		-- Columns centred on the trail; every tile is laid so the seam between
		-- the two floors is fully covered.
		for i = -math.floor(W / 2 / size), math.floor(W / 2 / size) do
			local tx = i * size
			local onWater = tx > W / 2 - 32 and (cfg.Water or from.Water)
			if not onWater then
				local mine = rng:NextNumber() < t
				if math.abs(tx) <= 6 then
					tile(z, c.X + tx, tz, size, size, 0.25, if mine then cfg.Path else from.Path, c.Y)
				else
					tile(z, c.X + tx, tz, size, size, 0.15, if mine then pick(cfg.Ground2) else pick(from.Ground2), c.Y)
				end
			end
		end
	end
end

-- The arch over the entrance and the barrier filling it.
local function gate(z, c, cfg, index)
	local W = Kit.WIDTH
	local gz = c.Z - Kit.DEPTH / 2
	local arch = Instance.new("Model")
	arch.Name = "Gate"
	arch:SetAttribute("ZoneId", cfg.Id)
	arch.Parent = z
	local trim = cfg.Trim
	for _, s in { -1, 1 } do
		local x = c.X + s * (W / 2 + 3)
		-- Off-grid sizes: cliff blocks end on whole studs, so a pillar face
		-- never lines up with one. The cap stands proud of the beam.
		block(arch, Vector3.new(x, c.Y, gz), Vector3.new(10.4, 3, 10.4), shade(trim, -0.35), 0, true)
		block(arch, Vector3.new(x, c.Y + 3, gz), Vector3.new(8.4, 38, 8.4), trim, 0, true)
		block(arch, Vector3.new(x, c.Y + 41, gz), Vector3.new(10.6, 3, 10.6), shade(trim, -0.35), 0, true)
	end
	-- Ends inside the pillars, never flush with their faces.
	local beam = part(arch, Vector3.new(W + 10, 6, 4), CFrame.new(c.X, c.Y + 40, gz), shade(trim, -0.35), true)
	beam.Name = "GateSign"
	local text = index .. "  " .. string.upper(cfg.Name)
	label(beam, Enum.NormalId.Front, text, WHITE)
	label(beam, Enum.NormalId.Back, text, WHITE)
	CollectionService:AddTag(arch, "ZoneGate")

	-- One dark, half-see-through part across the whole opening.
	local barrier = Instance.new("Part")
	barrier.Name = "Barrier"
	barrier.Anchored = true
	barrier.Size = Vector3.new(W, 37, 1)
	barrier.CFrame = CFrame.new(c.X, c.Y + 18.5, gz)
	barrier.Color = shade(trim, -0.8)
	barrier.Material = Enum.Material.SmoothPlastic
	barrier.TopSurface = Enum.SurfaceType.Smooth
	barrier.BottomSurface = Enum.SurfaceType.Smooth
	barrier.Transparency = 0.5
	barrier.CastShadow = false
	barrier.CanQuery = false
	barrier:SetAttribute("ZoneId", cfg.Id)
	barrier.Parent = z
	CollectionService:AddTag(barrier, "ZoneBarrier")
end

local function spawnPad(z, c, cfg, first)
	local at = c + Vector3.new(0, 0.5, -Kit.DEPTH / 2 + Kit.BLEND + 10)
	local pad
	if first then
		pad = Instance.new("SpawnLocation")
		pad.Neutral = true
		pad.Duration = 0
		local decal = pad:FindFirstChildOfClass("Decal")
		if decal then decal:Destroy() end
	else
		pad = Instance.new("Part")
	end
	pad.Name = "Spawn"
	pad.Anchored = true
	pad.Size = Vector3.new(10, 1, 10)
	pad.CFrame = CFrame.lookAt(at, at + Vector3.new(0, 0, 1))
	pad.Color = cfg.Trim
	pad.Material = Enum.Material.SmoothPlastic
	pad.TopSurface = Enum.SurfaceType.Studs
	pad.CanCollide = first
	pad:SetAttribute("ZoneId", cfg.Id)
	pad.Parent = z
	CollectionService:AddTag(pad, "ZoneSpawn")
end

local function keyboard(z, c, cfg)
	local cols, rows = cfg.KeyCols or 22, cfg.KeyRows or 8
	local center = c + Vector3.new(0, 0, 8)
	local size = Vector3.new(cols * PITCH, 0, rows * PITCH)
	block(z, center, Vector3.new(size.X + 4, 0.8, size.Z + 4), cfg.Plate, 0, true).Name = "KeyboardPlate"
	block(z, center, Vector3.new(size.X + 5, 0.6, size.Z + 5), cfg.Trim)

	local folder = Instance.new("Folder")
	folder.Name = "Keyboard"
	folder:SetAttribute("ZoneId", cfg.Id)
	folder:SetAttribute("KeyValue", 1)
	folder:SetAttribute("Multiplier", 1)
	folder:SetAttribute("Enabled", true)
	folder.Parent = z
	CollectionService:AddTag(folder, "Keyboard")

	local y = center.Y + 0.8 + KEY.Y / 2
	for row = 1, rows do
		local keyColor = cfg.Keys[(row - 1) % #cfg.Keys + 1]
		for col = 1, cols do
			local cf = CFrame.new(center.X + (col - (cols + 1) / 2) * PITCH, y, center.Z + (row - (rows + 1) / 2) * PITCH)
			local model = Instance.new("Model")
			model.Name = string.format("Key_R%02d_C%02d", row, col)
			local hitbox = Instance.new("Part")
			hitbox.Name = "Hitbox"
			hitbox.Size = Vector3.new(KEY.X * HITBOX, KEY.Y, KEY.Z * HITBOX)
			hitbox.CFrame = cf
			hitbox.Anchored = true
			hitbox.CanCollide = false
			hitbox.CanTouch = false
			hitbox.Transparency = 1
			hitbox.Parent = model
			local cap = part(model, KEY, cf, keyColor)
			cap.Name = "Cap"
			cap.CastShadow = false
			model.PrimaryPart = hitbox
			model:SetAttribute("Group", cfg.Id)
			model.Parent = folder
			CollectionService:AddTag(hitbox, "KeyCapper_Hitbox")
			CollectionService:AddTag(model, "KeyCapper_Key")
		end
	end
end

-- `board` is the keyboard's area (min, max corners relative to the centre).
local function propSpots(c, cfg, count, board)
	local W, D = Kit.WIDTH / 2, Kit.DEPTH / 2
	local spots = {}
	local tries = 0
	while #spots < count and tries < count * 40 do
		tries += 1
		local x = rng:NextNumber(-W + 10, W - 10)
		local zz = rng:NextNumber(-D + Kit.BLEND + 6, D - Kit.BLEND - 6)
		local ok = math.abs(x) > 10
			and not (x > board[1].X - 8 and x < board[2].X + 8 and zz > board[1].Z - 8 and zz < board[2].Z + 8)
			and not (math.abs(x) < 10 and zz < -D + Kit.BLEND + 20)
			and not (cfg.Water and x > W - 36)
		if ok then
			for _, s in ipairs(spots) do
				if (Vector3.new(x, 0, zz) - s).Magnitude < 10 then ok = false break end
			end
		end
		if ok then table.insert(spots, Vector3.new(x, 0, zz)) end
	end
	return spots
end

local function weighted(weights)
	local names, total = {}, 0
	for name, w in pairs(weights) do
		table.insert(names, name)
		total += w
	end
	table.sort(names)
	local roll = rng:NextNumber() * total
	for _, name in ipairs(names) do
		roll -= weights[name]
		if roll <= 0 then return name end
	end
	return names[#names]
end

-- Big scenery outside the walls, kept within this zone's depth so it never
-- runs into the neighbours'.
local function features(z, c, cfg)
	local D = Kit.DEPTH
	for _, f in ipairs(cfg.Features or {}) do
		local kind = f[1]
		local fc = color(f[2] or cfg.Rock[1])
		if kind == "Mountain" then
			local base = c + Vector3.new(Kit.WIDTH / 2 + 100, -2, 0)
			for tier = 0, 6 do
				local w = D - 10 - tier * 19
				block(z, base + Vector3.new(0, tier * 16, 0), Vector3.new(w, 16, w), shade(fc, -0.04 * tier), math.rad(tier * 7))
			end
			if f[3] then block(z, base + Vector3.new(0, 112, 0), Vector3.new(14, 2, 14), f[3]) end
		elseif kind == "Planet" then
			ball(z, c + Vector3.new(-120, 140, 0), 70, fc)
		elseif kind == "Rainbow" then
			local bands = { "#E8413C", "#F28C28", "#F5D428", "#4CB84A", "#3C8FE0", "#7A4CC8" }
			for i, band in ipairs(bands) do
				local r = 100 - i * 4
				for k = 0, 18 do
					local a = math.pi * k / 18
					part(z, Vector3.new(4, 4, 6), CFrame.new(c + Vector3.new(math.cos(a) * r, math.sin(a) * r, D / 2 - 30)) * CFrame.Angles(0, 0, a), band)
				end
			end
		elseif kind == "Pyramid" then
			local base = c + Vector3.new(-Kit.WIDTH / 2 - 100, -2, 0)
			for tier = 0, 9 do
				local w = D - 10 - tier * 14
				block(z, base + Vector3.new(0, tier * 9, 0), Vector3.new(w, 9, w), shade(fc, (tier % 2) * 0.06))
			end
		elseif kind == "Towers" then
			for k = 1, 8 do
				local h = rng:NextInteger(60, 140)
				local s = rng:NextInteger(16, 26)
				local side = if k % 2 == 0 then 1 else -1
				local zz = -D / 2 + 20 + (k - 1) * (D - 40) / 7
				block(z, c + Vector3.new(side * (Kit.WIDTH / 2 + 34 + rng:NextInteger(0, 50)), -2, zz), Vector3.new(s, h, s), shade(fc, rng:NextNumber(-0.15, 0.15)))
			end
		elseif kind == "Sun" then
			ball(z, c + Vector3.new(80, 160, 0), 50, fc)
		end
	end
end

local function skyClouds(z, c, cfg)
	if cfg.Roof or cfg.Clouds == false then return end
	local cloud = cfg.CloudColor or WHITE
	for k = 1, 6 do
		local zz = -Kit.DEPTH / 2 + k * Kit.DEPTH / 7
		local at = c + Vector3.new(rng:NextNumber(-150, 150), 80 + k * 6, zz)
		block(z, at, Vector3.new(rng:NextInteger(16, 30), 6, rng:NextInteger(10, 16)), cloud)
		block(z, at + Vector3.new(rng:NextNumber(-4, 4), 6, 0), Vector3.new(rng:NextInteger(8, 14), 5, rng:NextInteger(6, 9)), cloud)
	end
end

--------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------

local LOOK = {
	ClockTime = "Clock", Ambient = "Ambient", OutdoorAmbient = "Outdoor", FogColor = "Fog", FogEnd = "FogEnd",
	AtmosphereColor = "Atmosphere", AtmosphereDensity = "Density", Gravity = "Gravity",
}

function Kit.build(cfg)
	assert(type(cfg.Index) == "number" and cfg.Id and cfg.Name, "Index, Id and Name are required")
	rng = Random.new(cfg.Index * 7919)
	cfg.Trim = color(cfg.Trim)
	cfg.Ground = color(cfg.Ground)
	cfg.Ground2 = colors(cfg.Ground2 or { cfg.Ground })
	cfg.Path = color(cfg.Path)
	cfg.Rock = colors(cfg.Rock)
	cfg.Cap = cfg.Cap and color(cfg.Cap)
	cfg.Plate = color(cfg.Plate or "#2B2B33")
	cfg.Keys = colors(cfg.Keys)
	cfg.Palette = colors(cfg.Palette or { cfg.Trim })
	cfg.Leaves = cfg.Leaves and colors(cfg.Leaves)
	cfg.Stone = cfg.Stone and color(cfg.Stone)
	cfg.Water = cfg.Water and color(cfg.Water)
	cfg.CloudColor = cfg.CloudColor and color(cfg.CloudColor)
	if cfg.From then
		local from = cfg.From
		cfg.From = {
			Ground2 = colors(from.Ground2 or { from.Ground }),
			Path = color(from.Path),
			Rock = colors(from.Rock),
			Cap = from.Cap and color(from.Cap),
			Water = from.Water == true,
		}
	end

	local zones = workspace:FindFirstChild("Zones")
	if not zones then
		zones = Instance.new("Folder")
		zones.Name = "Zones"
		zones.Parent = workspace
	end
	local zone
	for _, child in ipairs(zones:GetChildren()) do
		if child:GetAttribute("ZoneId") == cfg.Id or child.Name == cfg.Name then
			zone = child
			break
		end
	end
	if not zone then
		zone = Instance.new("Folder")
		zone.Parent = zones
	end
	zone.Name = cfg.Name
	local old = zone:FindFirstChild("Generated")
	if old then old:Destroy() end

	local c = Kit.center(cfg.Index)
	zone:SetAttribute("ZoneId", cfg.Id)
	zone:SetAttribute("Center", c)
	zone:SetAttribute("ZoneSize", Vector3.new(Kit.WIDTH, 90, Kit.DEPTH))
	zone:SetAttribute("Subtitle", cfg.Subtitle or "")
	for attr, key in pairs(LOOK) do
		local value = cfg.Sky and cfg.Sky[key]
		if type(value) == "string" then value = color(value) end
		zone:SetAttribute(attr, value)
	end
	CollectionService:AddTag(zone, "Zone")

	local z = Instance.new("Folder")
	z.Name = "Generated"
	z.Parent = zone

	local first = cfg.Index == 1
	local last = cfg.Last == true
	ground(z, c, cfg)
	walls(z, c, cfg, first, last)
	if cfg.Roof then
		cave(z, c, cfg)
	end
	if not first then
		transition(z, c, cfg)
		gate(z, c, cfg, cfg.Index)
	end
	spawnPad(z, c, cfg, first)

	-- Keep a hand-built keyboard if the zone already has one; props stay off it.
	local half = Vector3.new((cfg.KeyCols or 22) * PITCH / 2 + 2, 0, (cfg.KeyRows or 8) * PITCH / 2 + 2)
	local board = { Vector3.new(-half.X, 0, 8 - half.Z), Vector3.new(half.X, 0, 8 + half.Z) }
	local kept = nil
	for _, d in ipairs(zone:GetDescendants()) do
		if CollectionService:HasTag(d, "Keyboard") and not d:IsDescendantOf(z) then
			kept = d
			break
		end
	end
	if kept then
		local low, high = nil, nil
		for _, d in ipairs(kept:GetDescendants()) do
			if d:IsA("BasePart") then
				local p = d.Position - c
				low = if low then Vector3.new(math.min(low.X, p.X), 0, math.min(low.Z, p.Z)) else p
				high = if high then Vector3.new(math.max(high.X, p.X), 0, math.max(high.Z, p.Z)) else p
			end
		end
		if low and high then
			board = { low - Vector3.new(2, 0, 2), high + Vector3.new(2, 0, 2) }
		end
	else
		keyboard(z, c, cfg)
	end

	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = z
	for _, spot in ipairs(propSpots(c, cfg, cfg.PropCount or 30, board)) do
		local name = weighted(cfg.Props)
		local build = P[name]
		if build then
			local m = Instance.new("Model")
			m.Name = name
			m.Parent = props
			build(m, c + spot, cfg)
		else
			warn("[ZoneKit] unknown prop " .. tostring(name))
		end
	end
	features(z, c, cfg)
	skyClouds(z, c, cfg)

	local count = 0
	for _, d in ipairs(z:GetDescendants()) do
		if d:IsA("BasePart") then count += 1 end
	end
	print(string.format("[ZoneKit] built %d %s (%s): %d parts at %s", cfg.Index, cfg.Name, cfg.Id, count, tostring(c)))
	return zone
end

return Kit
]====]
local ServerStorage = game:GetService("ServerStorage")
local kit = ServerStorage:FindFirstChild("ZoneKit") or Instance.new("ModuleScript")
kit.Name = "ZoneKit"
kit.Source = source
kit.Parent = ServerStorage
print("[ZoneKit] installed in ServerStorage.ZoneKit")
