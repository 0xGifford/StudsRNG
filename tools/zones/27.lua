require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 27, Id = "Galaxy", Name = "Galaxy", Subtitle = "Out of this world",
	Trim = "#B478FF", Ground = "#2E2A4A", Ground2 = { "#24203E", "#3A3458" }, Path = "#B478FF",
	Rock = { "#3A3458", "#2E2A4A", "#4A4268" }, WallHeight = 36,
	Keys = { "#FFFFFF", "#B478FF", "#5AC8FF" }, Plate = "#2B2B33",
	Palette = { "#B478FF", "#5AC8FF", "#FF78DC", "#FFE65A" }, Clouds = false,
	Props = { Orb = 5, Crystal = 3, Spire = 2 }, PropCount = 30,
	Features = { { "Planet", "#FF8A5A" } },
	Sky = { Clock = 0, Fog = "#140E28", FogEnd = 1200, Ambient = "#6E5A9A", Outdoor = "#4A3C78", Atmosphere = "#3C2878", Density = 0.2, Gravity = 55 },
})
