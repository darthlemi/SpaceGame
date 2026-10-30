# Factions & Territory Scene Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the data/logic built in Plan A
(`2026-10-30-factions-territory-simulation-layer.md`) into the playable
`CampaignScene`: bootstrap two power factions with territory and
fleets, pick each power-faction fleet's behavior from its reputation, and
detect + tick NPC-vs-NPC skirmishes during normal play.

**Architecture:** `CampaignScene._bootstrap_default_campaign()` gains two
`PowerFaction` entries and their fleets/bases; `_behavior_for_faction`
looks up reputation to choose hostile-vs-ignore behavior for power
factions. A new `area_entered` connection on every non-player icon feeds
`CampaignState.start_skirmish()` when two hostile fleets meet, and
`CampaignScene._physics_process` drives `CampaignState.tick_skirmishes()`
every frame so skirmishes actually resolve during play.

**Tech Stack:** Godot 4.7, GDScript. Tests follow the existing repo
pattern (`extends RefCounted`, `run()`/`run_async(tree)` returning
`Array[String]`), registered in `tests/run_tests.gd`.

## Global Constraints

- Tabs for indentation, matching every existing `.gd` file in this repo.
- Any fleet/base position added to `CampaignScene._bootstrap_default_campaign()`
  must stay within the game's 1152×648 default viewport (no `Camera2D`
  exists in `campaign_scene.tscn`) — a prior milestone's final review
  caught off-screen bootstrap fleets as a real playability bug; don't
  reintroduce it.
- `CampaignState.are_hostile`, `start_skirmish`, `tick_skirmishes`,
  `cancel_skirmish_for`, and the `factions`/`factions_at_war` fields
  already exist from Plan A — this plan only calls them, it does not
  redefine them.
- Any test that touches the live `CampaignState` autoload must call
  `campaign_state.reset()` both before and after, per the existing
  convention in `tests/test_campaign_scene.gd` and
  `tests/test_combat_scene.gd`.

---

### Task 7: Bootstrap power factions, territory, and reputation-based behavior

**Files:**
- Modify: `scripts/campaign/campaign_scene.gd`
- Modify: `tests/test_campaign_scene.gd`

**Interfaces:**
- Consumes: `PowerFaction`, `FactionBase`, `CampaignState.factions`,
  `CampaignState.HOSTILE_REPUTATION_THRESHOLD` (all from Plan A).
- Produces: `CampaignScene._bootstrap_default_campaign()` now also
  creates two `PowerFaction` entries and their `CampaignFleet`s;
  `CampaignScene._ready()` spawns one `FactionBase` per faction;
  `CampaignScene._behavior_for_faction()` picks hostile-vs-ignore
  behavior for `DOMINION`/`FREEHOLD` fleets from their faction's current
  reputation.

- [ ] **Step 1: Write the failing test**

Add this case to `tests/test_campaign_scene.gd`'s `run_async`, right
after the existing bootstrap checks (`expected CampaignState.player_fleet
populated by bootstrap`) and before the `# Simulate the player clicking
to engage` comment:

```gdscript
	if campaign_state.factions.size() != 2:
		failures.append("expected 2 PowerFactions created by bootstrap, got %d" % campaign_state.factions.size())
	var faction_enums: Array = []
	for faction in campaign_state.factions:
		faction_enums.append(faction.faction_enum)
	if not faction_enums.has(CampaignFleet.Faction.DOMINION):
		failures.append("expected a DOMINION PowerFaction created by bootstrap")
	if not faction_enums.has(CampaignFleet.Faction.FREEHOLD):
		failures.append("expected a FREEHOLD PowerFaction created by bootstrap")

	var faction_base_count := 0
	for child in scene.get_children():
		if child is FactionBase:
			faction_base_count += 1
	if faction_base_count != 2:
		failures.append("expected 2 FactionBase nodes spawned, got %d" % faction_base_count)

	var dominion_icon: CampaignFleetIcon = null
	var freehold_icon: CampaignFleetIcon = null
	for icon in scene.enemy_icons:
		if icon.fleet.faction == CampaignFleet.Faction.DOMINION:
			dominion_icon = icon
		elif icon.fleet.faction == CampaignFleet.Faction.FREEHOLD:
			freehold_icon = icon
	if dominion_icon == null or freehold_icon == null:
		failures.append("expected both a DOMINION and a FREEHOLD enemy icon spawned")
	elif dominion_icon.behavior_type != CampaignFleetIcon.BehaviorType.PATROL:
		failures.append("expected DOMINION fleet to use PATROL behavior at starting (non-hostile) reputation, got %s" % dominion_icon.behavior_type)
```

