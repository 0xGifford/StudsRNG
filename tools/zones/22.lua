require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 22, Id = "Geode", Name = "Geode Grotto", Subtitle = "Crystal clear Clacks",
	Trim = "#5AE6FF", Ground = "#4A4258", Ground2 = { "#3E3850", "#5A5068" }, Path = "#6E6480",
	Rock = { "#5A5068", "#4A4258", "#6E6480" }, Roof = true,
	Keys = { "#FFFFFF", "#5AE6FF", "#FF78DC" }, Plate = "#2B2B33",
	Palette = { "#5AE6FF", "#FF78DC", "#78FFB4", "#FFE65A" },
	Props = { Crystal = 7, Rubble = 2, Orb = 1 }, PropCount = 30,
	Sky = { Clock = 0, Fog = "#1E2846", FogEnd = 400, Ambient = "#5A6E96", Outdoor = "#3C4A6E", Atmosphere = "#3C5AA0", Density = 0.45 },
	-- Haunted Hollow, the zone before, blends in at the entrance.
	From = { Ground2 = { "#2E2E38", "#46464E" }, Path = "#5A5060", Rock = { "#4A4650", "#3A3640", "#5A5660" } },
})
