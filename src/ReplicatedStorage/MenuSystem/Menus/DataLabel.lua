--!nonstrict
--[[
	ReplicatedStorage/MenuSystem/Menus/DataLabel

	Binds any TextLabel to any value in the player's profile. Set one attribute
	and the label stays live — no script per label.

		ClacksLabel (TextLabel)    DataPath = "Clacks"

	Works for any field the game syncs to the client (MenuSystem/Data reads
	the client State), not just currency:

		DataPath = "FreeRolls"
		DataPath = "Rebirths"
		DataPath = "Stats.Luck"
		DataPath = "EnemiesDefeated"

	ATTRIBUTES — the formatting ones inherit up the ancestor chain, so set them
	once on a HUD frame and every label inside picks them up.
		DataPath        string   required; this is the marker
		DataFormat      string   string.format pattern, default "%s"
		                         e.g. "%s Coins", "Lv. %s", "x%s"
		DataAbbreviate  boolean  1,250 -> 1.2K, 2,400,000 -> 2.4M
		DataSeparator   string   thousands separator, default ","
		DataDefault     any      shown before the profile arrives, default 0
		DataTween       number   seconds to count up to a new value, 0 = instant
		DataPop         boolean  brief scale pop when the value rises

	Owned attributes are written back so other UI can react without reading
	the profile itself:
		DataValue       the raw current value

	API
		DataLabel.Start()
		DataLabel.Format(value, host) -> string
		DataLabel.Rescan(root)
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ClientData = require(script.Parent.Parent.Data) -- the game's state (MenuSystem/Data)

local DataLabel = {}

local entries: { [Instance]: any } = {}
local started = false

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

-- ---------------------------------------------------------------- helpers

local function inherit(instance: Instance, attribute: string, default: any): any
	local node: Instance? = instance
	while node do
		local value = node:GetAttribute(attribute)
		if value ~= nil then
			return value
		end
		node = node.Parent
	end
	return default
end

local function separate(whole: number, separator: string): string
	local digits = tostring(math.floor(math.abs(whole)))
	if separator == "" then
		return digits
	end
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1" .. separator):reverse()
	grouped = grouped:gsub("^" .. separator:gsub("%p", "%%%0"), "")
	return grouped
end

local function abbreviate(value: number): string
	local absolute = math.abs(value)
	if absolute < 1000 then
		return tostring(math.floor(value))
	end
	local tier = math.clamp(math.floor(math.log(absolute, 1000)), 0, #SUFFIXES - 1)
	local scaled = value / (1000 ^ tier)
	local text = string.format("%.1f", scaled):gsub("%.0$", "")
	return text .. SUFFIXES[tier + 1]
end

--- Formats a value the way this label is configured to show it.
function DataLabel.Format(value: any, host: Instance): string
	local body
	if type(value) == "number" then
		if inherit(host, "DataAbbreviate", false) == true then
			body = abbreviate(value)
		else
			local sign = value < 0 and "-" or ""
			body = sign .. separate(value, inherit(host, "DataSeparator", ","))
		end
	elseif type(value) == "boolean" then
		body = value and "Yes" or "No"
	elseif value == nil then
		body = ""
	else
		body = tostring(value)
	end

	local pattern = inherit(host, "DataFormat", "%s")
	local ok, text = pcall(string.format, pattern, body)
	return ok and text or body
end

local function setText(host: Instance, text: string)
	if host:IsA("TextLabel") or host:IsA("TextButton") or host:IsA("TextBox") then
		host.Text = text
	end
end

-- ---------------------------------------------------------------- rendering

local function pop(host: Instance)
	if not host:IsA("GuiObject") then
		return
	end
	local scale = host:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = host
	end
	scale.Scale = 1.15
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

local function render(entry: any, value: any, previous: any)
	local host = entry.host
	host:SetAttribute("DataValue", value)

	local duration = inherit(host, "DataTween", 0)

	-- Count up only between two numbers; anything else snaps.
	if type(value) == "number" and type(previous) == "number" and duration > 0 and value ~= previous then
		if entry.counter then
			entry.counter:Destroy()
		end

		local counter = Instance.new("NumberValue")
		counter.Value = entry.shown or previous
		entry.counter = counter

		counter.Changed:Connect(function(current)
			entry.shown = current
			setText(host, DataLabel.Format(math.floor(current + 0.5), host))
		end)

		local tween = TweenService:Create(
			counter,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Value = value }
		)
		tween.Completed:Once(function()
			if entry.counter == counter then
				setText(host, DataLabel.Format(value, host))
				entry.shown = value
				counter:Destroy()
				entry.counter = nil
			end
		end)
		tween:Play()
	else
		entry.shown = value
		setText(host, DataLabel.Format(value, host))
	end

	if
		type(value) == "number"
		and type(previous) == "number"
		and value > previous
		and inherit(host, "DataPop", false) == true
	then
		pop(host)
	end
end

-- ---------------------------------------------------------------- binding

function DataLabel.Unbind(host: Instance)
	local entry = entries[host]
	if not entry then
		return
	end
	if entry.disconnect then
		entry.disconnect()
	end
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	if entry.counter then
		entry.counter:Destroy()
	end
	entries[host] = nil
end

function DataLabel.Bind(host: Instance)
	if entries[host] then
		return
	end
	local path = host:GetAttribute("DataPath")
	if type(path) ~= "string" or path == "" then
		return
	end

	local entry = {
		host = host,
		path = path,
		shown = nil,
		counter = nil,
		connections = {},
		disconnect = nil,
	}
	entries[host] = entry

	-- Placeholder until the profile lands, so a HUD never flashes an empty label.
	if not ClientData.IsReady() then
		setText(host, DataLabel.Format(host:GetAttribute("DataDefault") or 0, host))
	end

	local first = true
	entry.disconnect = ClientData.Observe(path, function(value, previous)
		-- The first call is the current value, not a change, so it must not
		-- count up from zero or pop.
		if first then
			first = false
			entry.shown = value
			host:SetAttribute("DataValue", value)
			setText(host, DataLabel.Format(value, host))
			return
		end
		render(entry, value, previous)
	end)

	-- Repointing the label rebinds it; a format change just redraws.
	table.insert(
		entry.connections,
		host.AttributeChanged:Connect(function(attribute)
			if attribute == "DataPath" then
				DataLabel.Unbind(host)
				DataLabel.Bind(host)
			elseif
				attribute == "DataFormat"
				or attribute == "DataAbbreviate"
				or attribute == "DataSeparator"
			then
				setText(host, DataLabel.Format(entry.shown, host))
			end
		end)
	)
end

function DataLabel.Rescan(root: Instance?)
	local scope: Instance = root or Players.LocalPlayer:WaitForChild("PlayerGui")
	if scope:GetAttribute("DataPath") ~= nil then
		DataLabel.Bind(scope)
	end
	for _, descendant in scope:GetDescendants() do
		if descendant:GetAttribute("DataPath") ~= nil then
			DataLabel.Bind(descendant)
		end
	end
end

function DataLabel.Count(): number
	local count = 0
	for _ in entries do
		count += 1
	end
	return count
end

function DataLabel.Start()
	if started then
		return
	end
	started = true

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	DataLabel.Rescan(playerGui)

	playerGui.DescendantAdded:Connect(function(descendant)
		if descendant:GetAttribute("DataPath") ~= nil then
			task.defer(DataLabel.Bind, descendant)
		end
	end)

	playerGui.DescendantRemoving:Connect(function(descendant)
		DataLabel.Unbind(descendant)
	end)
end

return DataLabel
