# Systems and Stations Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Systems & Stations" menu that remembers what the player saw at every station they've
docked at, and lets them browse it: a tree of visited systems on the left, one station's remembered
detail (population, wealth, reputation, produces/consumes market tables) on the right.

**Architecture:** `CampaignState` gains a game-day counter and a per-station snapshot taken at the same
moment it already snapshots per-system jump-map data (`record_visit`). A new `SystemsStationsPanel`
Control (same full-screen-modal pattern as `JumpMapPanel`/`FleetManagementPanel`) reads that snapshot
data and renders the tree + detail panel, rebuilding its rows from Dictionaries like
`FleetManagementPanel` does. A new HUD button on `FleetStatusBar` opens it, wired in `campaign_scene.gd`
exactly like the existing Fleet/Jump buttons (pause on open, modal-exclusive with the other full panels).

**Tech Stack:** Godot 4.7, GDScript.

## Global Constraints

- Godot 4.7, GDScript, tabs, CRLF in the working tree. Patch `.gd` files with Python `newline=''`web
  if using a script; manual edits via an editor that preserves CRLF are fine. Never use `sed -i` on
  `.gd` files (strips CRLF).
- Implement directly on `main`. Do not push.
- UI follows `assets\ui\theme.tres` (no custom theme resources needed for this feature — it only uses
  stock `Control`/`Button`/`Label`/`VBoxContainer`/`HBoxContainer`/`ScrollContainer`/`Panel` nodes,
  which already pick up the project theme).
- Any panel drawn over the play area keeps its `Background` `Panel` node's `mouse_filter` at the
  default `MOUSE_FILTER_STOP` (do not override it) so clicks don't fall through to world input.
- No save games exist yet; the new state (`game_day`, `station_snapshots`) lives only in the running
  `CampaignState`, same as `visited`/`last_seen` today.
- Tests: run via `& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`, redirected to a log file (the
  non-console exe drops stdout otherwise). A clean suite is the known `test_campaign_long_run_sim.gd`
  pirate-targeting flake only, with zero `SCRIPT ERROR` lines.
- Panels that bare-reference the `CampaignState`/other autoloads must be registered in
  `tests\run_tests.gd` with `load()`, not `preload()` (see the comments already in that file).

---

### Task 1: Game-day counter and per-station snapshots in CampaignState

**Files:**
- Modify: `scripts\campaign\campaign_state.gd`
- Test: `tests\test_campaign_station_snapshots.gd` (new)
- Modify: `tests\run_tests.gd`

**Interfaces:**
- Produces:
  - `CampaignState.game_day() -> int` — whole days of unpaused play elapsed since `new_game()`/`reset()`.
  - `CampaignState.station_snapshots: Dictionary` — `station_id: String -> Dictionary`, written by
    `record_visit()`. Each value has exactly these keys:
    - `"day": int` — `game_day()` at the moment of the snapshot.
    - `"population": float`, `"population_trend": int` (-1/0/1) — copied from `BaseEconomy`.
    - `"wealth_level": int` — a `BaseEconomy.WealthLevel` value.
    - `"reputation"` — `float` when the station's owner has a `PowerFaction`, otherwise `null`.
    - `"produces": Array[Dictionary]`, `"consumes": Array[Dictionary]` — each row is
      `{"commodity": int, "stock": float, "buy": int, "sell": int}`, in `Commodity.Type` order,
      split by the sign of `BaseEconomy.net_commodities()[commodity]` (zero-net commodities appear in
      neither list).

**Step 1: Write the failing test**

Create `tests\test_campaign_station_snapshots.gd`:

```gdscript
extends RefCounted

const CampaignStateScript = preload("res://scripts/campaign/campaign_state.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	# Day counter: starts at 0, advances with unpaused time, resets with reset().
	var state := CampaignStateScript.new()
	if state.game_day() != 0:
		failures.append("game_day: expected 0 before any time has passed, got %d" % state.game_day())
	state.tick_economy(CampaignStateScript.DAY_LENGTH_SECONDS * 2.5)
	if state.game_day() != 2:
		failures.append("game_day: expected 2 after 2.5 day-lengths, got %d" % state.game_day())
	state.reset()
	if state.game_day() != 0:
		failures.append("game_day: expected reset() to clear the day counter, got %d" % state.game_day())

	# Station snapshot: taken by record_visit(), reflects the economy at that moment.
	var snap_state := CampaignStateScript.new()
	snap_state.new_game()
	var home := snap_state.galaxy.home_station()
	if not snap_state.station_snapshots.has(home.id):
		failures.append("snapshot: expected new_game() to snapshot the home station via record_visit()")
	var snapshot: Dictionary = snap_state.station_snapshots.get(home.id, {})
	if snapshot.get("day") != 0:
		failures.append("snapshot: expected day 0 at new game, got %s" % snapshot.get("day"))
	if snapshot.get("population") != home.economy.population:
		failures.append("snapshot: expected population copied from the economy")
	if snapshot.get("wealth_level") != home.economy.wealth_level():
		failures.append("snapshot: expected wealth_level copied from the economy")
	var expected_reputation = null
	var home_faction := snap_state.power_faction_for(home.owner)
	if home_faction != null:
		expected_reputation = home_faction.reputation
	if snapshot.get("reputation") != expected_reputation:
		failures.append("snapshot: expected reputation %s, got %s" % [expected_reputation, snapshot.get("reputation")])
	var net := home.economy.net_commodities()
	for row in snapshot.get("produces", []):
		if net.get(row["commodity"], 0.0) <= 0.0:
			failures.append("snapshot: '%s' in produces but net is %.2f" % [Commodity.NAMES[row["commodity"]], net.get(row["commodity"], 0.0)])
		if row["stock"] != home.economy.stock.get(row["commodity"], 0.0):
			failures.append("snapshot: produces row stock mismatch for %s" % Commodity.NAMES[row["commodity"]])
		if row["buy"] != home.economy.price_for(row["commodity"]):
			failures.append("snapshot: produces row buy price mismatch for %s" % Commodity.NAMES[row["commodity"]])
		if row["sell"] != home.economy.sell_price_for(row["commodity"]):
			failures.append("snapshot: produces row sell price mismatch for %s" % Commodity.NAMES[row["commodity"]])
	for row in snapshot.get("consumes", []):
		if net.get(row["commodity"], 0.0) >= 0.0:
			failures.append("snapshot: '%s' in consumes but net is %.2f" % [Commodity.NAMES[row["commodity"]], net.get(row["commodity"], 0.0)])
	var seen_commodities := []
	for row in snapshot.get("produces", []) + snapshot.get("consumes", []):
		seen_commodities.append(row["commodity"])
	var sorted_seen := seen_commodities.duplicate()
	sorted_seen.sort()
	if seen_commodities != sorted_seen:
		failures.append("snapshot: expected rows in Commodity.Type order, got %s" % [seen_commodities])

	# Re-visiting updates the snapshot (day advances, new economy numbers win).
	snap_state.tick_economy(CampaignStateScript.DAY_LENGTH_SECONDS * 3.0)
	home.economy.population = 999.0
	snap_state.record_visit(home.system_id)
	var refreshed: Dictionary = snap_state.station_snapshots[home.id]
	if refreshed.get("day") != 3 or refreshed.get("population") != 999.0:
		failures.append("snapshot: expected re-visiting to refresh day and population, got %s" % refreshed)

	snap_state.reset()
	return failures
```

