--[[ 

DevKeys
ModuleScript
/StarterPlayer/StarterPlayerScripts/Client/Controllers/DevKeys

Copyright © 2026. Mosswake, all rights reserved.

]]

--!strict
-- Studio-only test bindings until the real UI exists. Does nothing in a
-- live game. Results print to the Output.
--   R = free roll     T = paid roll     B = equip best    U = unequip all
--   G = +1,000 Clacks  H = +10 free rolls (dev command)   P = print state

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Studs = require(Shared.Studs)
local RollLogic = require(Shared.Util.RollLogic)

local State = require(script.Parent.State)

local DevKeys = {}

local function printRoll(label: string, response: any)
	if not response.Ok then
		print(`[Dev] {label} failed: {response.Error}`)
		return
	end
	for _, result in response.Results do
		local def = Studs.ById[result.Id]
		local status = if result.Kept then "kept" else `not kept ({result.Reason})`
		print(string.format(
			"[Dev] %s → %s %s (%s) 1 in %s%s — %s",
			label,
			result.Variant,
			def and def.Name or result.Id,
			def and def.Rarity or "?",
			tostring(math.floor(result.OneIn)),
			if result.New then " NEW" else "",
			status
			))
	end
end

local function dev(command: string, arg: any)
	local remote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("DevCommand")
	if remote and remote:IsA("RemoteFunction") then
		print("[Dev]", command, remote:InvokeServer(command, arg))
	end
end

local function printState()
	local stats = State.stats()
	print(string.format(
		"[Dev] Clacks %.1f | Free rolls %d | Meter %d/%d | ×%.2f | Luck %.2f | Slots %d | Index %d/%d | Studs %d/%d",
		State.get("Clacks") or 0,
		State.get("FreeRolls") or 0,
		State.get("RollMeter") or 0,
		stats.PressesPerFreeRoll,
		stats.ClackMultiplier,
		stats.Luck,
		stats.Slots,
		stats.Discovered,
		stats.IndexTotal,
		stats.StudCount,
		stats.MaxStuds
		))
	print("[Dev] Equipped:", table.concat(State.get("Equipped") or {}, ", "))
	for _, key in RollLogic.sortedOwned(State.get("Studs") or {}) do
		print(`   {key} ×{State.get("Studs")[key]}`)
	end
end

function DevKeys.start()
	if not RunService:IsStudio() then return end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not State.isReady() then return end
		local key = input.KeyCode
		if key == Enum.KeyCode.R then
			printRoll("Free roll", State.roll(1, true))
		elseif key == Enum.KeyCode.T then
			printRoll("Paid roll", State.roll(1, false))
		elseif key == Enum.KeyCode.B then
			print("[Dev] Equip best:", State.equipBest().Ok)
		elseif key == Enum.KeyCode.U then
			print("[Dev] Unequip all:", State.unequipAll().Ok)
		elseif key == Enum.KeyCode.G then
			dev("Clacks", 1000)
		elseif key == Enum.KeyCode.H then
			dev("FreeRolls", 10)
		elseif key == Enum.KeyCode.P then
			printState()
		end
	end)

	State.Announced:Connect(function(payload)
		print(`[Dev] ANNOUNCE: {payload.Player} rolled {payload.Variant} {payload.Id} (1 in {payload.OneIn})`)
	end)

	print("[Dev] DevKeys active: R/T roll, B best, U unequip, G clacks, H rolls, P print")
end

return DevKeys
