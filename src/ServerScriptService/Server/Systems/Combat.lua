--[[

Combat
ModuleScript
/ServerScriptService/Server/Systems/Combat

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Enemies and fights, server-authoritative. Each zone has a few enemies
-- (Shared/Enemies) that wander around their spot: EnemySpawn-tagged parts,
-- or Config.Combat.PerZone spots the zone gets by default. They only spawn
-- and move while a player is near their zone.
--
-- A player starts a fight (FightEnemy) with an enemy in a zone they own.
-- Every Tick their equipped studs deal the team's total Strength per second
-- and the enemy deals its Damage per second to the team's total Health
-- (RollLogic.teamStats). The enemy falling pays every player fighting it;
-- the team falling knocks it out for a few seconds. Out of a fight the
-- team's Health regenerates.
--
-- Clients see: enemy Models tagged Enemy (EnemyId, ZoneId, Health,
-- MaxHealth, Level attributes), the player's FightTarget attribute (so
-- everyone's followers can fly at the right enemy), and the "Team" state
-- field { Hp, MaxHp, Strength, Fighting }.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Tags = require(Shared.Tags)
local Zones = require(Shared.Zones)
local Enemies = require(Shared.Enemies)
local RollLogic = require(Shared.Util.RollLogic)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local Economy = require(Systems.Economy)

local Combat = {}

local Settings = Config.Combat

type Enemy = {
	id: number,
	zoneId: string,
	def: Enemies.EnemyDef,
	home: Vector3, -- ground point it wanders around
	model: Model?,
	body: BasePart?,
	health: number,
	alive: boolean,
	fighters: { [Player]: boolean },
	nextMove: number,
	tween: Tween?,
}

type ZoneState = { zone: Instance, id: string, spawned: boolean, active: boolean }

type Team = { hp: number, maxHp: number, strength: number, knockedUntil: number, sent: string }

local enemies: { [number]: Enemy } = {}
local zoneStates: { [Instance]: ZoneState } = {}
local fights: { [Player]: Enemy } = {}
local teams: { [Player]: Team } = {}
local folder: Folder
local nextId = 0
local rng = Random.new()

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function shortNumber(n: number): string
	local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
	if n < 1000 then return tostring(math.floor(n)) end
	local tier = math.min(math.floor(math.log10(n) / 3), #suffixes - 1)
	local text = string.format("%.2f", n / 10 ^ (tier * 3))
	text = string.gsub(text, "%.?0+$", "")
	return text .. suffixes[tier + 1]
end

local function notify(player: Player, text: string, color: Color3?)
	Net.fire(player, "Notify", { Text = text, Color = color })
end

--------------------------------------------------------------------------
-- Teams
--------------------------------------------------------------------------

local function teamOf(player: Player): Team?
	local data = PlayerData.get(player)
	if not data then return nil end
	local strength, health = RollLogic.teamStats(data.Equipped or {})
	local team = teams[player]
	if not team then
		team = { hp = health, maxHp = health, strength = strength, knockedUntil = 0, sent = "" }
		teams[player] = team
	end
	-- Equipment changes resize the pool but keep how hurt the team is.
	if team.maxHp ~= health then
		local share = if team.maxHp > 0 then team.hp / team.maxHp else 1
		team.maxHp = health
		team.hp = health * share
	end
	team.strength = strength
	return team
end

local function pushTeam(player: Player, team: Team)
	local fighting = fights[player] ~= nil
	local hp = math.max(0, math.floor(team.hp))
	local key = `{hp}/{team.maxHp}/{team.strength}/{fighting}`
	if key == team.sent then return end
	team.sent = key
	StateSync.setVolatile(player, "Team", { Hp = hp, MaxHp = team.maxHp, Strength = team.strength, Fighting = fighting })
end

--------------------------------------------------------------------------
-- Enemy models
--------------------------------------------------------------------------

local function weld(part: BasePart, to: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = to
	constraint.Part1 = part
	constraint.Parent = part
end

local function piece(model: Model, body: BasePart, size: Vector3, offset: CFrame, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = body.CFrame * offset
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Studs
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	weld(p, body)
	p.Parent = model
	return p
end

-- A chunky brick monster: body, eyes, feet. Welded to an anchored body so
-- tweening the body moves it all.
local function buildModel(enemy: Enemy): (Model, BasePart)
	local def = enemy.def
	local s = def.Size
	local model = Instance.new("Model")
	model.Name = def.Name

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(s, s * 0.8, s)
	body.CFrame = CFrame.new(enemy.home + Vector3.new(0, 0.6 + s * 0.4, 0))
	body.Color = def.Color:Lerp(Color3.new(0, 0, 0), 0.35)
	body.Material = Enum.Material.SmoothPlastic
	body.TopSurface = Enum.SurfaceType.Studs
	body.Anchored = true
	body.CanCollide = false
	body.CanTouch = false
	body.CanQuery = true -- clicks and prompts
	body.Parent = model
	model.PrimaryPart = body

	local white, black = Color3.fromRGB(245, 245, 245), Color3.fromRGB(20, 20, 26)
	for _, side in { -1, 1 } do
		piece(model, body, Vector3.new(s * 0.22, s * 0.26, 0.2), CFrame.new(side * s * 0.2, s * 0.08, -s / 2 - 0.1), white)
		piece(model, body, Vector3.new(s * 0.1, s * 0.13, 0.15), CFrame.new(side * s * 0.18, s * 0.05, -s / 2 - 0.22), black)
		-- Angry brows.
		piece(model, body, Vector3.new(s * 0.26, s * 0.06, 0.15), CFrame.new(side * s * 0.2, s * 0.26, -s / 2 - 0.12) * CFrame.Angles(0, 0, side * 0.35), black)
		piece(model, body, Vector3.new(s * 0.3, 0.6, s * 0.4), CFrame.new(side * s * 0.25, -s * 0.4 - 0.3, -s * 0.05), body.Color:Lerp(black, 0.4))
	end
	piece(model, body, Vector3.new(s * 0.4, s * 0.08, 0.15), CFrame.new(0, -s * 0.18, -s / 2 - 0.1), black) -- mouth

	model:SetAttribute("EnemyId", enemy.id)
	model:SetAttribute("ZoneId", enemy.zoneId)
	model:SetAttribute("Level", def.Level)
	model:SetAttribute("MaxHealth", def.Health)
	model:SetAttribute("Health", def.Health)
	CollectionService:AddTag(model, Tags.Enemy)
	model.Parent = folder
	return model, body
end

local function spawnEnemy(enemy: Enemy)
	enemy.health = enemy.def.Health
	enemy.alive = true
	enemy.nextMove = os.clock() + rng:NextNumber(1, 4)
	table.clear(enemy.fighters)
	local model, body = buildModel(enemy)
	enemy.model = model
	enemy.body = body
end

local function addEnemy(zoneId: string, home: Vector3)
	local def = Enemies.forZone(zoneId)
	if not def then return end
	nextId += 1
	local enemy: Enemy = {
		id = nextId,
		zoneId = zoneId,
		def = def,
		home = home,
		model = nil,
		body = nil,
		health = def.Health,
		alive = false,
		fighters = {},
		nextMove = 0,
		tween = nil,
	}
	enemies[enemy.id] = enemy
	spawnEnemy(enemy)
end

--------------------------------------------------------------------------
-- Zones: where enemies live, and which zones are awake
--------------------------------------------------------------------------

-- The zone's EnemySpawn parts, or default spots either side of the keyboard.
local function spotsFor(zone: Instance, zoneId: string): { Vector3 }
	local spots: { Vector3 } = {}
	for _, spawnPart in Tags.forZone(Tags.EnemySpawn, zoneId) do
		if spawnPart:IsA("BasePart") then
			table.insert(spots, spawnPart.Position - Vector3.new(0, spawnPart.Size.Y / 2, 0))
		end
	end
	if #spots > 0 then return spots end
	local center = zone:GetAttribute(Tags.Attr.Center)
	if typeof(center) ~= "Vector3" then
		local cframe = Tags.zoneBox(zone)
		if not cframe then return spots end
		center = cframe.Position
	end
	local offsets = { Vector3.new(-48, 0, -38), Vector3.new(48, 0, -38), Vector3.new(-48, 0, 44), Vector3.new(48, 0, 44) }
	for i = 1, math.min(Settings.PerZone, #offsets) do
		table.insert(spots, (center :: Vector3) + offsets[i])
	end
	return spots
end

local function scanZones()
	for _, zone in CollectionService:GetTagged(Tags.Zone) do
		local id = Tags.idOfZone(zone)
		if Zones.ById[id] and not zoneStates[zone] then
			zoneStates[zone] = { zone = zone, id = id, spawned = false, active = false }
		end
	end
end

local function zoneNear(zone: Instance): boolean
	local cframe, size = Tags.zoneBox(zone)
	if not (cframe and size) then return false end
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root then
			local localPoint = cframe:PointToObjectSpace(root.Position)
			local half = size / 2
			local dx = math.max(0, math.abs(localPoint.X) - half.X)
			local dz = math.max(0, math.abs(localPoint.Z) - half.Z)
			if math.sqrt(dx * dx + dz * dz) <= Settings.WakeRange then
				return true
			end
		end
	end
	return false
end

local function updateZones()
	scanZones()
	for zone, state in zoneStates do
		if not zone.Parent then
			zoneStates[zone] = nil
			continue
		end
		state.active = zoneNear(zone)
		if state.active and not state.spawned then
			state.spawned = true
			for _, spot in spotsFor(zone, state.id) do
				addEnemy(state.id, spot)
			end
		end
	end
end

local function zoneActive(zoneId: string): boolean
	for _, state in zoneStates do
		if state.id == zoneId and state.active then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------
-- Fights
--------------------------------------------------------------------------

local function endFight(player: Player)
	local enemy = fights[player]
	fights[player] = nil
	if enemy then
		enemy.fighters[player] = nil
		-- Left alone, it shakes the fight off.
		if next(enemy.fighters) == nil and enemy.alive then
			enemy.health = enemy.def.Health
			if enemy.model then
				enemy.model:SetAttribute("Health", enemy.health)
			end
		end
	end
	player:SetAttribute("FightTarget", nil)
	local team = teams[player]
	if team then
		pushTeam(player, team)
	end
end

local function defeat(enemy: Enemy)
	enemy.alive = false
	local rewardName = enemy.def.Name
	for player in enemy.fighters do
		local data = PlayerData.get(player)
		if data then
			local rebirths = if typeof(data.Rebirths) == "number" then data.Rebirths else 0
			local amount = math.floor(enemy.def.Reward * (1 + rebirths * Config.Rebirth.ClacksPerRebirth))
			Economy.addClacks(player, amount)
			local extra = ""
			if rng:NextNumber() < Settings.FreeRollChance then
				Economy.addFreeRolls(player, 1, true)
				extra = " +1 Roll"
			end
			data.EnemiesDefeated += 1
			StateSync.push(player, "EnemiesDefeated", data.EnemiesDefeated)
			notify(player, `Defeated {rewardName}! +{shortNumber(amount)} Clacks{extra}`, Color3.fromRGB(255, 215, 90))
		end
	end
	for player in table.clone(enemy.fighters) do
		endFight(player)
	end
	if enemy.tween then
		enemy.tween:Cancel()
		enemy.tween = nil
	end
	if enemy.model then
		enemy.model:SetAttribute("Health", 0)
		enemy.model:Destroy()
	end
	enemy.model = nil
	enemy.body = nil
	task.delay(Settings.Respawn, function()
		if enemies[enemy.id] == enemy and not enemy.alive then
			spawnEnemy(enemy)
		end
	end)
end

local function knockout(player: Player, team: Team)
	team.hp = 0
	team.knockedUntil = os.clock() + Settings.KnockoutCooldown
	endFight(player)
	notify(player, "Your studs were knocked out! Equip stronger studs or try an easier enemy.", Color3.fromRGB(255, 110, 110))
end

local function fightEnemy(player: Player, enemyId: unknown): any
	if typeof(enemyId) ~= "number" then return { Ok = false, Error = "EnemyGone" } end
	local enemy = enemies[enemyId :: number]
	if not enemy or not enemy.alive or not enemy.body then return { Ok = false, Error = "EnemyGone" } end
	local data = PlayerData.get(player)
	if not data then return { Ok = false, Error = "NotLoaded" } end
	if not Economy.ownsZone(player, enemy.zoneId) then return { Ok = false, Error = "ZoneLocked" } end
	local team = teamOf(player)
	if not team or team.strength <= 0 then return { Ok = false, Error = "NoStuds" } end
	if os.clock() < team.knockedUntil then return { Ok = false, Error = "KnockedOut" } end
	local root = rootOf(player)
	if not root or (root.Position - enemy.body.Position).Magnitude > Settings.FightRange then
		return { Ok = false, Error = "TooFar" }
	end
	if fights[player] and fights[player] ~= enemy then
		endFight(player)
	end
	fights[player] = enemy
	enemy.fighters[player] = true
	if enemy.tween then
		enemy.tween:Cancel()
		enemy.tween = nil
	end
	player:SetAttribute("FightTarget", enemy.id)
	pushTeam(player, team)
	return { Ok = true }
end

local function step(dt: number)
	-- Fights
	for player, enemy in fights do
		local team = teamOf(player)
		local root = rootOf(player)
		if not team or not enemy.alive or not enemy.body or not root
			or (root.Position - enemy.body.Position).Magnitude > Settings.LeashRange then
			endFight(player)
			continue
		end
		enemy.health -= team.strength * dt
		team.hp -= enemy.def.Damage * dt
		-- Face whoever it's fighting.
		local here = enemy.body.Position
		local look = Vector3.new(root.Position.X, here.Y, root.Position.Z)
		if (look - here).Magnitude > 0.5 then
			enemy.body.CFrame = CFrame.lookAt(here, look)
		end
		if team.hp <= 0 then
			knockout(player, team)
		end
	end
	for _, enemy in enemies do
		if enemy.alive and enemy.model then
			if enemy.health <= 0 then
				defeat(enemy)
			else
				enemy.model:SetAttribute("Health", math.ceil(enemy.health))
			end
		end
	end

	-- Teams out of a fight heal up.
	for _, player in Players:GetPlayers() do
		local team = teamOf(player)
		if team then
			if not fights[player] and team.hp < team.maxHp then
				team.hp = math.min(team.maxHp, team.hp + team.maxHp * Settings.RegenPerSecond * dt)
			end
			pushTeam(player, team)
		end
	end
end

-- Idle enemies stroll around their spot while their zone is awake.
local function wander()
	local now = os.clock()
	for _, enemy in enemies do
		local body = enemy.body
		if enemy.alive and body and next(enemy.fighters) == nil and now >= enemy.nextMove and zoneActive(enemy.zoneId) then
			local angle = rng:NextNumber(0, math.pi * 2)
			local distance = rng:NextNumber(3, Settings.WanderRadius)
			local goal = enemy.home + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			local here = body.Position
			local target = Vector3.new(goal.X, here.Y, goal.Z)
			local travel = (target - here).Magnitude / 6
			body.CFrame = CFrame.lookAt(here, target)
			local tween = TweenService:Create(body, TweenInfo.new(travel, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(target, target + (target - here).Unit) })
			enemy.tween = tween
			tween:Play()
			enemy.nextMove = now + travel + rng:NextNumber(2, 5)
		end
	end
end

--------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------

function Combat.init()
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = workspace

	Net.handle("FightEnemy", { Rate = 2, Burst = 4 }, fightEnemy)
	Net.handle("StopFight", { Rate = 2, Burst = 4 }, function(player)
		endFight(player)
		return { Ok = true }
	end)

	Players.PlayerRemoving:Connect(function(player)
		endFight(player)
		teams[player] = nil
	end)
end

function Combat.start()
	task.spawn(function()
		while true do
			updateZones()
			wander()
			task.wait(1)
		end
	end)
	while true do
		local dt = task.wait(Settings.Tick)
		step(dt)
	end
end

return Combat
