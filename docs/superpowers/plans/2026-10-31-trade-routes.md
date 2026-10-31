# Trade Routes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Dominion and Freehold autonomous NPC trader fleets that haul cargo to/from HomeBase to sustain their economies, let each faction grow/shrink its fleets based on economic and military strength, close the Fuel-production gap left by Milestone 4a, and let the player loot cargo from defeated fleets.

**Architecture:** Builds entirely on the existing 4a economy/campaign code (`BaseEconomy`, `EconomyRole`, `CampaignFleet`, `CampaignFleetIcon`, `CampaignState`, `CampaignScene`). No new systems are introduced — a "trader" is just a `CampaignFleet` with `role = TRADER` whose icon reuses the existing `TraderBehavior` route state machine retargeted to a faction base; fleet growth is a small new pure-function policy (`FleetAllocationPolicy`) invoked from the existing economy tick; loot is a `TradePanel`-shaped new `LootPanel` driven by a `CampaignState.pending_loot_fleet` field (not a transient signal, since the scene that would receive a transient signal has already been torn down by the time `resolve_engagement` runs — see Task 8).

**Tech Stack:** Godot 4.7 / GDScript, existing project test harness (`tests/run_tests.gd`, static `run()`/`run_async(tree)` pattern, no external test framework).

## Global Constraints

- Match existing code style exactly: tabs for indentation, `class_name` + `extends` header, static pure-function helper classes extend `RefCounted`.
- Every new/changed behavior needs a test in the existing `tests/` harness, registered in `tests/run_tests.gd`.
- Any script that bare-references the `CampaignState` autoload must be `load()`ed (not `preload()`ed) in `run_tests.gd`, and positioned after at least one `await tree.process_frame`/`physics_frame` has already run — see the comments already in `tests/run_tests.gd` for why. Scripts that don't reference `CampaignState` should stay `preload()`ed.
- Godot's global class cache (`class_name`) must be warmed for `--headless --script` test runs to see new classes: `GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe --headless --editor --quit` once after adding any new `class_name` file, before running tests.
- Test command: `C:\Users\corbi\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe --headless --script tests/run_tests.gd`
- Any new Control scene with `mouse_filter` needs it set to `2` (IGNORE) on its root, exactly like `TradePanel`/`debug_console`, or it silently swallows clicks across its whole rect.

---

### Task 1: `EconomyRole.refinery()` — closes the Fuel-production gap

**Files:**
- Modify: `scripts/campaign/economy_role.gd`
- Test: `tests/test_economy_role.gd`

**Interfaces:**
- Produces: `EconomyRole.RoleType.REFINERY` (new enum value), `EconomyRole.refinery() -> EconomyRole` (produces `{Commodity.Type.FUEL: 2.0}`, consumes nothing). Later tasks (Task 10) add this role to `CampaignState.home_base_economy`.

- [ ] **Step 1: Write the failing test**

Add to the end of `tests/test_economy_role.gd`, before `return failures`:

```gdscript
	var refinery := EconomyRole.refinery()
	if refinery.role_type != EconomyRole.RoleType.REFINERY:
		failures.append("refinery: expected role_type REFINERY, got %s" % refinery.role_type)
	if refinery.produces.get(Commodity.Type.FUEL, 0.0) <= 0.0:
		failures.append("refinery: expected it to produce Fuel")
	if not refinery.consumes.is_empty():
		failures.append("refinery: expected no consumption")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `...Godot_v4.7.2-stable_win64_console.exe --headless --script tests/run_tests.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'refinery' in base 'RefCounted (EconomyRole)'` (or similar), surfaced as a test failure since `test_economy_role.gd` is already registered in `run_tests.gd`.

- [ ] **Step 3: Implement**

In `scripts/campaign/economy_role.gd`, change the enum line to:

```gdscript
enum RoleType { MINING, AGRICULTURE, INDUSTRIAL, POPULATION, TRADE_HUB, REFINERY }
```

Add after `trade_hub()`:

```gdscript
static func refinery() -> EconomyRole:
	var role := EconomyRole.new()
	role.role_type = RoleType.REFINERY
	role.produces = {Commodity.Type.FUEL: 2.0}
	return role
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command. Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/economy_role.gd tests/test_economy_role.gd
git commit -m "Add EconomyRole.refinery() to produce ongoing Fuel"
```

---

### Task 2: `BaseEconomy.net_commodities()` and `surplus_streak`

**Files:**
- Modify: `scripts/campaign/base_economy.gd`
- Test: `tests/test_base_economy.gd`

**Interfaces:**
- Consumes: nothing new (operates on existing `slots`/`stock`/`deficit_streaks`).
- Produces: `BaseEconomy.net_commodities() -> Dictionary` (Commodity int -> float, produces-minus-consumes summed across slots). `BaseEconomy.surplus_streak: int` (increments on a tick with zero deficits, resets to 0 on any deficit). `BaseEconomy.SURPLUS_STREAK_THRESHOLD := 5` (const). Used by Task 7 (`CampaignState._economic_health`) and Task 6 (`CampaignState._load_surplus`/`_unload_and_load_deficit`).

- [ ] **Step 1: Write the failing test**

Add to the end of `tests/test_base_economy.gd`, before `return failures`:

```gdscript
	# net_commodities: sums produces-minus-consumes across all slots.
	var net_base := BaseEconomy.new()
	net_base.slots = [EconomyRole.industrial(), EconomyRole.mining()]
	var net := net_base.net_commodities()
	if abs(net.get(Commodity.Type.ORE, 0.0) - 2.0) > 0.001:
		failures.append("net_commodities: expected Ore net +2.0 (mining +5 - industrial -3), got %s" % net.get(Commodity.Type.ORE, 0.0))
	if abs(net.get(Commodity.Type.FUEL, 0.0) - (-2.0)) > 0.001:
		failures.append("net_commodities: expected Fuel net -2.0, got %s" % net.get(Commodity.Type.FUEL, 0.0))
	if abs(net.get(Commodity.Type.WEAPONS, 0.0) - 2.0) > 0.001:
		failures.append("net_commodities: expected Weapons net +2.0, got %s" % net.get(Commodity.Type.WEAPONS, 0.0))

	# surplus_streak: increments on a clean tick, resets to 0 on any deficit.
	var surplus_base := BaseEconomy.new()
	surplus_base.slots = [EconomyRole.mining()]
	surplus_base.max_slots = 1
	surplus_base.tick()
	surplus_base.tick()
	if surplus_base.surplus_streak != 2:
		failures.append("surplus_streak: expected 2 after two clean ticks, got %s" % surplus_base.surplus_streak)

	var deficit_then_clean_base := BaseEconomy.new()
	deficit_then_clean_base.slots = [EconomyRole.industrial()]
	deficit_then_clean_base.max_slots = 1
	deficit_then_clean_base.stock = {}
	deficit_then_clean_base.tick()
	if deficit_then_clean_base.surplus_streak != 0:
		failures.append("surplus_streak: expected 0 after a deficit tick, got %s" % deficit_then_clean_base.surplus_streak)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `...Godot_v4.7.2-stable_win64_console.exe --headless --script tests/run_tests.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'net_commodities'` and/or `Invalid get index 'surplus_streak'`.

- [ ] **Step 3: Implement**

In `scripts/campaign/base_economy.gd`, add the const and var near the top (after `var deficit_streaks: Dictionary = {}`):

```gdscript
const SURPLUS_STREAK_THRESHOLD := 5
var surplus_streak: int = 0
```

Replace the entire `tick()` function with:

```gdscript
func tick() -> void:
	for slot in slots:
		if slot.consumes.is_empty():
			for commodity in slot.produces:
				stock[commodity] = stock.get(commodity, 0.0) + slot.produces[commodity]

	var any_deficit := false
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
			for commodity in slot.produces:
				stock[commodity] = stock.get(commodity, 0.0) + slot.produces[commodity]
			deficit_streaks[i] = 0
		else:
			any_deficit = true
			for commodity in slot.consumes:
				stock[commodity] = 0.0
			deficit_streaks[i] = deficit_streaks.get(i, 0) + 1
			if deficit_streaks[i] >= DEFICIT_STREAK_THRESHOLD:
				slots.remove_at(slots.size() - 1)
				deficit_streaks.clear()
				break

	if any_deficit:
		surplus_streak = 0
	else:
		surplus_streak += 1
```

