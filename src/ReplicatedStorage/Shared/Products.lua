--[[

Products
ModuleScript
/ReplicatedStorage/Shared/Products

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Every Robux item. Paste the ids from the Creator Hub (Monetization →
-- Passes / Developer Products) into Id. Anything left at 0 shows "Soon" in
-- the shop and can't be bought. Prices come from Roblox, not from here.
--
-- Keys (VIP, LuckyRoll, ...) are referenced by code: rename the display
-- Name freely, never the key.
--
-- Suggested Robux prices (set them in the Creator Hub), from Roblox
-- simulator norms:
--   Passes:   VIP 399 · Double Roll 249 · Fast Roll 149 · +1 Equip 99
--             Stud Pass Premium 499 · Lucky Drops 199 · Stud Trainer 149
--   Products: Starter Pack 49 (one time) · Server Luck 99 · Lucky Roll 25
--             Summon Mini Boss 35 · Spins 25 / 99 / 199 · Boosts 15-35
--             Clacks 49 / 299 / 699 · Skip Rebirth 75 · Skip Rewards 49

export type PassDef = {
	Id: number,
	Name: string,
	Description: string,
	Icon: string, -- rbxassetid:// image or an emoji
	Color: string, -- card colour: Orange | Green | Blue | Purple | Sunset
	Order: number,
}

export type ProductDef = {
	Id: number,
	Name: string,
	Description: string,
	Icon: string,
	Color: string,
	Section: string?, -- shop section; nil = not listed (bought from another menu)
	Order: number,
	Badge: string?, -- corner tag, e.g. "+50%"
	-- What it grants (handled by Systems/Products):
	Clacks: number?,
	Spins: number?,
	Boost: string?, -- Config.Boosts id
	Luck: number?, -- permanent luck
	ServerLuck: boolean?,
	FreeRolls: number?,
	Action: string?, -- "SkipRebirth" | "SkipPlaytime" | "SummonBoss" (Products.registerAction)
	OneTime: boolean?, -- bought once (PlayerData.Bought); hidden from the shop after
}

local passes: { [string]: PassDef } = {
	VIP = { Id = 0, Name = "VIP", Order = 1, Color = "Orange", Icon = "rbxassetid://92190045509168",
		Description = "[VIP] chat tag, a golden trail, +25% Clacks and +25% luck." },
	DoubleRoll = { Id = 0, Name = "Double Roll", Order = 2, Color = "Purple", Icon = "🎲",
		Description = "Roll 2 studs every roll." },
	FastRoll = { Id = 0, Name = "Fast Roll", Order = 3, Color = "Blue", Icon = "⚡",
		Description = "Roll twice as fast." },
	ExtraEquip = { Id = 0, Name = "+1 Equip", Order = 4, Color = "Green", Icon = "➕",
		Description = "Equip an extra stud." },
	LuckyDrops = { Id = 0, Name = "Lucky Drops", Order = 6, Color = "Purple", Icon = "🎁",
		Description = "x2 chance of boss drops from Mini Bosses and Titans." },
	StudTrainer = { Id = 0, Name = "Stud Trainer", Order = 7, Color = "Green", Icon = "⭐",
		Description = "Your studs earn x2 XP from every fight." },
	StudPass = { Id = 0, Name = "Stud Pass Premium", Order = 5, Color = "Orange", Icon = "🎟️",
		Description = "Unlocks the premium track of this season's Stud Pass: every premium reward, back to tier 1, plus the Champion stud." },
}

local products: { [string]: ProductDef } = {
	-- Featured
	StarterPack = { Id = 0, Name = "Starter Pack", Section = "Featured", Order = 0, Color = "Orange",
		Icon = "🎁", OneTime = true, Luck = 2, Spins = 10, FreeRolls = 50, Boost = "UltraLuck", Badge = "ONCE",
		Description = "One time only: +2 permanent luck, 10 jackpot spins, 50 free rolls and an Ultra Luck boost." },
	SummonBoss = { Id = 0, Name = "Summon Mini Boss", Section = "Featured", Order = 3, Color = "Sunset",
		Icon = "👑", Action = "SummonBoss",
		Description = "A Mini Boss appears right next to you: big Clacks, XP and a shot at a boss drop." },
	ServerLuck = { Id = 0, Name = "Server Luck x2", Section = "Featured", Order = 1, Color = "Green",
		Icon = "rbxassetid://119611914627070", ServerLuck = true,
		Description = "Doubles EVERYONE's luck in this server for 15 minutes. Buying more adds time." },
	LuckyRoll = { Id = 0, Name = "Lucky Roll", Section = "Featured", Order = 2, Color = "Sunset",
		Icon = "🍀", Luck = 1,
		Description = "+1 permanent luck. Stacks forever. Tap Odds to see what it does." },

	-- Jackpot spins
	Spins1 = { Id = 0, Name = "1 Jackpot Spin", Section = "Spins", Order = 1, Color = "Blue",
		Icon = "rbxassetid://72974128962815", Spins = 1, Description = "One spin of the jackpot wheel." },
	Spins5 = { Id = 0, Name = "5 Jackpot Spins", Section = "Spins", Order = 2, Color = "Purple",
		Icon = "rbxassetid://72974128962815", Spins = 5, Badge = "4+1", Description = "4 spins + 1 bonus." },
	Spins12 = { Id = 0, Name = "12 Jackpot Spins", Section = "Spins", Order = 3, Color = "Orange",
		Icon = "rbxassetid://72974128962815", Spins = 12, Badge = "8+4", Description = "8 spins + 4 bonus." },

	-- Boosts
	LuckBoost = { Id = 0, Name = "Luck Boost", Section = "Boosts", Order = 1, Color = "Green",
		Icon = "🍀", Boost = "Luck", Description = "+1 luck for 3 minutes." },
	UltraLuckBoost = { Id = 0, Name = "Ultra Luck Boost", Section = "Boosts", Order = 2, Color = "Blue",
		Icon = "🌟", Boost = "UltraLuck", Description = "+2 luck for 3 minutes." },
	SpeedBoost = { Id = 0, Name = "Roll Speed Boost", Section = "Boosts", Order = 3, Color = "Purple",
		Icon = "⚡", Boost = "Speed", Description = "Roll x2 faster for 3 minutes." },
	ClacksBoost = { Id = 0, Name = "Clacks Boost", Section = "Boosts", Order = 4, Color = "Orange",
		Icon = "💰", Boost = "Clacks", Description = "x2 Clacks for 3 minutes." },

	-- Clack packs
	Clacks140K = { Id = 0, Name = "140K Clacks", Section = "Clacks", Order = 1, Color = "Green",
		Icon = "rbxassetid://117187305699068", Clacks = 140_000, Description = "A pouch of Clacks." },
	Clacks2M = { Id = 0, Name = "2.10M Clacks", Section = "Clacks", Order = 2, Color = "Blue",
		Icon = "rbxassetid://117187305699068", Clacks = 2_100_000, Badge = "+50%", Description = "A sack of Clacks, 50% bonus." },
	Clacks5M = { Id = 0, Name = "5.60M Clacks", Section = "Clacks", Order = 3, Color = "Purple",
		Icon = "rbxassetid://117187305699068", Clacks = 5_600_000, Badge = "+100%", Description = "A vault of Clacks, 100% bonus." },

	-- Bought from other menus
	SkipRebirth = { Id = 0, Name = "Skip Rebirth", Order = 0, Color = "Sunset", Icon = "🔁",
		Action = "SkipRebirth", Description = "Rebirth now without the Clacks." },
	SkipPlaytime = { Id = 0, Name = "Skip All Rewards", Order = 0, Color = "Sunset", Icon = "🎁",
		Action = "SkipPlaytime", Description = "Claim every playtime reward now." },
}

local Products = {
	Passes = passes,
	Products = products,
	-- Shop sections, top to bottom ("Passes" lists the game passes).
	Sections = {
		{ Id = "Passes", Title = "Game Passes" },
		{ Id = "Featured", Title = "Featured" },
		{ Id = "Boosts", Title = "Boosts" },
		{ Id = "Spins", Title = "Jackpot Spins" },
		{ Id = "Clacks", Title = "Clack Packs" },
	},
}

local passByAssetId: { [number]: string } = {}
for key, def in passes do
	if def.Id ~= 0 then
		passByAssetId[def.Id] = key
	end
end

local productByAssetId: { [number]: string } = {}
for key, def in products do
	if def.Id ~= 0 then
		assert(not productByAssetId[def.Id], `Product id {def.Id} used twice ({key})`)
		productByAssetId[def.Id] = key
	end
end

function Products.passKey(assetId: number): string?
	return passByAssetId[assetId]
end

function Products.productKey(assetId: number): string?
	return productByAssetId[assetId]
end

return Products
