require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 17, Id = "Tundra", Name = "Tundra", Subtitle = "Chilly fingers, fast keys",
	Trim = "#78B4FF", Ground = "#DCE8F0", Ground2 = { "#C8D8E6", "#E8F0F8", "#A8B8C4" }, Path = "#9AB4C8",
	Rock = { "#8A9AA8", "#748492", "#9EAEBC" }, Cap = "#FFFFFF", Snow = true,
	Keys = { "#FFFFFF", "#C8E6FF", "#8AB4E6" }, Plate = "#2B2B33",
	Leaves = { "#2E5A46", "#34644E" },
	Props = { Pine = 4, IceSpike = 3, Boulder = 3, Snowman = 1 }, PropCount = 30,
	Sky = { Clock = 10, Fog = "#DCE6F0", FogEnd = 600, Ambient = "#8C96A0", Outdoor = "#969696", Atmosphere = "#E6F0FA", Density = 0.4 },
	-- Red Canyon, the zone before, blends in at the entrance.
	From = { Ground2 = { "#B8683C", "#D4885A" }, Path = "#E0B48A", Rock = { "#B4502E", "#9A4026", "#C8643C" } },
})
