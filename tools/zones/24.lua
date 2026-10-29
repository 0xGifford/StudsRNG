require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 24, Id = "CyberCity", Name = "Cyber City", Subtitle = "Plugged in",
	Trim = "#3CF0FF", Ground = "#2A2E3A", Ground2 = { "#22262E", "#363A46" }, Path = "#3CF0FF",
	Rock = { "#3A3E4A", "#2E323C", "#464A56" }, WallHeight = 60,
	Keys = { "#2A2E3A", "#3CF0FF", "#FF3CC8" }, Plate = "#2B2B33",
	Palette = { "#3CF0FF", "#FF3CC8", "#B478FF", "#46505E" }, Clouds = false,
	Props = { Tower = 5, Antenna = 2, Lamp = 3, Pipe = 1 }, PropCount = 30,
	Features = { { "Towers", "#2E3240" } },
	Sky = { Clock = 21, Fog = "#1E1E3C", FogEnd = 700, Ambient = "#5A5A8C", Outdoor = "#3C3C6E", Atmosphere = "#3C3C8C", Density = 0.35 },
})
