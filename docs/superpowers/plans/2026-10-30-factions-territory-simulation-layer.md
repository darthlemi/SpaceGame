# Factions & Territory Simulation Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the data model and pure logic for power factions, faction
territory, and abstracted NPC-vs-NPC skirmish resolution, as
independently testable units. This plan does not wire anything into the
playable `CampaignScene` — that's Plan B
(`2026-10-30-factions-territory-scene-integration.md`).

**Architecture:** A `PowerFaction` Resource holds reputation and territory
data per faction. `SkirmishResolution` is a pure static-logic class
(mirroring `scripts/combat/formation.gd` and the existing campaign
behavior classes) computing skirmish duration/outcome from relative
fleet strength. A `Skirmish` is a plain data holder pairing two fleets
and icons mid-conflict. `CampaignState` (already the existing bridge
autoload) gains the methods that drive skirmishes end-to-end and the
reputation decay on player victories.

**Tech Stack:** Godot 4.7, GDScript. Tests follow this repo's existing
pattern: `extends RefCounted` with a static `run() -> Array[String]`
(synchronous) or `run_async(tree) -> Array[String]` (needs a live
SceneTree), registered in `tests/run_tests.gd` by a later task in Plan B
(this plan's tests are written but not yet wired into the suite runner,
matching how Plan A of the Campaign Map milestone handled its own
not-yet-registered tests).

## Global Constraints

- Tabs for indentation, matching every existing `.gd` file in this repo.
- `CampaignFleet.Faction` enum gains two new values, `DOMINION` and
  `FREEHOLD`, representing the two power factions — reusing the existing
  enum rather than introducing a parallel faction-identity field.
- `PowerFaction.faction_enum` is typed `CampaignFleet.Faction` (not a
  separate `StringName` id) so that matching a `CampaignFleet` to its
  owning `PowerFaction` is plain enum equality — no string keys to keep
  in sync.
- `MAX_SKIRMISH_TIME = 30.0`, `MIN_SKIRMISH_TIME = 3.0`,
  `MAX_WINNER_DAMAGE_FRACTION = 0.5`, `REPUTATION_LOSS_PER_DEFEAT = 15.0`,
  `HOSTILE_REPUTATION_THRESHOLD = 40.0` — exact values from the design
  spec, used verbatim.
- Pirates (`CampaignFleet.Faction.PIRATE`) never gain a `PowerFaction` and
  are unaffected by reputation — they remain exactly as implemented in
  the prior Campaign Map milestone.

---

### Task 1: PowerFaction data model

**Files:**
- Create: `scripts/campaign/power_faction.gd`
- Test: `tests/test_power_faction.gd`

**Interfaces:**
- Consumes: `CampaignFleet.Faction` enum (already exists).
- Produces: `class_name PowerFaction extends Resource` with
  `faction_enum: CampaignFleet.Faction`, `display_name: String`,
  `reputation: float`, `base_position: Vector2`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends RefCounted

