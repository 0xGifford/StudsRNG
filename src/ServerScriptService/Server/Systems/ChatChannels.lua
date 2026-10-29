--[[

ChatChannels
ModuleScript
/ServerScriptService/Server/Systems/ChatChannels

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The "Rolls" chat channel (Config.Announce.Channel): a TextChannel every
-- player joins, shown as its own chat tab. Clients post roll announcements
-- into it (RollReveal); players can't type in it (CanSend = false).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local ChatChannels = {}

local channel: TextChannel? = nil

local function join(player: Player)
	local current = channel
	if not current then return end
	local ok, source = pcall(current.AddUserAsync, current, player.UserId)
	if ok and source then
		(source :: TextSource).CanSend = false
	end
end

function ChatChannels.start()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		warn("[ChatChannels] TextChatService chat is off; the Rolls channel needs it")
		return
	end
	local channels = TextChatService:WaitForChild("TextChannels", 10)
	if not channels then return end

	local existing = channels:FindFirstChild(Config.Announce.Channel)
	if existing and existing:IsA("TextChannel") then
		channel = existing
	else
		local created = Instance.new("TextChannel")
		created.Name = Config.Announce.Channel
		created.Parent = channels
		channel = created
	end

	-- Chat tabs, so the channel shows next to General.
	local tabs = TextChatService:FindFirstChildOfClass("ChannelTabsConfiguration")
	if tabs then
		tabs.Enabled = true
	end

	Players.PlayerAdded:Connect(join)
	for _, player in Players:GetPlayers() do
		task.spawn(join, player)
	end
end

return ChatChannels
