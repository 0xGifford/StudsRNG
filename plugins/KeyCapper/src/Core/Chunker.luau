--!strict
-- Single responsibility: run a per-item job over a list without holding the
-- frame. Spends a fixed slice of each frame on the work and yields the rest.
--
-- Every heavy pass in the plugin is O(keys) — restyling a group, recolouring
-- after a stroke — and a board is expected to reach thousands of keys. Done
-- as one synchronous loop that is a visible Studio freeze; done a slice at a
-- time it is a progress bar nobody has to look at.
--
-- Note that this is adaptive by construction: a list that fits inside the
-- budget never yields at all. A ten-key stroke stays exactly as synchronous
-- (and as undo-correct) as it was before — only a pass big enough to actually
-- freeze ever pays the cost of spreading itself out.

local RunService = game:GetService("RunService")

local Chunker = {}

-- Measured on a 9k-key board, because both obvious instincts here are wrong:
--
--   * the dominant cost is the engine's own property writes (~80ms of genuine
--     cap.Color sets), and guarding them with a read-and-compare is measurably
--     SLOWER than just writing — the engine already skips no-op sets;
--   * shrinking the budget does NOT buy smoothness. Every yield costs a whole
--     frame, so halving it to 2ms doubled the wall time of a full pass
--     (410ms -> 1000ms) while the worst frame hold did not move at all: on a
--     board that size the frame was already ~18ms before we did anything.
--
-- So the budget buys nothing below roughly half a frame, and costs a lot. 8ms
-- keeps the pass clearly interactive while spending as few whole frames as it
-- can on getting there.
Chunker.BUDGET = 0.008

-- Runs `perItem` over every item. `shouldAbort` is polled at each yield:
-- returning true stops the run and makes Each return false, which is how a
-- superseded pass is dropped instead of finishing work nobody will look at.
function Chunker.Each<T>(
	items: { T },
	perItem: (T, number) -> (),
	shouldAbort: (() -> boolean)?
): boolean
	local deadline = os.clock() + Chunker.BUDGET
	for index, item in ipairs(items) do
		perItem(item, index)
		if os.clock() >= deadline then
			RunService.Heartbeat:Wait()
			if shouldAbort and shouldAbort() then return false end
			deadline = os.clock() + Chunker.BUDGET
		end
	end
	return true
end

return Chunker
