--[[
	ZoneManager: Mosswake's Studio plugin for setting up StudsRNG zones.
	Built from this folder by `lune run tools/build_plugin.luau` into
	ZoneManager.rbxmx; drop that file into your Studio Plugins folder.

	  Zones       every Zone<N> under workspace.Zones with what it still needs
	              (keys, enemy spawns). Click a row to select the zone.
	  Wire        one button that wires every zone for the game (ZoneWiring:
	              ids, boxes, gates and barriers on the DividerLines, spawns,
	              signs, EnemyGround on Ground). Safe to press again after
	              you move things; Undo puts it all back.
	  Active zone the zone your selection is in. Its tools: select Pit.Surf
	              (where the keyboard goes), select the gate, assign selected
	              keys to it, scatter / clear EnemySpawn markers, mark parts
	              as EnemyGround.
	  Tags / Attributes  add or remove any tag or attribute on the selection.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local Selection = game:GetService("Selection")
local Workspace = game:GetService("Workspace")

local Wiring = require(script.ZoneWiring)({
	Instance = Instance,
	Vector3 = Vector3,
	CFrame = CFrame,
	Color3 = Color3,
	Enum = Enum,
})

local ZONES_FOLDER = "Zones"
local KEY_TAG = "KeyCapper_Key"
local HITBOX_TAG = "KeyCapper_Hitbox"

--------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------

local toolbar = plugin:CreateToolbar("Mosswake")
local toggle = toolbar:CreateButton("MosswakeZoneManager", "Open the Zone Manager", "rbxassetid://4458901886", "Zone Manager")
toggle.ClickableWhenViewportHidden = true
local widget = plugin:CreateDockWidgetPluginGui("MosswakeZoneManager",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 380, 700, 300, 420))
widget.Title = "Zone Manager"
toggle.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggle:SetActive(widget.Enabled)
end)

local C = {
	bg = Color3.fromRGB(24, 26, 29), panel = Color3.fromRGB(32, 35, 39), input = Color3.fromRGB(19, 21, 24),
	border = Color3.fromRGB(58, 63, 70), text = Color3.fromRGB(235, 238, 241), muted = Color3.fromRGB(158, 166, 175),
	accent = Color3.fromRGB(132, 174, 139), warn = Color3.fromRGB(222, 184, 104), danger = Color3.fromRGB(190, 92, 92),
}

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local obj = Instance.new(className)
	for k, v in props do
		(obj :: any)[k] = v
	end
	obj.Parent = parent
	return obj
end

local root = make("Frame", { BackgroundColor3 = C.bg, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, widget)
local scroll = make("ScrollingFrame", {
	BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
	AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollBarThickness = 5, ScrollBarImageColor3 = C.border,
}, root)
make("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, scroll)
local body = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, scroll)
make("UIListLayout", { Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder }, body)

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function text(parent: Instance, value: string, size: number?, color: Color3?): TextLabel
	return make("TextLabel", {
		BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = value, TextColor3 = color or C.text, TextSize = size or 11,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, RichText = true,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder(),
	}, parent)
end

local status: TextLabel
local function report(message: string, kind: string?)
	status.Text = message
	status.TextColor3 = if kind == "bad" then C.danger elseif kind == "warn" then C.warn else C.accent
end

local function section(title: string, description: string?): Frame
	local f = make("Frame", { BackgroundColor3 = C.panel, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() }, body)
	make("UICorner", { CornerRadius = UDim.new(0, 7) }, f)
	make("UIStroke", { Color = C.border, Transparency = 0.45 }, f)
	make("UIPadding", { PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, f)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	local h = text(f, title, 13, C.accent)
	h.Font = Enum.Font.GothamBold
	if description then
		text(f, description, 10, C.muted)
	end
	return f
end

local function box(parent: Instance, hint: string, initial: string?): TextBox
	local b = make("TextBox", {
		BackgroundColor3 = C.input, BorderSizePixel = 0, ClearTextOnFocus = false, Font = Enum.Font.Code, PlaceholderText = hint,
		PlaceholderColor3 = C.muted, Text = initial or "", TextColor3 = C.text, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 30), LayoutOrder = nextOrder(),
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 5) }, b)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, b)
	return b
