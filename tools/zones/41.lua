require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 41, Id = "SkyIsles", Name = "Floating Isles", Subtitle = "Don't look down",
	Trim = "#5AC8FF", Ground = "#7EC468", Ground2 = { "#6EB45A", "#8ED478" }, Path = "#E6D2B4",
	Rock = { "#8A7A6A", "#7A6A5A", "#9A8A7A" }, Cap = "#6EB45A",
	Keys = { "#FFFFFF", "#5AC8FF", "#8EE07A" }, Plate = "#2B2B33",
	Palette = { "#FF6B8A", "#FFD23C" },
	Props = { Tree = 3, Cloud = 4, Flowers = 2, Bush = 2 }, PropCount = 30,
	Features = { { "Sun", "#FFE678" } },
	Sky = { Clock = 12, Fog = "#C8E6FF", FogEnd = 1800, Ambient = "#9AA0AA", Outdoor = "#969696", Atmosphere = "#DCF0FF", Density = 0.15, Gravity = 120 },
	-- Ancient Ruins, the zone before, blends in at the entrance.
	From = { Ground2 = { "#8A9060", "#AAB080", "#B4AA8C" }, Path = "#C8BC96", Rock = { "#A09A8A", "#8A8474", "#B4AE9E" }, Cap = "#7A9A4A" },
})
