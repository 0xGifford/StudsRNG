--[[
	Wires the zones built in Studio up to the game's tags and attributes.

	  lune run tools/wire_place.luau <in.rbxl> <out.rbxl>

	For every zone in ZONES (in unlock order; workspace.Zones children are
	found by their Studio name or, once wired, by their id):
	  * renames the Model to its id, sets ZoneId, Subtitle, and Center /
	    ZoneSize from its Ground (copies of a zone carried the original's)
	  * tags the Spawn ZoneSpawn (teleport target); only the first zone's
	    SpawnLocation stays enabled, so players always join in Grasslands;
	    zones without one get a spawn at their entrance
	  * zones without keys get a copy of the first zone's keyboard (KeyCapper
	    keys, regrouped to the zone, with a matching KeyCapperGroups style)
	  * tags the Ground EnemyGround and adds EnemySpawn markers around the
	    keyboard when a zone has none
	  * puts a ZoneBarrier (dark, half transparent, with the buy sign) on the
	    seam between each zone and the one before it
	It also untags the Lobby, Shortcut1 and WaterSurface (they aren't zones)
	and deletes the old ReplicatedStorage.Shared.MapAssets module.
	Re-running on an already wired place updates it instead of duplicating.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum

-- { Studio name, id, subtitle } in unlock order (must match Shared/Zones).
local ZONES = {
	{ "Grasslands", "Grasslands", "Where every Clack begins" },
	{ "City", "City", "Clacks never sleep" },
	{ "Desert", "Desert", "Hot keys, dry dunes" },
	{ "Orchard", "Orchard", "Ripe for the picking" },
	{ "Frostlands", "Frostlands", "Mind the ice" },
	{ "Zone7", "Springs", "Splash between the keys" },
	{ "Zone8", "Village", "A quiet little clatter" },
	{ "Zone9", "Metro", "Rush hour on the keyboard" },
	{ "Zone10", "WildWest", "Fastest fingers in the west" },
	{ "Zone11", "Quarry", "Dig deep for Clacks" },
	{ "Zone12", "Reef", "Under the coral" },
	{ "Zone13", "Lagoon", "Shells and starfish" },
	{ "Zone14", "Beach", "Sun, sand and studs" },
	{ "Zone15", "Meadow", "Flowers in full bloom" },
	{ "Zone16", "Woodlands", "Deep in the trees" },
	{ "Zone17", "Jungle", "Wild and overgrown" },
	{ "Zone18", "Canyon", "Echoes off the rocks" },
	{ "Zone19", "Suburbs", "Mow the keys" },
	{ "Zone20", "Lumberyard", "Timber!" },
	{ "Zone21", "Hive", "Busy as a bee" },
	{ "Zone22", "Snowfield", "Fresh powder" },
	{ "Zone23", "Wildwood", "Older than the oaks" },
	{ "Zone24", "Tropics", "Paradise found" },
	{ "Zone25", "Ashlands", "Still warm" },
	{ "Zone26", "Glacier", "Frozen solid" },
	{ "Zone27", "CrystalSprings", "Sparkling waters" },
	{ "Zone28", "Hamlet", "Smallest town around" },
	{ "Zone29", "Downtown", "Lights, traffic, Clacks" },
	{ "Zone30", "Frontier", "Out past the edge" },
	{ "Zone31", "Honeycomb", "Sweetest Clacks yet" },
	{ "Zone32", "Tundra", "Cold to the core" },
	{ "Zone33", "Elderwood", "The forest remembers" },
	{ "Zone34", "Badlands", "Nothing grows here" },
	{ "Zone35", "Obsidian", "The end of the keyboard" },
}
local NOT_ZONES = { "Lobby", "Shortcut1", "WaterSurface" }

local BARRIER_COLOR = Color3.fromRGB(25, 25, 35)
local BARRIER_HEIGHT = 40
local MARKER_SPOTS = { -- local to the Ground, around the 44 x 44 keyboard
	{ -40, -32 }, { -40, 0 }, { -40, 32 }, { -28, -36 }, { -28, 36 },
	{ 0, -36 }, { 0, 36 }, { 28, -36 }, { 28, 36 }, { 40, -32 }, { 40, 32 },
	{ -34, -18 }, { -34, 18 }, { 34, -18 }, { 34, 18 }, { 0, -30 },
}

local input, output = process.args[1], process.args[2]
assert(input and output, "usage: lune run tools/wire_place.luau <in.rbxl> <out.rbxl>")
local game = roblox.deserializePlace(fs.readFile(input))
local workspace = game:GetService("Workspace")
local zonesFolder = workspace:FindFirstChild("Zones")
assert(zonesFolder, "workspace.Zones not found")

local report = {}
local function note(text: string)
	table.insert(report, text)
end

local function groundOf(zone: any): any
	return zone:FindFirstChild("Ground") or zone:FindFirstChild("Floor")
end

-- World-space box of a part (handles rotation).
local function boxOf(part: any): (any, any)
	local cf, half = part.CFrame, part.Size / 2
	local lo, hi
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local p = cf * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
				lo = if lo then Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z)) else p
				hi = if hi then Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z)) else p
			end
		end
	end
	return lo, hi
