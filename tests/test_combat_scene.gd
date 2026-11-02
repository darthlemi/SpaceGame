extends RefCounted

const CombatSceneScene = preload("res://scenes/combat/combat_scene.tscn")

# See tests/test_ship.gd's run_async note: _ready()'s fleet spawning and signal wiring
# only runs on the next process frame after the scene enters the live SceneTree -- and
# combat_scene.gd's own _ready() now awaits an *additional* internal frame before wiring
# hull signals (see Task 6 Step 3), so this must await twice before asserting on any of it.
static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(scene)

	await tree.process_frame
	await tree.process_frame

	if scene.player_ships.size() != scene.player_spawn_points.size():
		failures.append("run_async: expected %d player ships spawned, got %d" % [scene.player_spawn_points.size(), scene.player_ships.size()])
	if scene.enemy_ships.size() != scene.enemy_spawn_points.size():
		failures.append("run_async: expected %d enemy ships spawned, got %d" % [scene.enemy_spawn_points.size(), scene.enemy_ships.size()])

	for ship in scene.player_ships:
		if ship.enemy_group != scene.ENEMY_GROUP:
			failures.append("run_async: expected player ship enemy_group == ENEMY_GROUP, got %s" % ship.enemy_group)
	for ship in scene.enemy_ships:
		if ship.enemy_group != scene.PLAYER_GROUP:
			failures.append("run_async: expected enemy ship enemy_group == PLAYER_GROUP, got %s" % ship.enemy_group)
		if ship.get_children().filter(func(c): return c is AIController).is_empty():
			failures.append("run_async: expected each enemy ship to own an AIController child")

	if scene.fleet_commander == null or scene.fleet_commander.ships != scene.player_ships:
		failures.append("run_async: expected fleet_commander.ships == player_ships")

	if scene.result_label == null:
		failures.append("run_async: expected result_label resolved by @onready, got null")
	elif scene.result_label.visible:
		failures.append("run_async: expected result_label.visible == false immediately after _ready()")

	# Victory: destroy every enemy ship's hull.
	for ship in scene.enemy_ships.duplicate():
		ship.hull.apply_damage(ship.hull.max_hp)
	if scene.result_label != null:
		if scene.result_label.text != "Victory":
			failures.append("run_async: expected result_label.text == 'Victory' after all enemy ships destroyed, got '%s'" % scene.result_label.text)
		if not scene.result_label.visible:
			failures.append("run_async: expected result_label.visible == true after Victory")

	if is_instance_valid(scene) and not scene.is_queued_for_deletion():
		scene.queue_free()

	# Defeat path: fresh scene instance, mirrors the Victory check above.
	var defeat_scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(defeat_scene)
	await tree.process_frame
	await tree.process_frame

	for ship in defeat_scene.player_ships.duplicate():
		ship.hull.apply_damage(ship.hull.max_hp)
	if defeat_scene.result_label != null:
		if defeat_scene.result_label.text != "Defeat":
			failures.append("run_async: expected result_label.text == 'Defeat' after all player ships destroyed, got '%s'" % defeat_scene.result_label.text)
		if not defeat_scene.result_label.visible:
			failures.append("run_async: expected result_label.visible == true after Defeat")

	if is_instance_valid(defeat_scene) and not defeat_scene.is_queued_for_deletion():
		defeat_scene.queue_free()

	# Campaign-driven battle: CombatScene should spawn from CampaignState
	# fleet data and report results back instead of using fixed spawn points.
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")
	var player_fleet := CampaignFleet.new()
	player_fleet.ship_compositions = [{
		"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0,
		"engine_max_hp": 25.0, "engine_current_hp": 5.0,
		"weapon_mount_max_hp": [15.0], "weapon_mount_current_hp": [3.0],
		"weapon_mount_items": ["res://resources/weapons/railgun.tres"],
		"shield_item": "res://resources/shields/shield_dominion_aegis.tres",
		"engine_item": "res://resources/engines/engine_freehold_racer.tres",
	}]
	var enemy_fleet := CampaignFleet.new()
	enemy_fleet.ship_compositions = [{"ship_type": ShipType.Kind.FREIGHTER, "max_hp": 80.0, "current_hp": 80.0, "max_shield": 20.0, "current_shield": 20.0}]
	campaign_state.player_fleet = player_fleet
	campaign_state.start_engagement(enemy_fleet)

	var campaign_scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(campaign_scene)
	await tree.process_frame
	await tree.process_frame

	if campaign_scene.player_ships.size() != 1:
		failures.append("campaign battle: expected 1 player ship spawned from fleet data, got %d" % campaign_scene.player_ships.size())
	if campaign_scene.enemy_ships.size() != 1:
		failures.append("campaign battle: expected 1 enemy ship spawned from fleet data, got %d" % campaign_scene.enemy_ships.size())
	if campaign_scene.enemy_ships.size() == 1:
		var spawned_enemy: Ship = campaign_scene.enemy_ships[0]
		if spawned_enemy.ship_type != ShipType.Kind.FREIGHTER:
			failures.append("campaign battle: expected the FREIGHTER-tagged composition to spawn a ship_type FREIGHTER, got %s" % spawned_enemy.ship_type)
		if spawned_enemy.weapon_mounts.size() != 0:
			failures.append("campaign battle: expected the spawned FREIGHTER ship to have 0 weapon mounts, got %d" % spawned_enemy.weapon_mounts.size())

	if campaign_scene.player_ships.size() == 1:
		var spawned_player: Ship = campaign_scene.player_ships[0]
		if not is_equal_approx(spawned_player.engine.current_hp, 5.0):
			failures.append("campaign battle: expected spawned player engine.current_hp carried over from composition, got %s" % spawned_player.engine.current_hp)
		if spawned_player.weapon_mounts[0].weapon == null or spawned_player.weapon_mounts[0].weapon.weapon_name != "Railgun":
			failures.append("campaign battle: expected the equipped railgun applied to the spawned player's weapon mount")
		if not is_equal_approx(spawned_player.shield.max_shield, 35.0):
			failures.append("campaign battle: expected the equipped aegis shield's max_shield (35.0) applied, got %s" % spawned_player.shield.max_shield)
		if not is_equal_approx(spawned_player.engine.max_speed, 300.0):
			failures.append("campaign battle: expected the equipped racer engine's max_speed (300.0) applied, got %s" % spawned_player.engine.max_speed)
		if spawned_player.weapon_mounts.size() != 1 or not is_equal_approx(spawned_player.weapon_mounts[0].current_hp, 3.0):
			failures.append("campaign battle: expected spawned player mount current_hp carried over from composition")

		spawned_player.engine.apply_damage(1000.0)
		spawned_player.weapon_mounts[0].apply_damage(1000.0)

	for ship in campaign_scene.enemy_ships.duplicate():
		ship.hull.apply_damage(ship.hull.max_hp)
	await tree.process_frame

	if not enemy_fleet.is_destroyed():
		failures.append("campaign battle: expected enemy_fleet marked destroyed after losing all ships")
	if campaign_state.active_enemy_fleet != null:
		failures.append("campaign battle: expected active_enemy_fleet cleared after resolution")

	if campaign_state.player_fleet.ship_compositions.size() != 1:
		failures.append("campaign battle: expected player_fleet to still have 1 surviving ship composition, got %d" % campaign_state.player_fleet.ship_compositions.size())
	elif campaign_state.player_fleet.ship_compositions[0].get("ship_type") != ShipType.Kind.CORVETTE:
		failures.append("campaign battle: expected the surviving player ship's composition to carry ship_type CORVETTE back from combat, got %s" % campaign_state.player_fleet.ship_compositions[0].get("ship_type"))
	else:
		var surviving_comp: Dictionary = campaign_state.player_fleet.ship_compositions[0]
		if surviving_comp.get("engine_current_hp", -1.0) != 0.0:
			failures.append("campaign battle: expected the destroyed engine's 0 hp carried back into the composition, got %s" % surviving_comp.get("engine_current_hp"))
		if surviving_comp.get("weapon_mount_current_hp", [-1.0])[0] != 0.0:
			failures.append("campaign battle: expected the destroyed mount's 0 hp carried back into the composition, got %s" % surviving_comp.get("weapon_mount_current_hp"))
		if surviving_comp.get("weapon_mount_items", []) != ["res://resources/weapons/railgun.tres"]:
			failures.append("campaign battle: expected equipped weapon item path carried back into the surviving composition, got %s" % surviving_comp.get("weapon_mount_items"))
		if surviving_comp.get("shield_item", "") != "res://resources/shields/shield_dominion_aegis.tres":
			failures.append("campaign battle: expected equipped shield item path carried back into the surviving composition")
		if surviving_comp.get("engine_item", "") != "res://resources/engines/engine_freehold_racer.tres":
			failures.append("campaign battle: expected equipped engine item path carried back into the surviving composition")

	campaign_state.reset()
	if is_instance_valid(campaign_scene) and not campaign_scene.is_queued_for_deletion():
		campaign_scene.queue_free()

	# Regression: randomize_loadout (ship_capital.tscn/ship_corvette.tscn) fills
	# every weapon mount with a random weapon at spawn time, even mounts the
	# player never equipped via RefitPanel. _collect_survivor_data must carry
	# weapon_mount_items forward from the ORIGINAL composition, not read the
	# live mount's weapon back -- otherwise an unequipped slot's random roll
	# gets permanently baked into the player's composition and silently eats
	# loadout budget forever.
	var randomize_state = tree.root.get_node("/root/CampaignState")
	randomize_state.reset()
	var randomize_player_fleet := CampaignFleet.new()
	randomize_player_fleet.ship_compositions = [{
		"ship_type": ShipType.Kind.CAPITAL, "max_hp": 220.0, "current_hp": 220.0, "max_shield": 80.0, "current_shield": 80.0,
		"weapon_mount_max_hp": [30.0, 30.0, 30.0], "weapon_mount_current_hp": [30.0, 30.0, 30.0],
		"weapon_mount_items": ["res://resources/weapons/railgun.tres", "", ""],
	}]
	var randomize_enemy_fleet := CampaignFleet.new()
	randomize_enemy_fleet.ship_compositions = [{"ship_type": ShipType.Kind.FREIGHTER, "max_hp": 80.0, "current_hp": 80.0, "max_shield": 20.0, "current_shield": 20.0}]
	randomize_state.player_fleet = randomize_player_fleet
	randomize_state.start_engagement(randomize_enemy_fleet)

	var randomize_scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(randomize_scene)
	await tree.process_frame
	await tree.process_frame

	if randomize_scene.player_ships.size() == 1:
		var randomize_ship: Ship = randomize_scene.player_ships[0]
		if randomize_ship.weapon_mounts.size() == 3:
			if randomize_ship.weapon_mounts[1].weapon == null or randomize_ship.weapon_mounts[2].weapon == null:
				failures.append("randomize_loadout regression: expected the unequipped mounts to still get a random weapon live on the Ship node (randomize_loadout=true)")

	for ship in randomize_scene.enemy_ships.duplicate():
		ship.hull.apply_damage(ship.hull.max_hp)
	await tree.process_frame

	if randomize_state.player_fleet.ship_compositions.size() == 1:
		var randomize_surviving_comp: Dictionary = randomize_state.player_fleet.ship_compositions[0]
		var randomize_surviving_items: Array = randomize_surviving_comp.get("weapon_mount_items", [])
		if randomize_surviving_items.size() != 3 or randomize_surviving_items[0] != "res://resources/weapons/railgun.tres":
			failures.append("randomize_loadout regression: expected the explicitly equipped mount 0 (railgun) to survive the round-trip, got %s" % randomize_surviving_items)
		if randomize_surviving_items.size() == 3 and (randomize_surviving_items[1] != "" or randomize_surviving_items[2] != ""):
			failures.append("randomize_loadout regression: expected unequipped mounts 1/2 to stay '' in the surviving composition (not bake in the random weapon rolled at spawn), got %s" % randomize_surviving_items)

	randomize_state.reset()
	if is_instance_valid(randomize_scene) and not randomize_scene.is_queued_for_deletion():
		randomize_scene.queue_free()
	var randomize_leaked_scene: Node = tree.current_scene
	if randomize_leaked_scene != null and randomize_leaked_scene != randomize_scene:
		tree.current_scene = null
		if is_instance_valid(randomize_leaked_scene) and not randomize_leaked_scene.is_queued_for_deletion():
			randomize_leaked_scene.queue_free()

	# Regression: _spawn_extra_ship (debug-console AddFriend/AddEnemy) appends a
	# ship with no matching original_compositions entry. _collect_survivor_data
	# must not crash with an out-of-range index when _report_to_campaign runs.
	var extra_ship_state = tree.root.get_node("/root/CampaignState")
	extra_ship_state.reset()
	var extra_ship_player_fleet := CampaignFleet.new()
	extra_ship_player_fleet.ship_compositions = [{"ship_type": ShipType.Kind.CORVETTE, "max_hp": 60.0, "current_hp": 60.0, "max_shield": 20.0, "current_shield": 20.0}]
	var extra_ship_enemy_fleet := CampaignFleet.new()
	extra_ship_enemy_fleet.ship_compositions = [{"ship_type": ShipType.Kind.FREIGHTER, "max_hp": 80.0, "current_hp": 80.0, "max_shield": 20.0, "current_shield": 20.0}]
	extra_ship_state.player_fleet = extra_ship_player_fleet
	extra_ship_state.start_engagement(extra_ship_enemy_fleet)

	var extra_ship_scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(extra_ship_scene)
	await tree.process_frame
	await tree.process_frame

	await extra_ship_scene._spawn_extra_ship(extra_ship_scene.PLAYER_GROUP, extra_ship_scene.ENEMY_GROUP, 0.0, extra_ship_scene.player_ships)
	if extra_ship_scene.player_ships.size() != 2:
		failures.append("debug-spawn regression: expected _spawn_extra_ship to append a second player ship, got %d" % extra_ship_scene.player_ships.size())

	for ship in extra_ship_scene.enemy_ships.duplicate():
		ship.hull.apply_damage(ship.hull.max_hp)
	await tree.process_frame

	if extra_ship_state.player_fleet == null or extra_ship_state.player_fleet.ship_compositions.size() != 2:
		failures.append("debug-spawn regression: expected _report_to_campaign to complete without crashing and carry both ships' compositions back")

	extra_ship_state.reset()
	if is_instance_valid(extra_ship_scene) and not extra_ship_scene.is_queued_for_deletion():
		extra_ship_scene.queue_free()
	var extra_ship_leaked_scene: Node = tree.current_scene
	if extra_ship_leaked_scene != null and extra_ship_leaked_scene != extra_ship_scene:
		tree.current_scene = null
		if is_instance_valid(extra_ship_leaked_scene) and not extra_ship_leaked_scene.is_queued_for_deletion():
			extra_ship_leaked_scene.queue_free()

	# _report_to_campaign() above called change_scene_to_file, which swaps in
	# res://scenes/campaign/campaign_scene.tscn as tree.current_scene. Free it so it
	# doesn't linger in the tree (and keep bootstrapping/wandering fleets) for the
	# rest of the --script test run.
	var leaked_scene: Node = tree.current_scene
	if leaked_scene != null and leaked_scene != campaign_scene:
		tree.current_scene = null
		if is_instance_valid(leaked_scene) and not leaked_scene.is_queued_for_deletion():
			leaked_scene.queue_free()

	return failures
