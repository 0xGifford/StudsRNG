--!strict
-- Single responsibility: decide what text a key being placed carries.
-- Either a fixed character typed by the user, or a random one drawn from a
-- named character set.
--
-- math.random is fine here (unlike colours): the label is drawn ONCE at
-- placement and baked into the key's attribute, never recomputed, so it
-- cannot flicker on a later restyle.

local LabelSource = {}

local CHARSETS = {
	{ Name = "A-Z", Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" },
	{ Name = "0-9", Chars = "0123456789" },
	{ Name = "A-Z 0-9", Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" },
}

LabelSource.MODES = { "Fixed", "Random" }
LabelSource.DEFAULT_CHARSET = CHARSETS[3].Name -- "A-Z 0-9": default charset covers letters+numbers

function LabelSource.CharsetNames(): { string }
	local names: { string } = {}
	for _, set in ipairs(CHARSETS) do
		table.insert(names, set.Name)
	end
	return names
end

local function charsOf(name: string): string
	for _, set in ipairs(CHARSETS) do
		if set.Name == name then return set.Chars end
	end
	return CHARSETS[1].Chars
end

function LabelSource.Pick(mode: string, fixed: string, charsetName: string): string
	if mode ~= "Random" then
		return fixed
	end
	local chars = charsOf(charsetName)
	local index = math.random(1, #chars)
	return chars:sub(index, index)
end

return LabelSource
