--!strict
-- Single responsibility: name <-> Font lookup for the label's typeface.
-- A curated, short list on purpose: the group panel exposes it as a cycling
-- button, not a free picker, so every name here must be a Font Studio can
-- always resolve (no dependency on an uploaded asset being available).
--
-- Lives inside RuntimeSource (not Core/Edit) because GuiFactory, which is
-- cloned into the shipped game, is conceptually the same layer.

local FontPresets = {}

local PRESETS: { { Name: string, Font: Font } } = {
	{ Name = "Fredoka", Font = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal) },
	{ Name = "Gotham", Font = Font.fromEnum(Enum.Font.GothamBlack) },
	{ Name = "Bangers", Font = Font.fromEnum(Enum.Font.Bangers) },
	{ Name = "Arial", Font = Font.fromEnum(Enum.Font.Arial) },
	{ Name = "Code", Font = Font.fromEnum(Enum.Font.Code) },
}

FontPresets.DEFAULT_NAME = PRESETS[1].Name

function FontPresets.List(): { string }
	local names = {}
	for _, preset in ipairs(PRESETS) do
		table.insert(names, preset.Name)
	end
	return names
end

-- Falls back to the default rather than erroring: a stale/unknown name
-- attribute (renamed preset, hand-edited data) must not break a key's GUI.
function FontPresets.Resolve(name: string?): Font
	for _, preset in ipairs(PRESETS) do
		if preset.Name == name then
			return preset.Font
		end
	end
	return PRESETS[1].Font
end

return FontPresets
