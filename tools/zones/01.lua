require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 1, Id = "Office", Name = "Grasslands", Subtitle = "Where every Clack begins",
	Trim = "#FFE678", Ground = "#6EBE50", Ground2 = { "#62B046", "#7ECC5C", "#8CC454" }, Path = "#C4A06E",
	Rock = { "#80766E", "#686262", "#8E8478" }, Cap = "#68B44A",
	Keys = { "#FAFAF5", "#D6ECC8", "#FFEEAA" }, Plate = "#463C34",
	Palette = { "#FF6B8A", "#FFD23C", "#FFFFFF", "#9B6BFF" },
	Props = { Tree = 5, Bush = 3, Flowers = 3, Boulder = 2, Fence = 1 }, PropCount = 30,
	Sky = { Clock = 14, Fog = "#BEE1FF", FogEnd = 1400, Ambient = "#828282", Outdoor = "#969696", Atmosphere = "#C8E1FF", Density = 0.2 },
})
