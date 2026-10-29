require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 3, Id = "Studio", Name = "Polar", Subtitle = "Keep your keys cool",
	Trim = "#96E6FF", Ground = "#ECF4FC", Ground2 = { "#DCEAF8", "#F6FAFF", "#C8E2F5" }, Path = "#AAD7F5",
	Rock = { "#96BEDC", "#7EA8CD", "#B0D0E8" }, Cap = "#F5FAFF", Snow = true,
	Keys = { "#FAFCFF", "#BEE6FF", "#96C8FF" }, Plate = "#3C5A78",
	Leaves = { "#2E6B4A", "#357A55", "#2A5E42" },
	Props = { Pine = 6, IceSpike = 3, Snowman = 1, Boulder = 1 }, PropCount = 30,
	Sky = { Clock = 15.5, Fog = "#D7EBFA", FogEnd = 700, Ambient = "#96A5B9", Outdoor = "#AAB9CD", Atmosphere = "#DCEEFF", Density = 0.35 },
	-- Beach, the zone before, blends in at the entrance.
	From = { Ground2 = { "#E6CC8A", "#F5E0A6", "#DEC484" }, Path = "#CEAA6E", Rock = { "#966046", "#84523C", "#A87050" }, Water = true },
})