end

local function button(parent: Instance, caption: string, callback: () -> (), width: number?, primary: boolean?): TextButton
	local b = make("TextButton", {
		BackgroundColor3 = if primary then C.accent else C.input, BorderSizePixel = 0, Font = Enum.Font.GothamMedium, Text = caption,
		TextColor3 = if primary then C.bg else C.text, TextSize = 11, Size = UDim2.new(1, 0, 0, 29), LayoutOrder = nextOrder(), AutoButtonColor = true,
	}, parent)
	if width then
		b.Size = UDim2.new(width, -4, 1, 0)
	end
	make("UICorner", { CornerRadius = UDim.new(0, 5) }, b)
	b.Activated:Connect(callback)
	return b
end

local function row(parent: Instance): Frame
	local f = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 29), LayoutOrder = nextOrder() }, parent)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	return f
end

-- Runs `fn` as one undo step; reports its message, or the error.
local function undoable(name: string, fn: () -> (string, string?))
	local recording = ChangeHistoryService:TryBeginRecording(name)
	local ok, message, kind = pcall(fn)
	if recording then
		ChangeHistoryService:FinishRecording(recording, if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	end
	if ok then
		report(message, kind)
	else
		report("Error: " .. tostring(message), "bad")
	end
end

--------------------------------------------------------------------------
-- Zones
--------------------------------------------------------------------------

local function zonesFolder(): Instance?
	return Workspace:FindFirstChild(ZONES_FOLDER)
end

-- The Zone<N> model an instance is in.
local function zoneOf(instance: Instance?): (Model?, number?)
	local folder = zonesFolder()
	local node = instance
	while node and folder and node ~= folder and node ~= game do
		if node.Parent == folder then
			local n = Wiring.numberOf(node.Name)
			if n and node:IsA("Model") then
				return node, n
			end
			return nil, nil
		end
		node = node.Parent
	end
	return nil, nil
end

local function activeZone(): (Model?, number?)
	for _, instance in Selection:Get() do
		local zone, n = zoneOf(instance)
		if zone then
			return zone, n
		end
	end
	return nil, nil
end

-- Key models (KeyCapper) inside / among the given instances.
local function keysIn(roots: { Instance }): { Instance }
	local keys, seen = {}, {}
	local function add(model: Instance?)
		if model and not seen[model] then
			seen[model] = true
			table.insert(keys, model)
		end
	end
	local function visit(instance: Instance)
		if CollectionService:HasTag(instance, KEY_TAG) then
			add(instance)
		elseif CollectionService:HasTag(instance, HITBOX_TAG) then
			add(instance.Parent)
		end
	end
	for _, r in roots do
		visit(r)
		for _, d in r:GetDescendants() do
			visit(d)
		end
	end
	return keys
end

local function countTagged(zone: Instance, tag: string): number
	local n = 0
	for _, d in zone:GetDescendants() do
		if CollectionService:HasTag(d, tag) then
			n += 1
		end
	end
	return n
end

-- Keys anywhere that belong to zone `id` (World attribute or sitting in it).
local function keysFor(zone: Instance, id: string): number
	local n = 0
	for _, key in CollectionService:GetTagged(KEY_TAG) do
		local world = key:GetAttribute("World")
		if world == id or (world == nil and key:IsDescendantOf(zone)) then
			n += 1
		end
	end
	return n
end

--------------------------------------------------------------------------
-- Header
--------------------------------------------------------------------------

local head = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() }, body)
make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, head)
local brand = text(head, "MOSSWAKE · ZONE MANAGER", 16, C.text)
brand.Font = Enum.Font.GothamBold
text(head, "Lobby → Zone1 … ZoneN under workspace.Zones", 10, C.muted)