- [ ] **Step 2: Run test to verify it fails**

Run the full suite via a throwaway runner (or `godot --headless --script
tests/run_tests.gd` if this task's own tests are temporarily added to
that file — but this task does not register them permanently; Task 8
does). Expected: FAIL — `CampaignState.factions` empty, no `FactionBase`
children, no `DOMINION`/`FREEHOLD` enemy icons.

- [ ] **Step 3: Write minimal implementation**

In `scripts/campaign/campaign_scene.gd`, add this const near the other
`preload`s at the top:

```gdscript
const FactionBaseScene = preload("res://scenes/campaign/faction_base.tscn")
```

In `_ready()`, after the existing `HomeBase` spawn block (`add_child(base)`)
and before `player_icon = _spawn_icon(...)`, add:

```gdscript
	for faction in CampaignState.factions:
		var faction_base: Area2D = FactionBaseScene.instantiate()
		faction_base.faction_enum = faction.faction_enum
		faction_base.global_position = faction.base_position
		add_child(faction_base)
```

In `_bootstrap_default_campaign()`, after the existing `patrol`
block and before `CampaignState.enemy_fleets = [pirate, trader, patrol]`,
add:

```gdscript
	var dominion_faction := PowerFaction.new()
	dominion_faction.faction_enum = CampaignFleet.Faction.DOMINION
	dominion_faction.display_name = "Dominion"
	dominion_faction.reputation = 60.0
	dominion_faction.base_position = Vector2(1000, 550)

	var freehold_faction := PowerFaction.new()
	freehold_faction.faction_enum = CampaignFleet.Faction.FREEHOLD
	freehold_faction.display_name = "Freehold"
	freehold_faction.reputation = 60.0
	freehold_faction.base_position = Vector2(150, 150)

	CampaignState.factions = [dominion_faction, freehold_faction]
	CampaignState.factions_at_war = true

	var dominion_fleet := CampaignFleet.new()
	dominion_fleet.faction = CampaignFleet.Faction.DOMINION
	dominion_fleet.position = Vector2(1000, 480)
	dominion_fleet.speed = 100.0
	dominion_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	var freehold_fleet := CampaignFleet.new()
	freehold_fleet.faction = CampaignFleet.Faction.FREEHOLD
	freehold_fleet.position = Vector2(200, 200)
	freehold_fleet.speed = 100.0
	freehold_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
```

Change the final line of `_bootstrap_default_campaign()` from
`CampaignState.enemy_fleets = [pirate, trader, patrol]` to:

```gdscript
	CampaignState.enemy_fleets = [pirate, trader, patrol, dominion_fleet, freehold_fleet]
```

Replace `_behavior_for_faction` with:

```gdscript
func _behavior_for_faction(faction: CampaignFleet.Faction) -> CampaignFleetIcon.BehaviorType:
	match faction:
		CampaignFleet.Faction.PIRATE:
			return CampaignFleetIcon.BehaviorType.PIRATE
		CampaignFleet.Faction.TRADER:
			return CampaignFleetIcon.BehaviorType.TRADER
		CampaignFleet.Faction.DOMINION, CampaignFleet.Faction.FREEHOLD:
			return CampaignFleetIcon.BehaviorType.PIRATE if _is_faction_hostile(faction) else CampaignFleetIcon.BehaviorType.PATROL
		_:
			return CampaignFleetIcon.BehaviorType.PATROL

func _is_faction_hostile(faction: CampaignFleet.Faction) -> bool:
	for power_faction in CampaignState.factions:
		if power_faction.faction_enum == faction:
			return power_faction.reputation < CampaignState.HOSTILE_REPUTATION_THRESHOLD
	return false
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS, 0 failures (including the pre-existing assertions in
this test's `run_async`).

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_scene.gd tests/test_campaign_scene.gd
git commit -m "Bootstrap Dominion and Freehold power factions with territory"
```

---

### Task 8: Skirmish detection, ticking, and full test-suite registration

