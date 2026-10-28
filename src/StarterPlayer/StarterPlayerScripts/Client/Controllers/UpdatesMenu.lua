--[[

UpdatesMenu
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/UpdatesMenu

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The update log (Updates window, opened from its TopbarPlus icon), built
-- from Shared/UpdateLog. Opening it marks the newest version as read.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UpdateLog = require(Shared.UpdateLog)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Kit = require(UI.Kit)

local UpdatesMenu = {}

local MENU = "Updates"

local items: ScrollingFrame

local function rebuild()
	Kit.list(items)
	local order = 0
	for _, entry in UpdateLog.Entries do
		order += 1
		Kit.header(items, `v{entry.Version} · {entry.Title}`, order)
		local lines = { `<i>{entry.Date}</i>` }
		for _, note in entry.Notes do
			table.insert(lines, `• {note}`)
		end
		order += 1
		Kit.paragraph(items, table.concat(lines, "\n"), order)
	end
end

function UpdatesMenu.hasUnread(): boolean
	return State.isReady() and State.get("SeenUpdate") ~= UpdateLog.Latest
end

function UpdatesMenu.start()
	Interface.setup()
	local window = Interface.Canva:WaitForChild(MENU)
	items = window:WaitForChild("Main"):WaitForChild("Items") :: ScrollingFrame

	Interface.MenuOpened:Connect(function(name)
		if name ~= MENU then return end
		rebuild()
		if UpdatesMenu.hasUnread() then
			task.spawn(State.markUpdateSeen)
		end
	end)
end

return UpdatesMenu
