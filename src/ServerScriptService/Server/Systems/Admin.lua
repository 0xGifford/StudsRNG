--[[

Admin
ModuleScript
/ServerScriptService/Server/Systems/Admin

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- The admin panel's server side (Controllers/AdminPanel is the UI).
--
-- Roles and permissions: Config.Admin. Each player's role is worked out when
-- they join and set as their "AdminRole" attribute (the panel only shows for
-- a role). Every request is checked again here: the role must have the
-- permission, and a role can only act on players of a lower rank.
--
--   Players     edit (Clacks, Free Rolls, Spins, Lucky Rolls, Rebirths, zones,
--               studs, boosts) or reset anyone by name or UserId. In this
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
-- Every action is logged (output + the "Log" key of the admin DataStore).

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
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

local AdminConfig = Config.Admin
local TOPIC = "StudsAdmin_v1"
local STORE_NAME = "StudsAdmin_v1"
local BAN_STORE_NAME = "StudsBans_v1"
local LOG_LIMIT = 200
local MAX_GRANT = 100
local SERVER_ID = if game.JobId ~= "" then game.JobId else "studio"

type Response = { Ok: boolean, Error: string?, Message: string?, Data: any? }

local adminStore: DataStore? = nil
local banStore: DataStore? = nil
local epochs = { Economy = 0, All = 0 }

--------------------------------------------------------------------------
-- Roles
--------------------------------------------------------------------------

local roles: { [Player]: string } = {}

local function rankOf(role: string?): number
	local def = if role then AdminConfig.Roles[role] else nil
	return if def then def.Rank else 0
end

local function topRank(): number
	local best = 0
	for _, def in AdminConfig.Roles do
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
	if RunService:IsStudio() and AdminConfig.StudioRole then
		return AdminConfig.StudioRole
	end
	if isCreator(player) then
		return AdminConfig.CreatorRole
	end
	local listed = AdminConfig.Users[player.UserId]
	if listed and AdminConfig.Roles[listed] then
		return listed
	end
	for _, rule in AdminConfig.Groups do
		local ok, rank = pcall(function()
			return player:GetRankInGroup(rule.GroupId)
		end)
		if ok and rank >= rule.MinRank and AdminConfig.Roles[rule.Role] then
			return rule.Role
		end
	end
	return nil
end

local function can(player: Player, permission: string): boolean
	local role = roles[player]
	local def = if role then AdminConfig.Roles[role] else nil
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
	local targetRole = if target then roles[target] else AdminConfig.Users[targetUserId]
	return rankOf(targetRole) < actorRank
end

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function log(actor: Player?, action: string, detail: string)
	local line = `[Admin] {if actor then `{actor.Name} ({actor.UserId})` else "system"}: {action} {detail}`
	print(line)
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

local function colorToTable(color: Color3): { number }
	return { math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255) }
end

local function colorFromTable(value: any): Color3
	if typeof(value) == "table" and #value == 3 then
		return Color3.fromRGB(tonumber(value[1]) or 255, tonumber(value[2]) or 255, tonumber(value[3]) or 255)
	end
	return Color3.new(1, 1, 1)
end

-- A player, or a UserId (with a name when one can be found). Yields.
local function resolveTarget(raw: any): (number?, string?)
	if typeof(raw) == "number" and raw > 0 and raw % 1 == 0 then
		local online = Players:GetPlayerByUserId(raw)
		if online then return raw, online.Name end
		local ok, name = pcall(function()
			return Players:GetNameFromUserIdAsync(raw)
		end)
		return raw, if ok then name else nil
	end
	if typeof(raw) ~= "string" or raw == "" then return nil, nil end
	local asNumber = tonumber(raw)
	if asNumber then
		return resolveTarget(asNumber)
	end
	local lower = string.lower(raw)
	for _, player in Players:GetPlayers() do
		if string.lower(player.Name) == lower or string.lower(player.DisplayName) == lower then
			return player.UserId, player.Name
		end
	end
	local ok, userId = pcall(function()
		return Players:GetUserIdFromNameAsync(raw)
	end)
	if ok and typeof(userId) == "number" then
		return userId, raw
	end
	return nil, nil
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
-- Editing saves (on a player whose save is open in this server)
--------------------------------------------------------------------------

local SET_FIELDS = { Clacks = true, FreeRolls = true, Spins = true, LuckyRolls = true, Rebirths = true }
Admin.EditFields = { "Clacks", "FreeRolls", "Spins", "LuckyRolls", "Rebirths", "Zones", "Stud", "Boost" }

-- field: Clacks | FreeRolls | Spins | LuckyRolls | Rebirths (set to value),
-- Zones (own the first value zones), Stud ("Id:Variant", value copies),
-- Boost (boost id, value minutes).
local function applyEdit(player: Player, field: string, value: any, extra: any): (boolean, string?)
	local data: any = PlayerData.get(player)
	if not data then return false, "NotLoaded" end
	local amount = tonumber(value)
	if SET_FIELDS[field] then
		if not amount or amount ~= amount or amount < 0 or amount > 1e15 then return false, "BadValue" end
		data[field] = math.floor(amount)
	elseif field == "Zones" then
		if not amount then return false, "BadValue" end
		local count = math.clamp(math.floor(amount), 1, #Zones.List)
		local unlocked = {}
		for i = 1, count do
			unlocked[Zones.List[i].Id] = true
		end
		data.UnlockedWorlds = unlocked
	elseif field == "Stud" then
		local def, variant = RollLogic.decodeKey(extra)
		if not def or not variant then return false, "BadStud" end
		for _ = 1, math.clamp(math.floor(amount or 1), 1, MAX_GRANT) do
			Inventory.grant(player, def.Id, variant.Name)
		end
	elseif field == "Boost" then
		if typeof(extra) ~= "string" or not Config.Boosts[extra] then return false, "BadBoost" end
		Boosts.add(player, extra, math.clamp(amount or 5, 1, 24 * 60) * 60)
	else
		return false, "BadField"
	end
	resync(player)
	return true, nil
end

-- Wipes a save (keeping Config.Admin.KeepOnReset). The player rejoins so
-- every system starts clean.
local function resetPlayer(player: Player, reason: string)
	local data: any = PlayerData.get(player)
	if not data then return end
	PlayerData.resetData(data, AdminConfig.KeepOnReset)
	data.Epochs = { Economy = epochs.Economy, All = epochs.All }
	player:Kick(reason)
end

local function resetEconomy(data: any)
	for field, value in AdminConfig.EconomyReset do
		data[field] = if typeof(value) == "table" then table.clone(value) else value
	end
end

-- Brings a save up to the latest resets. True when it changed.
local function applyEpochs(player: Player): boolean
	local data: any = PlayerData.get(player)
	if not data then return false end
	data.Epochs = data.Epochs or { Economy = 0, All = 0 }
	if (data.Epochs.All or 0) < epochs.All then
		PlayerData.resetData(data, AdminConfig.KeepOnReset)
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
-- Announcements and events
--------------------------------------------------------------------------

local function announce(text: string, from: string, color: Color3, global: boolean)
	Net.fireAll("Broadcast", {
		Text = text,
		From = from,
		Color = color,
		Seconds = AdminConfig.AnnounceSeconds,
		Global = global,
	})
end

local function onMessage(message: any)
	local data = message and message.Data
	if typeof(data) ~= "table" or data.Server == SERVER_ID then return end
	if data.T == "Announce" and typeof(data.Text) == "string" then
		announce(data.Text, tostring(data.From or ""), colorFromTable(data.Color), true)
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
-- Requests from the panel
--------------------------------------------------------------------------

local function summary(userId: number, name: string?): any
	local online = Players:GetPlayerByUserId(userId)
	local data: any = if online then PlayerData.get(online) else PlayerData.peek(userId)
	local banned = readBan(userId)
	local zones = 0
	if data and typeof(data.UnlockedWorlds) == "table" then
		for _ in data.UnlockedWorlds do
			zones += 1
		end
	end
	return {
		UserId = userId,
		Name = name or (if online then online.Name else tostring(userId)),
		Online = online ~= nil,
		Role = if online then roles[online] else AdminConfig.Users[userId],
		Found = data ~= nil,
		Clacks = if data then data.Clacks else 0,
		FreeRolls = if data then data.FreeRolls else 0,
		Spins = if data then data.Spins else 0,
		LuckyRolls = if data then data.LuckyRolls else 0,
		Rebirths = if data then data.Rebirths else 0,
		Zones = zones,
		Banned = if banned then banMessage(banned) else nil,
	}
end

local function infoFor(player: Player): any
	local role = roles[player]
	local def = if role then AdminConfig.Roles[role] else nil
	local events = {}
	for _, event in Config.Events.List do
		table.insert(events, { Id = event.Id, Name = event.Name, Color = event.Color, Description = event.Description or "" })
	end
	local boosts = {}
	for id in Config.Boosts do
		table.insert(boosts, id)
	end
	table.sort(boosts)
	local online = {}
	for _, other in Players:GetPlayers() do
		table.insert(online, { UserId = other.UserId, Name = other.Name, DisplayName = other.DisplayName, Role = roles[other] })
	end
	return {
		Role = role,
		Color = if def then def.Color else nil,
		Permissions = if def then def.Permissions else {},
		Events = events,
		Boosts = boosts,
		EditFields = Admin.EditFields,
		Players = online,
		CurrentEvent = ServerEffects.currentEvent(),
		Epochs = epochs,
	}
end

local function needs(player: Player, permission: string): Response?
	if can(player, permission) then return nil end
	return { Ok = false, Error = "NoPermission", Message = `You need the {permission} permission.` }
end

local function handle(player: Player, action: unknown, a: unknown, b: unknown, c: unknown): Response
	if not roles[player] then
		return { Ok = false, Error = "NotAdmin" }
	end

	if action == "Info" then
		return { Ok = true, Data = infoFor(player) }
	elseif action == "Lookup" then
		local userId, name = resolveTarget(a)
		if not userId then return { Ok = false, Error = "NotFound", Message = "No such player." } end
		return { Ok = true, Data = summary(userId, name) }

	elseif action == "Edit" then
		local denied = needs(player, "EditPlayers")
		if denied then return denied end
		local userId, name = resolveTarget(a)
		if not userId then return { Ok = false, Error = "NotFound", Message = "No such player." } end
		if not outranks(player, userId) then return { Ok = false, Error = "Rank", Message = "They outrank you." } end
		if typeof(b) ~= "string" or not table.find(Admin.EditFields, b) then return { Ok = false, Error = "BadField" } end
		-- c: "value" or "value|extra" (a stud key or boost id).
		local raw = if typeof(c) == "string" or typeof(c) == "number" then tostring(c) else ""
		local value, extra = string.match(raw, "^([^|]*)|?(.*)$")
		local target = Players:GetPlayerByUserId(userId)
		if target and PlayerData.get(target) then
			local ok, err = applyEdit(target, b, value, if extra ~= "" then extra else value)
			log(player, "Edit", `{name} {b} = {raw} ({if ok then "done" else err})`)
			return { Ok = ok, Error = err, Message = if ok then `{name}: {b} updated.` else nil, Data = summary(userId, name) }
		end
		local sent = PlayerData.message(userId, { T = "Edit", Field = b, Value = value, Extra = if extra ~= "" then extra else value, By = player.UserId })
		log(player, "Edit", `{name} {b} = {raw} (queued: {sent})`)
		return { Ok = sent, Message = if sent then `{name} isn't here: it applies next time their save opens.` else "Couldn't reach their save.", Error = if sent then nil else "SaveError" }

	elseif action == "ResetPlayer" then
		local denied = needs(player, "ResetPlayers")
		if denied then return denied end
		local userId, name = resolveTarget(a)
		if not userId then return { Ok = false, Error = "NotFound", Message = "No such player." } end
		if not outranks(player, userId) then return { Ok = false, Error = "Rank", Message = "They outrank you." } end
		local target = Players:GetPlayerByUserId(userId)
		log(player, "ResetPlayer", tostring(name))
		if target and PlayerData.get(target) then
			resetPlayer(target, "An admin reset your progress. Please rejoin!")
			return { Ok = true, Message = `{name} was reset.` }
		end
		local sent = PlayerData.message(userId, { T = "Reset", By = player.UserId })
		return { Ok = sent, Message = if sent then `{name} is reset next time their save opens.` else "Couldn't reach their save." }

	elseif action == "ResetEconomy" or action == "ResetAll" then
		local permission = action :: string
		local denied = needs(player, permission)
		if denied then return denied end
		if a ~= "CONFIRM" then return { Ok = false, Error = "Confirm", Message = "Type CONFIRM to do this." } end
		local kind = if action == "ResetAll" then "All" else "Economy"
		if not bumpEpoch(kind) then
			return { Ok = false, Error = "SaveError", Message = "Couldn't save the reset (DataStores unavailable?)." }
		end
		log(player, action :: string, "everyone")
		loadEpochs()
		publish({ T = "Epoch" })
		task.defer(applyEpochsToEveryone)
		return { Ok = true, Message = if kind == "All" then "Everyone's progress is reset." else "Everyone's currencies are reset." }

	elseif action == "Kick" then
		local denied = needs(player, "Kick")
		if denied then return denied end
		local userId, name = resolveTarget(a)
		if not userId then return { Ok = false, Error = "NotFound", Message = "No such player." } end
		if not outranks(player, userId) then return { Ok = false, Error = "Rank", Message = "They outrank you." } end
		local reason = if typeof(b) == "string" and b ~= "" then b else "Removed by an admin."
		local target = Players:GetPlayerByUserId(userId)
		if target then
			target:Kick(reason)
		else
			publish({ T = "Kick", UserId = userId, Reason = reason })
		end
		log(player, "Kick", `{name}: {reason}`)
		return { Ok = true, Message = `{name} was kicked.` }

	elseif action == "TempBan" or action == "Ban" then
		local denied = needs(player, action :: string)
		if denied then return denied end
		local userId, name = resolveTarget(a)
		if not userId then return { Ok = false, Error = "NotFound", Message = "No such player." } end
		if not outranks(player, userId) then return { Ok = false, Error = "Rank", Message = "They outrank you." } end
		local seconds = 0
		local reason: string
		if action == "TempBan" then
			local minutes = tonumber(b)
			if not minutes or minutes ~= minutes or minutes < 1 then return { Ok = false, Error = "BadValue", Message = "Minutes must be 1 or more." } end
			seconds = math.floor(math.min(minutes, 60 * 24 * 365) * 60)
			reason = if typeof(c) == "string" and c ~= "" then c else "Temporarily banned."
		else
			reason = if typeof(b) == "string" and b ~= "" then b else "Banned."
		end
		local saved = ban(player, userId, seconds, reason)
		log(player, action :: string, `{name} {seconds}s: {reason}`)
		return { Ok = true, Message = if saved then `{name} is banned.` else `{name} was kicked, but the ban couldn't be saved.` }

	elseif action == "Unban" then
		local denied = needs(player, "Unban")
		if denied then return denied end
		local userId, name = resolveTarget(a)
		if not userId then return { Ok = false, Error = "NotFound", Message = "No such player." } end
		local ok = unban(userId)
		log(player, "Unban", tostring(name))
		return { Ok = ok, Message = if ok then `{name} is unbanned.` else "Couldn't reach the ban list." }

	elseif action == "RunEvent" then
		local denied = needs(player, "Events")
		if denied then return denied end
		local global = c == "Global"
		if global then
			local deniedGlobal = needs(player, "Global")
			if deniedGlobal then return deniedGlobal end
		end
		local def = if typeof(a) == "string" then RollLogic.eventById(a) else nil
		if not def then return { Ok = false, Error = "BadEvent", Message = "No such event." } end
		local minutes = tonumber(b) or (Config.Events.AdminDuration / 60)
		local ends = workspace:GetServerTimeNow() + math.clamp(minutes, 1, 24 * 60) * 60
		ServerEffects.runEvent(def.Id, ends)
		if global then
			publish({ T = "Event", Id = def.Id, Ends = ends })
		end
		log(player, "RunEvent", `{def.Id} {minutes}m {if global then "all servers" else "this server"}`)
		return { Ok = true, Message = `{def.Name} is running{if global then " in every server" else ""}.` }

	elseif action == "StopEvent" then
		local denied = needs(player, "Events")
		if denied then return denied end
		local global = a == "Global"
		if global then
			local deniedGlobal = needs(player, "Global")
			if deniedGlobal then return deniedGlobal end
		end
		ServerEffects.stopEvent()
		if global then
			publish({ T = "StopEvent" })
		end
		log(player, "StopEvent", if global then "all servers" else "this server")
		return { Ok = true, Message = `Event stopped{if global then " in every server" else ""}.` }

	elseif action == "Announce" then
		local denied = needs(player, "Announce")
		if denied then return denied end
		local global = b == "Global"
		if global then
			local deniedGlobal = needs(player, "Global")
			if deniedGlobal then return deniedGlobal end
		end
		if typeof(a) ~= "string" then return { Ok = false, Error = "BadValue" } end
		local trimmed = string.gsub(a, "^%s+", "")
		local text = string.sub(trimmed, 1, AdminConfig.MaxAnnounceLength)
		if text == "" then return { Ok = false, Error = "BadValue", Message = "Write something to announce." } end
		-- Players' text must go through Roblox's filter.
		local ok, filtered = pcall(function()
			local result = game:GetService("TextService"):FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
			return result:GetNonChatStringForBroadcastAsync()
		end)
		if not ok then return { Ok = false, Error = "Filter", Message = "Couldn't filter that text. Try again." } end
		local role = roles[player]
		local def = if role then AdminConfig.Roles[role] else nil
		local color = if def then def.Color else Color3.new(1, 1, 1)
		announce(filtered, player.DisplayName, color, global)
		if global then
			publish({ T = "Announce", Text = filtered, From = player.DisplayName, Color = colorToTable(color) })
		end
		log(player, "Announce", `{if global then "all servers" else "this server"}: {filtered}`)
		return { Ok = true, Message = "Announced." }
	end

	return { Ok = false, Error = "BadAction" }
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

	Net.handle("Admin", { Rate = 4, Burst = 12, MaxString = AdminConfig.MaxAnnounceLength + 20 }, handle)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		roles[player] = nil
	end)

	-- Saves catch up with resets they missed, and take queued admin edits.
	PlayerData.Loaded:Connect(function(player)
		if applyEpochs(player) then
			resync(player)
		end
	end)
	PlayerData.Message:Connect(function(player, message)
		if typeof(message) ~= "table" then return end
		if message.T == "Edit" and typeof(message.Field) == "string" then
			applyEdit(player, message.Field, message.Value, message.Extra)
		elseif message.T == "Reset" then
			resetPlayer(player, "An admin reset your progress. Please rejoin!")
		end
	end)
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