const PowerFaction = preload("res://scripts/campaign/power_faction.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var faction := PowerFaction.new()
	if faction.faction_enum != CampaignFleet.Faction.NEUTRAL:
		failures.append("PowerFaction: expected default faction_enum == NEUTRAL, got %s" % faction.faction_enum)
	if faction.reputation != 60.0:
		failures.append("PowerFaction: expected default reputation == 60.0, got %s" % faction.reputation)

	faction.faction_enum = CampaignFleet.Faction.DOMINION
	faction.display_name = "Dominion"
	faction.reputation = 25.0
	faction.base_position = Vector2(1000, 550)

	if faction.faction_enum != CampaignFleet.Faction.DOMINION:
		failures.append("PowerFaction: expected faction_enum to be settable")
	if faction.display_name != "Dominion":
		failures.append("PowerFaction: expected display_name to be settable")
	if faction.reputation != 25.0:
		failures.append("PowerFaction: expected reputation to be settable")
	if faction.base_position != Vector2(1000, 550):
		failures.append("PowerFaction: expected base_position to be settable")

	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Run via a throwaway SceneTree runner (this test file is `extends
RefCounted` with a static `run()`, so it can't run directly via `godot
--headless --script` — write a small runner that preloads it and calls
`.run()`, same pattern used throughout this repo's test suite). Expected:
FAIL, script not found.

- [ ] **Step 3: Write minimal implementation**

```gdscript
class_name PowerFaction
extends Resource

@export var faction_enum: CampaignFleet.Faction = CampaignFleet.Faction.NEUTRAL
@export var display_name: String = ""
@export var reputation: float = 60.0
@export var base_position: Vector2 = Vector2.ZERO
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/power_faction.gd tests/test_power_faction.gd
git commit -m "Add PowerFaction data model for faction reputation and territory"
```

---

### Task 2: SkirmishResolution pure logic

**Files:**
- Create: `scripts/campaign/skirmish_resolution.gd`
- Test: `tests/test_skirmish_resolution.gd`

**Interfaces:**
- Consumes: nothing (pure functions, no dependency on Task 1).
- Produces: `class_name SkirmishResolution extends RefCounted` with
  constants `MAX_SKIRMISH_TIME = 30.0`, `MIN_SKIRMISH_TIME = 3.0`,
  `MAX_WINNER_DAMAGE_FRACTION = 0.5`, and static functions
  `imbalance(strength_a: float, strength_b: float) -> float`,
  `duration(imbalance: float) -> float`,
  `winner_damage_fraction(imbalance: float) -> float`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends RefCounted

const SkirmishResolution = preload("res://scripts/campaign/skirmish_resolution.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var even := SkirmishResolution.imbalance(100.0, 100.0)
	if even != 0.0:
		failures.append("imbalance: expected 0.0 for an even fight, got %s" % even)

	var lopsided := SkirmishResolution.imbalance(190.0, 10.0)
	if abs(lopsided - 0.9) > 0.001:
		failures.append("imbalance: expected ~0.9 for a 190/10 split, got %s" % lopsided)

	var zero_total := SkirmishResolution.imbalance(0.0, 0.0)
	if zero_total != 1.0:
		failures.append("imbalance: expected 1.0 when both strengths are 0, got %s" % zero_total)

	var long_duration := SkirmishResolution.duration(0.0)
	if abs(long_duration - SkirmishResolution.MAX_SKIRMISH_TIME) > 0.001:
		failures.append("duration: expected MAX_SKIRMISH_TIME at imbalance 0.0, got %s" % long_duration)

	var short_duration := SkirmishResolution.duration(1.0)
	if abs(short_duration - SkirmishResolution.MIN_SKIRMISH_TIME) > 0.001:
		failures.append("duration: expected MIN_SKIRMISH_TIME at imbalance 1.0, got %s" % short_duration)

	var even_damage := SkirmishResolution.winner_damage_fraction(0.0)
	if abs(even_damage - SkirmishResolution.MAX_WINNER_DAMAGE_FRACTION) > 0.001:
		failures.append("winner_damage_fraction: expected MAX_WINNER_DAMAGE_FRACTION at imbalance 0.0, got %s" % even_damage)

	var lopsided_damage := SkirmishResolution.winner_damage_fraction(1.0)
	if abs(lopsided_damage - 0.0) > 0.001:
		failures.append("winner_damage_fraction: expected ~0.0 at imbalance 1.0, got %s" % lopsided_damage)

	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, script not found.

- [ ] **Step 3: Write minimal implementation**

```gdscript
class_name SkirmishResolution
extends RefCounted

const MAX_SKIRMISH_TIME := 30.0
const MIN_SKIRMISH_TIME := 3.0
const MAX_WINNER_DAMAGE_FRACTION := 0.5

static func imbalance(strength_a: float, strength_b: float) -> float:
	var total := strength_a + strength_b
	if total <= 0.0:
		return 1.0
	return abs(strength_a - strength_b) / total

static func duration(imbalance_value: float) -> float:
	return lerp(MAX_SKIRMISH_TIME, MIN_SKIRMISH_TIME, imbalance_value)

static func winner_damage_fraction(imbalance_value: float) -> float:
	return (1.0 - imbalance_value) * MAX_WINNER_DAMAGE_FRACTION
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/skirmish_resolution.gd tests/test_skirmish_resolution.gd
git commit -m "Add SkirmishResolution duration/damage formulas"
```

---

### Task 3: CampaignFleet — faction enum extension and fractional damage

**Files:**
- Modify: `scripts/campaign/campaign_fleet.gd`
- Modify: `tests/test_campaign_fleet.gd`

**Interfaces:**
- Produces: `CampaignFleet.Faction` enum now `{ PLAYER, NEUTRAL, TRADER,
  PIRATE, DOMINION, FREEHOLD }`; new method
  `apply_fractional_damage(fraction: float) -> void`.

- [ ] **Step 1: Write the failing test**

Add this case to `tests/test_campaign_fleet.gd`'s `run()`, before the
final `return failures`:

```gdscript
	var dominion_fleet := CampaignFleet.new()
	dominion_fleet.faction = CampaignFleet.Faction.DOMINION
	if dominion_fleet.faction != CampaignFleet.Faction.DOMINION:
		failures.append("Faction enum: expected DOMINION to be a valid value")

	var freehold_fleet := CampaignFleet.new()
	freehold_fleet.faction = CampaignFleet.Faction.FREEHOLD
	if freehold_fleet.faction != CampaignFleet.Faction.FREEHOLD:
		failures.append("Faction enum: expected FREEHOLD to be a valid value")

	var damaged := CampaignFleet.new()
	damaged.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
	]
	damaged.apply_fractional_damage(0.5)
	var comp: Dictionary = damaged.ship_compositions[0]
	if abs(comp["current_hp"] - 50.0) > 0.001:
		failures.append("apply_fractional_damage: expected current_hp halved to 50.0, got %s" % comp["current_hp"])
	if abs(comp["current_shield"] - 25.0) > 0.001:
		failures.append("apply_fractional_damage: expected current_shield halved to 25.0, got %s" % comp["current_shield"])

	var overkill := CampaignFleet.new()
	overkill.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 10.0, "max_shield": 50.0, "current_shield": 5.0},
	]
	overkill.apply_fractional_damage(1.0)
	var overkill_comp: Dictionary = overkill.ship_compositions[0]
	if overkill_comp["current_hp"] != 0.0:
		failures.append("apply_fractional_damage: expected current_hp clamped to 0.0 at fraction 1.0, got %s" % overkill_comp["current_hp"])
	if overkill_comp["current_shield"] != 0.0:
		failures.append("apply_fractional_damage: expected current_shield clamped to 0.0 at fraction 1.0, got %s" % overkill_comp["current_shield"])
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `DOMINION`/`FREEHOLD` not valid enum values yet,
`apply_fractional_damage` not defined.

