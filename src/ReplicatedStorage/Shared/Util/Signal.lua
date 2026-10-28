--[[ 

Signal
ModuleScript
/ReplicatedStorage/Shared/Util/Signal

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Minimal signal for cross-system events. Handlers run in their own thread
-- so one erroring listener can't break the others.

export type Connection = { Disconnect: (self: Connection) -> (), Connected: boolean }

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({ _handlers = {} :: { [any]: (T...) -> () } }, Signal)
	return (self :: any) :: Signal<T...>
end

function Signal:Connect(fn)
	local connection = { Connected = true }
	local handlers = self._handlers
	handlers[connection] = fn
	function connection.Disconnect(conn)
		conn.Connected = false
		handlers[conn] = nil
	end
	return connection
end

function Signal:Fire(...)
	for _, fn in self._handlers do
		task.spawn(fn, ...)
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

return Signal
