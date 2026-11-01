--!strict
-- ModuleScript -> ReplicatedStorage/MenuSystem/Menus/PurchaseController
--
-- Buttons that prompt a purchase, and labels that show a price.
--
-- BUTTONS
--   Gamepass         = true   and  GamepassID         = 123456789
--   DeveloperProduct = true   and  DeveloperProductID = 987654321
--   RobloxPlus       = true                              (no id needed)
--
-- PRICE LABELS anywhere, no button required:
--   GamepassPrice = 123456789    fills with the price, or the owned text
--   ProductPrice  = 987654321    fills with the price
--   PlusPrice     = true         fills with the Plus text
--
-- Both accept per-instance overrides:
--   PriceFormat   = "R$ %s"      wraps the number
--   OwnedText     = "UNLOCKED"   replaces the price once owned
--   HideWhenOwned = true         removes it instead
--
-- Prices are fetched once per id and shared, so twenty labels showing the
-- same pass cost one network call between them.
--
-- ONE-TIME PURCHASES should be gamepasses: Roblox records ownership
-- permanently and for free. Developer products record nothing, so a
-- one-time unlock built on one means you own the ownership record, and
-- losing it means a player loses something they paid for.

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local MenuSystem = script.Parent.Parent
local Config = require(MenuSystem.Config)
local ButtonBounce = require(MenuSystem.Core.ButtonBounce)
local Signal = require(MenuSystem.Core.Signal)
local StateStyle = require(script.Parent.StateStyle)
local Registry = require(script.Parent.Registry)

local ATTR = Config.Attributes
local BUY = Config.Purchase

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PurchaseController = {}

PurchaseController.Prompted = Signal.new()    -- (kind, id, button)
PurchaseController.Finished = Signal.new()    -- (kind, id, purchased)
PurchaseController.PlusChanged = Signal.new() -- (hasPlus)

local KIND_GAMEPASS = "Gamepass"
local KIND_PRODUCT = "Product"
local KIND_PLUS = "RobloxPlus"

local owned: { [number]: boolean } = {}
local entries: { [GuiButton]: { Kind: string, Id: number? } } = {}
local labels: { [GuiObject]: { Kind: string, Id: number? } } = {}
local bound: { [Instance]: boolean } = {}
local priceCache: { [string]: string } = {}

--------------------------------------------------------------------
-- ROBLOX PLUS
--------------------------------------------------------------------

-- A live property rather than something to persist, so there's no
-- DataStore and no receipt to reconcile.
local function hasPlus(): boolean
	local ok, value = pcall(function()
		return (player :: any).HasRobloxSubscription
	end)

	if not ok then
		warn("[Purchase] HasRobloxSubscription unavailable on this client")
		return false
	end

	return value == true
end

--------------------------------------------------------------------
-- IDS
--------------------------------------------------------------------

-- Accepts a number or a numeric string, since attributes get typed by
-- hand and a copy-pasted id often lands as text. Anything else is worth
-- shouting about: a bad id fails silently at the prompt otherwise.
local function readId(instance: Instance, attribute: string): number?
	local value = instance:GetAttribute(attribute)
	if value == nil then return nil end

	if type(value) == "number" then
		return math.floor(value)
	end

	if type(value) == "string" then
		local parsed = tonumber(value)
		if parsed then return math.floor(parsed) end
	end

	warn(string.format("[Purchase] %s on %s is %s (%s), expected a number",
		attribute, instance:GetFullName(), tostring(value), typeof(value)))
	return nil
end

local function buttonKind(button: GuiButton): (string?, number?)
	if button:GetAttribute(ATTR.RobloxPlus) == true then
		return KIND_PLUS, nil
	end

	if button:GetAttribute(ATTR.Gamepass) == true then
		local id = readId(button, ATTR.GamepassID)
		if id then return KIND_GAMEPASS, id end

		warn(string.format("[Purchase] %s is marked %s but has no valid %s",
			button:GetFullName(), ATTR.Gamepass, ATTR.GamepassID))
		return nil, nil
	end

	if button:GetAttribute(ATTR.DeveloperProduct) == true then
		local id = readId(button, ATTR.DeveloperProductID)
		if id then return KIND_PRODUCT, id end

		warn(string.format("[Purchase] %s is marked %s but has no valid %s",
			button:GetFullName(), ATTR.DeveloperProduct, ATTR.DeveloperProductID))
		return nil, nil
	end

	return nil, nil
