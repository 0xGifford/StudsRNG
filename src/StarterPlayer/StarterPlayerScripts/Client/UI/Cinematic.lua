--[[

Cinematic
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/UI/Cinematic

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Camera shots that never clip through the map, whatever the zone looks
-- like (used by the intro).
--   Cinematic.shot(center, size)   picks an opening and closing camera
--                                  position with a clear view of the zone
--   Cinematic.fly(from, to, focus, seconds, cancelled)
--                                  flies between them, and every frame pulls
--                                  the camera in front of anything that
--                                  would come between it and the focus
-- Invisible parts (Transparency >= 0.9: zone bounds, hitboxes, barriers'
-- collision boxes) never block the view.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Cinematic = {}

local INVISIBLE = 0.9
local MARGIN = 1.6 -- studs the camera keeps in front of whatever it hit

local ignored: { Instance } = {}
local ignoredSet: { [Instance]: boolean } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function ignore(instance: Instance)
	if ignoredSet[instance] then return end
	ignoredSet[instance] = true
	table.insert(ignored, instance)
	rayParams.FilterDescendantsInstances = ignored
	overlapParams.FilterDescendantsInstances = ignored
end

local function refreshCharacters()
	for _, player in Players:GetPlayers() do
		if player.Character then
			ignore(player.Character)
		end
	end
end

local function blocks(part: BasePart): boolean
	return part.Transparency < INVISIBLE
end

-- The first visible part between two points, or nil.
function Cinematic.cast(from: Vector3, to: Vector3): RaycastResult?
	refreshCharacters()
	local direction = to - from
	for _ = 1, 8 do
		local hit = workspace:Raycast(from, direction, rayParams)
		if not hit then return nil end
		if hit.Instance:IsA("BasePart") and blocks(hit.Instance) then
			return hit
		end
		ignore(hit.Instance)
	end
	return nil
end

-- Is there room for a camera here (no visible part within `radius`)?
function Cinematic.clear(position: Vector3, radius: number?): boolean
	for _, part in workspace:GetPartBoundsInRadius(position, radius or 2.5, overlapParams) do
		if blocks(part) then
			return false
		end
	end
	return true
end

-- The floor under a point (or the point itself when there's none).
function Cinematic.ground(position: Vector3): Vector3
	local hit = Cinematic.cast(position + Vector3.new(0, 40, 0), Vector3.new(position.X, position.Y - 300, position.Z))
	return if hit then hit.Position else position
end

-- Where the camera may go on the line from focus to want: in front of the
-- first thing in the way.
function Cinematic.unblocked(focus: Vector3, want: Vector3): Vector3
	local hit = Cinematic.cast(focus, want)
	if not hit then return want end
	local back = focus - hit.Position
	local distance = back.Magnitude
	if distance <= MARGIN then return focus end
	return hit.Position + back.Unit * MARGIN
end

export type Shot = { focus: Vector3, from: Vector3, to: Vector3 }

-- An opening and closing position looking at a zone. `size` is the zone's
-- box (for how far out and how high the camera may go); `side` alternates
-- which way shots lean.
function Cinematic.shot(center: Vector3, size: Vector3?, side: number?): Shot
	refreshCharacters()
	local focus = Cinematic.ground(center) + Vector3.new(0, 5, 0)
	local extent = if size then math.min(size.X, size.Z) else 120
	local reach = math.clamp(extent * 0.42, 22, 95)
	-- Zone boxes reach size.Y above the floor less 10 (Tags.zoneBox); stay under that.
	local ceiling = if size then center.Y + size.Y - 14 else focus.Y + 70
	local headroom = math.max(ceiling - focus.Y, 8)
	local lean = side or 1

	-- Around the focus, far and high first, closer and lower until clear.
	local start = math.random() * math.pi * 2
	local best: Vector3? = nil
	local bestScore = -1
	for step = 0, 11 do
		local angle = start + lean * step * (math.pi * 2 / 12)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		for _, scale in { 1, 0.78, 0.58, 0.4 } do
			local distance = reach * scale
			local height = math.clamp(distance * 0.55, 8, headroom)
			local position = focus + direction * distance + Vector3.new(0, height, 0)
			if Cinematic.clear(position) and not Cinematic.cast(focus, position) then
				local score = distance
				if score > bestScore then
					best, bestScore = position, score
				end
				break
			end
		end
		if bestScore >= reach * 0.99 then break end
	end
	local from = best or Cinematic.unblocked(focus, focus + Vector3.new(0, math.min(30, headroom), 12))

	-- Closing: in toward the focus and a little around, still in the clear.
	local offset = from - focus
	local turned = CFrame.Angles(0, math.rad(22 * lean), 0) * (offset * 0.55)
	local to = focus + turned
	if not Cinematic.clear(to) or Cinematic.cast(focus, to) then
		to = focus + offset * 0.55 -- on the line we know is clear
	end
	return { focus = focus, from = from, to = to }
end

local function ease(t: number): number
	-- Sine in-out.
	return -(math.cos(math.pi * t) - 1) / 2
end

-- Flies the camera from → to looking at focus (or from a focus moving with
-- the target, when focus is a function), kept unoccluded every frame.
-- Returns early when cancelled() is true.
function Cinematic.fly(from: Vector3, to: Vector3, focus: Vector3 | () -> Vector3, seconds: number, cancelled: (() -> boolean)?)
	local camera = workspace.CurrentCamera
	local started = os.clock()
	while true do
		local t = math.clamp((os.clock() - started) / math.max(seconds, 0.01), 0, 1)
		local look = if type(focus) == "function" then focus() else focus
		local want = from:Lerp(to, ease(t))
		local position = Cinematic.unblocked(look, want)
		camera.CFrame = CFrame.lookAt(position, look)
		if t >= 1 or (cancelled and cancelled()) then break end
		RunService.RenderStepped:Wait()
	end
end

return Cinematic
