require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 5, Id = "Islands", Name = "Islands", Subtitle = "Island hopping",
	Trim = "#3CE6C8", Ground = "#78C85A", Ground2 = { "#F0DCA0", "#6CBC50", "#86D462" }, Path = "#F0DEA5",
	Rock = { "#6E965A", "#5A8650", "#80A064" }, Cap = "#6EC450", Water = "#1EC8D2",
	Keys = { "#FFFFFA", "#6EE6D2", "#FF96AA" }, Plate = "#644630",
	Palette = { "#FF6B8A", "#FFD23C", "#FFFFFF" },
	Props = { Palm = 5, Bush = 3, Flowers = 2, Chest = 1 }, PropCount = 30,
	Sky = { Clock = 13, Fog = "#A0E1FF", FogEnd = 2000, Ambient = "#828282", Outdoor = "#969696", Atmosphere = "#C8E1FF", Density = 0.2 },
	-- Volcano, the zone before, blends in at the entrance.
	From = { Ground2 = { "#3A2C2A", "#563E36", "#603228" }, Path = "#FF8A1E", Rock = { "#6E3C2E", "#5A3228", "#804834" } },
})
