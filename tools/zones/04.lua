require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 4, Id = "Neon", Name = "Volcano", Subtitle = "Things are heating up",
	Trim = "#FF6E1E", Ground = "#463430", Ground2 = { "#3A2C2A", "#563E36", "#603228" }, Path = "#FF8A1E",
	Rock = { "#6E3C2E", "#5A3228", "#804834" },
	Keys = { "#3C3232", "#FF7828", "#FFC83C" }, Plate = "#241C1C",
	Props = { Boulder = 3, DeadTree = 2, Spire = 2, Torch = 2, Bones = 1 }, PropCount = 30,
	Features = { { "Mountain", "#5A3228", "#FF6E1E" } },
	Sky = { Clock = 17.6, Fog = "#783C28", FogEnd = 650, Ambient = "#965A46", Outdoor = "#8C503C", Atmosphere = "#FF8250", Density = 0.4 },
	-- Polar, the zone before, blends in at the entrance.
	From = { Ground2 = { "#DCEAF8", "#F6FAFF", "#C8E2F5" }, Path = "#AAD7F5", Rock = { "#96BEDC", "#7EA8CD", "#B0D0E8" }, Cap = "#F5FAFF" },
})
