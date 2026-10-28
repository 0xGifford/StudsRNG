--[[

Social
ModuleScript
/ServerScriptService/Server/Systems/Social

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Friend boost (+10% Clacks per friend in the server, up to 5) and Premium
-- boost. Friendships are looked up once per pair when a player joins
-- (IsFriendsWith is a web call) and counted from the cache afterwards.

local Players = game:GetService("Players")

local Systems = script.Parent
local Modifiers = require(Systems.Modifiers)

local Social = {}

-- friendsOf[a][b] = true when a and b are friends (both directions stored).
local friendsOf: { [Player]: { [Player]: boolean } } = {}

local function setFor(player: Player): { [Player]: boolean }
	local set = friendsOf[player]
	if not set then
		set = {}
		friendsOf[player] = set
	end
	return set
end

local function recount(player: Player)
	local n = 0
	for other in setFor(player) do
		if other.Parent == Players then
			n += 1
		end
	end
	Modifiers.setFriends(player, n)
end

local function updatePremium(player: Player)
	Modifiers.setPremium(player, player.MembershipType == Enum.MembershipType.Premium)
end

local function onPlayerAdded(player: Player)
	setFor(player)
	updatePremium(player)
	player:GetPropertyChangedSignal("MembershipType"):Connect(function()
		updatePremium(player)
	end)

	for _, other in Players:GetPlayers() do
		if other ~= player then
			task.spawn(function()
				local ok, isFriend = pcall(player.IsFriendsWith, player, other.UserId)
				if ok and isFriend and player.Parent == Players and other.Parent == Players then
					setFor(player)[other] = true
					setFor(other)[player] = true
					recount(player)
					recount(other)
				end
			end)
		end
	end
end

function Social.friendCount(player: Player): number
	local n = 0
	for other in setFor(player) do
		if other.Parent == Players then
			n += 1
		end
	end
	return n
end

function Social.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local set = friendsOf[player]
		friendsOf[player] = nil
		if set then
			for other in set do
				local otherSet = friendsOf[other]
				if otherSet then
					otherSet[player] = nil
					recount(other)
				end
			end
		end
	end)
end

return Social
