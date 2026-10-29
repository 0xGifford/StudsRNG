require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 12, Id = "Shroom", Name = "Shroomlands", Subtitle = "Fungi with benefits",
	Trim = "#FF5A5A", Ground = "#6A8A4A", Ground2 = { "#5A7A3E", "#7A9A56" }, Path = "#B4966E",
	Rock = { "#6E6A5E", "#5E5A50", "#827C6E" }, Cap = "#5A7A3E", WallHeight = 44,
	Keys = { "#FFF5F0", "#FF8A8A", "#FFD27A" }, Plate = "#2B2B33",
	Palette = { "#FF4E4E", "#FF8A28", "#B478FF", "#4EB4FF" },
	Props = { Mushroom = 7, Bush = 2, Flowers = 1 }, PropCount = 30,
	Sky = { Clock = 15, Fog = "#C8D2A0", FogEnd = 900, Ambient = "#7A8264", Outdoor = "#969696", Atmosphere = "#DCE6B4", Density = 0.3 },
})
