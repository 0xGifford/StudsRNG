
--[[

Combat
ModuleScript
/ServerScriptService/Server/Systems/Combat

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Enemies and fights, server-authoritative. Each zone has enemies living
-- on its EnemyGround-tagged surfaces: at its EnemySpawn markers first, then
-- random clear spots on that ground, up to a capacity that scales with the
-- zone's floor area (Config.Combat AreaPerEnemy / MinPerZone / MaxPerZone).
-- A zone without EnemyGround uses its own geometry as ground.
--
-- Enemies only spawn and move while a player is near their zone.
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
-- (player, boss, zoneBoss) for everyone paid for a defeat (QuestService).
--
-- Zone Bosses (Config.ZoneBoss): on a fixed clock a Titan spawns in every
-- 10th zone. It's an enemy like any other (ZoneBoss attribute) but tracks
-- damage per player; on defeat everyone who hit it is paid by rank, and it
-- escapes when its Lifetime runs out. The "ZoneBoss" event tells clients:
-- Warning, Spawn, Board, Result, Defeated, Escaped.

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
local Modifiers = require(Systems.Modifiers)
local Boosts = require(Systems.Boosts)
local Drops = require(Systems.Drops)
local RewardService = require(Systems.RewardService)
local Products = require(Systems.Products)
local ServerEffects = require(Systems.ServerEffects)

local Combat = {}

-- (player, boss, zoneBoss) once per player paid for each defeated enemy
Combat.Defeated = Signal.new() :: Signal.Signal<Player, boolean, boolean>

local Settings = Config.Combat
local MOVE_STEP = 1 / 20

type Enemy = {
	id: number,
	zoneId: string,
	def: Enemies.EnemyDef,
	home: Vector3,
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

	-- Zone Bosses (a Mega Boss is one too: event-spawned, its own stats)
	zoneBoss: boolean,
	mega: Config.EventDef?, -- the event that spawned this Mega Boss
	forceBoss: boolean,
	summoned: boolean,
	damageBy: { [Player]: number },
	expiresAt: number,

	-- Movement
	chasing: Player?,
	goal: Vector3?,
	waypoints: { Vector3 },
	waypoint: number,
	pathing: boolean,
	lastPath: number,
	blocked: RBXScriptConnection?,
	nextWander: number,
}

type ZoneState = {
	zone: Instance,
	id: string,
	spawned: boolean,
	active: boolean,
}

type Team = {
	hp: number,
	maxHp: number,
	strength: number,
	knockedUntil: number,
	retreatUntil: number,
	sent: string,
}

type Streak = {
	count: number,
	last: number,
}

local enemies: { [number]: Enemy } = {}
-- The same enemies by zone: separation only compares neighbours in a zone
-- (comparing against every enemy in the game was O(n²) at 20 Hz).
local byZone: { [string]: { [number]: Enemy } } = {}

local function register(enemy: Enemy)
	enemies[enemy.id] = enemy
	local bucket = byZone[enemy.zoneId]
	if not bucket then
		bucket = {}
		byZone[enemy.zoneId] = bucket
	end
	bucket[enemy.id] = enemy
end

local function unregister(enemy: Enemy)
	enemies[enemy.id] = nil
	local bucket = byZone[enemy.zoneId]
	if bucket then
		bucket[enemy.id] = nil
	end
end
local zoneStates: { [Instance]: ZoneState } = {}
local fights: { [Player]: Enemy? } = {}
local engagedAt: { [Player]: number } = {}
local teams: { [Player]: Team } = {}
local folder: Folder
local nextId = 0
local rng = Random.new()
local streaks: { [Player]: Streak } = {}

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not (root and root:IsA("BasePart")) or (humanoid and humanoid.Health <= 0) then
		return nil
	end

	return root
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function shortNumber(n: number): string
	local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

	if n < 1000 then
		return tostring(math.floor(n))
	end

	local tier = math.min(math.floor(math.log10(n) / 3), #suffixes - 1)
	local formatted = string.format("%.2f", n / 10 ^ (tier * 3))
	formatted = string.gsub(formatted, "%.?0+$", "")

	return formatted .. suffixes[tier + 1]
end

local function notify(player: Player, message: string, color: Color3?)
	Net.fire(player, "Notify", {
		Text = message,
		Color = color,
	})
end

--------------------------------------------------------------------------
-- Teams
--------------------------------------------------------------------------

local function teamOf(player: Player): Team?
	local data = PlayerData.get(player)
	if not data then
		return nil
	end

	local strength, health = RollLogic.teamStats(data.Equipped or {}, data.StudXP)
	local stats = Modifiers.get(player)

	strength = math.floor(strength * stats.TeamStrength)
	health = math.floor(health * stats.TeamHealth)

	local team = teams[player]

	if not team then
		team = {
			hp = health,
			maxHp = health,
			strength = strength,
			knockedUntil = 0,
			retreatUntil = 0,
			sent = "",
		}

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

	if key == team.sent then
		return
	end

	team.sent = key

	StateSync.setVolatile(player, "Team", {
		Hp = hp,
		MaxHp = team.maxHp,
		Strength = team.strength,
		Fighting = fighting,
	})
end

--------------------------------------------------------------------------
-- Enemy models
--------------------------------------------------------------------------

local function hoverHeight(enemy: Enemy): number
	return 0.6 + enemy.size * 0.4
end

-- The server's enemy is an invisible proxy. EnemyVisuals builds the
-- visible monster on each client and glides it after this proxy.
-- The running event's enemy changes (Config.Events: Enemies), or nil.
local function eventEnemies(): { Glow: Color3?, Health: number?, Damage: number?, Reward: number?, Size: number? }?
	local def = RollLogic.eventById(ServerEffects.currentEvent())
	return if def then def.Enemies else nil
end

local function buildModel(enemy: Enemy): (Model, BasePart)
	local s = enemy.size

	local model = Instance.new("Model")
	model.Name = enemy.name

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(s, s * 0.8, s)
	body.CFrame = CFrame.new(enemy.home + Vector3.new(0, hoverHeight(enemy), 0))
	body.Color = enemy.def.Color:Lerp(
		Color3.new(0, 0, 0),
		if enemy.boss then 0.55 else 0.35
	)
	body.Transparency = 1
	body.Anchored = true
	body.CanCollide = false
	body.CanTouch = false
	body.CanQuery = false
	body.CastShadow = false
	body.Parent = model

	model.PrimaryPart = body

	model:SetAttribute("Color", body.Color)
	model:SetAttribute("Size", s)
	model:SetAttribute("EnemyId", enemy.id)
	model:SetAttribute("ZoneId", enemy.zoneId)
	model:SetAttribute("Level", enemy.def.Level)
	model:SetAttribute("Boss", enemy.boss)
	model:SetAttribute("ZoneBoss", if enemy.zoneBoss and not enemy.mega then true else nil)
	model:SetAttribute("MegaBoss", if enemy.mega then true else nil)
	local changes = eventEnemies()
	model:SetAttribute("Glow", if changes then changes.Glow else nil)
	model:SetAttribute("MaxHealth", enemy.maxHealth)
	model:SetAttribute("Health", enemy.maxHealth)

	CollectionService:AddTag(model, Tags.Enemy)
	model.Parent = folder

	return model, body
end

-- (Re)spawns at home, rolling whether this one is a Mini Boss.
local function spawnEnemy(enemy: Enemy)
	local def = enemy.def
	local mega = enemy.mega and enemy.mega.MegaBoss

	if mega then
		local zone = Zones.ById[enemy.zoneId]
		enemy.boss = true
		enemy.maxHealth = math.floor(def.Health * mega.Health)
		enemy.damage = def.Damage * mega.Damage
		enemy.reward = math.floor(def.Reward * mega.Reward)
		enemy.size = def.Size * mega.Size
		enemy.name = `{if zone then zone.Name else "Zone"} Mega Boss`
	elseif enemy.zoneBoss then
		local zoneBoss = Config.ZoneBoss
		local zone = Zones.ById[enemy.zoneId]

		enemy.boss = true
		enemy.maxHealth = math.floor(def.Health * zoneBoss.Health)
		enemy.damage = def.Damage * zoneBoss.Damage
		enemy.reward = math.floor(def.Reward * zoneBoss.Reward)
		enemy.size = def.Size * zoneBoss.Size
		enemy.name = `{if zone then zone.Name else "Zone"} Titan`
	else
		enemy.boss = enemy.forceBoss or rng:NextNumber() < Settings.BossChance
		enemy.maxHealth = math.floor(def.Health * (if enemy.boss then Settings.BossHealth else 1))
		enemy.damage = def.Damage * (if enemy.boss then Settings.BossDamage else 1)
		enemy.reward = math.floor(def.Reward * (if enemy.boss then Settings.BossReward else 1))
		enemy.size = def.Size * (if enemy.boss then Settings.BossSize else 1)
		enemy.name = if enemy.boss then `Mini Boss {def.Name}` else def.Name
	end

	-- Event changes (Blood Moon...) on everything but Mega Bosses.
	local changes = if mega then nil else eventEnemies()
	if changes then
		enemy.maxHealth = math.floor(enemy.maxHealth * (changes.Health or 1))
		enemy.damage *= changes.Damage or 1
		enemy.reward = math.floor(enemy.reward * (changes.Reward or 1))
		enemy.size *= changes.Size or 1
	end

	table.clear(enemy.damageBy)

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

	if enemy.boss and not enemy.zoneBoss then
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)

			if root and (root.Position - enemy.home).Magnitude < Settings.WakeRange then
				notify(player, `A {enemy.name} appeared!`, Color3.fromRGB(255, 205, 60))
			end
		end
	end
end

--------------------------------------------------------------------------
-- Zones and spawn positions
--------------------------------------------------------------------------

-- The zone's Center attribute, else the middle of its bounding box.
local function zoneCenter(zone: Instance): Vector3?
	local center = zone:GetAttribute(Tags.Attr.Center)

	if typeof(center) == "Vector3" then
		return center
	end

	local cframe = Tags.zoneBox(zone)

	return if cframe then cframe.Position else nil
end

-- Normal enemy capacity: one per AreaPerEnemy square studs of floor.
local function getMaxEnemiesForZone(zone: Instance): number
	local zoneSize = zone:GetAttribute(Tags.Attr.ZoneSize)
	if typeof(zoneSize) ~= "Vector3" then
		local _, size = Tags.zoneBox(zone)
		zoneSize = size or Vector3.new(100, 0, 100)
	end
	local area = zoneSize.X * zoneSize.Z
	return math.clamp(math.floor(area / Settings.AreaPerEnemy), Settings.MinPerZone, Settings.MaxPerZone)
end

-- Checks that an enemy has enough clear space above its spawn position.
-- EnemyGround and EnemySpawn parts are ignored because they are intentional
-- ground/marker geometry. Other scenery and obstacles are not ignored.
local function hasSpawnClearance(position: Vector3): boolean
	local excluded: { Instance } = {}

	for _, part in CollectionService:GetTagged(Tags.EnemyGround) do
		table.insert(excluded, part)
	end

	for _, part in CollectionService:GetTagged(Tags.EnemySpawn) do
		table.insert(excluded, part)
	end

	-- Ignore the invisible enemy proxy folder.
	table.insert(excluded, folder)

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded

	-- Clearance space: 6 studs wide, 8 studs tall, 6 studs deep, starting just
	-- above the surface (so the floor itself never counts).
	local checkSize = Vector3.new(6, 8, 6)
	local checkPosition = position + Vector3.new(0, 4.5, 0)

	local overlaps = workspace:GetPartBoundsInBox(
		CFrame.new(checkPosition),
		checkSize,
		params
	)

	return #overlaps == 0
end

-- Where a zone's enemies live: its EnemySpawn markers (in random order),
-- then random clear spots on its ground, up to the zone's capacity. Ground
-- is its EnemyGround parts, or, when it has none, the zone's own geometry.
local function spotsFor(zone: Instance, zoneId: string): { Vector3 }
	local spots: { Vector3 } = {}
	local capacity = getMaxEnemiesForZone(zone)

	local groundParts: { Instance } = {}
	for _, ground in CollectionService:GetTagged(Tags.EnemyGround) do
		if ground:IsA("BasePart") and ground:IsDescendantOf(zone) then
			table.insert(groundParts, ground)
		end
	end
	if #groundParts == 0 then
		warn(`[Combat] {zoneId} has no EnemyGround parts; using the zone itself as ground`)
		groundParts = { zone }
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = groundParts
	params.IgnoreWater = true

	local function tryPosition(position: Vector3)
		if #spots >= capacity then return end
		local result = workspace:Raycast(position + Vector3.new(0, 250, 0), Vector3.new(0, -750, 0), params)
		if not result then return end
		if result.Normal.Y < 0.7 then return end -- too steep
		if not hasSpawnClearance(result.Position) then return end -- scenery in the way
		for _, other in spots do
			if (other - result.Position).Magnitude < 8 then return end -- too close to another
		end
		table.insert(spots, result.Position)
	end

	-- The placed markers first, in random order.
	local markers = {}
	for _, spawnPart in Tags.forZone(Tags.EnemySpawn, zoneId) do
		if spawnPart:IsA("BasePart") then
			table.insert(markers, spawnPart.Position)
		end
	end
	for i = #markers, 2, -1 do
		local j = rng:NextInteger(1, i)
		markers[i], markers[j] = markers[j], markers[i]
	end
	for _, position in markers do
		tryPosition(position)
	end

	-- Then random spots on the ground.
	local center = zoneCenter(zone)
	local _, size = Tags.zoneBox(zone)
	if center and size then
		for _ = 1, capacity * 12 do
			if #spots >= capacity then break end
			tryPosition(center + Vector3.new(rng:NextNumber(-0.45, 0.45) * size.X, 0, rng:NextNumber(-0.45, 0.45) * size.Z))
		end
	end

	if #spots == 0 then
		warn(`[Combat] No valid enemy spawn positions found for {zoneId}`)
	end
	return spots
end

--------------------------------------------------------------------------
-- Enemy creation and zone scanning
--------------------------------------------------------------------------

local function scanZones()
	for _, zone in CollectionService:GetTagged(Tags.Zone) do
		local id = Tags.idOfZone(zone)

		if Zones.ById[id] and not zoneStates[zone] then
			zoneStates[zone] = {
				zone = zone,
				id = id,
				spawned = false,
				active = false,
			}
		end
	end
end

local function addEnemy(
	zoneId: string,
	home: Vector3,
	zoneBoss: boolean?,
	summoned: boolean?,
	mega: Config.EventDef?
): Enemy?
	local def = Enemies.forZone(zoneId)

	if not def then
		warn(`[Combat] No enemy definition found for zone {zoneId}`)
		return nil
	end

	-- Find the physical zone.
	local zone: Instance? = nil

	for instance, state in zoneStates do
		if state.id == zoneId and instance.Parent then
			zone = instance
			break
		end
	end

	if not zone then
		warn(`[Combat] Cannot spawn enemy: zone {zoneId} was not found`)
		return nil
	end

	-- Special enemies do not consume the normal enemy capacity.
	-- This prevents a full zone from blocking Titans or summoned bosses.
	if not zoneBoss and not summoned and not mega then
		local maxEnemies = getMaxEnemiesForZone(zone)
		local currentEnemies = 0

		-- Count normal enemies, including defeated enemies waiting to respawn.
		for _, existing in enemies do
			if existing.zoneId == zoneId and not existing.zoneBoss and not existing.summoned then
				currentEnemies += 1
			end
		end

		if currentEnemies >= maxEnemies then
			return nil
		end
	end

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

		zoneBoss = zoneBoss == true or mega ~= nil,
		mega = mega,
		forceBoss = summoned == true,
		summoned = summoned == true,
		damageBy = {},
		expiresAt = if mega then math.huge elseif zoneBoss then os.clock() + Config.ZoneBoss.Lifetime else math.huge,

		chasing = nil,
		goal = nil,
		waypoints = {},
		waypoint = 1,
		pathing = false,
		lastPath = 0,
		blocked = nil,
		nextWander = 0,
	}

	register(enemy)
	spawnEnemy(enemy)

	return enemy
end

local function zoneNear(zone: Instance): boolean
	local cframe, size = Tags.zoneBox(zone)

	if not (cframe and size) then
		return false
	end

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

				local spots = spotsFor(zone, state.id)

				for _, spot in spots do
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

	if enemy.pathing or not enemy.body then
		return
	end

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

		if not enemy.alive then
			return
		end

		local points: { Vector3 } = {}

		if ok and path.Status == Enum.PathStatus.Success then
			for _, waypoint in path:GetWaypoints() do
				table.insert(points, waypoint.Position)
			end

			-- Something moved into the way further along: re-path next step.
			if enemy.blocked then
				enemy.blocked:Disconnect()
			end

			enemy.blocked = path.Blocked:Connect(function(index)
				if index >= enemy.waypoint then
					enemy.lastPath = 0
					enemy.goal = nil
				end
			end)
		end

		if #points == 0 then
			points = { goal }
		end

		enemy.waypoints = points
		enemy.waypoint = math.min(2, #points)
	end)
end

-- Steps the enemy along its waypoints at speed.
local function walk(enemy: Enemy, dt: number, speed: number, stop: number): boolean
	local body = enemy.body

	if not body then
		return true
	end

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

	if distance < 0.05 then
		return false
	end

	local move = offset.Unit * math.min(distance, speed * dt)

	-- Separation: don't walk into or stack on other enemies (of this zone).
	for _, other in byZone[enemy.zoneId] or enemies do
		local otherBody = other.body

		if other ~= enemy and other.alive and otherBody then
			local away = flat(
				here - (otherBody.Position - Vector3.new(0, hoverHeight(other), 0))
			)

			local gap = away.Magnitude
			local room = (enemy.size + other.size) * 0.5 + 1

			if gap < room and gap > 0.01 then
				move += away.Unit * (room - gap) * math.min(1, dt * 6)
			end
		end
	end

	local nextPos = here + move

	-- Follow the ground the path walks on.
	nextPos = Vector3.new(
		nextPos.X,
		here.Y + (target.Y - here.Y) * math.clamp(speed * dt / math.max(distance, 0.1), 0, 1),
		nextPos.Z
	)

	local lifted = nextPos + Vector3.new(0, hoverHeight(enemy), 0)
	body.CFrame = CFrame.lookAt(lifted, lifted + move)

	return false
end

local function face(enemy: Enemy, position: Vector3)
	local body = enemy.body

	if not body then
		return
	end

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

	if not body then
		return nil, nil
	end

	local best: Player? = nil
	local bestRoot: BasePart? = nil
	local bestDistance = Settings.AggroRange

	for _, player in Players:GetPlayers() do
		local root = rootOf(player)

		if root and Economy.ownsZone(player, enemy.zoneId) then
			local distance = (root.Position - body.Position).Magnitude
			local fightingIt = enemy.fighters[player] == true

			if (distance < bestDistance or fightingIt)
				and (root.Position - enemy.home).Magnitude < Settings.HomeRadius + Settings.AggroRange then

				best = player
				bestRoot = root
				bestDistance = if fightingIt then -1 else distance
			end
		end
	end

	return best, bestRoot
end

local function move(dt: number)
	local now = os.clock()

	for _, enemy in enemies do
		local body = enemy.body

		if not (enemy.alive and body and activeZones[enemy.zoneId]) then
			continue
		end

		local prey, root = preyOf(enemy)
		local here = body.Position

		-- Once leashed it must get well back inside before it chases again.
		local leash = if enemy.chasing then Settings.HomeRadius else Settings.HomeRadius * 0.6

		if prey and root and flat(here - enemy.home).Magnitude < leash then
			-- Chase: re-path when the player has moved on.
			if enemy.chasing ~= prey and enemy.model then
				enemy.model:SetAttribute("Hunting", prey.UserId)
			end

			enemy.chasing = prey

			local stop = enemy.size / 2 + 4
			local goal = root.Position - Vector3.new(0, 3, 0)

			if not enemy.goal
				or (now - enemy.lastPath > Settings.RepathTime and flat(goal - enemy.goal).Magnitude > 3) then

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

				enemy.goal = enemy.home + Vector3.new(
					math.cos(angle) * distance,
					0,
					math.sin(angle) * distance
				)

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

	if current == enemy then
		return
	end

	if current then
		current.fighters[player] = nil

		-- Left alone, it shakes the fight off (Titans don't: it's a raid).
		if next(current.fighters) == nil and current.alive and not current.zoneBoss then
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

-- The nearest live enemy within range of the player, in a zone they own.
local function nearestEnemy(player: Player, range: number, except: Enemy?): Enemy?
	local root = rootOf(player)

	if not root then
		return nil
	end

	local best: Enemy? = nil
	local bestDistance = range

	for _, enemy in enemies do
		local body = enemy.body

		if enemy ~= except and enemy.alive and body and Economy.ownsZone(player, enemy.zoneId) then
			local distance = (body.Position - root.Position).Magnitude

			if distance < bestDistance then
				best = enemy
				bestDistance = distance
			end
		end
	end

	return best
end

local function canFight(player: Player, team: Team?): boolean
	local now = os.clock()

	return team ~= nil
		and team.strength > 0
		and now >= team.knockedUntil
		and now >= team.retreatUntil
end

-- Zone Boss damage ranks, best first.
local function rankings(enemy: Enemy): { { player: Player, damage: number } }
	local list: { { player: Player, damage: number } } = {}

	for player, damage in enemy.damageBy do
		if player.Parent == Players and damage > 0 then
			table.insert(list, {
				player = player,
				damage = damage,
			})
		end
	end

	table.sort(list, function(a, b)
		return a.damage > b.damage
	end)

	return list
end

local function topBoard(
	list: { { player: Player, damage: number } }
): { { Name: string, Damage: number } }
	local board = {}

	for i = 1, math.min(5, #list) do
		table.insert(board, {
			Name = list[i].player.DisplayName,
			Damage = math.floor(list[i].damage),
		})
	end

	return board
end

local function rankRewards(
	rank: number
): { Top: number, Clacks: number, FreeRolls: number, Spins: number }
	for _, tier in Config.ZoneBoss.Ranks do
		if rank <= tier.Top then
			return tier
		end
	end

	return Config.ZoneBoss.Ranks[#Config.ZoneBoss.Ranks]
end

-- Gone without a defeat (a Zone Boss that escaped): no rewards.
local function removeEnemy(enemy: Enemy)
	enemy.alive = false

	local fighters = table.clone(enemy.fighters)
	table.clear(enemy.fighters)

	for player in fighters do
		setFight(player, nil)
	end

	if enemy.model then
		enemy.model:Destroy()
	end

	enemy.model = nil
	enemy.body = nil

	if enemy.blocked then
		enemy.blocked:Disconnect()
		enemy.blocked = nil
	end

	unregister(enemy)
end

local function defeat(enemy: Enemy)
	enemy.alive = false

	local fighters = table.clone(enemy.fighters)

	-- Who gets paid: the fighters, or for a Zone Boss everyone who hit it.
	local ranks: { [Player]: number } = {}
	local paid: { [Player]: boolean } = fighters
	local ranking: { { player: Player, damage: number } } = {}

	if enemy.zoneBoss then
		ranking = rankings(enemy)
		paid = {}

		for rank, row in ranking do
			ranks[row.player] = rank
			paid[row.player] = true
		end
	end

	for player in paid do
		local data = PlayerData.get(player)

		if data then
			-- Kill streak: chain defeats inside the window.
			local now = os.clock()
			local existing = streaks[player]

			local streak: Streak = if existing and now - existing.last <= Settings.StreakWindow
				then existing
				else { count = 0, last = now }

			streak.count = math.min(streak.count + 1, Settings.StreakMax)
			streak.last = now
			streaks[player] = streak

			player:SetAttribute("KillStreak", streak.count)

			local streakBonus = 1 + (streak.count - 1) * Settings.StreakBonus
			local rank = ranks[player]
			local tier = if rank then rankRewards(rank) else nil

			-- Paid by the player's whole Clacks multiplier.
			local amount = math.floor(
				enemy.reward
					* Modifiers.get(player).ClackMultiplier
					* streakBonus
					* (if tier then tier.Clacks else 1)
			)

			Economy.addClacks(player, amount)

			local extra = ""

			if tier then
				if tier.FreeRolls > 0 then
					Economy.addFreeRolls(player, tier.FreeRolls, true)
					extra ..= ` +{tier.FreeRolls} Rolls`
				end

				if tier.Spins > 0 then
					RewardService.addSpins(player, tier.Spins)
					extra ..= ` +{tier.Spins} Spin{if tier.Spins > 1 then "s" else ""}`
				end
			elseif rng:NextNumber() < Settings.FreeRollChance * (if enemy.boss then 5 else 1) then
				Economy.addFreeRolls(player, if enemy.boss then 3 else 1, true)
				extra = if enemy.boss then " +3 Rolls" else " +1 Roll"
			end

			data.EnemiesDefeated += 1
			StateSync.push(player, "EnemiesDefeated", data.EnemiesDefeated)

			-- Every equipped stud earns XP, once per stud, however many copies.
			local levels = Config.Levels
			local xp = math.floor(
				(levels.XpPerDefeat + levels.XpPerEnemyLevel * enemy.def.Level)
					* (if enemy.boss then levels.BossXp else 1)
					* (if enemy.zoneBoss then 4 else 1)
					* (if Products.ownsPass(player, "StudTrainer") then 2 else 1)
			)

			local seen: { [string]: boolean } = {}

			for _, key in data.Equipped do
				local def = RollLogic.decodeKey(key)

				if def and not seen[def.Id] then
					seen[def.Id] = true
					data.StudXP[def.Id] = (data.StudXP[def.Id] or 0) + xp
				end
			end

			StateSync.push(player, "StudXP", data.StudXP)

			if enemy.boss then
				Drops.roll(
					player,
					if enemy.zoneBoss then Config.Drops.ZoneBossLuck else Config.Drops.MiniBossLuck,
					enemy.def.Level
				)
			end

			-- Rare drops: variant boosts (Big Roll, Shiny Roll).
			local dropBonus = if enemy.zoneBoss
				then Settings.TitanDropBonus
				elseif enemy.boss
				then Settings.BossDropBonus
				else 1

			for _, drop in Settings.RareDrops do
				if rng:NextNumber() < drop.Chance * dropBonus * Modifiers.get(player).DropLuck then
					local boost = Config.Boosts[drop.Boost]

					if boost and Boosts.add(player, drop.Boost, boost.Duration) then
						Net.fire(player, "Notify", {
							Kind = "RareDrop",
							Boost = drop.Boost,
							Text = `RARE DROP! {boost.Name}: {boost.Short} chance for {math.floor(boost.Duration / 60)} min`,
							Color = boost.Color,
						})
					end
				end
			end

			if rank then
				notify(
					player,
					`{enemy.name} defeated! You placed #{rank} · +{shortNumber(amount)} Clacks{extra}`,
					Color3.fromRGB(255, 205, 60)
				)

				Net.fire(player, "ZoneBoss", {
					Phase = "Result",
					Name = enemy.name,
					Rank = rank,
					Amount = amount,
					Of = #ranking,
				})
			else
				local streakText = if streak.count > 1 then ` (Streak x{streak.count})` else ""

				notify(
					player,
					`Defeated {enemy.name}! +{shortNumber(amount)} Clacks{extra}{streakText}`,
					Color3.fromRGB(255, 215, 90)
				)
			end

			Combat.Defeated:Fire(player, enemy.boss, enemy.zoneBoss)
		end
	end

	if enemy.zoneBoss then
		Net.fireAll("ZoneBoss", {
			Phase = "Defeated",
			Name = enemy.name,
			ZoneId = enemy.zoneId,
			Board = topBoard(ranking),
		})
	end

	if enemy.model then
		enemy.model:SetAttribute("Health", 0)
		enemy.model:Destroy()
	end

	enemy.model = nil
	enemy.body = nil

	if enemy.blocked then
		enemy.blocked:Disconnect()
		enemy.blocked = nil
	end

	table.clear(enemy.fighters)

	-- The studs move on to the next enemy nearby, or come home.
	for player in fighters do
		local nextEnemy = if canFight(player, teams[player])
			then nearestEnemy(player, Settings.RetargetRange, enemy)
			else nil

		setFight(player, nextEnemy)
	end

	if enemy.zoneBoss or enemy.summoned then
		unregister(enemy)
		return
	end

	-- Keep the normal enemy's capacity slot reserved while it respawns.
	task.delay(Settings.Respawn, function()
		if enemies[enemy.id] == enemy and not enemy.alive then
			spawnEnemy(enemy)
		end
	end)
end

--------------------------------------------------------------------------
-- Zone Bosses
--------------------------------------------------------------------------

-- The owned zone the player stands in, if any.
local function zoneAt(player: Player, position: Vector3): string?
	scanZones()

	for zone, state in zoneStates do
		local cframe, size = Tags.zoneBox(zone)

		if cframe and size and Economy.ownsZone(player, state.id) then
			local localPoint = cframe:PointToObjectSpace(position)

			if math.abs(localPoint.X) <= size.X / 2
				and math.abs(localPoint.Z) <= size.Z / 2 then

				return state.id
			end
		end
	end

	return nil
end

-- Summon Mini Boss (a product): a crowned Mini Boss of the zone the player
-- stands in, just in front of them. False when they aren't in a zone they
-- own (the product falls back to spins).
function Combat.summonMiniBoss(player: Player): boolean
	local root = rootOf(player)

	if not root then
		return false
	end

	local zoneId = zoneAt(player, root.Position)

	if not zoneId then
		return false
	end

	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local ahead = if look.Magnitude > 0.01
		then look.Unit * 14
		else Vector3.new(0, 0, -14)

	local enemy = addEnemy(
		zoneId,
		root.Position - Vector3.new(0, 3, 0) + ahead,
		false,
		true
	)

	if not enemy then
		return false
	end

	Net.fireAll("Announce", {
		Player = player.DisplayName,
		UserId = player.UserId,
		Summon = true,
		Name = enemy.name,
	})

	return true
end

-- Spawns a Titan in every Every-th zone that's on the map and has none.
function Combat.spawnZoneBosses(): { string }
	scanZones()

	local spawned: { string } = {}

	for zone, state in zoneStates do
		local def = Zones.ById[state.id]

		if not (def and zone.Parent and def.Order % Config.ZoneBoss.Every == 0) then
			continue
		end

		local exists = false

		for _, enemy in enemies do
			if enemy.zoneBoss and not enemy.mega and enemy.zoneId == state.id and enemy.alive then
				exists = true
				break
			end
		end

		local center = zoneCenter(zone)

		if not exists and center then
			local enemy = addEnemy(state.id, center, true)

			if enemy then
				table.insert(spawned, def.Name)
			end
		end
	end

	if #spawned > 0 then
		table.sort(spawned)

		Net.fireAll("ZoneBoss", {
			Phase = "Spawn",
			Zones = spawned,
			Lifetime = Config.ZoneBoss.Lifetime,
		})
	end

	return spawned
end

-- Live damage ranks to everyone near each Titan; escapes when time's up.
local function updateZoneBosses()
	for _, enemy in enemies do
		if not (enemy.zoneBoss and enemy.alive) then
			continue
		end

		if os.clock() > enemy.expiresAt then
			Net.fireAll("ZoneBoss", {
				Phase = "Escaped",
				Name = enemy.name,
				ZoneId = enemy.zoneId,
			})

			removeEnemy(enemy)
			continue
		end

		local body = enemy.body

		if not body then
			continue
		end

		local ranking = rankings(enemy)
		local board = topBoard(ranking)

		for _, player in Players:GetPlayers() do
			local root = rootOf(player)

			if root and (root.Position - body.Position).Magnitude < Settings.WakeRange then
				local mine = 0
				local rank = nil

				for i, row in ranking do
					if row.player == player then
						mine = math.floor(row.damage)
						rank = i
					end
				end

				Net.fire(player, "ZoneBoss", {
					Phase = "Board",
					Id = enemy.id,
					Name = enemy.name,
					Board = board,
					Mine = mine,
					Rank = rank,
					Left = math.max(0, math.floor(enemy.expiresAt - os.clock())),
				})
			end
		end
	end
end

--------------------------------------------------------------------------
-- Events: enemy glow and the Mega Boss
--------------------------------------------------------------------------

-- A Mega Boss in each zone players stand in (most players first).
function Combat.spawnMegaBosses(event: Config.EventDef): { string }
	local mega = event.MegaBoss
	if not mega then return {} end
	scanZones()

	local counts: { [string]: number } = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local zoneId = if root then zoneAt(player, root.Position) else nil
		if zoneId then
			counts[zoneId] = (counts[zoneId] or 0) + 1
		end
	end
	local order = {}
	for zoneId in counts do
		table.insert(order, zoneId)
	end
	table.sort(order, function(a, b)
		return counts[a] > counts[b]
	end)

	local spawned: { string } = {}
	for i = 1, math.min(#order, mega.MaxZones) do
		local zoneId = order[i]
		local zone: Instance? = nil
		for instance, state in zoneStates do
			if state.id == zoneId and instance.Parent then
				zone = instance
			end
		end
		local center = zone and zoneCenter(zone)
		if center then
			local enemy = addEnemy(zoneId, center, true, false, event)
			if enemy then
				table.insert(spawned, enemy.name)
			end
		end
	end
	if #spawned > 0 then
		Net.fireAll("ZoneBoss", { Phase = "Spawn", Zones = spawned, Lifetime = 0, Mega = true })
	end
	return spawned
end

-- The event ended: Mega Bosses leave.
local function removeMegaBosses()
	for _, enemy in enemies do
		if enemy.mega and enemy.alive then
			Net.fireAll("ZoneBoss", { Phase = "Escaped", Name = enemy.name, ZoneId = enemy.zoneId })
			removeEnemy(enemy)
		end
	end
end

local function onEventChanged(_id: string?, def: Config.EventDef?)
	-- Glow on every enemy alive now (stats change as they respawn).
	local glow = if def and def.Enemies then def.Enemies.Glow else nil
	for _, enemy in enemies do
		if enemy.model then
			enemy.model:SetAttribute("Glow", glow)
		end
	end
	removeMegaBosses()
	if def and def.MegaBoss then
		Combat.spawnMegaBosses(def)
	end
end

-- The clock: Warning, then Spawn, at the same times on every server.
local function zoneBossClock()
	local interval = Config.ZoneBoss.Interval
	local lastSlot = math.floor(os.time() / interval)
	local warned = -1

	while true do
		task.wait(1)

		local now = os.time()
		local slot = math.floor(now / interval)
		local nextAt = (slot + 1) * interval

		if nextAt - now <= Config.ZoneBoss.Warning and warned ~= slot then
			warned = slot

			Net.fireAll("ZoneBoss", {
				Phase = "Warning",
				In = nextAt - now,
			})
		end

		if slot ~= lastSlot then
			lastSlot = slot
			Combat.spawnZoneBosses()
		end

		updateZoneBosses()
	end
end

--------------------------------------------------------------------------
-- Combat update
--------------------------------------------------------------------------

local function knockout(player: Player, team: Team)
	team.hp = 0
	team.knockedUntil = os.clock() + Settings.KnockoutCooldown

	setFight(player, nil)

	notify(
		player,
		"Your studs were knocked out! Equip stronger studs or avoid this enemy.",
		Color3.fromRGB(255, 110, 110)
	)
end

local function step(dt: number)
	for _, player in Players:GetPlayers() do
		local team = teamOf(player)

		if not team then
			continue
		end

		local root = rootOf(player)
		local enemy = fights[player]

		-- Drop fights that no longer make sense.
		if enemy and (
			not enemy.alive
				or not enemy.body
				or not root
				or not canFight(player, team)
				or (root.Position - enemy.body.Position).Magnitude > Settings.LeashRange
			) then
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
			-- kills faster than MinFightTime.
			if os.clock() - (engagedAt[player] or 0) >= Settings.ArriveTime then
				local dps = math.min(team.strength, enemy.maxHealth / Settings.MinFightTime)

				if rng:NextNumber() < Settings.CritChance then
					dps *= Settings.CritMultiplier

					if enemy.model then
						local crits = enemy.model:GetAttribute("Crits")

						enemy.model:SetAttribute(
							"Crits",
							(if typeof(crits) == "number" then crits else 0) + 1
						)
					end
				end

				enemy.health -= dps * dt

				if enemy.zoneBoss then
					enemy.damageBy[player] = (enemy.damageBy[player] or 0) + dps * dt
				end

				team.hp -= enemy.damage * dt

				if team.hp <= 0 then
					knockout(player, team)
				end
			end
		elseif team.hp < team.maxHp then
			team.hp = math.min(
				team.maxHp,
				team.hp + team.maxHp * Settings.RegenPerSecond * dt
			)
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

	-- Summon Mini Boss product. Never throws: no valid zone → 2 spins instead.
	Products.registerAction("SummonBoss", function(player)
		if not Combat.summonMiniBoss(player) then
			RewardService.addSpins(player, 2)

			notify(
				player,
				"Stand in a zone you own to summon a Mini Boss. Here are 2 Jackpot Spins instead!",
				Color3.fromRGB(255, 205, 60)
			)
		end
	end)

	-- RETREAT: studs come home and stay out of fights for a moment.
	Net.handle("StopFight", {
		Rate = 2,
		Burst = 4,
	}, function(player)
		local team = teams[player]

		if team then
			team.retreatUntil = os.clock() + Settings.RetreatCooldown
		end

		setFight(player, nil)

		return {
			Ok = true,
		}
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

	-- 20 updates a second: clients interpolate between them (EnemyVisuals).
	local pending = 0

	RunService.Heartbeat:Connect(function(dt)
		pending += dt

		if pending >= MOVE_STEP then
			move(math.min(pending, 0.25))
			pending = 0
		end
	end)

	task.spawn(zoneBossClock)

	ServerEffects.EventChanged:Connect(onEventChanged)
	-- An event already running at boot (zones load first).
	task.delay(5, function()
		local running = RollLogic.eventById(ServerEffects.currentEvent())
		if running then
			onEventChanged(running.Id, running)
		end
	end)

	while true do
		local dt = task.wait(Settings.Tick)
		step(dt)
	end
end

return Combat
