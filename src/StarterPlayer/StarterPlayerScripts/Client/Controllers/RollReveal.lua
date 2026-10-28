--[[ 

RollReveal
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/RollReveal

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Owns the roll flow on the client: decides free vs paid, asks the server,
-- then plays the reveal (slot-machine spin → land → hold → fade). Also runs
-- auto-roll and turns server announcements into chat messages.
-- The server has already decided the result before the spin starts; the spin
-- is pure theatre.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Studs = require(Shared.Studs)
local Variants = require(Shared.Variants)
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)

local Controllers = script.Parent
local UI = Controllers.Parent:WaitForChild("UI")
local State = require(Controllers.State)
local Interface = require(UI.Interface)
local StudCell = require(UI.StudCell)
local Format = require(UI.Format)
local UIConfig = require(UI.UIConfig)

type RollResult = Types.RollResult
type StudDef = Types.StudDef

local RollReveal = {}

RollReveal.AutoChanged = Signal.new() :: Signal.Signal<boolean>
RollReveal.BusyChanged = Signal.new() :: Signal.Signal<boolean>

local busy = false
local auto = false
local gui: ScreenGui
local holder: CanvasGroup

--------------------------------------------------------------------------
-- Reveal visuals
--------------------------------------------------------------------------

local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "RollReveal"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	holder = Instance.new("CanvasGroup")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.45)
	holder.Size = UDim2.fromScale(0.7, 0.34)
	holder.BackgroundTransparency = 1
	holder.GroupTransparency = 1
	holder.Visible = false
	holder.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0.03, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
end

local function spinPool(): { StudDef }
	local unlocked = State.get("UnlockedWorlds") or {}
	local pool = {}
	for _, def in Studs.List do
		if unlocked[def.World] then
			table.insert(pool, def)
		end
	end
	if #pool == 0 then
		pool = table.clone(Studs.List)
	end
	return pool
end

type Card = { frame: Frame, viewport: ViewportFrame, caption: TextLabel, scale: UIScale, result: RollResult }

local function makeCard(result: RollResult, order: number): Card
	local def = Studs.ById[result.Id]
	local frame = StudCell.new(def, Variants.ById.Normal)
	frame.LayoutOrder = order
	frame.Size = UDim2.fromScale(0.3, 0.62) -- leaves room for the caption below
	frame.Position = UDim2.new()

	local scale = Instance.new("UIScale")
	scale.Parent = frame

	-- Caption under the card: rarity + odds once landed.
	local title = frame:FindFirstChild("Title") :: TextLabel
	local caption = title:Clone()
	caption.Name = "Caption"
	caption.Text = ""
	caption.Position = UDim2.fromScale(0.5, 1.13)
	caption.Size = UDim2.fromScale(1.1, 0.2)
	caption.Parent = frame

	frame.Parent = holder
	local viewport = StudCell.getViewport(frame) :: ViewportFrame
	-- The real variant is applied on land; the spin shows Normal studs.
	return { frame = frame, viewport = viewport, caption = caption, scale = scale, result = result }
end

local function shake(frame: GuiObject, duration: number)
	local start = os.clock()
	while os.clock() - start < duration do
		frame.Rotation = math.random(-6, 6)
		task.wait(0.03)
	end
	frame.Rotation = 0
end

