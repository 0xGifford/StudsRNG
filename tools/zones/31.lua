require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 31, Id = "Oasis", Name = "Oasis", Subtitle = "Water in the dunes",
	Trim = "#3CC8B4", Ground = "#E8CC8A", Ground2 = { "#DCBE78", "#F0D69A" }, Path = "#C8A46E",
	Rock = { "#D4A064", "#C08C52", "#E0B478" }, WallHeight = 34, Water = "#3CB4D2",
	Keys = { "#FFFFFF", "#3CC8B4", "#FFC864" }, Plate = "#2B2B33",
	Stone = "#E6C88C",
	Props = { Palm = 5, Cactus = 2, Pillar = 2, Chest = 1 }, PropCount = 30,
	Features = { { "Pyramid", "#E6BE78" } },
	Sky = { Clock = 13, Fog = "#F5E1B4", FogEnd = 1500, Ambient = "#828282", Outdoor = "#969696", Atmosphere = "#C8E1FF", Density = 0.2 },
})
