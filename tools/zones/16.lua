require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 16, Id = "Canyon", Name = "Red Canyon", Subtitle = "Echoing Clacks",
	Trim = "#E0643C", Ground = "#C8784A", Ground2 = { "#B8683C", "#D4885A" }, Path = "#E0B48A",
	Rock = { "#B4502E", "#9A4026", "#C8643C" },
	Keys = { "#FFE6D2", "#FF9664", "#C8502E" }, Plate = "#2B2B33",
	Props = { Spire = 5, Cactus = 2, Boulder = 2, Bones = 1 }, PropCount = 30,
	Sky = { Clock = 16, Fog = "#F0B48C", FogEnd = 1200, Ambient = "#966A56", Outdoor = "#969696", Atmosphere = "#FFC8A0", Density = 0.3 },
	-- Sakura Gardens, the zone before, blends in at the entrance.
	From = { Ground2 = { "#FFC8E0", "#6EB45A", "#8ED478" }, Path = "#E6D2B4", Rock = { "#A09A96", "#8A8480", "#B4AEA8" }, Cap = "#FFC8E0" },
})
