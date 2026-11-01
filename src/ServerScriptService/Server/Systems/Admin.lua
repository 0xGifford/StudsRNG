--[[

Admin
ModuleScript
/ServerScriptService/Server/Systems/Admin

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The admin panel's server side. The panel (MenuSystem AdminPanel, the
-- Admin ScreenGui) is built from Shared/AdminConfig and asks through
-- ReplicatedStorage.AdminRemotes.Admin:
--   { Action = "List" }                     everyone in this server
--   { Action = "Inspect", Target = userId } one player's summary
--   { Action = "Log" }                      the latest actions
--   { Action = <id>, Targets = { userId, ... }, Args = { ... } }
--   -> { ok, message, data }
-- AdminRemotes.Announcement (RemoteEvent: text, sender, title) carries
-- announcements to clients (MenuSystem Announcements shows them).
-- Each AdminConfig action has an ACTIONS entry below saying what it does.
--
-- Roles and permissions: Config.Admin. Each player's role is worked out when
-- they join and set as their "AdminRole" attribute, with IsAdmin = true (the
-- panel's ScreenGui is deleted for everyone else). Every request is checked
-- again here: the role must have the action's Permission, and a role can only
-- act on players of a lower rank.
--
--   Players     edit (Clacks, Free Rolls, Spins, Lucky Rolls, Rebirths, zones,
--               studs, boosts) or reset the selected players, or any UserId. In this
--               server: at once. Elsewhere or offline: a ProfileStore message
--               applied the next time (or, if they're playing in another
--               server, within a minute) their save is open.
--   Everyone    Reset economy / Reset all bump a saved "epoch": every save
--               older than it is reset when it next loads, and every server
--               resets its players right away (MessagingService).
--   Moderation  Kick (any server), TempBan (minutes) and Ban, kept in a
--               DataStore and checked on join, plus Roblox's own ban
--               (Players:BanAsync) where it's available. Unban lifts both.
--   Events      run / stop any Config.Events event here or in every server.
--   Announce    a banner for everyone here or in every server.
-- Every action is logged (the panel's Log tab, the output, and the "Log" key
-- of the admin DataStore).

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local AdminConfig = require(Shared.AdminConfig)
local RollLogic = require(Shared.Util.RollLogic)
local Zones = require(Shared.Zones)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local Economy = require(Systems.Economy)
local Inventory = require(Systems.Inventory)
local Modifiers = require(Systems.Modifiers)
local Boosts = require(Systems.Boosts)
local ServerEffects = require(Systems.ServerEffects)

local Admin = {}

local Roles = Config.Admin
local TOPIC = "StudsAdmin_v1"
local STORE_NAME = "StudsAdmin_v1"
local BAN_STORE_NAME = "StudsBans_v1"
local LOG_LIMIT = 200
local MAX_GRANT = 100
local SERVER_ID = if game.JobId ~= "" then game.JobId else "studio"

local MAX_TARGETS = 50
local LOG_SIZE = 60

type Result = { ok: boolean, message: string?, data: any? }

local adminStore: DataStore? = nil
local banStore: DataStore? = nil
local epochs = { Economy = 0, All = 0 }

--------------------------------------------------------------------------
-- Roles
--------------------------------------------------------------------------

local roles: { [Player]: string } = {}

local function rankOf(role: string?): number
	local def = if role then Roles.Roles[role] else nil
	return if def then def.Rank else 0
end

local function topRank(): number
	local best = 0
	for _, def in Roles.Roles do
		best = math.max(best, def.Rank)
	end
	return best
end

local function isCreator(player: Player): boolean
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(function()
		return player:GetRankInGroup(game.CreatorId)
	end)
	return ok and rank == 255
end

local function resolveRole(player: Player): string?
	if RunService:IsStudio() and Roles.StudioRole then
		return Roles.StudioRole
	end
	if isCreator(player) then
		return Roles.CreatorRole
	end
	local listed = Roles.Users[player.UserId]
	if listed and Roles.Roles[listed] then
		return listed
	end
	for _, rule in Roles.Groups do
		local ok, rank = pcall(function()
			return player:GetRankInGroup(rule.GroupId)
		end)
		if ok and rank >= rule.MinRank and Roles.Roles[rule.Role] then
			return rule.Role
		end
	end
	return nil
end

local function can(player: Player, permission: string): boolean
	local role = roles[player]
	local def = if role then Roles.Roles[role] else nil
	if not def then return false end
	for _, granted in def.Permissions do
		if granted == "*" or granted == permission then
			return true
		end
	end
	return false
end

-- A role acts only on lower ranks (the top role on anyone, itself included).
local function outranks(actor: Player, targetUserId: number): boolean
	local actorRank = rankOf(roles[actor])
	if actorRank >= topRank() then return true end
	if targetUserId == actor.UserId then return true end
	local target = Players:GetPlayerByUserId(targetUserId)
	local targetRole = if target then roles[target] else Roles.Users[targetUserId]
	return rankOf(targetRole) < actorRank
end

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local recent: { string } = {} -- for the panel's Log tab, newest first

local function log(actor: Player?, action: string, detail: string)
	local line = `{os.date("!%H:%M")}  {if actor then actor.Name else "system"} · {action}{if detail ~= "" then ` · {detail}` else ""}`
	table.insert(recent, 1, line)
	while #recent > LOG_SIZE do
		table.remove(recent)
	end
	print("[Admin] " .. line)
	local store = adminStore
	if not store then return end
	task.spawn(function()
		pcall(function()
			store:UpdateAsync("Log", function(old: any)
				local list = if typeof(old) == "table" then old else {}
				table.insert(list, 1, { At = os.time(), By = if actor then actor.UserId else 0, Action = action, Detail = detail })
				while #list > LOG_LIMIT do
					table.remove(list)
				end
				return list
			end)
		end)
	end)
end

local function publish(message: { [string]: any })
	message.Server = SERVER_ID
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:PublishAsync(TOPIC, message)
		end)
		if not ok then
			warn(`[Admin] cross-server message failed: {err}`)
		end
	end)
