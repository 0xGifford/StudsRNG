--!strict
-- Single responsibility: push a group's LOOK onto its members' caps.
-- Reads the group (GroupRegistry), computes the colours (GradientSolver),
-- assigns. Decides nothing itself.
--
-- Called after every edit AND after every stroke: a gradient depends on the
-- whole membership, so adding one key restyles the group.

local CollectionService = game:GetService("CollectionService")

local Constants = require(script.Parent.Parent.Constants)
local Chunker = require(script.Parent.Parent.Core.Chunker)
local GroupRegistry = require(script.Parent.Parent.Core.GroupRegistry)
local GradientSolver = require(script.Parent.GradientSolver)
local RandomColor = require(script.Parent.RandomColor)
local FontPresets = require(script.Parent.Parent.RuntimeSource.Style.FontPresets)

local GroupStyler = {}

-- Salts keep the cap and text channels from landing on the same hue in
-- Random mode when they're fed the exact same positions.
local CAP_RANDOM_SALT = 0
local TEXT_RANDOM_SALT = 1000

-- One colour per position, per the channel's own mode. Solid/Gradient/Random
-- are the only three GroupStyler knows about — an unrecognised mode (stale
-- data) is treated as Solid rather than erroring.
--
-- Random reads the SAME base colour as Solid, plus three variation
-- amplitudes: one base colour, three knobs, everything from "shades of blue"
-- to "confetti". See Edit.RandomColor.
local function resolveChannelColors(
	mode: string,
	positions: { Vector3 },
	solidColor: Color3,
	axis: string,
	gradientColor: Color3,
	random: { hue: number, sat: number, value: number },
	randomSalt: number
): { Color3 }
	if mode == "Gradient" then
		return GradientSolver.Colors(positions, axis, solidColor, gradientColor)
	elseif mode == "Random" then
		return RandomColor.Colors(positions, solidColor, random.hue, random.sat, random.value, randomSalt)
	end

	local colors: { Color3 } = {}
	for index = 1, #positions do
		colors[index] = solidColor
	end
	return colors
end

local function capOf(key: Model): BasePart?
	local cap = key:FindFirstChild("Cap")
	return cap and cap:IsA("BasePart") and cap or nil
end

-- The label/stroke are always built together by GuiFactory, so either both
-- are found or neither is: a nil here means the GUI hasn't been built yet
-- (streaming, or a placement mid-flight), not a broken key.
local function guiLabelAndStrokeOf(cap: BasePart): (SurfaceGui?, TextLabel?, UIStroke?)
	local gui = cap:FindFirstChild("SurfaceGui")
	if not (gui and gui:IsA("SurfaceGui")) then return nil, nil, nil end
	local label = gui:FindFirstChild("TextLabel")
	if not (label and label:IsA("TextLabel")) then return gui, nil, nil end
	local stroke = label:FindFirstChild("UIStroke")
	return gui, label, (stroke and stroke:IsA("UIStroke") and stroke or nil)
end