local footer = make("Frame", { BackgroundColor3 = C.input, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() }, body)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, footer)
make("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7) }, footer)
status = text(footer, "", 10, C.accent)

--------------------------------------------------------------------------
-- Wire
--------------------------------------------------------------------------

local wirePanel = section("Wire all zones",
	"Ids, zone boxes, a barrier on every DividerLine (price + BUY show on it in game), a spawn past each gate, the Lobby SpawnLocation, signs and EnemyGround. Press again after moving things; Undo reverts it.")
local wireLog = text(wirePanel, "", 10, C.muted)
local refreshZones: () -> ()

button(wirePanel, "Wire all zones", function()
	undoable("Wire zones", function()
		local result = Wiring.wire(Workspace)
		local lines = {}
		for _, problem in result.problems do
			table.insert(lines, `<font color="#DE6464">✗ {problem}</font>`)
		end
		for _, line in result.lines do
			table.insert(lines, "· " .. line)
		end
		wireLog.Text = table.concat(lines, "\n")
		refreshZones()
		if #result.problems > 0 then
			return `Wired, with {#result.problems} thing(s) to fix (see the list).`, "warn"
		end
		return "Wired every zone."
	end)
end, nil, true)

--------------------------------------------------------------------------
-- Zone list
--------------------------------------------------------------------------

local listPanel = section("Zones", "Click a zone to select it. Keys and enemy spawns are yours to place.")
button(listPanel, "Refresh", function()
	refreshZones()
end)
local list = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() }, listPanel)
make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, list)

refreshZones = function()
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	local folder = zonesFolder()
	if not folder then
		text(list, "No workspace.Zones folder.", 10, C.danger)
		return
	end
	local zones = {}
	for _, child in folder:GetChildren() do
		local n = Wiring.numberOf(child.Name)
		if n then table.insert(zones, { n = n, model = child }) end
	end
	table.sort(zones, function(a, b) return a.n < b.n end)
	for _, entry in zones do
		local model, n = entry.model, entry.n
		local id = Wiring.idOf(n)
		local keys = keysFor(model, id)
		local spawns = countTagged(model, "EnemySpawn")
		local wired = model:GetAttribute("ZoneId") == id and countTagged(model, "ZoneBarrier") > 0
		local surf = model:FindFirstChild("Stuff") and model.Stuff:FindFirstChild("Pit") and model.Stuff.Pit:FindFirstChild("Surf")
		local function mark(ok: boolean): string
			return if ok then `<font color="#84AE8B">✓</font>` else `<font color="#DEB868">○</font>`
		end
		local line = make("TextButton", {
			BackgroundColor3 = C.input, BorderSizePixel = 0, Font = Enum.Font.Code, RichText = true, TextSize = 11, TextColor3 = C.text,
			TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = n,
			Text = string.format("  %-7s %s wired  %s %d keys  %s %d spawns%s", "Zone" .. n, mark(wired), mark(keys > 0), keys,
				mark(spawns > 0), spawns, if surf then "" else "  <font color=\"#DE6464\">no Pit.Surf</font>"),
		}, list)
		make("UICorner", { CornerRadius = UDim.new(0, 4) }, line)
		line.Activated:Connect(function()
			Selection:Set({ model })
		end)
	end
end

--------------------------------------------------------------------------
-- Active zone
--------------------------------------------------------------------------

local zonePanel = section("Active zone", "The zone your selection is in.")
local activeLabel = text(zonePanel, "", 12, C.text)
activeLabel.Font = Enum.Font.GothamBold

local function needZone(): (Model?, number?)
	local zone, n = activeZone()
	if not zone then
		report("Select something inside a Zone<N> model first.", "bad")
	end
	return zone, n
end

local nav = row(zonePanel)
button(nav, "Select Pit.Surf", function()
	local zone = needZone()
	if not zone then return end
	local surf = zone:FindFirstChild("Stuff") and zone.Stuff:FindFirstChild("Pit") and zone.Stuff.Pit:FindFirstChild("Surf")
	if surf then
		Selection:Set({ surf })
		report("Selected Pit.Surf: brush the keyboard onto it with KeyCapper.")
	else
		report(zone.Name .. " has no Stuff.Pit.Surf.", "bad")
	end
end, 0.5)
button(nav, "Select gate", function()
	local zone = needZone()
	if not zone then return end
	local gate = zone:FindFirstChild("Gate")
	if gate then
		Selection:Set(gate:GetChildren())
		report("Selected the barrier and spawn. Run Wire again after moving the DividerLine.")
	else
		report(zone.Name .. " isn't wired yet: press Wire all zones.", "warn")
	end
end, 0.5)

