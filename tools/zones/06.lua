require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 6, Id = "Cave", Name = "Cave", Subtitle = "Something glitters in the dark",
	Trim = "#B068FF", Ground = "#3E3A48", Ground2 = { "#34303E", "#4A4456", "#3A344A" }, Path = "#544C60",
	Rock = { "#464052", "#3A3646", "#544C60" }, WallHeight = 52, Roof = true,
	Keys = { "#C8A0FF", "#5AE6FF", "#FF78DC" }, Plate = "#1E1A28",
	Palette = { "#B068FF", "#5AE6FF", "#FF78DC" },
	Props = { Crystal = 5, Mushroom = 4, Rubble = 2 }, PropCount = 30,
	Sky = { Clock = 0, Fog = "#1E1432", FogEnd = 420, Ambient = "#6E5096", Outdoor = "#46326E", Atmosphere = "#5A3CA0", Density = 0.45 },
})