-- The core pass. `candidates` are walked in chunks; when `filterGroup` is
-- given, the ones that don't belong to it are skipped as part of that same
-- walk rather than being filtered out beforehand — resolving membership up
-- front meant one unchunked O(keys) scan (~15ms on a 9k board) running before
-- the first yield, which was most of the hitch that survived chunking.
--
-- shouldAbort is polled at each yield and is what lets a superseded pass stop
-- mid-list; the return value says whether it ran to the end.
local function styleMembers(
	name: string,
	candidates: { Instance },
	filterGroup: string?,
	shouldAbort: (() -> boolean)?
): boolean
	if #candidates == 0 then return true end

	local caps: { BasePart } = {}
	local positions: { Vector3 } = {}
	local gathered = Chunker.Each(candidates, function(member)
		if filterGroup then
			if not member:IsA("Model") then return end
			if member:GetAttribute(Constants.ATTR_GROUP) ~= filterGroup then return end
		end
		local cap = capOf(member :: Model)
		if cap then
			table.insert(caps, cap)
			table.insert(positions, cap.Position)
		end
	end, shouldAbort)
	if not gathered then return false end
	if #caps == 0 then return true end

	local capMode = GroupRegistry.GetValue(name, "CapColorMode") :: string
	local textMode = GroupRegistry.GetValue(name, "TextColorMode") :: string

	local capColors = resolveChannelColors(
		capMode,
		positions,
		GroupRegistry.GetValue(name, "Color") :: Color3,
		GroupRegistry.GetValue(name, "GradientAxis") :: string,
		GroupRegistry.GetValue(name, "GradientColor") :: Color3,
		{
			hue = GroupRegistry.GetValue(name, "CapRandomHue") :: number,
			sat = GroupRegistry.GetValue(name, "CapRandomSat") :: number,
			value = GroupRegistry.GetValue(name, "CapRandomValue") :: number,
		},
		CAP_RANDOM_SALT
	)

	local textColors = resolveChannelColors(
		textMode,
		positions,
		GroupRegistry.GetValue(name, "TextColor") :: Color3,
		GroupRegistry.GetValue(name, "TextGradientAxis") :: string,
		GroupRegistry.GetValue(name, "TextGradientColor") :: Color3,
		{
			hue = GroupRegistry.GetValue(name, "TextRandomHue") :: number,
			sat = GroupRegistry.GetValue(name, "TextRandomSat") :: number,
			value = GroupRegistry.GetValue(name, "TextRandomValue") :: number,
		},
		TEXT_RANDOM_SALT
	)

	-- Font/stroke don't depend on membership like a gradient does: same value
	-- for every member, computed once outside the loop.
	local font = FontPresets.Resolve(GroupRegistry.GetValue(name, "FontName") :: string)
	local strokeEnabled = GroupRegistry.GetValue(name, "StrokeEnabled") :: boolean
	local strokeColor = GroupRegistry.GetValue(name, "StrokeColor") :: Color3
	local strokeSize = GroupRegistry.GetValue(name, "StrokeSize") :: number
	local maxDistance = GroupRegistry.GetValue(name, "LabelMaxDistance") :: number

	-- Cap colour, label and outline in ONE walk: this used to be two passes
	-- over the same list, which is two chunked walks for no benefit.
	return Chunker.Each(caps, function(cap, index)
		cap.Color = capColors[index]

		local gui, label, stroke = guiLabelAndStrokeOf(cap)
		if gui then
			gui.MaxDistance = maxDistance
		end
		if label then
			label.TextColor3 = textColors[index]
			label.FontFace = font
		end
		if stroke then
			stroke.Enabled = strokeEnabled
			stroke.Color = strokeColor
			stroke.Thickness = strokeSize
		end
	end, shouldAbort)
end

-- onlyKeys: restyle just those members instead of the whole group. The caller
-- passes it after a paint stroke, when recolouring everything would be
-- wasted work — a full pass is O(members), so a one-key stroke on a large
-- group cost as much as rebuilding the group.
--
-- It is only honoured when the group's look does NOT depend on its
-- membership. A gradient spans the bounding box of its members, so adding a
-- key moves the ends and every member has to be recomputed; that case
-- silently upgrades back to the full pass rather than leaving a stale
-- gradient behind.
function GroupStyler.Apply(name: string, onlyKeys: { Model }?, shouldAbort: (() -> boolean)?): boolean
	local capMode = GroupRegistry.GetValue(name, "CapColorMode") :: string
	local textMode = GroupRegistry.GetValue(name, "TextColorMode") :: string
	local membershipMatters = capMode == "Gradient" or textMode == "Gradient"

	if onlyKeys and not membershipMatters then
		return styleMembers(name, onlyKeys, nil, shouldAbort)
	end

	-- Full pass: hand the raw tagged list over and let the chunked gather do
	-- the group filter, rather than building the member array first.
	return styleMembers(name, CollectionService:GetTagged(Constants.TAG_KEY), name, shouldAbort)
end

-- Restyles every group at once. Used after a bulk change or an erase stroke, when
-- we do not know which groups were touched.
--
-- Goes through one bucketed walk rather than Apply per group: resolving each
-- group's membership separately rescanned the whole board once per group.
function GroupStyler.ApplyAll(shouldAbort: (() -> boolean)?): boolean
	for name, members in pairs(GroupRegistry.MembersByGroup()) do
		if not styleMembers(name, members, nil, shouldAbort) then return false end
	end
	return true
end

return GroupStyler
