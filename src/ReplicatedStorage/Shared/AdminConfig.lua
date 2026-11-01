--!nonstrict
--[[

AdminConfig
ModuleScript
/ReplicatedStorage/Shared/AdminConfig

Copyright © 2026. Mosswake, all rights reserved.

	The admin panel, as data. MenuSystem's AdminPanel (client) builds the UI
	from it; Systems/Admin (server) checks every request against the same
	definitions, so a field added here is validated automatically.

	TABS = { { Id, Text, Categories = { ... } } , ... }   (Log = true: the action log)
	A CATEGORY  { Text, Fields = { ... }, Actions = { ... } }
	A FIELD     { Id, Type, Text, Default, ... }
	  Number    Min, Max, Optional (blank allowed)
	  Text      MaxLength, Placeholder, Multiline, Required
	  Checkbox  Default true/false
	  Select    Options = { ... }
	AN ACTION   { Id, Text, Type = "Button" | "Switch", Confirm, Danger, Target, Permission }
	  Target    "Selected" (default: every selected player) · "None" (server-wide)
	            · "SelectedOrUserId" (a UserId field wins, else the selection;
	              a UserId of someone not in this server is edited through
	              their save, applied the next time it opens)
	  Permission  the Config.Admin permission it needs (Systems/Admin checks it;
	              an Everywhere = true request also needs "Global")
	  The action's fields are the ones in its own category. The server needs a
	  matching entry in Systems/Admin's ACTIONS — that's the only code to write.
]]

local Config = require(script.Parent.Config)

local AdminConfig = {}

-- Ban lengths, in minutes (0 = forever).
AdminConfig.BAN_MINUTES = {
	["15 minutes"] = 15, ["1 hour"] = 60, ["1 day"] = 24 * 60, ["7 days"] = 7 * 24 * 60,
	["30 days"] = 30 * 24 * 60, ["Permanent"] = 0,
}

-- Currency select option -> save field.
AdminConfig.CURRENCIES = {
	["Clacks"] = "Clacks",
	["Free Rolls"] = "FreeRolls",
	["Jackpot Spins"] = "Spins",
	["Lucky Rolls"] = "LuckyRolls",
}

local eventNames, eventIds = {}, {}
for _, event in Config.Events.List do
	table.insert(eventNames, event.Name)
	eventIds[event.Name] = event.Id
end
AdminConfig.EVENT_IDS = eventIds -- event name -> id

local boostNames = {}
for _, id in Config.BoostOrder do
	if Config.Boosts[id] then
		table.insert(boostNames, id)
	end
end

local USER_ID = { Id = "UserId", Type = "Number", Text = "Or a UserId (offline too)", Min = 1, Max = 1e13, Optional = true }

