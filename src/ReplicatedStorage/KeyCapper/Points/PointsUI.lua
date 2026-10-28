--!strict
-- Single responsibility: own the points HUD as a whole — create it, keep the
-- number it should be showing, and turn a local key press into a "+1" in
-- flight. The pixels and the motion belong to Counter and PointPopup; this
-- module is the orchestrator and holds the only public API (Init/Notify).
--
-- Purely cosmetic and purely local: never the source of truth for the count
-- (that's Player.KeyCapperData.Points, owned by Server.lua and replicated
-- automatically since it lives under the Player instance), only a display
-- of it.
--
-- Local display is OPTIMISTIC: every press bumps it immediately, before the
-- batched RemoteEvent (see Client.lua) has even reached the server. Mirroring
-- points.Value directly would make the counter visibly stutter — it would sit
-- still for up to POINTS_BATCH_INTERVAL, then jump. Instead the server value
-- is only ever allowed to push the display UP, never down: our own presses
-- are already reflected the instant they happen, so the server catching up a
-- second later is not new information and must not un-count anything. It can
-- still only push it up, e.g. a client rejoining with a higher persisted
-- total than whatever it predicted this session.
--
-- Note the two clocks that follow from that. `displayed` moves the moment a
-- key goes down; the COUNTER only reacts (punch, shockwave, sound) when the
-- "+1" actually arrives, ~0.55s later. Landing the impact on key-down instead
-- would fire it while the popup is still mid-flight, and the popup would then
-- fly into a counter that had already finished celebrating it.

local Players = game:GetService("Players")

local PointsFolder = script.Parent
local Counter = require(PointsFolder:WaitForChild("Counter"))
local PointPopup = require(PointsFolder:WaitForChild("PointPopup"))

local PointsUI = {}

local GUI_NAME = "KeyCapperPointsUI"

local player = Players.LocalPlayer

local displayed = 0
local counter = nil :: any
local screenGui: ScreenGui? = nil

-- pointsValue: the player's Player.KeyCapperData.Points IntValue. Owned and
-- written by Server.lua; this module only ever reads it.
function PointsUI.Init(pointsValue: IntValue)
	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")
	screenGui = gui

	counter = Counter.new(gui)
	displayed = pointsValue.Value
	counter:Set(displayed)

	pointsValue.Changed:Connect(function(newValue: number)
		if newValue > displayed then
			displayed = newValue
			-- Rolls rather than snaps, because this is always a jump of more
			-- than one (see Counter:Set). No impact is played: nothing was
			-- pressed, the server merely told us we own more than we thought.
			counter:Set(displayed)
		end
	end)
end

-- Called once per local press, optimistically — before the batch that press
-- belongs to has even gone out, let alone come back confirmed.
function PointsUI.Notify(worldPosition: Vector3)
	local gui = screenGui
	if not (gui and counter) then return end

	displayed += 1
	counter:Set(displayed)

	local camera = workspace.CurrentCamera
	if not camera then return end

	-- Lifted a stud so the "+1" is born above the cap rather than inside it.
	local screenPoint, onScreen = camera:WorldToViewportPoint(worldPosition + Vector3.new(0, 1, 0))
	-- Off-screen presses still count (the number above already moved), they
	-- just get no popup: one flying in from behind the camera would enter the
	-- frame from an arbitrary edge with no visible origin.
	if not onScreen then return end

	PointPopup.Spawn(
		gui,
		Vector2.new(screenPoint.X, screenPoint.Y),
		function()
			return counter:Center()
		end,
		function()
			counter:Land()
		end
	)
end

return PointsUI
