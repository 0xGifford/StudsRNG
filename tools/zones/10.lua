require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 10, Id = "Candy", Name = "Candyland", Subtitle = "Sweet, sweet Clacks",
	Trim = "#FF78C8", Ground = "#FFC8E6", Ground2 = { "#FFB4DC", "#FFDCF0", "#C8F0FF" }, Path = "#FFFFFF",
	Rock = { "#FF96C8", "#C8A0FF", "#96DCFF" }, Cap = "#FFFFFF",
	Keys = { "#FFFFFF", "#FFB4DC", "#B4F0FF" }, Plate = "#FF8CC8",
	Palette = { "#FF5AA0", "#5AC8FF", "#FFD23C", "#8CE65A", "#B478FF" },
	Props = { Lollipop = 4, CandyCane = 3, Gift = 2, Mushroom = 1 }, PropCount = 30,
	Features = { { "Rainbow" } },
	Sky = { Clock = 14, Fog = "#FFE1F5", FogEnd = 1300, Ambient = "#A08CA0", Outdoor = "#969696", Atmosphere = "#FFDCF0", Density = 0.25 },
	-- Jungle, the zone before, blends in at the entrance.
	From = { Ground2 = { "#438A32", "#5AAA44" }, Path = "#7A5A3A", Rock = { "#5A6A4A", "#4A5A3E", "#6A7A56" }, Cap = "#3E8A30" },
})
