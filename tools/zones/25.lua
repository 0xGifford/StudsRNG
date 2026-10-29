require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 25, Id = "Moon", Name = "Moon Base", Subtitle = "One small press",
	Trim = "#C8C8D2", Ground = "#B4B4BE", Ground2 = { "#A0A0AA", "#C8C8D2", "#8C8C96" }, Path = "#DCDCE6",
	Rock = { "#8C8C96", "#7A7A84", "#A0A0AA" }, WallHeight = 30,
	Keys = { "#FFFFFF", "#C8C8D2", "#5AC8FF" }, Plate = "#2B2B33",
	Palette = { "#5AC8FF", "#FFFFFF", "#FF5A5A" }, Clouds = false,
	Props = { Rubble = 3, Antenna = 2, Orb = 2, Boulder = 3 }, PropCount = 30,
	Features = { { "Planet", "#3C8CFF" } },
	Sky = { Clock = 0, Fog = "#14141E", FogEnd = 1500, Ambient = "#8C8C96", Outdoor = "#6E6E78", Atmosphere = "#28283C", Density = 0.1, Gravity = 60 },
})