- [ ] Add the test file above.

**Step 2: Register the test and run it to verify it fails**

Open `tests\run_tests.gd` and add `preload("res://tests/test_campaign_station_snapshots.gd"),` to the
`test_scripts` array, immediately after the existing
`preload("res://tests/test_campaign_start_stock.gd"),` line (around line 51) — same registration style,
since this is a synchronous `CampaignState.new()`-based test like that one.

Run: `& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd *> C:\Users\corbi\Desktop\SpaceGame\test_log.txt; Get-Content C:\Users\corbi\Desktop\SpaceGame\test_log.txt | Select-String "test_campaign_station_snapshots|SCRIPT ERROR"`

Expected: `FAIL [res://tests/test_campaign_station_snapshots.gd]: ...` lines (the API doesn't exist yet —
`game_day`, `station_snapshots`, `DAY_LENGTH_SECONDS` are all undefined, so this is actually expected
to hit a `SCRIPT ERROR` / parse failure rather than a clean FAIL list; confirm it fails for that reason,
not because the harness itself is broken).

- [ ] Run and confirm the expected failure.

**Step 3: Implement the day counter and station snapshot in CampaignState**

In `scripts\campaign\campaign_state.gd`, add a new constant near `ECONOMY_TICK_INTERVAL` (line 16):

```gdscript
const ECONOMY_TICK_INTERVAL := 5.0
# One game-day of unpaused play, for the Systems & Stations menu's "Visited: Day N" display.
const DAY_LENGTH_SECONDS := 60.0
```

Add a new var next to `_economy_tick_elapsed` (line 63):

```gdscript
var _economy_tick_elapsed: float = 0.0
var _day_elapsed: float = 0.0
```

Add a new var next to `last_seen` (line 60), for the per-station data the menu reads:

```gdscript
# station_id -> {"day", "population", "population_trend", "wealth_level", "reputation",
# "produces", "consumes"} at the last visit. See CampaignState.record_visit / _snapshot_station.
var station_snapshots: Dictionary = {}
```

Add `game_day()` right after `record_visit` (after line 226, before `jump_block_reason`):

```gdscript
func game_day() -> int:
	return floori(_day_elapsed / DAY_LENGTH_SECONDS)
```

Extend `record_visit` (lines 210-226) to also snapshot every station in the system:

```gdscript
# The snapshot is what the jump map shows for this system until the next visit.
func record_visit(system_id: String) -> void:
	var sys: StarSystem = galaxy.system(system_id) if galaxy != null else null
	if sys == null:
		return
	visited[system_id] = true
	discovered[system_id] = true
	for neighbour in sys.links:
		discovered[neighbour] = true
	var owners: Array = []
	for station in galaxy.stations_in(system_id):
		owners.append(station.owner)
		station_snapshots[station.id] = _snapshot_station(station)
	var pirates_seen := false
	for fleet in enemy_fleets:
		if fleet.system_id == system_id and fleet.faction == CampaignFleet.Faction.PIRATE:
			pirates_seen = true
			break
	last_seen[system_id] = {"owners": owners, "stations": owners.size(), "pirates_seen": pirates_seen, "tier": sys.tier}

# What the Systems & Stations menu shows for this station until the next visit.
func _snapshot_station(station: StationData) -> Dictionary:
	var economy: BaseEconomy = station.economy
	var net := economy.net_commodities()
	var produces: Array[Dictionary] = []
	var consumes: Array[Dictionary] = []
	for commodity in Commodity.Type.values():
		var amount: float = net.get(commodity, 0.0)
		if is_equal_approx(amount, 0.0):
			continue
		var row := {
			"commodity": commodity,
			"stock": economy.stock.get(commodity, 0.0),
			"buy": economy.price_for(commodity),
			"sell": economy.sell_price_for(commodity),
		}
		if amount > 0.0:
			produces.append(row)
		else:
			consumes.append(row)
	var faction := power_faction_for(station.owner)
	return {
		"day": game_day(),
		"population": economy.population,
		"population_trend": economy.population_trend,
		"wealth_level": economy.wealth_level(),
		"reputation": faction.reputation if faction != null else null,
		"produces": produces,
		"consumes": consumes,
	}
```

Hook the day counter into `tick_economy` (lines 430-444), by accumulating `delta` at the top:

