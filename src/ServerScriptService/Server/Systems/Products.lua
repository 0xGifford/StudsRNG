--[[

Products
ModuleScript
/ServerScriptService/Server/Systems/Products

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Robux: game pass ownership (+ VIP perks) and developer product receipts.
--
-- Receipts follow ProfileStore's purchase-id pattern: the grant and the
-- purchase id are written to the profile together, and the purchase is only
-- reported as granted once a save containing that id has landed. A
-- purchase can't be granted twice or lost to a crash.
--
-- Clients prompt purchases themselves (MarketplaceService); nothing here
-- trusts the client. Ids live in Shared/Products.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local ProductDefs = require(Shared.Products)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local StateSync = require(Systems.StateSync)
local Modifiers = require(Systems.Modifiers)
local Economy = require(Systems.Economy)
local Boosts = require(Systems.Boosts)
local ServerEffects = require(Systems.ServerEffects)
local Rebirth = require(Systems.Rebirth)
local RewardService = require(Systems.RewardService)

local Products = {}

-- Product actions other systems provide (avoids require cycles):
-- Products.registerAction("SummonBoss", fn). fn must not yield for long and
-- must not throw for a player-side reason (the receipt would retry forever).
local actions: { [string]: (Player) -> () } = {}

function Products.registerAction(name: string, fn: (Player) -> ())
	actions[name] = fn
end

local PURCHASE_ID_CACHE_SIZE = 100
local TRAIL_NAME = "VIPTrail"

local owned: { [Player]: { [string]: boolean } } = {}

--------------------------------------------------------------------------
-- Game passes
--------------------------------------------------------------------------

local function addTrail(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (root and root:IsA("BasePart")) or root:FindFirstChild(TRAIL_NAME) then return end

	local top = Instance.new("Attachment")
	top.Name = "VIPTrailTop"
	top.Position = Vector3.new(0, 0.8, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "VIPTrailBottom"
	bottom.Position = Vector3.new(0, -0.8, 0)
	bottom.Parent = root

	local colors = Config.VIP.TrailColors
	local trail = Instance.new("Trail")
	trail.Name = TRAIL_NAME
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(colors[1], colors[2])
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Lifetime = 0.45
	trail.LightEmission = 0.6
	trail.FaceCamera = true
	trail.Parent = root
end

local function applyPasses(player: Player)
	local passes = owned[player] or {}
	Modifiers.setPasses(player, table.clone(passes))
	StateSync.setVolatile(player, "Passes", table.clone(passes))
	player:SetAttribute("VIP", passes.VIP == true)
	if passes.VIP and player.Character then
		task.spawn(addTrail, player.Character)
	end
end

local function loadPasses(player: Player)
	local passes: { [string]: boolean } = {}
	for key, def in ProductDefs.Passes do
		if def.Id ~= 0 then
			local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, def.Id)
			if ok and has then
				passes[key] = true
			elseif not ok then
				warn(`[Products] ownership check failed for {key}: {has}`)
			end
		end
	end
	if player.Parent ~= Players then return end
	-- Keep anything granted while we were checking (a purchase mid-join).
	for key, value in owned[player] or {} do
		passes[key] = passes[key] or value
	end
	owned[player] = passes
	applyPasses(player)
end

function Products.ownsPass(player: Player, key: string): boolean
	local passes = owned[player]
	return passes ~= nil and passes[key] == true
end

--------------------------------------------------------------------------
-- Developer products
--------------------------------------------------------------------------

-- Throws on failure so the receipt stays unprocessed (and is retried).
local function grantProduct(player: Player, key: string)
	local def = ProductDefs.Products[key]
	assert(def, `unknown product {key}`)

	if def.Clacks then
		Economy.addClacks(player, def.Clacks)
	end
	if def.Spins then
		RewardService.addSpins(player, def.Spins)
	end
	if def.FreeRolls then
		Economy.addFreeRolls(player, def.FreeRolls, true)
	end
	if def.Boost then
		local boost = Config.Boosts[def.Boost]
		assert(boost, `unknown boost {def.Boost}`)
		assert(Boosts.add(player, def.Boost, boost.Duration), "boost grant failed")
	end
	if def.Luck then
		RewardService.addLuck(player, def.Luck)
	end
	if def.ServerLuck then
		ServerEffects.addServerLuck(player)
	end
	if def.Action == "SkipRebirth" then
		local result = Rebirth.perform(player, true)
		assert(result.Ok, `rebirth failed: {result.Error}`)
	elseif def.Action == "SkipPlaytime" then
		RewardService.skipPlaytime(player)
	elseif def.Action then
		local action = actions[def.Action]
		assert(action, `no handler for action {def.Action}`)
		action(player)
	end
	if def.OneTime then
		local data = PlayerData.get(player)
		if data then
			data.Bought[key] = true
			StateSync.push(player, "Bought", data.Bought)
		end
	end
end

local function purchaseIdCheckAsync(profile: any, purchaseId: string, grant: () -> ()): Enum.ProductPurchaseDecision
	if profile:IsActive() ~= true then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local cache = profile.Data.PurchaseIds
	if table.find(cache, purchaseId) == nil then
		local ok, err = pcall(grant)
		if not ok then
			warn(`[Products] grant failed for {profile.Key} / {purchaseId}: {err}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		while #cache >= PURCHASE_ID_CACHE_SIZE do
			table.remove(cache, 1)
		end
		table.insert(cache, purchaseId)
	end

	local function isSaved(): boolean
		local saved = profile.LastSavedData and profile.LastSavedData.PurchaseIds
		return saved ~= nil and table.find(saved, purchaseId) ~= nil
	end

	if isSaved() then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	while profile:IsActive() == true do
		local lastSaved = profile.LastSavedData
		profile:Save()
		if profile.LastSavedData == lastSaved then
			profile.OnAfterSave:Wait()
		end
		if isSaved() then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if profile:IsActive() == true then
			task.wait(10)
		end
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local key = ProductDefs.productKey(receipt.ProductId)
	if not key then
		warn(`[Products] receipt for unknown product id {receipt.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- The player may still be loading.
	if not PlayerData.waitFor(player, 30) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = PlayerData.getProfile(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local granted = false
	local decision = purchaseIdCheckAsync(profile, receipt.PurchaseId, function()
		grantProduct(player, key)
		granted = true
	end)

	if granted and player.Parent == Players then
		local def = ProductDefs.Products[key]
		Net.fire(player, "Notify", { Text = `Thanks! {def.Name} received.`, Color = Color3.fromRGB(120, 255, 140) })
	end
	return decision
end

--------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------

function Products.init()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then return end
		local key = ProductDefs.passKey(passId)
		if not key then return end
		local passes = owned[player] or {}
		passes[key] = true
		owned[player] = passes
		applyPasses(player)
		Net.fire(player, "Notify", { Text = `Thanks! {ProductDefs.Passes[key].Name} unlocked.`, Color = Color3.fromRGB(120, 255, 140) })
	end)

	PlayerData.Loaded:Connect(function(player)
		task.spawn(loadPasses, player)
	end)

	local function track(player: Player)
		player.CharacterAdded:Connect(function(character)
			if Products.ownsPass(player, "VIP") then
				addTrail(character)
			end
		end)
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
	end)
end

return Products
