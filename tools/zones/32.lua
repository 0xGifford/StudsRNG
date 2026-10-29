require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 32, Id = "Savanna", Name = "Savanna", Subtitle = "King of the keys",
	Trim = "#E6B43C", Ground = "#C8B45A", Ground2 = { "#B4A04A", "#D4C46A" }, Path = "#B48A50",
	Rock = { "#A8885A", "#94744A", "#BC9C6A" },
	Keys = { "#FFF5D2", "#E6B43C", "#A8783C" }, Plate = "#2B2B33",
	Leaves = { "#7A9A3A", "#8AAA44" },
	Props = { Tree = 4, Boulder = 3, Bush = 2, Bones = 1 }, PropCount = 30,
	Features = { { "Sun", "#FFB43C" } },
	Sky = { Clock = 17.5, Fog = "#F0C88C", FogEnd = 1500, Ambient = "#968264", Outdoor = "#969696", Atmosphere = "#FFD296", Density = 0.25 },
	-- Oasis, the zone before, blends in at the entrance.
	From = { Ground2 = { "#DCBE78", "#F0D69A" }, Path = "#C8A46E", Rock = { "#D4A064", "#C08C52", "#E0B478" }, Water = true },
})
