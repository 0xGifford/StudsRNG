require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 13, Id = "Reef", Name = "Coral Reef", Subtitle = "Clacks under the sea",
	Trim = "#FF6EAA", Ground = "#E8D8A8", Ground2 = { "#DCC890", "#F0E2B8" }, Path = "#C8B488",
	Rock = { "#4A8AA8", "#3A7896", "#5A9AB8" }, WallHeight = 40, Water = "#1E8CC8",
	Keys = { "#FFFFFF", "#FF96C8", "#6EE6FF" }, Plate = "#2B2B33",
	Palette = { "#FF6EAA", "#FF8A3C", "#B478FF", "#FFD23C" }, Clouds = false,
	Props = { Coral = 6, Seaweed = 4, Chest = 1, Boulder = 1 }, PropCount = 30,
	Sky = { Clock = 12, Fog = "#3C8CC8", FogEnd = 500, Ambient = "#5A8CB4", Outdoor = "#507CA0", Atmosphere = "#3C96DC", Density = 0.5 },
})
