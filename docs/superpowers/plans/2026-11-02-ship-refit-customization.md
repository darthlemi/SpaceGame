# Ship Refit/Customization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the player buy weapons/shields/engines with credits at any base, hold them in a spare-parts inventory, and equip them onto specific ships in their fleet under a per-ship-class loadout-points budget — with equipped gear actually carrying into combat.

**Architecture:** New `PartRarity` module centralizes price/points-by-rarity lookups shared by the existing `Weapon` resource and two new swappable resources (`ShieldGenerator`, `EngineCore`). `ShipType` gains slot/budget bookkeeping helpers operating on the existing `ship_compositions` dictionaries. `CampaignState` gains three thin business-logic methods (`buy_part`/`sell_part`/`equip_part`). A new `RefitPanel` UI (pattern-matched off the existing `TradePanel`/`LootPanel`) opens alongside the trade panel at any base. `combat_scene.gd` gets extended so equipped items actually apply to the live `Ship` node and round-trip back into the campaign.

**Tech Stack:** Godot 4 / GDScript. Hand-rolled test framework (`static func run() -> Array[String]` or `run_async(tree) -> Array[String]`, registered in `tests/run_tests.gd`). Headless test command:
`& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`

## Global Constraints

- Hull is never swappable — `ShipType.BASE_STATS[kind]["max_hp"]` stays fixed per class, permanently.
- Parts (weapons/shields/engines) are bought/sold/equipped only while docked at a base — no equip-anywhere.
- Spare-parts inventory shares the player fleet's existing cargo capacity (1 part = 1 cargo unit, same pool as commodities).
- A ship's total equipped points (every weapon mount + shield + engine, summed) must never exceed `ShipType.points_budget_for(kind)`. Enforced only at equip time — nothing retroactively unequips.
- Refit's Equip action is blocked on a damaged ship (`CampaignState.is_damaged(comp)` true) — repair first.
- New PNGs/textures are explicitly **not** part of this plan — all new UI rows are text-only (no icons), since no new art pipeline work is in scope.
- Godot's class cache needs one `--headless --editor --quit` warm pass per checkout after adding new `class_name` scripts or `.tres` resources, before `--headless --script` test runs will see them.
- Follow existing file style: tabs for indentation, `class_name`/`extends` header, no doc comments beyond what the codebase already has.

---

### Task 1: PartRarity shared pricing module

**Files:**
- Create: `scripts/ship/part_rarity.gd`
- Test: `tests/test_part_rarity.gd`

**Interfaces:**
- Produces: `class_name PartRarity`, `enum Tier { COMMON, UNCOMMON, RARE, EPIC }`, `static func price_for(tier: int) -> float`, `static func sell_price_for(tier: int) -> float`, `static func points_for(tier: int) -> int`. Later tasks (ShieldGenerator, EngineCore, CampaignState, RefitPanel) call these three functions and reference `PartRarity.Tier`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []

	if PartRarity.price_for(PartRarity.Tier.COMMON) != 100.0:
		failures.append("price_for: expected COMMON == 100.0, got %s" % PartRarity.price_for(PartRarity.Tier.COMMON))
	if PartRarity.price_for(PartRarity.Tier.EPIC) != 1500.0:
		failures.append("price_for: expected EPIC == 1500.0, got %s" % PartRarity.price_for(PartRarity.Tier.EPIC))
	if not is_equal_approx(PartRarity.sell_price_for(PartRarity.Tier.RARE), 300.0):
		failures.append("sell_price_for: expected RARE sell == 300.0 (50%% of 600), got %s" % PartRarity.sell_price_for(PartRarity.Tier.RARE))
	if PartRarity.points_for(PartRarity.Tier.UNCOMMON) != 10:
		failures.append("points_for: expected UNCOMMON == 10, got %s" % PartRarity.points_for(PartRarity.Tier.UNCOMMON))

	var prev_price := -1.0
	var prev_points := -1
	for tier in PartRarity.Tier.values():
		if PartRarity.price_for(tier) <= prev_price:
			failures.append("price_for: expected strictly increasing price by tier, failed at tier %s" % tier)
		if PartRarity.points_for(tier) <= prev_points:
			failures.append("points_for: expected strictly increasing points by tier, failed at tier %s" % tier)
		prev_price = PartRarity.price_for(tier)
		prev_points = PartRarity.points_for(tier)

	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Run: `& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --editor --quit --path .` (warm the class cache for the not-yet-existing `PartRarity`), then add `preload("res://tests/test_part_rarity.gd")` to `tests/run_tests.gd`'s `_run_all()` list and run the main test command.
Expected: FAIL — `Identifier "PartRarity" not declared`.

- [ ] **Step 3: Write minimal implementation**

```gdscript
class_name PartRarity
extends RefCounted

enum Tier { COMMON, UNCOMMON, RARE, EPIC }

const PRICE_BY_TIER := {
	Tier.COMMON: 100.0,
	Tier.UNCOMMON: 250.0,
	Tier.RARE: 600.0,
	Tier.EPIC: 1500.0,
}

const POINTS_BY_TIER := {
	Tier.COMMON: 5,
	Tier.UNCOMMON: 10,
	Tier.RARE: 15,
	Tier.EPIC: 20,
}

const SELL_FRACTION := 0.5

static func price_for(tier: int) -> float:
	return PRICE_BY_TIER[tier]

static func sell_price_for(tier: int) -> float:
	return PRICE_BY_TIER[tier] * SELL_FRACTION

static func points_for(tier: int) -> int:
	return POINTS_BY_TIER[tier]
```

- [ ] **Step 4: Run test to verify it passes**

Run the main headless test command (after one `--editor --quit` warm pass). Expected: `test_part_rarity.gd` reports 0 failures.

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/part_rarity.gd tests/test_part_rarity.gd tests/run_tests.gd
git commit -m "Add PartRarity shared price/points-by-tier lookup"
```

---

### Task 2: ShieldGenerator and EngineCore swappable resources

**Files:**
- Create: `scripts/ship/shield_generator.gd`, `scripts/ship/engine_core.gd`
- Create: `resources/shields/shield_standard.tres`, `resources/shields/shield_light.tres`, `resources/shields/shield_dominion_aegis.tres`, `resources/shields/shield_dominion_bulwark.tres`, `resources/shields/shield_freehold_patch.tres`, `resources/shields/shield_freehold_capacitor.tres`
- Create: `resources/engines/engine_standard.tres`, `resources/engines/engine_dominion_heavy.tres`, `resources/engines/engine_dominion_titan.tres`, `resources/engines/engine_freehold_scout.tres`, `resources/engines/engine_freehold_racer.tres`
- Test: `tests/test_shield_generator.gd`, `tests/test_engine_core.gd`

**Interfaces:**
- Consumes: `PartRarity.Tier` (Task 1).
- Produces: `class_name ShieldGenerator` (`item_name: String`, `max_shield: float`, `regen_rate: float`, `rarity: PartRarity.Tier`); `class_name EngineCore` (`item_name: String`, `max_speed: float`, `turn_rate: float`, `acceleration: float`, `rarity: PartRarity.Tier`). 11 `.tres` resource paths that Task 4 (RefitCatalog) and Task 9 (combat integration) reference by path.

- [ ] **Step 1: Write the failing tests**

```gdscript
# tests/test_shield_generator.gd
extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	var shield: ShieldGenerator = load("res://resources/shields/shield_dominion_bulwark.tres")
	if shield == null:
		failures.append("shield_dominion_bulwark.tres: failed to load")
		return failures
	if not is_equal_approx(shield.max_shield, 50.0):
		failures.append("shield_dominion_bulwark: expected max_shield 50.0, got %s" % shield.max_shield)
	if shield.rarity != PartRarity.Tier.RARE:
		failures.append("shield_dominion_bulwark: expected rarity RARE, got %s" % shield.rarity)

	var paths := [
		"res://resources/shields/shield_standard.tres",
		"res://resources/shields/shield_light.tres",
		"res://resources/shields/shield_dominion_aegis.tres",
		"res://resources/shields/shield_dominion_bulwark.tres",
		"res://resources/shields/shield_freehold_patch.tres",
		"res://resources/shields/shield_freehold_capacitor.tres",
	]
	for path in paths:
		if not ResourceLoader.exists(path):
			failures.append("ShieldGenerator pool: missing resource %s" % path)
	return failures