Add after `sell_price_for`:

```gdscript
func net_commodities() -> Dictionary:
	var net: Dictionary = {}
	for slot in slots:
		for commodity in slot.produces:
			net[commodity] = net.get(commodity, 0.0) + slot.produces[commodity]
		for commodity in slot.consumes:
			net[commodity] = net.get(commodity, 0.0) - slot.consumes[commodity]
	return net
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command. Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/base_economy.gd tests/test_base_economy.gd
git commit -m "Add BaseEconomy.net_commodities() and surplus_streak tracking"
```

---

### Task 3: `CampaignFleet.role`

**Files:**
- Modify: `scripts/campaign/campaign_fleet.gd`
- Test: `tests/test_campaign_fleet.gd`

**Interfaces:**
- Produces: `CampaignFleet.Role` enum `{ COMBAT, TRADER }`, `CampaignFleet.role: Role` (exported, default `COMBAT`). Used by every later task.

- [ ] **Step 1: Write the failing test**

Add to the end of `tests/test_campaign_fleet.gd`, before `return failures`:

```gdscript
	var default_role_fleet := CampaignFleet.new()
	if default_role_fleet.role != CampaignFleet.Role.COMBAT:
		failures.append("role: expected default role == COMBAT, got %s" % default_role_fleet.role)

	var trader_role_fleet := CampaignFleet.new()
	trader_role_fleet.role = CampaignFleet.Role.TRADER
	if trader_role_fleet.role != CampaignFleet.Role.TRADER:
		failures.append("role: expected TRADER to be settable")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `...Godot_v4.7.2-stable_win64_console.exe --headless --script tests/run_tests.gd`
Expected: FAIL — `Invalid get index 'role'` on `CampaignFleet`.

- [ ] **Step 3: Implement**

In `scripts/campaign/campaign_fleet.gd`, after `enum Faction { PLAYER, NEUTRAL, TRADER, PIRATE, DOMINION, FREEHOLD }`, add:

```gdscript
enum Role { COMBAT, TRADER }
@export var role: Role = Role.COMBAT
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command. Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_fleet.gd tests/test_campaign_fleet.gd
git commit -m "Add CampaignFleet.role (COMBAT/TRADER) for fleet allocation"
```

---

### Task 4: `FleetAllocationPolicy`

**Files:**
- Create: `scripts/campaign/fleet_allocation_policy.gd`
- Create: `scripts/campaign/fleet_allocation_policy.gd.uid` (auto-generated by Godot on first open — not created manually; ignore if missing until Task 11's editor-cache-warm step, which generates it)
- Test: Create `tests/test_fleet_allocation_policy.gd`

**Interfaces:**
- Produces: `FleetAllocationPolicy.EconomicHealth` enum `{ DEFICIT, STABLE, STRONG }`, `FleetAllocationPolicy.Action` enum `{ NONE, GROW_COMBAT, GROW_TRADE, REALLOCATE_TO_COMBAT }`, consts `DANGER_THRESHOLD := 1.2`, `SAFE_THRESHOLD := 0.6`, `MAX_FLEETS := 4`, `MAX_SHIPS_PER_FLEET := 3`, and `FleetAllocationPolicy.decide(economic_health: EconomicHealth, threat_ratio: float, trader_fleet_count: int) -> Action`. Used by Task 7 (`CampaignState._apply_fleet_allocation`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_fleet_allocation_policy.gd`:

```gdscript
extends RefCounted

const FleetAllocationPolicy = preload("res://scripts/campaign/fleet_allocation_policy.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var danger_stable := FleetAllocationPolicy.decide(FleetAllocationPolicy.EconomicHealth.STABLE, 2.0, 2)
	if danger_stable != FleetAllocationPolicy.Action.GROW_COMBAT:
		failures.append("decide: expected GROW_COMBAT when outmatched and not in deficit, got %s" % danger_stable)

	var danger_deficit_with_spare_trader := FleetAllocationPolicy.decide(FleetAllocationPolicy.EconomicHealth.DEFICIT, 2.0, 2)
	if danger_deficit_with_spare_trader != FleetAllocationPolicy.Action.REALLOCATE_TO_COMBAT:
		failures.append("decide: expected REALLOCATE_TO_COMBAT when outmatched, in deficit, and more than 1 trader, got %s" % danger_deficit_with_spare_trader)

	var danger_deficit_last_trader := FleetAllocationPolicy.decide(FleetAllocationPolicy.EconomicHealth.DEFICIT, 2.0, 1)
	if danger_deficit_last_trader != FleetAllocationPolicy.Action.NONE:
		failures.append("decide: expected NONE when outmatched, in deficit, and only 1 trader left, got %s" % danger_deficit_last_trader)

	var strong_safe := FleetAllocationPolicy.decide(FleetAllocationPolicy.EconomicHealth.STRONG, 0.1, 1)
	if strong_safe != FleetAllocationPolicy.Action.GROW_TRADE:
		failures.append("decide: expected GROW_TRADE when strong and safe, got %s" % strong_safe)

	var strong_not_safe := FleetAllocationPolicy.decide(FleetAllocationPolicy.EconomicHealth.STRONG, 0.9, 1)
	if strong_not_safe != FleetAllocationPolicy.Action.NONE:
		failures.append("decide: expected NONE when strong but threat_ratio isn't below SAFE_THRESHOLD, got %s" % strong_not_safe)

	var stable_mid := FleetAllocationPolicy.decide(FleetAllocationPolicy.EconomicHealth.STABLE, 0.9, 1)
	if stable_mid != FleetAllocationPolicy.Action.NONE:
		failures.append("decide: expected NONE when stable and threat_ratio is mid-range, got %s" % stable_mid)

	var boundary_danger := FleetAllocationPolicy.decide(FleetAllocationPolicy.EconomicHealth.STABLE, FleetAllocationPolicy.DANGER_THRESHOLD, 1)
	if boundary_danger != FleetAllocationPolicy.Action.NONE:
		failures.append("decide: expected threat_ratio exactly at DANGER_THRESHOLD to NOT count as danger, got %s" % boundary_danger)

	var boundary_safe := FleetAllocationPolicy.decide(FleetAllocationPolicy.EconomicHealth.STRONG, FleetAllocationPolicy.SAFE_THRESHOLD, 1)
	if boundary_safe != FleetAllocationPolicy.Action.NONE:
		failures.append("decide: expected threat_ratio exactly at SAFE_THRESHOLD to NOT count as safe, got %s" % boundary_safe)

	return failures
```

- [ ] **Step 2: Run test to verify it fails**

First register the new test in `tests/run_tests.gd` (add to the `test_scripts` array in `_run_all()`, alongside `test_commodity.gd`):

```gdscript
			preload("res://tests/test_fleet_allocation_policy.gd"),
```

