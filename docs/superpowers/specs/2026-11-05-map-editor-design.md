# Campaign map editor - design

## Intent
The galaxy (26 systems, 41 stations, 40 links) is hand-written in `scripts\campaign\galaxy_data.gd`.
The user wants to lay it out by eye and then hand it to Claude for balancing. This adds a map editor
that edits the galaxy as data. Placement, links, station roles, per-station production and starting
stock all become editable in one tool. The data format must be easy to extend for future features.

## Goals
- Drag systems on the jump map, link and unlink them, add and delete systems.
- Edit every station: identity, slots, production, starting stock, fleet quotas.
- Roles are presets (defaults); a station may override any number on its own slots.
- Validation that blocks Save for a broken galaxy (see Validation).
- Extensible: new per-station or per-system fields need one field-list entry, not new UI code.
- The game loads the same data file the editor writes, so editor output is what the game plays.

## Non-goals
- No player access: no menu entry, no in-game button, not in exported builds.
- No undo/redo in v1 (Load re-reads the last saved file).
- No change to economy or AI rules. Balancing happens afterwards, by editing the data.
- No in-system position drag preview in v1 (numeric fields only).

## Anti-goals
- A save that makes the game crash or load a different galaxy than the editor showed.
- Losing fields the editor doesn't know about (the file must round-trip them).
- Noisy diffs: saving an unchanged galaxy must not rewrite the file.

## Decisions (made with the user)
- **Layout A:** one screen. Map canvas on the left (drag, Link mode, Add System). Inspector on the
  right: system fields, the system's station list, and a click-through to the full station editor.
  Top bar: Mode (Move / Link / Add System), Save, Load, Validate.
- **Station editor** shows: name, system, owner, art, position in system; slots (max 2) each with
  preset, produces, consumes, housing, override markers and reset; starting stock per commodity
  (blank = default); fleet quotas (combat, trader); a read-only computed preview (net per tick,
  housing); free-form extra properties; duplicate and delete.
- **Presets tab:** the defaults every station inherits (produces, consumes, housing). New presets can
  be added and then appear in every slot dropdown.
- **Presets with per-station overrides.** A station's slot stores the preset name plus only the
  values it overrides.
- **Lives in the project, launched separately:** a `.bat` file starts Godot straight into the editor
  scene. Players never reach it; no game scene links to it.
- **Save is blocked** when any system has no connected links.

## Constraints
- Godot 4.7, GDScript, tabs, CRLF in the working tree (see CARRY_FORWARD gotchas: patch `.gd` files
  with Python `newline=''`, not `sed -i`).
- Implemented directly on `main`; do not push.
- Per project rules: `--verbose` on batch scripts, UI follows `assets\ui\theme.tres`, panels over play
  area use `MOUSE_FILTER_STOP`.
- Existing tests that build the galaxy (`test_galaxy_data.gd` and the campaign tests) must keep
  passing against the data-file galaxy, with changed assertions only where the API necessarily changes.

## My calls (the user hasn't confirmed these)
- **File:** `data\galaxy.json`, pretty-printed, systems/stations sorted by id, keys in a fixed order.
  Contains: `version`, `start_system`, `presets`, `systems`, `links`, `stations`. Every system and
  station has an `extra` object for unknown keys. Positions stay normalised 0..1 for the map and
  pixels for in-system.
- **Migration with a parity guarantee:** generate the file from the current constants, build a galaxy
  from the file, and compare it field by field with the constants-built one in a test. Only then
  remove the constants.
- **Presets** keep the six built-ins (`mining`, `agriculture`, `industrial`, `population`, `refinery`,
  `trade_hub`) at today's numbers. A preset has `kind` (one of the existing `EconomyRole.RoleType`
  names, used wherever code switches on role type), `produces`, `consumes`, `housing`. `EconomyRole`
  gains `preset` (name) and a per-instance `housing`; the `HOUSING` constant stays as the built-in
  default.
