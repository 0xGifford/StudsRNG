require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 7, Id = "Space", Name = "Heaven", Subtitle = "Low gravity, high rolls",
	Trim = "#FFE678", Ground = "#FAFAFF", Ground2 = { "#FFF6DC", "#F0F4FF", "#FFFCF0" }, Path = "#FFDE78",
	Rock = { "#FFFFFF", "#F4F6FF", "#FFFAF0" }, WallHeight = 28,
	Keys = { "#FFFFFF", "#FFECA0", "#FFD2E6" }, Plate = "#E6C878",
	Palette = { "#FFE678", "#FFFFFF" }, Stone = "#F2EEE4",
	Props = { Pillar = 4, Cloud = 4, Arch = 1, Crystal = 1 }, PropCount = 30,
	Sky = { Clock = 12.5, Fog = "#FFF5E1", FogEnd = 900, Ambient = "#B4AA96", Outdoor = "#C8BEAA", Atmosphere = "#FFF0D2", Density = 0.3, Gravity = 70 },
})
