--[[

ChatTags
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/ChatTags

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Chat tags: [VIP] (the server sets the "VIP" player attribute from the VIP
-- game pass) and the player's worn achievement title ("Title" / "TitleColor"
-- attributes, Systems/Achievements). Every client prefixes that player's
-- messages. Works with TextChatService (the default chat).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local Format = require(UI.Format)

local ChatTags = {}

function ChatTags.start()
	local tag = `<font color="{Format.hex(Config.VIP.TagColor)}"><b>{Config.VIP.TagText}</b></font>`

	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local properties = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		if source then
			local speaker = Players:GetPlayerByUserId(source.UserId)
			local prefix = message.PrefixText
			local title = speaker and speaker:GetAttribute("Title")
			if speaker and typeof(title) == "string" and title ~= "" then
				local color = speaker:GetAttribute("TitleColor")
				local hex = Format.hex(if typeof(color) == "Color3" then color else Color3.new(1, 1, 1))
				prefix = `<font color="{hex}"><b>[{title}]</b></font> {prefix}`
			end
			if speaker and speaker:GetAttribute("VIP") == true then
				prefix = `{tag} {prefix}`
			end
			if prefix ~= message.PrefixText then
				properties.PrefixText = prefix
			end
		end
		return properties
	end
end

return ChatTags