button(zonePanel, "Assign selected keys to this zone", function()
	local zone, n = needZone()
	if not zone or not n then return end
	local keys = keysIn(Selection:Get())
	if #keys == 0 then
		report("Select KeyCapper keys (or a folder of them) inside the zone.", "bad")
		return
	end
	undoable("Assign keys", function()
		local id = Wiring.idOf(n)
		for _, key in keys do
			key:SetAttribute("World", id)
		end
		refreshZones()
		return `{#keys} key(s) now pay in {zone.Name} ({id}).`
	end)
end)

button(zonePanel, "Mark selected parts as EnemyGround", function()
	local parts = {}
	for _, v in Selection:Get() do
		if v:IsA("BasePart") then table.insert(parts, v) end
	end
	if #parts == 0 then
		report("Select the parts enemies may walk on (blobs, ramps).", "bad")
		return
	end
	undoable("Tag EnemyGround", function()
		for _, p in parts do
			CollectionService:AddTag(p, "EnemyGround")
		end
		return `Tagged {#parts} part(s) EnemyGround.`
	end)
end)

-- Enemy spawn scatter
text(zonePanel, "<b>Enemy spawns</b>: markers on Ground and EnemyGround in this zone, away from the pit, gate and props.", 10, C.muted)
local countBox = box(zonePanel, "How many", "16")
local spacingBox = box(zonePanel, "Minimum spacing (studs)", "10")
local insetBox = box(zonePanel, "Edge inset (studs)", "6")

local function numberFrom(b: TextBox): number?
	local n = tonumber(b.Text)
	return if n and n == n and n >= 0 and n < math.huge then n else nil
end

