require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 48, Id = "GoldenCity", Name = "Golden City", Subtitle = "Streets paved with Clacks",
	Trim = "#FFD23C", Ground = "#F0DCA0", Ground2 = { "#E6CC8A", "#FFE6B4" }, Path = "#FFD23C",
	Rock = { "#E6C878", "#D2B464", "#F0D28C" }, Cap = "#FFFFFF", WallHeight = 50,
	Keys = { "#FFFFFF", "#FFD23C", "#C8963C" }, Plate = "#2B2B33",
	Palette = { "#FFD23C", "#FFFFFF", "#C8963C" }, Stone = "#FFF5DC",
	Props = { Pillar = 3, Coins = 3, Chest = 2, Tower = 2 }, PropCount = 30,
	Features = { { "Towers", "#E6C878" } },
	Sky = { Clock = 16, Fog = "#FFF0C8", FogEnd = 1300, Ambient = "#A0967A", Outdoor = "#969696", Atmosphere = "#FFEBBE", Density = 0.25 },
})