Run: `...Godot_v4.7.2-stable_win64_console.exe --headless --script tests/run_tests.gd`
Expected: FAIL — cannot preload `res://scripts/campaign/fleet_allocation_policy.gd` (file doesn't exist yet).

- [ ] **Step 3: Implement**

Create `scripts/campaign/fleet_allocation_policy.gd`:

```gdscript
class_name FleetAllocationPolicy
extends RefCounted

enum EconomicHealth { DEFICIT, STABLE, STRONG }
enum Action { NONE, GROW_COMBAT, GROW_TRADE, REALLOCATE_TO_COMBAT }

const DANGER_THRESHOLD := 1.2
const SAFE_THRESHOLD := 0.6
const MAX_FLEETS := 4
const MAX_SHIPS_PER_FLEET := 3

static func decide(economic_health: EconomicHealth, threat_ratio: float, trader_fleet_count: int) -> Action:
	if threat_ratio > DANGER_THRESHOLD:
		if economic_health != EconomicHealth.DEFICIT:
			return Action.GROW_COMBAT
		if trader_fleet_count > 1:
			return Action.REALLOCATE_TO_COMBAT
		return Action.NONE
	if economic_health == EconomicHealth.STRONG and threat_ratio < SAFE_THRESHOLD:
		return Action.GROW_TRADE
	return Action.NONE
```

Run the editor-cache-warm step once (new `class_name` file):

```bash
"C:\Users\corbi\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --headless --editor --quit
```

- [ ] **Step 4: Run test to verify it passes**

Run: `...Godot_v4.7.2-stable_win64_console.exe --headless --script tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/fleet_allocation_policy.gd tests/test_fleet_allocation_policy.gd tests/run_tests.gd
git commit -m "Add FleetAllocationPolicy pure decision function"
```

---

### Task 5: `CampaignFleetIcon` trade-route retargeting and arrival signal

**Files:**
- Modify: `scripts/campaign/campaign_fleet_icon.gd`
- Test: `tests/test_campaign_fleet_icon.gd`

**Interfaces:**
- Consumes: `TraderBehavior.RouteState`, `.next_route_state`, `.route_target` (unchanged, existing).
- Produces: `CampaignFleetIcon.set_route_endpoints(home_pos: Vector2, away_pos: Vector2) -> void`, `signal trader_arrived(at_home: bool)` (emitted once per arrival at either endpoint; `at_home = true` means it just arrived at `home_pos`, `false` means it just arrived at `away_pos`). Used by Task 10 (`CampaignScene._configure_trade_route`, `_on_trader_arrived`).

- [ ] **Step 1: Write the failing test**

Add to the end of `tests/test_campaign_fleet_icon.gd`, before `return failures`:

```gdscript
	# Trader route retargeting + trader_arrived signal: an icon set up with
	# set_route_endpoints should route between those exact points (not its
	# spawn point) and emit trader_arrived(true) on reaching home, then
	# trader_arrived(false) on reaching the away point.
	var route_fleet := CampaignFleet.new()
	route_fleet.position = Vector2(500, 500)
	route_fleet.speed = 400.0
	var route_icon: Area2D = CampaignFleetIconScene.instantiate()
	route_icon.behavior_type = route_icon.BehaviorType.TRADER
	route_icon.arrival_radius = 10.0
	tree.root.add_child(route_icon)
	route_icon.setup(route_fleet, Vector2.ZERO)
	var home_pos := Vector2(0, 0)
	var away_pos := Vector2(100, 0)
	route_icon.set_route_endpoints(home_pos, away_pos)
	route_icon.global_position = home_pos

	var arrivals: Array = []
	route_icon.trader_arrived.connect(func(at_home: bool): arrivals.append(at_home))

	for i in 60:
		await tree.physics_frame
		if arrivals.size() >= 1:
			break
	if arrivals.size() < 1 or arrivals[0] != false:
		failures.append("trader_arrived: expected first arrival to be at the away point (false), got %s" % [arrivals])

	for i in 60:
		await tree.physics_frame
		if arrivals.size() >= 2:
			break
	if arrivals.size() < 2 or arrivals[1] != true:
		failures.append("trader_arrived: expected second arrival to be at home (true), got %s" % [arrivals])

	route_icon.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `...Godot_v4.7.2-stable_win64_console.exe --headless --script tests/run_tests.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'set_route_endpoints'`.

- [ ] **Step 3: Implement**

In `scripts/campaign/campaign_fleet_icon.gd`, add after the existing `var _route_state` line:

```gdscript
signal trader_arrived(at_home: bool)
```

Add a new public method anywhere after `set_move_target`:

```gdscript
func set_route_endpoints(home_pos: Vector2, away_pos: Vector2) -> void:
	_home_position = home_pos
	_spawn_point = away_pos
```

Replace `_process_trader()` with:

```gdscript
func _process_trader() -> void:
	if player_target != null and is_instance_valid(player_target) and TraderBehavior.should_flee(global_position, player_target.global_position, flee_range):
		_move_target = TraderBehavior.flee_target(global_position, player_target.global_position, flee_distance)
		return
	var previous_state := _route_state
	_route_state = TraderBehavior.next_route_state(_route_state, global_position, _home_position, _spawn_point, arrival_radius)
	_move_target = TraderBehavior.route_target(_route_state, _home_position, _spawn_point)
	if _route_state != previous_state:
		trader_arrived.emit(_route_state == TraderBehavior.RouteState.FROM_BASE)
```

(Starting state is `TO_BASE`, with `_home_position` initially equal to whatever `setup()` was called with — since the test above calls `set_route_endpoints` right after `setup()` and before any physics frame, the icon starts `TO_BASE` toward the new `home_pos`; the test places it there directly to drive straight to `away_pos` first, confirming `FROM_BASE` fires `trader_arrived(false)`.)

- [ ] **Step 4: Run test to verify it passes**

Run the same command. Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_fleet_icon.gd tests/test_campaign_fleet_icon.gd
git commit -m "Add CampaignFleetIcon.set_route_endpoints and trader_arrived signal"
```

---

### Task 6: `CampaignState.run_npc_trade_for_fleet`

**Files:**
- Modify: `scripts/campaign/campaign_state.gd`
- Test: `tests/test_campaign_state.gd`

**Interfaces:**
- Consumes: `BaseEconomy.net_commodities()` (Task 2), `CampaignFleet.cargo_capacity()`/`cargo_total()` (existing), `CampaignState.factions` / `home_base_economy` (existing fields).
- Produces: `CampaignState.run_npc_trade_for_fleet(fleet: CampaignFleet, at_home: bool) -> void`. No-ops if `fleet.faction` has no matching `PowerFaction` in `factions`, or that faction's `economy` is null, or `home_base_economy` is null. Used by Task 10 (`CampaignScene._on_trader_arrived`).

- [ ] **Step 1: Write the failing test**

Add to the end of `tests/test_campaign_state.gd`'s `run() -> Array[String]` function, before `return failures`:

```gdscript
	# run_npc_trade_for_fleet: at the faction base, loads surplus commodities
	# (produced more than consumed) from the faction's own stock into cargo.
	var trade_route_state := CampaignState.new()
	var trade_route_faction := PowerFaction.new()
	trade_route_faction.faction_enum = CampaignFleet.Faction.FREEHOLD
	trade_route_faction.economy = BaseEconomy.new()
	trade_route_faction.economy.slots = [EconomyRole.mining(), EconomyRole.agriculture()]
	trade_route_faction.economy.stock = {Commodity.Type.ORE: 50.0, Commodity.Type.FOOD: 50.0}
	trade_route_state.factions = [trade_route_faction]
	trade_route_state.home_base_economy = BaseEconomy.new()

	var hauler := CampaignFleet.new()
	hauler.faction = CampaignFleet.Faction.FREEHOLD
	hauler.role = CampaignFleet.Role.TRADER
	hauler.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	trade_route_state.run_npc_trade_for_fleet(hauler, true)
	if hauler.cargo_total() <= 0.0:
		failures.append("run_npc_trade_for_fleet: expected loading surplus at the faction base to fill cargo")
	if trade_route_faction.economy.stock.get(Commodity.Type.ORE, 0.0) >= 50.0 and trade_route_faction.economy.stock.get(Commodity.Type.FOOD, 0.0) >= 50.0:
		failures.append("run_npc_trade_for_fleet: expected loading surplus to draw down the faction's own stock")

	# Arriving at HomeBase: dumps carried cargo into home_base_economy.stock,
	# then loads whatever the faction nets a deficit on (here, nothing is
	# consumed by mining/agriculture, so no deficit cargo should be loaded).
	trade_route_state.home_base_economy.stock[Commodity.Type.FUEL] = 20.0
	var cargo_before_dump: Dictionary = hauler.cargo.duplicate()
	trade_route_state.run_npc_trade_for_fleet(hauler, false)
	for commodity in cargo_before_dump:
		if trade_route_state.home_base_economy.stock.get(commodity, 0.0) < cargo_before_dump[commodity]:
			failures.append("run_npc_trade_for_fleet: expected carried cargo dumped into home_base_economy.stock")
	if hauler.cargo_total() != 0.0:
		failures.append("run_npc_trade_for_fleet: expected no deficit cargo loaded for a faction with no consuming slots, got cargo=%s" % hauler.cargo)

	# A faction with a deficit (Dominion needs Ore/Fuel/Food) loads from
	# home_base_economy.stock when arriving at HomeBase.
	var deficit_faction := PowerFaction.new()
	deficit_faction.faction_enum = CampaignFleet.Faction.DOMINION
	deficit_faction.economy = BaseEconomy.new()
	deficit_faction.economy.slots = [EconomyRole.industrial(), EconomyRole.population()]
	trade_route_state.factions.append(deficit_faction)
	trade_route_state.home_base_economy.stock[Commodity.Type.ORE] = 30.0

	var deficit_hauler := CampaignFleet.new()
	deficit_hauler.faction = CampaignFleet.Faction.DOMINION
	deficit_hauler.role = CampaignFleet.Role.TRADER
	deficit_hauler.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	trade_route_state.run_npc_trade_for_fleet(deficit_hauler, false)
	if deficit_hauler.cargo.get(Commodity.Type.ORE, 0.0) <= 0.0:
		failures.append("run_npc_trade_for_fleet: expected Dominion's hauler to load Ore (a deficit commodity) from home_base_economy.stock")

	# No-op cases: unknown faction, null economy, null home_base_economy.
	var orphan_hauler := CampaignFleet.new()
	orphan_hauler.faction = CampaignFleet.Faction.PIRATE
	trade_route_state.run_npc_trade_for_fleet(orphan_hauler, true)
	if orphan_hauler.cargo_total() != 0.0:
		failures.append("run_npc_trade_for_fleet: expected no-op for a faction with no matching PowerFaction")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `...Godot_v4.7.2-stable_win64_console.exe --headless --script tests/run_tests.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'run_npc_trade_for_fleet'`.

- [ ] **Step 3: Implement**

In `scripts/campaign/campaign_state.gd`, add near the bottom, after `_apply_reputation_loss`:

```gdscript
func run_npc_trade_for_fleet(fleet: CampaignFleet, at_home: bool) -> void:
	var faction := _power_faction_for(fleet.faction)
	if faction == null or faction.economy == null or home_base_economy == null:
		return
	if at_home:
		_load_surplus(fleet, faction.economy)
	else:
		_unload_and_load_deficit(fleet, faction.economy)

func _power_faction_for(faction_enum: CampaignFleet.Faction) -> PowerFaction:
	for faction in factions:
		if faction.faction_enum == faction_enum:
			return faction
	return null

func _load_surplus(fleet: CampaignFleet, economy: BaseEconomy) -> void:
	var net := economy.net_commodities()
	for commodity in net:
		if net[commodity] <= 0.0:
			continue
		var available: float = economy.stock.get(commodity, 0.0)
		var space: float = fleet.cargo_capacity() - fleet.cargo_total()
		var amount: float = min(available, space)
		if amount <= 0.0:
			continue
		economy.stock[commodity] = available - amount
		fleet.cargo[commodity] = fleet.cargo.get(commodity, 0.0) + amount

func _unload_and_load_deficit(fleet: CampaignFleet, economy: BaseEconomy) -> void:
	for commodity in fleet.cargo:
		var amount: float = fleet.cargo[commodity]
		if amount <= 0.0:
			continue
		home_base_economy.stock[commodity] = home_base_economy.stock.get(commodity, 0.0) + amount
	fleet.cargo = {}

	var net := economy.net_commodities()
	for commodity in net:
		if net[commodity] >= 0.0:
			continue
		var available: float = home_base_economy.stock.get(commodity, 0.0)
		var space: float = fleet.cargo_capacity() - fleet.cargo_total()
		var amount: float = min(available, space)
		if amount <= 0.0:
			continue
		home_base_economy.stock[commodity] = available - amount
		fleet.cargo[commodity] = fleet.cargo.get(commodity, 0.0) + amount
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command. Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_state.gd tests/test_campaign_state.gd
git commit -m "Add CampaignState.run_npc_trade_for_fleet for NPC hauler stock transfer"
```

---

### Task 7: Fleet allocation wiring in `CampaignState.tick_economy`

**Files:**
- Modify: `scripts/campaign/campaign_state.gd`
- Test: `tests/test_campaign_state.gd`

**Interfaces:**
- Consumes: `FleetAllocationPolicy.decide`/`.EconomicHealth`/`.Action`/`.MAX_FLEETS`/`.MAX_SHIPS_PER_FLEET` (Task 4), `CampaignFleet.role` (Task 3), `BaseEconomy.surplus_streak`/`.SURPLUS_STREAK_THRESHOLD` (Task 2).
- Produces: `signal fleet_spawn_requested(fleet: CampaignFleet)`, `signal fleet_role_changed(fleet: CampaignFleet)`, both emitted from `CampaignState.tick_economy`. Used by Task 10 (`CampaignScene._on_fleet_spawn_requested`/`_on_fleet_role_changed`).

- [ ] **Step 1: Write the failing test**

Add to the end of `tests/test_campaign_state.gd`'s `run() -> Array[String]` function (after the Task 6 additions), before `return failures`:

```gdscript
	# Fleet allocation: a faction outmatched by pirates, with a healthy
	# economy, grows a ship on its existing combat fleet.
	var grow_combat_state := CampaignState.new()
	var grow_combat_faction := PowerFaction.new()
	grow_combat_faction.faction_enum = CampaignFleet.Faction.DOMINION
	grow_combat_faction.economy = BaseEconomy.new()
	grow_combat_faction.economy.slots = [EconomyRole.mining()]  # no consumption -> never in deficit
	grow_combat_state.factions = [grow_combat_faction]
	grow_combat_state.home_base_economy = BaseEconomy.new()

	var weak_combat_fleet := CampaignFleet.new()
	weak_combat_fleet.faction = CampaignFleet.Faction.DOMINION
	weak_combat_fleet.role = CampaignFleet.Role.COMBAT
	weak_combat_fleet.ship_compositions = [{"max_hp": 10.0, "current_hp": 10.0, "max_shield": 0.0, "current_shield": 0.0}]
	var strong_pirate_fleet := CampaignFleet.new()
	strong_pirate_fleet.faction = CampaignFleet.Faction.PIRATE
	strong_pirate_fleet.ship_compositions = [{"max_hp": 1000.0, "current_hp": 1000.0, "max_shield": 0.0, "current_shield": 0.0}]
	grow_combat_state.enemy_fleets = [weak_combat_fleet, strong_pirate_fleet]

	var ships_before: int = weak_combat_fleet.ship_compositions.size()
	grow_combat_state.tick_economy(CampaignState.ECONOMY_TICK_INTERVAL)
	if weak_combat_fleet.ship_compositions.size() != ships_before + 1:
		failures.append("tick_economy: expected an outmatched combat fleet to grow a ship, had %d before, %d after" % [ships_before, weak_combat_fleet.ship_compositions.size()])

	# A faction that's economically strong and safe from pirates grows a new
	# trader fleet (spawn, since its one existing trader is already at the
	# ship cap would be a separate case -- here there is no trader fleet yet,
	# so this exercises the spawn-a-new-fleet path).
	var grow_trade_state := CampaignState.new()
	var grow_trade_faction := PowerFaction.new()
	grow_trade_faction.faction_enum = CampaignFleet.Faction.FREEHOLD
	grow_trade_faction.economy = BaseEconomy.new()
	grow_trade_faction.economy.slots = [EconomyRole.mining()]
	grow_trade_faction.base_position = Vector2(150, 150)
	grow_trade_state.factions = [grow_trade_faction]
	grow_trade_state.home_base_economy = BaseEconomy.new()

	var safe_combat_fleet := CampaignFleet.new()
	safe_combat_fleet.faction = CampaignFleet.Faction.FREEHOLD
	safe_combat_fleet.role = CampaignFleet.Role.COMBAT
	safe_combat_fleet.ship_compositions = [{"max_hp": 1000.0, "current_hp": 1000.0, "max_shield": 0.0, "current_shield": 0.0}]
	grow_trade_state.enemy_fleets = [safe_combat_fleet]

	var spawned := []
	grow_trade_state.fleet_spawn_requested.connect(func(fleet: CampaignFleet): spawned.append(fleet))
	for i in FleetAllocationPolicy.SURPLUS_STREAK_THRESHOLD + 1:
		grow_trade_state.tick_economy(CampaignState.ECONOMY_TICK_INTERVAL)
	if spawned.is_empty():
		failures.append("tick_economy: expected an economically strong, safe faction to spawn a new trader fleet")
	elif spawned[0].role != CampaignFleet.Role.TRADER:
		failures.append("tick_economy: expected the spawned fleet's role to be TRADER")

	# Reallocation: an outmatched faction in economic deficit with 2 trader
	# fleets flips one to COMBAT instead of growing (can't afford to grow).
	var reallocate_state := CampaignState.new()
	var reallocate_faction := PowerFaction.new()
	reallocate_faction.faction_enum = CampaignFleet.Faction.DOMINION
	reallocate_faction.economy = BaseEconomy.new()
	reallocate_faction.economy.slots = [EconomyRole.industrial()]  # will starve immediately, no inputs
	reallocate_state.factions = [reallocate_faction]
	reallocate_state.home_base_economy = BaseEconomy.new()

	var weak_combat_fleet_2 := CampaignFleet.new()
	weak_combat_fleet_2.faction = CampaignFleet.Faction.DOMINION
	weak_combat_fleet_2.role = CampaignFleet.Role.COMBAT
	weak_combat_fleet_2.ship_compositions = [{"max_hp": 1.0, "current_hp": 1.0, "max_shield": 0.0, "current_shield": 0.0}]
	var trader_fleet_1 := CampaignFleet.new()
	trader_fleet_1.faction = CampaignFleet.Faction.DOMINION
	trader_fleet_1.role = CampaignFleet.Role.TRADER
	trader_fleet_1.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0}]
	var trader_fleet_2 := CampaignFleet.new()
	trader_fleet_2.faction = CampaignFleet.Faction.DOMINION
	trader_fleet_2.role = CampaignFleet.Role.TRADER
	trader_fleet_2.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0}]
	var strong_pirate_fleet_2 := CampaignFleet.new()
	strong_pirate_fleet_2.faction = CampaignFleet.Faction.PIRATE
	strong_pirate_fleet_2.ship_compositions = [{"max_hp": 1000.0, "current_hp": 1000.0, "max_shield": 0.0, "current_shield": 0.0}]
	reallocate_state.enemy_fleets = [weak_combat_fleet_2, trader_fleet_1, trader_fleet_2, strong_pirate_fleet_2]

	var role_changes := []
	reallocate_state.fleet_role_changed.connect(func(fleet: CampaignFleet): role_changes.append(fleet))
	reallocate_state.tick_economy(CampaignState.ECONOMY_TICK_INTERVAL)
	if role_changes.size() != 1:
		failures.append("tick_economy: expected exactly one fleet reallocated to COMBAT, got %d" % role_changes.size())
	elif role_changes[0].role != CampaignFleet.Role.COMBAT:
		failures.append("tick_economy: expected the reallocated fleet's role to now be COMBAT")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `...Godot_v4.7.2-stable_win64_console.exe --headless --script tests/run_tests.gd`
