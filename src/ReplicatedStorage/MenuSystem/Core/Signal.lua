--!strict
-- ModuleScript -> ReplicatedStorage/MenuSystem/Core/Signal
--
-- Deliberately tiny. BindableEvents deep-copy their arguments, which makes
-- passing tables between listeners lossy; this doesn't.

export type Connection = { Disconnect: (Connection) -> () }

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	local handlers = self._handlers
	table.insert(handlers, fn)

	return {
		Disconnect = function()
			local index = table.find(handlers, fn)
			if index then table.remove(handlers, index) end
		end,
	}
end

function Signal:Once(fn: (...any) -> ())
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...)
	-- Iterate a copy so a handler disconnecting mid-fire can't skip the next
	for _, fn in ipairs(table.clone(self._handlers)) do
		local ok, err = pcall(fn, ...)
		if not ok then warn("[Signal] handler error: " .. tostring(err)) end
	end
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal