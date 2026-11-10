# Map editor: visual station & scenery placement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a visual "System" tab to the map editor (Stations sub-tab: drag station art onto its real position; Scenery sub-tab: pick a system's background and hand-place/randomize planets and asteroids), and wire the same per-system background/scenery data into the live campaign game.

**Architecture:** Two new `Control`-based canvases (`StationCanvas`, `SceneryCanvas`) follow the existing `MapCanvas` pattern (pure draw + mouse-input, signals out, no model access) and get wired by `MapEditor` into a new "System" tab, alongside a new `SceneryEditor` side-panel (modeled on `StationEditor`/`PresetEditor`). All edits route through new `MapEditModel` methods, which store two new optional per-system fields (`background`, `scenery`) that `GalaxyDocument` round-trips deterministically. A new pure-logic `SceneryRandomizer` generates random scenery. On the runtime side, `StarSystem` carries the new fields through `GalaxyData`, `SystemLayer` gains `add_scenery()`, and `campaign_scene.gd` wires both into the already-existing `StarfieldAssignment`/station-rendering pipeline.

**Tech Stack:** Godot 4.7, GDScript.

## Global Constraints
- Godot 4.7, GDScript, tabs, CRLF in the working tree. Patch `.gd` files with Python `open(path, newline='')`, never `sed -i` (CARRY_FORWARD gotcha).
- Implemented directly on `main`; do not push.
- `--verbose` on batch scripts; UI follows `assets\ui\theme.tres`; panels over the play area use `MOUSE_FILTER_STOP`.
- Existing tests that build the galaxy (`test_galaxy_data.gd`, campaign tests) must keep passing; only change assertions where the API necessarily changes.
- Every new per-system field is **optional**: a system with neither `background` nor `scenery` must behave exactly as it does today (byte-identical serialization, identical `StarfieldAssignment` hash pick, no scenery nodes).
- No Save blockers added. No camera panning added anywhere. No change to `CombatScenery` or combat rendering.
- Run the full suite (`tools\run_tests.bat` or equivalent `--headless --script res://tests/run_tests.gd`) after each task touching runtime code; 0 `SCRIPT ERROR`.

---

### Task 1: `GalaxyDocument` round-trips `background` and `scenery`

**Files:**
- Modify: `scripts\campaign\galaxy_document.gd`
- Test: `tests\test_galaxy_document.gd`

**Interfaces:**
- Produces: `GalaxyDocument.SYSTEM_KEYS` now includes `"background"`, `"scenery"`; new contexts `"background"` (keys `category`, `seed`) and `"scenery_item"` (keys `type`, `texture`, `pos`, `scale`, `layer`) recognized by `_child_context`/`_key_order`. `serialize()`/`parse()` round-trip these keys like every other field. Later tasks store `doc["systems"][i]["background"]` (a `Dictionary` or absent) and `doc["systems"][i]["scenery"]` (an `Array` of `Dictionary`, or absent/empty).

- [ ] **Step 1: Write the failing round-trip test**

