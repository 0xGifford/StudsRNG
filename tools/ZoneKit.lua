-- ZoneKit: builds one StudsRNG zone from Parts (SmoothPlastic, solid
-- colours, studded tops) from a short config, in Studio edit mode.
-- Installed into ServerStorage.ZoneKit by the installer command; each zone
-- command calls require(ServerStorage.ZoneKit:Clone()).build({...}).
--
-- Everything it makes goes in workspace.Zones.<Name>.Generated and is
-- rebuilt on every run; anything else in the zone folder (a hand-built
-- keyboard, your own props) is kept. Tags and attributes match
-- Shared/Tags, so the game needs nothing else.

local CollectionService = game:GetService("CollectionService")

local Kit = {}

-- Layout: zone 1's floor centre, zones in a line along +Z.
Kit.ORIGIN = Vector3.new(15, 1, -28)
Kit.WIDTH = 170
Kit.DEPTH = 150
Kit.GAP = 40 -- pass between zones
Kit.PASS = 28 -- pass / gate width

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
	return Kit.ORIGIN + Vector3.new(0, 0, (index - 1) * (Kit.DEPTH + Kit.GAP))
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
		block(m, o, Vector3.new(0.4, 1.6, 0.4), color("#3E9233"))
		block(m, o + Vector3.new(0, 1.6, 0), Vector3.new(1.2, 0.8, 1.2), pick(cfg.Palette), rng:NextNumber(0, math.pi))
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
	for _ = 1, 3 do
		block(m, at + Vector3.new(rng:NextNumber(-2, 2), h + 1.6, rng:NextNumber(-2, 2)), Vector3.new(0.8, 0.3, 0.8), WHITE)
	end
end

P.Cactus = function(m, at, cfg)
	local green = color("#4C9A3A")
	local h = rng:NextInteger(6, 9)
	block(m, at, Vector3.new(1.8, h, 1.8), green, 0, true)
	for _, side in { -1, 1 } do
		local y = rng:NextNumber(2, h - 3)
		block(m, at + Vector3.new(side * 1.6, y, 0), Vector3.new(1.4, 1.2, 1.2), green)
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
	block(m, at + Vector3.new(0, 5.4, 0), Vector3.new(3.2, 0.6, 3.2), color("#D63C3C"))
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
	block(m, at, Vector3.new(0.6, s + 0.1, s + 0.1), GOLD, yaw)
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
	block(m, at + Vector3.new(2, 4, 0), Vector3.new(4, 2, 2), c)
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
		for i = 0, h - 1 do
			-- Alternating shades read as the stalk's joints.
			block(m, o + Vector3.new(0, i * 2.4, 0), Vector3.new(0.9, 2.4, 0.9), if (i + k) % 2 == 0 then "#6DB33F" else "#5EA034", 0, i == 0)
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

local function ground(z, c, cfg)
	local W, D = Kit.WIDTH, Kit.DEPTH
	part(z, Vector3.new(W + 40, 4, D + 40), CFrame.new(c - Vector3.new(0, 2, 0)), cfg.Ground, true).Name = "Floor"
	for _ = 1, 26 do
		local size = Vector3.new(rng:NextInteger(3, 8) * 2, 0.2, rng:NextInteger(3, 8) * 2)
		block(z, c + Vector3.new(rng:NextNumber(-W / 2 + 8, W / 2 - 8), 0, rng:NextNumber(-D / 2 + 8, D / 2 - 8)), size, pick(cfg.Ground2),
			rng:NextInteger(0, 3) * math.pi / 2)
	end
	-- Trail from the entrance to the exit.
	block(z, c + Vector3.new(0, 0, 0), Vector3.new(12, 0.3, D + 40), cfg.Path)
	if cfg.Water then
		local water = part(z, Vector3.new(600, 1, D + 600), CFrame.new(c + Vector3.new(W / 2 + 300 - 30, -0.4, 0)), cfg.Water)
		water.Transparency = 0.2
		water.Name = "Water"
		block(z, c + Vector3.new(W / 2 - 30, 0, 0), Vector3.new(1.4, 0.35, D + 40), WHITE).Name = "Foam"
	end
end

-- Chunky stepped rock along one edge, from a to b (ground points), facing `out`.
local function wall(z, a, b, out, cfg)
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local yaw = math.atan2(-dir.Z, dir.X)
	local h0 = cfg.WallHeight or 40
	local x = 0
	while x < length do
		local w = rng:NextInteger(8, 14)
		local at = a + dir * (x + w / 2)
		for row = 0, 1 do
			local h = h0 * (if row == 0 then rng:NextNumber(0.55, 0.8) else rng:NextNumber(0.85, 1.15))
			local o = at + out * (row * 10 + 5)
			local rock = pick(cfg.Rock)
			block(z, o, Vector3.new(w + 1, h, 11), rock, yaw, true)
			if cfg.Cap then
				block(z, o + Vector3.new(0, h, 0), Vector3.new(w + 1.4, 1.2, 11.4), cfg.Cap, yaw)
			end
		end
		x += w
	end
