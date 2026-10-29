require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 19, Id = "Toyland", Name = "Toyland", Subtitle = "Play to win",
	Trim = "#3C8CFF", Ground = "#E6E6E6", Ground2 = { "#FF5A5A", "#3C8CFF", "#FFD23C", "#4CB84A" }, Path = "#FFFFFF",
	Rock = { "#FF5A5A", "#3C8CFF", "#FFD23C", "#4CB84A" },
	Keys = { "#FFFFFF", "#FFD23C", "#3C8CFF", "#FF5A5A" }, Plate = "#3C8CFF",
	Palette = { "#FF5A5A", "#3C8CFF", "#FFD23C", "#4CB84A", "#B478FF" },
	Props = { Gift = 4, Tower = 2, Gear = 1, Orb = 2 }, PropCount = 30,
	Sky = { Clock = 13, Fog = "#DCF0FF", FogEnd = 1400, Ambient = "#828282", Outdoor = "#969696", Atmosphere = "#C8E1FF", Density = 0.2 },
	-- Ashlands, the zone before, blends in at the entrance.
	From = { Ground2 = { "#2E2A2A", "#4A4040" }, Path = "#E04A1E", Rock = { "#4A4040", "#3A3232", "#5A4E4E" } },
})