- **Launcher:** `tools\map_editor.bat` runs the Godot exe (`GODOT_EXE` env var, default the Steam path
  from CARRY_FORWARD) with `--path` on the project and the editor scene. The editor's scenes, scripts
  and `tools\` go in the export exclusion filter.
- **Validation severities:**
  - Blocks Save: a system with no links; a system unreachable from the start system; no start system
    or an unknown one; duplicate system ids; duplicate station ids (the id is the lower-cased name);
    a station in an unknown system; an unknown preset; more than 2 slots; player stations not exactly 1
    (current test expectation).
  - Warns only: a system with no stations; a station with no slots.
- **Field list drives the inspector:** one descriptor per field (key, label, type, default, owner:
  system or station). New fields appear in the UI and in save/load by adding a descriptor.
- **Fleet quotas** are editable per role the game already has (combat, trader).
- **Save/Load targets** `res://data/galaxy.json`; Save writes only when validation passes and reports
  every failure in a list that selects the offending node or station on click.

## Left to the builder
- Scene and node structure, drawing code, theme details, exact validation message wording.
- How the editor reuses `JumpMapPanel` drawing, if at all.
- Test layout (keep to `tests\` mirroring source; register in `run_tests.gd`).

## Verification
- Parity test (file galaxy equals the old constants galaxy) before the constants go.
- Round trip: load, save with no edits, file unchanged; unknown `extra` keys survive.
- Validation tests: one per blocker and warning.
- Full suite clean except the known long-run-sim flake; 0 `SCRIPT ERROR`.
- Screenshot of the editor with the real galaxy loaded.

## Builder-check answers (settled from the project or my calls)
- **Slot = one entry in today's `roles` list.** The file stores each as `{"preset": "refinery",
  "overrides": {...}}`; a bare string is shorthand for no overrides. The 2-slot cap is the existing
  `STATION_MAX_SLOTS` (`BaseEconomy.max_slots`); the editor enforces the same number.
- **Owner** is stored by `CampaignFleet.Faction` name ("DOMINION", "PLAYER", ...). Player stations
  must number exactly 1 (the Home Base; `Galaxy.home_station()` and `test_galaxy_data.gd` assume it).
  Delete and duplicate of the player station are refused.
- **System fields:** `id`, `name`, `map` [x, y], optional `tier` (tier override), `extra`. Links are
  plain undirected pairs of ids with no attributes. Nothing outside `galaxy_data.gd` reads galaxy data
  except through `Galaxy`/`GalaxyData.build()` (`campaign_state.gd`, `campaign_scene.gd`).
- **Start system** is explicit in the file and must be the system holding the player station. It is
  exempt from "no links" only if the galaxy is a single system; otherwise it needs a link like any
  other. Reachability is over undirected links, from the start system.
- **No-rewrite contract:** the editor serialises to a string and compares it with the file's current
  text; it writes only when they differ. Serialisation: tab-free two-space JSON, fixed key order,
  floats via `String.num` at 4 decimals max, LF endings, trailing newline. The game reads it the same
  way regardless of line endings.
- **Commodities** stay a code enum (`Commodity.Type`). Starting stock is `{COMMODITY_NAME: units}` and
  unlisted goods default to `Commodity.TARGET_STOCK`, exactly as `CampaignState` does today. The
  computed preview calls the same functions (`BaseEconomy.net_commodities`, `population_capacity`) on a
  throwaway economy built from the file data, so no logic is duplicated.
- **File location and builds:** `res://data/galaxy.json`. It is not excluded from exports (the game
  needs it); the editor scenes, scripts and `tools\` are. A missing or corrupt file is a hard failure
  with a clear error at game start (no silent fallback to a stale galaxy).
- **Save games:** none exist yet, so editing or renaming ids breaks nothing today. Flag it again when
  saving is built.
- **Launcher:** the Steam Godot path from CARRY_FORWARD is the real path on this machine; the bat runs
  `godot --path <project> res://scenes/editor/map_editor.tscn` (game mode, no `--editor`). `GODOT_EXE`
  overrides it. No runtime flag is needed: nothing in the game references the editor scene.
