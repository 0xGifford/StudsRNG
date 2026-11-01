--[[

GameFeel
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/GameFeel

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Juice that isn't owned by one menu:
--   combo meter    "COMBO x37 +18%" over the Clacks counter while a press
--                  streak is alive (server sends "Combo")
--   key sparkles   a burst on every key the local player presses (from
--                  KeyCapper's KeyPressed event)
--   celebrations   zone unlocks, rebirths, Lucky Rolls, welcome back,
--                  server-wide banners for very rare rolls, stud level-ups
--                  ("⭐ EMBER LV 5" rising off the player), achievements

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Studs = require(Shared.Studs)
local Variants = require(Shared.Variants)
local Zones = require(Shared.Zones)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local Roles = require(UI.Roles)
local Format = require(UI.Format)
local Juice = require(UI.Juice)
local CombatFx = require(UI.CombatFx)
local RollLogic = require(Shared.Util.RollLogic)
local AchievementDefs = require(Shared.Achievements)

local GameFeel = {}

local BIG_ROLL_ONE_IN = 100_000

local player = Players.LocalPlayer
local comboLabel: TextLabel? = nil
local comboScale: UIScale? = nil
local comboSeenAt = 0
local lastPop = 0

--------------------------------------------------------------------------
-- Combo meter
--------------------------------------------------------------------------

-- The HUD's combo label (HudRole = "Combo"; tools/ui/migrate.luau adds it).
local function buildCombo()
	local label = Roles.find(Interface.HUD, "HudRole", "Combo")
	if not (label and label:IsA("TextLabel")) then
		warn('[GameFeel] the HUD has no label with HudRole = "Combo": the combo meter is hidden')
		return
	end
	label.Text = ""
	label.TextTransparency = 1
	comboLabel = label
	comboScale = label:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", label)
end

local function onCombo(combo: any)
	local label = comboLabel
	local scale = comboScale
	if not (label and scale) or typeof(combo) ~= "table" then return end
	local count = combo.Count or 0
	if count < 5 then return end
	comboSeenAt = os.clock()
	local heat = math.clamp(count / 100, 0, 1)
	label.Text = `COMBO x{count}  +{Format.percent(combo.Bonus or 0)}`
	label.TextColor3 = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 120, 40), heat)
	label.TextTransparency = 0
	for _, stroke in label:GetChildren() do
		if stroke:IsA("UIStroke") then
			stroke.Transparency = 0
		end
	end
	if os.clock() - lastPop > 0.12 then
		lastPop = os.clock()
		scale.Scale = 1.15 + heat * 0.25
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local function fadeCombo()
	local label = comboLabel
	if not label or label.TextTransparency >= 1 then return end
	if os.clock() - comboSeenAt > Config.Combo.Window + 0.4 then
		TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		for _, stroke in label:GetChildren() do
			if stroke:IsA("UIStroke") then
				TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			end
		end
	end
end

--------------------------------------------------------------------------
-- Key sparkles
--------------------------------------------------------------------------

local sparkle: ParticleEmitter? = nil
local sparkleHolder: Attachment? = nil

local function burstAt(cap: BasePart)
	local emitter = sparkle
	local holder = sparkleHolder
	if not (emitter and holder) then
		local attachment = Instance.new("Attachment")
		attachment.Name = "KeySparkles"
		attachment.Parent = workspace.Terrain
		local created = Instance.new("ParticleEmitter")
		created.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		created.Rate = 0
		created.Lifetime = NumberRange.new(0.3, 0.55)
		created.Speed = NumberRange.new(6, 11)
		created.SpreadAngle = Vector2.new(70, 70)
		created.EmissionDirection = Enum.NormalId.Top
		created.Acceleration = Vector3.new(0, -25, 0)
		created.Size = NumberSequence.new(0.45, 0)
		created.LightEmission = 1
		created.Parent = attachment
		emitter = created
		holder = attachment
		sparkle = created
		sparkleHolder = attachment
	end
	local e = emitter :: ParticleEmitter
	local h = holder :: Attachment
	h.WorldPosition = cap.Position + Vector3.new(0, cap.Size.Y / 2, 0)
	e.Color = ColorSequence.new(cap.Color:Lerp(Color3.new(1, 1, 1), 0.4))
	e:Emit(5)
end

local function bindKeySparkles()
	local runtime = ReplicatedStorage:WaitForChild("KeyCapper", 30)
	local event = runtime and runtime:WaitForChild("KeyPressed", 30)
	if not (event and event:IsA("BindableEvent")) then
		warn("[GameFeel] KeyCapper.KeyPressed not found; no key sparkles")
		return
	end
	event.Event:Connect(function(model: Instance?)
		local cap = model and model:FindFirstChild("Cap")
		if cap and cap:IsA("BasePart") then
			burstAt(cap)
		end
	end)
end

--------------------------------------------------------------------------
-- Celebrations
--------------------------------------------------------------------------

local function countTrue(set: any): number
	local n = 0
	if typeof(set) == "table" then
		for _, value in set do
			if value == true then n += 1 end
		end
	end
	return n
end

-- "⭐ EMBER LV 5" rising off the player, with a pop of light.
local function levelUpPopup(text: string, color: Color3, order: number)
	local character = player.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not (head and head:IsA("BasePart")) then return end
	local board = Roles.template(Roles.gui("WorldUI"), "LevelUpPopup") :: BillboardGui
	board.Name = "LevelUp"
	board.Adornee = head
	board.StudsOffset = Vector3.new(0, 3 + order * 1.7, 0)
	local label = Roles.get(board, "PopupRole", "Text") :: TextLabel
	label.Text = text
	label.TextColor3 = color
	local stroke = label:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", label)
	local scale = label:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", label)
	scale.Scale = 0.2
	board.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(board, TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = board.StudsOffset + Vector3.new(0, 3, 0) }):Play()
	task.delay(1.4, function()
		TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		task.wait(0.55)
		board:Destroy()
	end)
	CombatFx.impact(head.Position, color, 4)
	CombatFx.sound("Coin", nil, 1.6, 0.5)
