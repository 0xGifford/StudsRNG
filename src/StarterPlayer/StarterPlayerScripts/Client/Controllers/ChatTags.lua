--[[

ChatTags
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/ChatTags

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The [VIP] chat tag. The server sets the player attribute "VIP" (from the
-- VIP game pass); every client prefixes that player's messages. Works with
-- TextChatService (the default chat).

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
			if speaker and speaker:GetAttribute("VIP") == true then
				properties.PrefixText = `{tag} {message.PrefixText}`
			end
		end
		return properties
	end
end

return ChatTags
