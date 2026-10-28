--[[

MapThemes
ModuleScript
/ReplicatedStorage/Shared/MapThemes

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- How each zone looks and feels. Read by the server's MapBuilder (floor,
-- keys, props) and the client's ZoneAmbience (lighting, title card,
-- gravity). Keyed by Shared/Zones ids.

export type Theme = {
	Subtitle: string,
	Floor: Color3,
	FloorMaterial: Enum.Material,
	Trim: Color3, -- platform edge / neon accents
	Keys: { Color3 }, -- keycap colours, cycled per row
	Prop: string, -- MapBuilder prop set
	-- Lighting while the local player is in the zone
	ClockTime: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	FogColor: Color3,
	FogEnd: number,
	AtmosphereColor: Color3,
	AtmosphereDensity: number,
	Gravity: number,
}

local themes: { [string]: Theme } = {
	Office = {
		Subtitle = "Where every Clack begins",
		Floor = Color3.fromRGB(196, 186, 170),
		FloorMaterial = Enum.Material.Fabric,
		Trim = Color3.fromRGB(110, 150, 220),
		Keys = { Color3.fromRGB(245, 245, 240), Color3.fromRGB(205, 210, 220), Color3.fromRGB(140, 170, 230) },
		Prop = "Office",
		ClockTime = 14,
		Ambient = Color3.fromRGB(120, 120, 130),
		OutdoorAmbient = Color3.fromRGB(150, 150, 160),
		FogColor = Color3.fromRGB(200, 215, 235),
		FogEnd = 900,
		AtmosphereColor = Color3.fromRGB(200, 215, 235),
		AtmosphereDensity = 0.25,
		Gravity = 196.2,
	},
	Arcade = {
		Subtitle = "Insert Clacks to continue",
		Floor = Color3.fromRGB(30, 18, 45),
		FloorMaterial = Enum.Material.SmoothPlastic,
		Trim = Color3.fromRGB(255, 70, 200),
		Keys = { Color3.fromRGB(255, 90, 200), Color3.fromRGB(120, 80, 255), Color3.fromRGB(60, 220, 255) },
		Prop = "Arcade",
		ClockTime = 20.5,
		Ambient = Color3.fromRGB(110, 60, 140),
		OutdoorAmbient = Color3.fromRGB(90, 50, 130),
		FogColor = Color3.fromRGB(60, 20, 80),
		FogEnd = 600,
		AtmosphereColor = Color3.fromRGB(150, 60, 200),
		AtmosphereDensity = 0.35,
		Gravity = 196.2,
	},
	Studio = {
		Subtitle = "Turn the volume up",
		Floor = Color3.fromRGB(120, 80, 50),
		FloorMaterial = Enum.Material.WoodPlanks,
		Trim = Color3.fromRGB(255, 170, 60),
		Keys = { Color3.fromRGB(40, 40, 46), Color3.fromRGB(255, 160, 50), Color3.fromRGB(230, 225, 215) },
		Prop = "Studio",
		ClockTime = 18,
		Ambient = Color3.fromRGB(140, 100, 70),
		OutdoorAmbient = Color3.fromRGB(150, 110, 80),
		FogColor = Color3.fromRGB(80, 50, 35),
		FogEnd = 700,
		AtmosphereColor = Color3.fromRGB(255, 170, 110),
		AtmosphereDensity = 0.3,
		Gravity = 196.2,
	},
	Neon = {
		Subtitle = "The city never sleeps",
		Floor = Color3.fromRGB(28, 30, 38),
		FloorMaterial = Enum.Material.Asphalt,
		Trim = Color3.fromRGB(0, 230, 255),
		Keys = { Color3.fromRGB(0, 230, 255), Color3.fromRGB(255, 40, 140), Color3.fromRGB(255, 240, 0) },
		Prop = "Neon",
		ClockTime = 0,
		Ambient = Color3.fromRGB(60, 80, 120),
		OutdoorAmbient = Color3.fromRGB(50, 60, 110),
		FogColor = Color3.fromRGB(20, 25, 60),
		FogEnd = 500,
		AtmosphereColor = Color3.fromRGB(60, 80, 200),
		AtmosphereDensity = 0.4,
		Gravity = 196.2,
	},
	Space = {
		Subtitle = "Low gravity, high rolls",
		Floor = Color3.fromRGB(20, 18, 34),
		FloorMaterial = Enum.Material.Slate,
		Trim = Color3.fromRGB(176, 104, 255),
		Keys = { Color3.fromRGB(176, 104, 255), Color3.fromRGB(230, 230, 255), Color3.fromRGB(90, 220, 255) },
		Prop = "Space",
		ClockTime = 0,
		Ambient = Color3.fromRGB(70, 60, 110),
		OutdoorAmbient = Color3.fromRGB(40, 30, 80),
		FogColor = Color3.fromRGB(5, 5, 15),
		FogEnd = 2000,
		AtmosphereColor = Color3.fromRGB(40, 20, 90),
		AtmosphereDensity = 0.1,
		Gravity = 70,
	},
}

return themes