Expected: FAIL — `Invalid access to property or key 'fleet_spawn_requested'` (signal doesn't exist yet), ship counts/role unchanged since `tick_economy` doesn't call any allocation logic yet.

- [ ] **Step 3: Implement**

In `scripts/campaign/campaign_state.gd`, add near the top with the other signals:

```gdscript
signal fleet_spawn_requested(fleet: CampaignFleet)
signal fleet_role_changed(fleet: CampaignFleet)
```

Change `tick_economy` from:

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
```

to:

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
				_apply_fleet_allocation(faction)
```

Add near the bottom, after `_power_faction_for` (from Task 6):

```gdscript
func _apply_fleet_allocation(faction: PowerFaction) -> void:
	var combat_fleets := _fleets_for(faction.faction_enum, CampaignFleet.Role.COMBAT)
	var trader_fleets := _fleets_for(faction.faction_enum, CampaignFleet.Role.TRADER)
	var economic_health := _economic_health(faction.economy)
	var threat_ratio := _threat_ratio(combat_fleets)
	var action := FleetAllocationPolicy.decide(economic_health, threat_ratio, trader_fleets.size())
	match action:
		FleetAllocationPolicy.Action.GROW_COMBAT:
			_grow_fleet(faction, combat_fleets, trader_fleets, CampaignFleet.Role.COMBAT)
		FleetAllocationPolicy.Action.GROW_TRADE:
			_grow_fleet(faction, combat_fleets, trader_fleets, CampaignFleet.Role.TRADER)
		FleetAllocationPolicy.Action.REALLOCATE_TO_COMBAT:
			if trader_fleets.size() > 1:
				trader_fleets[0].role = CampaignFleet.Role.COMBAT
				fleet_role_changed.emit(trader_fleets[0])
		FleetAllocationPolicy.Action.NONE:
			pass

func _fleets_for(faction_enum: CampaignFleet.Faction, role: CampaignFleet.Role) -> Array[CampaignFleet]:
	var result: Array[CampaignFleet] = []
	for fleet in enemy_fleets:
		if fleet.faction == faction_enum and fleet.role == role:
			result.append(fleet)
	return result

func _economic_health(economy: BaseEconomy) -> FleetAllocationPolicy.EconomicHealth:
	for streak in economy.deficit_streaks.values():
		if streak > 0:
			return FleetAllocationPolicy.EconomicHealth.DEFICIT
	if economy.surplus_streak >= BaseEconomy.SURPLUS_STREAK_THRESHOLD:
		return FleetAllocationPolicy.EconomicHealth.STRONG
	return FleetAllocationPolicy.EconomicHealth.STABLE

func _threat_ratio(combat_fleets: Array[CampaignFleet]) -> float:
	var pirate_strength := 0.0
	for fleet in enemy_fleets:
		if fleet.faction == CampaignFleet.Faction.PIRATE:
			pirate_strength += fleet.total_strength()
	var combat_strength := 0.0
	for fleet in combat_fleets:
		combat_strength += fleet.total_strength()
	return pirate_strength / max(combat_strength, 1.0)

func _grow_fleet(faction: PowerFaction, combat_fleets: Array[CampaignFleet], trader_fleets: Array[CampaignFleet], role: CampaignFleet.Role) -> void:
	var fleets_of_role := combat_fleets if role == CampaignFleet.Role.COMBAT else trader_fleets
	for fleet in fleets_of_role:
		if fleet.ship_compositions.size() < FleetAllocationPolicy.MAX_SHIPS_PER_FLEET:
			fleet.ship_compositions.append(_new_ship_template())
			return
	if combat_fleets.size() + trader_fleets.size() >= FleetAllocationPolicy.MAX_FLEETS:
		return
	var new_fleet := CampaignFleet.new()
	new_fleet.faction = faction.faction_enum
	new_fleet.role = role
	new_fleet.position = faction.base_position
	new_fleet.speed = 100.0
	new_fleet.ship_compositions = [_new_ship_template()]
	enemy_fleets.append(new_fleet)
	fleet_spawn_requested.emit(new_fleet)

func _new_ship_template() -> Dictionary:
	return {"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command. Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_state.gd tests/test_campaign_state.gd
git commit -m "Wire FleetAllocationPolicy into CampaignState.tick_economy"
```

---

### Task 8: `CampaignState.pending_loot_fleet` on combat victory

**Files:**
- Modify: `scripts/campaign/campaign_state.gd`
- Test: `tests/test_campaign_state.gd`

**Interfaces:**
- Produces: `CampaignState.pending_loot_fleet: CampaignFleet` (set by `resolve_engagement` when the destroyed enemy fleet had cargo, cleared by `reset()`). Used by Task 10 (`CampaignScene._ready`).

- [ ] **Step 1: Write the failing test**

Add to the end of `tests/test_campaign_state.gd`'s `run() -> Array[String]` function, before `return failures`:

```gdscript
	# resolve_engagement: a destroyed enemy fleet carrying cargo sets
	# pending_loot_fleet; one with no cargo leaves it null.
	var loot_state := CampaignState.new()
	var loot_player := CampaignFleet.new()
	loot_player.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	loot_state.player_fleet = loot_player
	var looted_enemy := CampaignFleet.new()
	looted_enemy.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	looted_enemy.cargo = {Commodity.Type.ORE: 5.0}
	loot_state.enemy_fleets = [looted_enemy]
	loot_state.start_engagement(looted_enemy)
	loot_state.resolve_engagement([{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}], [])
	if loot_state.pending_loot_fleet != looted_enemy:
		failures.append("resolve_engagement: expected pending_loot_fleet set to the destroyed cargo-carrying fleet")

	var no_loot_state := CampaignState.new()
	var no_loot_player := CampaignFleet.new()
	no_loot_player.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	no_loot_state.player_fleet = no_loot_player
	var empty_cargo_enemy := CampaignFleet.new()
	empty_cargo_enemy.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	no_loot_state.enemy_fleets = [empty_cargo_enemy]
	no_loot_state.start_engagement(empty_cargo_enemy)
	no_loot_state.resolve_engagement([{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}], [])
	if no_loot_state.pending_loot_fleet != null:
		failures.append("resolve_engagement: expected pending_loot_fleet to stay null for a fleet with no cargo")

	loot_state.pending_loot_fleet = looted_enemy
	loot_state.reset()
	if loot_state.pending_loot_fleet != null:
		failures.append("reset: expected pending_loot_fleet cleared to null")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `...Godot_v4.7.2-stable_win64_console.exe --headless --script tests/run_tests.gd`
Expected: FAIL — `Invalid get index 'pending_loot_fleet'`.

- [ ] **Step 3: Implement**

In `scripts/campaign/campaign_state.gd`, add near the other `var` declarations:

```gdscript
var pending_loot_fleet: CampaignFleet = null
```

In `reset()`, add `pending_loot_fleet = null` alongside the other resets.

In `resolve_engagement`, change:

```gdscript
		if active_enemy_fleet.is_destroyed():
			enemy_fleets.erase(active_enemy_fleet)
			_apply_reputation_loss(active_enemy_fleet.faction)
```

to:

```gdscript
		if active_enemy_fleet.is_destroyed():
			enemy_fleets.erase(active_enemy_fleet)
			_apply_reputation_loss(active_enemy_fleet.faction)
			if active_enemy_fleet.cargo_total() > 0.0:
				pending_loot_fleet = active_enemy_fleet
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command. Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_state.gd tests/test_campaign_state.gd
git commit -m "Set CampaignState.pending_loot_fleet when a cargo-carrying fleet is destroyed"
```

---

### Task 9: `LootPanel`

**Files:**
- Create: `scripts/campaign/loot_panel.gd`
- Create: `scenes/campaign/loot_panel.tscn`
- Create: `tests/test_loot_panel.gd`

**Interfaces:**
- Consumes: `CampaignFleet.cargo`/`.cargo_total()`/`.cargo_capacity()` (existing), `Commodity.NAMES` (existing).
- Produces: `LootPanel.open_for(defeated_fleet: CampaignFleet, player_fleet: CampaignFleet) -> void`, `LootPanel.close() -> void`, `LootPanel.refresh() -> void`, `LootPanel.visible: bool`. Used by Task 10 (`CampaignScene`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_loot_panel.gd`:

```gdscript
extends RefCounted

const LootPanelScene = preload("res://scenes/campaign/loot_panel.tscn")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")
const Commodity = preload("res://scripts/campaign/commodity.gd")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var panel: Control = LootPanelScene.instantiate()
	tree.root.add_child(panel)
	await tree.process_frame

	if panel.visible:
		failures.append("LootPanel: expected hidden by default")

	var defeated_fleet := CampaignFleet.new()
	defeated_fleet.cargo = {Commodity.Type.ORE: 3.0, Commodity.Type.FOOD: 0.0}
	var player_fleet := CampaignFleet.new()
	player_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	panel.open_for(defeated_fleet, player_fleet)
	if not panel.visible:
		failures.append("LootPanel: expected visible after open_for")
	if not panel._rows.has(Commodity.Type.ORE):
		failures.append("LootPanel: expected a row for Ore (nonzero cargo)")
	if panel._rows.has(Commodity.Type.FOOD):
		failures.append("LootPanel: expected no row for Food (zero cargo)")

	var take_button: Button = panel._rows[Commodity.Type.ORE]["take_button"]
	take_button.pressed.emit()
	if defeated_fleet.cargo.get(Commodity.Type.ORE, 0.0) != 2.0:
		failures.append("LootPanel: expected Take to remove 1 unit from the defeated fleet's cargo")
	if player_fleet.cargo.get(Commodity.Type.ORE, 0.0) != 1.0:
		failures.append("LootPanel: expected Take to add 1 unit to the player's cargo")

	# Take disabled once the player's cargo is full.
	player_fleet.cargo = {Commodity.Type.FUEL: player_fleet.cargo_capacity()}
	panel.refresh()
	if not take_button.disabled:
		failures.append("LootPanel: expected Take disabled when the player's cargo is full")

	# Take disabled once the defeated fleet's cargo for that commodity runs out.
	player_fleet.cargo = {}
	defeated_fleet.cargo[Commodity.Type.ORE] = 0.0
	panel.refresh()
	if not take_button.disabled:
		failures.append("LootPanel: expected Take disabled once the defeated fleet's cargo is exhausted")

	panel.close()
	if panel.visible:
		failures.append("LootPanel: expected hidden after close")

	panel.queue_free()
	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Register the new test in `tests/run_tests.gd`. Since `loot_panel.gd` will not bare-reference the `CampaignState` autoload (it only takes fleets passed into `open_for`), it's safe to `preload()` like `test_home_base.gd`. Add this block after the `home_base_test` block:

```gdscript
	var loot_panel_test = preload("res://tests/test_loot_panel.gd")
	var loot_panel_failures: Array[String] = await loot_panel_test.run_async(self)
	for f in loot_panel_failures:
		print("FAIL [%s]: %s" % [loot_panel_test.resource_path, f])
	total_failures += loot_panel_failures.size()
```

Run: `...Godot_v4.7.2-stable_win64_console.exe --headless --script tests/run_tests.gd`
Expected: FAIL — cannot preload `res://scenes/campaign/loot_panel.tscn` (doesn't exist yet).

- [ ] **Step 3: Implement**

Create `scripts/campaign/loot_panel.gd`:

```gdscript
class_name LootPanel
extends Control

var _defeated_fleet: CampaignFleet
var _player_fleet: CampaignFleet
var _rows: Dictionary = {}

@onready var rows_container: VBoxContainer = $RowsContainer
@onready var close_button: Button = $CloseButton

func _ready() -> void:
	close_button.pressed.connect(close)
	visible = false

func open_for(defeated_fleet: CampaignFleet, player_fleet: CampaignFleet) -> void:
	_defeated_fleet = defeated_fleet
	_player_fleet = player_fleet
	visible = true
	_rebuild_rows()

func close() -> void:
	visible = false
	_defeated_fleet = null
	_player_fleet = null

func refresh() -> void:
	if _defeated_fleet == null or _player_fleet == null:
		return
	for commodity in _rows.keys():
		var row: Dictionary = _rows[commodity]
		var available: float = _defeated_fleet.cargo.get(commodity, 0.0)
		row["label"].text = "%s  available:%.0f" % [Commodity.NAMES[commodity], available]
		row["take_button"].disabled = available < 1.0 or _player_fleet.cargo_total() + 1.0 > _player_fleet.cargo_capacity()

func _rebuild_rows() -> void:
	for child in rows_container.get_children():
		child.queue_free()
	_rows = {}
	for commodity in _defeated_fleet.cargo.keys():
		if _defeated_fleet.cargo[commodity] <= 0.0:
			continue
		var row_box := HBoxContainer.new()
		var label := Label.new()
		var take_button := Button.new()
		take_button.text = "Take"
		take_button.pressed.connect(_on_take_pressed.bind(commodity))
		row_box.add_child(label)
		row_box.add_child(take_button)
		rows_container.add_child(row_box)
		_rows[commodity] = {"label": label, "take_button": take_button}
	refresh()

func _on_take_pressed(commodity: int) -> void:
	var available: float = _defeated_fleet.cargo.get(commodity, 0.0)
	if available < 1.0 or _player_fleet.cargo_total() + 1.0 > _player_fleet.cargo_capacity():
		return
	_defeated_fleet.cargo[commodity] = available - 1.0
	_player_fleet.cargo[commodity] = _player_fleet.cargo.get(commodity, 0.0) + 1.0
	refresh()
```

Create `scenes/campaign/loot_panel.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/campaign/loot_panel.gd" id="1"]

[node name="LootPanel" type="Control"]
offset_left = 200.0
offset_top = 100.0
offset_right = 700.0
offset_bottom = 450.0
mouse_filter = 2
script = ExtResource("1")

[node name="RowsContainer" type="VBoxContainer" parent="."]
offset_top = 0.0
offset_right = 500.0
offset_bottom = 300.0

[node name="CloseButton" type="Button" parent="."]
offset_top = 310.0
offset_right = 100.0
offset_bottom = 340.0
text = "Close"
```

Run the editor-cache-warm step once (new `class_name` file):

```bash
"C:\Users\corbi\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --headless --editor --quit
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command. Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/loot_panel.gd scenes/campaign/loot_panel.tscn tests/test_loot_panel.gd tests/run_tests.gd
git commit -m "Add LootPanel for taking cargo from defeated fleets"
```

---

### Task 10: Wire everything into `CampaignScene`

**Files:**
- Modify: `scripts/campaign/campaign_scene.gd`
- Modify: `scenes/campaign/campaign_scene.tscn`
- Test: `tests/test_campaign_scene.gd`, `tests/test_campaign_economy_bootstrap.gd`

**Interfaces:**
- Consumes: `CampaignFleetIcon.set_route_endpoints`/`.trader_arrived` (Task 5), `CampaignState.run_npc_trade_for_fleet` (Task 6), `CampaignState.fleet_spawn_requested`/`.fleet_role_changed` (Task 7), `CampaignState.pending_loot_fleet` (Task 8), `LootPanel.open_for` (Task 9), `EconomyRole.refinery()` (Task 1), `CampaignFleet.role` (Task 3).
- Produces: `CampaignScene._behavior_for_fleet(fleet: CampaignFleet) -> CampaignFleetIcon.BehaviorType` (replaces the old `_behavior_for_faction`), `CampaignScene._setup_enemy_icon(fleet: CampaignFleet) -> CampaignFleetIcon`, `CampaignScene._configure_trade_route(icon, fleet) -> void`. Bootstrap now creates one `TRADER`-role fleet per power faction in addition to the existing `COMBAT`-role one, and `home_base_economy` gains a `refinery()` slot.

- [ ] **Step 1: Write the failing test**

First, fix the two existing tests that assumed exactly one enemy icon per power faction (now there are two: one `COMBAT`, one `TRADER`).

In `tests/test_campaign_scene.gd`, replace:

```gdscript
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

with:

```gdscript
	var dominion_icon: CampaignFleetIcon = null
	var freehold_icon: CampaignFleetIcon = null
	var dominion_trader_icon: CampaignFleetIcon = null
	var freehold_trader_icon: CampaignFleetIcon = null
	for icon in scene.enemy_icons:
		if icon.fleet.faction == CampaignFleet.Faction.DOMINION and icon.fleet.role == CampaignFleet.Role.COMBAT:
			dominion_icon = icon
		elif icon.fleet.faction == CampaignFleet.Faction.FREEHOLD and icon.fleet.role == CampaignFleet.Role.COMBAT:
			freehold_icon = icon
		elif icon.fleet.faction == CampaignFleet.Faction.DOMINION and icon.fleet.role == CampaignFleet.Role.TRADER:
			dominion_trader_icon = icon
		elif icon.fleet.faction == CampaignFleet.Faction.FREEHOLD and icon.fleet.role == CampaignFleet.Role.TRADER:
			freehold_trader_icon = icon
	if dominion_icon == null or freehold_icon == null:
		failures.append("expected both a DOMINION and a FREEHOLD combat-role enemy icon spawned")
	elif dominion_icon.behavior_type != CampaignFleetIcon.BehaviorType.PATROL:
		failures.append("expected DOMINION combat fleet to use PATROL behavior at starting (non-hostile) reputation, got %s" % dominion_icon.behavior_type)
	if dominion_trader_icon == null or freehold_trader_icon == null:
		failures.append("expected both a DOMINION and a FREEHOLD trader-role enemy icon spawned")
	elif dominion_trader_icon.behavior_type != CampaignFleetIcon.BehaviorType.TRADER:
		failures.append("expected DOMINION trader fleet to use TRADER behavior, got %s" % dominion_trader_icon.behavior_type)
```

In `tests/test_campaign_economy_bootstrap.gd`, replace:

```gdscript
	if campaign_state.home_base_economy == null:
		failures.append("expected bootstrap to set CampaignState.home_base_economy")
	elif campaign_state.home_base_economy.slots.size() != 1 or campaign_state.home_base_economy.slots[0].role_type != EconomyRole.RoleType.TRADE_HUB:
		failures.append("expected home_base_economy to have a single TRADE_HUB slot")
```

with:

```gdscript
	if campaign_state.home_base_economy == null:
		failures.append("expected bootstrap to set CampaignState.home_base_economy")
	else:
		var home_role_types: Array = campaign_state.home_base_economy.slots.map(func(s): return s.role_type)
		if not home_role_types.has(EconomyRole.RoleType.TRADE_HUB):
			failures.append("expected home_base_economy to have a TRADE_HUB slot")
		if not home_role_types.has(EconomyRole.RoleType.REFINERY):
			failures.append("expected home_base_economy to have a REFINERY slot")
```

Now add a new scene-tree check to `tests/test_campaign_scene.gd`, appended right after the block above (still before the skirmish-triggering code that follows it):

```gdscript
	if dominion_trader_icon != null:
		var dominion_power_faction: PowerFaction = null
		for faction in campaign_state.factions:
			if faction.faction_enum == CampaignFleet.Faction.DOMINION:
				dominion_power_faction = faction
		if dominion_power_faction == null:
			failures.append("expected a DOMINION PowerFaction to look up its base_position")
		else:
			dominion_trader_icon.global_position = dominion_power_faction.base_position
			for i in 5:
				await tree.physics_frame
			var ore_before: float = dominion_power_faction.economy.stock.get(Commodity.Type.ORE, 0.0)
			# The trader route's "home" endpoint is the faction base; placing
			# the icon there and letting it tick should trigger a trader_arrived
			# arrival and load surplus cargo via CampaignState.run_npc_trade_for_fleet.
			if dominion_trader_icon.fleet.cargo_total() <= 0.0 and ore_before > 0.0:
				failures.append("expected the DOMINION trader icon to have loaded surplus cargo after reaching its faction base")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `...Godot_v4.7.2-stable_win64_console.exe --headless --script tests/run_tests.gd`
Expected: FAIL — multiple failures: the renamed/split icon lookups find only one trader-role icon's worth of nulls (bootstrap doesn't create trader fleets yet), the REFINERY slot check fails (role not in home_base_economy yet), and the trader-cargo check fails (no route wiring yet). The exact failure text will reference `CampaignFleet.Role.TRADER` combat-role filtering finding nulls where `COMBAT`-role fleets are expected but the only fleet present has no `role` distinction applied in the old spawn loop — this is expected until Step 3.

