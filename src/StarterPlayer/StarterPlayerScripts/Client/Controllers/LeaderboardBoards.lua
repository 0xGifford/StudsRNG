--[[

LeaderboardBoards
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/LeaderboardBoards

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Draws the global top lists (Systems/Leaderboards) on every part tagged
-- Leaderboard (Shared/Tags): Board = Clacks | Enemies | Rarest, Face = the
-- side to draw on. Top 10 with medals, your row in green, and your rank
-- underneath when you're further down.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Tags = require(Shared.Tags)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local Format = require(UI.Format)
local Roles = require(UI.Roles)

local LeaderboardBoards = {}
local ROWS = 10
local MEDALS = { "🥇", "🥈", "🥉" }
local TITLES = {
	Clacks = { "🏆 TOP CLACKS", Color3.fromRGB(255, 205, 60) },
	Enemies = { "⚔️ MOST ENEMIES DEFEATED", Color3.fromRGB(255, 110, 90) },
	Rarest = { "🎲 RAREST ROLLS", Color3.fromRGB(190, 120, 255) },
}

local player = Players.LocalPlayer

type Entry = { Rank: number, Name: string, UserId: number, Value: number }
type Board = { gui: SurfaceGui, part: BasePart, rows: { TextLabel }, values: { TextLabel }, footer: TextLabel, connections: { RBXScriptConnection } }

local boards: { [Instance]: Board } = {}
local latest: { [string]: { Entry } } = {}

local function boardId(part: Instance): string
	local id = Tags.read(part, Tags.Attr.Board, "Clacks")
	return if TITLES[id] then id else "Clacks"
end

local function formatValue(id: string, value: number): string
	if id == "Rarest" then
		return Format.oneIn(value)
	end
	return Format.number(value)
end

local function render(board: Board, id: string)
	local entries: { Entry } = latest[id] or {}
	local mine: Entry? = nil
	for _, entry in entries do
		if entry.UserId == player.UserId then
			mine = entry
		end
	end
	for i = 1, ROWS do
		local entry = entries[i]
		local row, value = board.rows[i], board.values[i]
		if entry then
			row.Text = `{MEDALS[i] or `#{i}`}  {entry.Name}`
			value.Text = formatValue(id, entry.Value)
			local isMe = entry.UserId == player.UserId
			row.TextColor3 = if isMe then Color3.fromRGB(120, 255, 140) elseif i <= 3 then Color3.fromRGB(255, 230, 150) else Color3.new(1, 1, 1)
			value.TextColor3 = row.TextColor3
		else
			row.Text = if i == 1 and #entries == 0 then "Loading..." else ""
			value.Text = ""
		end
	end
	board.footer.Text = if mine and mine.Rank > ROWS
		then `You: #{mine.Rank} · {formatValue(id, mine.Value)}`
		elseif mine then "You're on the board!"
		else "Keep playing to get ranked!"
end

local function build(part: BasePart): Board
	local id = boardId(part)
	local title = TITLES[id]
	local faceName = Tags.read(part, Tags.Attr.Face, "Front")
	local ok, face = pcall(function()
		return (Enum.NormalId :: any)[faceName]
	end)

	-- A copy of StarterGui.WorldUI's LeaderboardBoard (BoardRole: Title,
	-- Row / Value with BoardRow, Footer).
	local gui = Roles.template(Roles.gui("WorldUI"), "LeaderboardBoard") :: SurfaceGui
	gui.Name = "Leaderboard"
	gui.Adornee = part
	gui.Face = if ok and face then face else Enum.NormalId.Front
	local heading = Roles.find(gui, "BoardRole", "Title")
	if heading then
		heading.Text = title[1]
		heading.TextColor3 = title[2]
	end
	local rows, values = {}, {}
	for _, d in gui:GetDescendants() do
		local index = d:GetAttribute("BoardRow")
		if typeof(index) == "number" then
			if d:GetAttribute("BoardRole") == "Row" then
				rows[index] = d
			elseif d:GetAttribute("BoardRole") == "Value" then
				values[index] = d
			end
		end
	end
	local footer = Roles.get(gui, "BoardRole", "Footer")

	gui.Parent = player:WaitForChild("PlayerGui")
	return { gui = gui, part = part, rows = rows, values = values, footer = footer, connections = {} }
end

local function untrack(instance: Instance)
	local board = boards[instance]
	if not board then return end
	boards[instance] = nil
	for _, connection in board.connections do
		connection:Disconnect()
	end
	board.gui:Destroy()
end

local function track(instance: Instance)
	if not instance:IsA("BasePart") or boards[instance] then return end
	local board = build(instance)
	boards[instance] = board
	-- Board / Face are live: rebuild on change.
	table.insert(board.connections, instance.AttributeChanged:Connect(function()
		untrack(instance)
		track(instance)
	end))
	render(board, boardId(instance))
end

function LeaderboardBoards.start()
	Net.on("Leaderboards", function(payload)
		if typeof(payload) ~= "table" then return end
		latest = payload
		for part, board in boards do
			render(board, boardId(part))
		end
	end)
	for _, part in CollectionService:GetTagged(Tags.Leaderboard) do
		track(part)
	end
	CollectionService:GetInstanceAddedSignal(Tags.Leaderboard):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Tags.Leaderboard):Connect(untrack)
end

return LeaderboardBoards
