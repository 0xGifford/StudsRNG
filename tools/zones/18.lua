require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 18, Id = "Ashlands", Name = "Ashlands", Subtitle = "Hot ash, hotter rolls",
	Trim = "#FF5A28", Ground = "#3A3434", Ground2 = { "#2E2A2A", "#4A4040" }, Path = "#E04A1E",
	Rock = { "#4A4040", "#3A3232", "#5A4E4E" },
	Keys = { "#4A4040", "#FF5A28", "#FFB43C" }, Plate = "#2B2B33",
	Props = { DeadTree = 3, Spire = 3, Torch = 2, Rubble = 2 }, PropCount = 30,
	Features = { { "Mountain", "#3A3232", "#FF5A28" } },
	Sky = { Clock = 18.5, Fog = "#5A3228", FogEnd = 500, Ambient = "#7A4A3C", Outdoor = "#969696", Atmosphere = "#C85A3C", Density = 0.5 },
	-- Tundra, the zone before, blends in at the entrance.
	From = { Ground2 = { "#C8D8E6", "#E8F0F8", "#A8B8C4" }, Path = "#9AB4C8", Rock = { "#8A9AA8", "#748492", "#9EAEBC" }, Cap = "#FFFFFF" },
})