end

local function walls(z, c, cfg, first, last)
	local W, D = Kit.WIDTH / 2, Kit.DEPTH / 2
	local gap = Kit.PASS / 2
	local high = 160
	-- Edges are axis-aligned: rock outside, an invisible wall on the line.
	local function side(a, b, out)
		wall(z, a, b, out, cfg)
		local size = Vector3.new(math.abs(b.X - a.X) + 1, high, math.abs(b.Z - a.Z) + 1)
		invisible(z, size, CFrame.new((a + b) / 2 + Vector3.new(0, high / 2, 0)))
	end
	-- Sides (+X becomes open sea when Water is set).
	side(c + Vector3.new(-W, 0, -D), c + Vector3.new(-W, 0, D), Vector3.new(-1, 0, 0))
	if cfg.Water then
		invisible(z, Vector3.new(1, high, Kit.DEPTH), CFrame.new(c + Vector3.new(W, high / 2, 0)))
	else
		side(c + Vector3.new(W, 0, -D), c + Vector3.new(W, 0, D), Vector3.new(1, 0, 0))
	end
	-- Back (entrance) and front (exit) with a gap for the pass.
	for _, z0 in { -D, D } do
		local open = (z0 < 0 and not first) or (z0 > 0 and not last)
		local out = Vector3.new(0, 0, if z0 < 0 then -1 else 1)
		if open then
			side(c + Vector3.new(-W, 0, z0), c + Vector3.new(-gap, 0, z0), out)
			side(c + Vector3.new(gap, 0, z0), c + Vector3.new(W, 0, z0), out)
		else
			side(c + Vector3.new(-W, 0, z0), c + Vector3.new(W, 0, z0), out)
		end
	end
	if cfg.Roof then
		part(z, Vector3.new(Kit.WIDTH + 60, 6, Kit.DEPTH + 60), CFrame.new(c + Vector3.new(0, (cfg.WallHeight or 40) + 3, 0)), shade(color(cfg.Rock[1]), -0.3), true)
		for _ = 1, 30 do
			local h = rng:NextNumber(5, 14)
			block(z, c + Vector3.new(rng:NextNumber(-W + 6, W - 6), (cfg.WallHeight or 40) - h, rng:NextNumber(-D + 6, D - 6)), Vector3.new(3, h, 3), pick(cfg.Rock),
				math.rad(45))
		end
	end
end

-- The pass from the previous zone's exit to this zone's entrance.
local function pass(z, c, cfg)
	local startZ = c.Z - Kit.DEPTH / 2 - Kit.GAP
	local mid = Vector3.new(c.X, c.Y, startZ + Kit.GAP / 2)
	part(z, Vector3.new(Kit.PASS + 40, 4, Kit.GAP + 2), CFrame.new(mid - Vector3.new(0, 2, 0)), cfg.Ground, true).Name = "PassFloor"
	block(z, mid, Vector3.new(12, 0.3, Kit.GAP + 2), cfg.Path)
	for _, s in { -1, 1 } do
		local x = s * (Kit.PASS / 2 + 5)
		local zz = startZ
		while zz < startZ + Kit.GAP do
			block(z, Vector3.new(c.X + x, c.Y, zz + 5), Vector3.new(11, (cfg.WallHeight or 40) * rng:NextNumber(0.7, 1), 11), pick(cfg.Rock), 0, true)
			zz += 10
		end
		invisible(z, Vector3.new(1, 160, Kit.GAP), CFrame.new(c.X + s * (Kit.PASS / 2 + 0.5), c.Y + 80, mid.Z))
	end
end