local function scatter(zone: Model, n: number): (string, string?)
	local count, spacing, inset = numberFrom(countBox), numberFrom(spacingBox), numberFrom(insetBox)
	if not count or count < 1 or count > 200 or count % 1 ~= 0 then return "How many: a whole number from 1 to 200.", "bad" end
	if not spacing or not inset then return "Spacing and inset must be numbers.", "bad" end

	local surfaces: { BasePart } = {}
	local isSurface: { [Instance]: boolean } = {}
	for _, d in zone:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Ground" and d.Parent == zone or CollectionService:HasTag(d, "EnemyGround")) then
			table.insert(surfaces, d)
			isSurface[d] = true
		end
	end
	if #surfaces == 0 then return zone.Name .. " has no Ground or EnemyGround parts.", "bad" end

	local folder = zone:FindFirstChild("EnemySpawns")
	local existing: { Vector3 } = {}
	if folder then
		for _, d in folder:GetChildren() do
			if d:IsA("BasePart") then table.insert(existing, d.Position) end
		end
	end
	local gate = zone:FindFirstChild("Gate")
	local barrier = gate and gate:FindFirstChild("Barrier")
	local pit = zone:FindFirstChild("Stuff") and zone.Stuff:FindFirstChild("Pit")

	-- Ray down from above: the first collidable thing hit must be a surface,
	-- so spots under trees, rocks, the pit and the keyboard are skipped.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if folder then { folder } else {}
	params.RespectCanCollide = true
	params.IgnoreWater = true

	local function nearPit(p: Vector3): boolean
		if not pit then return false end
		for _, d in pit:GetDescendants() do
			if d:IsA("BasePart") then
				local offset = d.CFrame:PointToObjectSpace(p)
				local half = d.Size / 2 + Vector3.new(4, 0, 4)
				if math.abs(offset.X) <= half.X and math.abs(offset.Z) <= half.Z then return true end
			end
		end
		return false
	end

	local rng = Random.new()
	local made: { Vector3 } = {}
	for _ = 1, count * 60 do
		if #made >= count then break end
		local s = surfaces[rng:NextInteger(1, #surfaces)]
		local hx, hz = s.Size.X / 2 - inset, s.Size.Z / 2 - inset
		if hx <= 0 or hz <= 0 then continue end
		local sample = s.CFrame:PointToWorldSpace(Vector3.new(rng:NextNumber(-hx, hx), s.Size.Y / 2, rng:NextNumber(-hz, hz)))
		local hit = Workspace:Raycast(sample + Vector3.new(0, 60, 0), Vector3.new(0, -120, 0), params)
		if not (hit and isSurface[hit.Instance]) then continue end
		local pos = hit.Position
		if nearPit(pos) then continue end
		-- Not right by the gate, where players walk in.
		if barrier and math.abs(barrier.CFrame:PointToObjectSpace(pos).Z) < 14 then continue end
		local clear = true
		for _, list in { existing, made } do
			for _, other in list do
				if (Vector3.new(pos.X - other.X, 0, pos.Z - other.Z)).Magnitude < spacing then
					clear = false
					break
				end
			end
			if not clear then break end
		end
		if clear then table.insert(made, pos) end
	end
	if #made == 0 then return "No clear spots found: lower the spacing or inset.", "bad" end

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "EnemySpawns"
		folder.Parent = zone
	end
	local id = Wiring.idOf(n)
	local base = #existing
	for i, pos in made do
		local marker = Instance.new("Part")
		marker.Name = string.format("EnemySpawn_%03d", base + i)
		marker.Size = Vector3.new(1, 0.2, 1)
		marker.CFrame = CFrame.new(pos + Vector3.new(0, 0.1, 0))
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanTouch = false
		marker.CanQuery = false
		marker.Transparency = 1
		marker.CastShadow = false
		marker:SetAttribute("ZoneId", id)
		CollectionService:AddTag(marker, "EnemySpawn")
		marker.Parent = folder
	end
	local kind = if #made < count then "warn" else nil
	return `Added {#made} of {count} EnemySpawn markers to {zone.Name}.`, kind
end

local spawnRow = row(zonePanel)
button(spawnRow, "Scatter EnemySpawns", function()
	local zone, n = needZone()
	if not zone or not n then return end
	undoable("Scatter EnemySpawns", function()
		local message, kind = scatter(zone, n)
		refreshZones()
		return message, kind
	end)
end, 0.5)
button(spawnRow, "Clear EnemySpawns", function()
	local zone = needZone()
	if not zone then return end
	undoable("Clear EnemySpawns", function()
		local removed = 0
		for _, d in zone:GetDescendants() do
			if d:IsA("BasePart") and CollectionService:HasTag(d, "EnemySpawn") then
				d:Destroy()
				removed += 1
			end
		end
		refreshZones()
		return `Removed {removed} EnemySpawn marker(s).`
	end)
end, 0.5)

--------------------------------------------------------------------------
-- Tags and attributes (any instance)
--------------------------------------------------------------------------

local tagPanel = section("Tags", "Add or remove a tag on the selection (and, optionally, everything inside it).")
local tagBox = box(tagPanel, "Tag name (e.g. EnemyGround)")
local includeDescendants = false
local scopeButton: TextButton
scopeButton = button(tagPanel, "Scope: selection only", function()
	includeDescendants = not includeDescendants
	scopeButton.Text = if includeDescendants then "Scope: selection + descendants" else "Scope: selection only"
end)
local function targets(): { Instance }
	local out, seen = {}, {}
	for _, v in Selection:Get() do
		if not seen[v] then seen[v] = true; table.insert(out, v) end
		if includeDescendants then
			for _, d in v:GetDescendants() do
				if not seen[d] then seen[d] = true; table.insert(out, d) end
			end
		end
	end
	return out
end
local tagRow = row(tagPanel)
button(tagRow, "Add tag", function()
	local name, list = tagBox.Text, targets()
	if name == "" or #list == 0 then report("Enter a tag and select instances.", "bad") return end
	undoable("Add tag", function()
		local n = 0
		for _, v in list do
			if not CollectionService:HasTag(v, name) then CollectionService:AddTag(v, name); n += 1 end
		end
		return `Added '{name}' to {n} instance(s).`
	end)
end, 0.5)
button(tagRow, "Remove tag", function()
	local name, list = tagBox.Text, targets()
	if name == "" or #list == 0 then report("Enter a tag and select instances.", "bad") return end
	undoable("Remove tag", function()
		local n = 0
		for _, v in list do
			if CollectionService:HasTag(v, name) then CollectionService:RemoveTag(v, name); n += 1 end
		end
		return `Removed '{name}' from {n} instance(s).`
	end)
end, 0.5)

local attrPanel = section("Attributes", "Vector3 / Color3: x, y, z (Color3 as 0-1 or 0-255).")
local attrName = box(attrPanel, "Attribute name (e.g. Subtitle)")
local attrValue = box(attrPanel, "Value")
local attrType = "string"
local typeRow = row(attrPanel)
local typeButtons: { [string]: TextButton } = {}
local function pickType(kind: string)
	attrType = kind
	for k, b in typeButtons do
		b.BackgroundColor3 = if k == kind then C.border else C.input
	end
end
for _, kind in { "string", "number", "boolean", "Vector3", "Color3" } do
	local b = button(typeRow, kind, function() pickType(kind) end, 0.2)
	b.TextSize = 9
	typeButtons[kind] = b
end
pickType("string")
local function parseValue(): (boolean, any)
	local raw = attrValue.Text
	if attrType == "string" then return true, raw end
	if attrType == "number" then local n = tonumber(raw); return n ~= nil, n end
	if attrType == "boolean" then
		if raw:lower() == "true" then return true, true elseif raw:lower() == "false" then return true, false end
		return false, nil
	end
	local a, b, c = string.match(raw, "^%s*([%+%-%.%d]+)%s*,%s*([%+%-%.%d]+)%s*,%s*([%+%-%.%d]+)%s*$")
	local x, y, z = tonumber(a), tonumber(b), tonumber(c)
	if not x or not y or not z then return false, nil end
	if attrType == "Vector3" then return true, Vector3.new(x, y, z) end
	if x > 1 or y > 1 or z > 1 then
		return true, Color3.fromRGB(math.clamp(math.round(x), 0, 255), math.clamp(math.round(y), 0, 255), math.clamp(math.round(z), 0, 255))
	end
	return true, Color3.new(x, y, z)
end
local attrRow = row(attrPanel)
button(attrRow, "Set", function()
	local name, list = attrName.Text, Selection:Get()
	local ok, value = parseValue()
	if name == "" or #list == 0 or not ok then report("Check the name, the selection and the value.", "bad") return end
	undoable("Set attribute", function()
		for _, v in list do v:SetAttribute(name, value) end
		return `Set '{name}' on {#list} instance(s).`
	end)
end, 0.5)
button(attrRow, "Remove", function()
	local name, list = attrName.Text, Selection:Get()
	if name == "" or #list == 0 then report("Enter a name and select instances.", "bad") return end
	undoable("Remove attribute", function()
		local n = 0
		for _, v in list do
			if v:GetAttribute(name) ~= nil then v:SetAttribute(name, nil); n += 1 end
		end
		return `Removed '{name}' from {n} instance(s).`
	end)
end, 0.5)

-- Keep the status footer last.
footer.LayoutOrder = nextOrder()

--------------------------------------------------------------------------
-- Live
--------------------------------------------------------------------------

local function refreshActive()
	local zone, n = activeZone()
	if zone and n then
		activeLabel.Text = `{zone.Name}  ·  id {Wiring.idOf(n)}`
		activeLabel.TextColor3 = C.text
	else
		activeLabel.Text = "Nothing selected in a zone"
		activeLabel.TextColor3 = C.muted
	end
end
Selection.SelectionChanged:Connect(refreshActive)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	if widget.Enabled then
		refreshZones()
		refreshActive()
	end
end)
refreshActive()
refreshZones()
report("Ready. Press Wire all zones after building or moving zones.")
