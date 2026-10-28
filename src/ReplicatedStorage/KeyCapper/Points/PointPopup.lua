--!strict
-- Single responsibility: one "+1" flying from a keycap into the counter.
-- Fire and forget — Spawn() builds it, animates it, cleans it up, and calls
-- back once at the moment it is absorbed. Owns no state between popups, so
-- any number of them can be in the air at once without interfering.
--
-- The whole flight is hand-driven from a single Heartbeat rather than
-- assembled from TweenService tweens. Three reasons, all of them things that
-- were wrong when it was tweens:
--   * the arc cannot be expressed as a position tween at all;
--   * the target MOVES (the counter widens as it gains digits), so the
--     destination has to be re-read every frame, not baked in at spawn;
--   * scale, rotation, position and fade have to stay in lockstep. As
--     separate tweens on separate clocks they drifted, and the pop-in was
--     still finishing while the travel had already started — which read as
--     two animations fighting instead of one object moving.

local RunService = game:GetService("RunService")

-- WaitForChild, not a plain index: this whole folder is cloned into the
-- user's game by the plugin's Installer and replicated to the client, and a
-- sibling is not guaranteed to have arrived when this module first runs.
local Counter = require(script.Parent:WaitForChild("Counter"))

local PointPopup = {}

local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)

-- Every pixel metric here is scaled by Counter.SCALE, the HUD's single size
-- knob, so the popup always stays in proportion with the counter it feeds.
local SCALE = Counter.SCALE

-- Strictly below the counter's own size, and the peak of the pop-in overshoot
-- below is applied on top of THIS — so a "+1" never renders larger than the
-- total it is feeding, at any point in its flight. The gap is scaled too:
-- a fixed 8px gap would vanish at a large SCALE and the two would read as
-- the same size.
local TEXT_SIZE = Counter.TEXT_SIZE - 8 * SCALE
local DURATION = 0.55

-- How far above the straight line the arc's midpoint sits, and how far to
-- either side: a straight shot from cap to counter reads as the label sliding
-- rather than popping, and always bowing the same way reads as mechanical
-- once a few have landed in a row.
local ARC_HEIGHT = 90 * SCALE
local ARC_SPREAD = 70 * SCALE

-- Phase boundaries, as fractions of DURATION.
local POP_UNTIL = 0.28 -- scaling up out of nothing
local ABSORB_FROM = 0.72 -- shrinking into the counter
local FADE_FROM = 0.78 -- fading, deliberately AFTER the shrink starts so it
                       -- visibly shrinks before it vanishes: fading first
                       -- just deletes it, fading second reads as swallowed
local ABSORB_SCALE = 0.45
-- Not scaled: a tilt is an angle, and angles do not have a pixel size.
local TILT_DEGREES = 12

-- Overshoot curve: 0 -> past 1 -> settles at exactly 1. Does the pop-in and
-- its settle in ONE continuous curve, which is why the pop needs no separate
-- settle tween chasing it.
local BACK_C1 = 1.70158
local BACK_C3 = BACK_C1 + 1
local function backOut(x: number): number
	local p = x - 1
	return 1 + BACK_C3 * p * p * p + BACK_C1 * p * p
end

-- startPosition: screen-space pixels. targetOf: called every frame for the
-- counter's current center. onLand: fired once, at absorption.
function PointPopup.Spawn(
	gui: ScreenGui,
	startPosition: Vector2,
	targetOf: () -> Vector2,
	onLand: () -> ()
)
	local popup = Instance.new("TextLabel")
	popup.Name = "Popup"
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Position = UDim2.fromOffset(startPosition.X, startPosition.Y)
	popup.Size = UDim2.new(0, 0, 0, TEXT_SIZE)
	popup.AutomaticSize = Enum.AutomaticSize.X
	popup.BackgroundTransparency = 1
	popup.TextSize = TEXT_SIZE
	popup.FontFace = FONT
	popup.TextColor3 = Color3.new(1, 1, 1)
	popup.TextStrokeTransparency = 1
	popup.Text = "+1"
	popup.ZIndex = 5
	popup.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = Counter.STROKE_THICKNESS
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = popup

	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = popup

	-- Which way this one bows. Random per popup so a run of them fans out
	-- instead of retracing one path.
	local side = math.random() < 0.5 and -1 or 1

	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		local t = math.clamp(elapsed / DURATION, 0, 1)

		-- Re-read the destination every frame, and rebuild the arc around it:
		-- the counter drifts sideways as it gains a digit, and a popup already
		-- in the air has to follow it there rather than land where the counter
		-- used to be.
		local target = targetOf()
		local mid = (startPosition + target) / 2 + Vector2.new(side * ARC_SPREAD, -ARC_HEIGHT)

		-- Eased travel parameter: hangs by the cap while it pops in, then
		-- accelerates into the counter. A linear parameter made the popup
		-- leave before the eye had registered it and coast in at the end —
		-- exactly backwards from what should feel urgent.
		local travel = t ^ 1.7
		local a = startPosition:Lerp(mid, travel)
		local b = mid:Lerp(target, travel)
		local position = a:Lerp(b, travel)
		popup.Position = UDim2.fromOffset(position.X, position.Y)

		if t < POP_UNTIL then
			scale.Scale = backOut(t / POP_UNTIL)
		elseif t >= ABSORB_FROM then
			local k = (t - ABSORB_FROM) / (1 - ABSORB_FROM)
			scale.Scale = 1 - (1 - ABSORB_SCALE) * k
		else
			scale.Scale = 1
		end

		-- Unwinds as it flies: most tilted at launch, upright by arrival, so
		-- it settles into the counter's own orientation instead of hitting it
		-- askew.
		popup.Rotation = side * TILT_DEGREES * (1 - travel)

		local fade = t > FADE_FROM and (t - FADE_FROM) / (1 - FADE_FROM) or 0
		popup.TextTransparency = fade
		stroke.Transparency = fade

		if t >= 1 then
			connection:Disconnect()
			popup:Destroy()
			onLand()
		end
	end)
end

return PointPopup
