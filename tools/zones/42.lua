require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 42, Id = "CrystalGarden", Name = "Crystal Garden", Subtitle = "Gems in bloom",
	Trim = "#78FFDC", Ground = "#5AA08A", Ground2 = { "#4A9078", "#6AB09A" }, Path = "#C8F0E6",
	Rock = { "#6E8A84", "#5A7670", "#82A098" }, Cap = "#5AA08A", WallHeight = 42,
	Keys = { "#FFFFFF", "#78FFDC", "#B478FF" }, Plate = "#2B2B33",
	Palette = { "#78FFDC", "#B478FF", "#FF78DC", "#5AC8FF" },
	Props = { Crystal = 5, Flowers = 3, Orb = 2 }, PropCount = 30,
	Sky = { Clock = 18, Fog = "#B4E6DC", FogEnd = 900, Ambient = "#6E968C", Outdoor = "#969696", Atmosphere = "#C8F0E6", Density = 0.3 },
})
