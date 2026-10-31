--[[
	Checks a place file against what the code expects of the map.

	  lune run tools/check_place.luau <place.rbxl>

	Every zone in Shared/Zones.lua needs a Zone-tagged Model whose ZoneId is
	its id, with a ZoneSpawn, keys, EnemyGround and (after the first) a
	ZoneBarrier. Also flags: enabled SpawnLocations outside the first zone,
	ZoneId attributes naming unknown zones, keys whose KeyCapper Group has no
	style, Zone-tagged things that aren't in Shared/Zones, and zones whose
	boxes overlap. Exits 1 when it finds a problem.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3

local path = process.args[1]
assert(path, "usage: lune run tools/check_place.luau <place.rbxl>")
local game = roblox.deserializePlace(fs.readFile(path))
local workspace = game:GetService("Workspace")

-- Zone ids in unlock order, read from Shared/Zones.lua.
local zonesSource = fs.readFile("src/ReplicatedStorage/Shared/Zones.lua")
local listStart = string.find(zonesSource, "local zones:", 1, true) or 1
local listEnd = string.find(zonesSource, "\n}", listStart, true) or #zonesSource
local ids = {}
for id in string.gmatch(string.sub(zonesSource, listStart, listEnd), 'Id = "([%w_]+)"') do
	table.insert(ids, id)
end
local known = {}
for order, id in ids do
	known[id] = order
end

local problems = 0
local function problem(text: string)
	problems += 1
	print("✗ " .. text)
end

-- Zone models by id.
local zoneModels = {}
for _, d in workspace:GetDescendants() do
	if d:HasTag("Zone") then
		local id = d:GetAttribute("ZoneId")
		if typeof(id) ~= "string" or id == "" then
			id = d.Name
		end
		if not known[id] then
			problem(`{d:GetFullName()} is tagged Zone but "{id}" isn't in Shared/Zones`)
		elseif zoneModels[id] then
			problem(`two Zone models for "{id}": {zoneModels[id]:GetFullName()} and {d:GetFullName()}`)
		else
			zoneModels[id] = d
		end
	end
end

local styles = game:GetService("ReplicatedStorage"):FindFirstChild("KeyCapperGroups")
local boxes = {}
for order, id in ids do
	local zone = zoneModels[id]
	if not zone then
		problem(`zone {order} "{id}" has no Zone-tagged Model in the workspace`)
		continue
	end
	local has = { ZoneSpawn = 0, KeyCapper_Hitbox = 0, EnemyGround = 0, ZoneBarrier = 0 }
	local groups = {}
	for _, d in zone:GetDescendants() do
		for tag in has do
			if d:HasTag(tag) then has[tag] += 1 end
		end
		local group = d:GetAttribute("Group")
		if typeof(group) == "string" then groups[group] = true end
		local zid = d:GetAttribute("ZoneId")
		if typeof(zid) == "string" and zid ~= "" and not known[zid] then
			problem(`{d:GetFullName()} has ZoneId "{zid}", which isn't a zone`)
		end
		if d:IsA("SpawnLocation") and d.Enabled and order ~= 1 then
			problem(`{d:GetFullName()} is an enabled SpawnLocation: players can spawn in "{id}" without owning it`)
		end
	end
	if has.ZoneSpawn == 0 then problem(`"{id}" has no ZoneSpawn (teleports there fail)`) end
	if has.KeyCapper_Hitbox == 0 then problem(`"{id}" has no keys`) end
	if has.EnemyGround == 0 then problem(`"{id}" has no EnemyGround (enemies use the zone's own parts)`) end
	if order > 1 and has.ZoneBarrier == 0 then problem(`"{id}" has no ZoneBarrier (nothing stops players walking in)`) end
	for group in groups do
		if styles and not styles:FindFirstChild(group) then
			problem(`"{id}" has keys in KeyCapper group "{group}", which has no style in ReplicatedStorage.KeyCapperGroups`)
		end
	end
	local center = zone:GetAttribute("Center")
	local size = zone:GetAttribute("ZoneSize")
	if typeof(center) == "Vector3" and typeof(size) == "Vector3" then
		table.insert(boxes, { id = id, lo = center - size / 2, hi = center + size / 2 })
	else
		problem(`"{id}" has no Center / ZoneSize attributes (its bounding box is used)`)
	end
end

-- Overlapping zone boxes confuse "which zone am I in" (lighting, enemies).
for i = 1, #boxes do
	for j = i + 1, #boxes do
		local a, b = boxes[i], boxes[j]
		local x = math.min(a.hi.X, b.hi.X) - math.max(a.lo.X, b.lo.X)
		local z = math.min(a.hi.Z, b.hi.Z) - math.max(a.lo.Z, b.lo.Z)
		if x > 4 and z > 4 then
			problem(`zones "{a.id}" and "{b.id}" overlap by {math.floor(x)} x {math.floor(z)} studs`)
		end
	end
end

print(if problems == 0 then `✓ {#ids} zones, no problems` else `{problems} problem(s)`)
process.exit(if problems > 0 then 1 else 0)
