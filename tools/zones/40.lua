require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 40, Id = "Ruins", Name = "Ancient Ruins", Subtitle = "Old keys, new rolls",
	Trim = "#C8B478", Ground = "#9AA070", Ground2 = { "#8A9060", "#AAB080", "#B4AA8C" }, Path = "#C8BC96",
	Rock = { "#A09A8A", "#8A8474", "#B4AE9E" }, Cap = "#7A9A4A",
	Keys = { "#F5F0E1", "#C8B478", "#7A8A5A" }, Plate = "#2B2B33",
	Stone = "#D2CCB8",
	Props = { Pillar = 3, Arch = 2, Rubble = 3, Bush = 2 }, PropCount = 30,
	Sky = { Clock = 16, Fog = "#DCD2B4", FogEnd = 1100, Ambient = "#8A8470", Outdoor = "#969696", Atmosphere = "#E6DCBE", Density = 0.3 },
	-- Factory, the zone before, blends in at the entrance.
	From = { Ground2 = { "#5E6068", "#7E8088" }, Path = "#FFC83C", Rock = { "#7A7C84", "#686A72", "#8C8E96" } },
})
