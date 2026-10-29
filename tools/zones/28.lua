require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 28, Id = "Atlantis", Name = "Atlantis", Subtitle = "The lost keyboard",
	Trim = "#3CC8E6", Ground = "#C8D2C8", Ground2 = { "#B4C8BE", "#DCE6DC" }, Path = "#E6E6DC",
	Rock = { "#6E9AA8", "#5A8A9A", "#82AAB8" },
	Keys = { "#FFFFFF", "#3CC8E6", "#FFD23C" }, Plate = "#2B2B33",
	Palette = { "#FF6EAA", "#FFD23C", "#3CC8E6" }, Stone = "#E6E6DC", Clouds = false,
	Props = { Pillar = 4, Arch = 2, Coral = 3, Seaweed = 2 }, PropCount = 30,
	Sky = { Clock = 12, Fog = "#2878B4", FogEnd = 450, Ambient = "#5A8CB4", Outdoor = "#46789E", Atmosphere = "#2896DC", Density = 0.5 },
	-- Galaxy, the zone before, blends in at the entrance.
	From = { Ground2 = { "#24203E", "#3A3458" }, Path = "#B478FF", Rock = { "#3A3458", "#2E2A4A", "#4A4268" } },
})
