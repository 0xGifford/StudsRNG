--[[
	ZoneWiring: wires the hand-built zones under workspace.Zones for the game.
	Shared by the ZoneManager Studio plugin and tools/wire_zones.luau (Lune),
	so it only uses what both have: pass the Roblox types in as `env`.

	  local Wiring = require(ZoneWiring)(env)   -- env: Instance, Vector3, CFrame, Color3, Enum
	  local report = Wiring.wire(workspace, options)

	The map it expects:
	  workspace.Zones.Lobby              the start area: no price, keyboard or enemies
	  workspace.Zones.Zone1 .. ZoneN     a Model per zone, unlocked in number order
	    Ground                           the floor Part (sets the zone's box)
	    Ground.DividerLine               invisible ground-sized Part with two
	                                     Attachments (and a Beam) marking the
	                                     line players cross to ENTER this zone
	    Stuff.Pit.Surf                   where the keyboard goes (placed by hand)
	    Stuff.Decorations.signage        a sign whose TextLabel names a zone

	What it does (safe to run again: it rebuilds what it made):
	  zones     ZoneId "001".. from the name, tag Zone, Center / ZoneSize from
	            the Ground (cut at the gate lines so boxes don't overlap),
	            Ground tagged EnemyGround
	  gates     each DividerLine is matched to the zones on either side of it
	            (by position, not by which model it sits in), and gates the
	            higher one. A zone with no DividerLine gets one made from the
	            ground seam with the previous zone (reported).
	  barriers  Zone<N>.Gate.Barrier: ground-wide, up from the line, tagged
	            ZoneBarrier with ZoneId; the game shows the price and BUY button
	            on it and removes it once the zone is owned (the Beam stays)
	  spawns    Zone<N>.Gate.Spawn (tagged ZoneSpawn): a clear spot just past
	            the gate, where the Teleporter puts players. One SpawnLocation
	            in the Lobby; SpawnLocations inside zones are turned off.
	  signs     every signage TextLabel in Zone<N> reads "Zone N", and the
	            sign is tagged ZoneSign (the game keeps the text in step with
	            Shared/Zones)
	  other     Zone tag removed from things under Zones that aren't zones
]]

type Report = { lines: { string }, problems: { string } }

return function(env: any)
	local Instance = env.Instance
	local Vector3 = env.Vector3
	local CFrame = env.CFrame
	local Color3 = env.Color3
	local Enum = env.Enum

	local Wiring = {}

	Wiring.Defaults = {
		ZonesFolder = "Zones",
		Lobby = "Lobby",
		BarrierHeight = 40,
		BarrierThickness = 1.5,
		BarrierColor = Color3.fromRGB(25, 25, 35),
		BarrierTransparency = 0.5,
		BarrierMaterial = "SmoothPlastic",
		SpawnDepth = 12, -- studs past the gate line
		BoxHeight = 100, -- ZoneSize.Y
		-- What a sign says for zone n.
		NameOf = function(n: number): string
			return `Zone {n}`
		end,
	}

	local UP = Vector3.new(0, 1, 0)

	-- "Zone7" / "zone 7" → 7
	function Wiring.numberOf(name: string): number?
		return tonumber(string.match(string.lower(name), "^zone%s*(%d+)$"))
	end

	function Wiring.idOf(n: number): string
		return string.format("%03d", n)
	end

	-- World-space axis-aligned box of a part.
	local function aabb(part: any): (any, any)
		local cf, size = part.CFrame, part.Size
		local half = Vector3.new(
			math.abs(cf.XVector.X) * size.X + math.abs(cf.YVector.X) * size.Y + math.abs(cf.ZVector.X) * size.Z,
			math.abs(cf.XVector.Y) * size.X + math.abs(cf.YVector.Y) * size.Y + math.abs(cf.ZVector.Y) * size.Z,
			math.abs(cf.XVector.Z) * size.X + math.abs(cf.YVector.Z) * size.Y + math.abs(cf.ZVector.Z) * size.Z
		) / 2
		local p = cf.Position
		return p - half, p + half
	end

	local function flat(v: any): any
		return Vector3.new(v.X, 0, v.Z)
	end

	local function insideXZ(lo: any, hi: any, p: any, pad: number?): boolean
		local m = pad or 0
		return p.X >= lo.X - m and p.X <= hi.X + m and p.Z >= lo.Z - m and p.Z <= hi.Z + m
	end

	local function isPart(i: any): boolean
		return i:IsA("BasePart")
	end

	local function findDescendant(root: any, name: string): { any }
		local out = {}
		for _, d in root:GetDescendants() do
			if d.Name == name then
				table.insert(out, d)
			end
		end
		return out
	end

	--------------------------------------------------------------------------
	-- Zones
	--------------------------------------------------------------------------

	type Zone = {
		n: number, -- 0 = Lobby
		id: string?,
		model: any,
		ground: any?,
		lo: any, -- footprint (Ground + its DividerLines)
		hi: any,
		boxLo: any, -- the zone's box, cut at gate lines
		boxHi: any,
	}

	local function footprint(model: any, ground: any?): (any?, any?)
		local lo, hi = nil, nil
		local function add(part: any)
			local a, b = aabb(part)
			lo = if lo then lo:Min(a) else a
			hi = if hi then hi:Max(b) else b
		end
		if ground then add(ground) end
		for _, d in findDescendant(model, "DividerLine") do
			if isPart(d) then add(d) end
		end
		return lo, hi
	end

	function Wiring.collectZones(folder: any): ({ [number]: Zone }, Zone?, { any })
		local zones: { [number]: Zone } = {}
		local lobby: Zone? = nil
		local others = {}
		for _, child in folder:GetChildren() do
			local n = Wiring.numberOf(child.Name)
			local ground = child:FindFirstChild("Ground")
			if ground and not isPart(ground) then ground = nil end
			if n or child.Name == Wiring.Defaults.Lobby then
				local lo, hi = footprint(child, ground)
				if lo then
					local zone: Zone = {
						n = n or 0, id = if n then Wiring.idOf(n) else nil, model = child, ground = ground,
						lo = lo, hi = hi, boxLo = lo, boxHi = hi,
					}
					if n then zones[n] = zone else lobby = zone end
				else
					table.insert(others, child)
				end
			else
				table.insert(others, child)
			end
		end
		return zones, lobby, others
	end

	-- The zone whose footprint holds p; the nearest centre wins when they overlap.
	local function zoneAt(all: { Zone }, p: any): Zone?
		local best, bestScore = nil, math.huge
		for _, zone in all do
			if insideXZ(zone.lo, zone.hi, p) then
				local c = (zone.lo + zone.hi) / 2
				local half = (zone.hi - zone.lo) / 2
				local score = math.abs(p.X - c.X) / math.max(half.X, 1) + math.abs(p.Z - c.Z) / math.max(half.Z, 1)
				if score < bestScore then
					best, bestScore = zone, score
				end
			end
		end
		return best
	end

	--------------------------------------------------------------------------
	-- Gates
	--------------------------------------------------------------------------

	type Gate = {
		zone: Zone, -- gated (entered by crossing the line)
		from: Zone?, -- the side players come from
		a: any, -- line ends (world)
		b: any,
		dir: any, -- unit, along the line (flat)
		inward: any, -- unit, flat, pointing into `zone`
		length: number, -- barrier length (ground width)
		center: any, -- middle of the barrier on the line
		y: number, -- line height
		line: any?, -- the DividerLine part (nil when made up)
	}

	local function attachmentsOf(line: any): { any }
		local out = {}
		for _, c in line:GetChildren() do
			if c:IsA("Attachment") then
				table.insert(out, (line.CFrame * c.CFrame).Position)
			end
		end
		return out
	end

	-- A part's extent along a flat unit direction.
	local function extentAlong(part: any, dir: any): number
		local cf, size = part.CFrame, part.Size
		return math.abs(cf.XVector:Dot(dir)) * size.X + math.abs(cf.YVector:Dot(dir)) * size.Y + math.abs(cf.ZVector:Dot(dir)) * size.Z
	end

	local function makeGate(zone: Zone, from: Zone?, a: any, b: any, line: any?): Gate
		local dir = flat(b - a).Unit
		local mid = (a + b) / 2
		local normal = Vector3.new(-dir.Z, 0, dir.X)
		local zc = (zone.lo + zone.hi) / 2
		if flat(zc - mid):Dot(normal) < 0 then
			normal = -normal
		end
		local length, center = (b - a).Magnitude, mid
		if line then
			-- As wide as the ground: the DividerLine part's extent along the line.
			length = extentAlong(line, dir)
			local along = (line.CFrame.Position - mid):Dot(dir)
			center = mid + dir * along
		end
		return {
			zone = zone, from = from, a = a, b = b, dir = dir, inward = normal,
			length = length, center = Vector3.new(center.X, mid.Y, center.Z), y = mid.Y, line = line,
		}
	end

	-- The line between two touching footprints (prev → zone), from their seam.
	local function seamGate(zone: Zone, prev: Zone): Gate?
		local d = (zone.lo + zone.hi) / 2 - (prev.lo + prev.hi) / 2
		local y = prev.hi.Y
		if math.abs(d.X) >= math.abs(d.Z) then
			local x = if d.X > 0 then prev.hi.X else prev.lo.X
			local z0, z1 = math.max(prev.lo.Z, zone.lo.Z), math.min(prev.hi.Z, zone.hi.Z)
			if z1 - z0 < 4 then return nil end
			return makeGate(zone, prev, Vector3.new(x, y, z0), Vector3.new(x, y, z1), nil)
		else
			local z = if d.Z > 0 then prev.hi.Z else prev.lo.Z
			local x0, x1 = math.max(prev.lo.X, zone.lo.X), math.min(prev.hi.X, zone.hi.X)
			if x1 - x0 < 4 then return nil end
			return makeGate(zone, prev, Vector3.new(x0, y, z), Vector3.new(x1, y, z), nil)
		end
	end

	function Wiring.findGates(folder: any, zones: { [number]: Zone }, lobby: Zone?, report: Report): { [number]: Gate }
		local all: { Zone } = {}
		for _, zone in zones do table.insert(all, zone) end
		if lobby then table.insert(all, lobby) end

		local gates: { [number]: Gate } = {}
		for _, line in findDescendant(folder, "DividerLine") do
			if not isPart(line) then continue end
			local ends = attachmentsOf(line)
			if #ends < 2 then
				table.insert(report.problems, `{line:GetFullName()} needs two Attachments (found {#ends})`)
				continue
			end
			local a, b = ends[1], ends[2]
			local mid = (a + b) / 2
			local dir = flat(b - a).Unit
			local normal = Vector3.new(-dir.Z, 0, dir.X)
			local one, two = zoneAt(all, mid + normal * 10), zoneAt(all, mid - normal * 10)
			if not one or not two or one == two then
				table.insert(report.problems, `{line:GetFullName()} isn't between two zones (is it on a zone edge?)`)
				continue
			end
			local gated, from = one, two
			if two.n > one.n then gated, from = two, one end
			if gated.n == 0 then continue end
			if from.n ~= gated.n - 1 then
				table.insert(report.problems, `{line:GetFullName()} joins Zone{from.n} to Zone{gated.n}: zones should join in order`)
			end
			local existing = gates[gated.n]
			if existing then
				-- Keep the one that sits in the zone it gates.
				local mine = line:IsDescendantOf(gated.model)
				if mine and not (existing.line and existing.line:IsDescendantOf(gated.model)) then
					gates[gated.n] = makeGate(gated, from, a, b, line)
				end
				table.insert(report.lines, `Zone{gated.n} has two DividerLines; using {gates[gated.n].line:GetFullName()}`)
				continue
			end
			gates[gated.n] = makeGate(gated, from, a, b, line)
			if not line:IsDescendantOf(gated.model) then
				table.insert(report.lines, `Zone{gated.n}'s entrance is {line:GetFullName()} (it sits in another zone's model; that's fine)`)
			end
		end

		for n, zone in zones do
			if not gates[n] then
				local prev = if n == 1 then lobby else zones[n - 1]
				local gate = if prev then seamGate(zone, prev) else nil
				if gate then
					gates[n] = gate
					table.insert(report.problems, `Zone{n} has no DividerLine at its entrance: made the gate from the ground seam with {prev.model.Name}. Add a DividerLine there to place it yourself`)
				else
					table.insert(report.problems, `Zone{n} has no DividerLine and doesn't touch {if prev then prev.model.Name else "the previous zone"}: no gate`)
				end
			end
		end
		return gates
	end

	--------------------------------------------------------------------------
	-- Spawns
	--------------------------------------------------------------------------

	-- Collidable parts that could be in the way, with their boxes.
	type Solid = { part: any, lo: any, hi: any }
	local function solidsOf(roots: { any }, skip: { [any]: boolean }): { Solid }
		local out = {}
		for _, root in roots do
			for _, d in root:GetDescendants() do
				if isPart(d) and d.CanCollide and not skip[d] and d.Name ~= "DividerLine" then
					local lo, hi = aabb(d)
					table.insert(out, { part = d, lo = lo, hi = hi })
				end
			end
		end
		return out
	end

	-- The top of whatever a player would stand on at (x, z), at or below `below`.
	local function floorAt(solids: { Solid }, p: any, below: number): number?
		local best = nil
		for _, s in solids do
			if insideXZ(s.lo, s.hi, p) and s.hi.Y <= below and (best == nil or s.hi.Y > best) then
				-- Thin floors only (a pillar's top isn't a floor).
				if s.hi.Y - s.lo.Y <= 12 or s.part.Name == "Ground" then
					best = s.hi.Y
				end
			end
		end
		return best
	end

	local function blocked(solids: { Solid }, feet: any, radius: number): boolean
		local lo = feet + Vector3.new(-radius, 0.6, -radius)
		local hi = feet + Vector3.new(radius, 6, radius)
		for _, s in solids do
			if s.lo.X < hi.X and s.hi.X > lo.X and s.lo.Y < hi.Y and s.hi.Y > lo.Y and s.lo.Z < hi.Z and s.hi.Z > lo.Z then
				return true
			end
		end
		return false
	end

	-- A clear standing spot near `origin`, trying offsets across / along.
	local function clearSpot(solids: { Solid }, origin: any, across: any, along: any, top: number): any?
		for _, depth in { 0, 4, 8, 12, 16 } do
			for _, side in { 0, 6, -6, 12, -12, 18, -18, 24, -24 } do
				local p = origin + along * depth + across * side
				local y = floorAt(solids, p, top)
				if y then
					local feet = Vector3.new(p.X, y, p.Z)
					if not blocked(solids, feet, 2.5) then
						return feet
					end
				end
			end
		end
		return nil
	end

	local function spawnPart(parent: any, name: string, feet: any, facing: any, className: string?): any
		local part = Instance.new(className or "Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Transparency = 1
		part.CastShadow = false
		part.Size = Vector3.new(6, 1, 6)
		part.CFrame = CFrame.lookAt(feet + Vector3.new(0, 0.5, 0), feet + Vector3.new(0, 0.5, 0) + facing)
		part.Parent = parent
		return part
	end

	--------------------------------------------------------------------------
	-- Wire
	--------------------------------------------------------------------------

	function Wiring.wire(workspace: any, options: any?): Report
		local o = table.clone(Wiring.Defaults)
		for k, v in options or {} do o[k] = v end
		local report: Report = { lines = {}, problems = {} }

		local folder = workspace:FindFirstChild(o.ZonesFolder)
		if not folder then
			table.insert(report.problems, `workspace.{o.ZonesFolder} is missing`)
			return report
		end
		local zones, lobby, others = Wiring.collectZones(folder)
		local count = 0
		for n in zones do count = math.max(count, n) end
		for n = 1, count do
			if not zones[n] then
				table.insert(report.problems, `Zone{n} is missing (or has no Ground part)`)
			end
		end

		-- Not zones: the game would see unknown zone ids.
		for _, other in others do
			if other:HasTag("Zone") then
				other:RemoveTag("Zone")
				table.insert(report.lines, `untagged {other.Name} (under {o.ZonesFolder} but not a zone)`)
			end
		end
		if lobby and lobby.model:HasTag("Zone") then
			lobby.model:RemoveTag("Zone")
		end

		local gates = Wiring.findGates(folder, zones, lobby, report)

		-- Zone boxes, cut at the gate lines so neighbours don't overlap.
		for _, gate in gates do
			local axisX = math.abs(gate.inward.X) > 0.99
			local axisZ = math.abs(gate.inward.Z) > 0.99
			for _, zone in { gate.zone, gate.from } do
				if zone and zone.n > 0 then
					local into = if zone == gate.zone then gate.inward else -gate.inward
					if axisX then
						if into.X > 0 then
							zone.boxLo = Vector3.new(math.max(zone.boxLo.X, gate.center.X), zone.boxLo.Y, zone.boxLo.Z)
						else
							zone.boxHi = Vector3.new(math.min(zone.boxHi.X, gate.center.X), zone.boxHi.Y, zone.boxHi.Z)
						end
					elseif axisZ then
						if into.Z > 0 then
							zone.boxLo = Vector3.new(zone.boxLo.X, zone.boxLo.Y, math.max(zone.boxLo.Z, gate.center.Z))
						else
							zone.boxHi = Vector3.new(zone.boxHi.X, zone.boxHi.Y, math.min(zone.boxHi.Z, gate.center.Z))
						end
					end
				end
			end
		end

		-- SpawnLocations: only the Lobby's.
		for _, d in folder:GetDescendants() do
			if d:IsA("SpawnLocation") and d.Name ~= "LobbySpawn" and d.Enabled then
				d.Enabled = false
				table.insert(report.lines, `turned off {d:GetFullName()}`)
			end
		end

		for n = 1, count do
			local zone = zones[n]
			if not zone then continue end
			local model = zone.model
			model:SetAttribute("ZoneId", zone.id)
			model:AddTag("Zone")
			local lo, hi = zone.boxLo, zone.boxHi
			model:SetAttribute("Center", Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2))
			model:SetAttribute("ZoneSize", Vector3.new(hi.X - lo.X, o.BoxHeight, hi.Z - lo.Z))
			if zone.ground and not zone.ground:HasTag("EnemyGround") then
				zone.ground:AddTag("EnemyGround")
			end

			-- Rebuild what we made last time.
			local old = model:FindFirstChild("Gate")
			if old then old:Destroy() end
			local gate = gates[n]
			if not gate then continue end
			local holder = Instance.new("Folder")
			holder.Name = "Gate"
			holder.Parent = model

			-- Barrier: from the lower floor beside the line up to line + height.
			local floorBelow = gate.y
			for _, side in { gate.zone, gate.from } do
				if side and side.ground then
					local _, top = aabb(side.ground)
					floorBelow = math.min(floorBelow, top.Y)
				end
			end
			local bottom = floorBelow
			local top = gate.y + o.BarrierHeight
			local barrier = Instance.new("Part")
			barrier.Name = "Barrier"
			barrier.Anchored = true
			barrier.CanCollide = true
			barrier.CanTouch = false
			barrier.CanQuery = true -- the BUY button on it needs clicks to land
			barrier.CastShadow = false
			barrier.Color = o.BarrierColor
			barrier.Transparency = o.BarrierTransparency
			barrier.Material = Enum.Material[o.BarrierMaterial]
			barrier.Size = Vector3.new(gate.length, top - bottom, o.BarrierThickness)
			local at = Vector3.new(gate.center.X, (top + bottom) / 2, gate.center.Z)
			-- X along the line, Z across it: the sign faces both ways.
			barrier.CFrame = CFrame.fromMatrix(at, gate.dir, UP)
			barrier:SetAttribute("ZoneId", zone.id)
			barrier:AddTag("ZoneBarrier")
			barrier.Parent = holder

			-- Spawn: just past the line, somewhere clear.
			local skip = { [barrier] = true }
			local solids = solidsOf({ model }, skip)
			if gate.from then
				for _, s in solidsOf({ gate.from.model }, skip) do table.insert(solids, s) end
			end
			local origin = gate.center + gate.inward * o.SpawnDepth
			local groundTop = if zone.ground then select(2, aabb(zone.ground)).Y else gate.y
			local feet = clearSpot(solids, origin, gate.dir, gate.inward, math.max(gate.y, groundTop) + 6)
			if not feet then
				feet = Vector3.new(origin.X, groundTop, origin.Z)
				table.insert(report.problems, `Zone{n}: no clear spot past the gate for the spawn; put Gate.Spawn somewhere clear`)
			end
			local spawn = spawnPart(holder, "Spawn", feet, gate.inward)
			spawn:SetAttribute("ZoneId", zone.id)
			spawn:AddTag("ZoneSpawn")
		end

		-- The Lobby's SpawnLocation (where everyone joins).
		if lobby then
			local existing = lobby.model:FindFirstChild("LobbySpawn")
			if existing then existing:Destroy() end
			local solids = solidsOf({ lobby.model }, {})
			local center = (lobby.lo + lobby.hi) / 2
			local toward = Vector3.new(1, 0, 0)
			if zones[1] then
				toward = flat((zones[1].lo + zones[1].hi) / 2 - center).Unit
			end
			local feet = clearSpot(solids, center, Vector3.new(-toward.Z, 0, toward.X), toward, lobby.hi.Y + 6)
				or Vector3.new(center.X, lobby.hi.Y, center.Z)
			local spawn = spawnPart(lobby.model, "LobbySpawn", feet, toward, "SpawnLocation")
			spawn.Neutral = true
			spawn.Duration = 0
			spawn.Enabled = true
			table.insert(report.lines, string.format("Lobby spawn at (%.0f, %.0f, %.0f)", feet.X, feet.Y, feet.Z))
		else
			table.insert(report.problems, `{o.ZonesFolder}.{o.Lobby} is missing: nowhere for players to join`)
		end

		-- Signs: each names the zone whose model it sits in.
		local signs = 0
		for n = 1, count do
			local zone = zones[n]
			if not zone then continue end
			for _, sign in findDescendant(zone.model, "signage") do
				local labels = 0
				for _, d in sign:GetDescendants() do
					if d:IsA("TextLabel") then
						d.Text = o.NameOf(n)
						labels += 1
					end
				end
				if labels > 0 then
					sign:SetAttribute("ZoneId", zone.id)
					sign:AddTag("ZoneSign")
					signs += 1
				end
			end
		end

		local gateCount = 0
		for _ in gates do gateCount += 1 end
		table.insert(report.lines, `{count} zones, {gateCount} gates, {signs} signs`)
		return report
	end

	return Wiring
end
