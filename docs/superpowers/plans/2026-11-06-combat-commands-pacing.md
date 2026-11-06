# Combat Commands, Idle Start and Pacing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Battles open with every ship idle and formed up by strength; the player
commands fleets with five orders (Move, Hold, Attack, Protect, Flee) via
right-click, left-click now only selects; ships focus their best 1-2 weapons,
jink imperfectly against incoming fire, and fly slower and heavier.

**Architecture:** `Ship`'s default spawn order switches from the hunting `HOLD` to
the anchored `HOLD_POSITION`; a new `Order.Type.PROTECT` reuses the existing
idle-autofire plumbing (`idle_target()`/`pick_autofire_target`). `CombatScene`
sorts fleets by a new `strength_of` helper before handing them to
`formation_points`. `FleetCommander` gains an "armed command" that right-click
resolves into an order; `OrderBar` gains three new buttons. `Ship._process_weapons`
gains a top-N weapon filter and a projectile-aware jink; the three ship scenes
get slower `ShipEngine` values.

**Tech Stack:** Godot 4, GDScript, the project's own test runner (`tests\run_tests.gd`).

**Spec:** `docs\superpowers\specs\2026-11-06-combat-commands-pacing-design.md`
(approved 2026-11-06, builder-checked). Read it before each task. Where it
leaves a number open ("tuning constant", "placeholder"), the value given in a
task here is the one to use; it's a named, tunable `const`.

## Global Constraints

- Build on `main`, one commit per task, message ending with
  `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`. Never push.
- Match each file's style: tabs, typed GDScript, `# why` comments only.
- Run tests from the project root with the commands below. A clean run means no
  `FAIL` lines except the known `test_campaign_long_run_sim.gd` pirate-targeting
  flake (4-8 lines), and no `SCRIPT ERROR` in either log.
  ```powershell
  $godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
  Start-Process -FilePath $godot -ArgumentList '--headless','--path','.','--script','res://tests/run_tests.gd' -RedirectStandardOutput test_output.txt -RedirectStandardError test_error.txt -Wait -NoNewWindow
  Select-String -Path test_output.txt,test_error.txt -Pattern 'FAIL|SCRIPT ERROR'
  ```
- After adding a new `class_name` file (none planned here, but if a task needs
  one), run one warm pass first:
  `Start-Process -FilePath $godot -ArgumentList '--headless','--editor','--path','.','--quit' -Wait -NoNewWindow`.
  Then revert the `.import` churn it causes (delete each changed `.import`,
  then `git checkout -- <files>`); never commit `.import` or CRLF-only noise.
- Register new async test files in `tests\run_tests.gd`, each its own
  `load()`/`run_async`/print-loop block appended after the existing blocks
  (see the file's tail for the pattern); new sync test files go in the
  `test_scripts` array near files that test similar subsystems.
- GDScript gotchas: a freed object fails any Object-typed parameter check, so
  functions that guard with `is_instance_valid` take untyped params; check
  `is_instance_valid(x)` before `x is T`; assign literals to typed arrays with
  `.assign()`.
- Edit `project.godot` with Python using `newline=''` so its line endings stay
  as they are.
- Plain ASCII in all new text.
- `ShipType.BASE_STATS[kind]["max_speed"/"turn_rate"]` (used by
  `CrewRules`/the overworld map) is a **separate** copy of the numbers from the
  `ShipEngine` export values in `scenes\ship\ship_*.tscn` (used by combat
  physics). This plan only touches the `.tscn` values, so overworld travel
  speed is unaffected by the pacing change. Don't "fix" the duplication by
  touching `ShipType.BASE_STATS` — that's out of scope.
- Per `token-efficient-execution`: batch reviews rather than reviewing every
  task individually — one reviewer after Task 2 and one final whole-branch
  review after Task 4 is enough for a plan this size.

## Review Focus

1. **Order-target loss mid-battle.** An `ATTACK_TARGET` or `PROTECT` order
   whose target is freed the same tick it's read (killed by an ally one frame
   before, or in the same physics step). Expected: no `SCRIPT ERROR`, the ship
   re-targets or falls back to `HOLD_POSITION`, never crashes on a stale
   reference. (Tests in Task 2.)
2. **Strength sort with a one-ship or oversized fleet.** A single-ship fleet
   must still spawn on an anchor (not divide by zero in the centroid), and a
   fleet bigger than the anchor count must still put its weakest ships in the
   rear rows, not just in `indices` order. (Tests in Task 1.)
3. **Right-click with no armed command, and right-click while dragging.**
   Must keep clearing the selection with no order issued — this is the
   pre-existing behaviour and must not regress for players who never touch
   the new buttons. (Tests in Task 3.)
4. **Weapon focus on a ship with only PD, or only 1 working weapon.** Must
   never leave a ship with zero firing weapons when it has a working one.
   (Tests in Task 4.)
5. **Pacing regression on perf and feel.** Re-run `tests\perf_combat.gd`
   after Task 4's speed changes; a slower corvette taking longer to close
   must not blow the existing frame-time bar. (Task 4, Final review.)

---

### Task 1: Idle spawn and strength-sorted formation

**Files:**
- Modify: `scripts\ship\ship.gd:66-78` (`_ready`)
- Modify: `scripts\combat\combat_scene.gd` (new `strength_of`, `center_out_anchors`;
  `_spawn_fleet_from_data` sorts `indices`)
