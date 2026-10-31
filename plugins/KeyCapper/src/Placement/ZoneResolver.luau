--!strict
-- StudsRNG addition. Single responsibility: which game zone a spot belongs to.
--
-- The game's zones are Models named Zone1 .. ZoneN under workspace.Zones (the
-- Lobby sits there too and is not a zone). A key painted in Zone7 pays in
-- zone "007": it carries that id as its World attribute, which the game reads.
--
-- Resolution, cheapest and surest first:
--   1. the surface the key lands on sits inside a Zone<N> model;
--   2. the spot is inside a zone's box (its Center / ZoneSize attributes, set
--      by the ZoneManager plugin), else over its Ground part.
-- Nothing found (the Lobby, scratch parts): nil, and the key gets no zone.

local ZoneResolver = {}

local ZONES_FOLDER = "Zones"

-- "Zone7" / "zone 7" → 7
function ZoneResolver.NumberOf(name: string): number?
	return tonumber(string.match(string.lower(name), "^zone%s*(%d+)$"))
end

-- The id the game uses for zone n ("007").
function ZoneResolver.Id(n: number): string
	return string.format("%03d", n)
end

-- The KeyCapper group a zone's keys are painted into when zone groups are on.
function ZoneResolver.GroupName(n: number): string
	return "Zone" .. n
end

local function folder(): Instance?
	return workspace:FindFirstChild(ZONES_FOLDER)
end

-- Every zone model present, by number.
function ZoneResolver.Zones(): { [number]: Model }
	local zones: { [number]: Model } = {}
	local f = folder()
	if not f then return zones end
	for _, child in ipairs(f:GetChildren()) do
		local n = ZoneResolver.NumberOf(child.Name)
		if n and child:IsA("Model") then
			zones[n] = child
		end
	end
	return zones
end

-- Zone numbers present, ascending.
function ZoneResolver.List(): { number }
	local list: { number } = {}
	for n in pairs(ZoneResolver.Zones()) do
		table.insert(list, n)
	end
	table.sort(list)
	return list
end

function ZoneResolver.FromInstance(instance: Instance?): number?
	local f = folder()
	local node = instance
	while node and f and node ~= f and node ~= workspace do
		if node.Parent == f then
			return if node:IsA("Model") then ZoneResolver.NumberOf(node.Name) else nil
		end
		node = node.Parent
	end
	return nil
end

local function insideBox(zone: Model, position: Vector3): boolean
	local center = zone:GetAttribute("Center")
	local size = zone:GetAttribute("ZoneSize")
	if typeof(center) == "Vector3" and typeof(size) == "Vector3" then
		local offset = position - center
		return math.abs(offset.X) <= size.X / 2 and math.abs(offset.Z) <= size.Z / 2
			and offset.Y >= -10 and offset.Y <= size.Y - 10
	end
	local ground = zone:FindFirstChild("Ground")
	if ground and ground:IsA("BasePart") then
		local localPoint = ground.CFrame:PointToObjectSpace(position)
		return math.abs(localPoint.X) <= ground.Size.X / 2 and math.abs(localPoint.Z) <= ground.Size.Z / 2
	end
	return false
end

function ZoneResolver.FromPosition(position: Vector3): number?
	for n, zone in pairs(ZoneResolver.Zones()) do
		if insideBox(zone, position) then
			return n
		end
	end
	return nil
end

function ZoneResolver.Resolve(surface: Instance?, position: Vector3): number?
	return ZoneResolver.FromInstance(surface) or ZoneResolver.FromPosition(position)
end

return ZoneResolver
