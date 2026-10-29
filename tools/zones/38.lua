require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 38, Id = "Toxic", Name = "Toxic Wastes", Subtitle = "Glowing results",
	Trim = "#8CFF3C", Ground = "#4A5A3A", Ground2 = { "#3E4A30", "#5A6A44", "#6E8A2E" }, Path = "#8CFF3C",
	Rock = { "#5A5A50", "#4A4A42", "#6A6A5E" },
	Keys = { "#2E3228", "#8CFF3C", "#FFE63C" }, Plate = "#2B2B33",
	Palette = { "#8CFF3C", "#FFE63C", "#5A5A50" },
	Props = { Barrel = 4, Pipe = 3, Rubble = 2, DeadTree = 2 }, PropCount = 30,
	Sky = { Clock = 16, Fog = "#8CA05A", FogEnd = 500, Ambient = "#6E7A50", Outdoor = "#969696", Atmosphere = "#AACC6E", Density = 0.5 },
	-- Sweet Bakery, the zone before, blends in at the entrance.
	From = { Ground2 = { "#EBCDA0", "#FFE6C8", "#FFC8D7" }, Path = "#C8966E", Rock = { "#C8966E", "#B4825A", "#DCAA82" }, Cap = "#FFF5FA" },
})
