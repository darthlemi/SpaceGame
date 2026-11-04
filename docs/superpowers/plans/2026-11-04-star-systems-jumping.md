# Star Systems and Jumping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **SpaceGame execution defaults** (memory `token-efficient-execution`): work directly on `main`.
> - Run one batched reviewer after Task 2, one after Tasks 3-4, and a final whole-change review on the most capable model after Task 5.
> - Don't re-review fixes under ~50 lines.
> - Fix rounds go to a fresh, cheap subagent given only the finding and the file paths.
> - Subagents report in 10 lines or fewer.

**Goal:** Replace the single campaign map with a fixed galaxy of 26 connected star systems. The player and every AI fleet travel between them with a 3-second, fuel-costed, catchable warp. A full-screen jump map with discovery supports the player.

**Architecture:**
- **Data:** galaxy data (systems, links, stations) lives in `Galaxy`, built by `GalaxyData.build()` and held by the `CampaignState` autoload, together with every fleet's system, warp and route state. That way it survives the scene reload around combat.
- **Scene:** `CampaignScene` builds one `SystemLayer` node per system. The current layer sits at the world origin and is visible. Every other layer sits at its own far offset, hidden but still simulating, so physics overlaps can never cross systems.
- **Rules:** jump, tier and NPC jump rules are pure static classes with unit tests.

**Tech Stack:** Godot 4 (GDScript). The tests are the hand-rolled suite in `tests\run_tests.gd`: `static func run() -> Array[String]` for synchronous tests, `static func run_async(tree) -> Array[String]` for scene tests.

**Spec:** `docs\superpowers\specs\2026-11-04-star-systems-jumping-design.md`

## Global Constraints

- **Running tests:** use PowerShell. stdout is only captured through `Start-Process` redirection.
  ```powershell
  $godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
  Start-Process -FilePath $godot -ArgumentList '--headless','--path','.','--script','res://tests/run_tests.gd' -RedirectStandardOutput test_output.txt -RedirectStandardError test_error.txt -Wait -NoNewWindow
  Select-String -Path test_output.txt,test_error.txt -Pattern 'FAIL|SCRIPT ERROR'
  ```
  - **A clean run** is only the known flake: `test_campaign_long_run_sim.gd`, 5-6 pirate-targeting FAILs. There must be no `SCRIPT ERROR`.
  - **New `class_name` files or PNG imports** need one warm pass first: `--headless --editor --quit`. It rewrites `.import` files with CRLF-only churn. Never commit that churn; see the carry-forward for how to clear it.
- **Registering tests:**
  - New synchronous test files go in the `preload` list in `tests\run_tests.gd`.
  - Tests that touch the `CampaignState` autoload are `run_async` and loaded with `load()`, placed after the existing `campaign_scene_test` block.
