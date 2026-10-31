--!strict
-- StudsRNG addition. Single responsibility: which game zone the brush paints
-- for. Like ToolSection, these belong to the gesture, not to a group.
--
--   Zone         From surface (the zone of whatever the key lands on) |
--                Locked (always the zone picked below) | None
--   Locked to    Zone1 .. ZoneN, only shown when Locked
--   Zone groups  paint each zone's keys into its own group (Zone7), so every
--                zone's keyboard has its own look
--   Under cursor the zone a key would pay in right now

local Components = script.Parent.Parent.Components
local Row = require(Components.Row)
local Segmented = require(Components.Segmented)
local Dropdown = require(Components.Dropdown)
local Toggle = require(Components.Toggle)
local Theme = require(Components.Theme)
local Brush = require(script.Parent.Parent.Parent.Placement.Brush)

local ZoneSection = {}
ZoneSection.__index = ZoneSection

function ZoneSection.new(parent: Instance, order: number, overlay: GuiObject)
	local self = setmetatable({}, ZoneSection)

	self.OnModeChanged = nil :: ((string) -> ())?
	self.OnLockChanged = nil :: ((number) -> ())?
	self.OnGroupsChanged = nil :: ((boolean) -> ())?

	local modeRow = Row.new(parent, order, nil)
	self.mode = Segmented.new(modeRow.Content, {
		Options = Brush.ZONE_MODES,
		Labels = { Auto = "From surface", Locked = "Locked", Off = "None" },
		Value = "Auto",
	})

	local lockRow = Row.new(parent, order + 1, "Locked to")
	self.lockRow = lockRow
	self.lock = Dropdown.new(lockRow.Content, { Entries = {}, Overlay = overlay })
	self.lock.Frame.Size = UDim2.fromScale(1, 1)
	self.lock.OnChanged = function(value: string)
		local n = tonumber(string.match(value, "%d+"))
		if n and self.OnLockChanged then
			self.OnLockChanged(n)
		end
	end

	local groupsRow = Row.new(parent, order + 2, "Zone groups")
	self.groups = Toggle.new(groupsRow.Content, { Value = true })
	self.groups.OnChanged = function(value)
		if self.OnGroupsChanged then self.OnGroupsChanged(value) end
	end

	local hintRow = Row.new(parent, order + 3, nil, 32)
	local hint = Theme.Text("Each zone's keys go in their own group (Zone7) and pay in that zone.", hintRow.Content)
	hint.TextColor3 = Theme.Color(Enum.StudioStyleGuideColor.DimmedText)
	hint.TextWrapped = true
	hint.TextYAlignment = Enum.TextYAlignment.Top
	hint.TextSize = Theme.TEXT_SIZE - 2

	local hoverRow = Row.new(parent, order + 4, "Under cursor")
	self.hover = Theme.Text("-", hoverRow.Content)
	self.hover.Font = Theme.FONT_BOLD

	self.mode.OnChanged = function(value)
		self.lockRow:SetVisible(value == "Locked")
		if self.OnModeChanged then self.OnModeChanged(value) end
	end
	self.lockRow:SetVisible(false)

	return self
end

ZoneSection.ROW_COUNT = 5

-- zones: the zone numbers present in the place; current: the locked one.
function ZoneSection:SetZones(zones: { number }, current: number?)
	local entries = {}
	for _, n in ipairs(zones) do
		table.insert(entries, { Value = "Zone" .. n })
	end
	self.lock:SetEntries(entries, if current then "Zone" .. current else nil)
end

function ZoneSection:SetHover(zone: number?)
	self.hover.Text = if zone then "Zone " .. zone else "No zone"
	self.hover.TextColor3 = if zone then Theme.OK else Theme.Color(Enum.StudioStyleGuideColor.DimmedText)
end

return ZoneSection