local function land(card: Card)
	local result = card.result
	local def = Studs.ById[result.Id]
	local variant = Variants.ById[result.Variant]
	local rarityColor = Config.Rarities.Colors[def.Rarity] or Color3.new(1, 1, 1)

	StudCell.setViewport(card.viewport, def, variant)
	StudCell.setRarity(card.frame, def.Rarity)
	Interface.setText(card.frame, Format.studName(def, variant))
	card.caption.Text = `{def.Rarity} · {Format.oneIn(result.OneIn)}`
	card.caption.TextColor3 = rarityColor

	if result.New then
		Interface.setText(card.frame, "NEW!", "Badge", "Badge")
		local badge = card.frame:FindFirstChild("Badge")
		if badge and badge:IsA("TextLabel") then
			badge.TextColor3 = Color3.fromRGB(255, 230, 90)
		end
	end
	if not result.Kept then
		local text = if result.Reason == "Full" then "FULL" else "DELETED"
		Interface.setText(card.frame, text, "Count", "Count")
		local count = card.frame:FindFirstChild("Count")
		if count and count:IsA("TextLabel") then
			count.TextColor3 = Color3.fromRGB(255, 110, 110)
		end
	end

	-- Flash + pop
	local inner = card.frame:FindFirstChild("Frame")
	if inner and inner:IsA("Frame") then
		local original = inner.BackgroundColor3
		inner.BackgroundColor3 = rarityColor
		TweenService:Create(inner, TweenInfo.new(0.5), { BackgroundColor3 = original }):Play()
	end
	card.scale.Scale = 1.3
	TweenService:Create(card.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	Interface.play("Click", 1.2)
end

local function reveal(results: { RollResult }, quick: boolean)
	local spinTime = if quick then UIConfig.Reveal.AutoSpinTime else UIConfig.Reveal.SpinTime
	local holdTime = if quick then UIConfig.Reveal.AutoHoldTime else UIConfig.Reveal.HoldTime

	local cards: { Card } = {}
	for i, result in results do
		local card = makeCard(result, i)
		table.insert(cards, card)
	end

	holder.Visible = true
	holder.GroupTransparency = 1
	TweenService:Create(holder, Interface.FAST, { GroupTransparency = 0 }):Play()

	-- Spin: swap random studs in, slowing down towards the end.
	local pool = spinPool()
	local normal = Variants.ById.Normal
	local start = os.clock()
	while os.clock() - start < spinTime do
		local progress = (os.clock() - start) / spinTime
		for _, card in cards do
			local def = pool[math.random(#pool)]
			StudCell.setViewport(card.viewport, def, normal)
			StudCell.setRarity(card.frame, def.Rarity)
			Interface.setText(card.frame, def.Name)
		end
		Interface.play("Hover", 0.9 + progress * 0.5)
		task.wait(0.04 + progress * progress * 0.16)
	end

	-- Land in order; anything dramatic gets a wind-up first.
	for _, card in cards do
		if card.result.OneIn >= UIConfig.Reveal.DramaOneIn and not quick then
			shake(card.frame, 0.45)
		end
		land(card)
		task.wait(if quick then 0.05 else 0.15)
	end

	task.wait(holdTime)
	local fade = TweenService:Create(holder, Interface.FAST, { GroupTransparency = 1 })
	fade:Play()
	fade.Completed:Wait()
	holder.Visible = false
	for _, card in cards do
		card.frame:Destroy()
	end
end

--------------------------------------------------------------------------
-- Rolling
--------------------------------------------------------------------------

local function setBusy(value: boolean)
	busy = value
	RollReveal.BusyChanged:Fire(value)
end

function RollReveal.isBusy(): boolean
	return busy
end

function RollReveal.isAuto(): boolean
	return auto
end

-- What the Roll button would do right now: "free", "paid" or nil (can't).
function RollReveal.nextRollKind(): string?
	if (State.get("FreeRolls") or 0) > 0 then
		return "free"
	end
	if (State.get("Clacks") or 0) >= Config.Rolls.ClackCost then
		return "paid"
	end
	return nil
end

-- One roll (free first, then paid). Returns true if a roll happened.
function RollReveal.roll(quick: boolean?): boolean
	if busy or not State.isReady() then return false end
	local kind = RollReveal.nextRollKind()
	if not kind then
		if not auto then
			Interface.toast(`Walk the keys for free rolls, or earn {Format.number(Config.Rolls.ClackCost)} Clacks`)
		end
		return false
	end

	setBusy(true)
	local response = State.roll(1, kind == "free")
	if not response.Ok then
		setBusy(false)
		Interface.toastError(response)
		return false
	end
	local ok, err = pcall(function()
		reveal(response.Results, quick == true)
	end)
	if not ok then
		warn("[RollReveal]", err)
		holder.Visible = false
	end
	setBusy(false)
	return true
end

function RollReveal.setAuto(value: boolean)
	if auto == value then return end
	auto = value
	RollReveal.AutoChanged:Fire(value)
	if not value then return end

	task.spawn(function()
		while auto do
			if not RollReveal.roll(true) then
				task.wait(0.5) -- nothing to spend yet; check again shortly
			else
				task.wait(Config.Rolls.Cooldown * 0.2)
			end
		end
	end)
end

--------------------------------------------------------------------------
-- Announcements → chat
--------------------------------------------------------------------------

local function announce(payload: any)
	local def = Studs.ById[payload.Id]
	local variant = Variants.ById[payload.Variant]
	if not def or not variant then return end
	local color = Format.hex(Config.Rarities.Colors[def.Rarity] or Color3.new(1, 1, 1))
	local text = string.format(
		'<font color="%s"><b>%s rolled %s (%s)!</b></font>',
		color,
		tostring(payload.Player),
		Format.studName(def, variant),
		Format.oneIn(payload.OneIn)
	)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local system = channels and channels:FindFirstChild("RBXSystem")
	if system and system:IsA("TextChannel") then
		system:DisplaySystemMessage(text)
	end
end

function RollReveal.start()
	Interface.setup()
	buildGui()
	State.Announced:Connect(announce)
end

return RollReveal