```gdscript
func tick_economy(delta: float) -> void:
	_day_elapsed += delta
	_economy_tick_elapsed += delta
	while _economy_tick_elapsed >= ECONOMY_TICK_INTERVAL:
		_economy_tick_elapsed -= ECONOMY_TICK_INTERVAL
		pay_wages()
		if galaxy != null:
			for station in galaxy.stations:
				if station.economy != null:
					station.economy.tick()
					if _is_power_faction(station.owner):
						_apply_station_allocation(station)
				_tick_station_respawns(station, ECONOMY_TICK_INTERVAL)
		_refuel_npcs()
		_repair_npcs_at_home()
		_refill_npc_crew()
```

Clear both new fields in `reset()` (lines 166-182), alongside the existing `last_seen = {}`:

```gdscript
	discovered = {}
	visited = {}
	last_seen = {}
	station_snapshots = {}
	_economy_tick_elapsed = 0.0
	_day_elapsed = 0.0
```

- [ ] Make the edits above.

**Step 4: Run the test to verify it passes**

Run: `& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd *> C:\Users\corbi\Desktop\SpaceGame\test_log.txt; Get-Content C:\Users\corbi\Desktop\SpaceGame\test_log.txt | Select-String "FAIL|SCRIPT ERROR|All tests passed"`

Expected: no `FAIL [res://tests/test_campaign_station_snapshots.gd]` lines, no new `SCRIPT ERROR` lines,
and the only `FAIL` lines (if any) belong to the known `test_campaign_long_run_sim.gd` flake.

- [ ] Run and confirm.

**Step 5: Commit**

```bash
git add scripts/campaign/campaign_state.gd tests/test_campaign_station_snapshots.gd tests/run_tests.gd
git commit -m "Add a game-day counter and per-station visit snapshots to CampaignState"
```

- [ ] Commit.

---

### Task 2: SystemsStationsPanel (tree + detail panel, standalone)

**Files:**
- Create: `scenes\ui\systems_stations_panel.tscn`
- Create: `scripts\ui\systems_stations_panel.gd`
- Test: `tests\test_systems_stations_panel.gd` (new)
- Modify: `tests\run_tests.gd`

**Interfaces:**
- Consumes (from Task 1): `CampaignState.station_snapshots: Dictionary`, `CampaignState.game_day() ->
  int`, `CampaignState.visited: Dictionary`, `CampaignState.galaxy: Galaxy`
  (`Galaxy.system(id)->StarSystem`, `Galaxy.stations_in(id)->Array[StationData]`,
  `Galaxy.station(id)->StationData`), `CampaignState.power_faction_for(owner) -> PowerFaction`.
- Produces (for Task 3): a `Control`-derived `SystemsStationsPanel` class (`class_name
  SystemsStationsPanel`) with:
  - `func open_for(state: Node) -> void`
  - `func close() -> void`
  - `func refresh() -> void`
  - `func toggle_system(system_id: String) -> void`
  - `func select_station(station_id: String) -> void`
  - `func selected_station() -> String`
  - `func sort_table(table_key: String, column: int) -> void`
  - `@onready var close_button: Button`

**Step 1: Write the failing test**

Create `tests\test_systems_stations_panel.gd`:

