# Map Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the galaxy into `data\galaxy.json` and build an in-project map editor (separate launcher) that edits systems, links, stations, slot presets with per-station overrides, and starting stock, and blocks Save on an invalid galaxy.

**Architecture:** A plain-Dictionary "galaxy document" is the single source of truth. `GalaxyDocument` parses and serialises it, `GalaxyData.build_from(doc)` turns it into the runtime `Galaxy`, and the editor edits the same Dictionary through a pure-logic `MapEditModel` checked by `GalaxyValidator`. The editor UI is a thin view over the model.

**Tech Stack:** Godot 4.7, GDScript (tabs, CRLF in the working tree), the project's own test runner (`tests\run_tests.gd`), `assets\ui\theme.tres`.

**Spec:** `docs\superpowers\specs\2026-11-05-map-editor-design.md` (read its "Builder-check answers" section too).

## Global Constraints

- GDScript, tabs, CRLF working-tree files: patch `.gd` with Python `newline=''`, never `sed -i`. Match the file's style; do not reformat surrounding code.
- Work directly on `main`, commit per task, never push.
- Never commit `.import` churn or CRLF-only noise (`project.godot`, `tests\test_campaign_scene_fleet_panel.gd`).
- File: `res://data/galaxy.json`; two-space JSON, fixed key order, systems and stations sorted by id, floats at most 4 decimals, LF endings, trailing newline.
- Owners and commodities are stored by enum name (`CampaignFleet.Faction.keys()`, `Commodity.Type.keys()`, e.g. `"DOMINION"`, `"HULL_PARTS"`).
- Slot cap is `GalaxyData.STATION_MAX_SLOTS` (2). Exactly one PLAYER station. Positions: systems normalised 0..1, stations in pixels.
- No player access: no game scene references the editor; editor files are scenes\editor, scripts\editor, tools. No `export_presets.cfg` exists yet, so record the exclusion filter in `carry_forward.md` instead.
- New batch scripts take `--verbose`. Panels over play area need `MOUSE_FILTER_STOP` (editor is its own scene, still set it on the inspector so clicks never fall through to the canvas).
- Tests: add each new test file to `tests\run_tests.gd` (sync `run()` list; async ones near the `jump_map_panel_test` block). Suite must end clean except the known long-run-sim pirate-targeting flake, with 0 `SCRIPT ERROR`.
- Running Godot and tests: see `carry_forward.md` "Running Godot and tests" (non-console exe, redirect stdout, one `--headless --editor --quit` warm pass after adding `class_name` files).

## Review Focus

Failure modes the spec implies but no feature test would catch by default. Each has a test in the task that owns the code.

- Link to itself or a duplicate link: refused, no change (Task 2, `MapEditModel.link`).
- Deleting or duplicating the player station, or deleting the system that holds it: refused (Task 2).
- Renaming a station to a name whose lower-cased id already exists: a Save blocker, not a silent overwrite (Task 2, validator).
- Unknown keys at the top level, on a system, on a station, or in `extra` survive load then save (Task 1).
- A slot override naming an unknown commodity or a negative amount: a Save blocker (Task 2, validator).

---

### Task 1: Galaxy document, presets, and the move to `data\galaxy.json`

**Files:**
- Create: `scripts\campaign\galaxy_document.gd`, `data\galaxy.json`, `tools\export_galaxy_data.gd` (one-off, deleted at the end of this task), `tests\test_galaxy_document.gd`
- Modify: `scripts\campaign\galaxy_data.gd`, `scripts\campaign\economy_role.gd`, `scripts\campaign\base_economy.gd`, `tests\test_galaxy_data.gd`, `tests\run_tests.gd`

