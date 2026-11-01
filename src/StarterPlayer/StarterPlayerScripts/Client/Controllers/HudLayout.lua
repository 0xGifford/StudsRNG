--[[

HudLayout
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/HudLayout

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The HUD's Slime RNG layout is baked into StarterGui.HUD itself now
-- (tools/ui/migrate.luau: right column SHOP · REBIRTH · INDEX · TELEPORT,
-- the LeftButtons grid, the bottom bar BACKPACK · ROLL · UPGRADE · AUTO, the
-- Pass / Badges side buttons, the combo label). Edit it in Studio; nothing
-- moves it at runtime. This only warns when a place's HUD was never
-- migrated, so the cause is obvious.

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local Interface = require(UI.Interface)

local HudLayout = {}

function HudLayout.start()
	Interface.setup()
	if Interface.HUD:GetAttribute("HudArranged") ~= true then
		warn("[HudLayout] StarterGui.HUD hasn't been migrated: run `lune run tools/ui/migrate.luau place <in.rbxl> <out.rbxl>` on your place")
	end
end

return HudLayout
