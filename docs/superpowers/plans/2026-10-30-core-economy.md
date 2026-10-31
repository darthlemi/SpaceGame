# Core Economy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give map bases a production/consumption economy that drives local
commodity prices, and let the player haul cargo between bases to buy low /
sell high.

**Architecture:** Three new plain-data/logic classes (`Commodity`,
`EconomyRole`, `BaseEconomy`) carry the simulation; `CampaignState` (the
existing autoload) owns `credits`, a `home_base_economy`, and the tick
orchestration/buy/sell API, mirroring how it already owns `factions` and
`active_skirmishes`. `PowerFaction` gains an `economy` field so Dominion/
Freehold carry their own `BaseEconomy`. `CampaignFleet` gains a `cargo`
dictionary and capacity. A new `TradePanel` UI, wired into
`CampaignScene`'s existing dock-detection handlers, lets the player buy/
sell at HomeBase or either faction base.

**Tech Stack:** Godot 4.7, GDScript. Tests follow the existing repo
convention: plain `RefCounted` test scripts under `tests/` exposing
`static func run() -> Array[String]` (synchronous, no scene tree needed)
or `static func run_async(tree: SceneTree) -> Array[String]` (needs a live
tree/frames), registered by hand in `tests/run_tests.gd`. Run the full
suite via `godot --headless --script tests/run_tests.gd`.

## Global Constraints

- Six commodities: `ORE, FOOD, FUEL, HULL_PARTS, WEAPONS, LUXURY_GOODS`.
  Only `ORE, FOOD, FUEL, WEAPONS` are produced/consumed by any role this
  milestone; `HULL_PARTS`/`LUXURY_GOODS` exist in the enum/price table
  only.
- Fixed role catalog: `MINING` (produces Ore), `AGRICULTURE` (produces
  Food), `INDUSTRIAL` (consumes Ore+Fuel, produces Weapons), `POPULATION`
  (consumes Food), `TRADE_HUB` (no production/consumption).
- HomeBase = `[TRADE_HUB]`, max_slots 1, never decays. Dominion =
  `[INDUSTRIAL, POPULATION]`, max_slots 2. Freehold = `[MINING,
  AGRICULTURE]`, max_slots 2.
- Economy tick interval: `5.0` seconds of real time, independent of the
  physics-delta skirmish ticking that already exists.
- Deficit streak threshold: `5` consecutive under-stocked ticks for a slot
  removes the base's last slot (lowest priority) and resets all streaks.
- Price bands (ratio of stock to a per-commodity target): `<20% -> 1.6x`,
  `20-60% -> 1.3x`, `60-140% -> 1.0x`, `140-180% -> 0.8x`, `>180% -> 0.6x`.
  `sell_price = buy_price * 0.8`.
- Player starts with `500.0` credits (`CampaignState.credits`).
- Cargo capacity: `20.0` units per ship in the fleet
  (`CampaignFleet.cargo_capacity()`); buy/sell moves 1 unit per click.
- Docking at HomeBase or a FactionBase auto-opens the trade panel; leaving
  closes it. Mirrors the existing `EngagePrompt` show/hide pattern already
  in `campaign_scene.gd`.

---

### Task 1: Commodity catalog

**Files:**
- Create: `scripts/campaign/commodity.gd`
- Test: `tests/test_commodity.gd`
- Modify: `tests/run_tests.gd` (register the new test)

**Interfaces:**
- Produces: `class_name Commodity extends RefCounted`, `enum Type {ORE,
  FOOD, FUEL, HULL_PARTS, WEAPONS, LUXURY_GOODS}`, `const BASE_PRICE:
  Dictionary` (Type -> float), `const TARGET_STOCK: Dictionary` (Type ->
  float), `const NAMES: Dictionary` (Type -> String). All later tasks key
  their dictionaries by `Commodity.Type.<X>` ints and look up prices/
  targets/names through these three consts.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_commodity.gd
extends RefCounted

