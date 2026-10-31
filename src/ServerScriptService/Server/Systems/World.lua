--[[

World
ModuleScript
/ServerScriptService/Server/Systems/World

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The hand-built map (workspace.Zones: the Lobby, then Zone1 .. Zone34,
-- wired by tools/wire_zones.luau or the ZoneManager plugin). This keeps it
-- honest at runtime:
--   * ZoneSign-tagged signs show their zone's name from Shared/Zones, so a
--     rename never leaves a stale sign.
--   * Players who fall out of the map (below Config.World.FallY) are put back
--     at the nearest zone they own, else the Lobby's SpawnLocation.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Zones = require(Shared.Zones)
local Tags = require(Shared.Tags)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)

local World = {}

local function labelSign(sign: Instance)
	local zoneId = Tags.zoneOf(sign)
	local def = if zoneId then Zones.ById[zoneId] else nil
	if not def then return end
	local labels: { Instance } = if sign:IsA("TextLabel") then { sign } else sign:GetDescendants()
	for _, label in labels do
		if label:IsA("TextLabel") then
			label.Text = def.Name
		end
	end
end

local function lobbySpawn(): BasePart?
	local zones = workspace:FindFirstChild(Config.ZoneFolder)
	local lobby = zones and zones:FindFirstChild("Lobby")
	if not lobby then return nil end
	local found = lobby:FindFirstChild("LobbySpawn") or lobby:FindFirstChildWhichIsA("SpawnLocation", true)
	return if found and found:IsA("BasePart") then found else nil
end

local function rescueSpot(player: Player, position: Vector3): BasePart?
	local data = PlayerData.get(player)
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, def in Zones.List do
		local owned = def.Id == Zones.Default or (data ~= nil and data.UnlockedWorlds[def.Id] == true)
		local spawnPart = if owned then Tags.spawnOf(def.Id) else nil
		if spawnPart then
			local offset = spawnPart.Position - position
			local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				best = spawnPart
			end
		end
	end
	local lobby = lobbySpawn()
	if lobby then
		local offset = lobby.Position - position
		if Vector3.new(offset.X, 0, offset.Z).Magnitude < bestDistance then
			best = lobby
		end
	end
	return best
end

function World.init() end

function World.start()
	for _, sign in CollectionService:GetTagged(Tags.ZoneSign) do
		labelSign(sign)
	end
	CollectionService:GetInstanceAddedSignal(Tags.ZoneSign):Connect(labelSign)

	if not Config.World.FallRescue then return end
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if character and root and root:IsA("BasePart") and root.Position.Y < Config.World.FallY then
					local spot = rescueSpot(player, root.Position)
					if spot then
						root.AssemblyLinearVelocity = Vector3.zero
						character:PivotTo(spot.CFrame + Vector3.new(0, 4, 0))
					end
				end
			end
		end
	end)
end

return World
