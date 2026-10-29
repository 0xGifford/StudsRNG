require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 46, Id = "Thunder", Name = "Thunder Peaks", Subtitle = "Charged up",
	Trim = "#FFE63C", Ground = "#5A5E6E", Ground2 = { "#4E5262", "#6A6E7E" }, Path = "#FFE63C",
	Rock = { "#5A5E6E", "#4A4E5E", "#6E7282" }, WallHeight = 66,
	Keys = { "#E6E6EB", "#FFE63C", "#5A78FF" }, Plate = "#2B2B33",
	Palette = { "#FFE63C", "#5A78FF" }, CloudColor = "#5A5E6E",
	Props = { Spire = 4, Rubble = 2, Antenna = 2, DeadTree = 2 }, PropCount = 30,
	Features = { { "Mountain", "#4A4E5E", "#FFE63C" } },
	Sky = { Clock = 17, Fog = "#5A6070", FogEnd = 550, Ambient = "#6E7282", Outdoor = "#969696", Atmosphere = "#7A8296", Density = 0.45 },
})
