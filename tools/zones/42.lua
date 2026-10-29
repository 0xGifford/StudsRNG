require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 42, Id = "CrystalGarden", Name = "Crystal Garden", Subtitle = "Gems in bloom",
	Trim = "#78FFDC", Ground = "#5AA08A", Ground2 = { "#4A9078", "#6AB09A" }, Path = "#C8F0E6",
	Rock = { "#6E8A84", "#5A7670", "#82A098" }, Cap = "#5AA08A",
	Keys = { "#FFFFFF", "#78FFDC", "#B478FF" }, Plate = "#2B2B33",
	Palette = { "#78FFDC", "#B478FF", "#FF78DC", "#5AC8FF" },
	Props = { Crystal = 5, Flowers = 3, Orb = 2 }, PropCount = 30,
	Sky = { Clock = 18, Fog = "#B4E6DC", FogEnd = 900, Ambient = "#6E968C", Outdoor = "#969696", Atmosphere = "#C8F0E6", Density = 0.3 },
	-- Floating Isles, the zone before, blends in at the entrance.
	From = { Ground2 = { "#6EB45A", "#8ED478" }, Path = "#E6D2B4", Rock = { "#8A7A6A", "#7A6A5A", "#9A8A7A" }, Cap = "#6EB45A" },
})
