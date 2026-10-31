--!strict
-- Single responsibility: remove the keys under a set of boxes.
--
-- Deliberately grid-free: the eraser does NOT snap. It deletes any key whose
-- box it touches, so a key placed against another surface (a different plate,
-- another floor) can still be wiped without lining the cursor up with its
-- grid first. That is the opposite trade-off from placement, and on purpose.
--
-- Scope guards the common accident: cleaning up one row of a keyboard must
-- not be able to eat the rest of it.

local Constants = require(script.Parent.Parent.Constants)
local OverlapGuard = require(script.Parent.OverlapGuard)

local Eraser = {}

Eraser.SCOPES = { "Group", "All" }

-- Returns the set of group names that lost at least one key: the caller
-- restyles those, because a gradient is derived from the members that remain.
function Eraser.Erase(cframes: { CFrame }, size: Vector3, scope: string, group: string): ({ [string]: true }, number)
	local touchedGroups: { [string]: true } = {}
	local removed = 0

	for _, cframe in ipairs(cframes) do
		for _, key in ipairs(OverlapGuard.FindOverlapping(cframe, size)) do
			local keyGroup = key:GetAttribute(Constants.ATTR_GROUP)
			if scope == "All" or keyGroup == group then
				if typeof(keyGroup) == "string" then
					touchedGroups[keyGroup] = true
				end
				key:Destroy()
				removed += 1
			end
		end
	end

	return touchedGroups, removed
end

return Eraser