AdminConfig.TABS = {
	{
		Id = "Players", Text = "Players",
		Categories = {
			{
				Text = "Currency",
				Fields = {
					{ Id = "Kind", Type = "Select", Text = "Currency", Options = { "Clacks", "Free Rolls", "Jackpot Spins", "Lucky Rolls" }, Default = "Clacks" },
					{ Id = "Amount", Type = "Number", Text = "Amount", Min = 0, Max = 1e15, Default = 1000 },
					{ Id = "Mode", Type = "Select", Text = "Give or set", Options = { "Give", "Set" }, Default = "Give" },
					{ Id = "Notify", Type = "Checkbox", Text = "Tell the player", Default = true },
					USER_ID,
				},
				Actions = { { Id = "Currency", Text = "Apply", Target = "SelectedOrUserId", Permission = "EditPlayers" } },
			},
			{
				Text = "Progress",
				Fields = {
					{ Id = "Rebirths", Type = "Number", Text = "Rebirths", Min = 0, Max = 1e6, Optional = true },
					{ Id = "Zones", Type = "Number", Text = "Zones owned", Min = 1, Max = 1000, Optional = true },
					USER_ID,
				},
				Actions = { { Id = "Progress", Text = "Set", Target = "SelectedOrUserId", Permission = "EditPlayers" } },
			},
			{
				Text = "Studs",
				Fields = {
					{ Id = "Stud", Type = "Text", Text = "Stud", Placeholder = "Id:Variant, e.g. Nebula:Shiny", MaxLength = 60, Required = true },
					{ Id = "Count", Type = "Number", Text = "How many", Min = 1, Max = 100, Default = 1 },
					USER_ID,
				},
				Actions = { { Id = "GiveStud", Text = "Give", Target = "SelectedOrUserId", Permission = "EditPlayers" } },
			},
			{
				Text = "Boosts",
				Fields = {
					{ Id = "Boost", Type = "Select", Text = "Boost", Options = boostNames, Default = boostNames[1] },
					{ Id = "Minutes", Type = "Number", Text = "Minutes", Min = 1, Max = 24 * 60, Default = 15 },
					USER_ID,
				},
				Actions = { { Id = "GiveBoost", Text = "Give", Target = "SelectedOrUserId", Permission = "EditPlayers" } },
			},
			{
				Text = "Reset",
				Fields = { USER_ID },
				Actions = { { Id = "ResetPlayer", Text = "Reset progress", Target = "SelectedOrUserId", Confirm = true, Danger = true, Permission = "ResetPlayers" } },
			},
		},
	},
	{
		Id = "Moderation", Text = "Moderation",
		Categories = {
			{
				Text = "Kick",
				Fields = { { Id = "Reason", Type = "Text", Text = "Reason", Placeholder = "Shown to the player", MaxLength = 200 } },
				Actions = { { Id = "Kick", Text = "Kick", Confirm = true, Danger = true, Permission = "Kick" } },
			},
			{
				Text = "Ban",
				Fields = {
					{ Id = "Duration", Type = "Select", Text = "Length", Options = { "15 minutes", "1 hour", "1 day", "7 days", "30 days", "Permanent" }, Default = "1 day" },
					{ Id = "Reason", Type = "Text", Text = "Reason", Placeholder = "Shown to the player", MaxLength = 200 },
					{ Id = "UserId", Type = "Number", Text = "Or a UserId", Min = 1, Max = 1e13, Optional = true },
				},
				Actions = {
					{ Id = "Ban", Text = "Ban", Confirm = true, Danger = true, Target = "SelectedOrUserId", Permission = "TempBan" },
					{ Id = "Unban", Text = "Unban", Confirm = true, Target = "SelectedOrUserId", Permission = "Unban" },
				},
			},
		},
	},
	{
		Id = "Events", Text = "Events",
		Categories = {
			{
				Text = "Run an event",
				Fields = {
					{ Id = "Event", Type = "Select", Text = "Event", Options = eventNames, Default = eventNames[1] },
					{ Id = "Minutes", Type = "Number", Text = "Minutes", Min = 1, Max = 24 * 60, Default = math.floor(Config.Events.AdminDuration / 60) },
					{ Id = "Everywhere", Type = "Checkbox", Text = "Every server", Default = false },
				},
				Actions = { { Id = "RunEvent", Text = "Start", Target = "None", Confirm = true, Permission = "Events" } },
			},
			{
				Text = "Stop the event",
				Fields = { { Id = "Everywhere", Type = "Checkbox", Text = "Every server", Default = false } },
				Actions = { { Id = "StopEvent", Text = "Stop", Target = "None", Confirm = true, Permission = "Events" } },
			},
		},
	},
	{
		Id = "Server", Text = "Server",
		Categories = {
			{
				Text = "Announcement",
				Fields = {
					{ Id = "Message", Type = "Text", Text = "Message", Placeholder = "Everyone will see this", MaxLength = 200, Multiline = true, Required = true },
					{ Id = "Everywhere", Type = "Checkbox", Text = "Every server", Default = false },
				},
				Actions = { { Id = "Announce", Text = "Send", Target = "None", Confirm = true, Permission = "Announce" } },
			},
			{
				Text = "Reset everyone's currencies",
				Fields = { { Id = "Confirm", Type = "Text", Text = "Type RESET", Placeholder = "RESET", MaxLength = 10, Required = true } },
				Actions = { { Id = "ResetEconomy", Text = "Reset economy", Target = "None", Confirm = true, Danger = true, Permission = "ResetEconomy" } },
			},
			{
				Text = "Reset everyone's progress",
				Fields = { { Id = "Confirm", Type = "Text", Text = "Type RESET", Placeholder = "RESET", MaxLength = 10, Required = true } },
				Actions = { { Id = "ResetAll", Text = "Reset everything", Target = "None", Confirm = true, Danger = true, Permission = "ResetAll" } },
			},
		},
	},
	{ Id = "Log", Text = "Log", Log = true },
}

-- ================================================================ lookups

local actions, fieldsOf = {}, {}
for _, tab in AdminConfig.TABS do
	for _, category in tab.Categories or {} do
		for _, action in category.Actions or {} do
			actions[action.Id] = action
			fieldsOf[action.Id] = category.Fields or {}
		end
	end
end

--- The action definition and its category's fields.
function AdminConfig.Action(id: string)
	return actions[id], fieldsOf[id] or {}
end

--- Cleans an action's arguments against its fields: numbers clamped to whole
--- numbers in range, text trimmed and capped, selects limited to their
--- options. Returns (args, nil) or (nil, reason).
function AdminConfig.Clean(id: string, args)
	local action, fields = AdminConfig.Action(id)
	if not action then
		return nil, "Unknown action: " .. tostring(id)
	end
	args = type(args) == "table" and args or {}
	local out = {}
	for _, f in fields do
		local v = args[f.Id]
		if f.Type == "Number" then
			v = tonumber(v)
			if v == nil or v ~= v then
				v = nil
				if not f.Optional then
					return nil, ("%s needs a number"):format(f.Text or f.Id)
				end
			else
				v = math.floor(v)
				if (f.Min and v < f.Min) or (f.Max and v > f.Max) then
					return nil, ("%s must be between %s and %s"):format(f.Text or f.Id, tostring(f.Min or "-"), tostring(f.Max or "-"))
				end
			end
		elseif f.Type == "Text" then
			v = type(v) == "string" and (v:gsub("^%s+", ""):gsub("%s+$", "")) or ""
			v = v:sub(1, f.MaxLength or 200)
			if f.Required and v == "" then
				return nil, ("%s is empty"):format(f.Text or f.Id)
			end
		elseif f.Type == "Checkbox" then
			v = v == true
		elseif f.Type == "Select" then
			if not (f.Options and table.find(f.Options, v)) then
				v = f.Default or (f.Options and f.Options[1])
			end
		end
		out[f.Id] = v
	end
	if action.Type == "Switch" then
		out.Value = args.Value == true
	end
	return out, nil
end

return AdminConfig
