--[[ 

Types
ModuleScript
/ReplicatedStorage/Shared/Types

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Types that cross the client/server boundary.

export type StudDef = {
	Id: string,
	Name: string,
	Rarity: string,
	OneIn: number,
	Multiplier: number,
	World: string,
	Color: Color3,
	Material: Enum.Material,
	Particle: string?,
	Light: boolean?,
}

export type VariantDef = {
	Name: string,
	OneIn: number,
	Multiplier: number,
	Effect: string?,
	ColorOverride: Color3?,
	MaterialOverride: Enum.Material?,
}

-- Saved profile shape (ProfileStore template lives in Systems/PlayerData).
-- Stud keys are "StudId:Variant", e.g. "Ember:Shiny".
export type PlayerData = {
	Version: number,
	Clacks: number,
	LifetimeClacks: number,
	TotalPresses: number,
	FreeRolls: number,
	RollMeter: number,
	TotalRolls: number,
	Studs: { [string]: number }, -- key → count
	Equipped: { string }, -- keys; the same key may appear more than once
	Index: { [string]: boolean }, -- key → discovered
	AutoDelete: { [string]: boolean }, -- rarity → enabled (Normal variant only)
	UnlockedWorlds: { [string]: boolean },
}

-- Derived from PlayerData by Util/RollLogic.computeStats (same on both sides).
export type Stats = {
	ClackMultiplier: number,
	Luck: number,
	Slots: number,
	Discovered: number,
	IndexTotal: number,
	StudCount: number,
}

export type RollResult = {
	Id: string,
	Variant: string,
	Key: string,
	OneIn: number, -- combined nominal odds (stud × variant)
	New: boolean, -- first time in the index
	Kept: boolean, -- added to inventory
	Reason: string?, -- "AutoDelete" | "Full" when not kept
}

-- Every RemoteFunction answers with this shape.
export type Response = {
	Ok: boolean,
	Error: string?,
	[string]: any,
}

export type StatePatch = {
	Seq: number,
	Data: { [string]: any },
}

return {}