end

local function levelsOf(xp: any): { [string]: number }
	local levels: { [string]: number } = {}
	if typeof(xp) == "table" then
		for id, amount in xp do
			levels[id] = RollLogic.levelOf(amount)
		end
	end
	return levels
end

local function watchMilestones()
	local zones = countTrue(State.get("UnlockedWorlds"))
	local studLevels = levelsOf(State.get("StudXP"))
	local achieved = table.clone(State.get("Achievements") or {})
	local rebirths = State.get("Rebirths") or 0
	local luck = State.get("LuckyRolls") or 0

	State.Changed:Connect(function(field, value)
		if field == "UnlockedWorlds" then
			local now = countTrue(value)
			if now > zones then
				local newest = Zones.nextFor(value) -- zone after the newest owned one
				local owned = if newest then Zones.List[newest.Order - 1] else Zones.List[#Zones.List]
				Juice.banner("ZONE UNLOCKED!", if owned then `{owned.Name} is open` else "", if owned then owned.Color else nil, 2)
				Juice.confetti(90)
				Juice.shake(0.8, 0.5)
				Juice.fov(10, 0.8)
			end
			zones = now
		elseif field == "Rebirths" then
			if (value or 0) > rebirths then
				Juice.flash(Color3.fromRGB(255, 240, 200), 0.85, 1.2)
				Juice.banner(`REBIRTH {value}!`, "Your Clacks multiplier went up", Color3.fromRGB(255, 220, 90), 2.2)
				Juice.confetti(120)
				Juice.shake(1.2, 0.7)
				Juice.fov(14, 1)
			end
			rebirths = value or 0
		elseif field == "LuckyRolls" then
			if (value or 0) > luck then
				Juice.banner("+1 LUCK", "Permanent luck forever", Color3.fromRGB(120, 255, 140), 1.6)
				Juice.confetti(50)
			end
			luck = value or 0
		elseif field == "Combo" then
			onCombo(value)
		elseif field == "Achievements" then
			for id, on in value or {} do
				local def = AchievementDefs.ById[id]
				if on and not achieved[id] and def then
					local subtitle = `{def.Name} · {Format.reward(def.Reward)}`
					if def.Title then
						subtitle ..= ` · Title « {def.Title} »`
					end
					Juice.banner("🏅 ACHIEVEMENT UNLOCKED!", subtitle, def.TitleColor or Color3.fromRGB(255, 205, 60), 2)
					Juice.confetti(60)
					CombatFx.sound("Coin", nil, 1.3, 0.6)
				end
			end
			achieved = table.clone(value or {})
		elseif field == "StudXP" then
			local now = levelsOf(value)
			local order = 0
			for id, level in now do
				local def = Studs.ById[id]
				if def and level > (studLevels[id] or 1) then
					local color = if def.Rarity == "Secret" then Color3.new(1, 1, 1) else Config.Rarities.Colors[def.Rarity] or Color3.new(1, 1, 1)
					levelUpPopup(`⭐ {string.upper(def.Name)} LV {level}`, color, order)
					order += 1
				end
			end
			studLevels = now
		end
	end)

	State.Notified:Connect(function(payload)
		if payload.Kind == "RareDrop" then
			local boost = Config.Boosts[payload.Boost]
			if boost then
				Juice.banner("RARE DROP!", `{boost.Name} · {boost.Short} chance`, boost.Color, 1.6)
				Juice.confetti(45)
				Juice.flash(boost.Color, 0.25, 0.4)
				CombatFx.sound("Coin", nil, 1.5, 0.6)
			end
		elseif payload.Kind == "Welcome" then
			Juice.banner("WELCOME BACK!", `+{Format.number(payload.Amount or 0)} Clacks while you were away`, Color3.fromRGB(255, 220, 90), 2.6)
			Juice.confetti(70)
		end
	end)

	State.Announced:Connect(function(payload)
		if typeof(payload) ~= "table" or (payload.OneIn or 0) < BIG_ROLL_ONE_IN then return end
		local def = Studs.ById[payload.Id]
		local variant = Variants.ById[payload.Variant]
		if not (def and variant) then return end
		local color = Config.Rarities.Colors[def.Rarity] or Color3.new(1, 1, 1)
		local mine = payload.UserId == player.UserId
		Juice.banner(
			if mine then "INCREDIBLE ROLL!" else `{payload.Player} GOT LUCKY!`,
			`{Format.studName(def, variant)} · {Format.oneIn(payload.OneIn)}`,
			color,
			2.4
		)
	end)
end

function GameFeel.start()
	Interface.setup()
	buildCombo()
	task.spawn(bindKeySparkles)
	local function ready()
		watchMilestones()
	end
	if State.isReady() then
		ready()
	else
		State.Ready:Connect(ready)
	end
	while true do
		task.wait(0.2)
		fadeCombo()
	end
end

return GameFeel