**Interfaces:**
- Produces:
  - `GalaxyDocument.PATH: String` = `"res://data/galaxy.json"`, `GalaxyDocument.VERSION: int` = 1.
  - `GalaxyDocument.parse(text: String) -> Dictionary` returns `{"ok": bool, "doc": Dictionary, "error": String}`.
  - `GalaxyDocument.serialize(doc: Dictionary) -> String`.
  - `GalaxyDocument.load_file(path: String = PATH) -> Dictionary` (same result shape as `parse`).
  - `GalaxyDocument.save_file(doc: Dictionary, path: String = PATH) -> bool`: writes only when the serialised text differs from the file; returns true if it wrote.
  - Document shape: `{"version": 1, "start_system": "haven", "presets": {name: {"kind": "MINING", "produces": {"ORE": 5.0}, "consumes": {}, "housing": 800.0}}, "systems": [{"id", "name", "map": [x, y], "tier"?: int, "extra": {}}], "links": [["a", "b"]], "stations": [{"name", "system", "owner": "DOMINION", "pos": [x, y], "art", "slots": ["refinery" | {"preset": "mining", "overrides": {"produces"?: {}, "consumes"?: {}, "housing"?: float}}], "stock": {"ORE": 7.0}, "quota": {"COMBAT": 1, "TRADER": 1}, "extra": {}}]}`. The station id is still `name.to_lower().replace(" ", "_")`.
  - `GalaxyData.build() -> Galaxy` (now reads the file), `GalaxyData.build_from(doc: Dictionary) -> Galaxy`, `GalaxyData.default_presets() -> Dictionary` (the six built-ins in the preset shape above), `GalaxyData._make_system(entry: Dictionary) -> StarSystem`, `GalaxyData._make_station(entry: Dictionary, presets: Dictionary) -> StationData` (document-shaped entries).
  - `EconomyRole.preset: String`, `EconomyRole.housing: float` (per instance), `EconomyRole.from_preset(preset_name: String, preset: Dictionary, overrides: Dictionary) -> EconomyRole`.

- [ ] **Step 1: Extend `EconomyRole` and `BaseEconomy` (test first)**
  Add to `tests\test_economy_role.gd` (or a new block in `test_galaxy_document.gd`): `from_preset("refinery", {"kind": "REFINERY", "produces": {"FUEL": 3.0}, "consumes": {}, "housing": 800.0}, {"produces": {"FUEL": 4.0}})` gives `produces == {Commodity.Type.FUEL: 4.0}`, `role_type == REFINERY`, `housing == 800.0`, `preset == "refinery"`. Every built-in factory sets `preset` to its name and `housing` to `HOUSING[role_type]`. Run, see it fail.
- [ ] **Step 2: Implement it.** `population_capacity()` sums `slot.housing` instead of `housing_for(slot.role_type)`. `housing_for` and `HOUSING` stay. Existing `test_base_economy.gd` and `test_economy_role.gd` must still pass.
- [ ] **Step 3: Write `tests\test_galaxy_document.gd` failing tests:**
  - `serialize(parse(serialize(doc)).doc) == serialize(doc)` for a small hand-built doc (round trip, idempotent).
  - Unknown keys survive: top-level `"future": {"a": 1}`, a system `extra: {"mood": "calm"}`, a station key outside the field list `"zz": 5`, then parse and serialize keeps all three.
  - Key order is fixed and stable: `serialize` output of two docs built with keys inserted in different orders is identical; systems and stations come out sorted by id (stations by lower-cased name).
  - Floats: `0.123456` serialises as `0.1235`; whole floats as `5.0`; output ends with exactly one `"\n"` and contains no `"\r"`.
  - `parse("not json")` and `parse("[]")` return `ok == false` with a non-empty `error`; `load_file("res://data/missing.json")` the same.
  - `save_file` to a `user://` temp path writes (returns true), a second identical call returns false and does not change the file's modified time; an edited doc writes again.