end

-- What a price label is showing, if anything
local function labelKind(instance: GuiObject): (string?, number?)
	if instance:GetAttribute(ATTR.PlusPrice) == true then
		return KIND_PLUS, nil
	end

	local passId = readId(instance, ATTR.GamepassPrice)
	if passId then return KIND_GAMEPASS, passId end

	local productId = readId(instance, ATTR.ProductPrice)
	if productId then return KIND_PRODUCT, productId end

	return nil, nil
end

--------------------------------------------------------------------
-- PRICE
--------------------------------------------------------------------

local function comma(value: number): string
	local text = tostring(math.floor(value))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

-- Shared across buttons and labels, so twenty things showing the same
-- pass cost one call between them
local function fetchPrice(kind: string, id: number): string?
	local key = kind .. ":" .. id

	if BUY.CachePrices and priceCache[key] then
		return priceCache[key]
	end

	local infoType = kind == KIND_GAMEPASS
		and Enum.InfoType.GamePass
		or Enum.InfoType.Product

	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(id, infoType)
	end)

	if not ok then
		warn(string.format("[Purchase] couldn't read %s %d: %s",
			kind, id, tostring(info)))
		return nil
	end

	-- An off-sale item returns info with no price rather than erroring
	if not (info and info.PriceInRobux) then
		if Config.Behaviour.Verbose then
			warn(string.format("[Purchase] %s %d has no price; off sale?", kind, id))
		end
		return nil
	end

	local text = comma(info.PriceInRobux)
	priceCache[key] = text
	return text
end

local function formatFor(instance: Instance): string
	local format = instance:GetAttribute(ATTR.PriceFormat)
	if type(format) == "string" and format:find("%%s") then
		return format
	end
	return BUY.PriceFormat
end

local function ownedTextFor(instance: Instance, fallback: string): string
	local text = instance:GetAttribute(ATTR.OwnedText)
	if type(text) == "string" then return text end
	return fallback
end

-- Every label named Price, or PriceContainer's labels, matching how the
-- tooltip handles a text label plus its drop shadow
local function priceTargets(root: GuiObject): { GuiObject }
	local targets = {}
	local suffix = Config.Tooltip.ContainerSuffix

	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == BUY.PriceName then
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				table.insert(targets, d)
			end

		elseif d.Name == BUY.PriceName .. suffix then
			for _, child in ipairs(d:GetDescendants()) do
				if child:IsA("TextLabel") then table.insert(targets, child) end
			end
		end
	end

	return targets
end

local function writeText(root: GuiObject, text: string)
	-- A label carrying the attribute itself is written directly; anything
	-- else looks for Price labels inside it
	if root:IsA("TextLabel") or root:IsA("TextButton") then
		(root :: any).Text = text
		return
	end

	for _, target in ipairs(priceTargets(root)) do
		(target :: any).Text = text
	end
end

--------------------------------------------------------------------
-- OWNERSHIP
--------------------------------------------------------------------

-- Gamepasses only. Developer products record nothing on Roblox's side:
-- they're consumables, and a "one-time" product needs its own record
-- written in ProcessReceipt.
local function checkOwned(id: number): boolean
	if owned[id] ~= nil then return owned[id] end

	local ok, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
	end)

	if not ok then
		warn(string.format("[Purchase] ownership check failed for %d: %s",
			id, tostring(result)))
	end

	owned[id] = ok and result == true
	return owned[id]
end

function PurchaseController.IsOwned(kind: string, id: number?): boolean
	if kind == KIND_PLUS then return hasPlus() end
	if kind == KIND_GAMEPASS and id then return checkOwned(id) end
	return false   -- products are never "owned"
end

--------------------------------------------------------------------
-- REFRESH
--------------------------------------------------------------------