- **Credits are `int`.** Fuel is `CampaignFleet.cargo[Commodity.Type.FUEL]`, a `float`.
- **HUD panels** drawn over the play area need a `MOUSE_FILTER_STOP` background. UI uses the existing theme (holo chrome).
- **Freed objects:** an `is_instance_valid` guard needs an untyped parameter. Call `is_instance_valid` before `is T` on rosters that can hold freed nodes.
- **No new `DOMINION or FREEHOLD` branches.** Decide by station owner, fleet role, or the existing `_is_power_faction`.
- **Line endings:** never use `sed -i` on `.gd` files from Git Bash (it strips CRLF). Use the Edit tool or Python with `newline=''`.
- **Committing:** commit per task on `main` with a plain-sentence message ending in `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push.

## Review Focus

1. **Jumping while docked or with a dock sub-panel open:** the dock UI closes, the fleet undocks, and the warp starts. Test: Task 4, `jump_while_docked_undocks`.
2. **Returning from combat in a non-start system, while an NPC elsewhere is mid-warp:** the player is back in the same system and the NPC's countdown continues. Test: Task 4, `combat_round_trip_keeps_system_and_npc_warp`.
3. **Total loss in a far system:** the player respawns at HomeBase in the start system, and the start layer is shown. Test: Task 3, `respawn_returns_to_home_system`.
4. **Pressing J while the engage prompt or respawn screen is open:** the map doesn't open. Test: Task 4, `jump_map_blocked_by_modals`.
5. **An NPC with fuel for only one jump:** it never leaves home on a jump it can't come back from, and an NPC away from home heads home rather than idling forever. Test: Task 5, `planner_respects_round_trip_fuel`.

---

### Task 1: Galaxy model, layout data and pure rules

Pure data and rules, with no scene changes. Everything here is unit-testable without the autoload.

**Files:**
- Create: `scripts\campaign\star_system.gd`, `scripts\campaign\station_data.gd`, `scripts\campaign\galaxy.gd`, `scripts\campaign\galaxy_data.gd`, `scripts\campaign\jump_rules.gd`, `scripts\campaign\danger_tier.gd`
- Modify: `scripts\campaign\campaign_fleet.gd` (new fields and helpers)
- Test: `tests\test_galaxy.gd`, `tests\test_galaxy_data.gd`, `tests\test_jump_rules.gd`, `tests\test_danger_tier.gd`, `tests\test_campaign_fleet.gd` (extend), `tests\run_tests.gd`

**Interfaces (Produces):**
- **`StarSystem` (Resource):**
  - `id: String`, `display_name: String`, `map_position: Vector2` (normalised 0..1 jump-map coordinates).
  - `links: Array[String]`, `tier: int = 1`, `tier_override: int = 0`.
- **`StationData` (Resource):**
  - Fields: `id: String`, `display_name: String`, `system_id: String`, `position: Vector2` (in-system), `owner: CampaignFleet.Faction`.
  - `art: String`: a basename such as `"ring_2"`.
  - `economy: BaseEconomy`, `fleet_quota: Dictionary` (Role -> int), `respawn_timers: Dictionary` (Role -> float).
  - `func is_home() -> bool` returns `owner == Faction.PLAYER`.
  - `func texture_path() -> String` returns `"res://assets/sprites/stations/%s.png" % art`.
- **`Galaxy` (RefCounted):**
  - Fields: `systems: Dictionary` (id -> StarSystem), `stations: Array[StationData]`, `start_system_id: String`.
  - Lookups:
    - `system(id) -> StarSystem`
    - `station(id) -> StationData`
    - `stations_in(system_id) -> Array[StationData]`
    - `home_station() -> StationData`
  - Graph queries:
    - `neighbours(id) -> Array[String]`
    - `are_linked(a, b) -> bool`
    - `path(from_id, to_id) -> Array[String]`: BFS that excludes `from` and includes `to`. Returns `[]` when the two are the same or `to` is unreachable.
    - `jump_distance(from_id, to_id) -> int`: `-1` when unreachable.
  - Setup:
    - `link(a, b) -> void`: adds both directions.
    - `assign_tiers() -> void`: `tier = tier_override if > 0 else clampi(jump_distance(start, id), 1, 5)`.
- **`GalaxyData`:** `static func build() -> Galaxy`. It returns the layout below, with links added and `assign_tiers()` called. Each station's `economy` is a fresh `BaseEconomy` with the listed roles and `max_slots = 2`. Stock, population and crew are seeded in Task 2, not here.
- **`JumpRules` (static):**
  - Constants:
    - `WARP_DURATION := 3.0`
    - `JUMP_FUEL_FACTOR := 1.8`: the starter fleet burns 5.5, so it pays 9.9 of its 30 starting fuel.
    - `SYSTEM_MIN := Vector2(40, 90)` and `SYSTEM_MAX := Vector2(1112, 608)`: the 1152x648 viewport, minus a margin and the HUD strip.
    - `ARRIVAL_EDGE_MARGIN := 60.0`, `ARRIVAL_RADIUS := 80.0`, `DISTRESS_PRICE_MULTIPLIER := 3`.
  - Functions:
    - `jump_cost(fleet: CampaignFleet) -> float`: `fleet.fuel_burn_per_distance() * CampaignFleet.FUEL_BURN_DISTANCE * JUMP_FUEL_FACTOR`.
    - `can_afford(fleet) -> bool`
    - `clamp_to_system(p: Vector2) -> Vector2`
    - `edge_point(direction: Vector2) -> Vector2`
    - `arrival_point(origin_map_pos: Vector2, dest_map_pos: Vector2, rng: RandomNumberGenerator) -> Vector2`
    - `distress_quote(fleet, credits: int) -> Dictionary`, returning `{"fuel": float, "price": int, "ok": bool, "reason": String}`.
- **`DangerTier` (static):**
  - `fleet_for(tier: int, role: CampaignFleet.Role, rng: RandomNumberGenerator) -> Array[Dictionary]`
  - `const COMBAT_SHIPS`, `TRADER_SHIPS`, `WEAPON_RARITY_RANGE`, `CREW_FRACTION`, as defined in Step 5.
- **`CampaignFleet` additions:**
  - Fields: `@export var system_id: String = ""`, `home_station_id: String = ""`, `warp_remaining: float = 0.0`, `warp_target: String = ""`, `jump_path: Array[String] = []`, `dest_station_id: String = ""`, `jump_cooldown: float = 0.0`.
  - `func is_warping() -> bool` returns `warp_remaining > 0.0`.
  - `func start_warp(target: String) -> void` sets `warp_remaining = JumpRules.WARP_DURATION`.
  - `func cancel_warp() -> void` sets `warp_remaining = 0.0` and `warp_target = ""`.
  - `func max_strength() -> float` sums `max_hp + max_shield`.

**Galaxy layout (the user adjusts this later; keep it readable as data, not code):**

Systems: `id (map x, y)`. The tier is the jump distance from `haven`, so it isn't listed.

| id | name | map | stations: `Name, owner, (x, y), art, roles, quota` |
|---|---|---|---|
| aurum | Aurum | (0.70, 0.76) | Aurum Spire, D, (300,250), spoke_3, industrial+refinery, C1 T1; Aurum Bazaar, N, (850,420), cross_2, trade_hub+population, T1 |
| ashfall | Ashfall | (0.97, 0.08) | Ashfall Citadel, P, (850,420), ring_2, refinery+population, C2; Ashfall Yard, P, (300,250), cross_3, refinery+trade_hub, C1 |
| bastion | Bastion | (0.73, 0.58) | Bastion, D, (580,350), ring_4, industrial+population, C2 T1; Bastion Yards, D, (850,500), truss_6, industrial+refinery, T1 |
| blackwake | Blackwake | (0.66, 0.16) | Blackwake Den, P, (580,350), spoke_4, refinery+trade_hub, C2 |
| cinder | Cinder | (0.36, 0.34) | Cinder Works, F, (300,250), truss_5, mining+refinery, C1 T1; Cinder Market, N, (850,420), cross_2, trade_hub+population, T1 |
| crownspire | Crownspire | (0.92, 0.26) | Crownspire, D, (580,350), ring_3, industrial+population, C2 T1 |
| deadreach | Deadreach | (0.04, 0.08) | Deadreach Citadel, P, (300,250), truss_1, refinery+population, C2; Deadreach Yard, P, (850,420), spoke_4, refinery+trade_hub, C1 |
| farhaven | Farhaven | (0.08, 0.26) | Farhaven, N, (580,350), arcs_2, agriculture+mining, C1 T1 |
| freeport | Freeport | (0.17, 0.42) | Freeport, N, (300,250), cross_1, trade_hub+population, T1; Freehold Watch, F, (850,420), truss_1, mining+agriculture, C1 |
| frostline | Frostline | (0.50, 0.08) | Frostline Relay, N, (580,350), ring_4, mining+refinery, C1 T1 |
| gallows | Gallows | (0.34, 0.16) | Gallows Roost, P, (580,350), truss_3, refinery+trade_hub, C2 |
| greenreach | Greenreach | (0.27, 0.58) | Greenreach, F, (580,350), ring_3, mining+agriculture, C2 T1; Greenreach Fields, F, (300,500), arcs_2, agriculture+population, T1 |
| haven | Haven | (0.50, 0.50) | Home Base, PLAYER, (600,400), ring_2, trade_hub+refinery, none; Haven Exchange, N, (300,250), cross_1, trade_hub+population, T1 |
| ironhold | Ironhold | (0.83, 0.42) | Ironhold, D, (580,350), ring_2, industrial+population, C2 T1 |
| kestrel | Kestrel | (0.62, 0.50) | Kestrel Picket, D, (300,250), spoke_2, industrial+refinery, C1 T1 |
| marrow | Marrow | (0.50, 0.64) | Marrow Depot, N, (300,250), truss_3, agriculture+trade_hub, T1; Marrow Hideout, P, (850,420), spoke_3, refinery+trade_hub, C1 |
| northgate | Northgate | (0.50, 0.22) | Northgate Hub, N, (580,350), arcs_3, trade_hub+population, C1 T1 |
| redtide | Redtide | (0.82, 0.90) | Redtide Lair, P, (580,350), spoke_3, refinery+trade_hub, C2 |
| saltmarsh | Saltmarsh | (0.18, 0.90) | Saltmarsh Den, P, (580,350), truss_6, refinery+trade_hub, C2 |
| slagfall | Slagfall | (0.64, 0.34) | Slagfall Foundry, D, (850,420), spoke_4, industrial+refinery, C1 T1; Slagfall Exchange, N, (300,250), cross_3, trade_hub+agriculture, T1 |
| southdeep | Southdeep | (0.50, 0.78) | Southdeep Den, P, (580,350), spoke_2, refinery+trade_hub, C2 |
| thornfield | Thornfield | (0.30, 0.76) | Thornfield, F, (580,350), arcs_1, agriculture+population, C1 T1 |
| tollgate | Tollgate | (0.50, 0.36) | Tollgate Station, N, (580,520), arcs_1, trade_hub+refinery, C1 T1 |
| voidmouth | Voidmouth | (0.62, 0.03) | Voidmouth Hold, P, (580,350), arcs_3, refinery+trade_hub, C2 |
| wexford | Wexford | (0.38, 0.50) | Wexford Outpost, F, (850,420), truss_1, mining+refinery, C1 T1 |
| wreckyard | Wreckyard | (0.50, 0.92) | Wreckyard Salvage, N, (300,250), truss_5, industrial+trade_hub, T1; Wreckyard Roost, P, (850,420), spoke_2, refinery+trade_hub, C1 |

Owners: D = DOMINION, F = FREEHOLD, N = NEUTRAL, P = PIRATE. Quotas: C = `Role.COMBAT`, T = `Role.TRADER`. Station ids are the snake_case name, for example `haven_exchange`. Start system: `haven`.

Links (40 pairs): haven-wexford, haven-kestrel, haven-tollgate, haven-marrow, wexford-greenreach, wexford-cinder, kestrel-bastion, kestrel-slagfall, tollgate-cinder, tollgate-slagfall, tollgate-northgate, marrow-greenreach, marrow-bastion, marrow-southdeep, greenreach-freeport, greenreach-thornfield, cinder-freeport, cinder-gallows, bastion-ironhold, bastion-aurum, slagfall-ironhold, slagfall-blackwake, northgate-gallows, northgate-blackwake, northgate-frostline, southdeep-thornfield, southdeep-aurum, southdeep-wreckyard, freeport-farhaven, thornfield-saltmarsh, ironhold-crownspire, aurum-redtide, gallows-farhaven, blackwake-crownspire, blackwake-voidmouth, frostline-voidmouth, wreckyard-saltmarsh, wreckyard-redtide, farhaven-deadreach, crownspire-ashfall.

- [ ] **Step 1: Write the failing tests.** Each check appends a failure string on mismatch.
  - `test_galaxy.gd`, on a hand-built 4-system graph a-b, b-c, c-d with start `a`:
    - `path("a","d") == ["b","c","d"]`
    - `path("a","a") == []`
    - `path` to an unlinked `e` is `[]`, and `jump_distance("a","e") == -1`
    - `are_linked("b","a")` is true
    - after `assign_tiers()`: `a` = 1, `b` = 1, `c` = 2, `d` = 3
    - with `tier_override = 5` on `b`, `b` = 5
    - `stations_in` filters by system, and `home_station()` returns the PLAYER-owned station
  - `test_galaxy_data.gd`, on `GalaxyData.build()`:
    - 26 systems
    - every link is symmetric
    - every system can be reached from `haven`
    - every system has at least 1 station
    - exactly 1 PLAYER station, in `haven`
    - tiers: `haven` = 1, `wexford` = 1, `greenreach` = 2, `deadreach` = 5, `ashfall` = 5
    - every station position lies within `JumpRules.SYSTEM_MIN..SYSTEM_MAX`
    - every `texture_path()` passes `ResourceLoader.exists`
    - station ids are unique
  - `test_jump_rules.gd`:
    - **Cost:** `jump_cost` for a corvette + capital + freighter fleet is about 9.9 (within 0.001). `can_afford` is false at 9.8 fuel and true at 9.9.
    - **Arrival:**
      - `arrival_point` with origin map (0, 0.5) and destination (1, 0.5) gives x <= `SYSTEM_MIN.x + ARRIVAL_EDGE_MARGIN + ARRIVAL_RADIUS`. The origin is to the west, so arrival is at the west edge.
      - the result is always inside the system bounds over 50 seeded rolls;
      - identical origin and destination positions don't crash and stay in bounds.
    - **`distress_quote`:**
      - a fleet 4.0 fuel short with 1000 credits gives `{"fuel": 4.0, "price": 144, "ok": true}`;
      - with 100 credits, `ok` is false and the reason starts with `"Not enough credits"`;
      - with full cargo, `ok` is false and the reason is `"No cargo room for fuel"`.
  - `test_danger_tier.gd`, with a seeded RNG:
    - tier 1 COMBAT gives 1 corvette;
    - tier 5 COMBAT gives 2 capitals and 1 corvette;
    - tier 3 TRADER gives 2 freighters;
    - every weapon id in `weapon_mount_items` at tier 1 is COMMON (rarity 0);
    - at tier 5, every weapon has rarity >= 2;
    - tier 1 crew is `ceil(complement * 0.7)`;
    - tiers above 5 or below 1 clamp to the nearest table entry.
  - `test_campaign_fleet.gd`, extended: after `start_warp("x")`, `is_warping()` is true, `warp_remaining == 3.0` and `warp_target == "x"`; `cancel_warp()` clears both. `max_strength()` ignores current damage.
- [ ] **Step 2: Register the new test files** in the `preload` list in `run_tests.gd` (they are synchronous). Write stub classes first so the run can't hang on a parse error. Run the suite and confirm the new checks FAIL.
- [ ] **Step 3: Implement `StarSystem`, `StationData`, `Galaxy` and `GalaxyData`.**
  - `GalaxyData` holds the layout as `const` arrays of dictionaries (systems, stations, link pairs), turned into resources in `build()`. Match the style of `_bootstrap_default_campaign`'s literals.
  - Role names map to the `EconomyRole` factories (`trade_hub()`, `refinery()`, `industrial()`, `population()`, `mining()`, `agriculture()`).
- [ ] **Step 4: Implement `JumpRules`.**
  - `edge_point`: cast a ray from the system centre `(SYSTEM_MIN + SYSTEM_MAX) / 2` along `direction`, and stop at the rect shrunk by `ARRIVAL_EDGE_MARGIN`.
  - `arrival_point`: `edge_point((origin - dest).normalized())` (`Vector2.LEFT` if the vector is zero), plus a random point in a disc of radius `ARRIVAL_RADIUS`, passed through `clamp_to_system`.
  - `distress_quote`:
    - shortfall = `jump_cost - fuel_amount()`;
    - price = `ceili(shortfall * Commodity.BASE_PRICE[FUEL] * DISTRESS_PRICE_MULTIPLIER)`;
    - the cargo-room check is `cargo_capacity() - cargo_total() >= shortfall`, checked before credits.
- [ ] **Step 5: Implement `DangerTier`.**
  - `COMBAT_SHIPS = {1:[CORVETTE], 2:[CORVETTE,CORVETTE], 3:[CORVETTE x3], 4:[CAPITAL,CORVETTE,CORVETTE], 5:[CAPITAL,CAPITAL,CORVETTE]}`
  - `TRADER_SHIPS = {1:[FREIGHTER], 2:[FREIGHTER], 3:[FREIGHTER x2], 4:[FREIGHTER x2], 5:[FREIGHTER x3]}`
  - `WEAPON_RARITY_RANGE = {1:[0,0], 2:[0,1], 3:[1,2], 4:[1,2], 5:[2,3]}`
  - `CREW_FRACTION = {1:0.7, 2:0.8, 3:0.9, 4:1.0, 5:1.0}`
  - Comps come from `ShipType.new_composition`. Crew is set via `CrewRules.set_crew(comp, maxi(CrewRules.NPC_CREW_FLOOR, ceili(complement * fraction)))`.
  - Each mount gets a random `ShipType.WEAPON_POOL` path whose loaded `Weapon.rarity` is inside the range. Cache the loaded rarities in a static dictionary.
  - Set the flagship with `ensure_flagship` semantics: the largest class, at the first index.
- [ ] **Step 6: Add the `CampaignFleet` fields and helpers.**
- [ ] **Step 7: Run a warm pass, then the suite.** Expected: the new tests pass, and the run is otherwise clean (only the known flake).
- [ ] **Step 8: Commit:** "Add galaxy model, layout and jump rules".

---

### Task 2: Multi-station campaign state (economy, fleets, trade)

Turn `CampaignState` from "one base per faction" into "a galaxy of stations". This is still data-only; the scene changes in Task 3. There are no jumps yet: trade stays inside one system.

**Files:**
- Modify: `scripts\campaign\campaign_state.gd`, `scripts\campaign\power_faction.gd` (remove `base_position` and `economy`), `scripts\campaign\fleet_allocation_policy.gd` (remove `MAX_FLEETS`)
- Test: `tests\test_campaign_galaxy_state.gd` (new, `run_async`, `load()`ed). Update to the new model: `tests\test_campaign_state.gd`, `tests\test_power_faction.gd`, `tests\test_fleet_allocation_policy.gd`, `tests\test_campaign_economy_bootstrap.gd`, `tests\test_base_overview_panel.gd`.

**Interfaces:**
- **Consumes:** everything from Task 1.
- **Produces (`CampaignState`):**
  - State:
    - `var galaxy: Galaxy = null` (cleared in `reset()`)
    - `var rng := RandomNumberGenerator.new()`
    - `home_base_economy` stays, and is set to `galaxy.home_station().economy`
  - Constants:
    - `FLEET_RESPAWN_DELAY := 60.0`
    - `NPC_SPEED := {Role.COMBAT: 100.0, Role.TRADER: 80.0}`
    - `TRADE_RANGE_JUMPS := 0`: Task 5 raises it to 2.
    - `NPC_FUEL_TARGET_JUMPS := 3`
  - Game setup:
    - `func new_game() -> void`:
      - calls `reset()`;
      - builds `galaxy = GalaxyData.build()`;
      - seeds every station economy: stock = `Commodity.TARGET_STOCK`, population = capacity x `STARTING_POPULATION_FRACTION` (0.75; move that constant here from the scene), crew pool = cap;
      - creates the Dominion and Freehold `PowerFaction`s (reputation 60, `factions_at_war = true`);
      - creates the player fleet. It keeps today's corvette + capital + freighter comps, `speed` 120 and 30 fuel. Its `system_id` is `haven`, and its position is the home station position;
      - spawns every station's full quota.
  - Fleet spawning and hostility:
    - `static func fleet_faction_for(owner: Faction, role: Role) -> Faction`: NEUTRAL + TRADER -> `TRADER`, NEUTRAL + COMBAT -> `NEUTRAL`, otherwise the owner.
    - `func spawn_station_fleet(station: StationData, role: Role) -> CampaignFleet`:
      - builds the comps with `DangerTier.fleet_for(tier, role, rng)`;
      - sets faction, role, `home_station_id`, `system_id`, and the `NPC_SPEED` speed;
      - places it at `station.position + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))`;
      - gives it fuel cargo of `NPC_FUEL_TARGET_JUMPS * JumpRules.jump_cost(fleet)`;
      - appends it to `enemy_fleets` and emits `fleet_spawn_requested`.
    - `func is_hostile_to_player(fleet: CampaignFleet) -> bool`: PIRATE, or a power faction below `HOSTILE_REPUTATION_THRESHOLD`. This moves `_is_faction_hostile` from the scene.
  - Station lookups:
    - `func stations_of(owner: Faction) -> Array[StationData]`
    - `func station_fleets(station: StationData, role: Role) -> Array[CampaignFleet]`
    - `func power_faction_for(owner: Faction) -> PowerFaction`: a public rename of `_power_faction_for`. Update its callers.
  - Trade:
    - `func run_npc_trade_at(fleet: CampaignFleet, station: StationData) -> void`
    - `func next_trade_destination(fleet: CampaignFleet) -> String`
  - Economy tick: `tick_economy` now covers all stations, as described in Step 4.

- [ ] **Step 1: Write the failing tests** in `test_campaign_galaxy_state.gd`, on a fresh `CampaignState.new()` with `rng.seed = 1`:
  - **New game:** `new_game()` leaves `player_fleet.system_id == "haven"`. Its position equals the home station's position. It has 30 fuel. `home_base_economy` is the home station's economy.
  - **Fleet counts:**
    - `enemy_fleets.size()` equals the sum of all quotas (compute it from the galaxy; don't hard-code it);
    - every spawned fleet's `system_id` equals its home station's system;
    - a NEUTRAL station's trader has faction `TRADER`;
    - a tier-5 pirate fleet has 3 ships.
  - **Respawn:** erase every fleet of `southdeep_den`, then tick the economy for `FLEET_RESPAWN_DELAY + ECONOMY_TICK_INTERVAL` of game time. Its COMBAT count is back to 2. Before 60 s have passed, it is still 0.
  - **Threat:**
    - adding a strong pirate fleet in `deadreach` doesn't change Bastion's threat ratio;
    - adding one in `kestrel` (adjacent to `bastion`) does;
    - check through `_threat_ratio_for(station)`, made testable, or through the allocation outcome.
  - **Growth:** a Bastion combat fleet under 3 ships grows by 1 corvette on `GROW_COMBAT`, and no new fleet is created.
  - **`run_npc_trade_at`:**
    - at the home station, all cargo is unloaded into home stock, and goods with home net > 0 are loaded;
    - at another station, cargo is unloaded into that station's stock, and goods the home economy needs (home net < 0) are loaded from that station's stock.
  - **`next_trade_destination`** (`TRADE_RANGE_JUMPS = 0`):
    - a trader away from home gets its home station back;
    - a Freehold trader homed at `greenreach`, at home, picks `greenreach_fields`;
    - a neutral trader homed at `marrow_depot`, at home, never picks `marrow_hideout` (PIRATE), so it returns `""`.
  - **Crew refill:** a NEUTRAL patrol's crew refill draws from its home station's `crew_pool`.
- [ ] **Step 2: Register the test (run_async, load) and run it.** It should FAIL.
- [ ] **Step 3: Remove the single-base fields.**
  - Delete `PowerFaction.base_position` and `.economy`, and `FleetAllocationPolicy.MAX_FLEETS`.
  - Fix every compile error in `campaign_state.gd` against the new interfaces.
  - The scene breaks until Task 3. That's expected; don't patch the scene here beyond what's needed to compile. Leave `campaign_scene.gd` calling `CampaignState.new_game()` from `_ready` when `player_fleet == null`, and delete `_bootstrap_default_campaign`.
- [ ] **Step 4: Implement the per-station economy tick.** Each tick:
  - pay wages;
  - for each station:
    - `economy.tick()`;
    - for a power-faction owner, `_apply_station_allocation(station)`. It uses the station economy's health, `_threat_ratio_for(station)` (pirate strength in the station's system plus its neighbours, over this station's combat strength), and `FleetAllocationPolicy.decide`. GROW only adds ships to this station's fleets under `MAX_SHIPS_PER_FLEET`. REALLOCATE flips one of this station's traders to combat;
    - `_tick_station_respawns(station, ECONOMY_TICK_INTERVAL)`: for each quota role below its count, add time to `respawn_timers[role]`. Once it reaches `FLEET_RESPAWN_DELAY`, spawn one fleet and reset the timer. Reset the timer when the role is at quota;
  - `_refill_npc_crew()`: pirates keep their `PIRATE_CREW_REGEN`, and every other NPC draws from its home station's pool.
- [ ] **Step 5: Implement trade.**
  - `run_npc_trade_at` generalises `_unload_and_load_surplus` and `_unload_and_load_deficit`, replacing `home_base_economy` with the station's economy. Delete `run_npc_trade_for_fleet`.
  - `next_trade_destination`:
    - if the fleet's `dest_station_id` (the last stop) isn't home, return home;
    - otherwise, candidates are stations within `TRADE_RANGE_JUMPS` of home. Their owner must be one of: the fleet's faction, NEUTRAL, PLAYER, or a power faction not at war with it. Never PIRATE, and never home itself;
    - score each candidate by the sum of its stock of the commodities where the home economy's `net_commodities()` < 0;
    - pick the highest score. Ties go to the shortest jump distance, then to the shortest in-system distance;
    - with every score at 0, pick the nearest candidate;
    - return `""` when there are no candidates.
- [ ] **Step 6: Update the five listed existing tests** to the station model, keeping their intent. For example, faction economy assertions read `stations_of(DOMINION)[0].economy`. Run the suite. The non-scene tests pass. Scene tests may fail until Task 3; list them in the commit message.
- [ ] **Step 7: Commit:** "Move campaign state to a galaxy of stations".

---

### Task 3: System layers in the campaign scene

Show the galaxy, one system at a time, with every system simulated. When this task is done, the game is fully playable inside `haven`, as before.

**Files:**
- Create: `scripts\campaign\system_layer.gd`, `scripts\campaign\campaign_station.gd`, `scenes\campaign\campaign_station.tscn`
- Delete: `scripts\campaign\home_base.gd`, `scripts\campaign\faction_base.gd`, `scenes\campaign\home_base.tscn`, `scenes\campaign\faction_base.tscn`, `tests\test_home_base.gd`, `tests\test_faction_base.gd`. Remove their entries from `run_tests.gd`. Keep `assets\sprites\bases\` and flag it as unused in the commit message.
- Modify: `scripts\campaign\campaign_scene.gd`, `scripts\campaign\campaign_fleet_icon.gd`
- Test: `tests\test_campaign_scene.gd`, `tests\test_campaign_scene_trading.gd`, `tests\test_campaign_scene_fleet_panel.gd`, `tests\test_campaign_fleet_icon.gd` (update), `tests\test_campaign_layers.gd` (new, run_async)

**Interfaces:**
- **Consumes:** Task 2's `CampaignState` API.
- **Produces:**
  - **`SystemLayer` (Node2D):** `var system_id: String`; `func set_current(is_current: bool, offset: Vector2) -> void` sets `visible = is_current` and `position = Vector2.ZERO if is_current else offset`.
  - **`CampaignStation` (Area2D):**
    - `var station: StationData`; `func setup(data: StationData) -> void`.
    - The scene has a `CollisionShape2D` with radius 30, and a `Sprite2D` scaled so its longest side is `STATION_ICON_SIZE := 72.0`.
    - `_draw` draws a 2 px ring in `CampaignFleetIcon.FACTION_COLORS[station.owner]`, with PLAYER green.
  - **`CampaignScene`:**
    - `const SYSTEM_SPACING := 5000.0`; `var layers: Dictionary` (system_id -> SystemLayer); `var station_nodes: Dictionary` (station_id -> CampaignStation).
    - `func show_system(system_id: String) -> void`: layer `i` (in sorted id order) sits at `Vector2(SYSTEM_SPACING * (i + 1), 0)` unless it is current.
    - `func layer_for(system_id) -> SystemLayer`
  - **`CampaignFleetIcon`:**
    - Movement and `fleet.position` use the local `position`. Cross-icon distance checks (pirate detection, trader flee) use `global_position`, so icons in other layers are never in range.
    - Bounds come from `JumpRules.clamp_to_system`. Delete `MAP_MIN` and `MAP_MAX`.
    - `signal trader_arrived_at(station_id: String)` replaces `trader_arrived(at_home)`.
    - `var dest_position: Vector2`: the scene sets it from `fleet.dest_station_id`.
    - Trails emit only when `is_visible_in_tree()`.
    - `TraderBehavior.next_route_state` and `route_target` are no longer used by the icon. Delete them and their tests if nothing else uses them.

- [ ] **Step 1: Write the failing tests** in `test_campaign_layers.gd`. Instance the campaign scene after `CampaignState.new_game()` and await 2 frames.
  - **Layers:**
    - `layers.size() == 26`;
    - only `haven`'s layer is visible, and it sits at the origin;
    - every other layer is at least `SYSTEM_SPACING` from the origin;
    - every station node is a child of its system's layer;
    - every fleet icon is under `layer_for(fleet.system_id)`.
  - **No cross-system overlaps:** place a pirate in `marrow` and a trader in `wexford` at the same local position, run 10 physics frames, and check that no skirmish starts. In the same system, one does start.
  - **Docking:** clicking (calling `_trigger_arrival`) on `haven_exchange`'s node opens the overview with `"Haven Exchange"` and its economy, and the faction is null (no fine button). Docking at `marrow_hideout` (pirate) also opens the overview.
  - **`respawn_returns_to_home_system`:**
    - set `player_fleet.system_id = "marrow"`, call `begin_respawn()`, and reload the scene;
    - the player icon is in `haven`'s layer at the home station position, and `haven` is the current layer;
    - for this to pass, `begin_respawn` must also set `system_id` to the home system.
  - **Trading round trip:** a trader icon whose `dest_station_id` is a station in its own system moves to it, emits `trader_arrived_at`, and gets a new destination from `next_trade_destination`.
  - **Hidden layers keep running:** a fleet in a hidden layer still moves over 30 physics frames.
- [ ] **Step 2: Run it.** It should FAIL.
- [ ] **Step 3: Implement `SystemLayer` and `CampaignStation`, and delete the HomeBase and FactionBase files.**
- [ ] **Step 4: Rework `CampaignScene._ready`.**
  - Build the layers and station nodes from `CampaignState.galaxy`.
  - Spawn each icon under its fleet's layer.
  - Call `show_system(player_fleet.system_id)`.
  - The `_economy_for_base`, `_faction_for_base`, `_name_for_base` and `_catalog_for_base` helpers read `area.station`, using `CampaignState.power_faction_for(owner)` and `RefitCatalog.for_faction(owner)`.
  - Every `area is HomeBase or area is FactionBase` check becomes `area is CampaignStation`. Respawn docks at the home station node.
  - `_behavior_for_fleet` uses `CampaignState.is_hostile_to_player`.
  - Delete `_configure_trade_route` and `_dock_point_for`. On `trader_arrived_at(id)`, call `CampaignState.run_npc_trade_at(fleet, galaxy.station(id))`, then set `fleet.dest_station_id = CampaignState.next_trade_destination(fleet)` and update the icon's `dest_position`. A destination in another system leaves the trader idle until Task 5.
- [ ] **Step 5: Rework `CampaignFleetIcon`** as described in Interfaces. On spawn, `_spawn_point` is the home station position if the fleet is in its home system, otherwise the fleet's position.
- [ ] **Step 6: Update the listed scene tests to the station model.** Run the whole suite: it should be clean apart from the known flake.
- [ ] **Step 7: Screenshot check.** Take a non-headless screenshot of `haven` (see the carry-forward's screenshot recipe). Two stations should be visible with rings, and the fleets inside bounds. Delete any `images.jpg.import` the warm pass creates.
- [ ] **Step 8: Commit:** "Split the campaign into per-system layers".

---

### Task 4: Player jumping, jump map, discovery and distress

**Files:**
- Create: `scripts\ui\jump_map_panel.gd`, `scenes\ui\jump_map_panel.tscn`
- Modify: `scripts\campaign\campaign_state.gd`, `scripts\campaign\campaign_scene.gd`, `scenes\campaign\campaign_scene.tscn` (add the `JumpMapPanel` under `UILayer`), `scripts\campaign\campaign_fleet_icon.gd` (countdown ring, warp-in flash), `scenes\ui\fleet_status_bar.tscn` and `scripts\ui\fleet_status_bar.gd` (JumpButton), `project.godot` (input action)
- Test: `tests\test_campaign_jumping.gd` (new, run_async), `tests\test_jump_map_panel.gd` (new, run_async)

**Interfaces:**
- **Consumes:** `JumpRules`, `Galaxy`, the `CampaignFleet` warp helpers, and `CampaignScene.show_system` / `layer_for`.
- **Produces (`CampaignState`):**
  - Signal: `signal fleet_jumped(fleet: CampaignFleet, from_system: String)`.
  - Discovery state:
    - `var discovered: Dictionary` and `var visited: Dictionary` (system_id -> true).
    - `var last_seen: Dictionary`: system_id -> `{"owners": Array, "stations": int, "pirates_seen": bool, "tier": int}`.
  - Discovery:
    - `func record_visit(system_id: String) -> void`: marks the system visited, marks it and its neighbours discovered, and snapshots `last_seen` (station owners, station count, whether any PIRATE fleet is in the system now, tier).
    - `new_game()` calls `record_visit("haven")`.
  - Player warp:
    - `func jump_block_reason(dest_id: String, hostile_contact: bool) -> String`: returns `""` when allowed. Otherwise it returns the first match, in order: `"Not connected"`, `"Warp already charging"`, `"Hostile fleet in contact"`, `"Not enough fuel (need %.1f, have %.1f)"`.
    - `func begin_player_warp(dest_id: String, hostile_contact: bool) -> bool`
  - Warp ticking:
    - `func tick_warps(delta: float) -> void`: ticks the player and every enemy fleet. When `warp_remaining` reaches <= 0, it calls `complete_warp`.
    - `func complete_warp(fleet: CampaignFleet) -> void`:
      - takes off `JumpRules.jump_cost`, floored at 0;
      - moves the fleet to `warp_target`, placed by `JumpRules.arrival_point` using both systems' `map_position` and `rng`;
      - clears the warp state;
      - for the player, calls `record_visit` on the origin, then on the destination;
      - emits `fleet_jumped`.
  - Distress: `func send_distress() -> bool` applies `JumpRules.distress_quote(player_fleet, credits)`: it takes the credits and adds the fuel.
  - Skirmishes: `start_skirmish` calls `cancel_warp()` on both fleets.
- **Produces (`JumpMapPanel`, Control):**
  - Signals: `jump_requested(system_id: String)`, `distress_requested`, `closed`.
  - API:
    - `func open_for(state: Node, docked: bool, hostile_contact: bool) -> void`
    - `func close() -> void`, `func refresh() -> void`
    - `func select_system(id: String) -> void`, `func selected_system() -> String`
  - Child nodes: `jump_button: Button`, `distress_button: Button`, `reason_label: Label`, `info_label: Label`.
- **Produces (`CampaignScene`):**
  - `func _open_jump_map() -> void`, which follows the `_open_fleet_management` pattern: it is blocked while the engage prompt or respawn panel is visible, and it records and restores the pause state.
  - `func _player_hostile_contact() -> bool`: any overlapping icon where `is_hostile_to_player` holds.
- Status bar: `jump_button: Button`.
- Input action: `open_jump_map` (physical keycode 74, J).

- [ ] **Step 1: Write the failing tests.**
  - `test_campaign_jumping.gd`, state level on a fresh state:
    - **Block reasons:** `jump_block_reason("deadreach", false) == "Not connected"`. `"wexford"` with 5 fuel starts with `"Not enough fuel"`. With `hostile_contact = true` it gives `"Hostile fleet in contact"`.
    - **Fuel timing:** after `begin_player_warp("wexford", false)`, fuel is unchanged. After `tick_warps(2.9)` the player is still in `haven`. After `tick_warps(0.2)` the player is in `wexford`, and fuel dropped by exactly `jump_cost`.
    - **Arrival:** the player arrives within `ARRIVAL_RADIUS + 1` of `JumpRules.edge_point(haven.map_position - wexford.map_position)`.
    - **Discovery:** `visited` has `wexford`. `discovered` has `greenreach` and `cinder`. `last_seen["haven"]` exists.
    - **Cancelled warps cost nothing:** `cancel_warp` mid-countdown leaves fuel unchanged. `start_skirmish` on a warping NPC cancels its warp.
    - **Distress:** `send_distress` with too little fuel and enough credits leaves `can_afford` true and takes the quoted price.
  - `test_campaign_jumping.gd`, scene level, with the campaign scene instanced:
    - **`jump_while_docked_undocks`:** dock at the home station and open the trade sub-panel. `_on_jump_requested("wexford")` then leaves the overview and trade panel hidden, the tree unpaused, and the player warping.
    - **Moves are ignored mid-warp:** a click during the countdown doesn't change the player icon's move target.
    - **Caught by a hostile:** a hostile pirate icon touching the player mid-warp cancels the warp and shows the engage prompt. After Disengage, `begin_player_warp` is refused with `"Hostile fleet in contact"` while the pirate still overlaps.
    - **Switching layers:** after the countdown completes, the player icon is in `wexford`'s layer and `wexford` is the visible layer at the origin.
    - **`combat_round_trip_keeps_system_and_npc_warp`:**
      - put the player in `wexford`, and start a warp on an NPC in `kestrel` with 2.0 s left;
      - reload the scene (`change_scene_to_file` to the campaign, as combat does) and await 2 frames;
      - the player is still in `wexford`, and the NPC's `warp_remaining` is still about 2.0 (within 0.1) and is counting down.
    - **`jump_map_blocked_by_modals`:** with the engage prompt visible, the `open_jump_map` action leaves the panel hidden. The same holds for the respawn panel.
  - `test_jump_map_panel.gd`:
    - **What's shown:** after `open_for` at a new game, the panel draws exactly the discovered systems: `haven` plus its 4 neighbours. `wexford` is shown as unknown, and `info_label` reads `"Unknown system"` plus the cost line.
    - **Not connected:** selecting `greenreach` (marked discovered for the test but not linked to `haven`) disables `jump_button`, and `reason_label` reads `"Not connected"`.
    - **Low fuel:** with 5 fuel, selecting `wexford` disables `jump_button` and the reason starts with `"Not enough fuel"`. `distress_button` is visible with text `"Distress signal (%d cr for %.1f fuel)"`.
    - **Docked:** docked, the distress button is hidden.
    - **Signals:** pressing the enabled `jump_button` emits `jump_requested("wexford")`.
    - **Layout:** the panel passes `tests\ui_layout_check.gd` (nothing clipped at 1152x648).
- [ ] **Step 2: Register the tests and run them.** They should FAIL.
- [ ] **Step 3: Implement the `CampaignState` jump API, discovery and distress.**
- [ ] **Step 4: Build `JumpMapPanel`.**
  - **Layout:**
    - full-screen under the status bar: offsets (10, 80) to (1142, 638);
    - a `Panel` background on `MOUSE_FILTER_STOP`;
    - a `MapArea` Control that draws in `_draw`;
    - an info strip at the bottom holding `info_label`, `reason_label`, `jump_button`, `distress_button` and a Close button.
  - **Drawing:**
    - map `map_position` into `MapArea`'s rect, with a 24 px inset;
    - draw links only between two discovered systems;
    - unknown systems (discovered, not visited) are dim grey;
    - visited systems take the colour of the most common owner in `last_seen`, from `CampaignFleetIcon.FACTION_COLORS` with PLAYER green;
    - "you are here" gets a ring, and the selected system a white ring;
    - names are drawn under the nodes.
  - **Selecting:** clicking selects the nearest shown system within 14 px.
  - **Info text for a visited system:** `"%s - %s - %d stations - Danger %d"`, then `", pirates seen"` if relevant, then a newline and `"Jump cost: %.1f fuel (you have %.1f)"`.
  - **Closing:** Esc (`ui_cancel`) and J close the panel.
- [ ] **Step 5: Wire the scene.**
  - **Opening the map:** the status bar's JumpButton and the `open_jump_map` action call `_open_jump_map`.
  - **`_on_jump_requested(id)`:**
    - if docked, run `_on_docking_panel_closed()` first;
    - `CampaignState.begin_player_warp(id, _player_hostile_contact())`;
    - close the map and unpause.
  - **During a player warp:**
    - JumpButton shows `"Cancel Warp (%.1f)"`, and pressing it calls `player_fleet.cancel_warp()`;
    - `_unhandled_input` ignores move clicks;
    - a hostile icon entering the player area cancels the warp and calls the engage path (`_trigger_arrival(area)`). Outside a warp, behaviour stays as today.
  - **Ticking:** `_physics_process` calls `CampaignState.tick_warps(delta)` when not paused.
  - **On `fleet_jumped`:**
    - reparent the icon to the new layer and set its `position` from the fleet;
    - for the player, `show_system`, clear `_travel_target`, hide the engage prompt, and close the dock UI;
    - every arriving icon calls `play_warp_in()`.
  - **Icon visuals:** while `fleet.is_warping()`, draw an arc that fills with progress, plus a `ceil(warp_remaining)` label. `play_warp_in()` draws an expanding ring over 0.4 s.
- [ ] **Step 6: Run the full suite** (clean apart from the flake). Take a screenshot of the jump map at a new game, and check that it's readable.
- [ ] **Step 7: Commit:** "Add jumping, the jump map and distress signal".

---

### Task 5: AI jumping, NPC fuel, and the performance check

**Files:**
- Create: `scripts\campaign\npc_jump_planner.gd`, `tests\test_npc_jump_planner.gd` (synchronous), `tests\perf_galaxy.gd` (manual run, not in the suite)
- Modify: `scripts\campaign\campaign_state.gd`, `scripts\campaign\campaign_scene.gd`, `tests\test_campaign_long_run_sim.gd` (port it to the galaxy)
- Test: `tests\test_campaign_ai_jumps.gd` (new, run_async)

**Interfaces:**
- **Consumes:** `Galaxy`, `JumpRules`, `CampaignState.tick_warps`, `complete_warp`, `fleet_jumped`, `next_trade_destination`.
- **Produces (`NpcJumpPlanner`, static):**
  - Constants: `RETREAT_STRENGTH_FRACTION := 0.5`, `DECISION_INTERVAL := 20.0`, `DECISION_JITTER := 10.0`, `HOP_DELAY := 2.0`.
  - `func plan(fleet: CampaignFleet, galaxy: Galaxy, fleets: Array[CampaignFleet]) -> Array[String]`: the path of systems to travel; empty means stay.
  - `func fuel_allows(fleet: CampaignFleet, galaxy: Galaxy, path: Array[String]) -> bool`: fuel covers `jump_cost * (path.size() + jump_distance(path.back(), home_system))`. A path that ends at home needs only `path.size()` jumps.
- **Produces (`CampaignState`):**
  - `func tick_npc_jumps(delta: float) -> void`
  - `func refuel_npc(fleet: CampaignFleet, station: StationData) -> void`: tops fuel up to `NPC_FUEL_TARGET_JUMPS * jump_cost` from `station.economy.stock[FUEL]`, free.
  - `TRADE_RANGE_JUMPS` becomes 2.

- [ ] **Step 1: Write the failing tests.**
  - `test_npc_jump_planner.gd`, on a hand-built galaxy: home `h` (pirate station), `h-a`, `a-b`, with a power-faction station in `a`.
    - **Pirates:**
      - a healthy pirate at home, with a TRADER-role fleet in `a`, plans `["a"]`;
      - with no traders anywhere, it plans `[]`;
      - a pirate in `a` below 50% strength plans `["h"]`;
      - a pirate in `a` with no traders left plans `["h"]`.
    - **Patrols:** a patrol whose home station is in `a`, sitting in `a`, with a pirate in `b` (`b` has a station of the patrol's owner), plans `["b"]`. With no pirates anywhere and the patrol away from home, it plans the path home.
    - **Traders:** a trader whose `dest_station_id` is in `b` while it sits in `h` plans `["a","b"]`.
    - **`planner_respects_round_trip_fuel`:**
      - a pirate at home with fuel for exactly 1 jump: `fuel_allows(["a"])` is false, because it couldn't come back;
      - with 2 jumps of fuel, it is true;
      - a pirate in `a` with 1 jump of fuel: `fuel_allows(["h"])` is true.
  - `test_campaign_ai_jumps.gd`:
    - **Single jump:** after `new_game()`, set one Freehold trader's `dest_station_id` to `cinder_market`, which is 1 jump from `wexford` (its home). Tick `tick_npc_jumps` and `tick_warps` for 5 s of game time. The trader is in `cinder`, and its fuel dropped by `jump_cost`.
    - **Multi-jump trip:** a trader with a 2-hop destination finishes both hops within `2 * (WARP_DURATION + HOP_DELAY) + 1` seconds, after its first decision.
    - **Refuel:** an NPC that arrives at a station through `trader_arrived_at` is refuelled. The station's FUEL stock drops by the same amount.
    - **Skirmish:** a warping NPC that starts a skirmish loses its warp and stays put.
- [ ] **Step 2: Register the tests and run them.** They should FAIL.
- [ ] **Step 3: Implement `NpcJumpPlanner`.** The rules are in the test cases.
  - "Healthy" means `total_strength() >= RETREAT_STRENGTH_FRACTION * max_strength()`.
  - A raid target is the adjacent system with the most non-pirate TRADER-role fleets, and it needs at least 1.
  - Patrols treat a system as "owned" when it has a station whose owner is their home station's owner.
  - Fleets that are hostile to each other are found via `are_hostile` (pass a Callable, or keep the logic data-only with the faction rules inlined from `CampaignState.are_hostile`).
- [ ] **Step 4: Implement `tick_npc_jumps`.** For each NPC that is not warping and not in an active skirmish:
  - decrement `jump_cooldown`; at <= 0:
    - if `jump_path` is non-empty and `fuel_allows` holds, `start_warp(jump_path[0])`;
    - otherwise run `plan`. If the path is non-empty and fuel allows, store it and start the first hop. If it is non-empty but fuel doesn't allow, store the path home instead, or stay if even that isn't affordable;
    - reset `jump_cooldown` to `DECISION_INTERVAL + rng.randf() * DECISION_JITTER`.
  - When a warp completes for an NPC, pop the hop. If hops remain, set `jump_cooldown = HOP_DELAY`.
  - Refuelling:
    - the economy tick calls `refuel_npc` for combat NPCs sitting in their home system;
    - `run_npc_trade_at` calls `refuel_npc` at the station.
  - The scene calls `tick_npc_jumps` in `_physics_process` when not paused.
  - On `fleet_jumped`, an NPC icon's `_spawn_point` becomes its arrival position. For a trader, `dest_position` is refreshed if its destination is in the new system.
- [ ] **Step 5: Port `test_campaign_long_run_sim.gd`** to `new_game()`. Keep its intent: the economy and fleets stay alive over a long run.
- [ ] **Step 6: Write `tests\perf_galaxy.gd`, a SceneTree script run manually.**
  - It calls `CampaignState.new_game()`, instances the campaign scene, and runs 600 physics frames at `Engine.time_scale = 1.0`, then 600 at `5.0`.
  - It measures each frame's wall time with `Time.get_ticks_usec()`.
  - It prints the fleet count, plus average and max ms, per speed.
  - `--verbose` (read from `OS.get_cmdline_user_args()`) also prints per-100-frame averages.
  - Run it headless and non-headless:
    ```powershell
    Start-Process -FilePath $godot -ArgumentList '--path','.','--script','res://tests/perf_galaxy.gd' -RedirectStandardOutput perf_output.txt -Wait -NoNewWindow
    ```
  - Pass bar: average under 8 ms and max under 33 ms at both speeds, non-headless. **If it fails, stop and report the numbers.** Don't build off-screen simulation (spec Constraints).
- [ ] **Step 7: Run the full suite** (clean apart from the flake). Watch the game for ~2 minutes at 5x speed in the screenshot or debug view. Fleets should arrive in and leave `haven` with countdown rings and warp-in flashes.
- [ ] **Step 8: Commit:** "Let AI fleets jump between systems". Include the perf numbers in the commit body.

---

## Self-review notes

- **Spec coverage:**
  - the galaxy, tiers, stations, art and ring: Task 1 and Task 3;
  - per-station economies, quotas, respawn and local threat: Task 2;
  - physics isolation, interaction limited to the current system, and a hidden simulation that keeps running: Task 3;
  - the jump map (A), pausing, J, the button, the 3 s countdown, the caught rule, fuel spent on completion, arrival, discovery and last-seen info, danger shown, undocking, game-time countdown, cancel, distress: Task 4;
  - AI jumping by role, NPC fuel and refuel, the round-trip fuel rule, the perf check and the stop-and-report rule: Task 5;
  - HomeBase as a trade stop: Task 2 (PLAYER owner is a candidate).
- **Deliberately not built** (spec non-goals): a camera, a random galaxy, new factions, treasuries, fleets over 3 ships, reward scaling, attacking bases, saving, off-screen simulation, and NPCs following the player through a jump.