- [ ] **Step 4: Implement `GalaxyDocument`.** Build the output by hand (not `JSON.stringify`) so key order, 4-decimal floats and two-space indent are exact; `parse` uses `JSON.parse_string` and rejects anything that is not a Dictionary with `version`, `systems`, `links`, `stations`, `presets`, `start_system`. Run, tests pass.
- [ ] **Step 5: Write the migration generator and parity test (temporary).** In `GalaxyData` add `_constants_to_document() -> Dictionary` that reads the existing `SYSTEMS`, `STATIONS`, `LINKS`, `START_SYSTEM_ID` constants into the document shape (owner enum to name, roles to `slots`, Vector2 to `[x, y]`, `stock` and `quota` keys to names, `default_presets()` as `presets`), and `_build_from_constants() -> Galaxy` that is today's `build()` renamed. `tools\export_galaxy_data.gd` (SceneTree script, `--verbose` prints counts) writes `GalaxyDocument.serialize(GalaxyData._constants_to_document())` to `data\galaxy.json`. Run it once.
- [ ] **Step 6: Implement `build_from`, `_make_system`, `_make_station(entry, presets)`, `default_presets`.** `build_from` mirrors the old `build()` (systems, `add_station`, `link`, `start_system_id`, `assign_tiers`). A slot given as a string means no overrides. `_make_station` keeps `STATION_MAX_SLOTS`. Preset commodity and owner names map via `Commodity.Type.keys()` and `CampaignFleet.Faction.keys()`; keep the `assert(false, ...)` style for unknown names.
- [ ] **Step 7: Parity test (`tests\test_galaxy_parity.gd`, temporary, add to `run_tests.gd`).** Compare `build_from(load_file().doc)` with `_build_from_constants()`: same system ids, names, map positions, `tier_override`, sorted links; same station ids, system, owner, art, position, starting stock, quotas, and per slot `role_type`, `produces`, `consumes`, `housing`, `preset`; `start_system_id`. Run the suite: parity passes.
- [ ] **Step 8: Cut over.** `build()` becomes: `GalaxyDocument.load_file()`; on `ok == false` do `push_error` with the path and the parse error then `assert(false, ...)` (hard failure, no fallback), else `build_from(result["doc"])`. Delete `SYSTEMS`, `STATIONS`, `LINKS`, `START_SYSTEM_ID` (keep a `const START_SYSTEM_ID` only if other code references it; grep first), `_constants_to_document`, `_build_from_constants`, `tools\export_galaxy_data.gd`, and `tests\test_galaxy_parity.gd` (and its `run_tests.gd` line). Update `tests\test_galaxy_data.gd` to the document-shaped `_make_system`/`_make_station` calls (keep all its existing assertions: 26 systems, 41 stations, 40 links, one player station, pirate food rule). Add a `build()` hard-failure check only if it can be done without an assert aborting the run; otherwise note it as untested in the commit message.
- [ ] **Step 9: Verify and commit.** Warm pass, full suite: only the known flake; 0 `SCRIPT ERROR`; `data\galaxy.json` re-serialises byte-identical (`save_file` returns false). Commit `data\galaxy.json`, the new and changed scripts and tests: "Move the galaxy into data\galaxy.json with preset-based slots".

### Task 2: Validator and edit model (pure logic)

**Files:**
- Create: `scripts\editor\galaxy_validator.gd`, `scripts\editor\map_edit_model.gd`, `tests\test_galaxy_validator.gd`, `tests\test_map_edit_model.gd`
- Modify: `tests\run_tests.gd`

**Interfaces:**
- Consumes: the document shape and `GalaxyData.default_presets()` from Task 1.
- Produces:
  - `GalaxyValidator.validate(doc: Dictionary) -> Array[Dictionary]`; each finding is `{"severity": "block" | "warn", "message": String, "target": {"kind": "system" | "station" | "link" | "doc", "id": String}}` (`id` is the system id, the station id, `"a|b"` for a link, `""` for doc).
  - `GalaxyValidator.has_blockers(findings: Array[Dictionary]) -> bool`.
  - `MapEditModel` (`RefCounted`): `doc: Dictionary`, `dirty: bool`, `static func from_document(doc: Dictionary) -> MapEditModel`.
    - `move_system(id: String, map: Vector2) -> void` (clamped to 0..1)
    - `add_system(name: String, map: Vector2) -> String` (returns the new unique id)
    - `delete_system(id: String) -> bool`
    - `link(a: String, b: String) -> bool`, `unlink(a: String, b: String) -> bool`
    - `set_system_field(id: String, key: String, value: Variant) -> void`
    - `add_station(system_id: String) -> String`, `duplicate_station(id: String) -> String` (empty on refusal), `delete_station(id: String) -> bool`
    - `set_station_field(id: String, key: String, value: Variant) -> void`
    - `set_slot_preset(station_id: String, slot_index: int, preset: String) -> void`
    - `add_slot(station_id: String) -> bool`, `remove_slot(station_id: String, slot_index: int) -> bool`
    - `set_override(station_id: String, slot_index: int, key: String, value: Variant) -> void`, `reset_override(station_id: String, slot_index: int, key: String) -> void`
    - `set_stock(station_id: String, commodity: String, units: Variant) -> void` (null or empty clears)
    - `set_quota(station_id: String, role: String, count: int) -> void`
    - `set_preset_field(preset: String, key: String, value: Variant) -> void`, `add_preset(name: String) -> bool`
    - `station_index(id: String) -> int` and `station_id_of(entry: Dictionary) -> String` (lower-cased name, spaces to `_`), `stations_in(system_id: String) -> Array`.
    - Every mutator sets `dirty`.