- [ ] **Step 3: Write minimal implementation**

In `scripts/campaign/campaign_fleet.gd`, change the enum line:

```gdscript
enum Faction { PLAYER, NEUTRAL, TRADER, PIRATE, DOMINION, FREEHOLD }
```

Add this method (near `repair_to_full`):

```gdscript
func apply_fractional_damage(fraction: float) -> void:
	for comp in ship_compositions:
		comp["current_hp"] = max(0.0, comp["current_hp"] * (1.0 - fraction))
		comp["current_shield"] = max(0.0, comp["current_shield"] * (1.0 - fraction))
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS, 0 failures (including the pre-existing cases in this
file).

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_fleet.gd tests/test_campaign_fleet.gd
git commit -m "Add DOMINION/FREEHOLD faction values and fractional damage to CampaignFleet"
```

---

### Task 4: FactionBase territory landmark

**Files:**
- Create: `scripts/campaign/faction_base.gd`
- Create: `scenes/campaign/faction_base.tscn`
- Test: `tests/test_faction_base.gd`

**Interfaces:**
- Consumes: `CampaignFleet.Faction` enum (already exists).
- Produces: `class_name FactionBase extends Area2D` with exported
  `faction_enum: CampaignFleet.Faction`. No behavior logic this
  milestone — a static landmark only (docking/capture are out of scope,
  per the design spec).

- [ ] **Step 1: Write the failing test**

```gdscript
extends RefCounted

const FactionBaseScene = preload("res://scenes/campaign/faction_base.tscn")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var base: Area2D = FactionBaseScene.instantiate()
	if base.faction_enum != CampaignFleet.Faction.NEUTRAL:
		failures.append("FactionBase: expected default faction_enum == NEUTRAL, got %s" % base.faction_enum)

	base.faction_enum = CampaignFleet.Faction.FREEHOLD
	base.global_position = Vector2(150, 150)
	if base.faction_enum != CampaignFleet.Faction.FREEHOLD:
		failures.append("FactionBase: expected faction_enum to be settable")
	if base.global_position != Vector2(150, 150):
		failures.append("FactionBase: expected global_position to be settable")

	base.free()
	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, scene/script not found.

- [ ] **Step 3: Write minimal implementation**

`scripts/campaign/faction_base.gd`:

```gdscript
class_name FactionBase
extends Area2D

