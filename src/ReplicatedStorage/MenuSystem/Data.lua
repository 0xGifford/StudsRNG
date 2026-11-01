--!strict
-- ModuleScript -> ReplicatedStorage/MenuSystem/Data
--
-- Where MenuSystem reads the player's data (DataLabel and friends). The game
-- plugs its own client state in once at boot (Controllers/MenuSystem):
--
--   Data.Provide({
--       isReady = function() -> boolean,
--       get = function(field) -> any,           -- a top-level field
--       changed = Signal of (field, value),     -- fires on every change
--   })
--
-- Paths are dotted: "Clacks", "Stats.Luck", "Daily.Streak". The first part
-- is the field, the rest indexes into it.
--
--   Data.IsReady() -> boolean
--   Data.Get(path, default) -> any
--   Data.Observe(path, fn(value, previous)) -> disconnect()
--       calls fn with the current value at once, then on every change

local Signal = require(script.Parent.Core.Signal)

type Provider = {
	isReady: () -> boolean,
	get: (string) -> any,
	changed: any,
}

local Data = {}

local provider: Provider? = nil
local provided = Signal.new()

local function split(path: string): { string }
	return string.split(path, ".")
end

local function resolve(parts: { string }): any
	local current = provider
	if not current then return nil end
	local value = current.get(parts[1])
	for i = 2, #parts do
		if type(value) ~= "table" then return nil end
		value = value[parts[i]]
	end
	return value
end

function Data.Provide(source: Provider)
	provider = source
	provided:Fire()
end

function Data.IsReady(): boolean
	local current = provider
	return current ~= nil and current.isReady()
end

function Data.Get(path: string, default: any): any
	local value = resolve(split(path))
	if value == nil then return default end
	return value
end

function Data.Observe(path: string, fn: (any, any) -> ()): () -> ()
	local parts = split(path)
	local field = parts[1]
	local previous = resolve(parts)
	local connection: any = nil
	local alive = true

	local function attach()
		local current = provider
		if not current or not alive then return end
		previous = resolve(parts)
		fn(previous, nil)
		connection = current.changed:Connect(function(changedField: string)
			if changedField ~= field then return end
			local value = resolve(parts)
			if value ~= previous then
				local old = previous
				previous = value
				fn(value, old)
			end
		end)
	end

	if provider then
		attach()
	else
		local waiting
		waiting = provided:Connect(function()
			waiting:Disconnect()
			attach()
		end)
	end

	return function()
		alive = false
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end
end

return Data