- [ ] **Step 1: Write failing validator tests** (build small docs in the test; one test per rule). Blockers: system with no links (and a two-system galaxy where one is unlinked); system unreachable from `start_system` (two separate pairs); missing or unknown `start_system`; duplicate system id; duplicate station id (names `"A B"` and `"a b"`); station in an unknown system; unknown preset; more than 2 slots; unknown commodity name in an override/stock/preset; negative amount in an override or stock; player stations 0 and 2; the start system not holding the player station. Warnings: system with no stations; station with no slots. A valid doc returns no findings. A single-system galaxy with the player station is valid (no links needed).
- [ ] **Step 2: Implement `GalaxyValidator`** (undirected BFS from `start_system`). Messages name the system/station and what to do. Run, tests pass.
- [ ] **Step 3: Write failing model tests:** `link(a, a)` returns false and changes nothing; a second `link(a, b)` returns false; `unlink` of a missing link returns false; `delete_system` removes its links and stations; `delete_system` of the system holding the player station returns false; `delete_station` and `duplicate_station` of the player station return false and leave the doc unchanged; `duplicate_station` gives a unique name ("X copy", "X copy 2") and unique id; `add_system` ids are unique and lower-case; `move_system` clamps to 0..1; `set_station_field(id, "name", ...)` changes the derived id and keeps the station in place; `set_override` then `reset_override` restores the preset's value (key removed, no empty `overrides`); `add_slot` returns false at 2 slots; `set_stock(..., null)` removes the key; unknown keys on the touched entries survive every mutator; `dirty` is false after `from_document` and true after any change.
- [ ] **Step 4: Implement `MapEditModel`** as thin operations on the Dictionary (no scene, no autoload). Station renames update nothing else (no saves exist). Run, tests pass.
- [ ] **Step 5: Verify and commit** ("Add the map editor's galaxy validator and edit model"). Suite clean except the flake.

### Task 3: Editor screen - canvas, top bar, system inspector, station list, errors

**Files:**
- Create: `scenes\editor\map_editor.tscn`, `scripts\editor\map_editor.gd`, `scripts\editor\map_canvas.gd`, `scripts\editor\editor_fields.gd`, `tests\test_map_editor.gd`
- Modify: `tests\run_tests.gd` (async block)

**Interfaces:**
- Consumes: `MapEditModel`, `GalaxyValidator`, `GalaxyDocument` (Tasks 1-2), the theme at `assets\ui\theme.tres`.
- Produces:
  - `MapCanvas` (`Control`) signals `system_selected(id: String)`, `system_moved(id: String, map: Vector2)`, `link_requested(a: String, b: String)`, `link_delete_requested(a: String, b: String)`, `add_requested(map: Vector2)`. Properties `mode: int` (`Mode.MOVE`, `Mode.LINK`, `Mode.ADD`), `selected: String`, `node_points: Dictionary`. Methods `set_document(doc: Dictionary) -> void`, `refresh() -> void`, `system_at(point: Vector2) -> String`.
  - `EditorFields.SYSTEM_FIELDS` and `EditorFields.STATION_FIELDS`: `Array[Dictionary]` of `{"key": String, "label": String, "type": "string" | "int" | "float" | "vector2" | "enum" | "bool", "default": Variant, "choices": Variant (optional)}` read by the inspectors; adding an entry adds a row.
  - `MapEditor` (`Control`, scene root) methods the tests drive: `load_document(doc: Dictionary) -> void`, `select_system(id: String) -> void`, `select_station(id: String) -> void`, `validate() -> Array[Dictionary]`, `save() -> bool` (false and shows findings when blockers exist; otherwise `GalaxyDocument.save_file`), `reload() -> void`, property `model: MapEditModel`.