@export var faction_enum: CampaignFleet.Faction = CampaignFleet.Faction.NEUTRAL
```

`scenes/campaign/faction_base.tscn`:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/campaign/faction_base.gd" id="1"]

[sub_resource type="CircleShape2D" id="1"]
radius = 30.0

[node name="FactionBase" type="Area2D"]
script = ExtResource("1")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("1")

[node name="Polygon2D" type="Polygon2D" parent="."]
polygon = PackedVector2Array(-20, -20, 20, -20, 20, 20, -20, 20)
color = Color(0.8, 0.3, 0.3, 1)
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/faction_base.gd scenes/campaign/faction_base.tscn tests/test_faction_base.gd
git commit -m "Add FactionBase territory landmark"
```

---

### Task 5: CampaignFleetIcon — frozen state

**Files:**
- Modify: `scripts/campaign/campaign_fleet_icon.gd`
- Modify: `tests/test_campaign_fleet_icon.gd`

**Interfaces:**
- Produces: `CampaignFleetIcon.frozen: bool` (default `false`). When
  `true`, `_physics_process` skips both behavior dispatch and movement
  entirely (the icon holds its exact position).

- [ ] **Step 1: Write the failing test**

Add this case to `tests/test_campaign_fleet_icon.gd`'s `run_async`,
before the final `return failures`:

