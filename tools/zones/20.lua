require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 20, Id = "Farm", Name = "Farm", Subtitle = "Harvest the Clacks",
	Trim = "#E0B43C", Ground = "#7EB45A", Ground2 = { "#8A6A44", "#6EA44A", "#A8C864" }, Path = "#B48A5A",
	Rock = { "#8A7A6A", "#7A6A5A", "#9A8A7A" }, Cap = "#6EA44A",
	Keys = { "#FFF8E6", "#E0B43C", "#C8643C" }, Plate = "#2B2B33",
	Palette = { "#E8413C", "#FFFFFF" },
	Props = { HayBale = 4, Fence = 3, Tree = 2, Pumpkin = 2, Barrel = 1 }, PropCount = 30,
	Sky = { Clock = 11, Fog = "#D2E6FF", FogEnd = 1500, Ambient = "#828282", Outdoor = "#969696", Atmosphere = "#C8E1FF", Density = 0.2 },
	-- Toyland, the zone before, blends in at the entrance.
	From = { Ground2 = { "#FF5A5A", "#3C8CFF", "#FFD23C", "#4CB84A" }, Path = "#FFFFFF", Rock = { "#FF5A5A", "#3C8CFF", "#FFD23C", "#4CB84A" } },
})
