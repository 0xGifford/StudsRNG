--[[

Combat
ModuleScript
/ServerScriptService/Server/Systems/Combat

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Enemies and fights, server-authoritative. Each zone has a few enemies
-- (Shared/Enemies) living at EnemySpawn-tagged parts, or Config.Combat.PerZone
-- spots of their own. Any spawn can roll a Mini Boss (more Health, harder
-- hits, bigger reward). Enemies only spawn and move while a player is near
-- their zone.
--
-- Enemies hunt: the nearest player who owns their zone within AggroRange is
-- chased with PathfindingService, never further than HomeRadius from home;
-- with nobody to chase they walk home and wander.
--
-- Fights start on their own: a player's equipped studs take the nearest
-- enemy within EngageRange. Every Tick the team deals its total Strength per
-- second and the enemy deals its Damage per second to the team's total
-- Health (RollLogic.teamStats). A defeat pays every player fighting it and
-- their studs move on to the next enemy within RetargetRange, or come home.
-- A team that falls is knocked out for a few seconds; RETREAT (StopFight)
-- keeps the studs home for RetreatCooldown. Out of a fight the team heals.
--
-- Crits (CritChance) hit for CritMultiplier; defeats in quick succession
-- build a kill streak (StreakWindow) worth StreakBonus more Clacks a link.
--
-- Clients see: enemy Models tagged Enemy (EnemyId, ZoneId, Health,
-- MaxHealth, Level, Boss attributes; Crits counts crits taken, Hunting is
-- the UserId it's chasing), each player's FightTarget and KillStreak
-- attributes (so everyone's studs fly at the right enemy) and the "Team"
-- state field { Hp, MaxHp, Strength, Fighting }. Combat.Defeated fires
-- (player, boss) for every fighter of a defeated enemy (QuestService).

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Tags = require(Shared.Tags)
local Zones = require(Shared.Zones)
local Enemies = require(Shared.Enemies)
local RollLogic = require(Shared.Util.RollLogic)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local Economy = require(Systems.Economy)

local Combat = {}

-- (player, boss) once per fighter of each defeated enemy
Combat.Defeated = Signal.new() :: Signal.Signal<Player, boolean>

local Settings = Config.Combat

type Enemy = {
	id: number,
	zoneId: string,
	def: Enemies.EnemyDef,
	home: Vector3, -- ground point it lives around
	boss: boolean,
	maxHealth: number,
	damage: number,
	reward: number,
	size: number,
	name: string,
	model: Model?,
	body: BasePart?,
	health: number,
	alive: boolean,
	fighters: { [Player]: boolean },
	-- Movement
	chasing: Player?,
	goal: Vector3?, -- where the current path leads
	waypoints: { Vector3 },
	waypoint: number,
	pathing: boolean, -- a path is being computed
	lastPath: number,
	nextWander: number,
}

type ZoneState = { zone: Instance, id: string, spawned: boolean, active: boolean }

type Team = {
	hp: number,
	maxHp: number,
	strength: number,
	knockedUntil: number,
	retreatUntil: number,
	sent: string,
}

local enemies: { [number]: Enemy } = {}
local zoneStates: { [Instance]: ZoneState } = {}
local fights: { [Player]: Enemy? } = {}
local engagedAt: { [Player]: number } = {} -- when the current fight started
local teams: { [Player]: Team } = {}
local folder: Folder
local nextId = 0
local rng = Random.new()
type Streak = { count: number, last: number }
local streaks: { [Player]: Streak } = {}

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart")) or (humanoid and humanoid.Health <= 0) then return nil end
	return root
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
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
		team = { hp = health, maxHp = health, strength = strength, knockedUntil = 0, retreatUntil = 0, sent = "" }
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

local function piece(model: Model, body: BasePart, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = body.CFrame * offset
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Studs
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
	return p
end

local function hoverHeight(enemy: Enemy): number
	return 0.6 + enemy.size * 0.4
end

-- A chunky brick monster: body, eyes, brows, mouth, feet; bosses wear a
-- gold crown. Welded to an anchored body, so moving the body moves it all.
local function buildModel(enemy: Enemy): (Model, BasePart)
	local s = enemy.size
	local model = Instance.new("Model")
	model.Name = enemy.name

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(s, s * 0.8, s)
	body.CFrame = CFrame.new(enemy.home + Vector3.new(0, hoverHeight(enemy), 0))
	body.Color = enemy.def.Color:Lerp(Color3.new(0, 0, 0), if enemy.boss then 0.55 else 0.35)
	body.Material = Enum.Material.SmoothPlastic
	body.TopSurface = Enum.SurfaceType.Studs
	body.Anchored = true
	body.CanCollide = false
	body.CanTouch = false
	body.CanQuery = false
	body.Parent = model
	model.PrimaryPart = body

	local white, black = Color3.fromRGB(245, 245, 245), Color3.fromRGB(20, 20, 26)
	local eye = if enemy.boss then Color3.fromRGB(255, 70, 50) else black
	for _, side in { -1, 1 } do
		piece(model, body, Vector3.new(s * 0.22, s * 0.26, 0.2), CFrame.new(side * s * 0.2, s * 0.08, -s / 2 - 0.1), white)
		piece(model, body, Vector3.new(s * 0.1, s * 0.13, 0.15), CFrame.new(side * s * 0.18, s * 0.05, -s / 2 - 0.22), eye)
		piece(model, body, Vector3.new(s * 0.26, s * 0.06, 0.15), CFrame.new(side * s * 0.2, s * 0.26, -s / 2 - 0.12) * CFrame.Angles(0, 0, side * 0.35), black)
		piece(model, body, Vector3.new(s * 0.3, 0.6, s * 0.4), CFrame.new(side * s * 0.25, -s * 0.4 - 0.3, -s * 0.05), body.Color:Lerp(black, 0.4))
	end
	piece(model, body, Vector3.new(s * 0.4, s * 0.08, 0.15), CFrame.new(0, -s * 0.18, -s / 2 - 0.1), black)
	if enemy.boss then
		local gold = Color3.fromRGB(255, 205, 60)
		piece(model, body, Vector3.new(s * 0.7, s * 0.14, s * 0.7), CFrame.new(0, s * 0.47, 0), gold, Enum.Material.Foil)
		for k = 0, 3 do
			local a = k * math.pi / 2
			piece(model, body, Vector3.new(s * 0.14, s * 0.22, s * 0.14), CFrame.new(math.cos(a) * s * 0.26, s * 0.62, math.sin(a) * s * 0.26), gold, Enum.Material.Foil)
		end
	end

	model:SetAttribute("EnemyId", enemy.id)
	model:SetAttribute("ZoneId", enemy.zoneId)
	model:SetAttribute("Level", enemy.def.Level)
	model:SetAttribute("Boss", enemy.boss)
	model:SetAttribute("MaxHealth", enemy.maxHealth)
	model:SetAttribute("Health", enemy.maxHealth)
	CollectionService:AddTag(model, Tags.Enemy)
	model.Parent = folder
	return model, body
end

-- (Re)spawns at home, rolling whether this one is a Mini Boss.
local function spawnEnemy(enemy: Enemy)
	local def = enemy.def
	enemy.boss = rng:NextNumber() < Settings.BossChance
	enemy.maxHealth = math.floor(def.Health * (if enemy.boss then Settings.BossHealth else 1))
	enemy.damage = def.Damage * (if enemy.boss then Settings.BossDamage else 1)
	enemy.reward = math.floor(def.Reward * (if enemy.boss then Settings.BossReward else 1))
	enemy.size = def.Size * (if enemy.boss then Settings.BossSize else 1)
	enemy.name = if enemy.boss then `Mini Boss {def.Name}` else def.Name
	enemy.health = enemy.maxHealth
	enemy.alive = true
	enemy.chasing = nil
	enemy.goal = nil
	enemy.waypoints = {}
	enemy.waypoint = 1
	enemy.nextWander = os.clock() + rng:NextNumber(1, 4)
	table.clear(enemy.fighters)
	local model, body = buildModel(enemy)
	enemy.model = model
	enemy.body = body

	if enemy.boss then
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if root and (root.Position - enemy.home).Magnitude < Settings.WakeRange then
				notify(player, `A {enemy.name} appeared!`, Color3.fromRGB(255, 205, 60))
			end
		end
	end
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
		boss = false,
		maxHealth = def.Health,
		damage = def.Damage,
		reward = def.Reward,
		size = def.Size,
		name = def.Name,
		model = nil,
		body = nil,
		health = def.Health,
		alive = false,
		fighters = {},
		chasing = nil,
		goal = nil,
		waypoints = {},
		waypoint = 1,
		pathing = false,
		lastPath = 0,
		nextWander = 0,
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

local activeZones: { [string]: boolean } = {}

local function updateZones()
	scanZones()
	table.clear(activeZones)
	for zone, state in zoneStates do
		if not zone.Parent then
			zoneStates[zone] = nil
			continue
		end
		state.active = zoneNear(zone)
		if state.active then
			activeZones[state.id] = true
			if not state.spawned then
				state.spawned = true
				for _, spot in spotsFor(zone, state.id) do
					addEnemy(state.id, spot)
				end
			end
		end
	end
end

--------------------------------------------------------------------------
-- Movement: chase with pathfinding, walk home, wander
--------------------------------------------------------------------------

-- Computes a path in the background; until it lands the enemy heads
-- straight for the goal.
local function requestPath(enemy: Enemy, goal: Vector3)
	enemy.goal = goal
	enemy.lastPath = os.clock()
	if enemy.pathing or not enemy.body then return end
	enemy.pathing = true
	local from = enemy.body.Position - Vector3.new(0, hoverHeight(enemy), 0)
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = math.max(2, enemy.size / 2),
			AgentHeight = enemy.size,
			AgentCanJump = false,
			WaypointSpacing = 6,
		})
		local ok = pcall(path.ComputeAsync, path, from, goal)
		enemy.pathing = false
		if not enemy.alive then return end
		local points: { Vector3 } = {}
		if ok and path.Status == Enum.PathStatus.Success then
			for _, waypoint in path:GetWaypoints() do
				table.insert(points, waypoint.Position)
			end
		end
		if #points == 0 then
			points = { goal } -- no path: walk straight at it
		end
		enemy.waypoints = points
		enemy.waypoint = math.min(2, #points)
	end)
end

-- Steps the enemy along its waypoints at `speed`. Returns true when it has
-- arrived (within `stop` of the last one).
local function walk(enemy: Enemy, dt: number, speed: number, stop: number): boolean
	local body = enemy.body
	if not body then return true end
	local here = body.Position - Vector3.new(0, hoverHeight(enemy), 0)
	local points = enemy.waypoints
	if #points == 0 then
		points = { enemy.goal or here }
	end
	local target = points[math.min(enemy.waypoint, #points)]
	local final = points[#points]
	if flat(final - here).Magnitude <= stop then
		return true
	end
	while flat(target - here).Magnitude < 1 and enemy.waypoint < #points do
		enemy.waypoint += 1
		target = points[enemy.waypoint]
	end
	local offset = flat(target - here)
	local distance = offset.Magnitude
	if distance < 0.05 then return false end
	local move = offset.Unit * math.min(distance, speed * dt)
	local nextPos = here + move
	-- Follow the ground the path walks on.
	nextPos = Vector3.new(nextPos.X, here.Y + (target.Y - here.Y) * math.clamp(speed * dt / math.max(distance, 0.1), 0, 1), nextPos.Z)
	local lifted = nextPos + Vector3.new(0, hoverHeight(enemy), 0)
	body.CFrame = CFrame.lookAt(lifted, lifted + move)
	return false
end

local function face(enemy: Enemy, position: Vector3)
	local body = enemy.body
	if not body then return end
	local here = body.Position
	local look = Vector3.new(position.X, here.Y, position.Z)
	if (look - here).Magnitude > 0.5 then
		body.CFrame = CFrame.lookAt(here, look)
	end
end

-- Who an enemy goes after: whoever it's already fighting, else the nearest
-- player who owns its zone and is close, as long as it stays near home.
local function preyOf(enemy: Enemy): (Player?, BasePart?)
	local body = enemy.body
	if not body then return nil, nil end
	local best: Player?, bestRoot: BasePart?, bestDistance = nil, nil, Settings.AggroRange
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and Economy.ownsZone(player, enemy.zoneId) then
			local distance = (root.Position - body.Position).Magnitude
			local fightingIt = enemy.fighters[player] == true
			if (distance < bestDistance or fightingIt) and (root.Position - enemy.home).Magnitude < Settings.HomeRadius + Settings.AggroRange then
				best, bestRoot, bestDistance = player, root, if fightingIt then -1 else distance
			end
		end
	end
	return best, bestRoot
end

local function move(dt: number)
	local now = os.clock()
	for _, enemy in enemies do
		local body = enemy.body
		if not (enemy.alive and body and activeZones[enemy.zoneId]) then continue end

		local prey, root = preyOf(enemy)
		local here = body.Position
		-- Once leashed it must get well back inside before it chases again.
		local leash = if enemy.chasing then Settings.HomeRadius else Settings.HomeRadius * 0.6
		if prey and root and (flat(here - enemy.home)).Magnitude < leash then
			-- Chase: re-path when the player has moved on.
			if enemy.chasing ~= prey and enemy.model then
				enemy.model:SetAttribute("Hunting", prey.UserId)
			end
			enemy.chasing = prey
			local stop = enemy.size / 2 + 4
			local goal = root.Position - Vector3.new(0, 3, 0)
			if not enemy.goal or now - enemy.lastPath > Settings.RepathTime and flat(goal - enemy.goal).Magnitude > 3 then
				requestPath(enemy, goal)
			end
			if walk(enemy, dt, Settings.ChaseSpeed, stop) then
				face(enemy, root.Position)
			end
		else
			-- Too far from home or nobody about: go home, then wander.
			if enemy.chasing then
				enemy.chasing = nil
				if enemy.model then
					enemy.model:SetAttribute("Hunting", nil)
				end
				requestPath(enemy, enemy.home)
			end
			if walk(enemy, dt, Settings.WanderSpeed, 1.5) and now >= enemy.nextWander then
				local angle = rng:NextNumber(0, math.pi * 2)
				local distance = rng:NextNumber(3, Settings.WanderRadius)
				enemy.goal = enemy.home + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
				enemy.waypoints = { enemy.goal :: Vector3 }
				enemy.waypoint = 1
				enemy.nextWander = now + rng:NextNumber(3, 6)
			end
		end
	end
end

--------------------------------------------------------------------------
-- Fights
--------------------------------------------------------------------------

local function setFight(player: Player, enemy: Enemy?)
	local current = fights[player]
	if current == enemy then return end
	if current then
		current.fighters[player] = nil
		-- Left alone, it shakes the fight off.
		if next(current.fighters) == nil and current.alive then
			current.health = current.maxHealth
			if current.model then
				current.model:SetAttribute("Health", current.health)
			end
		end
	end
	fights[player] = enemy
	if enemy then
		enemy.fighters[player] = true
		engagedAt[player] = os.clock()
		player:SetAttribute("FightTarget", enemy.id)
	else
		player:SetAttribute("FightTarget", nil)
	end
	local team = teams[player]
	if team then
		pushTeam(player, team)
	end
end

-- The nearest live enemy within `range` of the player, in a zone they own.
local function nearestEnemy(player: Player, range: number, except: Enemy?): Enemy?
	local root = rootOf(player)
	if not root then return nil end
	local best: Enemy?, bestDistance = nil, range
	for _, enemy in enemies do
		local body = enemy.body
		if enemy ~= except and enemy.alive and body and Economy.ownsZone(player, enemy.zoneId) then
			local distance = (body.Position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = enemy, distance
			end
		end
	end
	return best
end

local function canFight(player: Player, team: Team?): boolean
	local now = os.clock()
	return team ~= nil and team.strength > 0 and now >= team.knockedUntil and now >= team.retreatUntil
end

local function defeat(enemy: Enemy)
	enemy.alive = false
	local fighters = table.clone(enemy.fighters)
	for player in fighters do
		local data = PlayerData.get(player)
		if data then
			local rebirths = if typeof(data.Rebirths) == "number" then data.Rebirths else 0
			-- Kill streak: chain defeats inside the window.
			local now = os.clock()
			local streak = streaks[player]
			if streak and now - streak.last <= Settings.StreakWindow then
				streak.count = math.min(streak.count + 1, Settings.StreakMax)
				streak.last = now
			else
				streak = { count = 1, last = now }
				streaks[player] = streak
			end
			player:SetAttribute("KillStreak", streak.count)
			local streakBonus = 1 + (streak.count - 1) * Settings.StreakBonus
			local amount = math.floor(enemy.reward * (1 + rebirths * Config.Rebirth.ClacksPerRebirth) * streakBonus)
			Economy.addClacks(player, amount)
			local extra = ""
			if rng:NextNumber() < Settings.FreeRollChance * (if enemy.boss then 5 else 1) then
				Economy.addFreeRolls(player, if enemy.boss then 3 else 1, true)
				extra = if enemy.boss then " +3 Rolls" else " +1 Roll"
			end
			data.EnemiesDefeated += 1
			StateSync.push(player, "EnemiesDefeated", data.EnemiesDefeated)
			local streakText = if streak.count > 1 then ` (Streak x{streak.count})` else ""
			notify(player, `Defeated {enemy.name}! +{shortNumber(amount)} Clacks{extra}{streakText}`, Color3.fromRGB(255, 215, 90))
			Combat.Defeated:Fire(player, enemy.boss)
		end
	end
	if enemy.model then
		enemy.model:SetAttribute("Health", 0)
		enemy.model:Destroy()
	end
	enemy.model = nil
	enemy.body = nil
	table.clear(enemy.fighters)
	-- The studs move on to the next enemy nearby, or come home.
	-- (setFight clears FightTarget when there's nobody left to fight.)
	for player in fighters do
		local nextEnemy = if canFight(player, teams[player]) then nearestEnemy(player, Settings.RetargetRange, enemy) else nil
		setFight(player, nextEnemy)
	end
	task.delay(Settings.Respawn, function()
		if enemies[enemy.id] == enemy and not enemy.alive then
			spawnEnemy(enemy)
		end
	end)
end

local function knockout(player: Player, team: Team)
	team.hp = 0
	team.knockedUntil = os.clock() + Settings.KnockoutCooldown
	setFight(player, nil)
	notify(player, "Your studs were knocked out! Equip stronger studs or avoid this enemy.", Color3.fromRGB(255, 110, 110))
end

local function step(dt: number)
	for _, player in Players:GetPlayers() do
		local team = teamOf(player)
		if not team then continue end
		local root = rootOf(player)
		local enemy = fights[player]

		-- Drop fights that no longer make sense.
		if enemy and (not enemy.alive or not enemy.body or not root or not canFight(player, team)
			or (root.Position - enemy.body.Position).Magnitude > Settings.LeashRange) then
			setFight(player, nil)
			enemy = nil
		end
		-- Start one with the nearest enemy close enough.
		if not enemy and root and canFight(player, team) then
			enemy = nearestEnemy(player, Settings.EngageRange)
			if enemy then
				setFight(player, enemy)
			end
		end

		if enemy then
			-- Nothing lands until the studs have flown over, and no team
			-- kills faster than MinFightTime (the dash animation needs it).
			if os.clock() - (engagedAt[player] or 0) >= Settings.ArriveTime then
				local dps = math.min(team.strength, enemy.maxHealth / Settings.MinFightTime)
				if rng:NextNumber() < Settings.CritChance then
					dps *= Settings.CritMultiplier
					if enemy.model then
						local crits = enemy.model:GetAttribute("Crits")
						enemy.model:SetAttribute("Crits", (if typeof(crits) == "number" then crits else 0) + 1)
					end
				end
				enemy.health -= dps * dt
				team.hp -= enemy.damage * dt
				if team.hp <= 0 then
					knockout(player, team)
				end
			end
		elseif team.hp < team.maxHp then
			team.hp = math.min(team.maxHp, team.hp + team.maxHp * Settings.RegenPerSecond * dt)
		end
		pushTeam(player, team)

		-- Streaks run out.
		local streak = streaks[player]
		if streak and os.clock() - streak.last > Settings.StreakWindow then
			streaks[player] = nil
			player:SetAttribute("KillStreak", nil)
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
end

--------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------

function Combat.init()
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = workspace

	-- RETREAT: studs come home and stay out of fights for a moment.
	Net.handle("StopFight", { Rate = 2, Burst = 4 }, function(player)
		local team = teams[player]
		if team then
			team.retreatUntil = os.clock() + Settings.RetreatCooldown
		end
		setFight(player, nil)
		return { Ok = true }
	end)

	Players.PlayerRemoving:Connect(function(player)
		setFight(player, nil)
		teams[player] = nil
		engagedAt[player] = nil
		streaks[player] = nil
	end)
end

function Combat.start()
	task.spawn(function()
		while true do
			updateZones()
			task.wait(1)
		end
	end)
	RunService.Heartbeat:Connect(move)
	while true do
		local dt = task.wait(Settings.Tick)
		step(dt)
	end
end

return Combat