**Files:**
- Modify: `scripts/campaign/campaign_scene.gd`
- Modify: `tests/test_campaign_scene.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: `CampaignState.are_hostile`, `start_skirmish`,
  `tick_skirmishes`, `cancel_skirmish_for` (all from Plan A).
- Produces: `CampaignScene` now detects hostile non-player icon overlaps
  and starts skirmishes; `CampaignScene._physics_process` ticks active
  skirmishes every frame; engaging a fleet cancels any skirmish it was
  part of. All of this plan's and Plan A's tests are registered in
  `tests/run_tests.gd`.

- [ ] **Step 1: Write the failing test**

Add this case to `tests/test_campaign_scene.gd`'s `run_async`,
immediately after the `dominion_icon`/`freehold_icon` lookup block added
in Task 7 (reuse the same `dominion_icon`/`freehold_icon` variables —
don't re-declare them):

```gdscript
	if dominion_icon != null and freehold_icon != null:
		dominion_icon.global_position = freehold_icon.global_position
		await tree.physics_frame
		if campaign_state.active_skirmishes.size() != 1:
			failures.append("expected overlapping hostile power-faction icons to start a skirmish")
		else:
			var skirmish: Skirmish = campaign_state.active_skirmishes[0]
			skirmish.remaining_time = 0.01
			await tree.physics_frame
			await tree.physics_frame
			if campaign_state.active_skirmishes.size() != 0:
				failures.append("expected CampaignScene._physics_process to tick and resolve the skirmish")
```

(Note: this test deliberately doesn't separately re-verify
`cancel_skirmish_for`'s own correctness — that's already covered by
Plan A's `tests/test_campaign_state.gd`. This task only needs to prove
the scene *wires into* that logic, not re-test the logic itself.)

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — no `area_entered` wiring for non-player icons yet, no
`_physics_process` ticking skirmishes yet.

- [ ] **Step 3: Write minimal implementation**

In `scripts/campaign/campaign_scene.gd`, in the enemy-spawning loop
inside `_ready()`, add a new connection right after `icon.player_target
= player_icon`:

```gdscript
		icon.area_entered.connect(_on_enemy_area_entered.bind(icon))
```

Add this new method (near `_on_player_area_entered`):

```gdscript
func _on_enemy_area_entered(other: Area2D, icon: CampaignFleetIcon) -> void:
	if other is CampaignFleetIcon and other != icon and other != player_icon:
		if CampaignState.are_hostile(icon.fleet, other.fleet):
			CampaignState.start_skirmish(icon, other)
```

Add a new `_physics_process`:

```gdscript
func _physics_process(delta: float) -> void:
	CampaignState.tick_skirmishes(delta)
```

Change `_on_engage_pressed` to cancel any skirmish the engaged fleet was
part of before starting real combat:

```gdscript
func _on_engage_pressed() -> void:
	engage_prompt.visible = false
	CampaignState.cancel_skirmish_for(_pending_enemy_icon)
	CampaignState.start_engagement(_pending_enemy_icon.fleet)
	get_tree().change_scene_to_file("res://scenes/combat/combat_scene.tscn")
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS, 0 failures.

- [ ] **Step 5: Register every new test from both plans in run_tests.gd**

In `tests/run_tests.gd`, add three new entries to the `test_scripts`
array (after the existing `preload("res://tests/test_campaign_state.gd"),`
line):

```gdscript
		preload("res://tests/test_power_faction.gd"),
		preload("res://tests/test_skirmish_resolution.gd"),
		preload("res://tests/test_faction_base.gd"),
```

Add a new awaited block for `test_campaign_state.gd`'s new `run_async`
(it constructs its own local `CampaignState.new()` instances rather than
touching the live autoload, same as its existing synchronous `run()`
case, so a plain `preload()` is safe here — no autoload-timing concern
applies). Place it right after the existing synchronous test loop and
before the `test_ship.gd` async block:

```gdscript
	var campaign_state_test = preload("res://tests/test_campaign_state.gd")
	var campaign_state_async_failures: Array[String] = await campaign_state_test.run_async(self)
	for f in campaign_state_async_failures:
		print("FAIL [%s]: %s" % [campaign_state_test.resource_path, f])
	total_failures += campaign_state_async_failures.size()
```

- [ ] **Step 6: Run the full suite to verify everything passes**

Run: `godot --headless --script tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 7: Manual playtest**

Run the game. Verify: Dominion and Freehold territory markers are
visible on the map, their fleets wander (not hostile at starting
reputation), and if a Dominion and a Freehold fleet are maneuvered into
contact (or happen to meet), they visibly freeze for a few seconds before
one is destroyed and the other continues on its way.

- [ ] **Step 8: Commit**

```bash
git add scripts/campaign/campaign_scene.gd tests/test_campaign_scene.gd tests/run_tests.gd
git commit -m "Wire NPC-vs-NPC skirmish detection and ticking into CampaignScene"
```
