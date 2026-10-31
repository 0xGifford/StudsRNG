--!strict
-- PLUGIN-side constants (Studio only).
-- Not to be confused with RuntimeSource.Config, which is GAME-side.

return {
	-- Bumped whenever RuntimeSource changes: the Installer re-clones the game
	-- side only on a version difference.
	VERSION = "0.6.0", -- R6 rigs detected (feet measured from the legs, not from HipHeight), and a per-group sound Volume

	-- Shown by the panel's Discord button for the user to copy.
	--
	-- Deliberately an INDIRECTION on our own domain, not the invite itself.
	-- A downloaded .rbxmx never updates, so an invite hard-coded here is
	-- final: revoke it or move server, and the button is dead forever for
	-- every existing user, with no way to repair it. This URL is a 302 on the
	-- site (temporary on purpose, so it stays changeable), which moves the
	-- choice of destination out of the distributed binary and onto the site.
	-- Same rule for anything else that ships to the user.
	--
	-- Copies of 0.5.17 and earlier still carry https://discord.gg/3XsMR7z5yf
	-- directly: that one must stay alive for them.
	DISCORD_URL = "https://zerodev.tools/discord",

	-- Tags. TAG_HITBOX must stay identical to RuntimeSource.Config.TAG_HITBOX.
	TAG_HITBOX = "KeyCapper_Hitbox",
	TAG_KEY = "KeyCapper_Key",

	-- The mesh republished under the ZeroDev account, public.
	MESH_ID = "rbxassetid://8837613273",
	KEY_SIZE = Vector3.new(3, 1.368114709854126, 3),

	-- The SurfaceGui is on the Top face: the mesh needs this base yaw for
	-- the text to read right-side up. Determined by hand on the prototype,
	-- don't change without re-validating visually.
	MESH_YAW_OFFSET = math.rad(-90),

	-- Grid: pitch of 3.15 = 3-stud key + a 0.15 gap.
	GRID_PITCH = 3.15,
	ROTATION_STEP = math.rad(90), -- the "90-degree grid"

	-- Each footprint cell is re-probed along the surface normal from this far
	-- out, so a cell hanging over a ledge finds nothing and is dropped instead
	-- of being placed mid-air. Also the tolerance for following a bumpy
	-- surface: beyond this, the cell is considered off-surface.
	CELL_PROBE_REACH = 4,

	-- Where keys are stored in the Workspace.
	KEYS_FOLDER = "KeyCapperKeys",

	-- Group storage. Kept OUTSIDE the installed runtime folder on purpose:
	-- the Installer wipes that one on a version bump. Must stay identical to
	-- RuntimeSource.Config.GROUPS_FOLDER.
	GROUPS_FOLDER = "KeyCapperGroups",
	ATTR_GROUP = "Group", -- attribute carried by each key Model
	DEFAULT_GROUP = "Default",

	-- Where the runtime is installed in the user's game.
	RUNTIME_PARENT = "ReplicatedStorage",
	RUNTIME_NAME = "KeyCapper",

	-- Must stay identical to RuntimeSource.Config.SETTINGS_FOLDER. Kept
	-- outside the versioned runtime folder for the same reason GROUPS_FOLDER
	-- is: the Installer wipes that one on a version bump.
	SETTINGS_FOLDER = "KeyCapperSettings",
}