```gdscript
extends RefCounted

const SystemsStationsPanelScene = preload("res://scenes/ui/systems_stations_panel.tscn")
const UiLayoutCheck = preload("res://tests/ui_layout_check.gd")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.new_game()

	var panel = SystemsStationsPanelScene.instantiate()
	tree.root.add_child(panel)
	await tree.process_frame
	if panel.visible:
		failures.append("setup: expected the panel hidden until opened")

	_check_tree(panel, campaign_state, failures)
	_check_detail(panel, campaign_state, failures)
	await _check_sorting(tree, panel, campaign_state, failures)
	await _check_layout(tree, panel, campaign_state, failures)

	panel.queue_free()
	await tree.process_frame
	campaign_state.reset()
	return failures

static func _check_tree(panel, campaign_state, failures: Array[String]) -> void:
	panel.open_for(campaign_state)
	if not panel.visible:
		failures.append("tree: expected open_for to show the panel")
	if panel.count_label.text != "%d LOGGED" % campaign_state.visited.size():
		failures.append("tree: expected the count label to show %d, got '%s'" % [campaign_state.visited.size(), panel.count_label.text])
	var home_id: String = campaign_state.player_fleet.system_id
	var stations: Array[StationData] = campaign_state.galaxy.stations_in(home_id)
	# new_game() only ever visits the home system, so exactly one system row exists, collapsed.
	if panel.tree_container.get_child_count() != 1:
		failures.append("tree: expected exactly 1 visited system row at new game, got %d" % panel.tree_container.get_child_count())
	panel.toggle_system(home_id)
	var expanded_count := 1 + stations.size()
	if panel.tree_container.get_child_count() != expanded_count:
		failures.append("tree: expected %d rows (system + %d stations) after expanding, got %d" % [expanded_count, stations.size(), panel.tree_container.get_child_count()])
	panel.toggle_system(home_id)
	if panel.tree_container.get_child_count() != 1:
		failures.append("tree: expected the station rows to collapse again")

static func _check_detail(panel, campaign_state, failures: Array[String]) -> void:
	var home_id: String = campaign_state.player_fleet.system_id
	var station: StationData = campaign_state.galaxy.stations_in(home_id)[0]
	panel.select_station(station.id)
	if panel.selected_station() != station.id:
		failures.append("detail: expected select_station to select '%s', got '%s'" % [station.id, panel.selected_station()])
	if panel.name_label.text != station.display_name.to_upper():
		failures.append("detail: expected name label '%s', got '%s'" % [station.display_name.to_upper(), panel.name_label.text])
	var sys: StarSystem = campaign_state.galaxy.system(home_id)
	if panel.system_label.text != "System: %s" % sys.display_name:
		failures.append("detail: expected system label 'System: %s', got '%s'" % [sys.display_name, panel.system_label.text])
	var snapshot: Dictionary = campaign_state.station_snapshots[station.id]
	var days_ago: int = campaign_state.game_day() - snapshot["day"]
	var expected_visited := "Visited: Day %d (%d days ago)" % [snapshot["day"], days_ago]
	if panel.visited_label.text != expected_visited:
		failures.append("detail: expected '%s', got '%s'" % [expected_visited, panel.visited_label.text])
	var faction := campaign_state.power_faction_for(station.owner)
	var expected_badge: String = (faction.display_name if faction != null else CampaignFleet.Faction.keys()[station.owner].capitalize()).to_upper()
	if panel.badge_label.text != expected_badge:
		failures.append("detail: expected badge '%s', got '%s'" % [expected_badge, panel.badge_label.text])
	var produces_rows := panel.produces_table_container.get_child_count() - 1
	if produces_rows != snapshot["produces"].size():
		failures.append("detail: expected %d produces rows, got %d" % [snapshot["produces"].size(), produces_rows])
	var consumes_rows := panel.consumes_table_container.get_child_count() - 1
	if consumes_rows != snapshot["consumes"].size():
		failures.append("detail: expected %d consumes rows, got %d" % [snapshot["consumes"].size(), consumes_rows])

static func _check_sorting(tree: SceneTree, panel, campaign_state, failures: Array[String]) -> void:
	for id in campaign_state.galaxy.systems:
		campaign_state.record_visit(id)
	var target_id := ""
	for sid in campaign_state.station_snapshots:
		if campaign_state.station_snapshots[sid]["produces"].size() >= 2:
			target_id = sid
			break
	if target_id == "":
		failures.append("sort: expected at least one station with 2+ produced commodities in the galaxy")
		return
	panel.select_station(target_id)
	var produces: Array = campaign_state.station_snapshots[target_id]["produces"]
	panel.sort_table("produces", 1)
	var ascending_names := _row_commodity_names(panel.produces_table_container)
	var expected_asc := produces.duplicate()
	expected_asc.sort_custom(func(a, b): return (a["stock"] - Commodity.TARGET_STOCK[a["commodity"]]) < (b["stock"] - Commodity.TARGET_STOCK[b["commodity"]]))
	var expected_asc_names: Array[String] = []
	for row in expected_asc:
		expected_asc_names.append(Commodity.NAMES[row["commodity"]])
	if ascending_names != expected_asc_names:
		failures.append("sort: expected produces ascending by stock %s, got %s" % [expected_asc_names, ascending_names])
	panel.sort_table("produces", 1)
	var descending_names := _row_commodity_names(panel.produces_table_container)
	expected_asc_names.reverse()
	if descending_names != expected_asc_names:
		failures.append("sort: expected produces descending by stock %s, got %s" % [expected_asc_names, descending_names])
	await tree.process_frame

static func _row_commodity_names(table_container: VBoxContainer) -> Array[String]:
	var names: Array[String] = []
	var children := table_container.get_children()
	for i in range(1, children.size()):
		var row: HBoxContainer = children[i]
		names.append((row.get_child(0) as Label).text)
	return names

static func _check_layout(tree: SceneTree, panel, campaign_state, failures: Array[String]) -> void:
	var home_id: String = campaign_state.player_fleet.system_id
	panel.toggle_system(home_id)
	panel.select_station(campaign_state.galaxy.stations_in(home_id)[0].id)
	await tree.process_frame
	UiLayoutCheck.check_panel_layout(panel, failures)
	if panel.get_node("Background").mouse_filter != Control.MOUSE_FILTER_STOP:
		failures.append("layout: expected the Background to stop clicks reaching the world below")
```

- [ ] Add the test file above.

**Step 2: Register the test and run it to verify it fails**

In `tests\run_tests.gd`, add this block after the `jump_map_panel_test` block (around line 197, right
before `campaign_galaxy_state_test`):

```gdscript
	var systems_stations_panel_test = load("res://tests/test_systems_stations_panel.gd")
	var systems_stations_panel_failures: Array[String] = await systems_stations_panel_test.run_async(self)
	for f in systems_stations_panel_failures:
		print("FAIL [%s]: %s" % [systems_stations_panel_test.resource_path, f])
	total_failures += systems_stations_panel_failures.size()
```

Run: `& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd *> C:\Users\corbi\Desktop\SpaceGame\test_log.txt; Get-Content C:\Users\corbi\Desktop\SpaceGame\test_log.txt | Select-String "systems_stations|SCRIPT ERROR"`