const Commodity = preload("res://scripts/campaign/commodity.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var all_types: Array = Commodity.Type.values()
	if all_types.size() != 6:
		failures.append("Commodity.Type: expected 6 commodities, got %d" % all_types.size())

	for t in all_types:
		if not Commodity.BASE_PRICE.has(t):
			failures.append("Commodity.BASE_PRICE: missing entry for type %s" % t)
		if not Commodity.TARGET_STOCK.has(t):
			failures.append("Commodity.TARGET_STOCK: missing entry for type %s" % t)
		if not Commodity.NAMES.has(t):
			failures.append("Commodity.NAMES: missing entry for type %s" % t)

	if Commodity.BASE_PRICE[Commodity.Type.ORE] != 10.0:
		failures.append("Commodity.BASE_PRICE: expected ORE == 10.0, got %s" % Commodity.BASE_PRICE[Commodity.Type.ORE])
	if Commodity.NAMES[Commodity.Type.HULL_PARTS] != "Hull Parts":
		failures.append("Commodity.NAMES: expected HULL_PARTS == 'Hull Parts', got %s" % Commodity.NAMES[Commodity.Type.HULL_PARTS])

	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script tests/run_tests.gd` (the new test isn't
registered yet, so instead run a quick one-off check that the file is
missing by trying to open it in the editor, or simply trust step 4's
registration+run to prove it — Godot has no single-file test runner here).
Confirm `scripts/campaign/commodity.gd` does not exist yet:

Run: `test -f scripts/campaign/commodity.gd && echo EXISTS || echo MISSING`
Expected: `MISSING`

- [ ] **Step 3: Write minimal implementation**

```gdscript
# scripts/campaign/commodity.gd
class_name Commodity
extends RefCounted

enum Type { ORE, FOOD, FUEL, HULL_PARTS, WEAPONS, LUXURY_GOODS }

const BASE_PRICE := {
	Type.ORE: 10.0,
	Type.FOOD: 8.0,
	Type.FUEL: 12.0,
	Type.HULL_PARTS: 40.0,
	Type.WEAPONS: 60.0,
	Type.LUXURY_GOODS: 50.0,
}

const TARGET_STOCK := {
	Type.ORE: 100.0,
	Type.FOOD: 100.0,
	Type.FUEL: 100.0,
	Type.HULL_PARTS: 40.0,
	Type.WEAPONS: 40.0,
	Type.LUXURY_GOODS: 40.0,
}

const NAMES := {
	Type.ORE: "Ore",
	Type.FOOD: "Food",
	Type.FUEL: "Fuel",
	Type.HULL_PARTS: "Hull Parts",
	Type.WEAPONS: "Weapons",
	Type.LUXURY_GOODS: "Luxury Goods",
}
```

- [ ] **Step 4: Register the test and run the full suite**

Add to `tests/run_tests.gd`, inside the `test_scripts` array (alongside the
other synchronous tests, e.g. right after
`preload("res://tests/test_power_faction.gd"),`):

```gdscript
		preload("res://tests/test_commodity.gd"),
```

Run: `godot --headless --script tests/run_tests.gd`
Expected: `All tests passed.` (exit code 0)

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/commodity.gd tests/test_commodity.gd tests/run_tests.gd
git commit -m "Add Commodity catalog for the core economy"
```

---

### Task 2: EconomyRole catalog

**Files:**
- Create: `scripts/campaign/economy_role.gd`
- Test: `tests/test_economy_role.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: `Commodity.Type` from Task 1.
- Produces: `class_name EconomyRole extends Resource`, `enum RoleType
  {MINING, AGRICULTURE, INDUSTRIAL, POPULATION, TRADE_HUB}`, instance
  fields `role_type: RoleType`, `produces: Dictionary` (Commodity.Type ->
  float), `consumes: Dictionary` (Commodity.Type -> float), and five
  static factories: `EconomyRole.mining()`, `.agriculture()`,
  `.industrial()`, `.population()`, `.trade_hub()`, each returning a new
  configured `EconomyRole`. Task 3's `BaseEconomy.tick()` iterates
  `slot.produces` / `slot.consumes` on whatever these factories return.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_economy_role.gd
extends RefCounted

const EconomyRole = preload("res://scripts/campaign/economy_role.gd")
const Commodity = preload("res://scripts/campaign/commodity.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var mining := EconomyRole.mining()
	if mining.role_type != EconomyRole.RoleType.MINING:
		failures.append("mining: expected role_type MINING, got %s" % mining.role_type)
	if mining.produces.get(Commodity.Type.ORE, 0.0) <= 0.0:
		failures.append("mining: expected it to produce Ore")
	if not mining.consumes.is_empty():
		failures.append("mining: expected no consumption")

	var agriculture := EconomyRole.agriculture()
	if agriculture.produces.get(Commodity.Type.FOOD, 0.0) <= 0.0:
		failures.append("agriculture: expected it to produce Food")

	var industrial := EconomyRole.industrial()
	if industrial.role_type != EconomyRole.RoleType.INDUSTRIAL:
		failures.append("industrial: expected role_type INDUSTRIAL, got %s" % industrial.role_type)
	if industrial.consumes.get(Commodity.Type.ORE, 0.0) <= 0.0 or industrial.consumes.get(Commodity.Type.FUEL, 0.0) <= 0.0:
		failures.append("industrial: expected it to consume Ore and Fuel")
	if industrial.produces.get(Commodity.Type.WEAPONS, 0.0) <= 0.0:
		failures.append("industrial: expected it to produce Weapons")

	var population := EconomyRole.population()
	if population.consumes.get(Commodity.Type.FOOD, 0.0) <= 0.0:
		failures.append("population: expected it to consume Food")
	if not population.produces.is_empty():
		failures.append("population: expected no production")

	var trade_hub := EconomyRole.trade_hub()
	if trade_hub.role_type != EconomyRole.RoleType.TRADE_HUB:
		failures.append("trade_hub: expected role_type TRADE_HUB, got %s" % trade_hub.role_type)
	if not trade_hub.produces.is_empty() or not trade_hub.consumes.is_empty():
		failures.append("trade_hub: expected no production or consumption")

	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Run: `test -f scripts/campaign/economy_role.gd && echo EXISTS || echo MISSING`
Expected: `MISSING`

- [ ] **Step 3: Write minimal implementation**

```gdscript
# scripts/campaign/economy_role.gd
class_name EconomyRole
extends Resource

enum RoleType { MINING, AGRICULTURE, INDUSTRIAL, POPULATION, TRADE_HUB }

@export var role_type: RoleType = RoleType.TRADE_HUB
@export var produces: Dictionary = {}
@export var consumes: Dictionary = {}

static func mining() -> EconomyRole:
	var role := EconomyRole.new()
	role.role_type = RoleType.MINING
	role.produces = {Commodity.Type.ORE: 5.0}
	return role

static func agriculture() -> EconomyRole:
	var role := EconomyRole.new()
	role.role_type = RoleType.AGRICULTURE
	role.produces = {Commodity.Type.FOOD: 5.0}
	return role

static func industrial() -> EconomyRole:
	var role := EconomyRole.new()
	role.role_type = RoleType.INDUSTRIAL
	role.consumes = {Commodity.Type.ORE: 3.0, Commodity.Type.FUEL: 2.0}
	role.produces = {Commodity.Type.WEAPONS: 2.0}
	return role

static func population() -> EconomyRole:
	var role := EconomyRole.new()
	role.role_type = RoleType.POPULATION
	role.consumes = {Commodity.Type.FOOD: 4.0}
	return role

static func trade_hub() -> EconomyRole:
	var role := EconomyRole.new()
	role.role_type = RoleType.TRADE_HUB
	return role
```

- [ ] **Step 4: Register the test and run the full suite**

Add to `tests/run_tests.gd`'s `test_scripts` array:

```gdscript
		preload("res://tests/test_economy_role.gd"),
```

Run: `godot --headless --script tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/economy_role.gd tests/test_economy_role.gd tests/run_tests.gd
git commit -m "Add EconomyRole catalog (mining/agriculture/industrial/population/trade hub)"
```

---

### Task 3: BaseEconomy — production, consumption, deficit decay

**Files:**
- Create: `scripts/campaign/base_economy.gd`
- Test: `tests/test_base_economy.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: `EconomyRole` (Task 2), `Commodity.Type` (Task 1).
- Produces: `class_name BaseEconomy extends Resource` with `slots:
  Array[EconomyRole]`, `max_slots: int`, `stock: Dictionary`
  (Commodity.Type -> float), `deficit_streaks: Dictionary` (slot index int
  -> int), `const DEFICIT_STREAK_THRESHOLD := 5`, and `func tick() ->
  void`. Task 4 adds `price_for`/`sell_price_for` to this same file/class.
  Task 6's `CampaignState.tick_economy` calls `.tick()` on instances of
  this class.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_base_economy.gd
extends RefCounted

const BaseEconomy = preload("res://scripts/campaign/base_economy.gd")
const EconomyRole = preload("res://scripts/campaign/economy_role.gd")
const Commodity = preload("res://scripts/campaign/commodity.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	# Production: a MINING slot adds Ore to stock each tick.
	var mining_base := BaseEconomy.new()
	mining_base.slots = [EconomyRole.mining()]
	mining_base.max_slots = 1
	mining_base.tick()
	if mining_base.stock.get(Commodity.Type.ORE, 0.0) != 5.0:
		failures.append("tick: expected MINING to add 5.0 Ore, got %s" % mining_base.stock.get(Commodity.Type.ORE, 0.0))

	# Consumption: INDUSTRIAL draws down Ore/Fuel and adds Weapons when stocked.
	var industrial_base := BaseEconomy.new()
	industrial_base.slots = [EconomyRole.industrial()]
	industrial_base.max_slots = 1
	industrial_base.stock = {Commodity.Type.ORE: 10.0, Commodity.Type.FUEL: 10.0}
	industrial_base.tick()
	if industrial_base.stock.get(Commodity.Type.ORE, 0.0) != 7.0:
		failures.append("tick: expected Ore drawn down to 7.0, got %s" % industrial_base.stock.get(Commodity.Type.ORE, 0.0))
	if industrial_base.stock.get(Commodity.Type.FUEL, 0.0) != 8.0:
		failures.append("tick: expected Fuel drawn down to 8.0, got %s" % industrial_base.stock.get(Commodity.Type.FUEL, 0.0))
	if industrial_base.stock.get(Commodity.Type.WEAPONS, 0.0) != 2.0:
		failures.append("tick: expected Weapons produced to 2.0, got %s" % industrial_base.stock.get(Commodity.Type.WEAPONS, 0.0))
	if industrial_base.deficit_streaks.get(0, 0) != 0:
		failures.append("tick: expected deficit streak reset to 0 when fully stocked")

	# Deficit: insufficient input drains that slot's inputs to 0 and increments its streak.
	var starved_base := BaseEconomy.new()
	starved_base.slots = [EconomyRole.industrial()]
	starved_base.max_slots = 1
	starved_base.stock = {Commodity.Type.ORE: 1.0, Commodity.Type.FUEL: 10.0}
	starved_base.tick()
	if starved_base.stock.get(Commodity.Type.ORE, 0.0) != 0.0:
		failures.append("tick: expected Ore drained to 0.0 on deficit, got %s" % starved_base.stock.get(Commodity.Type.ORE, 0.0))
	if starved_base.stock.get(Commodity.Type.FUEL, 0.0) != 0.0:
		failures.append("tick: expected Fuel also drained to 0.0 (same slot) on deficit, got %s" % starved_base.stock.get(Commodity.Type.FUEL, 0.0))
	if starved_base.stock.get(Commodity.Type.WEAPONS, 0.0) != 0.0:
		failures.append("tick: expected no Weapons produced on a deficit tick")
	if starved_base.deficit_streaks.get(0, 0) != 1:
		failures.append("tick: expected deficit streak == 1 after one starved tick, got %s" % starved_base.deficit_streaks.get(0, 0))

	# Slot removal: 5 consecutive starved ticks removes the last slot and resets streaks.
	var decaying_base := BaseEconomy.new()
	decaying_base.slots = [EconomyRole.mining(), EconomyRole.population()]
	decaying_base.max_slots = 2
	decaying_base.stock = {}
	for i in 5:
		decaying_base.tick()
	if decaying_base.slots.size() != 1:
		failures.append("tick: expected the last slot removed after 5 consecutive deficits, got %d slots" % decaying_base.slots.size())
	if decaying_base.deficit_streaks.values().any(func(v): return v != 0):
		failures.append("tick: expected all deficit streaks reset to 0 after a slot is removed")

	# TRADE_HUB (no production/consumption) never decays regardless of ticks.
	var trade_hub_base := BaseEconomy.new()
	trade_hub_base.slots = [EconomyRole.trade_hub()]
	trade_hub_base.max_slots = 1
	for i in 10:
		trade_hub_base.tick()
	if trade_hub_base.slots.size() != 1:
		failures.append("tick: expected TRADE_HUB slot to never decay, got %d slots" % trade_hub_base.slots.size())

	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Run: `test -f scripts/campaign/base_economy.gd && echo EXISTS || echo MISSING`
Expected: `MISSING`

- [ ] **Step 3: Write minimal implementation**

```gdscript
# scripts/campaign/base_economy.gd
class_name BaseEconomy
extends Resource

const DEFICIT_STREAK_THRESHOLD := 5

@export var slots: Array[EconomyRole] = []
@export var max_slots: int = 2
var stock: Dictionary = {}
var deficit_streaks: Dictionary = {}

func tick() -> void:
	for slot in slots:
		for commodity in slot.produces:
			stock[commodity] = stock.get(commodity, 0.0) + slot.produces[commodity]

	for i in slots.size():
		var slot: EconomyRole = slots[i]
		if slot.consumes.is_empty():
			continue
		var can_afford := true
		for commodity in slot.consumes:
			if stock.get(commodity, 0.0) < slot.consumes[commodity]:
				can_afford = false
				break
		if can_afford:
			for commodity in slot.consumes:
				stock[commodity] = stock.get(commodity, 0.0) - slot.consumes[commodity]
			deficit_streaks[i] = 0
		else:
			for commodity in slot.consumes:
				stock[commodity] = 0.0
			deficit_streaks[i] = deficit_streaks.get(i, 0) + 1
			if deficit_streaks[i] >= DEFICIT_STREAK_THRESHOLD:
				slots.remove_at(slots.size() - 1)
				deficit_streaks.clear()
				break
```

- [ ] **Step 4: Run test to verify it passes**

Add to `tests/run_tests.gd`'s `test_scripts` array:

```gdscript
		preload("res://tests/test_base_economy.gd"),
```

Run: `godot --headless --script tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/base_economy.gd tests/test_base_economy.gd tests/run_tests.gd
git commit -m "Add BaseEconomy production/consumption tick with deficit-streak decay"
```

---

### Task 4: BaseEconomy — tiered price bands

**Files:**
- Modify: `scripts/campaign/base_economy.gd`
- Modify: `tests/test_base_economy.gd`

**Interfaces:**
- Consumes: `Commodity.BASE_PRICE`, `Commodity.TARGET_STOCK` (Task 1).
- Produces: `BaseEconomy.price_for(commodity: int) -> float` and
  `BaseEconomy.sell_price_for(commodity: int) -> float`. Task 9's
  `TradePanel` and Task 6's `CampaignState.buy`/`sell` call these by name.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_base_economy.gd`, inside `run()`, just before the
final `return failures`:

```gdscript
	# Pricing: stock-ratio bands relative to Commodity.TARGET_STOCK.
	var pricing_base := BaseEconomy.new()
	var ore_target: float = Commodity.TARGET_STOCK[Commodity.Type.ORE]
	var ore_base_price: float = Commodity.BASE_PRICE[Commodity.Type.ORE]

	pricing_base.stock = {Commodity.Type.ORE: ore_target * 0.1}  # critical: <20%
	if abs(pricing_base.price_for(Commodity.Type.ORE) - ore_base_price * 1.6) > 0.001:
		failures.append("price_for: expected critical band 1.6x, got %s" % pricing_base.price_for(Commodity.Type.ORE))

	pricing_base.stock = {Commodity.Type.ORE: ore_target * 1.0}  # normal: 60-140%
	if abs(pricing_base.price_for(Commodity.Type.ORE) - ore_base_price * 1.0) > 0.001:
		failures.append("price_for: expected normal band 1.0x, got %s" % pricing_base.price_for(Commodity.Type.ORE))

	pricing_base.stock = {Commodity.Type.ORE: ore_target * 2.0}  # surplus: >180%
	if abs(pricing_base.price_for(Commodity.Type.ORE) - ore_base_price * 0.6) > 0.001:
		failures.append("price_for: expected surplus band 0.6x, got %s" % pricing_base.price_for(Commodity.Type.ORE))

	var buy := pricing_base.price_for(Commodity.Type.ORE)
	var sell := pricing_base.sell_price_for(Commodity.Type.ORE)
	if abs(sell - buy * 0.8) > 0.001:
		failures.append("sell_price_for: expected 80%% of buy price, got buy=%s sell=%s" % [buy, sell])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script tests/run_tests.gd`
Expected: `FAIL [res://tests/test_base_economy.gd]: ...` (method
`price_for` doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

Append to `scripts/campaign/base_economy.gd`:

```gdscript
const BAND_THRESHOLDS := [0.2, 0.6, 1.4, 1.8]
const BAND_MULTIPLIERS := [1.6, 1.3, 1.0, 0.8, 0.6]
const SELL_SPREAD := 0.8

func price_for(commodity: int) -> float:
	var target: float = Commodity.TARGET_STOCK[commodity]
	var ratio: float = stock.get(commodity, 0.0) / target
	var multiplier: float = BAND_MULTIPLIERS[BAND_MULTIPLIERS.size() - 1]
	for i in BAND_THRESHOLDS.size():
		if ratio < BAND_THRESHOLDS[i]:
			multiplier = BAND_MULTIPLIERS[i]
			break
	return Commodity.BASE_PRICE[commodity] * multiplier

func sell_price_for(commodity: int) -> float:
	return price_for(commodity) * SELL_SPREAD
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/base_economy.gd tests/test_base_economy.gd
git commit -m "Add tiered stock-ratio price bands to BaseEconomy"
```

---

### Task 5: CampaignFleet cargo

**Files:**
- Modify: `scripts/campaign/campaign_fleet.gd`
- Modify: `tests/test_campaign_fleet.gd`

**Interfaces:**
- Produces: `CampaignFleet.cargo: Dictionary` (Commodity.Type -> float),
  `const CARGO_CAPACITY_PER_SHIP := 20.0`, `func cargo_capacity() ->
  float`, `func cargo_total() -> float`. Task 6's `CampaignState.buy`/
  `sell` and Task 9's `TradePanel` read/write `fleet.cargo` and call these
  two functions by name.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_campaign_fleet.gd`, just before the final `return
failures`:

```gdscript
	var cargo_fleet := CampaignFleet.new()
	cargo_fleet.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
	]
	if cargo_fleet.cargo_capacity() != 40.0:
		failures.append("cargo_capacity: expected 40.0 for a 2-ship fleet, got %s" % cargo_fleet.cargo_capacity())
	if cargo_fleet.cargo_total() != 0.0:
		failures.append("cargo_total: expected 0.0 with empty cargo, got %s" % cargo_fleet.cargo_total())

	cargo_fleet.cargo = {0: 10.0, 1: 5.0}
	if cargo_fleet.cargo_total() != 15.0:
		failures.append("cargo_total: expected 15.0 with cargo {0:10.0, 1:5.0}, got %s" % cargo_fleet.cargo_total())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script tests/run_tests.gd`
Expected: `FAIL [res://tests/test_campaign_fleet.gd]: ...` (method
`cargo_capacity` doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

Append to `scripts/campaign/campaign_fleet.gd`:

```gdscript
const CARGO_CAPACITY_PER_SHIP := 20.0
@export var cargo: Dictionary = {}

func cargo_capacity() -> float:
	return ship_compositions.size() * CARGO_CAPACITY_PER_SHIP

func cargo_total() -> float:
	var sum := 0.0
	for amount in cargo.values():
		sum += amount
	return sum
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_fleet.gd tests/test_campaign_fleet.gd
git commit -m "Add cargo capacity and totals to CampaignFleet"
```

---

### Task 6: CampaignState credits, economy tick, buy/sell

**Files:**
- Modify: `scripts/campaign/power_faction.gd`
- Modify: `scripts/campaign/campaign_state.gd`
- Modify: `tests/test_power_faction.gd`
- Modify: `tests/test_campaign_state.gd`

**Interfaces:**
- Consumes: `BaseEconomy` (Tasks 3-4), `CampaignFleet.cargo_capacity()`/
  `.cargo_total()` (Task 5).
- Produces: `PowerFaction.economy: BaseEconomy` (default `null`).
  `CampaignState.credits: float` (default `500.0`),
  `CampaignState.home_base_economy: BaseEconomy` (default `null`),
  `CampaignState.tick_economy(delta: float) -> void`,
  `CampaignState.buy(base_economy: BaseEconomy, commodity: int, fleet:
  CampaignFleet) -> bool`, `CampaignState.sell(base_economy: BaseEconomy,
  commodity: int, fleet: CampaignFleet) -> bool`. `reset()` now also
  clears `credits` back to `500.0`, `home_base_economy` to `null`, and the
  internal tick accumulator. Task 7's bootstrap sets `home_base_economy`
  and each faction's `economy`; Task 9's `TradePanel` calls `buy`/`sell`.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_power_faction.gd`'s `run()`, before `return
failures`:

```gdscript
	if faction.economy != null:
		failures.append("PowerFaction: expected default economy == null")
	faction.economy = BaseEconomy.new()
	if faction.economy == null:
		failures.append("PowerFaction: expected economy to be settable")
```

Append to `tests/test_campaign_state.gd`'s synchronous `run()`, before
`return failures` (note: this file already builds `state`, `player`,
`enemy` earlier in `run()` — add after the existing `reset()` assertions):

```gdscript
	# Credits, cargo capacity, and buy/sell.
	var trade_state := CampaignState.new()
	trade_state.credits = 50.0
	var trade_economy := BaseEconomy.new()
	trade_economy.stock = {Commodity.Type.ORE: 10.0}
	var trade_fleet := CampaignFleet.new()
	trade_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	var buy_price: float = trade_economy.price_for(Commodity.Type.ORE)
	var bought: bool = trade_state.buy(trade_economy, Commodity.Type.ORE, trade_fleet)
	if not bought:
		failures.append("buy: expected a well-funded, in-capacity purchase to succeed")
	if abs(trade_state.credits - (50.0 - buy_price)) > 0.001:
		failures.append("buy: expected credits reduced by buy_price, got %s" % trade_state.credits)
	if trade_economy.stock.get(Commodity.Type.ORE, 0.0) != 9.0:
		failures.append("buy: expected base stock reduced by 1, got %s" % trade_economy.stock.get(Commodity.Type.ORE, 0.0))
	if trade_fleet.cargo.get(Commodity.Type.ORE, 0.0) != 1.0:
		failures.append("buy: expected fleet cargo increased by 1, got %s" % trade_fleet.cargo.get(Commodity.Type.ORE, 0.0))

	trade_state.credits = 0.0
	var bought_broke: bool = trade_state.buy(trade_economy, Commodity.Type.ORE, trade_fleet)
	if bought_broke:
		failures.append("buy: expected purchase to fail with 0 credits")

	var sell_price: float = trade_economy.sell_price_for(Commodity.Type.ORE)
	var sold: bool = trade_state.sell(trade_economy, Commodity.Type.ORE, trade_fleet)
	if not sold:
		failures.append("sell: expected selling held cargo to succeed")
	if abs(trade_state.credits - sell_price) > 0.001:
		failures.append("sell: expected credits increased by sell_price, got %s" % trade_state.credits)
	if trade_fleet.cargo.get(Commodity.Type.ORE, 0.0) != 0.0:
		failures.append("sell: expected fleet cargo reduced by 1, got %s" % trade_fleet.cargo.get(Commodity.Type.ORE, 0.0))

	var sold_empty: bool = trade_state.sell(trade_economy, Commodity.Type.ORE, trade_fleet)
	if sold_empty:
		failures.append("sell: expected selling with no cargo held to fail")

	# tick_economy: fires on a fixed interval, not every delta.
	var tick_state := CampaignState.new()
	var ticked_economy := BaseEconomy.new()
	ticked_economy.slots = [EconomyRole.mining()]
	ticked_economy.max_slots = 1
	tick_state.home_base_economy = ticked_economy
	tick_state.tick_economy(1.0)
	if ticked_economy.stock.get(Commodity.Type.ORE, 0.0) != 0.0:
		failures.append("tick_economy: expected no tick yet before the interval elapses")
	tick_state.tick_economy(CampaignState.ECONOMY_TICK_INTERVAL)
	if ticked_economy.stock.get(Commodity.Type.ORE, 0.0) != 5.0:
		failures.append("tick_economy: expected one economy tick once the interval elapses, got Ore=%s" % ticked_economy.stock.get(Commodity.Type.ORE, 0.0))

	# reset() clears the new economy fields too.
	tick_state.credits = 10.0
	tick_state.reset()
	if tick_state.credits != 500.0:
		failures.append("reset: expected credits reset to 500.0, got %s" % tick_state.credits)
	if tick_state.home_base_economy != null:
		failures.append("reset: expected home_base_economy cleared to null")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script tests/run_tests.gd`
Expected: `FAIL [res://tests/test_power_faction.gd]: ...` and `FAIL
[res://tests/test_campaign_state.gd]: ...` (members don't exist yet).

- [ ] **Step 3: Write minimal implementation**

Add to `scripts/campaign/power_faction.gd`:

```gdscript
@export var economy: BaseEconomy = null
```

Modify `scripts/campaign/campaign_state.gd`. Add near the top, alongside
the existing consts:

```gdscript
const ECONOMY_TICK_INTERVAL := 5.0
```

Add new vars alongside `var active_skirmishes`:

```gdscript
var credits: float = 500.0
var home_base_economy: BaseEconomy = null
var _economy_tick_elapsed: float = 0.0
```

Update `reset()` to also clear the new fields:

```gdscript
func reset() -> void:
	player_fleet = null
	enemy_fleets = []
	active_enemy_fleet = null
	factions = []
	factions_at_war = true
	active_skirmishes = []
	credits = 500.0
	home_base_economy = null
	_economy_tick_elapsed = 0.0
```

Add the new functions (anywhere after `reset()`):

```gdscript
func tick_economy(delta: float) -> void:
	_economy_tick_elapsed += delta
	while _economy_tick_elapsed >= ECONOMY_TICK_INTERVAL:
		_economy_tick_elapsed -= ECONOMY_TICK_INTERVAL
		if home_base_economy != null:
			home_base_economy.tick()
		for faction in factions:
			if faction.economy != null:
				faction.economy.tick()

func buy(base_economy: BaseEconomy, commodity: int, fleet: CampaignFleet) -> bool:
	var price := base_economy.price_for(commodity)
	var stock: float = base_economy.stock.get(commodity, 0.0)
	if credits < price or stock < 1.0 or fleet.cargo_total() + 1.0 > fleet.cargo_capacity():
		return false
	credits -= price
	base_economy.stock[commodity] = stock - 1.0
	fleet.cargo[commodity] = fleet.cargo.get(commodity, 0.0) + 1.0
	return true

func sell(base_economy: BaseEconomy, commodity: int, fleet: CampaignFleet) -> bool:
	var held: float = fleet.cargo.get(commodity, 0.0)
	if held < 1.0:
		return false
	var price := base_economy.sell_price_for(commodity)
	credits += price
	fleet.cargo[commodity] = held - 1.0
	base_economy.stock[commodity] = base_economy.stock.get(commodity, 0.0) + 1.0
	return true
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/power_faction.gd scripts/campaign/campaign_state.gd tests/test_power_faction.gd tests/test_campaign_state.gd
git commit -m "Add credits, economy ticking, and buy/sell to CampaignState"
```

---

### Task 7: Bootstrap base economies in CampaignScene

**Files:**
- Modify: `scripts/campaign/campaign_scene.gd`
- Create: `tests/test_campaign_economy_bootstrap.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: `CampaignState.home_base_economy`, `PowerFaction.economy`,
  `CampaignState.tick_economy()` (Task 6), `BaseEconomy`/`EconomyRole`
  (Tasks 2-4).
- Produces: On first run, `CampaignState.home_base_economy` is a
  `[TRADE_HUB]` economy; `CampaignState.factions` (Dominion, Freehold)
  each have `.economy` set to `[INDUSTRIAL, POPULATION]` /
  `[MINING, AGRICULTURE]` respectively. `CampaignScene._physics_process`
  now also calls `CampaignState.tick_economy(delta)`. Task 9's dock
  handlers read `CampaignState.home_base_economy` and
  `faction.economy` by these exact names.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_campaign_economy_bootstrap.gd
extends RefCounted

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(scene)
	await tree.process_frame

	if campaign_state.home_base_economy == null:
		failures.append("expected bootstrap to set CampaignState.home_base_economy")
	elif campaign_state.home_base_economy.slots.size() != 1 or campaign_state.home_base_economy.slots[0].role_type != EconomyRole.RoleType.TRADE_HUB:
		failures.append("expected home_base_economy to have a single TRADE_HUB slot")

	var dominion: PowerFaction = null
	var freehold: PowerFaction = null
	for faction in campaign_state.factions:
		if faction.faction_enum == CampaignFleet.Faction.DOMINION:
			dominion = faction
		elif faction.faction_enum == CampaignFleet.Faction.FREEHOLD:
			freehold = faction

	if dominion == null or dominion.economy == null:
		failures.append("expected the Dominion PowerFaction to have an economy set by bootstrap")
	else:
		var role_types: Array = dominion.economy.slots.map(func(s): return s.role_type)
		if not role_types.has(EconomyRole.RoleType.INDUSTRIAL) or not role_types.has(EconomyRole.RoleType.POPULATION):
			failures.append("expected Dominion economy to have INDUSTRIAL and POPULATION slots, got %s" % [role_types])

	if freehold == null or freehold.economy == null:
		failures.append("expected the Freehold PowerFaction to have an economy set by bootstrap")
	else:
		var role_types: Array = freehold.economy.slots.map(func(s): return s.role_type)
		if not role_types.has(EconomyRole.RoleType.MINING) or not role_types.has(EconomyRole.RoleType.AGRICULTURE):
			failures.append("expected Freehold economy to have MINING and AGRICULTURE slots, got %s" % [role_types])

	# _physics_process ticks the economy: a MINING slot should accrue stock
	# once enough physics frames cover the tick interval.
	if freehold != null and freehold.economy != null:
		var ore_before: float = freehold.economy.stock.get(Commodity.Type.ORE, 0.0)
		var elapsed := 0.0
		while elapsed < CampaignState.ECONOMY_TICK_INTERVAL + 1.0:
			await tree.physics_frame
			elapsed += 1.0 / 60.0
		var ore_after: float = freehold.economy.stock.get(Commodity.Type.ORE, 0.0)
		if ore_after <= ore_before:
			failures.append("expected CampaignScene._physics_process to tick the economy and grow Freehold's Ore stock, before=%s after=%s" % [ore_before, ore_after])

	campaign_state.reset()
	scene.queue_free()
	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Add to `tests/run_tests.gd` (as a `load()`-based async test, per the
existing documented ordering/race rules for anything instantiating
`campaign_scene.tscn` — place it immediately after the existing
`campaign_scene_test` block and before `campaign_fleet_icon_test`):

```gdscript
	var campaign_economy_bootstrap_test = load("res://tests/test_campaign_economy_bootstrap.gd")
	var campaign_economy_bootstrap_failures: Array[String] = await campaign_economy_bootstrap_test.run_async(self)
	for f in campaign_economy_bootstrap_failures:
		print("FAIL [%s]: %s" % [campaign_economy_bootstrap_test.resource_path, f])
	total_failures += campaign_economy_bootstrap_failures.size()
```

Run: `godot --headless --script tests/run_tests.gd`
Expected: `FAIL [res://tests/test_campaign_economy_bootstrap.gd]: expected
bootstrap to set CampaignState.home_base_economy` (and related failures).

- [ ] **Step 3: Write minimal implementation**

Modify `scripts/campaign/campaign_scene.gd`'s `_bootstrap_default_campaign()`.
Add this block right after the line `CampaignState.enemy_fleets = [pirate,
trader, patrol, dominion_fleet, freehold_fleet]`:

```gdscript
	CampaignState.home_base_economy = BaseEconomy.new()
	CampaignState.home_base_economy.slots = [EconomyRole.trade_hub()]
	CampaignState.home_base_economy.max_slots = 1
	for commodity in Commodity.Type.values():
		CampaignState.home_base_economy.stock[commodity] = Commodity.TARGET_STOCK[commodity]

	dominion_faction.economy = BaseEconomy.new()
	dominion_faction.economy.slots = [EconomyRole.industrial(), EconomyRole.population()]
	dominion_faction.economy.max_slots = 2
	dominion_faction.economy.stock = {
		Commodity.Type.ORE: 50.0,
		Commodity.Type.FUEL: 50.0,
		Commodity.Type.FOOD: 50.0,
	}

	freehold_faction.economy = BaseEconomy.new()
	freehold_faction.economy.slots = [EconomyRole.mining(), EconomyRole.agriculture()]
	freehold_faction.economy.max_slots = 2
	freehold_faction.economy.stock = {
		Commodity.Type.ORE: 50.0,
		Commodity.Type.FOOD: 50.0,
	}
```

Modify `_physics_process` to also tick the economy:

```gdscript
func _physics_process(delta: float) -> void:
	CampaignState.tick_skirmishes(delta)
	CampaignState.tick_economy(delta)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_scene.gd tests/test_campaign_economy_bootstrap.gd tests/run_tests.gd
git commit -m "Wire base economies into CampaignScene bootstrap and ticking"
```

---

### Task 8: TradePanel UI

**Files:**
- Create: `scripts/campaign/trade_panel.gd`
- Create: `scenes/campaign/trade_panel.tscn`
- Create: `tests/test_trade_panel.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: `BaseEconomy.price_for`/`.sell_price_for`/`.stock` (Tasks
  3-4), `CampaignFleet.cargo`/`.cargo_total`/`.cargo_capacity` (Task 5),
  `CampaignState.credits`/`.buy`/`.sell` (Task 6), `Commodity.Type.values()`/
  `.NAMES` (Task 1).
- Produces: `class_name TradePanel extends Control` with `func
  open_for(base_economy: BaseEconomy, fleet: CampaignFleet) -> void`,
  `func close() -> void`, `func refresh() -> void`. Task 9's
  `CampaignScene` instantiates this scene and calls `open_for`/`close` on
  dock/undock.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_trade_panel.gd
extends RefCounted

const TradePanelScene = preload("res://scenes/campaign/trade_panel.tscn")
const BaseEconomy = preload("res://scripts/campaign/base_economy.gd")
const EconomyRole = preload("res://scripts/campaign/economy_role.gd")
const Commodity = preload("res://scripts/campaign/commodity.gd")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var panel: Control = TradePanelScene.instantiate()
	tree.root.add_child(panel)
	await tree.process_frame

	if panel.visible:
		failures.append("TradePanel: expected hidden by default")

	var economy := BaseEconomy.new()
	economy.slots = [EconomyRole.trade_hub()]
	economy.stock = {Commodity.Type.ORE: 100.0}
	var fleet := CampaignFleet.new()
	fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	panel.open_for(economy, fleet)
	if not panel.visible:
		failures.append("TradePanel: expected visible after open_for")

	var buy_button: Button = panel._rows[Commodity.Type.ORE]["buy_button"]
	var ore_buy_price: float = economy.price_for(Commodity.Type.ORE)
	var credits_before: float = campaign_state.credits
	buy_button.pressed.emit()
	if campaign_state.credits != credits_before - ore_buy_price:
		failures.append("TradePanel: expected pressing Buy to call CampaignState.buy, credits before=%s after=%s" % [credits_before, campaign_state.credits])
	if fleet.cargo.get(Commodity.Type.ORE, 0.0) != 1.0:
		failures.append("TradePanel: expected pressing Buy to add 1 Ore to fleet cargo")

	var sell_button: Button = panel._rows[Commodity.Type.ORE]["sell_button"]
	var credits_before_sell: float = campaign_state.credits
	sell_button.pressed.emit()
	if campaign_state.credits <= credits_before_sell:
		failures.append("TradePanel: expected pressing Sell to call CampaignState.sell and increase credits")
	if fleet.cargo.get(Commodity.Type.ORE, 0.0) != 0.0:
		failures.append("TradePanel: expected pressing Sell to remove the Ore from fleet cargo")

	panel.close()
	if panel.visible:
		failures.append("TradePanel: expected hidden after close")

	campaign_state.reset()
	panel.queue_free()
	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Run: `test -f scripts/campaign/trade_panel.gd && echo EXISTS || echo MISSING`
Expected: `MISSING`

- [ ] **Step 3: Write minimal implementation**

```gdscript
# scripts/campaign/trade_panel.gd
class_name TradePanel
extends Control

var _docked_base_economy: BaseEconomy
var _player_fleet: CampaignFleet
var _rows: Dictionary = {}

@onready var rows_container: VBoxContainer = $RowsContainer
@onready var credits_label: Label = $CreditsLabel
@onready var close_button: Button = $CloseButton

func _ready() -> void:
	close_button.pressed.connect(close)
	visible = false
	_build_rows()

func open_for(base_economy: BaseEconomy, fleet: CampaignFleet) -> void:
	_docked_base_economy = base_economy
	_player_fleet = fleet
	visible = true
	refresh()

func close() -> void:
	visible = false
	_docked_base_economy = null
	_player_fleet = null

func refresh() -> void:
	if _docked_base_economy == null or _player_fleet == null:
		return
	credits_label.text = "Credits: %d" % CampaignState.credits
	for commodity in _rows.keys():
		var row: Dictionary = _rows[commodity]
		var stock: float = _docked_base_economy.stock.get(commodity, 0.0)
		var buy_price := _docked_base_economy.price_for(commodity)
		var sell_price := _docked_base_economy.sell_price_for(commodity)
		var held: float = _player_fleet.cargo.get(commodity, 0.0)
		row["label"].text = "%s  stock:%.0f  buy:%.0f  sell:%.0f  held:%.0f" % [Commodity.NAMES[commodity], stock, buy_price, sell_price, held]
		row["buy_button"].disabled = CampaignState.credits < buy_price or stock < 1.0 or _player_fleet.cargo_total() + 1.0 > _player_fleet.cargo_capacity()
		row["sell_button"].disabled = held < 1.0

func _build_rows() -> void:
	if not _rows.is_empty():
		return
	for commodity in Commodity.Type.values():
		var row_box := HBoxContainer.new()
		var label := Label.new()
		var buy_button := Button.new()
		buy_button.text = "Buy"
		buy_button.pressed.connect(_on_buy_pressed.bind(commodity))
		var sell_button := Button.new()
		sell_button.text = "Sell"
		sell_button.pressed.connect(_on_sell_pressed.bind(commodity))
		row_box.add_child(label)
		row_box.add_child(buy_button)
		row_box.add_child(sell_button)
		rows_container.add_child(row_box)
		_rows[commodity] = {"label": label, "buy_button": buy_button, "sell_button": sell_button}

func _on_buy_pressed(commodity: int) -> void:
	CampaignState.buy(_docked_base_economy, commodity, _player_fleet)
	refresh()

func _on_sell_pressed(commodity: int) -> void:
	CampaignState.sell(_docked_base_economy, commodity, _player_fleet)
	refresh()
```

```
# scenes/campaign/trade_panel.tscn
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/campaign/trade_panel.gd" id="1"]

[node name="TradePanel" type="Control"]
offset_left = 200.0
offset_top = 100.0
offset_right = 700.0
offset_bottom = 450.0
script = ExtResource("1")

[node name="CreditsLabel" type="Label" parent="."]
offset_top = 0.0
offset_right = 300.0
offset_bottom = 30.0

[node name="RowsContainer" type="VBoxContainer" parent="."]
offset_top = 40.0
offset_right = 500.0
offset_bottom = 300.0

[node name="CloseButton" type="Button" parent="."]
offset_top = 310.0
offset_right = 100.0
offset_bottom = 340.0
text = "Close"
```

- [ ] **Step 4: Run test to verify it passes**

Add to `tests/run_tests.gd`, as a `preload()`-based async test (no
autoload-at-top-level race here, since `trade_panel.gd` never bare-
references `CampaignState` at class/script top level — only inside
function bodies, which resolve at call time, same as `test_home_base.gd`'s
pattern). Place it near the other `preload()`-based async tests, e.g.
right after the `home_base_test` block:

```gdscript
	var trade_panel_test = preload("res://tests/test_trade_panel.gd")
	var trade_panel_failures: Array[String] = await trade_panel_test.run_async(self)
	for f in trade_panel_failures:
		print("FAIL [%s]: %s" % [trade_panel_test.resource_path, f])
	total_failures += trade_panel_failures.size()
```

Run: `godot --headless --script tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/trade_panel.gd scenes/campaign/trade_panel.tscn tests/test_trade_panel.gd tests/run_tests.gd
git commit -m "Add TradePanel UI for buying/selling commodities"
```

---

### Task 9: Wire TradePanel into CampaignScene docking

**Files:**
- Modify: `scripts/campaign/campaign_scene.gd`
- Modify: `scenes/campaign/campaign_scene.tscn`
- Create: `tests/test_campaign_scene_trading.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: `TradePanel.open_for`/`.close` (Task 8),
  `CampaignState.home_base_economy`/`factions[i].economy` (Tasks 6-7).
- Produces: Docking the player icon at `HomeBase` or a `FactionBase` opens
  the scene's `trade_panel`; undocking closes it. No new public API —
  this is pure wiring, verified end-to-end by the new test.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_campaign_scene_trading.gd
extends RefCounted

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(scene)
	await tree.process_frame

	var trade_panel: TradePanel = scene.get_node("TradePanel")
	if trade_panel.visible:
		failures.append("expected TradePanel hidden before the player docks anywhere")

	# HomeBase sits at CampaignScene.HOME_BASE_POSITION; the player icon
	# starts there too, but area_entered only fires on a fresh overlap
	# transition, so move away first and then back onto it.
	scene.player_icon.global_position = Vector2(-5000, -5000)
	for i in 3:
		await tree.physics_frame
	scene.player_icon.global_position = scene.HOME_BASE_POSITION
	for i in 5:
		await tree.physics_frame

	if not trade_panel.visible:
		failures.append("expected TradePanel visible after docking at HomeBase")

	scene.player_icon.global_position = Vector2(-5000, -5000)
	for i in 5:
		await tree.physics_frame

	if trade_panel.visible:
		failures.append("expected TradePanel hidden after leaving HomeBase")

	# Dock at a faction base and confirm the panel opens with that
	# faction's own economy (not HomeBase's).
	var faction_base: FactionBase = null
	for child in scene.get_children():
		if child is FactionBase:
			faction_base = child
			break
	if faction_base == null:
		failures.append("expected at least one FactionBase spawned by bootstrap")
	else:
		scene.player_icon.global_position = faction_base.global_position
		for i in 5:
			await tree.physics_frame
		if not trade_panel.visible:
			failures.append("expected TradePanel visible after docking at a FactionBase")
		else:
			var expected_economy: BaseEconomy = null
			for faction in campaign_state.factions:
				if faction.faction_enum == faction_base.faction_enum:
					expected_economy = faction.economy
			if trade_panel._docked_base_economy != expected_economy:
				failures.append("expected TradePanel to open with the docked FactionBase's own economy")

	campaign_state.reset()
	scene.queue_free()
	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Add to `tests/run_tests.gd` as a `load()`-based async test (same
autoload-race reasoning as the other `campaign_scene.tscn` tests),
positioned right after the `test_campaign_economy_bootstrap` block added
in Task 7:

```gdscript
	var campaign_scene_trading_test = load("res://tests/test_campaign_scene_trading.gd")
	var campaign_scene_trading_failures: Array[String] = await campaign_scene_trading_test.run_async(self)
	for f in campaign_scene_trading_failures:
		print("FAIL [%s]: %s" % [campaign_scene_trading_test.resource_path, f])
	total_failures += campaign_scene_trading_failures.size()
```

Run: `godot --headless --script tests/run_tests.gd`
Expected: `FAIL [res://tests/test_campaign_scene_trading.gd]: ...` (no
`TradePanel` node in the scene yet).

- [ ] **Step 3: Write minimal implementation**

Add to `scenes/campaign/campaign_scene.tscn`, as a new top-level child
(after the `EngagePrompt` node block):

```
[node name="TradePanel" type="Control" parent="." instance=ExtResource("2")]
```

This requires adding the `TradePanel` scene as an `ext_resource`. Update
the top of the file: change the `load_steps` count from `2` to `3` and
add a second `ext_resource` line, so the file's `[gd_scene ...]` and
`ext_resource` lines read:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/campaign/campaign_scene.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/campaign/trade_panel.tscn" id="2"]
```

Modify `scripts/campaign/campaign_scene.gd`. Add alongside the existing
`@onready var engage_prompt`:

```gdscript
@onready var trade_panel: TradePanel = $TradePanel
```

Add a helper function (anywhere after `_behavior_for_faction`):

```gdscript
func _economy_for_base(area: Area2D) -> BaseEconomy:
	if area is HomeBase:
		return CampaignState.home_base_economy
	if area is FactionBase:
		for faction in CampaignState.factions:
			if faction.faction_enum == area.faction_enum:
				return faction.economy
	return null
```

Modify `_on_player_area_entered` and `_on_player_area_exited`:

```gdscript
func _on_player_area_entered(area: Area2D) -> void:
	if area is CampaignFleetIcon and area != player_icon and not engage_prompt.visible:
		_pending_enemy_icon = area
		engage_prompt.visible = true
	elif area is HomeBase or area is FactionBase:
		var economy := _economy_for_base(area)
		if economy != null:
			trade_panel.open_for(economy, CampaignState.player_fleet)

func _on_player_area_exited(area: Area2D) -> void:
	if area == _pending_enemy_icon:
		_pending_enemy_icon = null
	elif area is HomeBase or area is FactionBase:
		trade_panel.close()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_scene.gd scenes/campaign/campaign_scene.tscn tests/test_campaign_scene_trading.gd tests/run_tests.gd
git commit -m "Open/close TradePanel when the player docks at HomeBase or a FactionBase"
```

---

### Task 10: Full-suite verification

**Files:** None (verification only).

- [ ] **Step 1: Run the full test suite one more time from a clean state**

Run: `godot --headless --script tests/run_tests.gd`
Expected: `All tests passed.` with no warnings about missing nodes/
autoloads.

- [ ] **Step 2: Manually sanity-check in the editor**

Open the project in the Godot editor, run the main scene
(`scenes/campaign/campaign_scene.tscn`), sail the player icon onto
HomeBase and confirm the trade panel opens showing 6 commodities with
sensible prices (home base starts at target stock, so all should show the
"Normal" 1.0x price), buy a unit of Ore, confirm credits drop and the Ore
row's "held" count increments, sail onto a faction base and confirm its
panel shows different stock/prices than HomeBase.

- [ ] **Step 3: Commit (only if Step 2 surfaced a fix)**

If manual testing found a bug, fix it, re-run the full suite, and commit
the fix with a message describing what was wrong — otherwise no commit is
needed for this task.
