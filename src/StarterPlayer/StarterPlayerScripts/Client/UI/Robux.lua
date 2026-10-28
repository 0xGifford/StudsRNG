--[[

Robux
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/UI/Robux

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Prices and purchase prompts for Shared/Products, by key. Prices are read
-- from Roblox once and cached. Items whose Id is still 0 show "Soon".

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Products)

local Robux = {}

local player = Players.LocalPlayer
local cache: { [string]: number } = {} -- -1 = lookup failed
local loading: { [string]: boolean } = {}

local function idOf(isPass: boolean, key: string): number
	local def = if isPass then Products.Passes[key] else Products.Products[key]
	return if def then def.Id else 0
end

-- Robux price, or nil while unknown (unset id, still loading or failed).
-- Yields on first use for a key.
function Robux.price(isPass: boolean, key: string): number?
	local id = idOf(isPass, key)
	if id == 0 then return nil end
	local cacheKey = `{isPass}:{key}`
	while loading[cacheKey] do
		task.wait(0.1)
	end
	local cached = cache[cacheKey]
	if cached ~= nil then
		return if cached >= 0 then cached else nil
	end
	loading[cacheKey] = true
	local infoType = if isPass then Enum.InfoType.GamePass else Enum.InfoType.Product
	local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
	local price = if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then info.PriceInRobux else nil
	cache[cacheKey] = price or -1
	loading[cacheKey] = nil
	return price
end

-- "Soon", "…" then the price, written into `label` (async).
function Robux.showPrice(label: TextLabel, isPass: boolean, key: string)
	if idOf(isPass, key) == 0 then
		label.Text = "Soon"
		return
	end
	label.Text = "…"
	task.spawn(function()
		local price = Robux.price(isPass, key)
		if label.Parent then
			label.Text = if price then tostring(price) else "?"
		end
	end)
end

-- Opens the Roblox purchase prompt. Returns false when the id isn't set.
function Robux.prompt(isPass: boolean, key: string): boolean
	local id = idOf(isPass, key)
	if id == 0 then return false end
	if isPass then
		MarketplaceService:PromptGamePassPurchase(player, id)
	else
		MarketplaceService:PromptProductPurchase(player, id)
	end
	return true
end

function Robux.available(isPass: boolean, key: string): boolean
	return idOf(isPass, key) ~= 0
end

return Robux
