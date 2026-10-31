--!strict
-- Single responsibility: know which keys exist.
-- Follows the tag, instantiates/destroys Keycap, and keeps the filter list
-- for overlap checks up to date (recomputed only when it changes, not every frame).

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Parent.Config)
local Keycap = require(script.Parent.Keycap)

local KeycapRegistry = {}
KeycapRegistry.__index = KeycapRegistry

function KeycapRegistry.new()
	local self = setmetatable({}, KeycapRegistry)
	self.byHitbox = {}
	-- Kept incrementally rather than counted on demand: Count() used to walk
	-- the whole table, and the DEBUG log below calls it once PER key arriving.
	-- On a board of several thousand that made startup quadratic.
	self.count = 0
	self.pending = {} -- hitbox that arrived without its Cap (streaming in progress)
	self.connections = {}
	self._filterDirty = true
	self._filterList = {}
	return self
end

function KeycapRegistry:Start()
	for _, hitbox in ipairs(CollectionService:GetTagged(Config.TAG_HITBOX)) do
		self:_add(hitbox)
	end
	table.insert(self.connections, CollectionService:GetInstanceAddedSignal(Config.TAG_HITBOX):Connect(function(h)
		self:_add(h)
	end))
	table.insert(self.connections, CollectionService:GetInstanceRemovedSignal(Config.TAG_HITBOX):Connect(function(h)
		self:_remove(h)
	end))
end

function KeycapRegistry:_add(hitbox: Instance)
	if not hitbox:IsA("BasePart") or self.byHitbox[hitbox] then return end

	local keycap = Keycap.new(hitbox)
	if keycap then
		self.byHitbox[hitbox] = keycap
		self.count += 1
		self._filterDirty = true
		if Config.DEBUG then
			print("[KeyCapper] + key", hitbox:GetFullName(), "total:", self.count)
		end
		return
	end

	-- The Cap hasn't streamed in yet: retry as soon as it arrives.
	self:_waitForCap(hitbox)
end

function KeycapRegistry:_waitForCap(hitbox: BasePart)
	if self.pending[hitbox] then return end
	local model = hitbox.Parent
	if not model then return end

	local connection
	connection = model.ChildAdded:Connect(function(child)
		if child.Name ~= "Cap" then return end
		connection:Disconnect()
		self.pending[hitbox] = nil
		if hitbox.Parent then
			self:_add(hitbox)
		end
	end)
	self.pending[hitbox] = connection
end

function KeycapRegistry:_remove(hitbox: Instance)
	local waiting = self.pending[hitbox]
	if waiting then
		waiting:Disconnect()
		self.pending[hitbox] = nil
	end

	local keycap = self.byHitbox[hitbox]
	if not keycap then return end

	keycap:Destroy()
	self.byHitbox[hitbox] = nil
	self.count -= 1
	self._filterDirty = true
	if Config.DEBUG then
		print("[KeyCapper] - key (streamed out), total:", self.count)
	end
end

-- List of hitboxes to pass as the OverlapParams whitelist.
function KeycapRegistry:GetFilterList(): { BasePart }
	if self._filterDirty then
		local list = {}
		for hitbox in pairs(self.byHitbox) do
			table.insert(list, hitbox)
		end
		self._filterList = list
		self._filterDirty = false
	end
	return self._filterList
end

function KeycapRegistry:Get(hitbox: BasePart)
	return self.byHitbox[hitbox]
end

function KeycapRegistry:All()
	return self.byHitbox
end

function KeycapRegistry:Count(): number
	return self.count
end

return KeycapRegistry
