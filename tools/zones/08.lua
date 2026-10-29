require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 8, Id = "Desert", Name = "Desert", Subtitle = "Hot keys only",
	Trim = "#FFAA3C", Ground = "#E8C27A", Ground2 = { "#DDB468", "#F0CE8C" }, Path = "#C9955A",
	Rock = { "#C47A4A", "#A9653C", "#D48C58" },
	Keys = { "#FFF4DD", "#FFC27A", "#E07A3C" }, Plate = "#2B2B33",
	Props = { Cactus = 5, Boulder = 2, Bones = 2, Spire = 1 }, PropCount = 30,
	Features = { { "Pyramid", "#E0B46E" } },
	Sky = { Clock = 14, Fog = "#F3D9A6", FogEnd = 1300, Ambient = "#8C7A64", Outdoor = "#969696", Atmosphere = "#FFE2B0", Density = 0.25 },
	-- Heaven, the zone before, blends in at the entrance.
	From = { Ground2 = { "#FFF6DC", "#F0F4FF", "#FFFCF0" }, Path = "#FFDE78", Rock = { "#FFFFFF", "#F4F6FF", "#FFFAF0" } },
})
