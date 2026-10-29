require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 36, Id = "Dino", Name = "Dino Valley", Subtitle = "Prehistoric presses",
	Trim = "#7AB43C", Ground = "#7A9A4A", Ground2 = { "#6A8A3E", "#8AAA56" }, Path = "#A08A5A",
	Rock = { "#8A7A5E", "#7A6A50", "#9A8A6E" }, Cap = "#6A8A3E",
	Keys = { "#F0FFD8", "#7AB43C", "#C8783C" }, Plate = "#2B2B33",
	Leaves = { "#3E7A2A", "#4A8A34" },
	Props = { Tree = 3, Bones = 3, Palm = 2, Boulder = 2, Bush = 2 }, PropCount = 30,
	Features = { { "Mountain", "#6E5A46", "#FF6E1E" } },
	Sky = { Clock = 15, Fog = "#C8DCA0", FogEnd = 1000, Ambient = "#7A8264", Outdoor = "#969696", Atmosphere = "#DCE6B4", Density = 0.3 },
	-- Rainbow Road, the zone before, blends in at the entrance.
	From = { Ground2 = { "#E8413C", "#F28C28", "#F5D428", "#4CB84A", "#3C8FE0", "#7A4CC8" }, Path = "#FFFFFF", Rock = { "#E8413C", "#F28C28", "#F5D428", "#4CB84A", "#3C8FE0", "#7A4CC8" } },
})
