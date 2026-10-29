require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 2, Id = "Arcade", Name = "Beach", Subtitle = "Sun, sand and Clacks",
	Trim = "#FF9650", Ground = "#EED696", Ground2 = { "#E6CC8A", "#F5E0A6", "#DEC484" }, Path = "#CEAA6E",
	Rock = { "#966046", "#84523C", "#A87050" }, WallHeight = 52, Water = "#28AADC",
	Keys = { "#FFF5E1", "#FFC478", "#6ED2E6" }, Plate = "#78543A",
	Palette = { "#FF6B6B", "#FFD23C", "#3CC8FF" },
	Props = { Palm = 6, Boulder = 2, Sign = 1, Barrel = 1, Chest = 1 }, PropCount = 30,
	Sky = { Clock = 15, Fog = "#AADCFF", FogEnd = 1600, Ambient = "#828282", Outdoor = "#969696", Atmosphere = "#C8E1FF", Density = 0.2 },
})
