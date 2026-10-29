require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 44, Id = "Underworld", Name = "Underworld", Subtitle = "Deep, dark Clacks",
	Trim = "#FF3C3C", Ground = "#2E2222", Ground2 = { "#241A1A", "#3A2A2A", "#4A1E1E" }, Path = "#FF3C3C",
	Rock = { "#3A2A2A", "#2E2020", "#4A3434" }, Roof = true,
	Keys = { "#2E2222", "#FF3C3C", "#FFB43C" }, Plate = "#2B2B33",
	Palette = { "#FF3C3C", "#FFB43C" },
	Props = { Spire = 3, Bones = 3, Torch = 3, Tombstone = 1 }, PropCount = 30,
	Sky = { Clock = 0, Fog = "#3C140E", FogEnd = 400, Ambient = "#8C3C32", Outdoor = "#6E281E", Atmosphere = "#8C1E14", Density = 0.5 },
	-- Neon Nights, the zone before, blends in at the entrance.
	From = { Ground2 = { "#221C30", "#342C44" }, Path = "#FF3CC8", Rock = { "#3A3248", "#2E2838", "#463C56" } },
})
