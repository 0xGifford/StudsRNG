require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 35, Id = "Rainbow", Name = "Rainbow Road", Subtitle = "Every colour of Clack",
	Trim = "#FF5AA0", Ground = "#FFFFFF", Ground2 = { "#E8413C", "#F28C28", "#F5D428", "#4CB84A", "#3C8FE0", "#7A4CC8" }, Path = "#FFFFFF",
	Rock = { "#E8413C", "#F28C28", "#F5D428", "#4CB84A", "#3C8FE0", "#7A4CC8" }, WallHeight = 30,
	Keys = { "#E8413C", "#F28C28", "#F5D428", "#4CB84A", "#3C8FE0", "#7A4CC8" }, Plate = "#2B2B33",
	Palette = { "#E8413C", "#F28C28", "#F5D428", "#4CB84A", "#3C8FE0", "#7A4CC8" },
	Props = { Cloud = 4, Orb = 2, Gift = 2, Lollipop = 2 }, PropCount = 30,
	Features = { { "Rainbow" } },
	Sky = { Clock = 13, Fog = "#F0F0FF", FogEnd = 1500, Ambient = "#828282", Outdoor = "#969696", Atmosphere = "#C8E1FF", Density = 0.2 },
})
