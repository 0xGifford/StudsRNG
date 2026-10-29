require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 49, Id = "Void", Name = "The Void", Subtitle = "Nothing but keys",
	Trim = "#FFFFFF", Ground = "#141418", Ground2 = { "#0E0E12", "#1E1E24" }, Path = "#FFFFFF",
	Rock = { "#1E1E24", "#141418", "#2A2A32" },
	Keys = { "#141418", "#FFFFFF", "#8C8C96" }, Plate = "#2B2B33",
	Palette = { "#FFFFFF", "#8C8C96", "#B478FF" }, Clouds = false,
	Props = { Orb = 4, Spire = 3, Crystal = 2 }, PropCount = 30,
	Sky = { Clock = 0, Fog = "#000000", FogEnd = 500, Ambient = "#5A5A64", Outdoor = "#3C3C46", Atmosphere = "#1E1E28", Density = 0.3, Gravity = 45 },
	-- Golden City, the zone before, blends in at the entrance.
	From = { Ground2 = { "#E6CC8A", "#FFE6B4" }, Path = "#FFD23C", Rock = { "#E6C878", "#D2B464", "#F0D28C" }, Cap = "#FFFFFF" },
})
