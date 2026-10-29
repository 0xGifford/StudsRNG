require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 43, Id = "NeonNights", Name = "Neon Nights", Subtitle = "The city never sleeps",
	Trim = "#FF3CC8", Ground = "#2A2438", Ground2 = { "#221C30", "#342C44" }, Path = "#FF3CC8",
	Rock = { "#3A3248", "#2E2838", "#463C56" }, WallHeight = 58,
	Keys = { "#2A2438", "#FF3CC8", "#3CF0FF" }, Plate = "#2B2B33",
	Palette = { "#FF3CC8", "#3CF0FF", "#FFE63C", "#8CFF3C" }, Clouds = false,
	Props = { Lamp = 4, Tower = 3, Sign = 2, Antenna = 1 }, PropCount = 30,
	Features = { { "Towers", "#2E2838" } },
	Sky = { Clock = 22, Fog = "#2A1E46", FogEnd = 650, Ambient = "#6E5096", Outdoor = "#46326E", Atmosphere = "#5A2896", Density = 0.35 },
})
