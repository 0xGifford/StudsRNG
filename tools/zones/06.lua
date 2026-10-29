require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 6, Id = "Cave", Name = "Cave", Subtitle = "Something glitters in the dark",
	Trim = "#B068FF", Ground = "#3E3A48", Ground2 = { "#34303E", "#4A4456", "#3A344A" }, Path = "#544C60",
	Rock = { "#464052", "#3A3646", "#544C60" }, Roof = true,
	Keys = { "#C8A0FF", "#5AE6FF", "#FF78DC" }, Plate = "#1E1A28",
	Palette = { "#B068FF", "#5AE6FF", "#FF78DC" },
	Props = { Crystal = 5, Mushroom = 4, Spire = 2, Rubble = 1 }, PropCount = 30,
	Sky = { Clock = 0, Fog = "#1E1432", FogEnd = 420, Ambient = "#6E5096", Outdoor = "#46326E", Atmosphere = "#5A3CA0", Density = 0.45 },
	-- Islands, the zone before, blends in at the entrance.
	From = { Ground2 = { "#F0DCA0", "#6CBC50", "#86D462" }, Path = "#F0DEA5", Rock = { "#6E965A", "#5A8650", "#80A064" }, Cap = "#6EC450", Water = true },
})
