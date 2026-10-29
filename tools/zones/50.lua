require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 50, Id = "Kingdom", Name = "Keyboard Kingdom", Subtitle = "The final Clack", Last = true,
	Trim = "#FF4E6A", Ground = "#7EC468", Ground2 = { "#6EB45A", "#8ED478" }, Path = "#E6D2B4",
	Rock = { "#A0A0AA", "#8C8C96", "#B4B4BE" }, Cap = "#6EB45A", WallHeight = 60,
	Keys = { "#FFFFFF", "#FFD23C", "#FF4E6A", "#3C8CFF" }, Plate = "#2B2B33",
	Palette = { "#FF4E6A", "#3C8CFF", "#FFD23C", "#FFFFFF" }, Stone = "#C8C8D2",
	Props = { Tower = 3, Lamp = 2, Chest = 2, Coins = 2, Arch = 1 }, PropCount = 30,
	Features = { { "Towers", "#A0A0AA" }, { "Rainbow" } },
	Sky = { Clock = 14, Fog = "#D2E6FF", FogEnd = 1500, Ambient = "#828282", Outdoor = "#969696", Atmosphere = "#C8E1FF", Density = 0.2 },
})
