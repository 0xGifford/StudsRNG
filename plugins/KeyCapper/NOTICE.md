# KeyCapper

KeyCapper is proprietary software by sebattfg (see `src/License.luau`, whose
terms and notices must stay intact). It is kept here, with StudsRNG's zone
additions, with the creator's permission, for building this game only.

- `KeyCapper.base.rbxmx` — the plugin as received (the non-code instances:
  key mesh, remotes, folders, are taken from it at build time)
- `src/` — every script in it, as editable files
- build: `lune run tools/build_plugin.luau KeyCapper` → `KeyCapper.rbxmx`

## StudsRNG additions

Marked `StudsRNG` in the source. Everything else is as received.

- **Zone section** in the panel (`UI/Sections/ZoneSection.luau`): where each
  painted key gets its game zone. *From surface* (the zone of whatever it lands
  on), *Locked* (always the zone you pick), or *None*. *Under cursor* shows the
  zone a key would get.
- **Zone groups** (on by default): each zone's keys go in their own group
  (`Zone7`). A new zone group starts from the current group's look. Starting a
  stroke in a zone switches the panel to that zone's group, so the style you
  edit is the one you're painting. *Erase → This group* means the zone's group.
- Keys get `World = "007"` (the game's zone id) and are filed under
  `workspace.KeyCapperKeys/Zone7` (`Placement/KeyPlacer.luau`,
  `Placement/ZoneResolver.luau`, `Placement/Brush.luau`, `Main.server.luau`).