```

```gdscript
# tests/test_engine_core.gd
extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	var engine: EngineCore = load("res://resources/engines/engine_freehold_racer.tres")
	if engine == null:
		failures.append("engine_freehold_racer.tres: failed to load")
		return failures
	if not is_equal_approx(engine.max_speed, 300.0):
		failures.append("engine_freehold_racer: expected max_speed 300.0, got %s" % engine.max_speed)
	if engine.rarity != PartRarity.Tier.RARE:
		failures.append("engine_freehold_racer: expected rarity RARE, got %s" % engine.rarity)

	var paths := [
		"res://resources/engines/engine_standard.tres",
		"res://resources/engines/engine_dominion_heavy.tres",
		"res://resources/engines/engine_dominion_titan.tres",
		"res://resources/engines/engine_freehold_scout.tres",
		"res://resources/engines/engine_freehold_racer.tres",
	]
	for path in paths:
		if not ResourceLoader.exists(path):
			failures.append("EngineCore pool: missing resource %s" % path)
	return failures
```

- [ ] **Step 2: Run tests to verify they fail**

Add both files to `tests/run_tests.gd`'s `_run_all()` list, then run the main headless test command.
Expected: FAIL — `Identifier "ShieldGenerator"/"EngineCore" not declared` and/or missing resource failures.

- [ ] **Step 3: Write minimal implementation**

```gdscript
# scripts/ship/shield_generator.gd
class_name ShieldGenerator
extends Resource

@export var item_name: String = "Standard Shield"
@export var max_shield: float = 25.0
@export var regen_rate: float = 4.0
@export var rarity: PartRarity.Tier = PartRarity.Tier.COMMON
```

```gdscript
# scripts/ship/engine_core.gd
class_name EngineCore
extends Resource