- [ ] **Step 3: Implement**

In `scripts/campaign/campaign_scene.gd`, in `_bootstrap_default_campaign()`, after the existing `dominion_fleet`/`freehold_fleet` creation (which stays as the `COMBAT`-role fleet, `role` defaults to `COMBAT` so no change needed there) and before `CampaignState.enemy_fleets = [...]`, add:

```gdscript
	var dominion_trader_fleet := CampaignFleet.new()
	dominion_trader_fleet.faction = CampaignFleet.Faction.DOMINION
	dominion_trader_fleet.role = CampaignFleet.Role.TRADER
	dominion_trader_fleet.position = dominion_faction.base_position
	dominion_trader_fleet.speed = 100.0
	dominion_trader_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	var freehold_trader_fleet := CampaignFleet.new()
	freehold_trader_fleet.faction = CampaignFleet.Faction.FREEHOLD
	freehold_trader_fleet.role = CampaignFleet.Role.TRADER
	freehold_trader_fleet.position = freehold_faction.base_position
	freehold_trader_fleet.speed = 100.0
	freehold_trader_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
```

Change the line:

```gdscript
	CampaignState.enemy_fleets = [pirate, trader, patrol, dominion_fleet, freehold_fleet]
```

to:

```gdscript
	CampaignState.enemy_fleets = [pirate, trader, patrol, dominion_fleet, freehold_fleet, dominion_trader_fleet, freehold_trader_fleet]
```