local function applyOwned(instance: GuiObject, text: string)
	if instance:GetAttribute(ATTR.HideWhenOwned) == true then
		instance.Visible = false
		return
	end

	-- Reuses the Toggled look, so an owned pass or an active subscription
	-- is styled with the same attributes as any other two-state button
	if StateStyle.IsStyled(instance) then
		StateStyle.Apply(instance, true)
	end

	if text ~= "" then writeText(instance, text) end
end

-- Shared by buttons and labels: both show a price, an owned state, or a
-- fallback, and differ only in whether they also prompt
local function refresh(instance: GuiObject, kind: string, id: number?)
	if kind == KIND_PLUS then
		if hasPlus() then
			applyOwned(instance, ownedTextFor(instance, BUY.PlusOwnedText))
		else
			instance.Visible = true
			if StateStyle.IsStyled(instance) then
				StateStyle.Initialise(instance, false)
			end
			writeText(instance, BUY.PlusText)
		end
		return
	end

	if kind == KIND_GAMEPASS and id and checkOwned(id) then
		applyOwned(instance, ownedTextFor(instance, BUY.OwnedText))
		return
	end

	if StateStyle.IsStyled(instance) then
		StateStyle.Initialise(instance, false)
	end

	if not id then return end

	local price = fetchPrice(kind, id)

	if price then
		writeText(instance, string.format(formatFor(instance), price))
	else
		-- Off sale, or the lookup failed. Blanking it would look broken.
		writeText(instance, BUY.PriceErrorText)
	end
end

local function refreshAll()
	for button, entry in pairs(entries) do
		if button.Parent then
			task.spawn(refresh, button, entry.Kind, entry.Id)
		end
	end

	for label, entry in pairs(labels) do
		if label.Parent then
			task.spawn(refresh, label, entry.Kind, entry.Id)
		end
	end
end

--------------------------------------------------------------------
-- PUBLIC
--------------------------------------------------------------------

function PurchaseController.Owns(id: number): boolean
	return owned[id] == true
end

function PurchaseController.HasPlus(): boolean
	return hasPlus()
end

-- Price as displayed, for building a string elsewhere
function PurchaseController.GetPrice(kind: string, id: number): string?
	return fetchPrice(kind, id)
end

-- Full product info: name, description, price. Uncached.
function PurchaseController.GetInfo(kind: string, id: number)
	local infoType = kind == KIND_GAMEPASS
		and Enum.InfoType.GamePass
		or Enum.InfoType.Product

	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(id, infoType)
	end)

	if not ok then
		warn(string.format("[Purchase] couldn't read %s %d: %s",
			kind, id, tostring(info)))
		return nil
	end

	return info
end

-- Call after granting something server-side so everything restyles
-- without waiting for a rejoin. No id clears the lot.
function PurchaseController.Invalidate(id: number?)
	if id then
		owned[id] = nil
	else
		table.clear(owned)
	end

	refreshAll()
end

function PurchaseController.Prompt(kind: string, id: number?)
	if kind == KIND_PLUS then
		-- Prompting from inside the experience is what earns the creator
		-- bonus; sending them to a web page doesn't
		local ok, err = pcall(function()
			MarketplaceService:PromptRobloxSubscriptionPurchase(player)
		end)

		if not ok then
			warn("[Purchase] PromptRobloxSubscriptionPurchase failed: " .. tostring(err))
		end

	elseif kind == KIND_GAMEPASS and id then
		MarketplaceService:PromptGamePassPurchase(player, id)

	elseif id then
		MarketplaceService:PromptProductPurchase(player, id)
	end
end

function PurchaseController.Describe()
	print("[Purchase] Roblox Plus: " .. tostring(hasPlus()))

	print("[Purchase] buttons:")
	for button, entry in pairs(entries) do
		print(string.format("    %-11s %-12s %s%s",
			entry.Kind,
			entry.Id and tostring(entry.Id) or "-",
			button:GetFullName(),
			PurchaseController.IsOwned(entry.Kind, entry.Id) and "  (owned)" or ""))
	end

	print("[Purchase] price labels:")
	for label, entry in pairs(labels) do
		print(string.format("    %-11s %-12s %s",
			entry.Kind,
			entry.Id and tostring(entry.Id) or "-",
			label:GetFullName()))
	end