end

local function nameOf(userId: number): string
	local online = Players:GetPlayerByUserId(userId)
	if online then return online.Name end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	return if ok and name then name else tostring(userId)
end

local function notify(player: Player, text: string)
	Net.fire(player, "Notify", { Text = text, Color = Color3.fromRGB(255, 205, 60) })
end

local function commas(n: number): string
	local text = tostring(math.floor(n))
	return (text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- Pushes every saved field to the client and refreshes cached stats.
local function resync(player: Player)
	local data = PlayerData.get(player)
	if not data then return end
	for field, value in data :: any do
		if field ~= "Version" and field ~= "PurchaseIds" then
			StateSync.push(player, field, value)
		end
	end
	Inventory.refresh(player)
	Economy.refreshLeaderstats(player)
	Modifiers.invalidate(player)
end

--------------------------------------------------------------------------
-- Editing saves
--------------------------------------------------------------------------
-- An edit is an op table, applied straight away to a player whose save is
-- open in this server, else queued on their save (PlayerData.message) and
-- applied by PlayerData.Message the next time it opens.

-- Wipes a save (keeping Config.Admin.KeepOnReset). The player rejoins so
-- every system starts clean.
local function resetPlayer(player: Player, reason: string)
	local data: any = PlayerData.get(player)
	if not data then return end
	PlayerData.resetData(data, Roles.KeepOnReset)
	data.Epochs = { Economy = epochs.Economy, All = epochs.All }
	player:Kick(reason)
end

local function applyOp(player: Player, op: any): (boolean, string)
	local data: any = PlayerData.get(player)
	if not data then return false, "data not loaded yet" end
	local kind = op.Op
	if kind == "Currency" then
		local field = AdminConfig.CURRENCIES[op.Kind]
		local amount = tonumber(op.Amount)
		if not field or not amount then return false, "bad currency" end
		local before = tonumber(data[field]) or 0
		data[field] = math.max(0, math.floor(if op.Mode == "Set" then amount else before + amount))
		if op.Notify then
			notify(player, if op.Mode == "Set"
				then `An admin set your {op.Kind} to {commas(data[field])}.`
				else `You received {commas(amount)} {op.Kind}!`)
		end
		resync(player)
		return true, `{op.Kind} {if op.Mode == "Set" then "=" else "+"} {commas(amount)}`
	elseif kind == "Progress" then
		local done = {}
		if tonumber(op.Rebirths) then
			data.Rebirths = math.max(0, math.floor(op.Rebirths))
			table.insert(done, `rebirths = {data.Rebirths}`)
		end
		if tonumber(op.Zones) then
			local count = math.clamp(math.floor(op.Zones), 1, #Zones.List)
			local unlocked = {}
			for i = 1, count do
				unlocked[Zones.List[i].Id] = true
			end
			data.UnlockedWorlds = unlocked
			table.insert(done, `zones = {count}`)
		end
		if #done == 0 then return false, "nothing to set" end
		resync(player)
		return true, table.concat(done, ", ")
	elseif kind == "GiveStud" then
		local def, variant = RollLogic.decodeKey(op.Stud)
		if not def or not variant then return false, "no stud " .. tostring(op.Stud) end
		local count = math.clamp(math.floor(tonumber(op.Count) or 1), 1, MAX_GRANT)
		for _ = 1, count do
			Inventory.grant(player, def.Id, variant.Name)
		end
		resync(player)
		return true, `{count} x {op.Stud}`
	elseif kind == "GiveBoost" then
		if typeof(op.Boost) ~= "string" or not Config.Boosts[op.Boost] then return false, "no such boost" end
		Boosts.add(player, op.Boost, math.clamp(tonumber(op.Minutes) or 15, 1, 24 * 60) * 60)
		resync(player)
		return true, `{op.Boost} boost, {op.Minutes} min`
	elseif kind == "Reset" then
		resetPlayer(player, "An admin reset your progress. Please rejoin!")
		return true, "progress reset"
	end
	return false, "unknown edit"
end

-- Applies an op here, or queues it on the save. Yields.
local function editUser(userId: number, op: any): (boolean, string)
	local target = Players:GetPlayerByUserId(userId)
	if target and PlayerData.get(target) then
		return applyOp(target, op)
	end
	op.T = "Edit"
	if PlayerData.message(userId, op) then
		return true, "queued: applies when their save next opens"
	end
	return false, "couldn't reach their save"
end

local function resetEconomy(data: any)
	for field, value in Roles.EconomyReset do
		data[field] = if typeof(value) == "table" then table.clone(value) else value
	end
end

-- Brings a save up to the latest resets. True when it changed.
local function applyEpochs(player: Player): boolean
	local data: any = PlayerData.get(player)
	if not data then return false end
	data.Epochs = data.Epochs or { Economy = 0, All = 0 }
	if (data.Epochs.All or 0) < epochs.All then
		PlayerData.resetData(data, Roles.KeepOnReset)
		data.Epochs = { Economy = epochs.Economy, All = epochs.All }
		return true
	elseif (data.Epochs.Economy or 0) < epochs.Economy then
		resetEconomy(data)
		data.Epochs.Economy = epochs.Economy
		return true
	end
	return false
end

local function loadEpochs()
	local store = adminStore
	if not store then return end
	local ok, value = pcall(function()
		return store:GetAsync("Epochs")
	end)
	if ok and typeof(value) == "table" then
		epochs.Economy = tonumber(value.Economy) or 0
		epochs.All = tonumber(value.All) or 0
	end
end

local function bumpEpoch(kind: string): boolean
	local store = adminStore
	if not store then return false end
	local ok = pcall(function()
		store:UpdateAsync("Epochs", function(old: any)
			local value = if typeof(old) == "table" then old else { Economy = 0, All = 0 }
			value[kind] = (tonumber(value[kind]) or 0) + 1
			if kind == "All" then
				-- A full wipe covers the economy too.
				value.Economy = (tonumber(value.Economy) or 0) + 1
			end
			return value
		end)
	end)
	return ok
end

local function applyEpochsToEveryone()
	for _, player in Players:GetPlayers() do
		local data: any = PlayerData.get(player)
		local wiped = data and (data.Epochs and (data.Epochs.All or 0) < epochs.All)
		if applyEpochs(player) then
			if wiped then
				player:Kick("Everyone's progress was reset. Please rejoin!")
			else
				resync(player)
			end
		end
	end
end

--------------------------------------------------------------------------
-- Bans
--------------------------------------------------------------------------

type Ban = { Until: number, Reason: string, By: number }

local function readBan(userId: number): Ban?
	local store = banStore
	if not store then return nil end
	local ok, value = pcall(function()
		return store:GetAsync(tostring(userId))
	end)
	if not ok or typeof(value) ~= "table" then return nil end
	local untilTime = tonumber(value.Until) or 0
	if untilTime ~= 0 and untilTime <= os.time() then
		return nil -- expired
	end
	return { Until = untilTime, Reason = tostring(value.Reason or ""), By = tonumber(value.By) or 0 }
end

local function banMessage(ban: Ban): string
	if ban.Until == 0 then
		return `You are banned. {ban.Reason}`
	end
	local minutes = math.max(1, math.ceil((ban.Until - os.time()) / 60))
	local left = if minutes >= 120 then `{math.ceil(minutes / 60)} hours` else `{minutes} minutes`
	return `You are banned for {left}. {ban.Reason}`
end

-- seconds: 0 = forever.
local function ban(actor: Player, userId: number, seconds: number, reason: string): boolean
	local record = { Until = if seconds > 0 then os.time() + seconds else 0, Reason = reason, By = actor.UserId }
	local store = banStore
	local saved = false
	if store then
		saved = pcall(function()
			store:SetAsync(tostring(userId), record)
		end)
	end
	-- Roblox's own ban too (covers alt accounts where Roblox detects them).
	pcall(function()
		Players:BanAsync({
			UserIds = { userId },
			ApplyToUniverse = true,
			Duration = if seconds > 0 then seconds else -1,
			DisplayReason = reason,
			PrivateReason = `By {actor.Name} ({actor.UserId}) from the admin panel`,
			ExcludeAltAccounts = false,
		})
	end)
	local message = banMessage(record)
	local online = Players:GetPlayerByUserId(userId)
	if online then
		online:Kick(message)
	end
	publish({ T = "Kick", UserId = userId, Reason = message })
	return saved
end

local function unban(userId: number): boolean
	local store = banStore
	local ok = false
	if store then
		ok = pcall(function()
			store:RemoveAsync(tostring(userId))
		end)
	end
	pcall(function()
		Players:UnbanAsync({ UserIds = { userId }, ApplyToUniverse = true })
	end)
	return ok
end

--------------------------------------------------------------------------
-- Announcements and cross-server messages
--------------------------------------------------------------------------

local announcement: RemoteEvent

local function broadcast(text: string, sender: string)
	announcement:FireAllClients(text, sender, "ANNOUNCEMENT")
end

local function onMessage(message: any)
	local data = message and message.Data
	if typeof(data) ~= "table" or data.Server == SERVER_ID then return end
	if data.T == "Announce" and typeof(data.Text) == "string" then
		broadcast(data.Text, tostring(data.Sender or ""))
	elseif data.T == "Event" and typeof(data.Id) == "string" and typeof(data.Ends) == "number" then
		ServerEffects.runEvent(data.Id, data.Ends)
	elseif data.T == "StopEvent" then
		ServerEffects.stopEvent()
	elseif data.T == "Kick" and typeof(data.UserId) == "number" then
		local target = Players:GetPlayerByUserId(data.UserId)
		if target then
			target:Kick(tostring(data.Reason or "Removed by an admin."))
		end
	elseif data.T == "Epoch" then
		loadEpochs()
		applyEpochsToEveryone()
	end
end

--------------------------------------------------------------------------
-- Actions: one per AdminConfig action id. args are already cleaned.
--   ById    Run(admin, userId, args): works for anyone, here or not
--   Target = "None" in AdminConfig: Run(admin, nil, args), once
--   otherwise Run(admin, player, args) per selected player in this server
--------------------------------------------------------------------------

local ACTIONS = {}

ACTIONS.Currency = { ById = true, Run = function(_, userId, a)
	return editUser(userId, { Op = "Currency", Kind = a.Kind, Amount = a.Amount, Mode = a.Mode, Notify = a.Notify })
end }

ACTIONS.Progress = { ById = true, Run = function(_, userId, a)
	if a.Rebirths == nil and a.Zones == nil then
		return false, "Fill in Rebirths or Zones owned"
	end
	return editUser(userId, { Op = "Progress", Rebirths = a.Rebirths, Zones = a.Zones })
end }

ACTIONS.GiveStud = { ById = true, Run = function(_, userId, a)
	local def, variant = RollLogic.decodeKey(a.Stud)
	if not def or not variant then
		return false, `No stud "{a.Stud}" (use Id:Variant, e.g. Nebula:Shiny)`
	end
	return editUser(userId, { Op = "GiveStud", Stud = a.Stud, Count = a.Count })
end }

ACTIONS.GiveBoost = { ById = true, Run = function(_, userId, a)
	return editUser(userId, { Op = "GiveBoost", Boost = a.Boost, Minutes = a.Minutes })
end }

ACTIONS.ResetPlayer = { ById = true, Run = function(_, userId, _a)
	return editUser(userId, { Op = "Reset" })
end }

ACTIONS.Kick = { Run = function(admin, target, a)
	if target == admin then
		return false, "That's you"
	end
	target:Kick(if a.Reason ~= "" then a.Reason else "Removed by an admin.")
	return true, "kicked" .. (if a.Reason ~= "" then ` · {a.Reason}` else "")
end }

ACTIONS.Ban = { ById = true, Run = function(admin, userId, a)
	if userId == admin.UserId then
		return false, "That's you"
	end
	local minutes = AdminConfig.BAN_MINUTES[a.Duration] or 0
	if minutes == 0 and not can(admin, "Ban") then
		return false, "You can only give temporary bans"
	end
	local saved = ban(admin, userId, minutes * 60, if a.Reason ~= "" then a.Reason else "Banned by an admin.")
	return true, `banned {a.Duration}{if saved then "" else " (kicked; the ban couldn't be saved)"}`
end }

ACTIONS.Unban = { ById = true, Run = function(_, userId, _a)
	return unban(userId), "unbanned"
end }

ACTIONS.RunEvent = { Run = function(_, _, a)
	local id = AdminConfig.EVENT_IDS[a.Event]
	local def = RollLogic.eventById(id)
	if not def then return false, "No such event" end
	local ends = workspace:GetServerTimeNow() + a.Minutes * 60
	ServerEffects.runEvent(def.Id, ends)
	if a.Everywhere then
		publish({ T = "Event", Id = def.Id, Ends = ends })
	end
	return true, `{def.Name}, {a.Minutes} min{if a.Everywhere then ", every server" else ""}`
end }

ACTIONS.StopEvent = { Run = function(_, _, a)
	ServerEffects.stopEvent()
	if a.Everywhere then
		publish({ T = "StopEvent" })
	end
	return true, `stopped{if a.Everywhere then " in every server" else ""}`
end }

ACTIONS.Announce = { Run = function(admin, _, a)
	local ok, clean = pcall(function()
		return game:GetService("TextService"):FilterStringAsync(a.Message, admin.UserId):GetNonChatStringForBroadcastAsync()
	end)
	if not ok or not clean then
		return false, "The text filter is unavailable, try again"
	end
	broadcast(clean, admin.DisplayName)
	if a.Everywhere then
		publish({ T = "Announce", Text = clean, Sender = admin.DisplayName })
		return true, "announced to every server"
	end
	return true, "announced to this server"
end }

local function epochAction(kind: string)
	return { Run = function(_, _, a)
		if a.Confirm ~= "RESET" then
			return false, "Type RESET to confirm"
		end
		if not bumpEpoch(kind) then
			return false, "Couldn't save the reset (DataStores unavailable?)"
		end
		loadEpochs()
		publish({ T = "Epoch" })
		task.defer(applyEpochsToEveryone)
		return true, if kind == "All" then "everyone's progress reset" else "everyone's currencies reset"
	end }
end
ACTIONS.ResetEconomy = epochAction("Economy")
ACTIONS.ResetAll = epochAction("All")

--------------------------------------------------------------------------
-- Requests from the panel
--------------------------------------------------------------------------

local function inspect(target: Player): any
	local data: any = PlayerData.get(target)
	local zones, studs = 0, 0
	if data then
		for _ in data.UnlockedWorlds or {} do zones += 1 end
		for _, count in data.Studs or {} do studs += count end
	end
	local role = roles[target]
	return {
		Name = target.Name, DisplayName = target.DisplayName, UserId = target.UserId, AccountAge = target.AccountAge,
		Role = role or "Player",
		Clacks = if data then data.Clacks else nil,
		FreeRolls = if data then data.FreeRolls else nil,
		Spins = if data then data.Spins else nil,
		LuckyRolls = if data then data.LuckyRolls else nil,
		Rebirths = if data then data.Rebirths else nil,
		Zones = zones,
		Studs = studs,
		Enemies = if data then data.EnemiesDefeated else nil,
		BestRoll = if data then data.BestRoll else nil,
		Loaded = data ~= nil,
	}
end

local function runAction(admin: Player, request: any): Result
	local def = AdminConfig.Action(request.Action)
	local impl = ACTIONS[request.Action]
	if not def or not impl then
		return { ok = false, message = "Unknown action: " .. tostring(request.Action) }
	end
	if def.Permission and not can(admin, def.Permission) then
		return { ok = false, message = `You need the {def.Permission} permission` }
	end
	local args, why = AdminConfig.Clean(request.Action, request.Args)
	if not args then
		return { ok = false, message = why }
	end
	if args.Everywhere and not can(admin, "Global") then
		return { ok = false, message = "You need the Global permission for every server" }
	end

	-- server-wide
	if def.Target == "None" then
		local ok, msg = impl.Run(admin, nil, args)
		if ok then
			log(admin, request.Action, msg or "")
		end
		return { ok = ok, message = msg }
	end

	-- a UserId field wins for ById actions; otherwise every selected player
	local ids = {}
	if impl.ById and args.UserId then
		ids = { args.UserId }
	elseif type(request.Targets) == "table" then
		for i, id in request.Targets do
			if i > MAX_TARGETS then break end
			if tonumber(id) then
				table.insert(ids, tonumber(id))
			end
		end
	end
	if #ids == 0 then
		return { ok = false, message = if def.Target == "SelectedOrUserId" then "Select a player or enter a UserId" else "Select a player first" }
	end

	local done, failed, lastMsg, lastWhy = 0, 0, "", ""
	for _, id in ids do
		local ok, msg
		if not outranks(admin, id) then
			ok, msg = false, "they outrank you"
		elseif impl.ById then
			ok, msg = impl.Run(admin, id, args)
			if ok then
				log(admin, request.Action, `{nameOf(id)}: {msg or ""}`)
			end
		else
			local target = Players:GetPlayerByUserId(id)
			if not target then
				ok, msg = false, "not in this server"
			else
				ok, msg = impl.Run(admin, target, args)
				if ok then
					log(admin, request.Action, `{target.Name}: {msg or ""}`)
				end
			end
		end
		if ok then
			done += 1
			lastMsg = msg or "done"
		else
			failed += 1
			lastWhy = msg or "failed"
		end
	end
	if done == 0 then
		return { ok = false, message = lastWhy }
	end
	local who = if done == 1 then "1 player" else `{done} players`
	return { ok = true, message = `{lastMsg} → {who}{if failed > 0 then ` · {failed} failed ({lastWhy})` else ""}` }
end

local function handle(admin: Player, request: any): Result
	local action = request.Action
	if action == "List" then
		local list = {}
		for _, p in Players:GetPlayers() do
			table.insert(list, { UserId = p.UserId, Name = p.Name, DisplayName = p.DisplayName, IsAdmin = roles[p] ~= nil })
		end
		table.sort(list, function(a, b)
			return a.Name:lower() < b.Name:lower()
		end)
		return { ok = true, data = list }
	elseif action == "Log" then
		return { ok = true, data = recent }
	elseif action == "Inspect" then
		local target = tonumber(request.Target) and Players:GetPlayerByUserId(tonumber(request.Target))
		if not target then
			return { ok = false, message = "That player isn't in this server" }
		end
		return { ok = true, data = inspect(target) }
	end
	return runAction(admin, request)
end

--------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	-- Banned? Out before anything else happens.
	local banned = readBan(player.UserId)
	if banned then
		player:Kick(banMessage(banned))
		return
	end
	local role = resolveRole(player)
	roles[player] = role
	player:SetAttribute("AdminRole", role)
	player:SetAttribute("IsAdmin", if role then true else nil)
end

function Admin.init()
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	adminStore = if ok then store else nil
	local banOk, bans = pcall(function()
		return DataStoreService:GetDataStore(BAN_STORE_NAME)
	end)
	banStore = if banOk then bans else nil

	local folder = Instance.new("Folder")
	folder.Name = "AdminRemotes"
	local remote = Instance.new("RemoteFunction")
	remote.Name = "Admin"
	remote.Parent = folder
	local event = Instance.new("RemoteEvent")
	event.Name = "Announcement"
	event.Parent = folder
	announcement = event
	folder.Parent = ReplicatedStorage

	local lastCall: { [Player]: number } = {}
	remote.OnServerInvoke = function(player: Player, request: any): Result
		if not roles[player] then
			return { ok = false, message = "Not an admin" }
		end
		if type(request) ~= "table" or type(request.Action) ~= "string" then
			return { ok = false, message = "Bad request" }
		end
		-- Only actions are rate-limited; lookups are harmless and the panel
		-- makes them back to back on every refresh.
		local lookup = request.Action == "List" or request.Action == "Inspect" or request.Action == "Log"
		if not lookup then
			local now = os.clock()
			if lastCall[player] and now - lastCall[player] < 0.15 then
				return { ok = false, message = "Too fast" }
			end
			lastCall[player] = now
		end
		local done, result = pcall(handle, player, request)
		if not done then
			warn("[Admin] " .. tostring(result))
			return { ok = false, message = "Error: " .. tostring(result) }
		end
		return result
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		roles[player] = nil
		lastCall[player] = nil
	end)

	-- Saves catch up with resets they missed, and take queued admin edits.
	PlayerData.Loaded:Connect(function(player)
		if applyEpochs(player) then
			resync(player)
		end
	end)
	PlayerData.Message:Connect(function(player, message)
		if typeof(message) == "table" and message.T == "Edit" then
			applyOp(player, message)
		end
	end)

	-- Every AdminConfig action needs an implementation here.
	for _, tab in AdminConfig.TABS do
		for _, category in tab.Categories or {} do
			for _, action in category.Actions or {} do
				if not ACTIONS[action.Id] then
					warn(`[Admin] AdminConfig action "{action.Id}" has no ACTIONS entry in Systems/Admin`)
				end
			end
		end
	end
end

function Admin.start()
	loadEpochs()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(TOPIC, onMessage)
		end)
		if not ok then
			warn(`[Admin] cross-server messages unavailable: {err}`)
		end
	end)
end

-- The role a player has ("Owner", "Admin"...), or nil.
function Admin.roleOf(player: Player): string?
	return roles[player]
end

return Admin