Change:

```gdscript
	CampaignState.home_base_economy.slots = [EconomyRole.trade_hub()]
	CampaignState.home_base_economy.max_slots = 1
```

to:

```gdscript
	CampaignState.home_base_economy.slots = [EconomyRole.trade_hub(), EconomyRole.refinery()]
	CampaignState.home_base_economy.max_slots = 2
```

Replace `_behavior_for_faction` with:

```gdscript
func _behavior_for_fleet(fleet: CampaignFleet) -> CampaignFleetIcon.BehaviorType:
	match fleet.faction:
		CampaignFleet.Faction.PIRATE:
			return CampaignFleetIcon.BehaviorType.PIRATE
		CampaignFleet.Faction.TRADER:
			return CampaignFleetIcon.BehaviorType.TRADER
		CampaignFleet.Faction.DOMINION, CampaignFleet.Faction.FREEHOLD:
			if fleet.role == CampaignFleet.Role.TRADER:
				return CampaignFleetIcon.BehaviorType.TRADER
			return CampaignFleetIcon.BehaviorType.PIRATE if _is_faction_hostile(fleet.faction) else CampaignFleetIcon.BehaviorType.PATROL
		_:
			return CampaignFleetIcon.BehaviorType.PATROL
```

Replace the `_ready()` enemy-spawn loop:

```gdscript
	for enemy_fleet in CampaignState.enemy_fleets:
		var behavior := _behavior_for_faction(enemy_fleet.faction)
		var icon := _spawn_icon(enemy_fleet, behavior)
		icon.player_target = player_icon
		icon.area_entered.connect(_on_enemy_area_entered.bind(icon))
		enemy_icons.append(icon)
```

with:

```gdscript
	for enemy_fleet in CampaignState.enemy_fleets:
		_setup_enemy_icon(enemy_fleet)
```

At the end of `_ready()`, after the `CampaignState.skirmish_resolved.connect(_on_skirmish_resolved)` line, add:

```gdscript
	CampaignState.fleet_spawn_requested.connect(_on_fleet_spawn_requested)
	CampaignState.fleet_role_changed.connect(_on_fleet_role_changed)

	if CampaignState.pending_loot_fleet != null:
		loot_panel.open_for(CampaignState.pending_loot_fleet, CampaignState.player_fleet)
		CampaignState.pending_loot_fleet = null
```

Add the `@onready` for the new panel alongside the existing one:

```gdscript
@onready var loot_panel: LootPanel = $LootPanel
```

Add these new methods (anywhere after `_spawn_icon`):

```gdscript
func _setup_enemy_icon(fleet: CampaignFleet) -> CampaignFleetIcon:
	var behavior := _behavior_for_fleet(fleet)
	var icon := _spawn_icon(fleet, behavior)
	icon.player_target = player_icon
	icon.area_entered.connect(_on_enemy_area_entered.bind(icon))
	icon.trader_arrived.connect(_on_trader_arrived.bind(icon))
	enemy_icons.append(icon)
	_configure_trade_route(icon, fleet)
	return icon

func _on_fleet_spawn_requested(fleet: CampaignFleet) -> void:
	_setup_enemy_icon(fleet)

func _on_fleet_role_changed(fleet: CampaignFleet) -> void:
	for icon in enemy_icons:
		if icon.fleet == fleet:
			icon.behavior_type = _behavior_for_fleet(fleet)
			_configure_trade_route(icon, fleet)
			break

func _on_trader_arrived(at_home: bool, icon: CampaignFleetIcon) -> void:
	if icon.fleet.faction == CampaignFleet.Faction.DOMINION or icon.fleet.faction == CampaignFleet.Faction.FREEHOLD:
		CampaignState.run_npc_trade_for_fleet(icon.fleet, at_home)

func _configure_trade_route(icon: CampaignFleetIcon, fleet: CampaignFleet) -> void:
	if fleet.faction != CampaignFleet.Faction.DOMINION and fleet.faction != CampaignFleet.Faction.FREEHOLD:
		return
	var faction: PowerFaction = null
	for f in CampaignState.factions:
		if f.faction_enum == fleet.faction:
			faction = f
			break
	if faction == null:
		return
	if fleet.role == CampaignFleet.Role.TRADER:
		icon.set_route_endpoints(faction.base_position, HOME_BASE_POSITION)
	else:
		icon.set_route_endpoints(faction.base_position, faction.base_position)
```

