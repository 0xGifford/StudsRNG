--!strict
-- Single responsibility: make sure a group gets restyled soon, once, and
-- never twice over the same keys at the same time.
--
-- Exists because a slider fires a value change on every frame of a drag, and
-- each one invalidates the whole group's look. Running GroupStyler on every
-- one of them was both the freeze and wasted work: of the hundred values a
-- drag passes through, only the last is ever seen. Requests coalesce into one
-- pending pass per group, and a pass already in flight is abandoned the
-- moment its own group is requested again.

local GroupStyler = require(script.Parent.GroupStyler)

local RestyleQueue = {}

local pending: { [string]: true } = {}
local running = false

local function pump()
	if running then return end
	running = true

	task.spawn(function()
		-- Drains rather than iterating once: a request that lands mid-pass
		-- (the usual case during a drag) has to be picked up without waiting
		-- for another caller to restart the pump.
		while next(pending) do
			local names = {}
			for name in pairs(pending) do
				table.insert(names, name)
			end
			pending = {}

			for _, name in ipairs(names) do
				-- Deliberately NOT aborted when the group goes dirty again
				-- mid-pass, which is the normal case during a drag. Restarting
				-- on every new value livelocks: a pass opens with an
				-- unchunkable GetTagged (~27ms on a 9k board), gets abandoned a
				-- chunk later, and pays that cost again having painted almost
				-- nothing — so the keys never visibly move while the slider is
				-- held. Letting the pass finish and running exactly one more
				-- lap afterwards repaints at a steady few frames per second and
				-- wastes no work, and the coalescing above still collapses the
				-- hundred values in between into that single lap.
				GroupStyler.Apply(name)
			end
		end
		running = false
	end)
end

function RestyleQueue.Request(name: string)
	pending[name] = true
	pump()
end

-- Whether anything is still queued or in flight. Callers that have to close
-- an undo recording need it: committing before the restyle lands would leave
-- the colours it writes outside the entry that owns them.
function RestyleQueue.IsBusy(): boolean
	return running or next(pending) ~= nil
end

return RestyleQueue
