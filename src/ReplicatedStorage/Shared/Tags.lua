--[[

Tags
ModuleScript
/ReplicatedStorage/Shared/Tags

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Every CollectionService tag and attribute the game reads from the world
-- and the UI. Build anything by hand in Studio, tag it, set its attributes,
-- and the game picks it up (MapBuilder's generated map uses the same tags,
-- so generated and hand-built pieces behave identically). Attributes are
-- read live: change one in a running test and the game follows.
--
-- WORLD
--   Zone          Model / Folder / Part covering one zone.
--                   ZoneId    string   Shared/Zones id (default: its Name)
--                   Center    Vector3  middle of the zone floor   } default: the
--                   ZoneSize  Vector3  extents of the zone        } bounding box
--                 Anything inside it belongs to that zone.
--   ZoneSpawn     BasePart players teleport to (the Teleporter, and when
--                 falling off the map; buying a zone never teleports).
--                   ZoneId    string   default: the Zone it sits in
--   ZoneBarrier   BasePart (or a Model of them) blocking a zone's entrance.
--                 Opens locally once the zone is owned. Until then a sign on
--                 it (SurfaceGui) shows the zone's title, its price in Clacks
--                 and a BUY button you click on the barrier itself.
--                   ZoneId          string   default: the Zone it sits in
--                   ShowPrompt      boolean  show the sign (default true)
--                   PromptDistance  number   studs the sign renders from (default 150)
--                   Title           string   sign title (default: emoji + zone name)
--   ZoneGate      Decoration around a barrier (arch, pillars). Hidden locally
--                 once the zone is owned when HideWhenOwned is true.
--                   ZoneId          string
--                   HideWhenOwned   boolean  default false
--   Keyboard      Model / Folder holding keys.
--                   ZoneId      string   zone its keys pay in (default: the Zone it sits in)
--                   KeyValue    number   Clacks per press for keys without their own Value
--                   Multiplier  number   extra multiplier on every key in it (default 1)
--                   Enabled     boolean  false: its keys never pay (default true)
--   KeyCapper_Hitbox (Config.Press.HitboxTag, placed by the KeyCapper plugin)
--                 A key's hitbox; its parent Model is the key.
--                   Value    number   Clacks per press (on the key Model)
--                   World    string   zone id (on the key Model; default: its Keyboard / Zone)
--                   Enabled  boolean  false: this key never pays (default true)
--   EnemySpawn    BasePart where an enemy lives (wanders around it).
--                   ZoneId    string   default: the Zone it sits in
--                 Zones without any get Config.Combat.PerZone spots of their own.
--   Enemy         set by the server on each enemy Model (EnemyId, ZoneId,
--                 Health, MaxHealth attributes); don't place these yourself.
--   Leaderboard   BasePart showing a global top list on its front face.
--                   Board     string   Clacks | Enemies | Rarest (default Clacks)
--                   Face      string   NormalId to draw on (default Front)
--   MenuTrigger   BasePart that opens a menu.
--                   Menu        string   menu name (a Menu.Canva window, or Upgrades)
--                   MenuAction  string   Open (default) | Toggle | Close
--                   Prompt      boolean  use a ProximityPrompt instead of touch (default false)
--                   PromptText  string   default "Open"
--
-- UI (anywhere under PlayerGui: HUD, Menu, SurfaceGuis, BillboardGuis)
--   A GuiButton, or a kit button Frame (with a "Button" child), carrying
--     Menu        string   the menu it opens
--     MenuAction  string   Toggle (default) | Open | Close
--   A Menu.Canva window carrying
--     Blur     boolean  blur the world while open (default true)
--     HideHUD  boolean  slide the HUD away while open (default true)

local CollectionService = game:GetService("CollectionService")

local Tags = {
	Zone = "Zone",
	ZoneSpawn = "ZoneSpawn",
	ZoneBarrier = "ZoneBarrier",
	ZoneGate = "ZoneGate",
	Keyboard = "Keyboard",
	MenuTrigger = "MenuTrigger",
	EnemySpawn = "EnemySpawn",
	Enemy = "Enemy",
	Leaderboard = "Leaderboard",

	Attr = {
		ZoneId = "ZoneId",
		Center = "Center",
		ZoneSize = "ZoneSize",
		ShowPrompt = "ShowPrompt",
		PromptDistance = "PromptDistance",
		Title = "Title",
		HideWhenOwned = "HideWhenOwned",
		KeyValue = "KeyValue",
		Multiplier = "Multiplier",
		Enabled = "Enabled",
		Value = "Value",
		World = "World",
		Menu = "Menu",
		MenuAction = "MenuAction",
		Prompt = "Prompt",
		PromptText = "PromptText",
		Blur = "Blur",
		HideHUD = "HideHUD",
		Board = "Board",
		Face = "Face",
	},
}

