--!strict
-- Single responsibility: turn whatever a user pasted into a sound asset id —
-- or say why it cannot be one. No storage, no UI, no Sound instances.
--
-- Lives in RuntimeSource because BOTH sides need the exact same verdict:
-- GroupConfig parses stored ids at runtime, and the panel's SoundSection
-- validates them as they are typed. Two implementations of "is this an id?"
-- would eventually disagree, and the failure mode of that disagreement is a
-- field the panel accepts and the game silently ignores — which is the very
-- thing this module exists to prevent.

local SoundId = {}

-- The forms people actually arrive with: the bare number from the toolbox,
-- the canonical asset url, and the two roblox.com links you get from the
-- website's address bar or a Share button.
local FORMS = {
	"^(%d+)$",
	"^rbxassetid://(%d+)$",
	"^https?://[%w%.]*roblox%.com/asset/%?id=(%d+)",
	"^https?://[%w%.]*roblox%.com/library/(%d+)",
}

function SoundId.Trim(raw: string): string
	return (tostring(raw):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Returns the canonical "rbxassetid://N" form, or nil plus a message written
-- for the person who typed it. An empty string is neither: it is a row not
-- filled in yet, so it returns nil with no complaint.
function SoundId.Parse(raw: string): (string?, string?)
	local text = SoundId.Trim(raw)
	if text == "" then return nil, nil end

	for _, form in ipairs(FORMS) do
		local id = text:match(form)
		if id then return "rbxassetid://" .. id, nil end
	end

	-- Everything below is a rejection. The message names what is actually
	-- wrong rather than restating the rule, because the overwhelmingly common
	-- case here is a mistyped scheme ("rbxassetid" is a mouthful) where the
	-- number itself is perfectly fine and the user cannot see the difference.
	local scheme = text:match("^(%a[%w%+%-%.]*)://")
	if scheme and scheme:lower() ~= "rbxassetid" then
		return nil, string.format("“%s://” is not valid — did you mean rbxassetid:// ?", scheme)
	end
	if text:match("%d") then
		return nil, "Not recognised — use the number alone, or rbxassetid://number"
	end
	return nil, "No asset id here — it must contain the sound's number"
end

return SoundId
