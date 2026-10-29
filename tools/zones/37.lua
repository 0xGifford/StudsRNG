require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 37, Id = "Bakery", Name = "Sweet Bakery", Subtitle = "Freshly baked Clacks",
	Trim = "#FFB4C8", Ground = "#F5DCB4", Ground2 = { "#EBCDA0", "#FFE6C8", "#FFC8D7" }, Path = "#C8966E",
	Rock = { "#C8966E", "#B4825A", "#DCAA82" }, Cap = "#FFF5FA", WallHeight = 34,
	Keys = { "#FFFFFF", "#FFB4C8", "#8A5A3A" }, Plate = "#8A5A3A",
	Palette = { "#FFB4C8", "#8A5A3A", "#FFFFFF", "#B4E6FF" },
	Props = { Gift = 3, Lollipop = 2, CandyCane = 2, Mushroom = 2 }, PropCount = 30,
	Sky = { Clock = 14, Fog = "#FFEBDC", FogEnd = 1300, Ambient = "#A0968C", Outdoor = "#969696", Atmosphere = "#FFEBDC", Density = 0.25 },
})
