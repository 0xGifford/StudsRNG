--[[

MapAssets
ModuleScript
/ReplicatedStorage/Shared/MapAssets

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Generated 3D models (ForgeGUI) dressing the biome valleys. MapBuilder
-- builds every zone from Parts first, with each mesh prop's Fallback in its
-- place, then loads these with InsertService and swaps them in. A model that
-- fails to load (not published yet, or the place isn't owned by the
-- creator that owns the asset) just leaves its fallback standing.
--
-- Props: scattered by MapThemes[zone].Props weights, like the Part props.
--   Height    studs from the ground to the top (varied ±15% per copy)
--   Fallback  MapBuilder Part prop to build until the mesh loads
--   Collide   players bump into it
-- Landmarks: one hero piece per zone, at Offset from the zone centre.
--   Radius    props keep this far away from it
--   Light     optional PointLight colour

export type PropAsset = {
	Id: number,
	Height: number,
	Fallback: string,
	Collide: boolean,
}

export type LandmarkAsset = {
	Id: number,
	Height: number,
	Offset: Vector3,
	Yaw: number, -- degrees
	Radius: number,
	Light: Color3?,
}

local Props: { [string]: PropAsset } = {
	-- Grasslands
	Oak = { Id = 0, Height = 17, Fallback = "Tree", Collide = true },
	FlowerBush = { Id = 0, Height = 6, Fallback = "Bush", Collide = false },
	MossRock = { Id = 0, Height = 6, Fallback = "Boulder", Collide = true },
	-- Beach
	PalmTree = { Id = 87670978379443, Height = 22, Fallback = "Palm", Collide = true },
	BeachSet = { Id = 123639382212087, Height = 10, Fallback = "Umbrella", Collide = false },
	Sandcastle = { Id = 71307309103643, Height = 7, Fallback = "Shells", Collide = true },
	-- Polar
	SnowPine = { Id = 78971354284239, Height = 20, Fallback = "Pine", Collide = true },
	IceCluster = { Id = 86038780561963, Height = 11, Fallback = "IceSpike", Collide = true },
	Frosty = { Id = 0, Height = 8, Fallback = "Snowman", Collide = true },
	-- Volcano
	CharredTree = { Id = 116412493482394, Height = 16, Fallback = "DeadTree", Collide = true },
	LavaRock = { Id = 122124084515883, Height = 6, Fallback = "Boulder", Collide = true },
	Obsidian = { Id = 125381719715376, Height = 13, Fallback = "Vent", Collide = true },
	-- Islands
	Tropical = { Id = 89878357382775, Height = 8, Fallback = "Bush", Collide = false },
	Tiki = { Id = 81602972227751, Height = 12, Fallback = "Boulder", Collide = true },
	StiltHut = { Id = 76180359059859, Height = 17, Fallback = "Hut", Collide = true },
	-- Cave
	GemCluster = { Id = 114859216875913, Height = 11, Fallback = "Crystal", Collide = true },
	GlowShrooms = { Id = 100143116186467, Height = 14, Fallback = "Mushroom", Collide = true },
	MineCart = { Id = 112434811630710, Height = 6, Fallback = "Boulder", Collide = true },
}

-- Keyed by Shared/Zones ids.
local Landmarks: { [string]: LandmarkAsset } = {
	Office = { Id = 0, Height = 52, Offset = Vector3.new(-60, 0, 44), Yaw = 35, Radius = 20 },
	Arcade = { Id = 87326614270003, Height = 60, Offset = Vector3.new(70, 0, -48), Yaw = 0, Radius = 14,
		Light = Color3.fromRGB(255, 230, 140) },
	Studio = { Id = 130881164863635, Height = 22, Offset = Vector3.new(-58, 0, 46), Yaw = 40, Radius = 20 },
	Neon = { Id = 99942438399123, Height = 30, Offset = Vector3.new(58, 0, 46), Yaw = -140, Radius = 22,
		Light = Color3.fromRGB(255, 120, 40) },
	Islands = { Id = 0, Height = 30, Offset = Vector3.new(68, 0, 38), Yaw = 20, Radius = 22 },
}

return {
	Props = Props,
	Landmarks = Landmarks,
}
