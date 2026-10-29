require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 39, Id = "Factory", Name = "Factory", Subtitle = "Mass-produced Clacks",
	Trim = "#FFC83C", Ground = "#6E7078", Ground2 = { "#5E6068", "#7E8088" }, Path = "#FFC83C",
	Rock = { "#7A7C84", "#686A72", "#8C8E96" },
	Keys = { "#E6E6EB", "#FFC83C", "#3C3E46" }, Plate = "#2B2B33",
	Palette = { "#FFC83C", "#E8413C", "#8C8E96" },
	Props = { Gear = 3, Pipe = 4, Barrel = 2, Tower = 1 }, PropCount = 30,
	Features = { { "Towers", "#5E6068" } },
	Sky = { Clock = 15, Fog = "#A0A0A8", FogEnd = 800, Ambient = "#7A7A82", Outdoor = "#969696", Atmosphere = "#C8C8D2", Density = 0.35 },
	-- Toxic Wastes, the zone before, blends in at the entrance.
	From = { Ground2 = { "#3E4A30", "#5A6A44", "#6E8A2E" }, Path = "#8CFF3C", Rock = { "#5A5A50", "#4A4A42", "#6A6A5E" } },
})
