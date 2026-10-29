require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 14, Id = "Swamp", Name = "Swamp", Subtitle = "Bog-standard Clacks",
	Trim = "#8CC83C", Ground = "#4E5A36", Ground2 = { "#44502E", "#5A6640", "#3A5A4A" }, Path = "#6A5A3A",
	Rock = { "#4A5040", "#3E4434", "#58604C" }, WallHeight = 38,
	Keys = { "#E6F0C8", "#9CC85A", "#5A8A3C" }, Plate = "#2B2B33",
	Palette = { "#8CC83C", "#C8E65A" }, Leaves = { "#4A6A2E", "#5A7A36" },
	Props = { DeadTree = 4, Mushroom = 2, Seaweed = 2, Bush = 2 }, PropCount = 30,
	Sky = { Clock = 17, Fog = "#6E7A50", FogEnd = 450, Ambient = "#5A6446", Outdoor = "#969696", Atmosphere = "#8C9A64", Density = 0.5 },
})
