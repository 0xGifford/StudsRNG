require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 30, Id = "WildWest", Name = "Wild West", Subtitle = "Fastest keys in the west",
	Trim = "#C8783C", Ground = "#D4A86E", Ground2 = { "#C89A5E", "#E0B47E" }, Path = "#A87A4A",
	Rock = { "#B47A4A", "#9A643C", "#C88A58" }, WallHeight = 48,
	Keys = { "#FFF0DC", "#C8783C", "#8A4A28" }, Plate = "#2B2B33",
	Palette = { "#C8783C", "#FFE6B4" },
	Props = { Cactus = 4, Barrel = 2, Fence = 2, Sign = 2, Bones = 1 }, PropCount = 30,
	Sky = { Clock = 17, Fog = "#F0C896", FogEnd = 1200, Ambient = "#967A5E", Outdoor = "#969696", Atmosphere = "#FFD2A0", Density = 0.3 },
})
