--!strict
-- Single responsibility: stop the SAME sound asset from starting twice within
-- a few milliseconds. Nothing else — it owns no Sound and plays nothing, it
-- only answers yes or no.
--
-- Two copies of one sample a few ms apart do not sound like two taps, they
-- sound like one wrong tap: the offset copies comb-filter against each other
-- and the result is a hollow, flanged version of the sound. Two keys landing
-- together is completely normal (a chord, a foot covering two caps, one press
-- detected on overlapping hitboxes), so this happens constantly.
--
-- Config.SOUND_MIN_INTERVAL has to stay well under one detection tick: see
-- that constant for why a value near the tick period silences ordinary fast
-- typing across different keys instead of only same-tick overlaps.
--
-- Gated per ASSET, not per key: two different sounds at the same instant is a
-- chord and must stay one, and a single key retriggering fast is the same
-- asset so it is covered by the same rule.

local Config = require(script.Parent.Parent.Config)

local SoundGate = {}

-- Last start time per asset id. Bounded by the number of distinct sounds in
-- the place, which is the number of ids across all groups — small, and it
-- never grows with the number of keys or presses.
local lastPlay: { [string]: number } = {}

-- True if this asset may start now, and records it as started. Callers that
-- get false must skip the :Play() but everything else (the animation) still
-- runs — the key was pressed, only its sound is being merged into the one
-- already sounding.
function SoundGate.Allow(soundId: string): boolean
	local now = os.clock()
	local previous = lastPlay[soundId]
	if previous and now - previous < Config.SOUND_MIN_INTERVAL then
		return false
	end
	lastPlay[soundId] = now
	return true
end

return SoundGate
