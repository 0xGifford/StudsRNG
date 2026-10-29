require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 34, Id = "Frostpeak", Name = "Frostpeak", Subtitle = "Above the clouds",
	Trim = "#5AA0FF", Ground = "#E6EEF6", Ground2 = { "#D2DEEA", "#F2F6FA" }, Path = "#A8C4DC",
	Rock = { "#7A8A9A", "#687888", "#8C9CAC" }, Cap = "#FFFFFF", Snow = true,
	Keys = { "#FFFFFF", "#B4D7FF", "#5AA0FF" }, Plate = "#2B2B33",
	Leaves = { "#2E5A46", "#34644E" },
	Props = { Pine = 4, IceSpike = 4, Boulder = 2, Snowman = 1 }, PropCount = 30,
	Features = { { "Mountain", "#8C9CAC", "#FFFFFF" } },
	Sky = { Clock = 12, Fog = "#F0F5FA", FogEnd = 650, Ambient = "#A0AAB4", Outdoor = "#969696", Atmosphere = "#F0F8FF", Density = 0.4 },
	-- Bamboo Forest, the zone before, blends in at the entrance.
	From = { Ground2 = { "#5A8A3E", "#7AAA56" }, Path = "#C8B48A", Rock = { "#8A8A7A", "#7A7A6A", "#9A9A8A" }, Cap = "#6A9A4A" },
})