- [ ] **Step 1: Failing UI tests** (`run_async`, instantiate the scene under the test tree, load a small doc, await one frame): dragging (emit through the canvas methods) updates the model position and `dirty`; Link mode with two clicks adds a link, a click on the same node twice does not; right-clicking a link deletes it; Add mode creates a system at the clicked position; selecting a system lists its stations in the right-hand list and clicking one calls `select_station` and shows the station editor container; Save with an unlinked system returns false, writes nothing, and the errors list shows a blocker that selects the system when clicked; Save on a valid doc writes; Save twice writes once; Load discards edits. Run a layout check with `tests\ui_layout_check.gd` on the opened screen.
- [ ] **Step 2: Implement `MapEditor` and `MapCanvas`.** Layout A from the spec: top bar (mode buttons, Save, Load, Validate, a dirty marker), canvas on the left (drawing style from `JumpMapPanel`: same constants, links, node colours by owner via the existing `node_color` palette, selection ring), inspector on the right (system rows built from `EditorFields.SYSTEM_FIELDS`, then the station list with an "all stations" filter toggle and a "+ Add station" button), and an errors list under the canvas. Deleting a system or station asks for confirmation. `MOUSE_FILTER_STOP` on the inspector. Number fields that don't parse revert to the old value.
- [ ] **Step 3: Station editor container (stub for Task 4).** Selecting a station shows a container that, for now, lists the name, system, owner, art and position rows built from `EditorFields.STATION_FIELDS` and the slots as read-only text. Task 4 replaces the read-only parts.
- [ ] **Step 4: Verify.** Warm pass, suite clean except the flake. Run the editor scene non-headless (`Start-Process -Wait`, screenshot script like the one used for the jump map) with the real `data\galaxy.json` loaded, and read the PNG: nodes, links, owner colours, inspector and list are visible and nothing overlaps.
- [ ] **Step 5: Commit** ("Add the map editor screen: canvas, system inspector, validation on Save").

### Task 4: Station editor, presets tab, launcher, and wrap-up

**Files:**
- Create: `scripts\editor\station_editor.gd`, `scripts\editor\preset_editor.gd`, `tools\map_editor.bat`
- Modify: `scripts\editor\map_editor.gd`, `scripts\editor\editor_fields.gd`, `tests\test_map_editor.gd`, `carry_forward.md`

**Interfaces:**
- Consumes: `MapEditModel` slot, stock, quota, preset and override operations (Task 2); `MapEditor.select_station` (Task 3).
- Produces: `StationEditor` (`Control`) with `bind(model: MapEditModel, station_id: String) -> void`; `PresetEditor` (`Control`) with `bind(model: MapEditModel) -> void`; a `Presets` tab beside the map in `MapEditor`.

- [ ] **Step 1: Failing UI tests:** choosing a different preset for a slot updates the doc and the computed preview; editing a slot's produce amount stores an override and shows the override marker; Reset removes it; starting stock blank means default (key absent), a typed value stores it; the computed preview (net per tick and housing) matches `BaseEconomy.net_commodities()` and `population_capacity()` for the same slots built through `GalaxyData._make_station`; quotas edit through `set_quota`; duplicate and delete buttons call the model (and are disabled for the player station); an extra-property row add and remove round-trips through save; the Presets tab edits a preset's produces, consumes and housing, and a new preset appears in every slot dropdown.
- [ ] **Step 2: Implement `StationEditor` and `PresetEditor`** as in the spec's mockup. The preview builds a throwaway station with `GalaxyData._make_station` from the doc entry and calls the same economy functions (no duplicated logic). The slot dropdown lists the doc's presets, sorted. Free-form extra properties are string key/value rows backed by `extra`.
- [ ] **Step 3: Launcher.** `tools\map_editor.bat`: `set GODOT=%GODOT_EXE%`, default `C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe` when unset, `cd /d %~dp0..`, then `"%GODOT%" --path . res://scenes/editor/map_editor.tscn` (setup lines chained, the real command on its own line). Run it once from PowerShell to confirm it opens the editor scene with the real galaxy.
- [ ] **Step 4: End-to-end check.** In the editor, load `data\galaxy.json`, change nothing, Save: the file does not change (`git status` clean). Move one system, Save, check the diff touches only that system's `map`, then `git checkout` the file. Screenshot the station editor on "Bastion Quarry" and the Presets tab and read the PNGs.
- [ ] **Step 5: Docs and commit.** Update `carry_forward.md`: the map editor exists (launcher, file, schema pointer to the spec), the export exclusion filter to add when `export_presets.cfg` is created (`scenes/editor/*, scripts/editor/*, tools/*`), and that balancing now happens by editing `data\galaxy.json` or through the editor. Full suite clean except the flake; commit ("Add the station editor, presets tab and map editor launcher").

## Execution note

Tasks 1 and 2 are logic with unit tests and can be done in either order after the `EconomyRole` change; Task 3 needs both; Task 4 needs Task 3. Per the user's standing preference: batch reviews (one reviewer after Tasks 1-2, one after 3-4), then one final whole-change review on the most capable model.
