require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 23, Id = "Clockwork", Name = "Clockwork", Subtitle = "Tick tock, click clack",
	Trim = "#D4A048", Ground = "#7A6A5A", Ground2 = { "#6A5A4A", "#8A7A6A" }, Path = "#B48A50",
	Rock = { "#8A7058", "#6E5A46", "#A08060" },
	Keys = { "#F0E2C8", "#D4A048", "#8A5A3A" }, Plate = "#3E3228",
	Palette = { "#D4A048", "#B87333", "#8C8C94" },
	Props = { Gear = 5, Pipe = 3, Barrel = 2, Lamp = 1 }, PropCount = 30,
	Sky = { Clock = 17, Fog = "#C8A87A", FogEnd = 900, Ambient = "#8A7A64", Outdoor = "#969696", Atmosphere = "#E6C896", Density = 0.35 },
	-- Geode Grotto, the zone before, blends in at the entrance.
	From = { Ground2 = { "#3E3850", "#5A5068" }, Path = "#6E6480", Rock = { "#5A5068", "#4A4258", "#6E6480" } },
})
