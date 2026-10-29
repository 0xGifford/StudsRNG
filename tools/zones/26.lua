require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 26, Id = "Mars", Name = "Mars", Subtitle = "The red keyboard",
	Trim = "#E05A2E", Ground = "#B4502E", Ground2 = { "#A04428", "#C8643C" }, Path = "#D47A50",
	Rock = { "#963C24", "#7E3220", "#AA4A2E" },
	Keys = { "#FFE6DC", "#E05A2E", "#8A3220" }, Plate = "#2B2B33",
	Palette = { "#FFFFFF", "#5AC8FF" }, Clouds = false,
	Props = { Spire = 4, Rubble = 3, Antenna = 2, Boulder = 2 }, PropCount = 30,
	Features = { { "Mountain", "#8A3A24" } },
	Sky = { Clock = 15, Fog = "#D2825A", FogEnd = 900, Ambient = "#9A5A46", Outdoor = "#969696", Atmosphere = "#E6966E", Density = 0.35, Gravity = 90 },
	-- Moon Base, the zone before, blends in at the entrance.
	From = { Ground2 = { "#A0A0AA", "#C8C8D2", "#8C8C96" }, Path = "#DCDCE6", Rock = { "#8C8C96", "#7A7A84", "#A0A0AA" } },
})