end

-- Solid, visible scenery in a zone: what keys and spawns shouldn't sit in.
local function sceneryOf(zone: any, ground: any): { { any } }
	local boxes = {}
	for _, d in zone:GetDescendants() do
		if d:IsA("BasePart") and d ~= ground and d.CanCollide and d.Transparency < 1
			and d.Name ~= "Spawn" and not d:HasTag("ZoneBarrier") and not d:HasTag("EnemySpawn")
			and not (d:FindFirstAncestor("Keyboard")) then
			local lo, hi = boxOf(d)
			table.insert(boxes, { lo, hi })
		end
	end
	return boxes
end

-- How much scenery volume a box overlaps.
local function clutter(boxes: { { any } }, lo: any, hi: any): number
	local total = 0
	for _, box in boxes do
		local x = math.min(hi.X, box[2].X) - math.max(lo.X, box[1].X)
		local y = math.min(hi.Y, box[2].Y) - math.max(lo.Y, box[1].Y)
		local z = math.min(hi.Z, box[2].Z) - math.max(lo.Z, box[1].Z)
		if x > 0 and y > 0 and z > 0 then
			total += x * y * z
		end
	end
	return total
end

-- World box of a local box (centre, size) placed with cframe.
local function placedBox(cframe: any, size: any): (any, any)
	local lo, hi
	local half = size / 2
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local p = cframe * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
				lo = if lo then Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z)) else p
				hi = if hi then Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z)) else p
			end
		end
	end
	return lo, hi
end

