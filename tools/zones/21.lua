require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 21, Id = "Haunted", Name = "Haunted Hollow", Subtitle = "Spooky keys",
	Trim = "#9A5AFF", Ground = "#3A3A44", Ground2 = { "#2E2E38", "#46464E" }, Path = "#5A5060",
	Rock = { "#4A4650", "#3A3640", "#5A5660" },
	Keys = { "#C8C8D2", "#9A5AFF", "#FF8A28" }, Plate = "#2B2B33",
	Palette = { "#9A5AFF", "#FF8A28" },
	Props = { Tombstone = 5, DeadTree = 3, Pumpkin = 2, Lamp = 1 }, PropCount = 30,
	Sky = { Clock = 0.5, Fog = "#2A2438", FogEnd = 400, Ambient = "#5A5070", Outdoor = "#3C3450", Atmosphere = "#4A3C6E", Density = 0.5 },
	-- Farm, the zone before, blends in at the entrance.
	From = { Ground2 = { "#8A6A44", "#6EA44A", "#A8C864" }, Path = "#B48A5A", Rock = { "#8A7A6A", "#7A6A5A", "#9A8A7A" }, Cap = "#6EA44A" },
})
