--[[

BarrierTextures
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/BarrierTextures

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Scrolls the textures on zone barriers from left to right (locally).
--
-- Every Texture inside a ZoneBarrier-tagged part or model is animated, on
-- every face, so you don't tag textures one by one. Settings, as attributes
-- (on the Texture, else on the barrier it belongs to, else the defaults):
--   ScrollSpeed  number   studs per second along the face (default 4).
--                         Negative scrolls right to left.
--   ScrollV      number   studs per second up / down too (default 0)
--   Scroll       boolean  false to leave this one still
-- A texture whose part is hidden (an opened barrier, Transparency 1) is
-- hidden with it and stops moving; it comes back if the part does.
-- Only barriers within RANGE studs of the camera's focus animate.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tags = require(Shared.Tags)

local BarrierTextures = {}

local DEFAULT_SPEED = 4 -- studs per second, left to right
local RANGE = 400 -- studs from the camera's focus
local RANGE_CHECK = 0.5 -- seconds between distance checks

type Entry = {
	texture: Texture,
	barrier: Instance,
	part: BasePart?,
	transparency: number, -- the texture's own, to restore
	hidden: boolean,
	near: boolean,
}

local entries: { [Texture]: Entry } = {}
local watched: { [Instance]: { RBXScriptConnection } } = {}

local function setting(entry: Entry, name: string, default: any): any
	local own = entry.texture:GetAttribute(name)
	if own ~= nil and typeof(own) == typeof(default) then
		return own
	end
	local fromBarrier = entry.barrier:GetAttribute(name)
	if fromBarrier ~= nil and typeof(fromBarrier) == typeof(default) then
		return fromBarrier
	end
	return default
end

local function add(texture: Instance, barrier: Instance)
	if not texture:IsA("Texture") or entries[texture] then return end
	local part = texture.Parent
	entries[texture] = {
		texture = texture,
		barrier = barrier,
		part = if part and part:IsA("BasePart") then part else nil,
		transparency = texture.Transparency,
		hidden = false,
		near = true,
	}
end

local function remove(texture: Instance)
	local entry = entries[texture :: Texture]
	if not entry then return end
	entries[texture :: Texture] = nil
	if entry.hidden and texture.Parent then
		(texture :: Texture).Transparency = entry.transparency
	end
end

local function track(barrier: Instance)
	if watched[barrier] then return end
	if barrier:IsA("Texture") then
		-- A tagged texture on its own: its part is the barrier.
		add(barrier, barrier.Parent or barrier)
		return
	end
	for _, d in barrier:GetDescendants() do
		add(d, barrier)
	end
	-- Streaming / edits: textures can arrive or leave later.
	watched[barrier] = {
		barrier.DescendantAdded:Connect(function(d)
			add(d, barrier)
		end),
		barrier.DescendantRemoving:Connect(remove),
	}
end

local function untrack(barrier: Instance)
	local connections = watched[barrier]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
		watched[barrier] = nil
	end
	for texture, entry in entries do
		if entry.barrier == barrier then
			remove(texture)
		end
	end
end

-- Barriers out of range don't move (cheap); opened ones hide their textures.
local function refresh()
	local camera = workspace.CurrentCamera
	local focus = if camera then camera.Focus.Position else Vector3.zero
	for texture, entry in entries do
		if not texture.Parent then
			entries[texture] = nil
			continue
		end
		local part = entry.part
		entry.near = part == nil or (part.Position - focus).Magnitude <= RANGE

		local hide = part ~= nil and part.Transparency >= 0.99
		if hide ~= entry.hidden then
			if hide then
				entry.transparency = texture.Transparency
				texture.Transparency = 1
			else
				texture.Transparency = entry.transparency
			end
			entry.hidden = hide
		end
	end
end

local function step(dt: number)
	for texture, entry in entries do
		if entry.hidden or not entry.near or setting(entry, "Scroll", true) == false then
			continue
		end
		local speed = setting(entry, "ScrollSpeed", DEFAULT_SPEED)
		local vertical = setting(entry, "ScrollV", 0)
		-- Wrap at the tile size, so the offset never grows without limit.
		local tileU = math.max(texture.StudsPerTileU, 0.01)
		local tileV = math.max(texture.StudsPerTileV, 0.01)
		-- Offsets move the image the other way: subtract to scroll toward +U
		-- (to the right, seen from the face's own side).
		texture.OffsetStudsU = (texture.OffsetStudsU - speed * dt) % tileU
		if vertical ~= 0 then
			texture.OffsetStudsV = (texture.OffsetStudsV - vertical * dt) % tileV
		end
	end
end

function BarrierTextures.start()
	for _, barrier in CollectionService:GetTagged(Tags.ZoneBarrier) do
		track(barrier)
	end
	CollectionService:GetInstanceAddedSignal(Tags.ZoneBarrier):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Tags.ZoneBarrier):Connect(untrack)

	RunService.RenderStepped:Connect(step)
	task.spawn(function()
		while true do
			refresh()
			task.wait(RANGE_CHECK)
		end
	end)
end

return BarrierTextures