Add to `tests\test_galaxy_document.gd` (find the existing `run()` dispatcher and add a new check function, following the file's existing style of one `_check_*` function per concern):

```gdscript
static func _check_background_and_scenery(failures: Array[String]) -> void:
	var doc := {
		"version": 1, "start_system": "a", "presets": {},
		"systems": [{"id": "a", "name": "A", "map": [0.5, 0.5], "extra": {},
			"background": {"category": "medium", "seed": 3},
			"scenery": [
				{"type": "planet", "texture": "planet_gas_purple.png", "pos": [160.0, 90.0], "scale": 3.5, "layer": "mid_distance"},
				{"type": "asteroid", "texture": "v1_round_a.png", "pos": [860.0, 520.0], "scale": 1.3, "layer": "foreground"},
			]},
			{"id": "b", "name": "B", "map": [0.2, 0.2], "extra": {}},
		],
		"links": [["a", "b"]], "stations": [],
	}
	var text := GalaxyDocument.serialize(doc)
	var parsed := GalaxyDocument.parse(text)
	if not parsed["ok"]:
		failures.append("background/scenery: expected a valid parse, got %s" % parsed["error"])
		return
	var back: Dictionary = parsed["doc"]
	var sys_a: Dictionary = back["systems"][0]
	if sys_a.get("background", {}) != {"category": "medium", "seed": 3}:
		failures.append("background/scenery: expected background to round-trip, got %s" % [sys_a.get("background")])
	if sys_a.get("scenery", []).size() != 2 or sys_a["scenery"][0]["texture"] != "planet_gas_purple.png" \
			or sys_a["scenery"][1]["layer"] != "foreground":
		failures.append("background/scenery: expected scenery to round-trip, got %s" % [sys_a.get("scenery")])
	var sys_b: Dictionary = back["systems"][1]
	if sys_b.has("background") or sys_b.has("scenery"):
		failures.append("background/scenery: expected a system without them to stay absent, got %s" % [sys_b])
	# A system with background/scenery, re-serialized, must not change (no-rewrite contract).
	if GalaxyDocument.serialize(back) != text:
		failures.append("background/scenery: expected a stable re-serialize")
```

Call `_check_background_and_scenery(failures)` from `run()`.

- [ ] **Step 2: Run test to verify it fails**

Run: `"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL at `test_galaxy_document.gd` — background/scenery missing from the parsed system (today `_child_context` has no case for these keys, so they'd currently still pass through as unordered scalar/array data... verify by running first; if it unexpectedly passes because the generic fallback already handles it, the test still documents the contract going forward — either way, proceed to Step 3 to lock in the explicit key order).

- [ ] **Step 3: Add the keys and contexts**

In `scripts\campaign\galaxy_document.gd`:

```gdscript
const SYSTEM_KEYS := ["id", "name", "map", "tier", "background", "scenery", "extra"]
const BACKGROUND_KEYS := ["category", "seed"]
const SCENERY_ITEM_KEYS := ["type", "texture", "pos", "scale", "layer"]
# Keys whose numbers are integers in the document (parse_string returns every number as float).
const INT_KEYS := ["version", "tier", "seed"]
```

Extend `_key_order`:

```gdscript
static func _key_order(context: String) -> Array:
	match context:
		"doc":
			return DOC_KEYS
		"preset":
			return PRESET_KEYS
		"system":
			return SYSTEM_KEYS
		"station":
			return STATION_KEYS
		"slot":
			return SLOT_KEYS
		"overrides":
			return OVERRIDE_KEYS
		"background":
			return BACKGROUND_KEYS
		"scenery_item":
			return SCENERY_ITEM_KEYS
	return []
```

Extend `_child_context`'s `"system"` branch:

```gdscript
		"system":
			if key == "background":
				return "background"
			if key == "scenery":
				return "scenery_item"
```

(This sits in the existing `match context:` block inside `_child_context`, alongside the current `"doc"`/`"presets"`/`"station"`/`"slot"` branches — add a new `"system"` case there.)

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS, 0 `SCRIPT ERROR`.

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/galaxy_document.gd tests/test_galaxy_document.gd
git commit -m "Round-trip per-system background and scenery in galaxy.json"
```

---

### Task 2: `StarfieldAssignment` accepts an explicit override

**Files:**
- Modify: `scripts\background\starfield_assignment.gd`
- Test: `tests\test_starfield_assignment.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `StarfieldAssignment.pick(id: String, categories: Array = CATEGORIES, override: Dictionary = {}) -> Dictionary` and `StarfieldAssignment.base_texture_path(id: String, categories: Array = CATEGORIES, override: Dictionary = {}) -> String`. When `override` has both `category` and `seed`, it wins outright (no hashing); otherwise behavior is identical to today. Later tasks (campaign wiring) pass a system's `background` dict (or `{}`) as `override`.

- [ ] **Step 1: Write the failing test**

Add to `tests\test_starfield_assignment.gd`, inside `run()`:

```gdscript
	var overridden := StarfieldAssignmentScript.pick("sol", StarfieldAssignmentScript.CATEGORIES, {"category": "dense", "seed": 2})
	if overridden != {"category": "dense", "seed": 2}:
		failures.append("pick: expected an explicit override to win outright, got %s" % [overridden])
	var overridden_path := StarfieldAssignmentScript.base_texture_path("sol", StarfieldAssignmentScript.CATEGORIES, {"category": "dense", "seed": 2})
	if overridden_path != "res://assets/sprites/backgrounds/starfield/dense/dense_02.png":
		failures.append("base_texture_path: expected the override path, got %s" % overridden_path)
	var empty_override := StarfieldAssignmentScript.pick("sol", StarfieldAssignmentScript.CATEGORIES, {})
	if empty_override != first:
		failures.append("pick: expected an empty override to fall back to the hash, got %s vs %s" % [empty_override, first])
```

(`first` is already defined earlier in the file as `StarfieldAssignmentScript.pick("sol")`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `pick()` doesn't accept a third argument.

- [ ] **Step 3: Implement the override**

```gdscript
static func pick(id: String, categories: Array = CATEGORIES, override: Dictionary = {}) -> Dictionary:
	if override.has("category") and override.has("seed"):
		return {"category": override["category"], "seed": override["seed"]}
	var category: String = categories[abs(hash(id)) % categories.size()]
	var seed_index: int = abs(hash(id + "_seed")) % SEED_COUNT + 1
	return {"category": category, "seed": seed_index}

static func base_texture_path(id: String, categories: Array = CATEGORIES, override: Dictionary = {}) -> String:
	var choice := pick(id, categories, override)
	return "res://assets/sprites/backgrounds/starfield/%s/%s_%02d.png" % [choice.category, choice.category, choice.seed]
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/background/starfield_assignment.gd tests/test_starfield_assignment.gd
git commit -m "Let StarfieldAssignment take an explicit category/seed override"
```

---

### Task 3: `EditorFields` gains a reusable asset-folder scanner

**Files:**
- Modify: `scripts\editor\editor_fields.gd`
- Create: `tests\test_editor_fields.gd`
- Modify: `tests\run_tests.gd` (register the new test)

**Interfaces:**
- Consumes: nothing new.
- Produces: `EditorFields.scan_png_basenames(dir: String) -> Array` (sorted `.png` basenames in a directory, no extension — generalizes the existing inline scan used for station `art`). `EditorFields.scan_subfolders(dir: String) -> Array` (sorted subfolder names). Both used by Task 9's `SceneryEditor` to list `assets/sprites/backgrounds/*` folders and the files inside the chosen one; `choices_for`'s existing `"art"` case is refactored to call `scan_png_basenames` so behavior is unchanged but no longer duplicated.

- [ ] **Step 1: Write the failing test**

Create `tests\test_editor_fields.gd`:

```gdscript
extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	var art := EditorFields.scan_png_basenames(EditorFields.ART_DIR)
	if art.is_empty() or not art.has("ring_2") or art != art.duplicate().sort_custom(func(a, b): return a < b) as Array:
		pass # sort check below is more reliable than comparing to a re-sorted duplicate of itself
	if art.is_empty() or not art.has("ring_2"):
		failures.append("scan_png_basenames: expected the stations art list to include ring_2, got %s" % [art])
	for i in range(1, art.size()):
		if art[i - 1] > art[i]:
			failures.append("scan_png_basenames: expected a sorted result, got %s" % [art])
			break
	var planets := EditorFields.scan_png_basenames("res://assets/sprites/backgrounds/planets")
	if not planets.has("planet_earthlike"):
		failures.append("scan_png_basenames: expected planet_earthlike in the planets folder, got %s" % [planets])
	var folders := EditorFields.scan_subfolders("res://assets/sprites/backgrounds")
	if not folders.has("planets") or not folders.has("asteroids"):
		failures.append("scan_subfolders: expected planets and asteroids under backgrounds, got %s" % [folders])
	return failures
```

Remove the dead `if art.is_empty()... pass` placeholder line before finalizing — it was scratch; the clean version is just the two checks below it. (Write the file with that line already removed.)

- [ ] **Step 2: Register the test and run it to verify it fails**

In `tests\run_tests.gd`, add `preload("res://tests/test_editor_fields.gd"),` to the `test_scripts` array (alongside the other `preload`-based synchronous tests, e.g. right after `test_jump_rules.gd`).

Run: `godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `scan_png_basenames`/`scan_subfolders` don't exist yet.

- [ ] **Step 3: Implement the scanners and refactor `choices_for`**

In `scripts\editor\editor_fields.gd`, replace the body of the `"art"` match case and add two new static functions:

```gdscript
static func scan_png_basenames(dir: String) -> Array:
	var names: Array = []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".png"):
			names.append(file.get_basename())
	names.sort()
	return names

static func scan_subfolders(dir: String) -> Array:
	var names: Array = []
	for folder in DirAccess.get_directories_at(dir):
		names.append(folder)
	names.sort()
	return names
```

Update the `"art"` case inside `choices_for`:

```gdscript
		"art":
			return scan_png_basenames(ART_DIR)
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS, and the existing `test_map_editor.gd` art-dropdown coverage still passes unchanged (it exercises `choices_for` indirectly through the station editor's Art field).

- [ ] **Step 5: Commit**

```bash
git add scripts/editor/editor_fields.gd tests/test_editor_fields.gd tests/run_tests.gd
git commit -m "Generalize the map editor's asset-folder scanning"
```

---

### Task 4: `SceneryRandomizer` pure generation logic

**Files:**
- Create: `scripts\editor\scenery_randomizer.gd`
- Test: `tests\test_scenery_randomizer.gd`
- Modify: `tests\run_tests.gd`

**Interfaces:**
- Consumes: `StarfieldAssignment.CATEGORIES`, `StarfieldAssignment.SEED_COUNT` (Task 2 unchanged consts).
- Produces: `SceneryRandomizer.generate(rng: RandomNumberGenerator, planet_textures: Array, asteroid_textures: Array) -> Dictionary` returning `{"background": {"category": String, "seed": int}, "scenery": Array}`, where each `scenery` entry is `{"type": "planet"|"asteroid", "texture": String, "pos": [float, float], "scale": float, "layer": String}` with `pos` inside `[0, SPACE.x] x [0, SPACE.y]` (`SPACE := Vector2(3200, 3200)`). Later tasks (`MapEditModel.randomize_scenery`) call this directly.

- [ ] **Step 1: Write the failing test**

Create `tests\test_scenery_randomizer.gd`:

```gdscript
extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var planets := ["planet_gas_purple.png", "planet_earthlike.png"]
	var asteroids := ["v1_round_a.png", "v2_elongated_a.png"]
	var result := SceneryRandomizer.generate(rng, planets, asteroids)

	if not StarfieldAssignmentScript.CATEGORIES.has(result["background"]["category"]):
		failures.append("generate: unexpected background category %s" % [result["background"]])
	if result["background"]["seed"] < 1 or result["background"]["seed"] > StarfieldAssignmentScript.SEED_COUNT:
		failures.append("generate: seed out of range, got %s" % [result["background"]])

	var scenery: Array = result["scenery"]
	var planet_count := 0
	var asteroid_count := 0
	for item in scenery:
		if item["type"] == "planet":
			planet_count += 1
		elif item["type"] == "asteroid":
			asteroid_count += 1
		else:
			failures.append("generate: unexpected type %s" % item["type"])
		var pos: Array = item["pos"]
		if pos[0] < 0.0 or pos[0] > SceneryRandomizer.SPACE.x or pos[1] < 0.0 or pos[1] > SceneryRandomizer.SPACE.y:
			failures.append("generate: position out of bounds, got %s" % [pos])
		if not SceneryRandomizer.LAYERS.has(item["layer"]):
			failures.append("generate: unexpected layer %s" % item["layer"])
	if planet_count < 1 or planet_count > 2:
		failures.append("generate: expected 1-2 planets, got %d" % planet_count)
	if asteroid_count < 1 or asteroid_count > 4:
		failures.append("generate: expected 1-4 asteroids, got %d" % asteroid_count)

	# Same-type overlap check (mirrors test_combat_scenery.gd's approach).
	for i in scenery.size():
		for j in range(i + 1, scenery.size()):
			var a: Dictionary = scenery[i]
			var b: Dictionary = scenery[j]
			if a["type"] != b["type"]:
				continue
			var pa := Vector2(a["pos"][0], a["pos"][1])
			var pb := Vector2(b["pos"][0], b["pos"][1])
			var base: float = SceneryRandomizer.PLANET_BASE_RADIUS if a["type"] == "planet" else SceneryRandomizer.ASTEROID_BASE_RADIUS
			var radii: float = (float(a["scale"]) + float(b["scale"])) * base
			if pa.distance_to(pb) < radii:
				failures.append("generate: %s and %s of the same type overlap (distance %.1f < %.1f)" % [a["texture"], b["texture"], pa.distance_to(pb), radii])

	var repeat := RandomNumberGenerator.new()
	repeat.seed = 42
	var result2 := SceneryRandomizer.generate(repeat, planets, asteroids)
	if result2 != result:
		failures.append("generate: expected the same seed to reproduce the same result")
	return failures
```

Note: `StarfieldAssignmentScript` needs a `const StarfieldAssignmentScript = preload("res://scripts/background/starfield_assignment.gd")` at the top of the test file, matching `test_starfield_assignment.gd`'s own preload style.

- [ ] **Step 2: Register the test and run it to verify it fails**

Add `preload("res://tests/test_scenery_randomizer.gd"),` to `tests\run_tests.gd`'s `test_scripts` array, right after `test_editor_fields.gd`.

Run: `godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `SceneryRandomizer` doesn't exist.

- [ ] **Step 3: Implement `SceneryRandomizer`**

Create `scripts\editor\scenery_randomizer.gd`:

```gdscript
class_name SceneryRandomizer
extends RefCounted

# Generates random system scenery: same spirit as CombatScenery's hand-placed recipes, but
# procedural, since every system (not 5 combat backdrops) needs its own look. PLANET/ASTEROID_
# BASE_RADIUS are approximate visible radii at scale 1.0 (same idea as CombatScenery's per-body
# "radius", tuned by eye against its existing values), used only for the overlap check below.

const SPACE := Vector2(3200.0, 3200.0)
const LAYERS := ["deep_background", "mid_distance", "foreground"]
const PLANET_SCALE_MIN := 3.0
const PLANET_SCALE_MAX := 4.0
const ASTEROID_SCALE_MIN := 1.0
const ASTEROID_SCALE_MAX := 2.5
const PLANET_BASE_RADIUS := 128.0
const ASTEROID_BASE_RADIUS := 160.0
const MAX_RETRIES := 8

static func generate(rng: RandomNumberGenerator, planet_textures: Array, asteroid_textures: Array) -> Dictionary:
	var background := {
		"category": StarfieldAssignment.CATEGORIES[rng.randi_range(0, StarfieldAssignment.CATEGORIES.size() - 1)],
		"seed": rng.randi_range(1, StarfieldAssignment.SEED_COUNT),
	}
	var scenery: Array = []
	for i in rng.randi_range(1, 2):
		scenery.append(_place(rng, "planet", planet_textures, PLANET_SCALE_MIN, PLANET_SCALE_MAX, PLANET_BASE_RADIUS, scenery))
	for i in rng.randi_range(1, 4):
		scenery.append(_place(rng, "asteroid", asteroid_textures, ASTEROID_SCALE_MIN, ASTEROID_SCALE_MAX, ASTEROID_BASE_RADIUS, scenery))
	return {"background": background, "scenery": scenery}

static func _place(rng: RandomNumberGenerator, type: String, textures: Array, scale_min: float, scale_max: float, base_radius: float, placed: Array) -> Dictionary:
	var texture: String = textures[rng.randi_range(0, textures.size() - 1)]
	var scale: float = rng.randf_range(scale_min, scale_max)
	var layer: String = LAYERS[rng.randi_range(0, LAYERS.size() - 1)]
	var pos := Vector2.ZERO
	for attempt in MAX_RETRIES:
		pos = Vector2(rng.randf_range(0.0, SPACE.x), rng.randf_range(0.0, SPACE.y))
		if not _overlaps(pos, scale, base_radius, type, placed):
			break
	return {"type": type, "texture": texture, "pos": [pos.x, pos.y], "scale": scale, "layer": layer}

static func _overlaps(pos: Vector2, scale: float, base_radius: float, type: String, placed: Array) -> bool:
	for item in placed:
		if item["type"] != type:
			continue
		var other_pos := Vector2(item["pos"][0], item["pos"][1])
		var other_radius: float = float(item["scale"]) * base_radius
		if pos.distance_to(other_pos) < scale * base_radius + other_radius:
			return true
	return false
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/editor/scenery_randomizer.gd tests/test_scenery_randomizer.gd tests/run_tests.gd
git commit -m "Add SceneryRandomizer for random per-system backgrounds and scenery"
```

---

### Task 5: `MapEditModel` background and scenery edits

**Files:**
- Modify: `scripts\editor\map_edit_model.gd`
- Test: `tests\test_map_edit_model.gd`

**Interfaces:**
- Consumes: `SceneryRandomizer.generate()` (Task 4).
- Produces (all on `MapEditModel`):
  - `set_background(system_id: String, category: String, seed: int) -> void`
  - `clear_background(system_id: String) -> void` (erases the key; the system falls back to the hash)
  - `add_scenery(system_id: String, type: String, texture: String, layer: String) -> int` — appends a new item at the center of `SceneryRandomizer.SPACE` with a default scale (`3.5` for `"planet"`, `"1.5"` for `"asteroid"`), returns its index
  - `set_scenery_field(system_id: String, index: int, key: String, value) -> void` (`key` one of `pos`, `scale`, `layer`, `texture`)
  - `remove_scenery(system_id: String, index: int) -> bool`
  - `randomize_scenery(system_id: String, rng: RandomNumberGenerator, planet_textures: Array, asteroid_textures: Array) -> void` — replaces the system's `background` and `scenery` wholesale via `SceneryRandomizer.generate`

- [ ] **Step 1: Write the failing tests**

Add to `tests\test_map_edit_model.gd` (find its `run()` dispatcher and existing `_check_*` style; add a new function and call it from `run()`):

```gdscript
static func _check_background_and_scenery(failures: Array[String]) -> void:
	var model := MapEditModel.from_document(Validator.doc())

	model.set_background("b", "dense", 4)
	if model.doc["systems"][1].get("background", {}) != {"category": "dense", "seed": 4} or not model.dirty:
		failures.append("set_background: expected it stored and the model dirty, got %s" % [model.doc["systems"][1].get("background")])
	model.clear_background("b")
	if model.doc["systems"][1].has("background"):
		failures.append("clear_background: expected the key removed")

	var index := model.add_scenery("b", "planet", "planet_gas_purple.png", "mid_distance")
	var scenery: Array = model.doc["systems"][1]["scenery"]
	if index != 0 or scenery.size() != 1 or scenery[0]["type"] != "planet" or scenery[0]["layer"] != "mid_distance":
		failures.append("add_scenery: expected one planet entry, got %s" % [scenery])
	if typeof(scenery[0]["pos"]) != TYPE_ARRAY or scenery[0]["scale"] <= 0.0:
		failures.append("add_scenery: expected a default pos and positive scale, got %s" % [scenery[0]])

	model.set_scenery_field("b", 0, "scale", 5.0)
	if model.doc["systems"][1]["scenery"][0]["scale"] != 5.0:
		failures.append("set_scenery_field: expected scale 5.0, got %s" % [model.doc["systems"][1]["scenery"][0]])
	model.set_scenery_field("b", 0, "pos", Vector2(100.0, 200.0))
	if model.doc["systems"][1]["scenery"][0]["pos"] != [100.0, 200.0]:
		failures.append("set_scenery_field: expected pos [100, 200], got %s" % [model.doc["systems"][1]["scenery"][0]["pos"]])

	model.add_scenery("b", "asteroid", "v1_round_a.png", "foreground")
	if not model.remove_scenery("b", 0) or model.doc["systems"][1]["scenery"].size() != 1 \
			or model.doc["systems"][1]["scenery"][0]["type"] != "asteroid":
		failures.append("remove_scenery: expected the planet removed and the asteroid left, got %s" % [model.doc["systems"][1]["scenery"]])
	if model.remove_scenery("b", 99):
		failures.append("remove_scenery: expected an out-of-range index refused")

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	model.randomize_scenery("b", rng, ["planet_gas_purple.png"], ["v1_round_a.png"])
	if not model.doc["systems"][1].has("background") or model.doc["systems"][1]["scenery"].is_empty():
		failures.append("randomize_scenery: expected a fresh background and non-empty scenery, got %s" % [model.doc["systems"][1]])
```

Add `const Validator = preload("res://tests/test_galaxy_validator.gd")` at the top of `test_map_edit_model.gd` if it isn't already imported under that name (check the existing file first — it likely already builds its own fixture doc; if so, reuse whatever existing helper constructs a 3-system `a`/`b`/`c` doc instead of introducing `Validator`, to stay consistent with the file's existing style).

- [ ] **Step 2: Run test to verify it fails**

Run: `godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — the new `MapEditModel` methods don't exist.

- [ ] **Step 3: Implement the methods**

Add to `scripts\editor\map_edit_model.gd`, in a new `# --- background & scenery ---` section after the existing `# --- links ---` section (systems-related, so it belongs near `set_system_field`):

```gdscript
# --- background & scenery ---

const NEW_SCENERY_POS := [1600.0, 1600.0]
const NEW_SCENERY_SCALE := {"planet": 3.5, "asteroid": 1.5}

func set_background(system_id: String, category: String, seed: int) -> void:
	var i := _system_index(system_id)
	if i < 0:
		return
	doc["systems"][i]["background"] = {"category": category, "seed": seed}
	_touch()

func clear_background(system_id: String) -> void:
	var i := _system_index(system_id)
	if i < 0:
		return
	doc["systems"][i].erase("background")
	_touch()

func _scenery_of(system_id: String) -> Array:
	var i := _system_index(system_id)
	if i < 0:
		return []
	if not doc["systems"][i].has("scenery"):
		doc["systems"][i]["scenery"] = []
	return doc["systems"][i]["scenery"]

func add_scenery(system_id: String, type: String, texture: String, layer: String) -> int:
	var scenery := _scenery_of(system_id)
	if _system_index(system_id) < 0:
		return -1
	scenery.append({"type": type, "texture": texture, "pos": NEW_SCENERY_POS.duplicate(),
		"scale": NEW_SCENERY_SCALE.get(type, 1.0), "layer": layer})
	_touch()
	return scenery.size() - 1

func set_scenery_field(system_id: String, index: int, key: String, value) -> void:
	var scenery := _scenery_of(system_id)
	if index < 0 or index >= scenery.size():
		return
	scenery[index][key] = _vec_to_array(value)
	_touch()

func remove_scenery(system_id: String, index: int) -> bool:
	var scenery := _scenery_of(system_id)
	if index < 0 or index >= scenery.size():
		return false
	scenery.remove_at(index)
	_touch()
	return true

func randomize_scenery(system_id: String, rng: RandomNumberGenerator, planet_textures: Array, asteroid_textures: Array) -> void:
	var i := _system_index(system_id)
	if i < 0:
		return
	var generated := SceneryRandomizer.generate(rng, planet_textures, asteroid_textures)
	doc["systems"][i]["background"] = generated["background"]
	doc["systems"][i]["scenery"] = generated["scenery"]
	_touch()
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/editor/map_edit_model.gd tests/test_map_edit_model.gd
git commit -m "Add MapEditModel edits for per-system background and scenery"
```

---

### Task 6: `StationCanvas` — draggable station art on the Stations sub-tab

**Files:**
- Create: `scripts\editor\station_canvas.gd`
- Test: `tests\test_map_editor.gd` (extend; this canvas is exercised through the editor like `MapCanvas` is)

**Interfaces:**
- Consumes: a galaxy document (`Dictionary`) and a `system_id: String`, via `set_system(doc, system_id)`.
- Produces: `StationCanvas.station_moved(id: String, pos: Vector2)` and `StationCanvas.station_selected(id: String)` signals; public `handle_press(point, button)`, `handle_drag(point)`, `handle_release()`, `station_at(point) -> String`, and `station_points: Dictionary` (id -> `Vector2`, the same coordinate space as the station `pos` field) for tests to drive directly, mirroring `MapCanvas`'s public test surface.

- [ ] **Step 1: Write the failing test**

Add a new check function to `tests\test_map_editor.gd` and call it from `run_async` (after `_check_drag`, since it needs `editor` already loaded):

```gdscript
static func _check_station_canvas(editor: MapEditor, failures: Array[String]) -> void:
	editor.load_document(Validator.doc())
	editor.select_system("b")
	var canvas := editor.station_canvas
	canvas.set_system(editor.model.doc, "b")
	if not canvas.station_points.has("post_b"):
		failures.append("station canvas: expected post_b plotted, got %s" % [canvas.station_points.keys()])
		return
	var start: Vector2 = canvas.station_points["post_b"]
	canvas.handle_press(start, MOUSE_BUTTON_LEFT)
	if editor.selected_station != "" :
		pass # selection itself is wired at the MapEditor level in Task 10; here we only check the canvas's own signal/drag plumbing
	canvas.handle_drag(start + Vector2(50.0, 20.0))
	canvas.handle_release()
	var moved_pos: Array = editor.model.doc["stations"][editor.model.station_index("post_b")]["pos"]
	if Vector2(moved_pos[0], moved_pos[1]) == Vector2(300.0, 250.0):
		failures.append("station canvas: expected post_b's pos to change after a drag, stayed at %s" % [moved_pos])
	editor.load_document(Validator.doc())
```

This test references `editor.station_canvas`, which doesn't exist until Task 10 wires it into `MapEditor`. **Leave this test commented out (or skip calling it) until Task 10** — write it now as a standalone canvas-level test instead so Task 6 is independently testable:

```gdscript
# Standalone (no MapEditor) version actually used for this task:
static func _check_station_canvas_standalone(failures: Array[String]) -> void:
	var canvas := StationCanvas.new()
	canvas.size = Vector2(1152, 648)
	var doc := Validator.doc()
	canvas.set_system(doc, "b")
	if not canvas.station_points.has("post_b"):
		failures.append("station canvas: expected post_b plotted, got %s" % [canvas.station_points.keys()])
		return
	var start: Vector2 = canvas.station_points["post_b"]
	var moved_signals: Array = []
	canvas.station_moved.connect(func(id: String, pos: Vector2): moved_signals.append([id, pos]))
	var selected_signals: Array[String] = []
	canvas.station_selected.connect(func(id: String): selected_signals.append(id))
	canvas.handle_press(start, MOUSE_BUTTON_LEFT)
	if selected_signals != ["post_b"] or canvas.selected != "post_b":
		failures.append("station canvas: expected post_b selected on press, got %s" % [selected_signals])
	canvas.handle_drag(start + Vector2(50.0, 20.0))
	if moved_signals.size() != 1 or moved_signals[0][0] != "post_b":
		failures.append("station canvas: expected a station_moved signal for post_b, got %s" % [moved_signals])
	canvas.handle_release()
	canvas.handle_drag(start + Vector2(500.0, 500.0))
	if moved_signals.size() != 1:
		failures.append("station canvas: expected a drag after release to be ignored")
	canvas.queue_free()
```

Call `_check_station_canvas_standalone(failures)` from `run_async` (plain call, not awaited, placed right after `_check_drag(editor, failures)`). Remove the earlier `_check_station_canvas` draft (the `MapEditor`-dependent one) from the file for now — it was exploratory; only the standalone version ships in this task. Add `const Validator = preload("res://tests/test_galaxy_validator.gd")` at the top of `test_map_editor.gd` if not already present (check first — `MapEditor`'s own test already uses `Validator.doc()` per the existing file, so it's already imported).

- [ ] **Step 2: Run test to verify it fails**

Run: `godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `StationCanvas` doesn't exist.

- [ ] **Step 3: Implement `StationCanvas`**

Create `scripts\editor\station_canvas.gd`:

```gdscript
class_name StationCanvas
extends Control

# Draws every station in one system as its real sprite at its real `pos`, 1:1 with the station
# `pos` field's own coordinate space (JumpRules.SYSTEM_MIN..MAX), and turns mouse input into
# signals; the editor applies them to the model. Mirrors MapCanvas's shape.

signal station_selected(id: String)
signal station_moved(id: String, pos: Vector2)

const BACKDROP_COLOR := Color(0.02, 0.03, 0.06, 1.0)
const ICON_RADIUS := 36.0
const SELECTED_RING_RADIUS := 44.0
const SELECTED_COLOR := Color(0.4, 0.8, 1.0, 1.0)

var selected: String = ""
# station id -> Vector2 in the document's own pos space.
var station_points: Dictionary = {}

var _doc: Dictionary = {}
var _system_id: String = ""
var _textures: Dictionary = {}
var _drag_id: String = ""

func set_system(doc: Dictionary, system_id: String) -> void:
	_doc = doc
	_system_id = system_id
	refresh()

func refresh() -> void:
	station_points.clear()
	_textures.clear()
	for st in _doc.get("stations", []):
		if st.get("system", "") != _system_id:
			continue
		var id := MapEditModel.station_id_of(st)
		var pos: Array = st.get("pos", [580.0, 350.0])
		station_points[id] = Vector2(pos[0], pos[1])
		var path := "res://assets/sprites/stations/%s.png" % str(st.get("art", "ring_2"))
		if ResourceLoader.exists(path):
			_textures[id] = load(path)
	queue_redraw()

func station_at(point: Vector2) -> String:
	var nearest := ""
	var nearest_dist := ICON_RADIUS
	for id in station_points:
		var dist: float = point.distance_to(station_points[id])
		if dist <= nearest_dist:
			nearest = id
			nearest_dist = dist
	return nearest

func handle_press(point: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	var id := station_at(point)
	if id != "":
		selected = id
		station_selected.emit(id)
		_drag_id = id
	queue_redraw()

func handle_drag(point: Vector2) -> void:
	if _drag_id != "":
		station_moved.emit(_drag_id, point)

func handle_release() -> void:
	_drag_id = ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			handle_press(event.position, event.button_index)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			handle_release()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		handle_drag(event.position)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP_COLOR)
	for id in station_points:
		var point: Vector2 = station_points[id]
		if _textures.has(id):
			var tex: Texture2D = _textures[id]
			var longest: float = max(tex.get_width(), tex.get_height())
			var icon_scale: float = (ICON_RADIUS * 2.0) / longest
			var draw_size := Vector2(tex.get_width(), tex.get_height()) * icon_scale
			draw_texture_rect(tex, Rect2(point - draw_size * 0.5, draw_size), false)
		else:
			draw_circle(point, ICON_RADIUS, Color.GRAY)
		if id == selected:
			draw_arc(point, SELECTED_RING_RADIUS, 0.0, TAU, 32, SELECTED_COLOR, 2.0, true)
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/editor/station_canvas.gd tests/test_map_editor.gd
git commit -m "Add StationCanvas for dragging station art onto its real position"
```

---

### Task 7: `SceneryCanvas` — draggable scenery on the Scenery sub-tab

**Files:**
- Create: `scripts\editor\scenery_canvas.gd`
- Test: `tests\test_scenery_canvas.gd`
- Modify: `tests\run_tests.gd`

**Interfaces:**
- Consumes: `MapEditModel.station_id_of` is not needed here (scenery has no id, only an index); nothing else from earlier tasks at compile time, but the data shape matches Task 5's `scenery` entries.
- Produces: `SceneryCanvas.SPACE := Vector2(3200, 3200)` (shared constant, same value as `SceneryRandomizer.SPACE`), `SceneryCanvas.VIEWPORT_SIZE := Vector2(1152, 648)`, `set_scenery(scenery: Array, background_texture: Texture2D) -> void`, signals `scenery_selected(index: int)` and `scenery_moved(index: int, pos: Vector2)`, public `handle_press`, `handle_drag`, `handle_release`, `item_at(point) -> int`.

- [ ] **Step 1: Write the failing test**

Create `tests\test_scenery_canvas.gd`:

```gdscript
extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	var canvas := SceneryCanvas.new()
	canvas.size = Vector2(800, 800)
	var scenery := [
		{"type": "planet", "texture": "planet_gas_purple.png", "pos": [1600.0, 1600.0], "scale": 3.5, "layer": "mid_distance"},
		{"type": "asteroid", "texture": "v1_round_a.png", "pos": [400.0, 400.0], "scale": 1.5, "layer": "foreground"},
	]
	canvas.set_scenery(scenery, null)

	var moved_signals: Array = []
	canvas.scenery_moved.connect(func(index: int, pos: Vector2): moved_signals.append([index, pos]))
	var selected_signals: Array[int] = []
	canvas.scenery_selected.connect(func(index: int): selected_signals.append(index))

	var point := canvas._world_to_canvas(Vector2(1600.0, 1600.0))
	canvas.handle_press(point, MOUSE_BUTTON_LEFT)
	if selected_signals != [0] or canvas.selected_index != 0:
		failures.append("scenery canvas: expected index 0 selected at the planet's point, got %s" % [selected_signals])
	canvas.handle_drag(point + Vector2(40.0, 10.0))
	if moved_signals.size() != 1 or moved_signals[0][0] != 0:
		failures.append("scenery canvas: expected a scenery_moved signal for index 0, got %s" % [moved_signals])
	var moved_world: Vector2 = moved_signals[0][1]
	if moved_world.x < 0.0 or moved_world.x > SceneryCanvas.SPACE.x or moved_world.y < 0.0 or moved_world.y > SceneryCanvas.SPACE.y:
		failures.append("scenery canvas: expected the moved position clamped inside SPACE, got %s" % moved_world)
	canvas.handle_release()

	var far_point := canvas._world_to_canvas(Vector2(10.0, 10.0))
	canvas.handle_press(far_point, MOUSE_BUTTON_LEFT)
	if selected_signals.size() != 1:
		failures.append("scenery canvas: expected a click far from any item to not select, got %s selections" % selected_signals.size())
	canvas.queue_free()
	return failures
```

- [ ] **Step 2: Register and run to verify it fails**

Add `preload("res://tests/test_scenery_canvas.gd"),` to `tests\run_tests.gd`'s `test_scripts` array, after `test_scenery_randomizer.gd`.

Run: `godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `SceneryCanvas` doesn't exist.

- [ ] **Step 3: Implement `SceneryCanvas`**

Create `scripts\editor\scenery_canvas.gd`:

```gdscript
class_name SceneryCanvas
extends Control

# Draws a system's background and placed planets/asteroids at the 3200x3200 scale the combat
# arena uses (future-proofed for camera panning, even though nothing scrolls today), with the
# actual 1152x648 campaign viewport outlined so it's clear what's visible in-game right now.

signal scenery_selected(index: int)
signal scenery_moved(index: int, pos: Vector2)

const SPACE := Vector2(3200.0, 3200.0)
const VIEWPORT_SIZE := Vector2(1152.0, 648.0)
const BACKDROP_COLOR := Color(0.02, 0.03, 0.06, 1.0)
const VIEWPORT_OUTLINE_COLOR := Color(0.4, 0.8, 1.0, 0.5)
const PICK_RADIUS := 24.0
const SELECTED_COLOR := Color(0.4, 0.8, 1.0, 1.0)
const FOLDER_BY_TYPE := {"planet": "planets", "asteroid": "asteroids"}

var selected_index: int = -1
var items: Array = []

var _textures: Array = []
var _background_texture: Texture2D = null
var _drag_index: int = -1

func set_scenery(scenery: Array, background_texture: Texture2D) -> void:
	items = scenery.duplicate(true)
	_background_texture = background_texture
	_textures.clear()
	for item in items:
		var folder: String = FOLDER_BY_TYPE.get(item.get("type", ""), "")
		var path := "res://assets/sprites/backgrounds/%s/%s" % [folder, item.get("texture", "")]
		_textures.append(load(path) if folder != "" and ResourceLoader.exists(path) else null)
	queue_redraw()

func _world_to_canvas(world: Vector2) -> Vector2:
	return world * (size / SPACE)

func _canvas_to_world(point: Vector2) -> Vector2:
	return (point * (SPACE / size)).clamp(Vector2.ZERO, SPACE)

func item_at(point: Vector2) -> int:
	var nearest := -1
	var nearest_dist := PICK_RADIUS
	for i in items.size():
		var world := Vector2(items[i]["pos"][0], items[i]["pos"][1])
		var dist: float = point.distance_to(_world_to_canvas(world))
		if dist <= nearest_dist:
			nearest = i
			nearest_dist = dist
	return nearest

func handle_press(point: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	var index := item_at(point)
	selected_index = index
	if index >= 0:
		scenery_selected.emit(index)
		_drag_index = index
	queue_redraw()

func handle_drag(point: Vector2) -> void:
	if _drag_index >= 0:
		scenery_moved.emit(_drag_index, _canvas_to_world(point))

func handle_release() -> void:
	_drag_index = -1

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			handle_press(event.position, event.button_index)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			handle_release()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		handle_drag(event.position)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP_COLOR)
	if _background_texture != null:
		draw_texture_rect(_background_texture, Rect2(Vector2.ZERO, size), true)
	var viewport_origin: Vector2 = _world_to_canvas((SPACE - VIEWPORT_SIZE) / 2.0)
	var viewport_size: Vector2 = VIEWPORT_SIZE * (size / SPACE)
	draw_rect(Rect2(viewport_origin, viewport_size), VIEWPORT_OUTLINE_COLOR, false, 2.0)
	for i in items.size():
		var world := Vector2(items[i]["pos"][0], items[i]["pos"][1])
		var point := _world_to_canvas(world)
		var tex: Texture2D = _textures[i]
		if tex != null:
			var scale_factor: float = float(items[i].get("scale", 1.0))
			var draw_size := Vector2(tex.get_width(), tex.get_height()) * scale_factor * (size.x / SPACE.x)
			draw_texture_rect(tex, Rect2(point - draw_size * 0.5, draw_size), false)
		else:
			draw_circle(point, PICK_RADIUS, Color.GRAY)
		if i == selected_index:
			draw_arc(point, PICK_RADIUS + 6.0, 0.0, TAU, 32, SELECTED_COLOR, 2.0, true)
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/editor/scenery_canvas.gd tests/test_scenery_canvas.gd tests/run_tests.gd
git commit -m "Add SceneryCanvas for placing planets and asteroids at arena scale"
```

---

### Task 8: `SceneryEditor` side panel

**Files:**
- Create: `scripts\editor\scenery_editor.gd`
- Test: `tests\test_scenery_editor.gd`
- Modify: `tests\run_tests.gd`

**Interfaces:**
- Consumes: `MapEditModel` (Task 5), `EditorFields.scan_png_basenames`/`scan_subfolders` (Task 3), `SceneryRandomizer` (Task 4, indirectly via `MapEditModel.randomize_scenery`).
- Produces: `SceneryEditor.bind(model: MapEditModel, system_id: String) -> void`; signal `edited`; public editing methods mirroring `StationEditor`'s style: `set_background(category: String, seed: int)`, `pick_folder(folder: String)`, `pick_layer(layer: String)`, `place_selected()`, `select_item(index: int)`, `set_selected_scale(value: float)`, `delete_selected()`, `randomize()`. Exposes `folder_option: OptionButton`, `layer_option: OptionButton`, `thumbnail_grid: GridContainer`, `scale_spin: SpinBox`, `delete_button: Button`, `randomize_button: Button` so tests and `MapEditor` (Task 10) can drive/inspect it directly, matching how `StationEditor` exposes its controls by name.

- [ ] **Step 1: Write the failing test**

Create `tests\test_scenery_editor.gd`:

```gdscript
extends RefCounted

const Validator = preload("res://tests/test_galaxy_validator.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []
	var model := MapEditModel.from_document(Validator.doc())
	var editor := SceneryEditor.new()
	editor.bind(model, "b")

	if editor.folder_option.item_count < 2:
		failures.append("scenery editor: expected at least 2 folders (planets, asteroids), got %d" % editor.folder_option.item_count)
	editor.pick_folder("planets")
	if editor.thumbnail_grid.get_child_count() == 0:
		failures.append("scenery editor: expected thumbnails for the planets folder")
	editor.select_thumbnail("planet_gas_purple")
	editor.pick_layer("foreground")
	editor.place_selected()
	var scenery: Array = model.doc["systems"][1]["scenery"]
	if scenery.size() != 1 or scenery[0]["texture"] != "planet_gas_purple.png" or scenery[0]["layer"] != "foreground":
		failures.append("place_selected: expected a placed planet_gas_purple on foreground, got %s" % [scenery])

	editor.select_item(0)
	editor.set_selected_scale(4.2)
	if model.doc["systems"][1]["scenery"][0]["scale"] != 4.2:
		failures.append("set_selected_scale: expected 4.2, got %s" % [model.doc["systems"][1]["scenery"][0]])

	editor.delete_selected()
	if not model.doc["systems"][1]["scenery"].is_empty():
		failures.append("delete_selected: expected scenery cleared, got %s" % [model.doc["systems"][1]["scenery"]])

	editor.set_background("sparse", 1)
	if model.doc["systems"][1].get("background", {}) != {"category": "sparse", "seed": 1}:
		failures.append("set_background: expected it stored, got %s" % [model.doc["systems"][1].get("background")])

	editor.randomize()
	if not model.doc["systems"][1].has("background") or model.doc["systems"][1]["scenery"].is_empty():
		failures.append("randomize: expected a fresh background and scenery, got %s" % [model.doc["systems"][1]])

	editor.queue_free()
	return failures
```

- [ ] **Step 2: Register and run to verify it fails**

Add `preload("res://tests/test_scenery_editor.gd"),` to `tests\run_tests.gd`'s `test_scripts` array, after `test_scenery_canvas.gd`.

Run: `godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `SceneryEditor` doesn't exist.

- [ ] **Step 3: Implement `SceneryEditor`**

Create `scripts\editor\scenery_editor.gd`:

```gdscript
class_name SceneryEditor
extends VBoxContainer

# The Scenery sub-tab's side panel: background category/seed, an asset-folder thumbnail
# browser, layer picking, randomize, and the selected item's scale/delete. All edits go
# through MapEditModel; `edited` tells the screen to refresh its canvas and findings.

signal edited

const BACKGROUNDS_DIR := "res://assets/sprites/backgrounds"
const LAYERS := ["deep_background", "mid_distance", "foreground"]
const SEED_COUNT := 5
# Singular type name stored in the document, keyed by the plural folder name on disk.
const TYPE_BY_FOLDER := {"planets": "planet", "asteroids": "asteroid"}

var model: MapEditModel = null
var system_id: String = ""

var background_category_option: OptionButton
var background_seed_option: OptionButton
var folder_option: OptionButton
var layer_option: OptionButton
var thumbnail_grid: GridContainer
var scale_spin: SpinBox
var delete_button: Button
var randomize_button: Button

var _selected_folder: String = ""
var _selected_texture: String = ""
var _selected_index: int = -1

func bind(new_model: MapEditModel, new_system_id: String) -> void:
	model = new_model
	system_id = new_system_id
	_rebuild()

func pick_folder(folder: String) -> void:
	_selected_folder = folder
	_selected_texture = ""
	_rebuild_thumbnails()

func select_thumbnail(basename: String) -> void:
	_selected_texture = "%s.png" % basename

func pick_layer(_layer: String) -> void:
	pass # layer_option already reflects the choice; place_selected reads it directly

func place_selected() -> void:
	if model == null or _selected_folder == "" or _selected_texture == "":
		return
	var type: String = TYPE_BY_FOLDER.get(_selected_folder, _selected_folder.trim_suffix("s"))
	var layer := layer_option.get_item_text(layer_option.selected) if layer_option.selected >= 0 else LAYERS[0]
	model.add_scenery(system_id, type, _selected_texture, layer)
	edited.emit()
	_rebuild()

func select_item(index: int) -> void:
	_selected_index = index
	var entry := _entry()
	if entry.is_empty() or index < 0 or index >= entry.get("scenery", []).size():
		return
	scale_spin.value = float(entry["scenery"][index].get("scale", 1.0))

func set_selected_scale(value: float) -> void:
	if model == null or _selected_index < 0:
		return
	model.set_scenery_field(system_id, _selected_index, "scale", value)
	edited.emit()

func delete_selected() -> void:
	if model == null or _selected_index < 0:
		return
	model.remove_scenery(system_id, _selected_index)
	_selected_index = -1
	edited.emit()
	_rebuild()

func set_background(category: String, seed: int) -> void:
	if model == null:
		return
	model.set_background(system_id, category, seed)
	edited.emit()

func randomize() -> void:
	if model == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var planets := EditorFields.scan_png_basenames("%s/planets" % BACKGROUNDS_DIR)
	var asteroids := EditorFields.scan_png_basenames("%s/asteroids" % BACKGROUNDS_DIR)
	var planet_files: Array = planets.map(func(name): return "%s.png" % name)
	var asteroid_files: Array = asteroids.map(func(name): return "%s.png" % name)
	model.randomize_scenery(system_id, rng, planet_files, asteroid_files)
	edited.emit()
	_rebuild()

func _entry() -> Dictionary:
	if model == null:
		return {}
	for sys in model.doc["systems"]:
		if sys["id"] == system_id:
			return sys
	return {}

func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

func _rebuild() -> void:
	_clear()
	if model == null:
		return

	add_child(_label("Background"))
	background_category_option = OptionButton.new()
	background_category_option.name = "BackgroundCategory"
	for category in StarfieldAssignment.CATEGORIES:
		background_category_option.add_item(category)
	background_category_option.item_selected.connect(func(_i): _on_background_changed())
	add_child(background_category_option)
	background_seed_option = OptionButton.new()
	background_seed_option.name = "BackgroundSeed"
	for seed in range(1, SEED_COUNT + 1):
		background_seed_option.add_item(str(seed))
	background_seed_option.item_selected.connect(func(_i): _on_background_changed())
	add_child(background_seed_option)
	var current_background: Dictionary = StarfieldAssignment.pick(system_id, StarfieldAssignment.SYSTEM_CATEGORIES, _entry().get("background", {}))
	background_category_option.select(StarfieldAssignment.CATEGORIES.find(current_background.category))
	background_seed_option.select(current_background.seed - 1)

	add_child(_label("Folder"))
	folder_option = OptionButton.new()
	folder_option.name = "Folder"
	var folders := EditorFields.scan_subfolders(BACKGROUNDS_DIR)
	for folder in folders:
		if TYPE_BY_FOLDER.has(folder):
			folder_option.add_item(folder)
	folder_option.item_selected.connect(func(i): pick_folder(folder_option.get_item_text(i)))
	add_child(folder_option)
	if _selected_folder == "" and folder_option.item_count > 0:
		_selected_folder = folder_option.get_item_text(0)

	add_child(_label("Layer"))
	layer_option = OptionButton.new()
	layer_option.name = "Layer"
	for layer in LAYERS:
		layer_option.add_item(layer)
	add_child(layer_option)

	thumbnail_grid = GridContainer.new()
	thumbnail_grid.name = "ThumbnailGrid"
	thumbnail_grid.columns = 2
	add_child(thumbnail_grid)
	_rebuild_thumbnails()

	var place_button := Button.new()
	place_button.name = "PlaceButton"
	place_button.text = "+ Place"
	place_button.pressed.connect(place_selected)
	add_child(place_button)

	randomize_button = Button.new()
	randomize_button.name = "RandomizeButton"
	randomize_button.text = "Randomize"
	randomize_button.pressed.connect(randomize)
	add_child(randomize_button)

	add_child(_label("Selected item"))
	scale_spin = SpinBox.new()
	scale_spin.name = "ScaleSpin"
	scale_spin.min_value = 0.1
	scale_spin.max_value = 10.0
	scale_spin.step = 0.1
	scale_spin.value_changed.connect(set_selected_scale)
	add_child(scale_spin)
	delete_button = Button.new()
	delete_button.name = "DeleteButton"
	delete_button.text = "Delete"
	delete_button.pressed.connect(delete_selected)
	add_child(delete_button)

func _rebuild_thumbnails() -> void:
	if thumbnail_grid == null:
		return
	for child in thumbnail_grid.get_children():
		thumbnail_grid.remove_child(child)
		child.queue_free()
	if _selected_folder == "":
		return
	for basename in EditorFields.scan_png_basenames("%s/%s" % [BACKGROUNDS_DIR, _selected_folder]):
		var button := Button.new()
		button.name = "Thumb_%s" % basename
		button.text = basename
		var path := "%s/%s/%s.png" % [BACKGROUNDS_DIR, _selected_folder, basename]
		if ResourceLoader.exists(path):
			button.icon = load(path)
		button.pressed.connect(func(): select_thumbnail(basename))
		thumbnail_grid.add_child(button)

func _on_background_changed() -> void:
	var category: String = background_category_option.get_item_text(background_category_option.selected)
	var seed: int = background_seed_option.selected + 1
	set_background(category, seed)

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/editor/scenery_editor.gd tests/test_scenery_editor.gd tests/run_tests.gd
git commit -m "Add SceneryEditor side panel for backgrounds and scenery placement"
```

---

### Task 9: `MapEditor` — wire the System tab together

**Files:**
- Modify: `scripts\editor\map_editor.gd`
- Test: `tests\test_map_editor.gd`

**Interfaces:**
- Consumes: `StationCanvas` (Task 6), `SceneryCanvas` (Task 7), `SceneryEditor` (Task 8).
- Produces: `MapEditor.station_canvas: StationCanvas`, `MapEditor.scenery_canvas: SceneryCanvas`, `MapEditor.scenery_editor: SceneryEditor`, all rebuilt/refreshed whenever `select_system` runs or a scenery/background edit happens, exactly like the existing `canvas`/`station_box` are today.

- [ ] **Step 1: Write the failing test**

Add to `tests\test_map_editor.gd`, a new check exercising the wiring (the real `_check_station_canvas` from Task 6's draft, now meaningful because `editor.station_canvas` exists):

```gdscript
static func _check_system_tab(editor: MapEditor, failures: Array[String]) -> void:
	editor.load_document(Validator.doc())
	editor.select_system("b")
	if not editor.station_canvas.station_points.has("post_b"):
		failures.append("system tab: expected the station canvas to show post_b, got %s" % [editor.station_canvas.station_points.keys()])

	var start: Vector2 = editor.station_canvas.station_points["post_b"]
	editor.station_canvas.handle_press(start, MOUSE_BUTTON_LEFT)
	if editor.selected_station != "post_b":
		failures.append("system tab: expected clicking the station canvas to select post_b, got '%s'" % editor.selected_station)
	editor.station_canvas.handle_drag(start + Vector2(30.0, 10.0))
	editor.station_canvas.handle_release()
	var moved: Array = editor.model.doc["stations"][editor.model.station_index("post_b")]["pos"]
	if Vector2(moved[0], moved[1]) == Vector2(300.0, 250.0):
		failures.append("system tab: expected the drag to move post_b's pos, stayed at %s" % [moved])

	editor.scenery_editor.set_background("dense", 2)
	if editor.scenery_canvas.items.is_empty() and editor.model.doc["systems"][1].get("background", {}) != {"category": "dense", "seed": 2}:
		failures.append("system tab: expected the background edit to reach the model")
	editor.scenery_editor.randomize()
	if editor.scenery_canvas.items.is_empty():
		failures.append("system tab: expected the scenery canvas to refresh with the randomized items")
	editor.load_document(Validator.doc())
```

Call `_check_system_tab(editor, failures)` from `run_async`, after `_check_lists`. Also delete the now-redundant `_check_station_canvas_standalone`'s call-site duplication concern — no change needed there, it stays as Task 6's own coverage.

- [ ] **Step 2: Run test to verify it fails**

Run: `godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `editor.station_canvas` etc. don't exist.

- [ ] **Step 3: Wire it into `MapEditor`**

In `scripts\editor\map_editor.gd`:

1. Add fields near the existing `var canvas: MapCanvas` block:

```gdscript
var station_canvas: StationCanvas
var scenery_canvas: SceneryCanvas
var scenery_editor: SceneryEditor
var system_tab: HBoxContainer
```

2. In `_build_ui()`, after the existing `tabs.add_child(preset_scroll)` / `tabs.set_tab_title(1, "Presets")` block, add a third tab with its own two sub-tabs:

```gdscript
	system_tab = HBoxContainer.new()
	system_tab.name = "System"
	tabs.add_child(system_tab)
	tabs.set_tab_title(2, "System")
	var system_subtabs := TabContainer.new()
	system_subtabs.name = "SystemSubtabs"
	system_subtabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	system_tab.add_child(system_subtabs)

	var stations_subtab := HBoxContainer.new()
	stations_subtab.name = "Stations"
	system_subtabs.add_child(stations_subtab)
	station_canvas = StationCanvas.new()
	station_canvas.name = "StationCanvas"
	station_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	station_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	station_canvas.custom_minimum_size = Vector2(300.0, 200.0)
	station_canvas.station_selected.connect(select_station)
	station_canvas.station_moved.connect(_on_station_canvas_moved)
	stations_subtab.add_child(station_canvas)

	var scenery_subtab := HBoxContainer.new()
	scenery_subtab.name = "Scenery"
	system_subtabs.add_child(scenery_subtab)
	scenery_canvas = SceneryCanvas.new()
	scenery_canvas.name = "SceneryCanvas"
	scenery_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scenery_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scenery_canvas.custom_minimum_size = Vector2(300.0, 200.0)
	scenery_canvas.scenery_selected.connect(func(index: int): scenery_editor.select_item(index))
	scenery_canvas.scenery_moved.connect(_on_scenery_canvas_moved)
	scenery_subtab.add_child(scenery_canvas)
	var scenery_editor_scroll := ScrollContainer.new()
	scenery_editor_scroll.name = "SceneryEditorScroll"
	scenery_editor_scroll.custom_minimum_size.x = INSPECTOR_WIDTH
	scenery_editor_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scenery_editor = SceneryEditor.new()
	scenery_editor.name = "SceneryEditorBox"
	scenery_editor.edited.connect(_on_scenery_edited)
	scenery_editor_scroll.add_child(scenery_editor)
	scenery_subtab.add_child(scenery_editor_scroll)
```

3. Add the handlers, near the other `_on_*` edit handlers:

```gdscript
func _on_station_canvas_moved(id: String, pos: Vector2) -> void:
	model.set_station_field(id, "pos", pos)
	_after_edit(selected_station == id)
	station_canvas.refresh()

func _on_scenery_canvas_moved(index: int, pos: Vector2) -> void:
	model.set_scenery_field(selected_system, index, "pos", pos)
	model.dirty = true
	_update_dirty()

func _on_scenery_edited() -> void:
	_refresh_scenery_tab()
	_update_dirty()
```

4. In `select_system(id)`, after the existing `_rebuild_station_box()` call, refresh the new tabs:

```gdscript
	_rebuild_station_box()
	_refresh_system_tab()
```

5. Add the refresh helper near `_rebuild_station_box`:

```gdscript
func _refresh_system_tab() -> void:
	station_canvas.set_system(model.doc, selected_system)
	_refresh_scenery_tab()

func _refresh_scenery_tab() -> void:
	if selected_system == "":
		scenery_canvas.set_scenery([], null)
		return
	scenery_editor.bind(model, selected_system)
	var entry := {}
	for sys in model.doc["systems"]:
		if sys["id"] == selected_system:
			entry = sys
	var background_choice := StarfieldAssignment.pick(selected_system, StarfieldAssignment.SYSTEM_CATEGORIES, entry.get("background", {}))
	var background_path := StarfieldAssignment.base_texture_path(selected_system, StarfieldAssignment.SYSTEM_CATEGORIES, entry.get("background", {}))
	var background_texture: Texture2D = load(background_path) if ResourceLoader.exists(background_path) else null
	scenery_canvas.set_scenery(entry.get("scenery", []), background_texture)
```

6. Also call `_refresh_system_tab()` from `_refresh_all()` (the full-document refresh), right after `_rebuild_station_box()`.

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS, and all of Tasks 1-9's prior tests still pass (0 `SCRIPT ERROR`).

- [ ] **Step 5: Commit**

```bash
git add scripts/editor/map_editor.gd tests/test_map_editor.gd
git commit -m "Wire the System tab (Stations + Scenery) into the map editor"
```

---

### Task 10: Runtime wiring — `StarSystem`, `GalaxyData`, `SystemLayer`, `campaign_scene.gd`

**Files:**
- Modify: `scripts\campaign\star_system.gd`
- Modify: `scripts\campaign\galaxy_data.gd`
- Modify: `scripts\campaign\system_layer.gd`
- Modify: `scripts\campaign\campaign_scene.gd`
- Test: `tests\test_galaxy_data.gd`, `tests\test_campaign_layers.gd`

**Interfaces:**
- Consumes: `StarfieldAssignment.pick`/`base_texture_path` with an override (Task 2).
- Produces: `StarSystem.background_override: Dictionary` and `StarSystem.scenery: Array`; `SystemLayer.add_scenery(item: Dictionary) -> Sprite2D`; `campaign_scene.gd`'s `_build_layers()` adds scenery after stations, and `show_system()` threads the current system's `background_override` into its existing `StarfieldAssignment` call.

- [ ] **Step 1: Write the failing tests**

In `tests\test_galaxy_data.gd`, extend `_check_optional_keys` (or add a sibling `_check_background_and_scenery` called from `run()`):

```gdscript
static func _check_background_and_scenery(failures: Array[String]) -> void:
	var with_both := GalaxyData._make_system({"id": "z", "name": "Z", "map": [0.0, 0.0],
		"background": {"category": "dense", "seed": 2},
		"scenery": [{"type": "planet", "texture": "planet_gas_purple.png", "pos": [100.0, 100.0], "scale": 3.0, "layer": "foreground"}]})
	if with_both.background_override != {"category": "dense", "seed": 2}:
		failures.append("background: expected the override carried onto StarSystem, got %s" % [with_both.background_override])
	if with_both.scenery.size() != 1 or with_both.scenery[0]["texture"] != "planet_gas_purple.png":
		failures.append("scenery: expected one planet carried onto StarSystem, got %s" % [with_both.scenery])
	var without := GalaxyData._make_system({"id": "y2", "name": "Y2", "map": [0.0, 0.0]})
	if not without.background_override.is_empty() or not without.scenery.is_empty():
		failures.append("background/scenery: expected empty defaults when absent, got %s / %s" % [without.background_override, without.scenery])
```

Call it from `run()`.

In `tests\test_campaign_layers.gd`, add a new check (needs a system with scenery in the live galaxy; since `data/galaxy.json` won't have any yet, build a standalone scene against a hand-made doc instead of the real `CampaignState.new_game()` flow used elsewhere in that file — simplest is a focused unit check on `SystemLayer` directly, not the full scene):

Create a small addition to `tests\test_campaign_layers.gd`'s `run_async`:

```gdscript
static func _check_scenery_layering(tree: SceneTree, campaign_state, failures: Array[String]) -> void:
	var layer := SystemLayer.new()
	tree.root.add_child(layer)
	var behind := layer.add_scenery({"type": "planet", "texture": "planet_gas_purple.png", "pos": [100.0, 100.0], "scale": 3.0, "layer": "mid_distance"})
	var front := layer.add_scenery({"type": "asteroid", "texture": "v1_round_a.png", "pos": [200.0, 200.0], "scale": 1.5, "layer": "foreground"})
	if behind == null or front == null:
		failures.append("scenery layering: expected both sprites created")
	elif behind.position != Vector2(100.0, 100.0) or front.position != Vector2(200.0, 200.0):
		failures.append("scenery layering: expected sprites at their recipe position, got %s / %s" % [behind.position, front.position])
	elif layer.get_children().find(front) <= layer.get_children().find(behind):
		failures.append("scenery layering: expected the foreground sprite added after the mid_distance one")
	layer.queue_free()
	await tree.process_frame
```

Call `await _check_scenery_layering(tree, campaign_state, failures)` from `run_async`, alongside the other `await _check_*` calls.

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `StarSystem` has no `background_override`/`scenery`, `SystemLayer` has no `add_scenery`.

- [ ] **Step 3: Implement the runtime wiring**

`scripts\campaign\star_system.gd` — add two fields:

```gdscript
# Explicit {"category", "seed"} background override from the editor; empty means fall back
# to StarfieldAssignment's hash, exactly as before this field existed.
@export var background_override: Dictionary = {}
# Hand-placed or randomized planets/asteroids: {"type", "texture", "pos", "scale", "layer"}.
@export var scenery: Array = []
```

`scripts\campaign\galaxy_data.gd` — extend `_make_system`:

```gdscript
static func _make_system(entry: Dictionary) -> StarSystem:
	var sys := StarSystem.new()
	sys.id = entry["id"]
	sys.display_name = entry["name"]
	sys.map_position = Vector2(entry["map"][0], entry["map"][1])
	sys.tier_override = int(entry.get("tier", 0))
	sys.background_override = entry.get("background", {})
	sys.scenery = entry.get("scenery", [])
	return sys
```

`scripts\campaign\system_layer.gd` — add `add_scenery`:

```gdscript
const FOLDER_BY_TYPE := {"planet": "planets", "asteroid": "asteroids"}
# Layers at or before this draw before stations; later ones draw in front, matching the real
# asset names (deep_background, mid_distance draw behind; foreground draws in front).
const BEHIND_STATION_LAYERS := ["deep_background", "mid_distance"]

func add_scenery(item: Dictionary) -> Sprite2D:
	var folder: String = FOLDER_BY_TYPE.get(item.get("type", ""), "")
	var path := "res://assets/sprites/backgrounds/%s/%s" % [folder, item.get("texture", "")]
	var sprite := Sprite2D.new()
	if folder != "" and ResourceLoader.exists(path):
		sprite.texture = load(path)
	sprite.position = Vector2(item["pos"][0], item["pos"][1])
	sprite.scale = Vector2.ONE * float(item.get("scale", 1.0))
	if BEHIND_STATION_LAYERS.has(item.get("layer", "")):
		add_child(sprite)
		move_child(sprite, 0)
	else:
		add_child(sprite)
	return sprite
```

(The `move_child(sprite, 0)` keeps "behind" scenery as the layer's first child, so anything added after — stations, in `_build_layers()` — draws on top; "foreground" scenery is simply appended last, after stations are already children.)

`scripts\campaign\campaign_scene.gd` — in `_build_layers()`, after the existing station loop, add scenery for every system, and update `show_system()`:

```gdscript
func _build_layers() -> void:
	var ids: Array = CampaignState.galaxy.systems.keys()
	ids.sort()
	for system_id in ids:
		var layer := SystemLayer.new()
		layer.name = system_id
		layer.system_id = system_id
		add_child(layer)
		layers[system_id] = layer
	for station in CampaignState.galaxy.stations:
		station_nodes[station.id] = layer_for(station.system_id).add_station(station)
	for system_id in ids:
		var sys: StarSystem = CampaignState.galaxy.systems[system_id]
		for item in sys.scenery:
			layer_for(system_id).add_scenery(item)

func show_system(system_id: String) -> void:
	var ids: Array = layers.keys()
	ids.sort()
	for i in ids.size():
		layers[ids[i]].set_current(ids[i] == system_id, Vector2(SYSTEM_SPACING * (i + 1), 0))
	var sys: StarSystem = CampaignState.galaxy.systems[system_id]
	$Background.texture = load(StarfieldAssignment.base_texture_path(system_id, StarfieldAssignment.SYSTEM_CATEGORIES, sys.background_override))
```

(The scenery loop runs after all stations exist, satisfying "foreground scenery draws in front of stations" — each foreground item is appended as the layer's last child at that point, after that system's stations were already added earlier in the same function.)

- [ ] **Step 4: Run tests to verify they pass**

Run the same command as Step 2.
Expected: PASS. Then run the **full** suite once more to confirm nothing else regressed:

Run: `godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.`, 0 `SCRIPT ERROR`.

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/star_system.gd scripts/campaign/galaxy_data.gd scripts/campaign/system_layer.gd scripts/campaign/campaign_scene.gd tests/test_galaxy_data.gd tests/test_campaign_layers.gd
git commit -m "Render per-system background override and scenery in the campaign view"
```

---

### Task 11: Asset-existence coverage and a real screenshot

**Files:**
- Modify: `tests\test_galaxy_data.gd`
- Verify only: no code changes beyond the test

**Interfaces:**
- Consumes: `StationData.texture_path()`-style existence checking, extended to scenery.

- [ ] **Step 1: Write the failing test**

In `tests\test_galaxy_data.gd`, extend `_check_background_and_scenery` (from Task 10) or add a sibling check that walks every system actually in `data/galaxy.json` via `GalaxyData.build()`'s result, checking any `scenery` entries that exist resolve to a real file:

```gdscript
static func _check_scenery_assets_exist(failures: Array[String]) -> void:
	var doc := GalaxyDocument.load_file()
	if not doc["ok"]:
		failures.append("scenery assets: could not load galaxy.json: %s" % doc["error"])
		return
	var folder_by_type := {"planet": "planets", "asteroid": "asteroids"}
	for sys in doc["doc"]["systems"]:
		for item in sys.get("scenery", []):
			var folder: String = folder_by_type.get(item.get("type", ""), "")
			var path := "res://assets/sprites/backgrounds/%s/%s" % [folder, item.get("texture", "")]
			if folder == "" or not ResourceLoader.exists(path):
				failures.append("scenery assets: system %s has a missing texture %s" % [sys["id"], path])
```

Call it from `run()`. Since `data/galaxy.json` has no `scenery` yet, this passes trivially today — it exists so that once any system gets scenery (by hand or via the editor's Randomize), a bad texture name fails the suite immediately, same spirit as the existing station-art check right above it in the file.

- [ ] **Step 2: Run test to verify it passes immediately (no systems have scenery yet)**

Run: `godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`
Expected: PASS (vacuously, until a system actually has scenery).

- [ ] **Step 3: Manual verification — run the editor and take screenshots**

Run `tools\map_editor.bat`. In the running editor:
1. Open the System tab, select a system with stations (e.g. `haven`), switch to the Stations sub-tab, drag a station, confirm its position updates (cross-check against the numeric pos field in the Station editor on another system selection).
2. Switch to the Scenery sub-tab, pick a background category/seed, place a planet and an asteroid from the thumbnail browser, drag them, click Randomize, confirm the canvas updates and the dashed viewport outline is visible.
3. Save. Confirm `data/galaxy.json` now has `background`/`scenery` keys on that system.
4. Take a screenshot of the Scenery sub-tab with real placements (per `godot_notes.md`'s existing screenshot verification pattern for this project).
5. Launch the actual campaign scene (not the editor) at that system and take a screenshot confirming the placed planet/asteroid render with the chosen background, matching what the editor showed.
6. Revert `data/galaxy.json` to its prior state with `git checkout -- data/galaxy.json` afterward, since this was manual exploration, not a deliberate galaxy change — unless the user wants this run's placements to stick, in which case leave it and mention it when reporting completion.

- [ ] **Step 4: Run the full suite one final time**

Run: `godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.`, 0 `SCRIPT ERROR`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_galaxy_data.gd
git commit -m "Add scenery asset-existence coverage"
```

---

## Self-review notes (already applied above)

- **Spec coverage:** System tab with Stations/Scenery sub-tabs (Task 9), background category+seed override (Tasks 2, 5, 8, 10), hand-placed scenery with layer/scale/delete (Tasks 5, 7, 8), Randomize replacing wholesale with same-type overlap avoidance (Tasks 4, 5), asset-folder browser generalized for future folders (Task 3), live campaign rendering with draw-order-only layers and no camera panning (Task 10), round-trip data model (Task 1), asset-existence safety net (Task 11) — every goal in the design doc maps to a task.
- **Type consistency:** `scenery` entries are always `{"type", "texture", "pos": [x, y], "scale", "layer"}` across `GalaxyDocument`, `MapEditModel`, `SceneryRandomizer`, `SceneryCanvas`, `SceneryEditor`, `StarSystem`, and `SystemLayer` — checked every task's code against this shape while writing it.
- **No placeholders:** every step above has real code or a real shell command; the one draft/discard note in Task 6 explains exactly what to keep and what to drop rather than leaving two conflicting tests in the file.