local Attr = Tags.Attr

-- An attribute of the given type, or the default.
function Tags.read<T>(instance: Instance, name: string, default: T): T
	local value = instance:GetAttribute(name)
	if value ~= nil and typeof(value) == typeof(default) then
		return value :: any
	end
	return default
end

function Tags.string(instance: Instance, name: string): string?
	local value = instance:GetAttribute(name)
	return if typeof(value) == "string" and value ~= "" then value else nil
end

-- The nearest ancestor (or the instance itself) carrying the tag.
function Tags.ancestorWith(instance: Instance, tag: string): Instance?
	local node: Instance? = instance
	while node and node ~= game do
		if CollectionService:HasTag(node, tag) then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- The id of a Zone-tagged instance: its ZoneId, else its Name.
function Tags.idOfZone(zone: Instance): string
	return Tags.string(zone, Attr.ZoneId) or zone.Name
end

-- Which zone an instance belongs to: its own ZoneId, else the Zone it sits in.
function Tags.zoneOf(instance: Instance): string?
	local own = Tags.string(instance, Attr.ZoneId)
	if own then return own end
	local zone = Tags.ancestorWith(instance, Tags.Zone)
	return if zone then Tags.idOfZone(zone) else nil
end

-- A key's zone: the key Model's World, else its Keyboard's / Zone's.
function Tags.keyZone(hitbox: Instance): string?
	local model = hitbox.Parent
	if not model then return nil end
	local world = Tags.string(model, Attr.World)
	if world then return world end
	local keyboard = Tags.ancestorWith(model, Tags.Keyboard)
	local fromKeyboard = keyboard and Tags.string(keyboard, Attr.ZoneId)
	if fromKeyboard then return fromKeyboard end
	return Tags.zoneOf(model)
end

-- Every tagged instance of a zone (e.g. all ZoneSpawns of "Arcade").
function Tags.forZone(tag: string, zoneId: string): { Instance }
	local found: { Instance } = {}
	for _, instance in CollectionService:GetTagged(tag) do
		local id = if tag == Tags.Zone then Tags.idOfZone(instance) else Tags.zoneOf(instance)
		if id == zoneId then
			table.insert(found, instance)
		end
	end
	return found
end

-- The first ZoneSpawn of a zone that's a BasePart in the workspace.
function Tags.spawnOf(zoneId: string): BasePart?
	for _, instance in Tags.forZone(Tags.ZoneSpawn, zoneId) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			return instance
		end
	end
	return nil
end

-- A zone's box: its Center/ZoneSize attributes, else its bounds.
function Tags.zoneBox(zone: Instance): (CFrame?, Vector3?)
	local center = zone:GetAttribute(Attr.Center)
	local size = zone:GetAttribute(Attr.ZoneSize)
	if typeof(center) == "Vector3" and typeof(size) == "Vector3" then
		return CFrame.new(center + Vector3.new(0, size.Y / 2 - 10, 0)), size
	elseif zone:IsA("Model") then
		local cframe, extents = zone:GetBoundingBox()
		return cframe, extents + Vector3.new(0, 40, 0)
	elseif zone:IsA("BasePart") then
		return zone.CFrame, zone.Size
	end
	-- A Folder: the box around every part inside it.
	local low: Vector3?, high: Vector3? = nil, nil
	for _, descendant in zone:GetDescendants() do
		if descendant:IsA("BasePart") then
			local half = descendant.Size / 2
			local a, b = descendant.Position - half, descendant.Position + half
			low = if low then low:Min(a) else a
			high = if high then high:Max(b) else b
		end
	end
	if low and high then
		return CFrame.new((low + high) / 2), (high - low) + Vector3.new(0, 40, 0)
	end
	return nil, nil
end

return Tags