-- The plate the keyboard sits on (a 50 x 50 part in the zone's Pit model).
local function plateOf(zone: any): any
	local pit = zone:FindFirstChild("Pit", true)
	return pit and (pit:FindFirstChild("KeyboardPlate") or pit:FindFirstChild("Surf"))
end

local function hasTagged(root: any, tag: string): boolean
	for _, d in root:GetDescendants() do
		if d:HasTag(tag) then return true end
	end
	return false
end

-- Find every zone first (by Studio name, or by id when already wired).
local models = {}
for order, entry in ZONES do
	local zone = zonesFolder:FindFirstChild(entry[1]) or zonesFolder:FindFirstChild(entry[2])
	assert(zone, `zone {entry[1]} / {entry[2]} not found in workspace.Zones`)
	assert(groundOf(zone), `zone {entry[1]} has no Ground / Floor part`)
	models[order] = zone
end

local first = models[1]
local firstGround = groundOf(first)
local templateKeyboard = first:FindFirstChild("Keyboard")
local templateSpawn = first:FindFirstChild("Spawn")
assert(templateKeyboard, "the first zone needs a Keyboard to copy")
local templatePlate = plateOf(first)
assert(templatePlate, "the first zone needs a keyboard plate (Pit.KeyboardPlate)")
-- The first zone's keys face its entrance, towards the lobby (+X).
local templateEntrance = Vector3.new(1, 0, 0)
local keyGroups = game:GetService("ReplicatedStorage"):FindFirstChild("KeyCapperGroups")
local templateGroup = keyGroups and keyGroups:FindFirstChild(ZONES[1][2])

-- Zone boxes (from their Ground), trimmed back to the seam where two
-- grounds overlap, so "which zone am I in" is never ambiguous.
local zoneBoxes = {}
for order in ZONES do
	local lo, hi = boxOf(groundOf(models[order]))
	zoneBoxes[order] = { lo = lo, hi = hi }
end
for i = 1, #ZONES do
	for j = i + 1, #ZONES do
		local a, b = zoneBoxes[i], zoneBoxes[j]
		local overlapX = math.min(a.hi.X, b.hi.X) - math.max(a.lo.X, b.lo.X)
		local overlapZ = math.min(a.hi.Z, b.hi.Z) - math.max(a.lo.Z, b.lo.Z)
		if overlapX > 0 and overlapZ > 0 then
			if overlapX < overlapZ then
				local left, right = if a.lo.X < b.lo.X then a else b, if a.lo.X < b.lo.X then b else a
				local seam = (left.hi.X + right.lo.X) / 2
				left.hi = Vector3.new(seam, left.hi.Y, left.hi.Z)
				right.lo = Vector3.new(seam, right.lo.Y, right.lo.Z)
			else
				local near, far = if a.lo.Z < b.lo.Z then a else b, if a.lo.Z < b.lo.Z then b else a
				local seam = (near.hi.Z + far.lo.Z) / 2
				near.hi = Vector3.new(near.hi.X, near.hi.Y, seam)
				far.lo = Vector3.new(far.lo.X, far.lo.Y, seam)
			end
		end
	end
end

for order, entry in ZONES do
	local zone = models[order]
	local id, subtitle = entry[2], entry[3]
	local ground = groundOf(zone)
	local lo, hi = boxOf(ground)
	local top = hi.Y
	local area = zoneBoxes[order]

	zone.Name = id
	zone:AddTag("Zone")
	zone:SetAttribute("ZoneId", id)
	zone:SetAttribute("Subtitle", subtitle)
	zone:SetAttribute("Center", Vector3.new((area.lo.X + area.hi.X) / 2, top, (area.lo.Z + area.hi.Z) / 2))
	zone:SetAttribute("ZoneSize", Vector3.new(area.hi.X - area.lo.X, 80, area.hi.Z - area.lo.Z))

	-- Anything inside that still names another zone (copied from where it
	-- was built) belongs to this one.
	for _, d in zone:GetDescendants() do
		local named = d:GetAttribute("ZoneId")
		if typeof(named) == "string" and named ~= id then
			d:SetAttribute("ZoneId", id)
			note(`{id}: {d.Name} said ZoneId "{named}", now "{id}"`)
		end
	end

	-- Which way the previous zone (or the lobby, for the first) lies.
	local center = Vector3.new((lo.X + hi.X) / 2, top, (lo.Z + hi.Z) / 2)
	local toward: any
	if order > 1 then
		local plo, phi = boxOf(groundOf(models[order - 1]))
		toward = Vector3.new((plo.X + phi.X) / 2, top, (plo.Z + phi.Z) / 2) - center
	else
		toward = Vector3.new(1, 0, 0)
	end
	local entrance = if math.abs(toward.X) > math.abs(toward.Z)
		then Vector3.new(if toward.X > 0 then 1 else -1, 0, 0)
		else Vector3.new(0, 0, if toward.Z > 0 then 1 else -1)

	-- Spawn: the teleport target. Only the first zone's spawns players.
	local scenery = sceneryOf(zone, ground)
	local spawnPart = zone:FindFirstChild("Spawn")
	if not spawnPart then
		spawnPart = if templateSpawn then templateSpawn:Clone() else Instance.new("SpawnLocation")
		spawnPart.Name = "Spawn"
		-- Near the entrance, on the clearest spot along it.
		local half = if entrance.X ~= 0 then (hi.X - lo.X) / 2 else (hi.Z - lo.Z) / 2
		local side = Vector3.new(entrance.Z, 0, entrance.X)
		local best, bestScore = nil, math.huge
		for _, inset in { 10, 14, 18, 22 } do
			for _, slide in { 0, 6, -6, 12, -12, 18, -18, 24, -24, 30, -30, 36, -36, 42, -42 } do
				local position = center + entrance * (half - inset) + side * slide + Vector3.new(0, spawnPart.Size.Y / 2 + 0.5, 0)
				local blo, bhi = placedBox(CFrame.new(position + Vector3.new(0, 3, 0)), Vector3.new(spawnPart.Size.X, 7, spawnPart.Size.Z))
				local score = clutter(scenery, blo, bhi) + inset * 0.01 + math.abs(slide) * 0.001
				if score < bestScore then
					best, bestScore = position, score
				end
			end
		end
		spawnPart.CFrame = CFrame.lookAt(best, best - entrance)
		spawnPart.Parent = zone
		note(`{id}: added a spawn at its entrance{if bestScore >= 1 then " (some scenery around it)" else ""}`)
	end
	spawnPart:AddTag("ZoneSpawn")
	if spawnPart:IsA("SpawnLocation") then
		spawnPart.Enabled = order == 1
	end

	-- Keyboard.
	local keyboard = zone:FindFirstChild("Keyboard")
	if not keyboard then
		keyboard = templateKeyboard:Clone()
		-- On the zone's keyboard plate, like the first zone's keyboard on its
		-- own, turned so the keys face the zone's entrance.
		local plate = plateOf(zone)
		local target = if plate then plate.CFrame.Position else ground.CFrame.Position + Vector3.new(0, ground.Size.Y / 2 - 2, 0)
		local turn = math.atan2(-entrance.Z, entrance.X) - math.atan2(-templateEntrance.Z, templateEntrance.X)
		local transform = CFrame.new(target) * CFrame.Angles(0, turn, 0) * CFrame.new(-templatePlate.CFrame.Position)
		for _, d in keyboard:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = transform * d.CFrame
			end
			if d:GetAttribute("Group") ~= nil then
				d:SetAttribute("Group", id)
			end
		end
		keyboard.Parent = zone
		note(`{id}: added a keyboard ({#keyboard:GetChildren()} keys)`)
	end
	keyboard:AddTag("Keyboard")
	if keyGroups and templateGroup and not keyGroups:FindFirstChild(id) then
		local style = templateGroup:Clone()
		style.Name = id
		local color = ground.Color
		style:SetAttribute("Color", color)
		style:SetAttribute("TextColor", color)
		style.Parent = keyGroups
	end

	-- Enemies: ground to stand on, and spots to live at.
	if not hasTagged(zone, "EnemyGround") then
		ground:AddTag("EnemyGround")
	end
	if not hasTagged(zone, "EnemySpawn") then
		local folder = Instance.new("Folder")
		folder.Name = "EnemySpawns"
		local scaleX = ground.Size.X / 120
		local scaleZ = ground.Size.Z / 100
		for i, spot in MARKER_SPOTS do
			local marker = Instance.new("Part")
			marker.Name = string.format("EnemySpawn_%03d", i)
			marker.Size = Vector3.new(1, 0.2, 1)
			marker.Anchored = true
			marker.CanCollide = false
			marker.CanQuery = false
			marker.CanTouch = false
			marker.Transparency = 1
			marker.CFrame = ground.CFrame * CFrame.new(spot[1] * scaleX, ground.Size.Y / 2 + 0.6, spot[2] * scaleZ)
			marker:AddTag("EnemySpawn")
			marker.Parent = folder
		end
		folder.Parent = zone
		note(`{id}: added {#MARKER_SPOTS} enemy spawn markers`)
	end

	-- Barrier on the seam with the previous zone.
	for _, d in zone:GetDescendants() do
		if d:HasTag("ZoneBarrier") then
			d:Destroy()
		end
	end
	if order > 1 then
		local plo, phi = boxOf(groundOf(models[order - 1]))
		local bottom = math.min(top, phi.Y) - 1
		local height = math.max(top, phi.Y) + BARRIER_HEIGHT - bottom
		local barrier = Instance.new("Part")
		barrier.Name = "Barrier"
		local overlapX = math.min(hi.X, phi.X) - math.max(lo.X, plo.X)
		local overlapZ = math.min(hi.Z, phi.Z) - math.max(lo.Z, plo.Z)
		if overlapX > overlapZ then
			-- Stacked along Z: the seam runs along X.
			local seam = if (lo.Z + hi.Z) < (plo.Z + phi.Z) then (hi.Z + plo.Z) / 2 else (lo.Z + phi.Z) / 2
			local fromX, toX = math.max(lo.X, plo.X), math.min(hi.X, phi.X)
			barrier.Size = Vector3.new(toX - fromX, height, 1.5)
			barrier.CFrame = CFrame.new((fromX + toX) / 2, bottom + height / 2, seam)
		else
			local seam = if (lo.X + hi.X) < (plo.X + phi.X) then (hi.X + plo.X) / 2 else (lo.X + phi.X) / 2
			local fromZ, toZ = math.max(lo.Z, plo.Z), math.min(hi.Z, phi.Z)
			barrier.Size = Vector3.new(1.5, height, toZ - fromZ)
			barrier.CFrame = CFrame.new(seam, bottom + height / 2, (fromZ + toZ) / 2)
		end
		barrier.Anchored = true
		barrier.CanCollide = true
		barrier.CastShadow = false
		barrier.Material = Enum.Material.SmoothPlastic
		barrier.Color = BARRIER_COLOR
		barrier.Transparency = 0.5
		barrier:AddTag("ZoneBarrier")
		barrier:SetAttribute("ZoneId", id)
		barrier.Parent = zone
	end
end

-- Not zones.
for _, name in NOT_ZONES do
	local model = zonesFolder:FindFirstChild(name)
	if model then
		model:RemoveTag("Zone")
		for _, attribute in { "ZoneId", "Center", "ZoneSize", "Subtitle" } do
			model:SetAttribute(attribute, nil)
		end
		note(`{name}: no longer tagged as a zone`)
	end
end

-- Leftover from the ForgeGUI map.
local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
local mapAssets = shared and shared:FindFirstChild("MapAssets")
if mapAssets then
	mapAssets:Destroy()
	note("deleted ReplicatedStorage.Shared.MapAssets (unused)")
end

fs.writeFile(output, roblox.serializePlace(game))
for _, line in report do
	print(line)
end
print(`wired {#ZONES} zones → {output}`)