- Test: `tests\test_combat_scene.gd` (rewrite the "idle ships head toward the
  enemy" assertion), `tests\test_combat_scene.gd` (new formation-order check)

**Interfaces:**
- Produces:
  - `CombatScene.strength_of(comp: Dictionary) -> float`: static,
    `ShipType.BASE_STATS[ShipType.kind_of(comp)]["max_hp"]` plus
    `CombatTactics.weapon_dps(load(path))` summed over every non-empty path in
    `comp.get("weapon_mount_items", [])`.
  - `CombatScene.center_out_anchors(anchors: Array[Vector2]) -> Array[Vector2]`:
    static, the input re-sorted by ascending distance to the anchors'
    centroid (ties broken by original order, i.e. a stable sort) — for a
    straight line of spawn points this puts the middle point first and the
    two flanking points next.
- Consumes (unchanged): `ShipType.BASE_STATS`, `ShipType.kind_of`,
  `CombatTactics.weapon_dps`, `CombatScene.formation_points` (all exist today).

- [ ] **Step 1: Write the failing tests.** Add to `tests\test_combat_scene.gd`
  (as new static helper functions called from `run_async`, following the
  file's existing `_formation_failures()` pattern for anything that doesn't
  need a live scene):

  ```gdscript
  static func _strength_and_anchor_failures() -> Array[String]:
      var failures: Array[String] = []
      var weak := ShipType.new_composition(ShipType.Kind.CORVETTE)
      var strong := ShipType.new_composition(ShipType.Kind.CAPITAL)
      ShipType.set_equipped_path(strong, ShipType.SlotType.WEAPON, 0, "res://resources/weapons/heavy_beam.tres")
      if CombatScene.strength_of(strong) <= CombatScene.strength_of(weak):
          failures.append("strength_of: expected the armed capital to score higher than the bare corvette")
      var bare_corvette := ShipType.new_composition(ShipType.Kind.CORVETTE)
      if not is_equal_approx(CombatScene.strength_of(bare_corvette), ShipType.BASE_STATS[ShipType.Kind.CORVETTE]["max_hp"]):
          failures.append("strength_of: expected an unarmed hull to score exactly its max_hp, got %s" % CombatScene.strength_of(bare_corvette))

      var line: Array[Vector2] = [Vector2(1000, 1400), Vector2(1000, 1600), Vector2(1000, 1800)]
      var ordered := CombatScene.center_out_anchors(line)
      if ordered[0] != Vector2(1000, 1600):
          failures.append("center_out_anchors: expected the middle point first, got %s" % [ordered])
      var single: Array[Vector2] = [Vector2(5, 5)]
      if CombatScene.center_out_anchors(single) != single:
          failures.append("center_out_anchors: expected a single anchor unchanged, got %s" % [CombatScene.center_out_anchors(single)])
      return failures
  ```

  Add `failures.append_array(_strength_and_anchor_failures())` next to the
  existing `_formation_failures()` call in `run_async`.

- [ ] **Step 2: Run the tests.** Expected: FAIL (`strength_of` and
  `center_out_anchors` don't exist yet — a parse error; write empty stub
  functions returning `0.0` / the input unchanged first so the run doesn't hang).

- [ ] **Step 3: Implement `strength_of` and `center_out_anchors` in
  `combat_scene.gd`**, next to the existing `formation_points` static func:

  ```gdscript
  static func strength_of(comp: Dictionary) -> float:
      var kind: ShipType.Kind = ShipType.kind_of(comp)
      var total: float = ShipType.BASE_STATS[kind]["max_hp"]
      for path in comp.get("weapon_mount_items", []):
          if path != "":
              total += CombatTactics.weapon_dps(load(path))
      return total

  # Re-orders anchors by distance to their own centroid, closest first, so the
  # strongest ship in a strength-sorted roster lands in the middle of the line
  # and the next-strongest ones land on the flanking anchors.
  static func center_out_anchors(anchors: Array[Vector2]) -> Array[Vector2]:
      if anchors.size() <= 1:
          return anchors.duplicate()
      var centre := Vector2.ZERO
      for a in anchors:
          centre += a
      centre /= float(anchors.size())
      var sorted := anchors.duplicate()
      sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(centre) < b.distance_to(centre))
      return sorted
  ```

- [ ] **Step 4: Run the tests.** Expected: PASS.

- [ ] **Step 5: Sort `indices` by strength in `_spawn_fleet_from_data`**
  (`combat_scene.gd:141-156`). At the top of the function, before computing
  `spawn_points`, add:

  ```gdscript
  indices.sort_custom(func(a: int, b: int) -> bool:
      return CombatScene.strength_of(fleet_data.ship_compositions[a]) > CombatScene.strength_of(fleet_data.ship_compositions[b])
  )
  ```

  `indices` is a reference type parameter, so this also re-orders
  `_player_spawned_indices`/`_enemy_spawned_indices` in place for every later
  consumer (`_apply_fleet_data`, survivor collection, the flagship check) —
  they all already index by `indices[i]` paired with `ships[i]`, so no other
  code needs to change. Then change the `formation_points` call on the next
  line from `formation_points(points, indices.size(), facing_rotation)` to
  `formation_points(CombatScene.center_out_anchors(points), indices.size(), facing_rotation)`.

- [ ] **Step 6: Switch the default spawn order.** In `scripts\ship\ship.gd`,
  line 72, change `execute_order(Order.hold())` to
  `execute_order(Order.hold_position())`.

- [ ] **Step 7: Update the now-wrong assertion in `tests\test_combat_scene.gd`**
  (around line 40-46). Replace:

  ```gdscript
  # Idle player ships hunt the enemy line to their right; they once drifted to the
  # origin because spawners place a ship after add_child has run its _ready.
  await tree.physics_frame
  for k in scene.player_ships.size():
      var heading: Vector2 = scene.player_ships[k].velocity
      if heading.x <= 0.0:
          failures.append("run_async: expected idle player ship %d to head toward the enemy, got velocity %s" % [k, heading])
  ```

  with an assertion that idle ships hold their spawn point instead:

  ```gdscript
  # Idle player ships spawn on HOLD_POSITION: they don't move toward the enemy
  # on their own, only an explicit order (or the player) sends them in.
  var spawn_positions: Array[Vector2] = []
  for ship in scene.player_ships:
      spawn_positions.append(ship.global_position)
  await tree.physics_frame
  await tree.physics_frame
  for k in scene.player_ships.size():
      var drift := scene.player_ships[k].global_position.distance_to(spawn_positions[k])
      if drift >= 10.0:
          failures.append("run_async: expected idle player ship %d to stay near its spawn point, drifted %s px" % [k, drift])
  ```

- [ ] **Step 8: Run the full suite.** Expected: clean.

- [ ] **Step 9: Commit:** "Spawn ships idle at strength-sorted formation anchors".

---

### Task 2: Protect order and auto-retarget on target loss

**Files:**
- Modify: `scripts\orders\order.gd` (`PROTECT` type, `protect()` constructor)
- Modify: `scripts\ship\ship.gd` (`_process_order_movement`, new
  `_process_protect`, new `_attack_or_fallback` helper, `pick_autofire_target`)
- Test: `tests\test_order.gd` (sync, new `Order.protect` check), new
  `tests\test_protect_and_retarget_async.gd` (async, registered in
  `run_tests.gd`)

**Interfaces:**
- Produces:
  - `Order.Type.PROTECT` (new enum value, added after `FLEE`).
  - `Order.protect(ship: Node2D) -> Order`: sets `type = PROTECT`,
    `target_ship = ship` (same shape as `Order.attack_target`).
  - `Ship.PROTECT_STANDOFF := 150.0` (new const, tunable): how far the
    protector sits from the protectee.
- Consumes (unchanged): `CombatTactics.pick_target`, `Ship._is_live_target`,
  `Ship.idle_target()`, `engine.hold_station`.

- [ ] **Step 1: Write the failing sync test** in `tests\test_order.gd`, next
  to the existing `Order.hold()` / `Order.flee()` checks:

  ```gdscript
  var ally := Ship.new()
  var protect := Order.protect(ally)
  if protect.type != Order.Type.PROTECT or protect.target_ship != ally:
      failures.append("Order.protect: expected type PROTECT and target_ship set, got %s / %s" % [protect.type, protect.target_ship])
  ally.free()
  ```

- [ ] **Step 2: Run it.** Expected: FAIL (parse error — add the enum value
  and a stub `protect()` returning a plain `Order.new()` first).

- [ ] **Step 3: Implement `Order.Type.PROTECT` and `Order.protect()`** in
  `scripts\orders\order.gd`, mirroring `attack_target()`:

  ```gdscript
  static func protect(ship: Node2D) -> Order:
      var o := Order.new()
      o.type = Type.PROTECT
      o.target_ship = ship
      return o
  ```

- [ ] **Step 4: Run it.** Expected: PASS.

- [ ] **Step 5: Write the failing async tests** in
  `tests\test_protect_and_retarget_async.gd`, following
  `tests\test_flee_async.gd`'s `_spawn`/`_spawn_dummy`/`_run_for`/`_cleanup`
  pattern (corvette scenes, a stationary huge-hull dummy as the stand-in
  enemy/protectee where needed):

  ```gdscript
  extends RefCounted

  const CorvetteScene = preload("res://scenes/ship/ship_corvette.tscn")
  const Railgun = preload("res://resources/weapons/railgun.tres")

  const ENEMY_GROUP := &"test_protect_enemies"
  const ALLY_GROUP := &"test_protect_allies"

  static func run_async(tree: SceneTree) -> Array[String]:
      var failures: Array[String] = []
      await _check_protect_holds_near_protectee(tree, failures)
      await _check_protect_faces_threat(tree, failures)
      await _check_attack_retargets_on_loss(tree, failures)
      await _check_protect_falls_back_when_protectee_lost(tree, failures)
      return failures

  static func _spawn(tree: SceneTree, pos: Vector2, weapon: Weapon, group: StringName) -> Ship:
      var ship: Ship = CorvetteScene.instantiate()
      tree.root.add_child(ship)
      ship.global_position = pos
      for mount in ship.weapon_mounts:
          mount.weapon = null
      if weapon != null:
          ship.weapon_mounts[0].weapon = weapon
      ship.ally_group = group
      ship.add_to_group(group)
      ship.enemy_group = ENEMY_GROUP if group == ALLY_GROUP else ALLY_GROUP
      await tree.physics_frame
      return ship

  static func _spawn_dummy(tree: SceneTree, pos: Vector2, group: StringName) -> Ship:
      var dummy := await _spawn(tree, pos, null, group)
      dummy.set_physics_process(false)
      dummy.hull.max_hp = 1.0e9
      dummy.hull.current_hp = 1.0e9
      return dummy

  static func _run_for(tree: SceneTree, seconds: float) -> void:
      for i in int(seconds * Engine.physics_ticks_per_second):
          await tree.physics_frame

  static func _cleanup(tree: SceneTree, nodes: Array) -> void:
      for node in nodes:
          if is_instance_valid(node):
              node.queue_free()
      await tree.physics_frame

  static func _check_protect_holds_near_protectee(tree: SceneTree, failures: Array[String]) -> void:
      var protectee := await _spawn_dummy(tree, Vector2(500.0, 500.0), ALLY_GROUP)
      var guard := await _spawn(tree, Vector2(900.0, 500.0), Railgun, ALLY_GROUP)
      guard.execute_order(Order.protect(protectee))
      await _run_for(tree, 2.0)
      var dist := guard.global_position.distance_to(protectee.global_position)
      if dist > Ship.PROTECT_STANDOFF + 60.0 or dist < 10.0:
          failures.append("protect_holds_near_protectee: expected the guard near standoff range of the protectee, got %s px" % dist)
      await _cleanup(tree, [protectee, guard])

  static func _check_protect_faces_threat(tree: SceneTree, failures: Array[String]) -> void:
      var protectee := await _spawn_dummy(tree, Vector2(500.0, 500.0), ALLY_GROUP)
      var threat := await _spawn_dummy(tree, Vector2(200.0, 500.0), ENEMY_GROUP)
      var guard := await _spawn(tree, Vector2(900.0, 500.0), Railgun, ALLY_GROUP)
      guard.execute_order(Order.protect(protectee))
      await _run_for(tree, 2.0)
      var toward_threat := (threat.global_position - protectee.global_position).normalized()
      var toward_guard := (guard.global_position - protectee.global_position).normalized()
      if toward_guard.dot(toward_threat) < 0.3:
          failures.append("protect_faces_threat: expected the guard to sit on the threat's side of the protectee, dot %s" % toward_guard.dot(toward_threat))
      await _cleanup(tree, [protectee, threat, guard])

  static func _check_attack_retargets_on_loss(tree: SceneTree, failures: Array[String]) -> void:
      var target := await _spawn_dummy(tree, Vector2(700.0, 500.0), ENEMY_GROUP)
      var backup := await _spawn_dummy(tree, Vector2(750.0, 540.0), ENEMY_GROUP)
      var attacker := await _spawn(tree, Vector2(500.0, 500.0), Railgun, ALLY_GROUP)
      attacker.execute_order(Order.attack_target(target))
      await _run_for(tree, 0.1)
      target.queue_free()
      await _run_for(tree, 0.5)
      if attacker.current_order.type != Order.Type.ATTACK_TARGET or attacker.current_order.target_ship != backup:
          failures.append("attack_retargets_on_loss: expected the attacker to retarget the remaining enemy, got %s" % [attacker.current_order.type, attacker.current_order.target_ship])
      await _cleanup(tree, [backup, attacker])

  static func _check_protect_falls_back_when_protectee_lost(tree: SceneTree, failures: Array[String]) -> void:
      var protectee := await _spawn_dummy(tree, Vector2(500.0, 500.0), ALLY_GROUP)
      var threat := await _spawn_dummy(tree, Vector2(700.0, 500.0), ENEMY_GROUP)
      var guard := await _spawn(tree, Vector2(300.0, 500.0), Railgun, ALLY_GROUP)
      guard.execute_order(Order.protect(protectee))
      await _run_for(tree, 0.1)
      protectee.queue_free()
      await _run_for(tree, 0.5)
      if guard.current_order.type != Order.Type.ATTACK_TARGET or guard.current_order.target_ship != threat:
          failures.append("protect_falls_back_when_protectee_lost: expected the guard to attack the remaining enemy, got %s / %s" % [guard.current_order.type, guard.current_order.target_ship])
      await _cleanup(tree, [threat, guard])
  ```

- [ ] **Step 6: Run them.** Expected: FAIL (no `PROTECT` branch, no
  retargeting).

- [ ] **Step 7: Implement.** In `scripts\ship\ship.gd`:
  - Add `const PROTECT_STANDOFF := 150.0` near the other movement consts.
  - Add a shared fallback helper:

    ```gdscript
    # Picks a new enemy to attack when an order's target is gone; falls back to
    # HOLD_POSITION (anchored where the ship currently is) if none remain.
    func _attack_or_fallback(candidates: Array) -> void:
        var new_target := CombatTactics.pick_target(self, candidates, null)
        if new_target != null:
            execute_order(Order.attack_target(new_target))
        else:
            execute_order(Order.hold_position())
    ```

  - In `_process_order_movement`'s `Order.Type.ATTACK_TARGET` branch, replace
    `execute_order(Order.hold())` with `_attack_or_fallback(_enemy_candidates())`
    (keep the `return` after it).
  - Add a `Order.Type.PROTECT:` branch calling a new `_process_protect(delta, _enemy_candidates())`.
  - Implement `_process_protect`:

    ```gdscript
    func _process_protect(delta: float, candidates: Array) -> void:
        if not _is_live_target(current_order.target_ship):
            _attack_or_fallback(candidates)
            return
        var protectee: Node2D = current_order.target_ship
        _retarget_timer -= delta
        if _retarget_timer <= 0.0 or not _is_live_target(_idle_target):
            var reach := attack_range()
            var in_reach: Array = []
            for candidate in candidates:
                if _is_live_target(candidate) and candidate is Node2D and CombatTactics.edge_distance(protectee.global_position, candidate) <= reach + PROTECT_STANDOFF:
                    in_reach.append(candidate)
            _idle_target = CombatTactics.pick_target(self, in_reach, _idle_target)
            _retarget_timer = CombatTactics.RETARGET_INTERVAL
        var station := protectee.global_position
        var face := global_position + Vector2.RIGHT.rotated(rotation) * 100.0
        if _idle_target != null:
            var away := protectee.global_position - _idle_target.global_position
            var dir := away.normalized() if away.length() > 0.01 else Vector2.RIGHT
            station = protectee.global_position + dir * PROTECT_STANDOFF
            face = _idle_target.global_position
        var result := engine.hold_station(global_position, rotation, face, station, delta)
        rotation = result["rotation"]
        velocity = result["velocity"]
    ```

  - Extend `pick_autofire_target` so `PROTECT` reuses the idle-target autofire
    path, matching `HOLD`/`HOLD_POSITION`:

    ```gdscript
    if (order.type == Order.Type.HOLD or order.type == Order.Type.HOLD_POSITION or order.type == Order.Type.PROTECT) and idle != null and CombatTactics.edge_distance(own_position, idle) <= max_range:
        return idle
    ```

- [ ] **Step 8: Run the full suite.** Expected: clean.

- [ ] **Step 9: Commit:** "Add Protect order; Attack and Protect auto-retarget
  when their target is lost".

---

### Task 3: Fleet command bar and right-click-issues input scheme

**Files:**
- Modify: `scenes\ui\order_bar.tscn` (3 new buttons), `scripts\ui\order_bar.gd`
  (3 new signals/wiring)
- Modify: `scripts\controllers\fleet_commander.gd` (armed command, right-click
  resolution, left-click no longer issues orders)
- Modify: `scripts\combat\combat_scene.gd:70-74` (wire the 3 new signals)
- Modify: `project.godot` (3 new input actions)
- Test: `tests\test_order_bar.gd`, `tests\test_fleet_commander.gd`

**Interfaces:**
- Consumes: `Order.Type.PROTECT`, `Order.protect()` (Task 2).
- Produces:
  - `OrderBar`: `signal move_pressed`, `signal attack_pressed`,
    `signal protect_pressed` (alongside the existing `hold_pressed`,
    `flee_pressed`, `formation_picked`).
  - `FleetCommander.set_armed_command(type: Order.Type) -> void`.
  - Input actions `order_move` (physical key M, keycode 77), `order_attack`
    (physical key A, keycode 65), `order_protect` (physical key P, keycode 80).

- [ ] **Step 1: Write the failing `OrderBar` test.** Add to
  `tests\test_order_bar.gd`'s `run_async`:

  ```gdscript
  static func _check_new_buttons_emit(tree: SceneTree, failures: Array[String]) -> void:
      var bar := await _open(tree)
      var move_btn: Button = bar.get_node("Row/MoveButton")
      var attack_btn: Button = bar.get_node("Row/AttackButton")
      var protect_btn: Button = bar.get_node("Row/ProtectButton")
      var presses: Array[String] = []
      bar.move_pressed.connect(func(): presses.append("move"))
      bar.attack_pressed.connect(func(): presses.append("attack"))
      bar.protect_pressed.connect(func(): presses.append("protect"))
      move_btn.pressed.emit()
      attack_btn.pressed.emit()
      protect_btn.pressed.emit()
      if presses != ["move", "attack", "protect"]:
          failures.append("order bar: expected move_pressed, attack_pressed, protect_pressed in order, got %s" % [presses])
      bar.get_parent().queue_free()
  ```

  Call it from `run_async`. (These three buttons are not selection-gated —
  the player can arm a command before or after selecting ships — so no
  disabled-state assertion is needed for them, unlike Hold/Flee.)

- [ ] **Step 2: Run it.** Expected: FAIL (nodes don't exist).

- [ ] **Step 3: Add the three buttons to `scenes\ui\order_bar.tscn`**, in
  `Row`, matching `HoldButton`'s shape, inserted before `FormationButton`:

  ```
  [node name="MoveButton" type="Button" parent="Row"]
  custom_minimum_size = Vector2(100, 0)
  focus_mode = 0
  text = "Move [M]"

  [node name="AttackButton" type="Button" parent="Row"]
  custom_minimum_size = Vector2(100, 0)
  focus_mode = 0
  text = "Attack [A]"

  [node name="ProtectButton" type="Button" parent="Row"]
  custom_minimum_size = Vector2(100, 0)
  focus_mode = 0
  text = "Protect [P]"
  ```

- [ ] **Step 4: Wire them in `scripts\ui\order_bar.gd`.** Add
  `signal move_pressed`, `signal attack_pressed`, `signal protect_pressed`;
  add `@onready var move_button: Button = $Row/MoveButton`,
  `attack_button`, `protect_button`; in `_ready()`, next to the existing
  `hold_button.pressed.connect(...)` lines:

  ```gdscript
  move_button.pressed.connect(func(): move_pressed.emit())
  attack_button.pressed.connect(func(): attack_pressed.emit())
  protect_button.pressed.connect(func(): protect_pressed.emit())
  ```

- [ ] **Step 5: Run the `OrderBar` test.** Expected: PASS.

- [ ] **Step 6: Write the failing `FleetCommander` tests.** Add to
  `tests\test_fleet_commander.gd`:

  ```gdscript
  static func _check_armed_move_issues_command(failures: Array[String]) -> void:
      var ship := _make_ship(Vector2(100, 100))
      var commander := _selected_commander([ship])
      commander.ships = [ship]
      commander.set_armed_command(Order.Type.MOVE_TO)
      # Calls the resolver directly, like the ATTACK_TARGET/PROTECT checks below:
      # _on_right_press() itself reads get_global_mouse_position(), which needs a
      # live viewport these bare-node unit tests don't have.
      commander._issue_armed_command(Vector2(500, 500))
      if ship.current_order == null or ship.current_order.type != Order.Type.MOVE_TO:
          failures.append("armed_move: expected a MOVE_TO order issued, got %s" % [ship.current_order])
      commander.free()
      ship.free()

  static func _check_unarmed_right_click_only_clears(failures: Array[String]) -> void:
      var ship := _make_ship(Vector2(100, 100))
      var commander := _selected_commander([ship])
      commander.ships = [ship]
      var before := ship.current_order
      commander._on_right_press()
      if ship.current_order != before:
          failures.append("unarmed_right_click: expected no order issued with nothing armed, got %s" % [ship.current_order])
      if not commander.selected_ships.is_empty():
          failures.append("unarmed_right_click: expected the selection cleared")
      commander.free()
      ship.free()

  static func _check_armed_protect_targets_ally(failures: Array[String]) -> void:
      var protectee := _make_ship(Vector2(400, 400))
      var ship := _make_ship(Vector2(100, 100))
      var commander := _selected_commander([ship])
      commander.ships = [ship, protectee]
      commander.set_armed_command(Order.Type.PROTECT)
      commander._issue_armed_command(protectee.global_position)
      if ship.current_order == null or ship.current_order.type != Order.Type.PROTECT or ship.current_order.target_ship != protectee:
          failures.append("armed_protect: expected a PROTECT order on the ally, got %s" % [ship.current_order])
      commander.free()
      ship.free()
      protectee.free()

  static func _check_left_click_empty_space_no_longer_orders(failures: Array[String]) -> void:
      var ship := _make_ship(Vector2(100, 100))
      var commander := _selected_commander([ship])
      commander.ships = [ship]
      var before := ship.current_order
      commander._on_left_release(Vector2(900, 900), Vector2(900, 900))
      if ship.current_order != before:
          failures.append("left_click_empty_space: expected no order issued, got %s" % [ship.current_order])
      commander.free()
      ship.free()
  ```

  Register these four in `run()`.

  Add a fifth test as `run_async`, in its own block, since resolving an
  attack click needs a live `get_tree().get_nodes_in_group(enemy_group)` call
  that a bare unparented `FleetCommander` can't make:

  ```gdscript
  static func run_async(tree: SceneTree) -> Array[String]:
      var failures: Array[String] = []
      await _check_armed_attack_targets_enemy(tree, failures)
      return failures

  static func _check_armed_attack_targets_enemy(tree: SceneTree, failures: Array[String]) -> void:
      var enemy := _make_ship(Vector2(400, 400))
      tree.root.add_child(enemy)
      var ship := _make_ship(Vector2(100, 100))
      tree.root.add_child(ship)
      var commander := _selected_commander([ship])
      tree.root.add_child(commander)
      commander.ships = [ship]
      commander.enemy_group = &"test_fc_enemies"
      enemy.add_to_group(&"test_fc_enemies")
      commander.set_armed_command(Order.Type.ATTACK_TARGET)
      commander._issue_armed_command(enemy.global_position)
      if ship.current_order == null or ship.current_order.type != Order.Type.ATTACK_TARGET or ship.current_order.target_ship != enemy:
          failures.append("armed_attack: expected an ATTACK_TARGET order on the enemy, got %s" % [ship.current_order])
      commander.queue_free()
      ship.queue_free()
      enemy.queue_free()
      await tree.process_frame
  ```

  Register this `run_async` in `tests\run_tests.gd` as a new block (own
  `load()`/print-loop, appended after the existing blocks) — `test_fleet_commander`
  already has a sync `run()` entry in `test_scripts`; both run independently
  since the harness calls sync and async scripts through separate code paths.

- [ ] **Step 7: Run them.** Expected: FAIL.

- [ ] **Step 8: Implement in `scripts\controllers\fleet_commander.gd`.**
  - Add fields: `var armed_command: Order.Type = Order.Type.MOVE_TO`,
    `var _has_armed_command: bool = false`.
  - Add:

    ```gdscript
    func set_armed_command(type: Order.Type) -> void:
        armed_command = type
        _has_armed_command = true
    ```

  - In `_unhandled_input`, add three branches (next to the existing
    `order_hold`/`order_flee` ones):

    ```gdscript
    elif event.is_action_pressed("order_move"):
        set_armed_command(Order.Type.MOVE_TO)
    elif event.is_action_pressed("order_attack"):
        set_armed_command(Order.Type.ATTACK_TARGET)
    elif event.is_action_pressed("order_protect"):
        set_armed_command(Order.Type.PROTECT)
    ```

  - Replace `_issue_order(world_pos: Vector2)` with
    `_issue_armed_command(world_pos: Vector2)`:

    ```gdscript
    func _issue_armed_command(world_pos: Vector2) -> void:
        _prune_selection()
        if selected_ships.is_empty():
            return
        match armed_command:
            Order.Type.MOVE_TO:
                var destinations := _compute_destinations(world_pos)
                for ship in selected_ships:
                    if destinations.has(ship):
                        ship.execute_order(Order.move_to(destinations[ship]))
            Order.Type.ATTACK_TARGET:
                var enemy_candidates: Array = get_tree().get_nodes_in_group(enemy_group)
                var target_enemy := FleetCommander.ship_at_point(enemy_candidates, world_pos, click_target_radius)
                if target_enemy != null:
                    for ship in selected_ships:
                        ship.execute_order(Order.attack_target(target_enemy))
            Order.Type.PROTECT:
                var protectee := FleetCommander.ship_at_point(ships, world_pos, click_target_radius)
                if protectee != null:
                    for ship in selected_ships:
                        if ship != protectee:
                            ship.execute_order(Order.protect(protectee))
    ```

    (`get_tree()` returns null in the bare-node unit tests above, which is
    why those tests call `_issue_armed_command` directly with a world
    position instead of going through `_on_right_press`'s mouse read — keep
    that `get_tree()` call only inside the `ATTACK_TARGET` branch, so the
    `MOVE_TO`/`PROTECT` tests above don't need a live tree.)
  - Rewrite `_on_right_press`:

    ```gdscript
    func _on_right_press() -> void:
        if _has_armed_command:
            _issue_armed_command(get_global_mouse_position())
        var none: Array[Ship] = []
        selected_ships = none
        queue_redraw()
    ```
  - In `_on_left_release`, delete the `else: _issue_order(end)` branch
    entirely — a click that hits no ship and isn't a drag now does nothing:

    ```gdscript
    func _on_left_release(start: Vector2, end: Vector2) -> void:
        if start.distance_to(end) >= drag_threshold:
            var boxed := FleetCommander.ships_in_rect(ships, Rect2(start, Vector2.ZERO).expand(end))
            if not boxed.is_empty():
                selected_ships = boxed
        else:
            var picked := FleetCommander.ship_at_point(ships, end, select_radius)
            if picked != null:
                var picked_ships: Array[Ship] = [picked]
                selected_ships = picked_ships
        queue_redraw()
    ```

- [ ] **Step 9: Wire the new signals in `scripts\combat\combat_scene.gd`**,
  next to the existing `order_bar.hold_pressed.connect(...)` lines (around
  line 70-71):

  ```gdscript
  order_bar.move_pressed.connect(fleet_commander.set_armed_command.bind(Order.Type.MOVE_TO))
  order_bar.attack_pressed.connect(fleet_commander.set_armed_command.bind(Order.Type.ATTACK_TARGET))
  order_bar.protect_pressed.connect(fleet_commander.set_armed_command.bind(Order.Type.PROTECT))
  ```

- [ ] **Step 10: Add the three input actions to `project.godot`**, next to
  the existing `order_hold`/`order_flee` entries, using Python with
  `newline=''`:

  ```
  order_move={
  "deadzone": 0.5,
  "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":77,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
  ]
  }
  order_attack={
  "deadzone": 0.5,
  "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":65,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
  ]
  }
  order_protect={
  "deadzone": 0.5,
  "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":80,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
  ]
  }
  ```

  Confirm M, A and P aren't already bound to anything else in
  `project.godot`'s `[input]` section before adding these.

- [ ] **Step 11: Run the full suite.** Expected: clean. `test_fleet_commander`'s
  pre-existing `_check_selection_changed` test calls `_on_right_press()` with
  no armed command set on a fresh `FleetCommander` — confirm it still passes
  unchanged (it should, since `_has_armed_command` defaults to `false`).

- [ ] **Step 12: Commit:** "Add Move/Attack/Protect command buttons and
  hotkeys; right-click now issues the armed command, left-click only selects".

---

### Task 4: Weapon focus, imperfect dodge, and movement pacing

**Files:**
- Modify: `scripts\ship\ship.gd` (`_process_weapons`, new `primary_weapons`,
  new dodge state/update, `_park_at`, `_process_hold_position`,
  `_process_protect`)
- Modify: `scripts\weapons\weapon_mount.gd` (`_spawn_projectile` adds
  projectiles to a group)
- Modify: `scenes\ship\ship_corvette.tscn`, `scenes\ship\ship_capital.tscn`,
  `scenes\ship\ship_freighter.tscn` (`ShipEngine` export values)
- Test: `tests\test_ship.gd` (sync, `primary_weapons`), new
  `tests\test_weapon_focus_and_dodge_async.gd` (async, registered in
  `run_tests.gd`)

**Interfaces:**
- Produces:
  - `Ship.PRIMARY_WEAPON_COUNT := 2` (const).
  - `static func Ship.primary_weapons(weapons: Array[Weapon]) -> Array[Weapon]`.
  - `Ship.DODGE_REACT_RADIUS := 250.0`, `Ship.DODGE_OFFSET := 60.0`,
    `Ship.DODGE_DECAY_TIME := 0.6` (consts).
- Consumes: `CombatTactics.range_weapons`, `CombatTactics.weapon_dps`
  (existing), `Weapon.point_defense` (existing).

- [ ] **Step 1: Write the failing sync test** in `tests\test_ship.gd`, next to
  the other `Ship.best_engagement_range` checks (reuse that file's
  `_make_weapon(range, dps_damage, fire_rate)`-style helper if one exists —
  check the top of the file first and match its exact signature):

  ```gdscript
  static func _check_primary_weapons(failures: Array[String]) -> void:
      var pd := _make_weapon(150.0, 5.0, 1.0)
      pd.point_defense = true
      var weakest := _make_weapon(300.0, 5.0, 1.0)
      var middle := _make_weapon(300.0, 10.0, 1.0)
      var strongest := _make_weapon(300.0, 20.0, 1.0)
      var picked := Ship.primary_weapons([pd, weakest, middle, strongest])
      if picked.size() != 2 or not picked.has(strongest) or not picked.has(middle):
          failures.append("primary_weapons: expected the top 2 non-PD weapons by dps, got %s" % [picked])
      if picked.has(pd):
          failures.append("primary_weapons: expected PD excluded from the ranked set")
      var only_one := Ship.primary_weapons([weakest])
      if only_one != [weakest]:
          failures.append("primary_weapons: expected a single weapon returned unchanged, got %s" % [only_one])
      var all_pd := Ship.primary_weapons([pd])
      if all_pd != [pd]:
          failures.append("primary_weapons: expected range_weapons' all-PD fallback kept, got %s" % [all_pd])
  ```

  Register it in `run()`.

- [ ] **Step 2: Run it.** Expected: FAIL.

- [ ] **Step 3: Implement `Ship.primary_weapons`** near `best_engagement_range`:

  ```gdscript
  const PRIMARY_WEAPON_COUNT := 2

  # The ship's best non-PD weapons by dps, capped at PRIMARY_WEAPON_COUNT. PD
  # keeps firing independently (it's defense, not the offensive focus here).
  static func primary_weapons(weapons: Array[Weapon]) -> Array[Weapon]:
      var ranked := CombatTactics.range_weapons(weapons).duplicate()
      ranked.sort_custom(func(a: Weapon, b: Weapon) -> bool: return CombatTactics.weapon_dps(a) > CombatTactics.weapon_dps(b))
      return ranked.slice(0, PRIMARY_WEAPON_COUNT)
  ```

- [ ] **Step 4: Run it.** Expected: PASS.

- [ ] **Step 5: Write the failing async tests** in
  `tests\test_weapon_focus_and_dodge_async.gd` (new file, same
  `_spawn`/`_spawn_dummy`/`_run_for`/`_cleanup` pattern as Task 2's test
  file — copy it rather than importing, since these test files are meant to
  stand alone):

  ```gdscript
  extends RefCounted

  const CorvetteScene = preload("res://scenes/ship/ship_corvette.tscn")
  const CapitalScene = preload("res://scenes/ship/ship_capital.tscn")
  const Railgun = preload("res://resources/weapons/railgun.tres")
  const PdLaserTurret = preload("res://resources/weapons/pd_laser_turret.tres")

  const ENEMY_GROUP := &"test_focus_enemies"
  const ALLY_GROUP := &"test_focus_allies"

  static func run_async(tree: SceneTree) -> Array[String]:
      var failures: Array[String] = []
      await _check_only_primary_weapons_fire(tree, failures)
      await _check_pd_fires_regardless(tree, failures)
      await _check_dodge_offsets_station(tree, failures)
      return failures

  static func _spawn_dummy(tree: SceneTree, pos: Vector2, group: StringName) -> Ship:
      var ship: Ship = CorvetteScene.instantiate()
      tree.root.add_child(ship)
      ship.global_position = pos
      for mount in ship.weapon_mounts:
          mount.weapon = null
      ship.ally_group = group
      ship.add_to_group(group)
      ship.enemy_group = ENEMY_GROUP if group == ALLY_GROUP else ALLY_GROUP
      ship.set_physics_process(false)
      ship.hull.max_hp = 1.0e9
      ship.hull.current_hp = 1.0e9
      await tree.physics_frame
      return ship

  static func _run_for(tree: SceneTree, seconds: float) -> void:
      for i in int(seconds * Engine.physics_ticks_per_second):
          await tree.physics_frame

  static func _cleanup(tree: SceneTree, nodes: Array) -> void:
      for node in nodes:
          if is_instance_valid(node):
              node.queue_free()
      await tree.physics_frame

  static func _check_only_primary_weapons_fire(tree: SceneTree, failures: Array[String]) -> void:
      var target := await _spawn_dummy(tree, Vector2(700.0, 500.0), ENEMY_GROUP)
      var capital: Ship = CapitalScene.instantiate()
      tree.root.add_child(capital)
      capital.global_position = Vector2(500.0, 500.0)
      # Capital has 3 mounts: wire 3 distinct-dps railguns so one is clearly
      # the lowest and must be held back.
      var weak := Railgun.duplicate()
      weak.damage = 1.0
      capital.weapon_mounts[0].weapon = weak
      capital.weapon_mounts[1].weapon = Railgun.duplicate()
      capital.weapon_mounts[2].weapon = Railgun.duplicate()
      capital.ally_group = ALLY_GROUP
      capital.add_to_group(ALLY_GROUP)
      capital.enemy_group = ENEMY_GROUP
      await tree.physics_frame
      capital.execute_order(Order.attack_target(target))
      await _run_for(tree, 1.0)
      if capital.weapon_mounts[0].cooldown_remaining > 0.0:
          failures.append("only_primary_weapons_fire: expected the lowest-dps mount to be held back, but it fired")
      if capital.weapon_mounts[1].cooldown_remaining <= 0.0 and capital.weapon_mounts[2].cooldown_remaining <= 0.0:
          failures.append("only_primary_weapons_fire: expected the two higher-dps mounts to fire")
      await _cleanup(tree, [target, capital])

  static func _check_pd_fires_regardless(tree: SceneTree, failures: Array[String]) -> void:
      var target := await _spawn_dummy(tree, Vector2(600.0, 500.0), ENEMY_GROUP)
      var ship := await _spawn_dummy(tree, Vector2(500.0, 500.0), ALLY_GROUP)
      ship.weapon_mounts[0].weapon = PdLaserTurret
      ship.weapon_mounts[1].weapon = Railgun.duplicate()
      if ship.weapon_mounts.size() > 2:
          ship.weapon_mounts[2].weapon = Railgun.duplicate()
      ship.set_physics_process(true)
      ship.execute_order(Order.attack_target(target))
      await _run_for(tree, 1.0)
      if ship.weapon_mounts[0].cooldown_remaining <= 0.0:
          failures.append("pd_fires_regardless: expected the PD mount to fire even when not in the top-2 ranked set")
      await _cleanup(tree, [target, ship])

  static func _check_dodge_offsets_station(tree: SceneTree, failures: Array[String]) -> void:
      var target := await _spawn_dummy(tree, Vector2(700.0, 500.0), ENEMY_GROUP)
      var attacker := await _spawn_dummy(tree, Vector2(500.0, 500.0), ALLY_GROUP)
      attacker.set_physics_process(true)
      attacker.weapon_mounts[0].weapon = Railgun
      var projectile := Projectile.new()
      tree.root.add_child(projectile)
      projectile.global_position = target.global_position
      projectile.target = attacker
      projectile.travel_direction = (attacker.global_position - target.global_position).normalized()
      projectile.add_to_group(&"projectiles")
      attacker.execute_order(Order.hold_position())
      await tree.physics_frame
      if attacker._dodge_timer <= 0.0:
          failures.append("dodge_offsets_station: expected an incoming projectile targeting this ship to start a dodge")
      await _cleanup(tree, [target, attacker, projectile])
  ```

- [ ] **Step 6: Run them.** Expected: FAIL.

- [ ] **Step 7: Mark incoming projectiles.** In
  `scripts\weapons\weapon_mount.gd`'s `_spawn_projectile`, right after
  `host.add_child(projectile)`, add `projectile.add_to_group(&"projectiles")`.

- [ ] **Step 8: Implement the weapon focus filter.** Rewrite
  `Ship._process_weapons`:

  ```gdscript
  func _process_weapons() -> void:
      if weapon_mounts.is_empty():
          return
      var candidates := _enemy_candidates()
      var primary := Ship.pick_autofire_target(current_order, candidates, global_position, attack_range(), idle_target())
      var focus := Ship.primary_weapons(working_weapons())
      for mount in weapon_mounts:
          if not mount.can_fire():
              continue
          if mount.weapon != null and not mount.weapon.point_defense and not focus.has(mount.weapon):
              continue
          var target := Ship.pick_mount_target(mount, primary, candidates)
          if target != null:
              mount.try_fire(target)
  ```

- [ ] **Step 9: Implement the dodge.** Add fields and consts near the top of
  `ship.gd`:

  ```gdscript
  const DODGE_REACT_RADIUS := 250.0
  const DODGE_OFFSET := 60.0
  const DODGE_DECAY_TIME := 0.6

  var _dodge_offset: Vector2 = Vector2.ZERO
  var _dodge_timer: float = 0.0
  ```

  Add an update function and call it first thing in `_physics_process`
  (before `_process_order_movement`):

  ```gdscript
  func _update_dodge(delta: float) -> void:
      _dodge_timer = maxf(_dodge_timer - delta, 0.0)
      if _dodge_timer > 0.0:
          return
      for p in get_tree().get_nodes_in_group(&"projectiles"):
          if is_instance_valid(p) and p.target == self and global_position.distance_to(p.global_position) <= DODGE_REACT_RADIUS:
              var side := p.travel_direction.orthogonal()
              _dodge_offset = side * DODGE_OFFSET * (1.0 if randf() < 0.5 else -1.0)
              _dodge_timer = DODGE_DECAY_TIME
              break

  # The current jink offset, full strength right after a dodge triggers,
  # fading linearly back to zero over DODGE_DECAY_TIME.
  func _dodge_vector() -> Vector2:
      return _dodge_offset * (_dodge_timer / DODGE_DECAY_TIME) if _dodge_timer > 0.0 else Vector2.ZERO
  ```

  Call `_update_dodge(delta)` as the first line of `_physics_process`, before
  `_process_order_movement(delta)`.

  Apply the offset in the three station-holding spots:
  - `_park_at`: after computing `station := target_pos + bearing * centre_gap`
    (before the ally-separation push is added), add
    `station += _dodge_vector()`.
  - `_process_hold_position`: change the `engine.hold_station(...)` call's
    last positional arg from `_hold_position_anchor` to
    `_hold_position_anchor + _dodge_vector()`.
  - `_process_protect`: add `station += _dodge_vector()` right before the
    `engine.hold_station(...)` call.

- [ ] **Step 10: Run the async tests.** Expected: PASS.

- [ ] **Step 11: Retune ship pacing.** In the three `ShipEngine` nodes:
  - `scenes\ship\ship_corvette.tscn`: `max_speed = 200.0`,
    `acceleration = 160.0`, `turn_rate = 3.5` (was 280.0/220.0/5.0).
  - `scenes\ship\ship_capital.tscn`: `max_speed = 80.0`,
    `acceleration = 50.0`, `turn_rate = 0.85` (was 90.0/60.0/1.0).
  - `scenes\ship\ship_freighter.tscn`: `max_speed = 95.0`,
    `acceleration = 65.0`, `turn_rate = 1.2` (was 110.0/80.0/1.5).

  These are starting numbers, not final — the spec flags them as a
  playtest tuning item. Don't touch `ShipType.BASE_STATS` (see Global
  Constraints).

- [ ] **Step 12: Run the full suite.** Expected: clean. Pay particular
  attention to any test with a fixed-duration `_run_for`/physics-frame-count
  assertion written against the old speeds (e.g. a kite or run test expecting
  a ship to cover a certain distance in N seconds) — if the slower corvette
  now fails to reach an assertion's distance/time window, widen that test's
  tolerance or duration rather than reverting the speed change; note each
  such adjustment in the commit message.

- [ ] **Step 13: Run `tests\perf_combat.gd`** (non-headless, per
  `carry_forward.md`'s recipe) at 10v10 and confirm frame time is still well
  inside the 8 ms avg / 33 ms max bar — a slower corvette takes longer to
  close, which can run more ships' AI loops concurrently for longer.

- [ ] **Step 14: Commit:** "Ships focus their best weapons, jink against
  incoming fire, and fly slower".

---

## Final review

After Task 4, one whole-change review on the most capable model, against the
spec and this plan. It must specifically check:
- A full idle-start battle (via `CombatSceneScene`, not just unit tests):
  ships hold formation, nobody drifts, and issuing each of the five commands
  from a fresh battle works end to end including the UI buttons.
- The campaign bootstrap path (`campaign_scene.gd`'s hand-written comps, not
  only `ShipType.new_composition()`), per the carry-forward's standing rule
  that only the real bootstrap numbers expose some bugs.
- A manual non-headless playtest pass: does Protect read as "shooting things
  near the ally," does the slower pacing fix the fly-by complaint or just
  make it slower, does weapon focus look like a ship "committing" rather than
  going quiet. Record findings in `carry_forward.md`, not as code changes
  made during the review itself.
- One `tests\perf_combat.gd` run at 15v15 or 20v20, since slower ships plus
  five playable commands could extend average battle length past what the
  original `NPC_fleet_scale` perf gate assumed.