local function gate(z, c, cfg, index)
	local gz = c.Z - Kit.DEPTH / 2 - 1
	local folder = Instance.new("Model")
	folder.Name = "Gate"
	folder:SetAttribute("ZoneId", cfg.Id)
	folder.Parent = z
	for _, s in { -1, 1 } do
		local x = c.X + s * (Kit.PASS / 2 + 3)
		block(folder, Vector3.new(x, c.Y, gz), Vector3.new(8, 2, 8), shade(cfg.Trim, -0.3), 0, true)
		block(folder, Vector3.new(x, c.Y + 2, gz), Vector3.new(6, 26, 6), cfg.Trim, 0, true)
	end
	local beam = part(folder, Vector3.new(Kit.PASS + 14, 6, 3), CFrame.new(c.X, c.Y + 31, gz), shade(cfg.Trim, -0.3), true)
	beam.Name = "GateSign"
	local text = index .. "  " .. string.upper(cfg.Name)
	label(beam, Enum.NormalId.Front, text, WHITE)
	label(beam, Enum.NormalId.Back, text, WHITE)
	CollectionService:AddTag(folder, "ZoneGate")

	local barrier = Instance.new("Part")
	barrier.Name = "Barrier"
	barrier.Anchored = true
	barrier.Size = Vector3.new(Kit.PASS, 26, 1)
	barrier.CFrame = CFrame.new(c.X, c.Y + 13, gz)
	barrier.Color = cfg.Trim
	barrier.Material = Enum.Material.SmoothPlastic
	barrier.Transparency = 0.45
	barrier.CastShadow = false
	barrier.CanQuery = false
	barrier:SetAttribute("ZoneId", cfg.Id)
	barrier.Parent = z
	CollectionService:AddTag(barrier, "ZoneBarrier")
end

local function spawnPad(z, c, cfg, first)
	local at = c + Vector3.new(0, 0.5, -Kit.DEPTH / 2 + 14)
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
		local zz = rng:NextNumber(-D + 10, D - 10)
		local ok = math.abs(x) > 10
			and not (x > board[1].X - 8 and x < board[2].X + 8 and zz > board[1].Z - 8 and zz < board[2].Z + 8)
			and not (math.abs(x) < 10 and zz < -D + 26)
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

-- Big scenery outside the walls.
local function features(z, c, cfg)
	for _, f in ipairs(cfg.Features or {}) do
		local kind = f[1]
		local fc = color(f[2] or cfg.Rock[1])
		if kind == "Mountain" then
			local base = c + Vector3.new(Kit.WIDTH / 2 + 110, -2, 20)
			for tier = 0, 6 do
				local w = 170 - tier * 22
				block(z, base + Vector3.new(0, tier * 16, 0), Vector3.new(w, 16, w), shade(fc, -0.04 * tier), math.rad(tier * 7))
			end
			if f[3] then block(z, base + Vector3.new(0, 112, 0), Vector3.new(16, 2, 16), f[3]) end
		elseif kind == "Planet" then
			ball(z, c + Vector3.new(-120, 140, 160), 70, fc)
		elseif kind == "Rainbow" then
			local bands = { "#E8413C", "#F28C28", "#F5D428", "#4CB84A", "#3C8FE0", "#7A4CC8" }
			for i, band in ipairs(bands) do
				local r = 90 - i * 4
				for k = 0, 18 do
					local a = math.pi * k / 18
					part(z, Vector3.new(4, 4, 16), CFrame.new(c + Vector3.new(math.cos(a) * r, math.sin(a) * r, Kit.DEPTH / 2 + 40)) * CFrame.Angles(0, 0, a), band)
				end
			end
		elseif kind == "Pyramid" then
			local base = c + Vector3.new(-Kit.WIDTH / 2 - 110, -2, 0)
			for tier = 0, 9 do
				local w = 150 - tier * 15
				block(z, base + Vector3.new(0, tier * 9, 0), Vector3.new(w, 9, w), shade(fc, (tier % 2) * 0.06))
			end
		elseif kind == "Towers" then
			for k = 1, 8 do
				local h = rng:NextInteger(60, 140)
				local s = rng:NextInteger(16, 28)
				local side = if k % 2 == 0 then 1 else -1
				block(z, c + Vector3.new(side * (Kit.WIDTH / 2 + 30 + rng:NextInteger(0, 60)), -2, rng:NextNumber(-Kit.DEPTH / 2, Kit.DEPTH / 2)), Vector3.new(s, h, s),
					shade(fc, rng:NextNumber(-0.15, 0.15)))
			end
		elseif kind == "Sun" then
			ball(z, c + Vector3.new(80, 160, 200), 50, fc)
		end
	end
end

local function skyClouds(z, c, cfg)
	if cfg.Roof or cfg.Clouds == false then return end
	local cloud = cfg.CloudColor or WHITE
	for _ = 1, 8 do
		local at = c + Vector3.new(rng:NextNumber(-160, 160), rng:NextNumber(85, 120), rng:NextNumber(-120, 120))
		block(z, at, Vector3.new(rng:NextInteger(16, 30), 6, rng:NextInteger(10, 18)), cloud)
		block(z, at + Vector3.new(rng:NextNumber(-4, 4), 5, rng:NextNumber(-3, 3)), Vector3.new(rng:NextInteger(8, 14), 5, rng:NextInteger(6, 10)), cloud)
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
	if not first then
		pass(z, c, cfg)
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