```gdscript
	# Frozen: a patrol icon should not move at all while frozen, then
	# should resume wandering once unfrozen.
	var frozen_fleet := CampaignFleet.new()
	frozen_fleet.position = Vector2(300, 300)
	frozen_fleet.speed = 400.0
	var frozen_icon: Area2D = CampaignFleetIconScene.instantiate()
	frozen_icon.behavior_type = frozen_icon.BehaviorType.PATROL
	frozen_icon.wander_radius = 50.0
	frozen_icon.frozen = true
	tree.root.add_child(frozen_icon)
	frozen_icon.setup(frozen_fleet, Vector2.ZERO)

	var frozen_start: Vector2 = frozen_icon.global_position
	for i in 15:
		await tree.physics_frame
	if frozen_icon.global_position != frozen_start:
		failures.append("frozen: expected icon to hold position while frozen, moved from %s to %s" % [frozen_start, frozen_icon.global_position])

	frozen_icon.frozen = false
	for i in 30:
		await tree.physics_frame
	if frozen_icon.global_position == frozen_start:
		failures.append("frozen: expected icon to move again once unfrozen, still at %s" % frozen_icon.global_position)

	frozen_icon.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `frozen` property doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

In `scripts/campaign/campaign_fleet_icon.gd`, add the field near the
other `var` declarations:

```gdscript
var frozen: bool = false
```

Change the top of `_physics_process`:

```gdscript
func _physics_process(delta: float) -> void:
	if fleet == null or frozen:
		return
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS, 0 failures (including the pre-existing cases in this
file).

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_fleet_icon.gd tests/test_campaign_fleet_icon.gd
git commit -m "Add CampaignFleetIcon frozen state for skirmish freezing"
```

---

### Task 6: Skirmish data holder and CampaignState wiring

**Files:**
- Create: `scripts/campaign/skirmish.gd`
- Modify: `scripts/campaign/campaign_state.gd`
- Test: `tests/test_campaign_state.gd`

**Interfaces:**
- Consumes: `PowerFaction` (Task 1), `SkirmishResolution` (Task 2),
  `CampaignFleet.apply_fractional_damage`/`Faction` enum (Task 3),
  `CampaignFleetIcon.frozen` (Task 5).
- Produces: `class_name Skirmish extends RefCounted` with
  `fleet_winner: CampaignFleet`, `fleet_loser: CampaignFleet`,
  `icon_winner: CampaignFleetIcon`, `icon_loser: CampaignFleetIcon`,
  `remaining_time: float`, `winner_damage_fraction: float`.
  `CampaignState` gains `factions: Array[PowerFaction] = []`,
  `factions_at_war: bool = true`, `active_skirmishes: Array[Skirmish] =
  []`, constants `REPUTATION_LOSS_PER_DEFEAT = 15.0` and
  `HOSTILE_REPUTATION_THRESHOLD = 40.0`, and methods
  `are_hostile(fleet_a: CampaignFleet, fleet_b: CampaignFleet) -> bool`,
  `start_skirmish(icon_a: CampaignFleetIcon, icon_b: CampaignFleetIcon)
  -> void`, `tick_skirmishes(delta: float) -> void`,
  `cancel_skirmish_for(icon: CampaignFleetIcon) -> void`. `reset()` and
  `resolve_engagement()` are extended (see Step 3).

- [ ] **Step 1: Write the failing test**

Add this case to `tests/test_campaign_state.gd`'s `run()`, before the
final `return failures` (note: unlike the other synchronous cases in
this file, exercising `tick_skirmishes`' node cleanup needs a live tree,
so this new case uses a fresh `run_async(tree)` — add that function to
the same file, after `run()`, following the exact `async_failures`
collection pattern already used elsewhere in this repo for files that
have both a sync and async entry point, e.g. how `test_ship.gd` and
`test_combat_scene.gd` are both invoked in `tests/run_tests.gd`):

```gdscript
static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var state := CampaignState.new()

	var dominion := PowerFaction.new()
	dominion.faction_enum = CampaignFleet.Faction.DOMINION
	var freehold := PowerFaction.new()
	freehold.faction_enum = CampaignFleet.Faction.FREEHOLD
	state.factions = [dominion, freehold]
	state.factions_at_war = true

	var dominion_fleet := CampaignFleet.new()
	dominion_fleet.faction = CampaignFleet.Faction.DOMINION
	var freehold_fleet := CampaignFleet.new()
	freehold_fleet.faction = CampaignFleet.Faction.FREEHOLD
	var trader_fleet := CampaignFleet.new()
	trader_fleet.faction = CampaignFleet.Faction.TRADER

	if not state.are_hostile(dominion_fleet, freehold_fleet):
		failures.append("are_hostile: expected two warring power factions to be hostile")
	if state.are_hostile(dominion_fleet, trader_fleet):
		failures.append("are_hostile: expected a power faction and a trader to be non-hostile")
	state.factions_at_war = false
	if state.are_hostile(dominion_fleet, freehold_fleet):
		failures.append("are_hostile: expected power factions at peace to be non-hostile")
	state.factions_at_war = true

	var pirate_fleet := CampaignFleet.new()
	pirate_fleet.faction = CampaignFleet.Faction.PIRATE
	if not state.are_hostile(pirate_fleet, dominion_fleet):
		failures.append("are_hostile: expected a pirate and a power faction to be hostile")

	# start_skirmish + tick_skirmishes: stronger fleet wins, loser removed,
	# winner damaged proportionally, loser icon freed, winner icon unfrozen.
	var strong_fleet := CampaignFleet.new()
	strong_fleet.faction = CampaignFleet.Faction.DOMINION
	strong_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0}]
	var weak_fleet := CampaignFleet.new()
	weak_fleet.faction = CampaignFleet.Faction.FREEHOLD
	weak_fleet.ship_compositions = [{"max_hp": 20.0, "current_hp": 20.0, "max_shield": 0.0, "current_shield": 0.0}]

	state.enemy_fleets = [strong_fleet, weak_fleet]

	const CampaignFleetIconScene = preload("res://scenes/campaign/campaign_fleet_icon.tscn")
	var strong_icon: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(strong_icon)
	strong_icon.setup(strong_fleet, Vector2.ZERO)
	var weak_icon: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(weak_icon)
	weak_icon.setup(weak_fleet, Vector2.ZERO)

	state.start_skirmish(strong_icon, weak_icon)
	if not strong_icon.frozen or not weak_icon.frozen:
		failures.append("start_skirmish: expected both icons frozen")
	if state.active_skirmishes.size() != 1:
		failures.append("start_skirmish: expected exactly one active skirmish, got %d" % state.active_skirmishes.size())

	var skirmish: Skirmish = state.active_skirmishes[0]
	if skirmish.fleet_winner != strong_fleet or skirmish.fleet_loser != weak_fleet:
		failures.append("start_skirmish: expected the stronger fleet to be recorded as winner")

	state.tick_skirmishes(skirmish.remaining_time + 1.0)
	if state.active_skirmishes.size() != 0:
		failures.append("tick_skirmishes: expected the skirmish to be resolved and removed")
	if state.enemy_fleets.has(weak_fleet):
		failures.append("tick_skirmishes: expected the loser fleet removed from enemy_fleets")
	if strong_fleet.ship_compositions[0]["current_hp"] >= 100.0:
		failures.append("tick_skirmishes: expected the winner to take proportional damage")
	if strong_icon.frozen:
		failures.append("tick_skirmishes: expected the winner icon to unfreeze")

	await tree.process_frame

	# cancel_skirmish_for: starting a fresh skirmish and cancelling it
	# should unfreeze the untouched participant without resolving a winner.
	var fleet_c := CampaignFleet.new()
	fleet_c.faction = CampaignFleet.Faction.DOMINION
	fleet_c.ship_compositions = [{"max_hp": 50.0, "current_hp": 50.0, "max_shield": 0.0, "current_shield": 0.0}]
	var fleet_d := CampaignFleet.new()
	fleet_d.faction = CampaignFleet.Faction.FREEHOLD
	fleet_d.ship_compositions = [{"max_hp": 50.0, "current_hp": 50.0, "max_shield": 0.0, "current_shield": 0.0}]
	var icon_c: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(icon_c)
	icon_c.setup(fleet_c, Vector2.ZERO)
	var icon_d: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(icon_d)
	icon_d.setup(fleet_d, Vector2.ZERO)

	state.start_skirmish(icon_c, icon_d)
	state.cancel_skirmish_for(icon_c)
	if state.active_skirmishes.size() != 0:
		failures.append("cancel_skirmish_for: expected the skirmish removed")
	if icon_d.frozen:
		failures.append("cancel_skirmish_for: expected the other participant unfrozen")

	icon_c.queue_free()
	icon_d.queue_free()

	# resolve_engagement reputation decay.
	var defeat_state := CampaignState.new()
	var defeat_dominion := PowerFaction.new()
	defeat_dominion.faction_enum = CampaignFleet.Faction.DOMINION
	defeat_dominion.reputation = 60.0
	defeat_state.factions = [defeat_dominion]
	var defeat_player := CampaignFleet.new()
	defeat_player.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	defeat_state.player_fleet = defeat_player
	var defeated_enemy := CampaignFleet.new()
	defeated_enemy.faction = CampaignFleet.Faction.DOMINION
	defeated_enemy.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	defeat_state.start_engagement(defeated_enemy)
	defeat_state.resolve_engagement(
		[{"max_hp": 100.0, "current_hp": 80.0, "max_shield": 50.0, "current_shield": 50.0}],
		[]
	)
	if abs(defeat_dominion.reputation - 45.0) > 0.001:
		failures.append("resolve_engagement: expected reputation reduced by REPUTATION_LOSS_PER_DEFEAT to 45.0, got %s" % defeat_dominion.reputation)

	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `Skirmish`, `are_hostile`, `start_skirmish`,