Expected: a failure to load `res://scenes/ui/systems_stations_panel.tscn` (it doesn't exist yet).

- [ ] Run and confirm the expected failure.

**Step 3: Build the scene**

Create `scenes\ui\systems_stations_panel.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/systems_stations_panel.gd" id="1"]

[node name="SystemsStationsPanel" type="Control"]
offset_left = 10.0
offset_top = 80.0
offset_right = 1142.0
offset_bottom = 638.0
mouse_filter = 2
script = ExtResource("1")

[node name="Background" type="Panel" parent="."]
offset_right = 1132.0
offset_bottom = 558.0

[node name="TopBar" type="HBoxContainer" parent="."]
offset_left = 14.0
offset_top = 10.0
offset_right = 1118.0
offset_bottom = 34.0
mouse_filter = 2

[node name="TitleLabel" type="Label" parent="TopBar"]
text = "SYSTEMS & STATIONS"

[node name="Spacer" type="Control" parent="TopBar"]
size_flags_horizontal = 3
mouse_filter = 2

[node name="CountLabel" type="Label" parent="TopBar"]
text = "0 LOGGED"

[node name="CloseButton" type="Button" parent="TopBar"]
text = "Close"

[node name="Body" type="HBoxContainer" parent="."]
offset_left = 14.0
offset_top = 40.0
offset_right = 1118.0
offset_bottom = 544.0
mouse_filter = 2

[node name="TreeScroll" type="ScrollContainer" parent="Body"]
custom_minimum_size = Vector2(350, 0)

[node name="TreeContainer" type="VBoxContainer" parent="Body/TreeScroll"]
size_flags_horizontal = 3

[node name="DetailScroll" type="ScrollContainer" parent="Body"]
size_flags_horizontal = 3

[node name="DetailContainer" type="VBoxContainer" parent="Body/DetailScroll"]
size_flags_horizontal = 3

[node name="Header" type="HBoxContainer" parent="Body/DetailScroll/DetailContainer"]

[node name="NameBox" type="VBoxContainer" parent="Body/DetailScroll/DetailContainer/Header"]

[node name="NameLabel" type="Label" parent="Body/DetailScroll/DetailContainer/Header/NameBox"]
text = "STATION"

[node name="SystemLabel" type="Label" parent="Body/DetailScroll/DetailContainer/Header/NameBox"]
text = "System: "

[node name="HeaderSpacer" type="Control" parent="Body/DetailScroll/DetailContainer/Header"]
size_flags_horizontal = 3

[node name="BadgeBox" type="VBoxContainer" parent="Body/DetailScroll/DetailContainer/Header"]

[node name="BadgeLabel" type="Label" parent="Body/DetailScroll/DetailContainer/Header/BadgeBox"]
text = ""
horizontal_alignment = 2

[node name="VisitedLabel" type="Label" parent="Body/DetailScroll/DetailContainer/Header/BadgeBox"]
text = ""
horizontal_alignment = 2

[node name="Tiles" type="HBoxContainer" parent="Body/DetailScroll/DetailContainer"]
theme_override_constants/separation = 12

[node name="PopulationTile" type="VBoxContainer" parent="Body/DetailScroll/DetailContainer/Tiles"]

[node name="PopulationKeyLabel" type="Label" parent="Body/DetailScroll/DetailContainer/Tiles/PopulationTile"]
text = "POPULATION"

[node name="PopulationValueLabel" type="Label" parent="Body/DetailScroll/DetailContainer/Tiles/PopulationTile"]
text = "0"

[node name="WealthTile" type="VBoxContainer" parent="Body/DetailScroll/DetailContainer/Tiles"]

[node name="WealthKeyLabel" type="Label" parent="Body/DetailScroll/DetailContainer/Tiles/WealthTile"]
text = "WEALTH"

[node name="WealthValueLabel" type="Label" parent="Body/DetailScroll/DetailContainer/Tiles/WealthTile"]
text = ""

[node name="ReputationTile" type="VBoxContainer" parent="Body/DetailScroll/DetailContainer/Tiles"]

[node name="ReputationKeyLabel" type="Label" parent="Body/DetailScroll/DetailContainer/Tiles/ReputationTile"]
text = "REPUTATION"

[node name="ReputationValueLabel" type="Label" parent="Body/DetailScroll/DetailContainer/Tiles/ReputationTile"]
text = ""

[node name="ProducesHeader" type="Label" parent="Body/DetailScroll/DetailContainer"]
text = "PRODUCES"

[node name="ProducesTableContainer" type="VBoxContainer" parent="Body/DetailScroll/DetailContainer"]

[node name="ConsumesHeader" type="Label" parent="Body/DetailScroll/DetailContainer"]
text = "CONSUMES"

[node name="ConsumesTableContainer" type="VBoxContainer" parent="Body/DetailScroll/DetailContainer"]
```

- [ ] Add the scene file above.

**Step 4: Write the script**

Create `scripts\ui\systems_stations_panel.gd`:

```gdscript
class_name SystemsStationsPanel
extends Control

const SURPLUS_COLOR := Color("#5fe08a")
const DEFICIT_COLOR := Color("#ff7a6a")
const COLUMN_LABELS := ["COMMODITY", "STOCK", "BUY", "SELL"]
const COLUMN_WIDTHS := [160.0, 100.0, 100.0, 100.0]
const TOGGLE_WIDTH := 24.0

var _state: Node = null
# system_id -> bool, expanded state of the left tree.
var _expanded: Dictionary = {}
var _selected_station: String = ""
# "produces"/"consumes" -> {"sort_column": int, "ascending": bool}. -1 = unsorted.
var _table_state: Dictionary = {}

@onready var tree_container: VBoxContainer = $Body/TreeScroll/TreeContainer
@onready var count_label: Label = $TopBar/CountLabel
@onready var close_button: Button = $TopBar/CloseButton
@onready var name_label: Label = $Body/DetailScroll/DetailContainer/Header/NameBox/NameLabel
@onready var system_label: Label = $Body/DetailScroll/DetailContainer/Header/NameBox/SystemLabel
@onready var badge_label: Label = $Body/DetailScroll/DetailContainer/Header/BadgeBox/BadgeLabel
@onready var visited_label: Label = $Body/DetailScroll/DetailContainer/Header/BadgeBox/VisitedLabel
@onready var population_value_label: Label = $Body/DetailScroll/DetailContainer/Tiles/PopulationTile/PopulationValueLabel
@onready var wealth_value_label: Label = $Body/DetailScroll/DetailContainer/Tiles/WealthTile/WealthValueLabel
@onready var reputation_value_label: Label = $Body/DetailScroll/DetailContainer/Tiles/ReputationTile/ReputationValueLabel
@onready var produces_table_container: VBoxContainer = $Body/DetailScroll/DetailContainer/ProducesTableContainer
@onready var consumes_table_container: VBoxContainer = $Body/DetailScroll/DetailContainer/ConsumesTableContainer

func _ready() -> void:
	close_button.pressed.connect(close)
	visible = false

func open_for(state: Node) -> void:
	_state = state
	_expanded = {}
	_selected_station = ""
	_reset_table_state()
	visible = true
	refresh()

func close() -> void:
	visible = false
	_state = null

func refresh() -> void:
	if _state == null:
		return
	_rebuild_tree()
	count_label.text = "%d LOGGED" % _state.visited.size()
	_refresh_detail()

func toggle_system(system_id: String) -> void:
	_expanded[system_id] = not _expanded.get(system_id, false)
	_rebuild_tree()

func select_station(station_id: String) -> void:
	_selected_station = station_id
	_reset_table_state()
	_rebuild_tree()
	_refresh_detail()

func selected_station() -> String:
	return _selected_station

func sort_table(table_key: String, column: int) -> void:
	var state: Dictionary = _table_state[table_key]
	if state["sort_column"] == column:
		state["ascending"] = not state["ascending"]
	else:
		state["sort_column"] = column
		state["ascending"] = true
	_refresh_detail()

func _reset_table_state() -> void:
	_table_state = {
		"produces": {"sort_column": -1, "ascending": true},
		"consumes": {"sort_column": -1, "ascending": true},
	}

func _rebuild_tree() -> void:
	for child in tree_container.get_children():
		tree_container.remove_child(child)
		child.queue_free()
	var system_ids: Array = _state.visited.keys()
	system_ids.sort_custom(func(a, b): return _state.galaxy.system(a).display_name < _state.galaxy.system(b).display_name)
	for system_id in system_ids:
		var sys: StarSystem = _state.galaxy.system(system_id)
		if sys == null:
			continue
		var stations: Array[StationData] = _state.galaxy.stations_in(system_id)
		tree_container.add_child(_build_system_row(sys, stations.size()))
		if _expanded.get(system_id, false):
			for station in stations:
				tree_container.add_child(_build_station_row(station))

func _build_system_row(sys: StarSystem, station_count: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	var toggle := Button.new()
	toggle.custom_minimum_size = Vector2(TOGGLE_WIDTH, 0)
	toggle.text = "-" if _expanded.get(sys.id, false) else "+"
	toggle.pressed.connect(toggle_system.bind(sys.id))
	var labels := VBoxContainer.new()
	var name := Label.new()
	name.text = sys.display_name
	var count := Label.new()
	count.text = "Stations - %d" % station_count
	labels.add_child(name)
	labels.add_child(count)
	row.add_child(toggle)
	row.add_child(labels)
	return row

func _build_station_row(station: StationData) -> HBoxContainer:
	var row := HBoxContainer.new()
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(9, 9)
	dot.color = CampaignFleetIcon.FACTION_COLORS.get(station.owner, CampaignFleetIcon.FACTION_COLORS[CampaignFleet.Faction.NEUTRAL])
	var button := Button.new()
	button.flat = true
	button.text = station.display_name
	if station.id == _selected_station:
		button.add_theme_color_override("font_color", Color.WHITE)
	button.pressed.connect(select_station.bind(station.id))
	row.add_child(dot)
	row.add_child(button)
	return row

func _refresh_detail() -> void:
	if _selected_station == "":
		name_label.text = ""
		system_label.text = "System: "
		badge_label.text = ""
		visited_label.text = ""
		population_value_label.text = "0"
		wealth_value_label.text = ""
		reputation_value_label.text = ""
		_build_table(produces_table_container, [], "produces")
		_build_table(consumes_table_container, [], "consumes")
		return
	var station: StationData = _state.galaxy.station(_selected_station)
	var snapshot: Dictionary = _state.station_snapshots.get(_selected_station, {})
	name_label.text = station.display_name.to_upper()
	system_label.text = "System: %s" % _state.galaxy.system(station.system_id).display_name
	var faction := _state.power_faction_for(station.owner)
	badge_label.text = (faction.display_name if faction != null else CampaignFleet.Faction.keys()[station.owner].capitalize()).to_upper()
	var day: int = snapshot.get("day", 0)
	var days_ago: int = _state.game_day() - day
	visited_label.text = "Visited: Day %d (%d days ago)" % [day, days_ago]
	_update_population_tile(snapshot)
	_update_wealth_tile(snapshot)
	_update_reputation_tile(snapshot)
	_build_table(produces_table_container, snapshot.get("produces", []), "produces")
	_build_table(consumes_table_container, snapshot.get("consumes", []), "consumes")

func _update_population_tile(snapshot: Dictionary) -> void:
	var population: float = snapshot.get("population", 0.0)
	var trend: int = snapshot.get("population_trend", 0)
	if trend > 0:
		population_value_label.text = "+%d" % roundi(population)
		population_value_label.add_theme_color_override("font_color", SURPLUS_COLOR)
	elif trend < 0:
		population_value_label.text = "-%d" % roundi(population)
		population_value_label.add_theme_color_override("font_color", DEFICIT_COLOR)
	else:
		population_value_label.text = "%d" % roundi(population)
		population_value_label.remove_theme_color_override("font_color")

func _update_wealth_tile(snapshot: Dictionary) -> void:
	var wealth_level: int = snapshot.get("wealth_level", BaseEconomy.WealthLevel.MIDDLING)
	wealth_value_label.text = BaseOverviewPanel.WEALTH_NAMES[wealth_level]

func _update_reputation_tile(snapshot: Dictionary) -> void:
	var reputation = snapshot.get("reputation")
	reputation_value_label.text = "-" if reputation == null else "%+d" % roundi(reputation)

func _build_table(container: VBoxContainer, rows_data: Array, table_key: String) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	var state: Dictionary = _table_state[table_key]
	var header := HBoxContainer.new()
	for i in COLUMN_LABELS.size():
		var header_button := Button.new()
		header_button.flat = true
		header_button.custom_minimum_size = Vector2(COLUMN_WIDTHS[i], 0)
		var arrow := ""
		if state["sort_column"] == i:
			arrow = " ^" if state["ascending"] else " v"
		header_button.text = COLUMN_LABELS[i] + arrow
		header_button.pressed.connect(sort_table.bind(table_key, i))
		header.add_child(header_button)
	container.add_child(header)
	for row in _sorted_rows(rows_data, state):
		container.add_child(_build_table_row(row))

func _sorted_rows(rows_data: Array, state: Dictionary) -> Array:
	var column: int = state["sort_column"]
	if column < 0:
		return rows_data.duplicate()
	var ascending: bool = state["ascending"]
	var sorted_rows: Array = rows_data.duplicate()
	sorted_rows.sort_custom(func(a, b):
		var key_a = _sort_key(a, column)
		var key_b = _sort_key(b, column)
		return key_a < key_b if ascending else key_a > key_b)
	return sorted_rows

func _sort_key(row: Dictionary, column: int):
	match column:
		0:
			return Commodity.NAMES[row["commodity"]]
		1:
			return row["stock"] - Commodity.TARGET_STOCK[row["commodity"]]
		2:
			return row["buy"]
		3:
			return row["sell"]
	return 0

func _build_table_row(row: Dictionary) -> HBoxContainer:
	var box := HBoxContainer.new()
	var commodity_label := Label.new()
	commodity_label.custom_minimum_size = Vector2(COLUMN_WIDTHS[0], 0)
	commodity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	commodity_label.text = Commodity.NAMES[row["commodity"]]
	var diff: float = row["stock"] - Commodity.TARGET_STOCK[row["commodity"]]
	var stock_label := Label.new()
	stock_label.custom_minimum_size = Vector2(COLUMN_WIDTHS[1], 0)
	stock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stock_label.text = "%+d" % roundi(diff)
	stock_label.add_theme_color_override("font_color", SURPLUS_COLOR if diff >= 0.0 else DEFICIT_COLOR)
	var buy_label := Label.new()
	buy_label.custom_minimum_size = Vector2(COLUMN_WIDTHS[2], 0)
	buy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	buy_label.text = str(row["buy"])
	var sell_label := Label.new()
	sell_label.custom_minimum_size = Vector2(COLUMN_WIDTHS[3], 0)
	sell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sell_label.text = str(row["sell"])
	for widget in [commodity_label, stock_label, buy_label, sell_label]:
		box.add_child(widget)
	return box
```

- [ ] Add the script above.

**Step 5: Run the test to verify it passes**

Run: `& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd *> C:\Users\corbi\Desktop\SpaceGame\test_log.txt; Get-Content C:\Users\corbi\Desktop\SpaceGame\test_log.txt | Select-String "FAIL|SCRIPT ERROR|All tests passed"`

Expected: no `FAIL [res://tests/test_systems_stations_panel.gd]` lines, no new `SCRIPT ERROR` lines.
If a new `class_name` isn't picked up, run one headless editor warm pass first per `godot_notes.md`:
`& "<same exe>" --headless --editor --quit --path .`

- [ ] Run and confirm.

**Step 6: Commit**

```bash
git add scenes/ui/systems_stations_panel.tscn scripts/ui/systems_stations_panel.gd tests/test_systems_stations_panel.gd tests/run_tests.gd
git commit -m "Add the Systems & Stations panel (tree of visited systems, station detail, sortable market tables)"
```

- [ ] Commit.

---

### Task 3: HUD button, campaign-scene wiring, modal exclusivity

**Files:**
- Modify: `scenes\ui\fleet_status_bar.tscn`
- Modify: `scripts\ui\fleet_status_bar.gd`
- Modify: `scenes\campaign\campaign_scene.tscn`
- Modify: `scripts\campaign\campaign_scene.gd`
- Modify: `scripts\campaign\jump_controller.gd`
- Test: `tests\test_campaign_scene_systems_stations.gd` (new)
- Modify: `tests\run_tests.gd`

**Interfaces:**
- Consumes (from Task 2): `SystemsStationsPanel.open_for(state)`, `.close()`, `.visible`,
  `.close_button`.
- Produces: nothing further consumes this; it's the final wiring task.

**Step 1: Write the failing test**

Create `tests\test_campaign_scene_systems_stations.gd`, modeled on
`tests\test_campaign_scene_fleet_panel.gd`:

```gdscript
extends RefCounted

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(scene)
	await tree.process_frame
	tree.paused = false

	var panel: SystemsStationsPanel = scene.systems_stations_panel
	var systems_button: Button = scene.fleet_status_bar.systems_button

	# (a) open pauses, close unpauses.
	systems_button.pressed.emit()
	if not panel.visible or not tree.paused:
		failures.append("(a) expected Systems to open the panel and pause, visible=%s paused=%s" % [panel.visible, tree.paused])
	panel.close_button.pressed.emit()
	if panel.visible or tree.paused:
		failures.append("(a) expected Close to hide the panel and unpause")

	# (b) a pre-existing pause survives open/close.
	tree.paused = true
	systems_button.pressed.emit()
	panel.close_button.pressed.emit()
	if not tree.paused:
		failures.append("(b) expected Close to keep a pre-existing pause")
	tree.paused = false

	# (c) the engage prompt is modal: Systems is ignored while it's up.
	scene.engage_prompt.visible = true
	systems_button.pressed.emit()
	if panel.visible:
		failures.append("(c) expected Systems to be ignored while the engage prompt is visible")
	scene.engage_prompt.visible = false

	# (d) mutual exclusion: Systems is ignored while the Fleet panel is open, and vice versa.
	scene.fleet_status_bar.fleet_button.pressed.emit()
	systems_button.pressed.emit()
	if panel.visible:
		failures.append("(d) expected Systems to be ignored while the Fleet panel is visible")
	scene.fleet_management_panel.close_button.pressed.emit()
	tree.paused = false
	systems_button.pressed.emit()
	scene.fleet_status_bar.fleet_button.pressed.emit()
	if scene.fleet_management_panel.visible:
		failures.append("(d) expected Fleet to be ignored while the Systems panel is visible")
	panel.close_button.pressed.emit()
	tree.paused = false

	campaign_state.reset()
	return failures
```

- [ ] Add the test file above.

**Step 2: Register the test and run it to verify it fails**

In `tests\run_tests.gd`, add this block after the `campaign_scene_fleet_panel_test` block (around line
315, right before `respawn_panel_test`):

```gdscript
	var campaign_scene_systems_stations_test = load("res://tests/test_campaign_scene_systems_stations.gd")
	var campaign_scene_systems_stations_failures: Array[String] = await campaign_scene_systems_stations_test.run_async(self)
	for f in campaign_scene_systems_stations_failures:
		print("FAIL [%s]: %s" % [campaign_scene_systems_stations_test.resource_path, f])
	total_failures += campaign_scene_systems_stations_failures.size()
```

Run: `& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd *> C:\Users\corbi\Desktop\SpaceGame\test_log.txt; Get-Content C:\Users\corbi\Desktop\SpaceGame\test_log.txt | Select-String "systems_stations|SCRIPT ERROR"`

Expected: a failure resolving `scene.systems_stations_panel` / `scene.fleet_status_bar.systems_button`
(neither exists yet).

- [ ] Run and confirm the expected failure.

**Step 3: Add the HUD button**

In `scenes\ui\fleet_status_bar.tscn`, add a new button after `JumpButton` (after line 52):

```
[node name="SystemsButton" type="Button" parent="Layout"]
size_flags_vertical = 4
text = "Systems"
```

In `scripts\ui\fleet_status_bar.gd`, add the `@onready` next to `jump_button` (line 11):

```gdscript
	@onready var jump_button: Button = $Layout/JumpButton
	@onready var systems_button: Button = $Layout/SystemsButton
```

- [ ] Make the edits above.

**Step 4: Add the panel node to CampaignScene**

In `scenes\campaign\campaign_scene.tscn`:
- Bump `load_steps=11` (line 1) to `load_steps=12`.
- Add a new ext_resource after `id="11"` (line 13):

```
[ext_resource type="PackedScene" path="res://scenes/ui/systems_stations_panel.tscn" id="12"]
```

- Add the node after `JumpMapPanel` (line 60):

```
[node name="SystemsStationsPanel" parent="UILayer" instance=ExtResource("12")]
```

- [ ] Make the edits above.

**Step 5: Wire it in campaign_scene.gd**

Add the `@onready` next to `jump_map_panel` (line 26):

```gdscript
	@onready var jump_map_panel: JumpMapPanel = $UILayer/JumpMapPanel
	@onready var systems_stations_panel: SystemsStationsPanel = $UILayer/SystemsStationsPanel
```

Add a new pause-tracking var next to `_paused_before_fleet_panel` (line 32):

```gdscript
	var _paused_before_fleet_panel: bool = false
	var _paused_before_systems_panel: bool = false
```

In `_ready()`, connect the button next to the Fleet button wiring (line 71):

```gdscript
	fleet_status_bar.fleet_button.pressed.connect(_open_fleet_management)
	fleet_status_bar.systems_button.pressed.connect(_open_systems_stations)
	systems_stations_panel.close_button.pressed.connect(_on_systems_stations_closed)
```

Add the open/close handlers next to `_open_fleet_management`/`_on_fleet_management_closed` (after line
357, before `_open_jump_map`):

```gdscript
func _open_systems_stations() -> void:
	# Same modal rule as Fleet/Jump: whichever full panel is open owns the pause state.
	if engage_prompt.visible or respawn_panel.visible or jump_map_panel.visible or fleet_management_panel.visible:
		return
	if not systems_stations_panel.visible:
		_paused_before_systems_panel = get_tree().paused
	systems_stations_panel.open_for(CampaignState)
	get_tree().paused = true

func _on_systems_stations_closed() -> void:
	get_tree().paused = _paused_before_systems_panel
```

Update the two existing modal-guard lists to include the new panel:
- `_open_fleet_management`'s guard (line 346):

```gdscript
	if engage_prompt.visible or respawn_panel.visible or jump_map_panel.visible or systems_stations_panel.visible:
		return
```

- `_unhandled_input`'s guard (line 405):

```gdscript
		if base_overview_panel.visible or engage_prompt.visible or fleet_management_panel.visible or respawn_panel.visible or jump_map_panel.visible or systems_stations_panel.visible:
			return
```

- [ ] Make the edits above.

**Step 6: Add the same guard to the jump map's open check**

In `scripts\campaign\jump_controller.gd`, update `open_jump_map`'s guard (line 27) so Systems and Jump
are also mutually exclusive:

```gdscript
func open_jump_map() -> void:
	if _scene.engage_prompt.visible or _scene.respawn_panel.visible or _scene.systems_stations_panel.visible:
		return
	if not _scene.jump_map_panel.visible:
		_paused_before_jump_map = _scene.get_tree().paused
	_scene.jump_map_panel.open_for(CampaignState, _scene._docked_base != null, player_hostile_contact())
	_scene.get_tree().paused = true
```

- [ ] Make the edit above.

**Step 7: Run the test to verify it passes**

Run: `& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd *> C:\Users\corbi\Desktop\SpaceGame\test_log.txt; Get-Content C:\Users\corbi\Desktop\SpaceGame\test_log.txt | Select-String "FAIL|SCRIPT ERROR|All tests passed"`

Expected: `All tests passed.` or only the known `test_campaign_long_run_sim.gd` flake lines.

- [ ] Run and confirm.

**Step 8: Manual check**

Launch the game, dock at 2-3 different stations across a couple of systems (to populate snapshots with
real variety), open the Systems button on the HUD, and confirm:
- the tree lists only visited systems, expands/collapses correctly, and station dots match faction
  colours seen elsewhere (e.g. the jump map);
- selecting a station shows its remembered population/wealth/reputation and produces/consumes tables;
- clicking a column header sorts that table only, and clicking again reverses it;
- Close returns to the previous pause state and the world is clickable again.

- [ ] Perform the manual check.

**Step 9: Commit**

```bash
git add scenes/ui/fleet_status_bar.tscn scripts/ui/fleet_status_bar.gd scenes/campaign/campaign_scene.tscn scripts/campaign/campaign_scene.gd scripts/campaign/jump_controller.gd tests/test_campaign_scene_systems_stations.gd tests/run_tests.gd
git commit -m "Open the Systems & Stations panel from the campaign HUD"
```

- [ ] Commit.
