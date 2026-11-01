--[[ 

StudCell
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/UI/StudCell

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Stud viewports for code that fills lists. The drawing is MenuSystem's
-- StudView: a ViewportFrame with Stud = "<id>" (and StudVariant,
-- ViewSilhouette) draws itself. These helpers just set those attributes,
-- so a viewport designed in Studio and one copied from a template behave
-- the same.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)

local Menus = ReplicatedStorage:WaitForChild("MenuSystem"):WaitForChild("Menus")
local StudView = require(Menus:WaitForChild("StudView"))

local Kit = require(script.Parent.Kit)

type StudDef = Types.StudDef
type VariantDef = Types.VariantDef

local StudCell = {}

-- A copy of StarterGui.Templates.StudViewport showing this stud.
function StudCell.viewport(def: StudDef, variant: VariantDef): ViewportFrame
	local viewport = Kit.template("StudViewport") :: ViewportFrame
	viewport.Name = "Viewport"
	StudCell.setViewport(viewport, def, variant)
	return viewport
end

function StudCell.setViewport(viewport: ViewportFrame, def: StudDef, variant: VariantDef)
	StudView.Set(viewport, { Stud = def.Id, StudVariant = variant.Name })
end

-- Dark shape for studs not found yet.
function StudCell.setSilhouette(viewport: ViewportFrame, on: boolean)
	StudView.Set(viewport, { ViewSilhouette = on })
end

return StudCell