@export var item_name: String = "Standard Engine"
@export var max_speed: float = 200.0
@export var turn_rate: float = 3.0
@export var acceleration: float = 150.0
@export var rarity: PartRarity.Tier = PartRarity.Tier.COMMON
```

Create each `.tres` file in the same format as `resources/weapons/kinetic_cannon.tres`, e.g.:

```
# resources/shields/shield_dominion_bulwark.tres
[gd_resource type="Resource" script_class="ShieldGenerator" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ship/shield_generator.gd" id="1"]

[resource]
script = ExtResource("1")
item_name = "Bulwark Shield"
max_shield = 50.0
regen_rate = 3.0
rarity = 2
```

Repeat for the other 5 shield and 5 engine resources, using these values (`rarity`: 0=COMMON, 1=UNCOMMON, 2=RARE):

| File | item_name | Fields | rarity |
|---|---|---|---|
| shield_standard.tres | Standard Shield | max_shield=25.0, regen_rate=4.0 | 0 |
| shield_light.tres | Light Shield | max_shield=15.0, regen_rate=3.0 | 0 |
| shield_dominion_aegis.tres | Aegis Shield | max_shield=35.0, regen_rate=5.0 | 1 |
| shield_dominion_bulwark.tres | Bulwark Shield | max_shield=50.0, regen_rate=3.0 | 2 |
| shield_freehold_patch.tres | Patch Shield | max_shield=10.0, regen_rate=6.0 | 0 |
| shield_freehold_capacitor.tres | Capacitor Shield | max_shield=18.0, regen_rate=9.0 | 1 |
| engine_standard.tres | Standard Engine | max_speed=200.0, turn_rate=3.0, acceleration=150.0 | 0 |
| engine_dominion_heavy.tres | Heavy Drive | max_speed=180.0, turn_rate=2.5, acceleration=200.0 | 1 |
| engine_dominion_titan.tres | Titan Drive | max_speed=160.0, turn_rate=2.0, acceleration=250.0 | 2 |
| engine_freehold_scout.tres | Scout Drive | max_speed=260.0, turn_rate=4.5, acceleration=170.0 | 1 |
| engine_freehold_racer.tres | Racer Drive | max_speed=300.0, turn_rate=5.0, acceleration=180.0 | 2 |

(Engine `.tres` files reference `res://scripts/ship/engine_core.gd` as their script, same `[gd_resource ... script_class="EngineCore" ...]` shape as above.)

- [ ] **Step 4: Run tests to verify they pass**

Run `--headless --editor --quit` to import the new resources, then the main headless test command.
Expected: `test_shield_generator.gd` and `test_engine_core.gd` report 0 failures.

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/shield_generator.gd scripts/ship/engine_core.gd resources/shields resources/engines tests/test_shield_generator.gd tests/test_engine_core.gd tests/run_tests.gd
git commit -m "Add ShieldGenerator/EngineCore swappable parts and their resource pools"
```

---

### Task 3: ShipType slot/budget bookkeeping

**Files:**
- Modify: `scripts/ship/ship_type.gd`
- Modify: `tests/test_ship_type.gd`

**Interfaces:**
- Consumes: `PartRarity.points_for`/`PartRarity.Tier` (Task 1).
- Produces: `enum SlotType { WEAPON, SHIELD, ENGINE }`, `const LOADOUT_POINTS`, `static func points_budget_for(kind: Kind) -> int`, `static func equipped_path(comp, slot_type, slot_index) -> String`, `static func set_equipped_path(comp, slot_type, slot_index, path) -> void`, `static func points_of_path(path: String) -> int`, `static func points_used(comp: Dictionary) -> int`. `new_composition()` now also sets `weapon_mount_items`, `shield_item`, `engine_item` keys. Tasks 6 (CampaignState), 7 (RefitPanel), and 9 (combat_scene) all call these.

- [ ] **Step 1: Write the failing test additions**

Add to `tests/test_ship_type.gd` (before the final `return failures`):

```gdscript
	if ShipType.points_budget_for(ShipType.Kind.CORVETTE) != 20:
		failures.append("points_budget_for: expected corvette 20, got %s" % ShipType.points_budget_for(ShipType.Kind.CORVETTE))
	if ShipType.points_budget_for(ShipType.Kind.CAPITAL) != 40:
		failures.append("points_budget_for: expected capital 40, got %s" % ShipType.points_budget_for(ShipType.Kind.CAPITAL))

	if comp["weapon_mount_items"] != ["", "", ""]:
		failures.append("new_composition: expected capital weapon_mount_items == 3 empty strings, got %s" % comp["weapon_mount_items"])
	if comp["shield_item"] != "" or comp["engine_item"] != "":
		failures.append("new_composition: expected shield_item/engine_item to default to empty string")

	var test_comp := ShipType.new_composition(ShipType.Kind.CORVETTE)
	if ShipType.equipped_path(test_comp, ShipType.SlotType.WEAPON, 0) != "":
		failures.append("equipped_path: expected empty string for a fresh composition's weapon slot")
	ShipType.set_equipped_path(test_comp, ShipType.SlotType.WEAPON, 0, "res://resources/weapons/railgun.tres")
	if ShipType.equipped_path(test_comp, ShipType.SlotType.WEAPON, 0) != "res://resources/weapons/railgun.tres":
		failures.append("set_equipped_path/equipped_path: expected weapon slot to round-trip the assigned path")
	if ShipType.points_of_path("res://resources/weapons/railgun.tres") != PartRarity.points_for(PartRarity.Tier.RARE):
		failures.append("points_of_path: expected railgun (RARE) to cost %s points, got %s" % [PartRarity.points_for(PartRarity.Tier.RARE), ShipType.points_of_path("res://resources/weapons/railgun.tres")])
	if ShipType.points_used(test_comp) != PartRarity.points_for(PartRarity.Tier.RARE):
		failures.append("points_used: expected a corvette with only a RARE weapon equipped to use exactly that many points, got %s" % ShipType.points_used(test_comp))

	ShipType.set_equipped_path(test_comp, ShipType.SlotType.SHIELD, 0, "res://resources/shields/shield_dominion_aegis.tres")
	if ShipType.equipped_path(test_comp, ShipType.SlotType.SHIELD, 0) != "res://resources/shields/shield_dominion_aegis.tres":
		failures.append("set_equipped_path/equipped_path: expected shield slot to round-trip the assigned path")
```

- [ ] **Step 2: Run test to verify it fails**

Run the main headless test command. Expected: FAIL — `Invalid call. Nonexistent function 'points_budget_for' in base 'RefCounted'` (or similar) for each new call.

- [ ] **Step 3: Write minimal implementation**

In `scripts/ship/ship_type.gd`, add after the existing `WEAPON_POOL` const:

```gdscript
enum SlotType { WEAPON, SHIELD, ENGINE }

const LOADOUT_POINTS := {
	Kind.CORVETTE: 20,
	Kind.FREIGHTER: 15,
	Kind.CAPITAL: 40,
}

static func points_budget_for(kind: Kind) -> int:
	return LOADOUT_POINTS[kind]

static func equipped_path(comp: Dictionary, slot_type: SlotType, slot_index: int) -> String:
	match slot_type:
		SlotType.WEAPON:
			var items: Array = comp.get("weapon_mount_items", [])
			return items[slot_index] if slot_index < items.size() else ""
		SlotType.SHIELD:
			return comp.get("shield_item", "")
		SlotType.ENGINE:
			return comp.get("engine_item", "")
	return ""

static func set_equipped_path(comp: Dictionary, slot_type: SlotType, slot_index: int, path: String) -> void:
	match slot_type:
		SlotType.WEAPON:
			var items: Array = comp.get("weapon_mount_items", [])
			items[slot_index] = path
			comp["weapon_mount_items"] = items
		SlotType.SHIELD:
			comp["shield_item"] = path
		SlotType.ENGINE:
			comp["engine_item"] = path

static func points_of_path(path: String) -> int:
	if path == "":
		return 0
	var item: Resource = load(path)
	return PartRarity.points_for(item.rarity)

static func points_used(comp: Dictionary) -> int:
	var total := 0
	for path in comp.get("weapon_mount_items", []):
		total += points_of_path(path)
	total += points_of_path(comp.get("shield_item", ""))
	total += points_of_path(comp.get("engine_item", ""))
	return total
```

Modify `new_composition()` to also initialize the new keys:

```gdscript
static func new_composition(kind: Kind) -> Dictionary:
	var stats: Dictionary = BASE_STATS[kind]
	var mount_hp: Array[float] = []
	var mount_items: Array[String] = []
	for i in int(stats["weapon_mount_count"]):
		mount_hp.append(stats["weapon_mount_hp"])
		mount_items.append("")
	return {
		"ship_type": kind,
		"max_hp": stats["max_hp"],
		"current_hp": stats["max_hp"],
		"max_shield": stats["max_shield"],
		"current_shield": stats["max_shield"],
		"engine_max_hp": stats["engine_hp"],
		"engine_current_hp": stats["engine_hp"],
		"weapon_mount_max_hp": mount_hp,
		"weapon_mount_current_hp": mount_hp.duplicate(),
		"weapon_mount_items": mount_items,
		"shield_item": "",
		"engine_item": "",
	}
```

- [ ] **Step 4: Run test to verify it passes**

Run the main headless test command. Expected: `test_ship_type.gd` reports 0 failures.

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/ship_type.gd tests/test_ship_type.gd
git commit -m "Add loadout-points budget and equipped-item slot bookkeeping to ShipType"
```

---

### Task 4: RefitCatalog (per-faction shops)

**Files:**
- Create: `scripts/campaign/refit_catalog.gd`
- Test: `tests/test_refit_catalog.gd`

**Interfaces:**
- Consumes: `CampaignFleet.Faction` enum (existing), the 14 existing weapon `.tres` paths, the 11 new shield/engine `.tres` paths (Task 2).
- Produces: `class_name RefitCatalog`, `const HOME_CATALOG/DOMINION_CATALOG/FREEHOLD_CATALOG: Array[String]`, `static func for_faction(faction: CampaignFleet.Faction) -> Array[String]`. Task 8 (campaign_scene wiring) calls `for_faction`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []

	for catalog_name in ["HOME_CATALOG", "DOMINION_CATALOG", "FREEHOLD_CATALOG"]:
		var catalog: Array = RefitCatalog.get(catalog_name)
		if catalog.is_empty():
			failures.append("%s: expected a non-empty catalog" % catalog_name)
		var seen := {}
		for path in catalog:
			if seen.has(path):
				failures.append("%s: duplicate entry %s" % [catalog_name, path])
			seen[path] = true
			if not ResourceLoader.exists(path):
				failures.append("%s: path does not exist: %s" % [catalog_name, path])

	if RefitCatalog.for_faction(CampaignFleet.Faction.DOMINION) != RefitCatalog.DOMINION_CATALOG:
		failures.append("for_faction: expected DOMINION to return DOMINION_CATALOG")
	if RefitCatalog.for_faction(CampaignFleet.Faction.FREEHOLD) != RefitCatalog.FREEHOLD_CATALOG:
		failures.append("for_faction: expected FREEHOLD to return FREEHOLD_CATALOG")
	if RefitCatalog.for_faction(CampaignFleet.Faction.PLAYER) != RefitCatalog.HOME_CATALOG:
		failures.append("for_faction: expected any non-power faction to fall back to HOME_CATALOG")

	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Add to `tests/run_tests.gd`, run the main headless test command.
Expected: FAIL — `Identifier "RefitCatalog" not declared`.

- [ ] **Step 3: Write minimal implementation**

```gdscript
class_name RefitCatalog
extends RefCounted

const HOME_CATALOG: Array[String] = [
	"res://resources/weapons/kinetic_cannon.tres",
	"res://resources/weapons/mass_driver.tres",
	"res://resources/weapons/seeker_missile.tres",
	"res://resources/weapons/pulse_laser.tres",
	"res://resources/weapons/pd_flak_turret.tres",
	"res://resources/shields/shield_standard.tres",
	"res://resources/shields/shield_light.tres",
	"res://resources/engines/engine_standard.tres",
]

const DOMINION_CATALOG: Array[String] = [
	"res://resources/weapons/kinetic_cannon.tres",
	"res://resources/weapons/mass_driver.tres",
	"res://resources/weapons/flak_cannon.tres",
	"res://resources/weapons/railgun.tres",
	"res://resources/weapons/pulse_laser.tres",
	"res://resources/weapons/heavy_beam.tres",
	"res://resources/weapons/disruptor_beam.tres",
	"res://resources/weapons/lance_graser.tres",
	"res://resources/shields/shield_dominion_aegis.tres",
	"res://resources/shields/shield_dominion_bulwark.tres",
	"res://resources/engines/engine_dominion_heavy.tres",
	"res://resources/engines/engine_dominion_titan.tres",
]

const FREEHOLD_CATALOG: Array[String] = [
	"res://resources/weapons/seeker_missile.tres",
	"res://resources/weapons/swarm_missile.tres",
	"res://resources/weapons/torpedo.tres",
	"res://resources/weapons/emp_missile.tres",
	"res://resources/weapons/pd_flak_turret.tres",
	"res://resources/weapons/pd_laser_turret.tres",
	"res://resources/shields/shield_freehold_patch.tres",
	"res://resources/shields/shield_freehold_capacitor.tres",
	"res://resources/engines/engine_freehold_scout.tres",
	"res://resources/engines/engine_freehold_racer.tres",
]

static func for_faction(faction: CampaignFleet.Faction) -> Array[String]:
	match faction:
		CampaignFleet.Faction.DOMINION:
			return DOMINION_CATALOG
		CampaignFleet.Faction.FREEHOLD:
			return FREEHOLD_CATALOG
		_:
			return HOME_CATALOG
```

- [ ] **Step 4: Run test to verify it passes**

Run the main headless test command. Expected: `test_refit_catalog.gd` reports 0 failures.

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/refit_catalog.gd tests/test_refit_catalog.gd tests/run_tests.gd
git commit -m "Add RefitCatalog per-faction part shop inventories"
```

---

### Task 5: CampaignFleet spare-parts inventory

**Files:**
- Modify: `scripts/campaign/campaign_fleet.gd`
- Modify: `tests/test_campaign_fleet.gd`

**Interfaces:**
- Produces: `@export var part_inventory: Array[String] = []`; `cargo_total()` now includes `part_inventory.size()`. Tasks 6/7 read/mutate `fleet.part_inventory` directly.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_campaign_fleet.gd`:

```gdscript
	var parts_fleet := CampaignFleet.new()
	parts_fleet.ship_compositions = [ShipType.new_composition(ShipType.Kind.FREIGHTER)]
	parts_fleet.cargo = {Commodity.Type.ORE: 5.0}
	parts_fleet.part_inventory = ["res://resources/weapons/kinetic_cannon.tres", "res://resources/weapons/mass_driver.tres"]
	if parts_fleet.cargo_total() != 7.0:
		failures.append("cargo_total: expected commodities (5) + part_inventory (2) == 7.0, got %s" % parts_fleet.cargo_total())
```

(Add `const Commodity = preload("res://scripts/campaign/commodity.gd")` at the top of the test file if not already present.)

- [ ] **Step 2: Run test to verify it fails**

Run the main headless test command. Expected: FAIL — `cargo_total` returns `5.0`, not `7.0`.

- [ ] **Step 3: Write minimal implementation**

In `scripts/campaign/campaign_fleet.gd`, add after the existing `cargo` export:

```gdscript
@export var part_inventory: Array[String] = []
```

Modify `cargo_total()`:

```gdscript
func cargo_total() -> float:
	var sum := 0.0
	for amount in cargo.values():
		sum += amount
	sum += part_inventory.size()
	return sum
```

- [ ] **Step 4: Run test to verify it passes**

Run the main headless test command. Expected: `test_campaign_fleet.gd` reports 0 failures.

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_fleet.gd tests/test_campaign_fleet.gd
git commit -m "Add CampaignFleet.part_inventory sharing cargo capacity"
```

---

### Task 6: CampaignState buy_part/sell_part/equip_part

**Files:**
- Modify: `scripts/campaign/campaign_state.gd`
- Modify: `tests/test_campaign_state.gd`

**Interfaces:**
- Consumes: `PartRarity` (Task 1), `ShipType.SlotType`/`points_budget_for`/`points_used`/`points_of_path`/`equipped_path`/`set_equipped_path` (Task 3), `CampaignFleet.part_inventory` (Task 5), existing `CampaignState.is_damaged(comp)`.
- Produces: `func buy_part(path: String, fleet: CampaignFleet) -> bool`, `func sell_part(fleet: CampaignFleet, inventory_index: int) -> bool`, `func equip_part(comp: Dictionary, fleet: CampaignFleet, slot_type: ShipType.SlotType, slot_index: int, inventory_index: int) -> bool`. Task 7 (RefitPanel) calls all three.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_campaign_state.gd`'s `run_async` (or `run`, matching whichever existing section covers `buy`/`sell`/`repair_ship` — place these alongside those):

```gdscript
	campaign_state.reset()
	campaign_state.credits = 1000.0
	var part_fleet := CampaignFleet.new()
	part_fleet.ship_compositions = [ShipType.new_composition(ShipType.Kind.CORVETTE)]

	if not campaign_state.buy_part("res://resources/weapons/railgun.tres", part_fleet):
		failures.append("buy_part: expected buying an affordable, in-capacity part to succeed")
	if part_fleet.part_inventory != ["res://resources/weapons/railgun.tres"]:
		failures.append("buy_part: expected the bought part added to part_inventory, got %s" % part_fleet.part_inventory)
	if not is_equal_approx(campaign_state.credits, 1000.0 - PartRarity.price_for(PartRarity.Tier.RARE)):
		failures.append("buy_part: expected credits debited by the railgun's RARE price, got %s" % campaign_state.credits)

	campaign_state.credits = 0.0
	if campaign_state.buy_part("res://resources/weapons/mass_driver.tres", part_fleet):
		failures.append("buy_part: expected buying to fail with insufficient credits")
	campaign_state.credits = 1000.0

	var credits_before_sell := campaign_state.credits
	if not campaign_state.sell_part(part_fleet, 0):
		failures.append("sell_part: expected selling an owned inventory part to succeed")
	if not part_fleet.part_inventory.is_empty():
		failures.append("sell_part: expected part_inventory emptied after selling its only item")
	if campaign_state.credits <= credits_before_sell:
		failures.append("sell_part: expected credits to increase after selling")
	if campaign_state.sell_part(part_fleet, 0):
		failures.append("sell_part: expected selling an out-of-range index to fail")

	# equip_part: budget enforcement. Corvette budget is 20 points; a RARE
	# weapon (15 points) plus a RARE shield (15 points) would be 30, over budget.
	var corvette_comp: Dictionary = part_fleet.ship_compositions[0]
	part_fleet.part_inventory = ["res://resources/weapons/railgun.tres", "res://resources/shields/shield_dominion_bulwark.tres"]
	if not campaign_state.equip_part(corvette_comp, part_fleet, ShipType.SlotType.WEAPON, 0, 0):
		failures.append("equip_part: expected equipping the RARE railgun (15/20 points) to succeed")
	if ShipType.equipped_path(corvette_comp, ShipType.SlotType.WEAPON, 0) != "res://resources/weapons/railgun.tres":
		failures.append("equip_part: expected the corvette's weapon slot to now hold the railgun")
	if part_fleet.part_inventory.has("res://resources/weapons/railgun.tres"):
		failures.append("equip_part: expected the equipped railgun removed from part_inventory")
	if campaign_state.equip_part(corvette_comp, part_fleet, ShipType.SlotType.SHIELD, 0, 0):
		failures.append("equip_part: expected equipping the RARE shield (would push 15+15=30 > 20 budget) to fail")

	# Swapping a different weapon back into the same slot returns the old one to inventory.
	part_fleet.part_inventory.append("res://resources/weapons/mass_driver.tres")
	if not campaign_state.equip_part(corvette_comp, part_fleet, ShipType.SlotType.WEAPON, 0, part_fleet.part_inventory.find("res://resources/weapons/mass_driver.tres")):
		failures.append("equip_part: expected swapping in the COMMON mass_driver (5 points) to succeed")
	if not part_fleet.part_inventory.has("res://resources/weapons/railgun.tres"):
		failures.append("equip_part: expected the swapped-out railgun returned to part_inventory")

	# equip_part is blocked on a damaged ship.
	corvette_comp["current_hp"] = 1.0
	if campaign_state.equip_part(corvette_comp, part_fleet, ShipType.SlotType.WEAPON, 0, part_fleet.part_inventory.find("res://resources/weapons/railgun.tres")):
		failures.append("equip_part: expected equip to be blocked on a damaged ship")
	corvette_comp["current_hp"] = corvette_comp["max_hp"]

	# equip_part on SHIELD updates max_shield/current_shield proportionally.
	part_fleet.part_inventory.append("res://resources/shields/shield_dominion_aegis.tres")
	var old_max_shield: float = corvette_comp["max_shield"]
	if not campaign_state.equip_part(corvette_comp, part_fleet, ShipType.SlotType.SHIELD, 0, part_fleet.part_inventory.find("res://resources/shields/shield_dominion_aegis.tres")):
		failures.append("equip_part: expected equipping the UNCOMMON aegis shield (10 points, within budget) to succeed")
	if not is_equal_approx(corvette_comp["max_shield"], 35.0):
		failures.append("equip_part: expected max_shield updated to the aegis shield's 35.0, got %s" % corvette_comp["max_shield"])
	if not is_equal_approx(corvette_comp["current_shield"], corvette_comp["max_shield"]):
		failures.append("equip_part: expected current_shield scaled up to the new max (was full before swap)")

	campaign_state.reset()
```

(Add `const PartRarity = preload("res://scripts/ship/part_rarity.gd")` and `const ShipType = preload("res://scripts/ship/ship_type.gd")` near the test file's other preloads if not already globally resolvable in that test's context — check the existing file's top for its preload style and match it.)

- [ ] **Step 2: Run test to verify it fails**

Run the main headless test command. Expected: FAIL — `Invalid call. Nonexistent function 'buy_part'` etc.

- [ ] **Step 3: Write minimal implementation**

Add to `scripts/campaign/campaign_state.gd` (near the existing `buy`/`sell`/`repair_ship` functions):

```gdscript
func buy_part(path: String, fleet: CampaignFleet) -> bool:
	var item: Resource = load(path)
	var price: float = PartRarity.price_for(item.rarity)
	if credits < price or fleet.cargo_total() + 1.0 > fleet.cargo_capacity():
		return false
	credits -= price
	fleet.part_inventory.append(path)
	return true

func sell_part(fleet: CampaignFleet, inventory_index: int) -> bool:
	if inventory_index < 0 or inventory_index >= fleet.part_inventory.size():
		return false
	var path: String = fleet.part_inventory[inventory_index]
	var item: Resource = load(path)
	credits += PartRarity.sell_price_for(item.rarity)
	fleet.part_inventory.remove_at(inventory_index)
	return true

func equip_part(comp: Dictionary, fleet: CampaignFleet, slot_type: ShipType.SlotType, slot_index: int, inventory_index: int) -> bool:
	if is_damaged(comp):
		return false
	if inventory_index < 0 or inventory_index >= fleet.part_inventory.size():
		return false
	var new_path: String = fleet.part_inventory[inventory_index]
	var new_item: Resource = load(new_path)
	var old_path := ShipType.equipped_path(comp, slot_type, slot_index)
	var budget := ShipType.points_budget_for(ShipType.kind_of(comp))
	var projected := ShipType.points_used(comp) - ShipType.points_of_path(old_path) + PartRarity.points_for(new_item.rarity)
	if projected > budget:
		return false
	fleet.part_inventory.remove_at(inventory_index)
	if old_path != "":
		fleet.part_inventory.append(old_path)
	ShipType.set_equipped_path(comp, slot_type, slot_index, new_path)
	if slot_type == ShipType.SlotType.SHIELD:
		var old_max: float = comp["max_shield"]
		comp["max_shield"] = new_item.max_shield
		comp["current_shield"] = new_item.max_shield if old_max <= 0.0 else comp["current_shield"] * (new_item.max_shield / old_max)
	return true
```

- [ ] **Step 4: Run test to verify it passes**

Run the main headless test command. Expected: `test_campaign_state.gd` reports 0 failures.

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_state.gd tests/test_campaign_state.gd
git commit -m "Add CampaignState.buy_part/sell_part/equip_part with loadout-budget enforcement"
```

---

### Task 7: RefitPanel UI (Shop + Equip)

**Files:**
- Create: `scenes/campaign/refit_panel.tscn`, `scripts/campaign/refit_panel.gd`
- Test: `tests/test_refit_panel.gd`

**Interfaces:**
- Consumes: `CampaignState.buy_part/sell_part/equip_part/is_damaged` (Task 6), `CampaignFleet.part_inventory` (Task 5), `ShipType.SlotType/points_budget_for/points_used/equipped_path` (Task 3), `PartRarity.price_for/sell_price_for` (Task 1), `Weapon`/`ShieldGenerator`/`EngineCore` (existing/Task 2).
- Produces: `class_name RefitPanel`, `func open_for(fleet: CampaignFleet, catalog: Array[String]) -> void`, `func close() -> void`, `func refresh() -> void`, `close_button: Button` (onready, for Task 8 to connect externally). Task 8 (campaign_scene wiring) calls `open_for`/`close` and connects `close_button.pressed`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends RefCounted

const RefitPanelScene = preload("res://scenes/campaign/refit_panel.tscn")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()
	campaign_state.credits = 1000.0

	var panel: Control = RefitPanelScene.instantiate()
	tree.root.add_child(panel)
	await tree.process_frame

	if panel.visible:
		failures.append("RefitPanel: expected hidden by default")

	var fleet := CampaignFleet.new()
	fleet.ship_compositions = [ShipType.new_composition(ShipType.Kind.CORVETTE)]
	var catalog: Array[String] = ["res://resources/weapons/mass_driver.tres", "res://resources/shields/shield_dominion_aegis.tres", "res://resources/weapons/lance_graser.tres", "res://resources/shields/shield_light.tres"]

	panel.open_for(fleet, catalog)
	if not panel.visible:
		failures.append("RefitPanel: expected visible after open_for")
	if panel.catalog_rows_container.get_child_count() != catalog.size():
		failures.append("RefitPanel: expected one catalog row per catalog entry, got %d" % panel.catalog_rows_container.get_child_count())

	var buy_row: HBoxContainer = panel.catalog_rows_container.get_child(0)
	var buy_button: Button = buy_row.get_child(1)
	var credits_before := campaign_state.credits
	buy_button.pressed.emit()
	if campaign_state.credits >= credits_before:
		failures.append("RefitPanel: expected pressing Buy to deduct credits")
	if fleet.part_inventory != ["res://resources/weapons/mass_driver.tres"]:
		failures.append("RefitPanel: expected the bought part added to fleet.part_inventory, got %s" % fleet.part_inventory)

	if panel.inventory_rows_container.get_child_count() != 1:
		failures.append("RefitPanel: expected 1 inventory row after buying 1 part, got %d" % panel.inventory_rows_container.get_child_count())

	panel.equip_button.pressed.emit()
	if panel.slots_container.get_child_count() != 3:
		failures.append("RefitPanel: expected 3 equip slot rows for a corvette (1 weapon + shield + engine), got %d" % panel.slots_container.get_child_count())

	var weapon_slot_row: HBoxContainer = panel.slots_container.get_child(0)
	var weapon_equip_button: Button = weapon_slot_row.get_child(2)
	if weapon_equip_button.disabled:
		failures.append("RefitPanel: expected the weapon slot's Equip button enabled with a compatible part in inventory")
	weapon_equip_button.pressed.emit()
	if ShipType.equipped_path(fleet.ship_compositions[0], ShipType.SlotType.WEAPON, 0) != "res://resources/weapons/mass_driver.tres":
		failures.append("RefitPanel: expected pressing Equip to call CampaignState.equip_part and assign the weapon")

	# Budget exclusion: swap the weapon slot to the EPIC lance_graser (20/20
	# points, maxing the corvette's budget), then buy a shield -- it must not
	# appear as an equippable option since 20 + any shield cost > 20.
	var lance_buy_row: HBoxContainer = panel.catalog_rows_container.get_child(2)
	var lance_buy_button: Button = lance_buy_row.get_child(1)
	lance_buy_button.pressed.emit()
	var light_shield_buy_row: HBoxContainer = panel.catalog_rows_container.get_child(3)
	var light_shield_buy_button: Button = light_shield_buy_row.get_child(1)
	light_shield_buy_button.pressed.emit()
	var weapon_slot_row_2: HBoxContainer = panel.slots_container.get_child(0)
	var weapon_picker_2: OptionButton = weapon_slot_row_2.get_child(1)
	for i in weapon_picker_2.item_count:
		if weapon_picker_2.get_item_text(i) == "Lance/Graser":
			weapon_picker_2.selected = i
	var weapon_equip_button_2: Button = weapon_slot_row_2.get_child(2)
	weapon_equip_button_2.pressed.emit()
	if ShipType.equipped_path(fleet.ship_compositions[0], ShipType.SlotType.WEAPON, 0) != "res://resources/weapons/lance_graser.tres":
		failures.append("RefitPanel: expected swapping the weapon slot to the lance_graser to succeed (20/20 points)")
	var shield_slot_row_2: HBoxContainer = panel.slots_container.get_child(1)
	var shield_picker_2: OptionButton = shield_slot_row_2.get_child(1)
	var shield_equip_button_2: Button = shield_slot_row_2.get_child(2)
	if shield_picker_2.item_count != 0 or not shield_equip_button_2.disabled:
		failures.append("RefitPanel: expected the shield slot to exclude an over-budget shield once the weapon slot uses the full 20 points")

	# Damaged ship blocks the Equip tab's buttons.
	fleet.ship_compositions[0]["current_hp"] = 1.0
	panel.refresh()
	var shield_slot_row: HBoxContainer = panel.slots_container.get_child(1)
	var shield_equip_button: Button = shield_slot_row.get_child(2)
	if not shield_equip_button.disabled:
		failures.append("RefitPanel: expected Equip buttons disabled while the selected ship is damaged")

	panel.close()
	if panel.visible:
		failures.append("RefitPanel: expected hidden after close")

	campaign_state.reset()
	panel.queue_free()
	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Add to `tests/run_tests.gd` (as a `run_async` test like `trade_panel_test` — load, not preload, since `refit_panel.gd` will bare-reference `CampaignState`). Run the main headless test command.
Expected: FAIL — scene/script doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

Create `scenes/campaign/refit_panel.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/campaign/refit_panel.gd" id="1"]

[node name="RefitPanel" type="Control"]
offset_left = 720.0
offset_top = 100.0
offset_right = 1220.0
offset_bottom = 460.0
mouse_filter = 2
script = ExtResource("1")

[node name="Background" type="Panel" parent="."]
offset_right = 500.0
offset_bottom = 360.0
mouse_filter = 2

[node name="CreditsLabel" type="Label" parent="."]
offset_left = 14.0
offset_top = 14.0
offset_right = 314.0
offset_bottom = 44.0

[node name="ShopButton" type="Button" parent="."]
offset_left = 14.0
offset_top = 40.0
offset_right = 94.0
offset_bottom = 70.0
text = "Shop"

[node name="EquipButton" type="Button" parent="."]
offset_left = 100.0
offset_top = 40.0
offset_right = 180.0
offset_bottom = 70.0
text = "Equip"

[node name="ShopContainer" type="VBoxContainer" parent="."]
offset_left = 14.0
offset_top = 76.0
offset_right = 486.0
offset_bottom = 300.0

[node name="CatalogRowsContainer" type="VBoxContainer" parent="ShopContainer"]

[node name="InventoryRowsContainer" type="VBoxContainer" parent="ShopContainer"]

[node name="EquipContainer" type="VBoxContainer" parent="."]
visible = false
offset_left = 14.0
offset_top = 76.0
offset_right = 486.0
offset_bottom = 300.0

[node name="ShipSelector" type="OptionButton" parent="EquipContainer"]

[node name="PointsLabel" type="Label" parent="EquipContainer"]

[node name="SlotsContainer" type="VBoxContainer" parent="EquipContainer"]

[node name="CloseButton" type="Button" parent="."]
offset_left = 14.0
offset_top = 306.0
offset_right = 114.0
offset_bottom = 336.0
text = "Close"
```

Create `scripts/campaign/refit_panel.gd`:

```gdscript
class_name RefitPanel
extends Control

var _fleet: CampaignFleet
var _catalog: Array[String] = []
var _selected_ship_index: int = 0

@onready var credits_label: Label = $CreditsLabel
@onready var shop_button: Button = $ShopButton
@onready var equip_button: Button = $EquipButton
@onready var shop_container: VBoxContainer = $ShopContainer
@onready var equip_container: VBoxContainer = $EquipContainer
@onready var catalog_rows_container: VBoxContainer = $ShopContainer/CatalogRowsContainer
@onready var inventory_rows_container: VBoxContainer = $ShopContainer/InventoryRowsContainer
@onready var ship_selector: OptionButton = $EquipContainer/ShipSelector
@onready var points_label: Label = $EquipContainer/PointsLabel
@onready var slots_container: VBoxContainer = $EquipContainer/SlotsContainer
@onready var close_button: Button = $CloseButton

func _ready() -> void:
	close_button.pressed.connect(close)
	shop_button.pressed.connect(_show_shop)
	equip_button.pressed.connect(_show_equip)
	ship_selector.item_selected.connect(_on_ship_selected)
	visible = false
	_show_shop()

func open_for(fleet: CampaignFleet, catalog: Array[String]) -> void:
	_fleet = fleet
	_catalog = catalog
	_selected_ship_index = 0
	visible = true
	_rebuild_ship_selector()
	refresh()

func close() -> void:
	visible = false
	_fleet = null
	_catalog = []

func _show_shop() -> void:
	shop_container.visible = true
	equip_container.visible = false

func _show_equip() -> void:
	shop_container.visible = false
	equip_container.visible = true

func refresh() -> void:
	if _fleet == null:
		return
	credits_label.text = "Credits: %d" % CampaignState.credits
	_rebuild_catalog_rows()
	_rebuild_inventory_rows()
	_rebuild_slot_rows()

func _rebuild_ship_selector() -> void:
	ship_selector.clear()
	for i in _fleet.ship_compositions.size():
		ship_selector.add_item("Ship %d" % (i + 1), i)
	if _selected_ship_index >= _fleet.ship_compositions.size():
		_selected_ship_index = 0

func _on_ship_selected(index: int) -> void:
	_selected_ship_index = index
	refresh()

func _rebuild_catalog_rows() -> void:
	for child in catalog_rows_container.get_children():
		child.queue_free()
	for path in _catalog:
		var item: Resource = load(path)
		var price: float = PartRarity.price_for(item.rarity)
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s  price:%d" % [_item_name(item), price]
		var buy_button := Button.new()
		buy_button.text = "Buy"
		buy_button.disabled = CampaignState.credits < price or _fleet.cargo_total() + 1.0 > _fleet.cargo_capacity()
		buy_button.pressed.connect(_on_buy_pressed.bind(path))
		row.add_child(label)
		row.add_child(buy_button)
		catalog_rows_container.add_child(row)

func _rebuild_inventory_rows() -> void:
	for child in inventory_rows_container.get_children():
		child.queue_free()
	for i in _fleet.part_inventory.size():
		var path: String = _fleet.part_inventory[i]
		var item: Resource = load(path)
		var sell_price: float = PartRarity.sell_price_for(item.rarity)
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s  sell:%d" % [_item_name(item), sell_price]
		var sell_button := Button.new()
		sell_button.text = "Sell"
		sell_button.pressed.connect(_on_sell_pressed.bind(i))
		row.add_child(label)
		row.add_child(sell_button)
		inventory_rows_container.add_child(row)

func _rebuild_slot_rows() -> void:
	for child in slots_container.get_children():
		child.queue_free()
	if _fleet.ship_compositions.is_empty():
		return
	var comp: Dictionary = _fleet.ship_compositions[_selected_ship_index]
	var budget := ShipType.points_budget_for(ShipType.kind_of(comp))
	var used := ShipType.points_used(comp)
	points_label.text = "Points: %d / %d" % [used, budget]
	var damaged := CampaignState.is_damaged(comp)

	var mount_count: int = comp.get("weapon_mount_items", []).size()
	for j in mount_count:
		_add_slot_row(comp, ShipType.SlotType.WEAPON, j, "Weapon %d" % (j + 1), Weapon, damaged, budget, used)
	_add_slot_row(comp, ShipType.SlotType.SHIELD, 0, "Shield", ShieldGenerator, damaged, budget, used)
	_add_slot_row(comp, ShipType.SlotType.ENGINE, 0, "Engine", EngineCore, damaged, budget, used)

func _add_slot_row(comp: Dictionary, slot_type: ShipType.SlotType, slot_index: int, label_text: String, item_class: Script, damaged: bool, budget: int, used: int) -> void:
	var equipped_path := ShipType.equipped_path(comp, slot_type, slot_index)
	var equipped_name := "stock" if equipped_path == "" else _item_name(load(equipped_path))
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "%s: %s" % [label_text, equipped_name]
	var picker := OptionButton.new()
	var remaining_without_slot := used - ShipType.points_of_path(equipped_path)
	var compatible_indices: Array[int] = []
	for i in _fleet.part_inventory.size():
		var candidate: Resource = load(_fleet.part_inventory[i])
		if is_instance_of(candidate, item_class) and remaining_without_slot + PartRarity.points_for(candidate.rarity) <= budget:
			picker.add_item(_item_name(candidate))
			compatible_indices.append(i)
	var equip_btn := Button.new()
	equip_btn.text = "Equip"
	equip_btn.disabled = damaged or compatible_indices.is_empty()
	equip_btn.pressed.connect(_on_equip_pressed.bind(slot_type, slot_index, picker, compatible_indices))
	row.add_child(label)
	row.add_child(picker)
	row.add_child(equip_btn)
	slots_container.add_child(row)

func _item_name(item: Resource) -> String:
	if item is Weapon:
		return item.weapon_name
	return item.item_name

func _on_buy_pressed(path: String) -> void:
	CampaignState.buy_part(path, _fleet)
	refresh()

func _on_sell_pressed(inventory_index: int) -> void:
	CampaignState.sell_part(_fleet, inventory_index)
	refresh()

func _on_equip_pressed(slot_type: ShipType.SlotType, slot_index: int, picker: OptionButton, compatible_indices: Array[int]) -> void:
	if picker.selected < 0 or picker.selected >= compatible_indices.size():
		return
	var inventory_index: int = compatible_indices[picker.selected]
	var comp: Dictionary = _fleet.ship_compositions[_selected_ship_index]
	CampaignState.equip_part(comp, _fleet, slot_type, slot_index, inventory_index)
	refresh()
```

Note: in the test above, `weapon_equip_button.pressed.emit()` relies on the picker defaulting to `selected == 0` (the first and only compatible item) when an `OptionButton` has exactly one item added — Godot auto-selects index 0 in that case, so no extra selection step is needed in the test.

- [ ] **Step 4: Run test to verify it passes**

Run `--headless --editor --quit` then the main headless test command. Expected: `test_refit_panel.gd` reports 0 failures.

- [ ] **Step 5: Commit**

```bash
git add scenes/campaign/refit_panel.tscn scripts/campaign/refit_panel.gd tests/test_refit_panel.gd tests/run_tests.gd
git commit -m "Add RefitPanel Shop/Equip UI"
```

---

### Task 8: Wire RefitPanel into CampaignScene

**Files:**
- Modify: `scenes/campaign/campaign_scene.tscn`, `scripts/campaign/campaign_scene.gd`
- Modify: `tests/test_campaign_scene_trading.gd`

**Interfaces:**
- Consumes: `RefitPanel.open_for/close/close_button` (Task 7), `RefitCatalog.for_faction/HOME_CATALOG` (Task 4).
- Produces: `campaign_scene.gd` now opens/closes `RefitPanel` alongside `TradePanel` whenever the player docks, picking the catalog via a new `_catalog_for_base(area: Area2D) -> Array[String]` helper.

- [ ] **Step 1: Write the failing test addition**

Add to `tests/test_campaign_scene_trading.gd`, right after the existing "expected TradePanel visible after docking at HomeBase" check (reusing that same dock-at-HomeBase state):

```gdscript
	var refit_panel: RefitPanel = scene.get_node("UILayer/RefitPanel")
	if not refit_panel.visible:
		failures.append("expected RefitPanel visible after docking at HomeBase")
```

And right after the existing "expected TradePanel hidden after leaving HomeBase" check:

```gdscript
	if refit_panel.visible:
		failures.append("expected RefitPanel hidden after leaving HomeBase")
```

- [ ] **Step 2: Run test to verify it fails**

Run the main headless test command. Expected: FAIL — `Node not found: "UILayer/RefitPanel"`.

- [ ] **Step 3: Write minimal implementation**

In `scenes/campaign/campaign_scene.tscn`, bump `load_steps=4` to `load_steps=5`, add after the existing `id="4"` ext_resource line:

```
[ext_resource type="PackedScene" path="res://scenes/campaign/refit_panel.tscn" id="5"]
```

Add after the existing `[node name="TradePanel" ...]` line:

```
[node name="RefitPanel" type="Control" parent="UILayer" instance=ExtResource("5")]
```

In `scripts/campaign/campaign_scene.gd`:

Add the `@onready` next to the existing `trade_panel`/`loot_panel` ones:

```gdscript
@onready var refit_panel: RefitPanel = $UILayer/RefitPanel
```

Replace the line `trade_panel.close_button.pressed.connect(_on_trade_panel_closed)` in `_ready()` with:

```gdscript
	trade_panel.close_button.pressed.connect(_on_docking_panel_closed)
	refit_panel.close_button.pressed.connect(_on_docking_panel_closed)
```

Rename `_on_trade_panel_closed` to `_on_docking_panel_closed` and have it close both panels:

```gdscript
func _on_docking_panel_closed() -> void:
	trade_panel.close()
	refit_panel.close()
	get_tree().paused = false
	_travel_target = null
```

In `_trigger_arrival`, change the `HomeBase`/`FactionBase` branch to also open the refit panel:

```gdscript
	elif area is HomeBase or area is FactionBase:
		var economy := _economy_for_base(area)
		if economy != null:
			trade_panel.open_for(economy, CampaignState.player_fleet)
			refit_panel.open_for(CampaignState.player_fleet, _catalog_for_base(area))
			get_tree().paused = true
			_travel_target = null
```

In `_on_player_area_exited`, change the `HomeBase`/`FactionBase` branch:

```gdscript
	elif area is HomeBase or area is FactionBase:
		trade_panel.close()
		refit_panel.close()
		get_tree().paused = false
```

Add the new helper near `_economy_for_base`:

```gdscript
func _catalog_for_base(area: Area2D) -> Array[String]:
	if area is FactionBase:
		return RefitCatalog.for_faction(area.faction_enum)
	return RefitCatalog.HOME_CATALOG
```

- [ ] **Step 4: Run test to verify it passes**

Run `--headless --editor --quit` then the main headless test command. Expected: `test_campaign_scene_trading.gd` and the full suite report 0 failures.

- [ ] **Step 5: Commit**

```bash
git add scenes/campaign/campaign_scene.tscn scripts/campaign/campaign_scene.gd tests/test_campaign_scene_trading.gd
git commit -m "Open RefitPanel alongside TradePanel when docked, using the base's faction catalog"
```

---

### Task 9: Combat integration — equipped parts apply in battle and round-trip back

**Files:**
- Modify: `scripts/combat/combat_scene.gd`
- Modify: `tests/test_combat_scene.gd`

**Interfaces:**
- Consumes: `ShieldGenerator`/`EngineCore` (Task 2), `comp["weapon_mount_items"]/["shield_item"]/["engine_item"]` (Task 3).
- Produces: `_apply_fleet_data` now applies equipped weapon/shield/engine items onto the live `Ship` node; `_collect_survivor_data` (signature changed to take the original compositions array) now carries equipped item paths back into the returned dict; `_report_to_campaign` passes the original compositions through.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_combat_scene.gd`, right after the existing "campaign battle" setup block builds `player_fleet`/`enemy_fleet` but before `campaign_state.player_fleet = player_fleet` — extend the player composition's dict literal (in place of the existing one) to:

```gdscript
	var player_fleet := CampaignFleet.new()
	player_fleet.ship_compositions = [{
		"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0,
		"engine_max_hp": 25.0, "engine_current_hp": 5.0,
		"weapon_mount_max_hp": [15.0], "weapon_mount_current_hp": [3.0],
		"weapon_mount_items": ["res://resources/weapons/railgun.tres"],
		"shield_item": "res://resources/shields/shield_dominion_aegis.tres",
		"engine_item": "res://resources/engines/engine_freehold_racer.tres",
	}]
```

Then, right after the existing "spawned_player.engine.current_hp carried over" checks, add:

```gdscript
	if spawned_player.weapon_mounts[0].weapon == null or spawned_player.weapon_mounts[0].weapon.weapon_name != "Railgun":
		failures.append("campaign battle: expected the equipped railgun applied to the spawned player's weapon mount")
	if not is_equal_approx(spawned_player.shield.max_shield, 35.0):
		failures.append("campaign battle: expected the equipped aegis shield's max_shield (35.0) applied, got %s" % spawned_player.shield.max_shield)
	if not is_equal_approx(spawned_player.engine.max_speed, 300.0):
		failures.append("campaign battle: expected the equipped racer engine's max_speed (300.0) applied, got %s" % spawned_player.engine.max_speed)
```

And right after the existing "surviving player ship's composition to carry ship_type CORVETTE back" check, add (inside the `else` branch that already has `surviving_comp`):

```gdscript
		if surviving_comp.get("weapon_mount_items", []) != ["res://resources/weapons/railgun.tres"]:
			failures.append("campaign battle: expected equipped weapon item path carried back into the surviving composition, got %s" % surviving_comp.get("weapon_mount_items"))
		if surviving_comp.get("shield_item", "") != "res://resources/shields/shield_dominion_aegis.tres":
			failures.append("campaign battle: expected equipped shield item path carried back into the surviving composition")
		if surviving_comp.get("engine_item", "") != "res://resources/engines/engine_freehold_racer.tres":
			failures.append("campaign battle: expected equipped engine item path carried back into the surviving composition")
```

- [ ] **Step 2: Run test to verify it fails**

Run the main headless test command. Expected: FAIL — `spawned_player.weapon_mounts[0].weapon` is whatever the scene's default/randomized loadout assigned, not the railgun; shield/engine stats are unchanged from scene defaults.

- [ ] **Step 3: Write minimal implementation**

In `scripts/combat/combat_scene.gd`, modify `_apply_fleet_data`:

```gdscript
func _apply_fleet_data(ships: Array[Ship], fleet_data: CampaignFleet) -> void:
	for i in ships.size():
		var comp: Dictionary = fleet_data.ship_compositions[i]
		ships[i].hull.max_hp = comp["max_hp"]
		ships[i].hull.current_hp = comp["current_hp"]
		ships[i].shield.max_shield = comp["max_shield"]
		ships[i].shield.current_shield = comp["current_shield"]
		if comp.get("shield_item", "") != "":
			var shield_item: ShieldGenerator = load(comp["shield_item"])
			ships[i].shield.max_shield = shield_item.max_shield
			ships[i].shield.regen_rate = shield_item.regen_rate
		if comp.has("engine_max_hp"):
			ships[i].engine.max_hp = comp["engine_max_hp"]
			ships[i].engine.current_hp = comp["engine_current_hp"]
		if comp.get("engine_item", "") != "":
			var engine_item: EngineCore = load(comp["engine_item"])
			ships[i].engine.max_speed = engine_item.max_speed
			ships[i].engine.turn_rate = engine_item.turn_rate
			ships[i].engine.acceleration = engine_item.acceleration
		if comp.has("weapon_mount_max_hp"):
			var mount_max: Array = comp["weapon_mount_max_hp"]
			var mount_cur: Array = comp["weapon_mount_current_hp"]
			for j in ships[i].weapon_mounts.size():
				if j < mount_max.size():
					ships[i].weapon_mounts[j].max_hp = mount_max[j]
					ships[i].weapon_mounts[j].current_hp = mount_cur[j]
		var mount_items: Array = comp.get("weapon_mount_items", [])
		for j in ships[i].weapon_mounts.size():
			if j < mount_items.size() and mount_items[j] != "":
				ships[i].weapon_mounts[j].weapon = load(mount_items[j])
```

Modify `_collect_survivor_data` to take the original compositions and carry the item paths forward:

```gdscript
func _collect_survivor_data(ships: Array[Ship], original_compositions: Array[Dictionary]) -> Array[Dictionary]:
	var survivors: Array[Dictionary] = []
	for i in ships.size():
		var ship := ships[i]
		if is_instance_valid(ship) and not ship.hull.is_destroyed():
			var mount_max: Array[float] = []
			var mount_cur: Array[float] = []
			var mount_items: Array[String] = []
			for mount in ship.weapon_mounts:
				mount_max.append(mount.max_hp)
				mount_cur.append(mount.current_hp)
				mount_items.append(mount.weapon.resource_path if mount.weapon != null else "")
			survivors.append({
				"ship_type": ship.ship_type,
				"max_hp": ship.hull.max_hp,
				"current_hp": ship.hull.current_hp,
				"max_shield": ship.shield.max_shield,
				"current_shield": ship.shield.current_shield,
				"engine_max_hp": ship.engine.max_hp,
				"engine_current_hp": ship.engine.current_hp,
				"weapon_mount_max_hp": mount_max,
				"weapon_mount_current_hp": mount_cur,
				"weapon_mount_items": mount_items,
				"shield_item": original_compositions[i].get("shield_item", ""),
				"engine_item": original_compositions[i].get("engine_item", ""),
			})
	return survivors
```

Update `_report_to_campaign` to pass the original compositions:

```gdscript
func _report_to_campaign() -> void:
	CampaignState.resolve_engagement(
		_collect_survivor_data(player_ships, CampaignState.player_fleet.ship_compositions),
		_collect_survivor_data(enemy_ships, CampaignState.active_enemy_fleet.ship_compositions)
	)
	if CampaignState.player_fleet == null:
		return
	if CampaignState.player_fleet.is_destroyed():
		get_tree().change_scene_to_file("res://scenes/ui/game_over.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/campaign/campaign_scene.tscn")
```

- [ ] **Step 4: Run test to verify it passes**

Run the main headless test command. Expected: `test_combat_scene.gd` reports 0 failures.

- [ ] **Step 5: Commit**

```bash
git add scripts/combat/combat_scene.gd tests/test_combat_scene.gd
git commit -m "Carry equipped weapon/shield/engine items into and out of combat"
```

---

### Task 10: Full-suite regression pass

**Files:**
- None (verification only), plus any small fixes discovered.

**Interfaces:**
- None new.

- [ ] **Step 1: Run the full headless suite**

Run: `& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --editor --quit --path .` (warm the cache for everything added across Tasks 1-9), then:
`& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd > test_output.log`
(redirect straight to a file rather than piping through another command — piping can look like a 10+ minute hang from buffering even when the run has already finished).

- [ ] **Step 2: Read the log and confirm**

Read `test_output.log`. Expected: `All tests passed.` or only the pre-existing, known-flaky `test_campaign_long_run_sim.gd` pirate-targeting failures (5-6, varies with wander RNG) — no new failures from this plan's work.

- [ ] **Step 3: Fix any genuinely new failures**

If a failure traces to this plan's changes (not the pre-existing flake above), fix it in the relevant task's files and re-run. Do not touch `test_campaign_long_run_sim.gd`'s known flake.

- [ ] **Step 4: Delete the temporary log**

```bash
rm test_output.log
```

- [ ] **Step 5: Commit (only if Step 3 required fixes)**

```bash
git add -A
git commit -m "Fix regressions found in ship refit/customization full-suite pass"
```