Finally, in `scenes/campaign/campaign_scene.tscn`, add the `LootPanel` scene instance. Add after the existing `ext_resource` line for `TradePanel`:

```
[ext_resource type="PackedScene" path="res://scenes/campaign/loot_panel.tscn" id="3"]
```

And after the existing `TradePanel` node, add:

```
[node name="LootPanel" type="Control" parent="." instance=ExtResource("3")]
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command. Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_scene.gd scenes/campaign/campaign_scene.tscn tests/test_campaign_scene.gd tests/test_campaign_economy_bootstrap.gd
git commit -m "Wire faction trader fleets, allocation policy, and loot into CampaignScene"
```

---

### Task 11: Full test suite pass and final review

**Files:**
- None new — verification only.

- [ ] **Step 1: Run the full suite**

Run: `...Godot_v4.7.2-stable_win64_console.exe --headless --script tests/run_tests.gd`
Expected: `All tests passed.` with zero failures across all registered tests (old and new).

- [ ] **Step 2: Confirm new `class_name` files were cache-warmed**

If any test fails with `Identifier "X" not declared` for `FleetAllocationPolicy` or `LootPanel`, run:

```bash
"C:\Users\corbi\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --headless --editor --quit
```

then re-run the test suite.

- [ ] **Step 3: Manual sanity check (if a GUI session is available)**

Open the project in the Godot editor, run the campaign scene, and confirm: Dominion/Freehold each show two fleet icons near their base at start (one patrol-ish, one that beelines toward HomeBase); docking at HomeBase shows Fuel's stock slowly climbing from the new refinery; after a few minutes Dominion's industrial stock no longer collapses to zero and stays replenished. If no GUI session is available, say so explicitly rather than claiming this was verified.

- [ ] **Step 4: Commit (only if Step 2 required a fix)**

```bash
git add -A
git commit -m "Fix class cache / test ordering issues found in final verification"
```
