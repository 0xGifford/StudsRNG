require(game:GetService("ServerStorage").ZoneKit:Clone()).build({
	Index = 45, Id = "Fairy", Name = "Fairy Forest", Subtitle = "A little magic",
	Trim = "#E6A0FF", Ground = "#5A9A6A", Ground2 = { "#4A8A5A", "#6AAA7A", "#E6A0FF" }, Path = "#F0E6C8",
	Rock = { "#6E7A7A", "#5E6A6A", "#7E8A8A" }, Cap = "#4A8A5A", WallHeight = 44,
	Keys = { "#FFFFFF", "#E6A0FF", "#A0FFE6" }, Plate = "#2B2B33",
	Palette = { "#E6A0FF", "#A0FFE6", "#FFE6A0", "#FF96C8" }, Leaves = { "#3E8A5A", "#4A9A6A", "#E6A0FF" },
	Props = { Tree = 3, Mushroom = 3, Flowers = 3, Lamp = 1, Crystal = 1 }, PropCount = 30,
	Sky = { Clock = 19, Fog = "#C8B4E6", FogEnd = 800, Ambient = "#8A7AA0", Outdoor = "#969696", Atmosphere = "#DCC8F0", Density = 0.35 },
})