end

--------------------------------------------------------------------
-- BINDING
--------------------------------------------------------------------

function PurchaseController.Bind(button: GuiButton)
	if bound[button] then return end

	local kind, id = buttonKind(button)
	if not kind then return end

	bound[button] = true
	entries[button] = { Kind = kind, Id = id }

	if button:GetAttribute(ATTR.Bounce) ~= false then
		ButtonBounce.apply(button, button:GetAttribute(ATTR.BounceHover))
	end

	task.spawn(refresh, button, kind, id)

	button.Activated:Connect(function()
		-- Prompting for something they already have opens a dead-end dialog
		if PurchaseController.IsOwned(kind, id) then return end

		PurchaseController.Prompted:Fire(kind, id, button)
		PurchaseController.Prompt(kind, id)
	end)

	button.Destroying:Connect(function()
		bound[button] = nil
		entries[button] = nil
	end)

	if Config.Behaviour.Verbose then
		print(string.format("[Purchase] button %s -> %s %s",
			button.Name, kind, id and tostring(id) or ""))
	end
end

-- A label that shows a price without prompting anything
function PurchaseController.BindLabel(instance: GuiObject)
	-- Own table, not Bind's: a buy button can also show its own price
	if labels[instance] then return end

	local kind, id = labelKind(instance)
	if not kind then return end

	labels[instance] = { Kind = kind, Id = id }

	-- Something has to show while the lookup is in flight, or the label
	-- reads as whatever placeholder was left in Studio
	if BUY.PriceLoadingText ~= "" then
		writeText(instance, BUY.PriceLoadingText)
	end

	task.spawn(refresh, instance, kind, id)

	instance.Destroying:Connect(function()
		bound[instance] = nil
		labels[instance] = nil
	end)

	if Config.Behaviour.Verbose then
		print(string.format("[Purchase] label %s -> %s %s",
			instance.Name, kind, id and tostring(id) or ""))
	end
end

local function consider(instance: Instance)
	if not instance:IsA("GuiObject") then return end

	if instance:IsA("GuiButton") then
		PurchaseController.Bind(instance)
	end

	PurchaseController.BindLabel(instance)
end

--------------------------------------------------------------------

function PurchaseController.Start()
	Registry.ButtonAdded:Connect(PurchaseController.Bind)

	-- Price labels aren't buttons, so Registry never announces them
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		consider(descendant)
	end

	playerGui.DescendantAdded:Connect(function(instance)
		-- Attributes are usually set a frame after parenting
		task.defer(function()
			if instance.Parent then consider(instance) end
		end)
	end)

	-- Tagged instances, for bulk-marking in the tag editor
	for _, instance in ipairs(CollectionService:GetTagged(Config.Tags.Price)) do
		consider(instance)
	end

	CollectionService:GetInstanceAddedSignal(Config.Tags.Price):Connect(consider)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(_, id, purchased)
		if purchased then
			owned[id] = true
			refreshAll()
		end

		PurchaseController.Finished:Fire(KIND_GAMEPASS, id, purchased)
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(_, id, purchased)
		PurchaseController.Finished:Fire(KIND_PRODUCT, id, purchased)
	end)

	-- The prompt closing doesn't guarantee they subscribed, so the
	-- property is the thing that's actually checked
	local finished = (MarketplaceService :: any).PromptRobloxSubscriptionPurchaseFinished
	if finished then
		finished:Connect(function()
			task.wait(BUY.PlusRecheckDelay)

			local subscribed = hasPlus()
			refreshAll()

			PurchaseController.Finished:Fire(KIND_PLUS, nil, subscribed)
			PurchaseController.PlusChanged:Fire(subscribed)
		end)
	else
		warn("[Purchase] PromptRobloxSubscriptionPurchaseFinished unavailable")
	end

	-- Subscribing on the website or in another experience changes the
	-- property without any prompt firing here
	pcall(function()
		player:GetPropertyChangedSignal("HasRobloxSubscription"):Connect(function()
			local subscribed = hasPlus()
			refreshAll()
			PurchaseController.PlusChanged:Fire(subscribed)
		end)
	end)
end

return PurchaseController