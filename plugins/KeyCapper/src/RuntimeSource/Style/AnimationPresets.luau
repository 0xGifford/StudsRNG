--!strict
-- Single responsibility: name <-> press-animation shape lookup. Pure data,
-- no tweening logic here — Keycap reads a preset and drives TweenService
-- itself, this module only says WHAT the press should look like.
--
-- Lives inside RuntimeSource: consumed by Keycap at runtime, so it must ship
-- with the game like GuiFactory/FontPresets do.

export type Preset = {
	Name: string,
	-- How far the cap sinks along its own local Y on press, in studs.
	--
	-- Reference for reading these numbers: the cap is Constants.KEY_SIZE.Y =
	-- 1.368 studs tall and rests ON the surface, so a depth of D leaves
	-- 1.368 - D standing proud of it. Under about 0.4 of travel the key does
	-- not look pressed next to its unpressed neighbours, it looks slightly
	-- lower — which is what these presets were all guilty of.
	PressDepth: number,
	-- Per-axis multiplier on the cap's rest Size while pressed.
	--
	-- CEILING on X/Z: Constants.GRID_PITCH / Constants.KEY_SIZE.X, i.e.
	-- 3.15 / 3 = 1.05. At exactly 1.05 a pressed cap fills its cell and its
	-- edges meet its neighbours'; anything above that overlaps them, and on a
	-- full keyboard — where every cell IS occupied — that reads as the key
	-- growing through the ones beside it rather than squashing.
	PressSizeScale: Vector3,
	-- Degrees the cap rocks about its own local X on press. 0 for a pure
	-- vertical press. Applied after the sink, in the cap's local frame, so it
	-- stays correct on a sloped surface like everything else here.
	PressTilt: number,
	PressEasingStyle: Enum.EasingStyle,
	PressEasingDirection: Enum.EasingDirection,
	-- Release always returns to rest CFrame/Size: only the easing differs.
	ReleaseEasingStyle: Enum.EasingStyle,
	ReleaseEasingDirection: Enum.EasingDirection,
}

local AnimationPresets = {}

local PRESETS: { Preset } = {
	{
		Name = "Default",
		-- The original prototype's feel: a plain dip, no shape change.
		-- 1.15 of a 1.368-stud cap leaves ~0.22 standing: the key bottoms out
		-- against the plate instead of hovering part-way down.
		PressDepth = 1.15,
		PressSizeScale = Vector3.new(1, 1, 1),
		PressTilt = 0,
		PressEasingStyle = Enum.EasingStyle.Quad,
		PressEasingDirection = Enum.EasingDirection.Out,
		ReleaseEasingStyle = Enum.EasingStyle.Back,
		ReleaseEasingDirection = Enum.EasingDirection.Out,
	},
	{
		Name = "Slime",
		-- Squash (flatten Y) and spread (widen X/Z) on press, ball-bounce back.
		--
		-- The spread sits ON the 1.05 ceiling documented above, not past it: at
		-- the old 1.28 a pressed cap was 3.84 studs across in a 3.15 cell and
		-- visibly swallowed its neighbours. Filling the cell exactly is what the
		-- squash was ever meant to read as — the cap spreading until it meets
		-- what is next to it, then stopping.
		--
		-- Slime goes DOWN by squashing rather than by travelling: the Y scale is
		-- what makes it look pressed, so it is the number that was raised. At
		-- 0.34 the cap flattens to ~0.47 studs. The depth is not free either —
		-- it has to cover the half-height the squash removes, 0.684 x (1 - 0.34)
		-- = 0.45, or the cap would shrink about its centre and lift off the
		-- surface. 0.55 covers that and sinks the last 0.1 on top.
		PressDepth = 0.55,
		PressSizeScale = Vector3.new(1.05, 0.34, 1.05),
		PressTilt = 0,
		PressEasingStyle = Enum.EasingStyle.Quad,
		PressEasingDirection = Enum.EasingDirection.Out,
		ReleaseEasingStyle = Enum.EasingStyle.Bounce,
		ReleaseEasingDirection = Enum.EasingDirection.Out,
	},
	{
		Name = "Typewriter",
		-- The cap ROCKS forward as it sinks, pivoting about its own local X the
		-- way a typebar key does, instead of dropping flat. Chosen because it is
		-- the one thing neither other preset does: Default changes position and
		-- Slime changes shape, this one changes ORIENTATION, so it stays legible
		-- next to them at a glance rather than reading as "Default but more".
		--
		-- It is also the preset that gains the most from a full keyboard: a
		-- single key rocking is a small motion, a row of them rocking in
		-- sequence as you type is the whole effect.
		--
		-- Size is untouched (1,1,1), so it cannot overlap a neighbour whatever
		-- the grid does. 9 degrees over a 3-stud cap lifts the trailing edge by
		-- ~0.23 studs — clearly readable, and well under the 1.368-stud cap
		-- height, so the cap never looks like it is coming out of its socket.
		PressDepth = 0.85,
		PressSizeScale = Vector3.new(1, 1, 1),
		PressTilt = 9,
		-- Quart Out front-loads the travel: the cap snaps down and settles,
		-- which is what makes it read as mechanical rather than soft.
		PressEasingStyle = Enum.EasingStyle.Quart,
		PressEasingDirection = Enum.EasingDirection.Out,
		-- Back Out overshoots slightly on the way up, so the cap rocks BACK past
		-- level for a moment before settling — the return half of the same
		-- pivot, and the reason the release is worth watching at all.
		ReleaseEasingStyle = Enum.EasingStyle.Back,
		ReleaseEasingDirection = Enum.EasingDirection.Out,
	},
}

AnimationPresets.DEFAULT_NAME = PRESETS[1].Name

function AnimationPresets.List(): { string }
	local names = {}
	for _, preset in ipairs(PRESETS) do
		table.insert(names, preset.Name)
	end
	return names
end

-- Falls back to Default rather than erroring: a stale/unknown name attribute
-- must not break a key's press animation.
function AnimationPresets.Resolve(name: string?): Preset
	for _, preset in ipairs(PRESETS) do
		if preset.Name == name then
			return preset
		end
	end
	return PRESETS[1]
end

return AnimationPresets