`tick_skirmishes`, `cancel_skirmish_for`, `factions`, `factions_at_war`
not defined yet.

- [ ] **Step 3: Write minimal implementation**

`scripts/campaign/skirmish.gd`:

```gdscript
class_name Skirmish
extends RefCounted

var fleet_winner: CampaignFleet
var fleet_loser: CampaignFleet
var icon_winner: CampaignFleetIcon
var icon_loser: CampaignFleetIcon
var remaining_time: float
var winner_damage_fraction: float
```

Replace the full contents of `scripts/campaign/campaign_state.gd` with:

```gdscript
extends Node

const REPUTATION_LOSS_PER_DEFEAT := 15.0
const HOSTILE_REPUTATION_THRESHOLD := 40.0

var player_fleet: CampaignFleet
var enemy_fleets: Array[CampaignFleet] = []
var active_enemy_fleet: CampaignFleet
var factions: Array[PowerFaction] = []
var factions_at_war: bool = true
var active_skirmishes: Array[Skirmish] = []

func start_engagement(enemy_fleet: CampaignFleet) -> void:
	active_enemy_fleet = enemy_fleet

func resolve_engagement(player_survivors: Array[Dictionary], enemy_survivors: Array[Dictionary]) -> void:
	if player_fleet == null:
		return
	player_fleet.ship_compositions = player_survivors.duplicate(true)
	if active_enemy_fleet != null:
		active_enemy_fleet.ship_compositions = enemy_survivors.duplicate(true)
		if active_enemy_fleet.is_destroyed():
			enemy_fleets.erase(active_enemy_fleet)
			_apply_reputation_loss(active_enemy_fleet.faction)
	active_enemy_fleet = null

func reset() -> void:
	player_fleet = null
	enemy_fleets = []
	active_enemy_fleet = null
	factions = []
	factions_at_war = true
	active_skirmishes = []

func are_hostile(fleet_a: CampaignFleet, fleet_b: CampaignFleet) -> bool:
	var a := fleet_a.faction
	var b := fleet_b.faction
	var pirate := CampaignFleet.Faction.PIRATE
	if a == pirate and _is_power_faction(b):
		return true
	if b == pirate and _is_power_faction(a):
		return true
	if _is_power_faction(a) and _is_power_faction(b) and a != b:
		return factions_at_war
	return false

func start_skirmish(icon_a: CampaignFleetIcon, icon_b: CampaignFleetIcon) -> void:
	if icon_a.frozen or icon_b.frozen:
		return
	var strength_a := icon_a.fleet.total_strength()
	var strength_b := icon_b.fleet.total_strength()
	var imbalance_value := SkirmishResolution.imbalance(strength_a, strength_b)

	var skirmish := Skirmish.new()
	skirmish.remaining_time = SkirmishResolution.duration(imbalance_value)
	skirmish.winner_damage_fraction = SkirmishResolution.winner_damage_fraction(imbalance_value)
	if strength_a >= strength_b:
		skirmish.fleet_winner = icon_a.fleet
		skirmish.fleet_loser = icon_b.fleet
		skirmish.icon_winner = icon_a
		skirmish.icon_loser = icon_b
	else:
		skirmish.fleet_winner = icon_b.fleet
		skirmish.fleet_loser = icon_a.fleet
		skirmish.icon_winner = icon_b
		skirmish.icon_loser = icon_a

	icon_a.frozen = true
	icon_b.frozen = true
	active_skirmishes.append(skirmish)

func tick_skirmishes(delta: float) -> void:
	for skirmish in active_skirmishes.duplicate():
		skirmish.remaining_time -= delta
		if skirmish.remaining_time <= 0.0:
			_resolve_skirmish(skirmish)

func cancel_skirmish_for(icon: CampaignFleetIcon) -> void:
	for skirmish in active_skirmishes.duplicate():
		if skirmish.icon_winner == icon or skirmish.icon_loser == icon:
			active_skirmishes.erase(skirmish)
			var other: CampaignFleetIcon = skirmish.icon_loser if skirmish.icon_winner == icon else skirmish.icon_winner
			if is_instance_valid(other):
				other.frozen = false

func _resolve_skirmish(skirmish: Skirmish) -> void:
	active_skirmishes.erase(skirmish)
	skirmish.fleet_winner.apply_fractional_damage(skirmish.winner_damage_fraction)
	enemy_fleets.erase(skirmish.fleet_loser)
	if is_instance_valid(skirmish.icon_loser):
		skirmish.icon_loser.queue_free()
	if is_instance_valid(skirmish.icon_winner):
		skirmish.icon_winner.frozen = false

func _is_power_faction(faction: CampaignFleet.Faction) -> bool:
	return faction == CampaignFleet.Faction.DOMINION or faction == CampaignFleet.Faction.FREEHOLD

func _apply_reputation_loss(defeated_faction: CampaignFleet.Faction) -> void:
	for power_faction in factions:
		if power_faction.faction_enum == defeated_faction:
			power_faction.reputation = max(0.0, power_faction.reputation - REPUTATION_LOSS_PER_DEFEAT)
```

- [ ] **Step 4: Run test to verify it passes**

Run via a throwaway runner that calls both `.run()` and `await
.run_async(self)` on `test_campaign_state.gd`, same pattern as this
repo's other dual-entry-point test files. Expected: PASS, 0 failures on
both.

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/skirmish.gd scripts/campaign/campaign_state.gd tests/test_campaign_state.gd
git commit -m "Add Skirmish resolution and reputation decay to CampaignState"
```

## What This Plan Does Not Do

No bootstrap data creates any `PowerFaction` or power-faction
`CampaignFleet` yet, `CampaignScene` doesn't spawn `FactionBase` scenes or
detect NPC-vs-NPC overlaps, and none of this plan's tests are registered
in `tests/run_tests.gd`. That's Plan B:
`docs/superpowers/plans/2026-10-30-factions-territory-scene-integration.md`.
