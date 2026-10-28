--[[

Tutorial
ModuleScript
/ReplicatedStorage/Shared/Tutorial

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- First-session tutorial steps. PlayerData.Tutorial is the index of the
-- current step (#Steps + 1 = finished). Each step's Done check reads saved
-- data only, so the server can verify it (Systems/Tutorial) and the client
-- can show progress with the same code.
--
-- Target tells the client what to point at: "Keys" (nearest key in the
-- player's zone), "Tile" (an active +1 tile), or a HUD button name.

local Upgrades = require(script.Parent.Upgrades)

export type Step = {
	Id: string,
	Text: string,
	Target: string,
	Done: (data: any) -> boolean,
	Progress: ((data: any) -> (number, number))?,
}

local steps: { Step } = {
	{
		Id = "Walk",
		Text = "Walk on the keys to earn Clacks!",
		Target = "Keys",
		Done = function(data)
			return (data.TotalPresses or 0) >= 30
		end,
		Progress = function(data)
			return math.min(data.TotalPresses or 0, 30), 30
		end,
	},
	{
		Id = "Roll",
		Text = "Press ROLL to roll your first stud!",
		Target = "Roll",
		Done = function(data)
			return (data.TotalRolls or 0) >= 1
		end,
	},
	{
		Id = "Equip",
		Text = "Open Studs and equip your best stud",
		Target = "Studs",
		Done = function(data)
			return #(data.Equipped or {}) >= 1
		end,
	},
	{
		Id = "Tile",
		Text = "Step on a glowing +1 tile for a free roll",
		Target = "Tile",
		Done = function(data)
			return (data.TilesClaimed or 0) >= 1
		end,
	},
	{
		Id = "Auto",
		Text = "Buy Auto Roll in the Upgrade tree",
		Target = "Upgrades",
		Done = function(data)
			return Upgrades.level(data.Upgrades, "AutoRoll") >= 1
		end,
		Progress = function(data)
			local cost = Upgrades.cost(Upgrades.ById.AutoRoll, 0)
			return math.min(math.floor(data.Clacks or 0), cost), cost
		end,
	},
}

return {
	Steps = steps,
	Finished = #steps + 1,
}
