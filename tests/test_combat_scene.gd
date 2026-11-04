extends RefCounted

const CombatSceneScene = preload("res://scenes/combat/combat_scene.tscn")

# First randf() of each seed sits outside the [ESCAPE_MIN, ESCAPE_MAX] clamp, so a single
# roll escapes (0.0125) or is caught (0.996) whatever the speeds.
const ESCAPE_SEED := 60
const CAPTURE_SEED := 14

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

	# Idle player ships hunt the enemy line to their right; they once drifted to the
	# origin because spawners place a ship after add_child has run its _ready.
	await tree.physics_frame
	for k in scene.player_ships.size():
		var heading: Vector2 = scene.player_ships[k].velocity
		if heading.x <= 0.0:
			failures.append("run_async: expected idle player ship %d to head toward the enemy, got velocity %s" % [k, heading])

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
	# The armed corvette keeps the battle going; an unarmed enemy alone would be an instant Victory.
	enemy_fleet.ship_compositions = [{"ship_type": ShipType.Kind.FREIGHTER, "max_hp": 80.0, "current_hp": 80.0, "max_shield": 20.0, "current_shield": 20.0}, ShipType.new_composition(ShipType.Kind.CORVETTE)]
	campaign_state.player_fleet = player_fleet
	campaign_state.start_engagement(enemy_fleet)

	var campaign_scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(campaign_scene)
	await tree.process_frame
	await tree.process_frame

	if campaign_scene.player_ships.size() != 1:
		failures.append("campaign battle: expected 1 player ship spawned from fleet data, got %d" % campaign_scene.player_ships.size())
	if campaign_scene.enemy_ships.size() != 2:
		failures.append("campaign battle: expected 2 enemy ships spawned from fleet data, got %d" % campaign_scene.enemy_ships.size())
	if campaign_scene.enemy_ships.size() == 2:
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

	for ship in campaign_scene.enemy_ships.duplicate():
		ship.hull.apply_damage(ship.hull.max_hp)
	# After the Victory: disarming first would end the battle as a Defeat.
	# The report is deferred, so this damage still reaches the survivor comp.
	if campaign_scene.player_ships.size() == 1:
		campaign_scene.player_ships[0].engine.apply_damage(1000.0)
		campaign_scene.player_ships[0].weapon_mounts[0].apply_damage(1000.0)
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
	randomize_enemy_fleet.ship_compositions = [ShipType.new_composition(ShipType.Kind.CORVETTE)]
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
	extra_ship_enemy_fleet.ship_compositions = [ShipType.new_composition(ShipType.Kind.CORVETTE)]
	extra_ship_state.enemy_fleets.assign([extra_ship_enemy_fleet])
	extra_ship_state.player_fleet = extra_ship_player_fleet
	extra_ship_state.start_engagement(extra_ship_enemy_fleet)

	var extra_ship_scene: Node2D = CombatSceneScene.instantiate()
	extra_ship_scene.escape_rng = _seeded_rng(CAPTURE_SEED)
	tree.root.add_child(extra_ship_scene)
	await tree.process_frame
	await tree.process_frame

	await extra_ship_scene._spawn_extra_ship(extra_ship_scene.PLAYER_GROUP, extra_ship_scene.ENEMY_GROUP, 0.0, extra_ship_scene.player_ships)
	if extra_ship_scene.player_ships.size() != 2:
		failures.append("debug-spawn regression: expected _spawn_extra_ship to append a second player ship, got %d" % extra_ship_scene.player_ships.size())
	# An enemy extra also has no comp; disarmed rather than destroyed, it rolls to escape and is caught.
	await extra_ship_scene._spawn_extra_ship(extra_ship_scene.ENEMY_GROUP, extra_ship_scene.PLAYER_GROUP, PI, extra_ship_scene.enemy_ships)
	if extra_ship_scene.enemy_ships.size() != 2:
		failures.append("debug-spawn regression: expected _spawn_extra_ship to append a second enemy ship, got %d" % extra_ship_scene.enemy_ships.size())
	else:
		extra_ship_scene.enemy_ships[0].hull.apply_damage(extra_ship_scene.enemy_ships[0].hull.max_hp)
		for mount in extra_ship_scene.enemy_ships[1].weapon_mounts:
			mount.apply_damage(mount.max_hp)
	if extra_ship_scene.result_label.text != "Victory":
		failures.append("debug-spawn regression: expected 'Victory' once the enemy extra is disarmed, got '%s'" % extra_ship_scene.result_label.text)
	await tree.process_frame

	if extra_ship_state.player_fleet == null or extra_ship_state.player_fleet.ship_compositions.size() != 2:
		failures.append("debug-spawn regression: expected _report_to_campaign to complete without crashing and carry both ships' compositions back")
	if extra_ship_state.enemy_fleets.has(extra_ship_enemy_fleet):
		failures.append("debug-spawn regression: expected the enemy erased once its extra was captured")

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

	# Regression: a ship lost mid-battle is freed before the deferred report runs, and
	# passing it to a Ship-typed parameter raised "previously freed" and aborted the report.
	campaign_state.reset()
	var freed_player := CampaignFleet.new()
	freed_player.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE), ShipType.new_composition(ShipType.Kind.CORVETTE)])
	var freed_enemy := CampaignFleet.new()
	freed_enemy.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	campaign_state.enemy_fleets.assign([freed_enemy])
	campaign_state.player_fleet = freed_player
	campaign_state.start_engagement(freed_enemy)

	var freed_scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(freed_scene)
	await tree.process_frame
	await tree.process_frame
	if freed_scene.player_ships.size() != 2:
		failures.append("freed-ship report: expected 2 player ships deployed, got %d" % freed_scene.player_ships.size())
	else:
		var lost_ship: Ship = freed_scene.player_ships[0]
		lost_ship.hull.apply_damage(lost_ship.hull.max_hp)
		await tree.process_frame
		await tree.process_frame
		if is_instance_valid(lost_ship):
			failures.append("freed-ship report: expected the lost ship freed before the battle ends")
		for ship in freed_scene.enemy_ships.duplicate():
			ship.hull.apply_damage(ship.hull.max_hp)
		await _take_loot_offer(tree, freed_scene)
		if campaign_state.active_enemy_fleet != null:
			failures.append("freed-ship report: expected _report_to_campaign to resolve the engagement")
		if campaign_state.player_fleet == null or campaign_state.player_fleet.ship_compositions.size() != 1:
			failures.append("freed-ship report: expected the 1 surviving player ship carried back")
	campaign_state.reset()
	if is_instance_valid(freed_scene) and not freed_scene.is_queued_for_deletion():
		freed_scene.queue_free()

	# Crew deployment: only crewed, deploy-flagged ships spawn; the held-back
	# comps come back unchanged after the battle.
	campaign_state.reset()
	var deploy_flagship := ShipType.new_composition(ShipType.Kind.CORVETTE)
	deploy_flagship["crew"] = 12
	deploy_flagship["flagship"] = true
	var deploy_short := ShipType.new_composition(ShipType.Kind.CORVETTE)
	deploy_short["crew"] = 2
	deploy_short["deploy"] = true
	var deploy_held := ShipType.new_composition(ShipType.Kind.FREIGHTER)
	deploy_held["crew"] = 6
	deploy_held["deploy"] = false
	var deploy_player := CampaignFleet.new()
	deploy_player.ship_compositions.assign([deploy_flagship, deploy_short, deploy_held])
	var deploy_short_before: Dictionary = deploy_short.duplicate(true)
	var deploy_held_before: Dictionary = deploy_held.duplicate(true)
	var deploy_enemy := CampaignFleet.new()
	deploy_enemy.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	campaign_state.player_fleet = deploy_player
	campaign_state.start_engagement(deploy_enemy)

	var deploy_scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(deploy_scene)
	await tree.process_frame
	await tree.process_frame

	if deploy_scene.player_ships.size() != 1:
		failures.append("crew deploy: expected only the crewed, deploy-flagged ship spawned, got %d" % deploy_scene.player_ships.size())
	else:
		var deployed: Ship = deploy_scene.player_ships[0]
		if deployed.crew_floor != 0:
			failures.append("crew deploy: expected player ship crew_floor 0, got %d" % deployed.crew_floor)
		if not is_equal_approx(deployed.crew, 12.0) or deployed.crew_complement != 12:
			failures.append("crew deploy: expected player ship crew 12/12 from its comp, got %s/%d" % [deployed.crew, deployed.crew_complement])
	if deploy_scene.enemy_ships.size() != 1:
		failures.append("crew deploy: expected 1 enemy ship spawned, got %d" % deploy_scene.enemy_ships.size())
	elif deploy_scene.enemy_ships[0].crew_floor != CrewRules.NPC_CREW_FLOOR:
		failures.append("crew deploy: expected enemy ship crew_floor %d, got %d" % [CrewRules.NPC_CREW_FLOOR, deploy_scene.enemy_ships[0].crew_floor])

	for ship in deploy_scene.enemy_ships.duplicate():
		ship.hull.apply_damage(ship.hull.max_hp)
	var deploy_next_scene: String = await _take_leaked_scene(tree, deploy_scene)

	var deploy_comps: Array[Dictionary] = campaign_state.player_fleet.ship_compositions
	if deploy_comps.size() != 3:
		failures.append("crew deploy: expected the fought ship plus 2 held-back comps after the battle, got %d comps" % deploy_comps.size())
	else:
		if deploy_comps[0].get("crew", -1) != 12 or deploy_comps[0].get("flagship") != true or deploy_comps[0].get("deploy") != true:
			failures.append("crew deploy: expected the fought ship back with crew 12, flagship true, deploy true, got %s" % deploy_comps[0])
		if deploy_comps[1] != deploy_short_before:
			failures.append("crew deploy: expected the under-crewed held-back comp unchanged, got %s" % deploy_comps[1])
		if deploy_comps[2] != deploy_held_before:
			failures.append("crew deploy: expected the deploy:false held-back comp unchanged, got %s" % deploy_comps[2])
	if deploy_next_scene != "res://scenes/campaign/campaign_scene.tscn":
		failures.append("crew deploy: expected the victory to return to the campaign scene, got '%s'" % deploy_next_scene)
	campaign_state.reset()
	if is_instance_valid(deploy_scene) and not deploy_scene.is_queued_for_deletion():
		deploy_scene.queue_free()

	# Victory with an enemy held-back corvette: it rolls to escape against the player's top speed.
	# Escaping, it keeps the enemy fleet (and its cargo) on the map with nothing looted.
	campaign_state.reset()
	var fled_reserve := ShipType.new_composition(ShipType.Kind.CORVETTE)
	fled_reserve["crew"] = 3  # Under the corvette deploy minimum (4): held back.
	var fled_enemy := CampaignFleet.new()
	fled_enemy.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE), fled_reserve])
	fled_enemy.cargo = {Commodity.Type.ORE: 10.0}
	var fled_player := CampaignFleet.new()
	fled_player.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	campaign_state.enemy_fleets.assign([fled_enemy])
	campaign_state.player_fleet = fled_player
	campaign_state.start_engagement(fled_enemy)

	var fled_scene: Node2D = CombatSceneScene.instantiate()
	fled_scene.escape_rng = _seeded_rng(ESCAPE_SEED)
	tree.root.add_child(fled_scene)
	await tree.process_frame
	await tree.process_frame
	if fled_scene.enemy_ships.size() != 1:
		failures.append("held-back escape: expected only the crewed enemy corvette deployed, got %d" % fled_scene.enemy_ships.size())
	for ship in fled_scene.enemy_ships.duplicate():
		ship.hull.apply_damage(ship.hull.max_hp)
	if fled_scene.result_label.text != "Victory":
		failures.append("held-back escape: expected 'Victory', got '%s'" % fled_scene.result_label.text)
	var fled_offer: LootOffer = await _take_loot_offer(tree, fled_scene)
	if not campaign_state.enemy_fleets.has(fled_enemy) or fled_enemy.ship_compositions.size() != 1:
		failures.append("held-back escape: expected the enemy fleet kept with 1 ship, got %d" % fled_enemy.ship_compositions.size())
	elif CrewRules.crew_of(fled_enemy.ship_compositions[0]) != 3:
		failures.append("held-back escape: expected the escaper to keep its crew 3, got %d" % CrewRules.crew_of(fled_enemy.ship_compositions[0]))
	if fled_offer != null and not fled_offer.ships.is_empty():
		failures.append("held-back escape: expected no captured ships offered, got %d" % fled_offer.ships.size())
	if fled_enemy.cargo.get(Commodity.Type.ORE, 0.0) != 10.0:
		failures.append("held-back escape: expected the escaper to keep all the cargo, got %s" % fled_enemy.cargo)
	campaign_state.reset()
	if is_instance_valid(fled_scene) and not fled_scene.is_queued_for_deletion():
		fled_scene.queue_free()

	# Same battle with the roll failing: the corvette is offered with its crew and the fleet is gone.
	campaign_state.reset()
	var caught_reserve := ShipType.new_composition(ShipType.Kind.CORVETTE)
	caught_reserve["crew"] = 3
	var caught_enemy := CampaignFleet.new()
	caught_enemy.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE), caught_reserve])
	var caught_player := CampaignFleet.new()
	caught_player.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	campaign_state.enemy_fleets.assign([caught_enemy])
	campaign_state.player_fleet = caught_player
	campaign_state.start_engagement(caught_enemy)

	var caught_scene: Node2D = CombatSceneScene.instantiate()
	caught_scene.escape_rng = _seeded_rng(CAPTURE_SEED)
	tree.root.add_child(caught_scene)
	await tree.process_frame
	await tree.process_frame
	for ship in caught_scene.enemy_ships.duplicate():
		ship.hull.apply_damage(ship.hull.max_hp)
	var caught_offer: LootOffer = await _take_loot_offer(tree, caught_scene)
	if caught_offer == null or caught_offer.ships.size() != 1:
		failures.append("held-back capture: expected the captured corvette offered as loot")
	elif ShipType.kind_of(caught_offer.ships[0]) != ShipType.Kind.CORVETTE or CrewRules.crew_of(caught_offer.ships[0]) != 3:
		failures.append("held-back capture: expected a corvette with crew 3 offered, got %s" % caught_offer.ships[0])
	if campaign_state.enemy_fleets.has(caught_enemy):
		failures.append("held-back capture: expected the enemy fleet erased")
	if campaign_state.player_fleet.ship_compositions.size() != 1:
		failures.append("held-back capture: expected the captured ship only offered, not added, got %d player comps" % campaign_state.player_fleet.ship_compositions.size())
	campaign_state.reset()
	if is_instance_valid(caught_scene) and not caught_scene.is_queued_for_deletion():
		caught_scene.queue_free()

	# Mutual knockout (Review Focus 2): both sides out in the same check -> Defeat.
	campaign_state.reset()
	var mutual_player := CampaignFleet.new()
	mutual_player.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	var mutual_enemy := CampaignFleet.new()
	var mutual_reserve := ShipType.new_composition(ShipType.Kind.CORVETTE)
	mutual_reserve["crew"] = 3  # Under the corvette deploy minimum (4): held back, so the fleet outlives the knockout.
	mutual_enemy.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE), mutual_reserve])
	campaign_state.enemy_fleets.assign([mutual_enemy])
	campaign_state.player_fleet = mutual_player
	campaign_state.start_engagement(mutual_enemy)

	var mutual_scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(mutual_scene)
	await tree.process_frame
	await tree.process_frame

	var mutual_ships: Array = mutual_scene.player_ships + mutual_scene.enemy_ships
	for ship in mutual_ships:
		# Blocking the hull's signals keeps its destroyed handler from running the end check early.
		ship.hull.set_block_signals(true)
		ship.hull.apply_damage(ship.hull.max_hp)
		ship.hull.set_block_signals(false)
		ship.queue_free()
		if not ship.hull.is_destroyed():
			failures.append("mutual knockout: expected every ship destroyed by the setup damage")
	if mutual_scene.result_label.visible:
		failures.append("mutual knockout: expected no result before the end check runs")
	mutual_scene._check_battle_end()
	if mutual_scene.result_label.text != "Defeat":
		failures.append("mutual knockout: expected 'Defeat' when both sides are out in the same check, got '%s'" % mutual_scene.result_label.text)
	await _take_leaked_scene(tree, mutual_scene)
	# The total loss opened the respawn panel, which paused the tree.
	tree.paused = false
	if not campaign_state.enemy_fleets.has(mutual_enemy):
		failures.append("mutual knockout: expected the enemy fleet kept after a player defeat")
	campaign_state.reset()
	if is_instance_valid(mutual_scene) and not mutual_scene.is_queued_for_deletion():
		mutual_scene.queue_free()

	# Defeat with a held-back ship that escapes: the fleet continues with it instead of game over.
	campaign_state.reset()
	var held_flagship := ShipType.new_composition(ShipType.Kind.CORVETTE)
	held_flagship["flagship"] = true
	var held_reserve := ShipType.new_composition(ShipType.Kind.CORVETTE)
	held_reserve["crew"] = 3  # Under the corvette deploy minimum (4): held back.
	var held_player := CampaignFleet.new()
	held_player.ship_compositions.assign([held_flagship, held_reserve])
	var held_reserve_before: Dictionary = held_reserve.duplicate(true)
	var held_enemy := CampaignFleet.new()
	held_enemy.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	campaign_state.enemy_fleets.assign([held_enemy])
	campaign_state.player_fleet = held_player
	campaign_state.start_engagement(held_enemy)

	var held_scene: Node2D = CombatSceneScene.instantiate()
	held_scene.escape_rng = _seeded_rng(ESCAPE_SEED)  # The held-back reserve gets away.
	tree.root.add_child(held_scene)
	await tree.process_frame
	await tree.process_frame

	if held_scene.player_ships.size() != 1:
		failures.append("held-back defeat: expected 1 player ship deployed, got %d" % held_scene.player_ships.size())
	# Speeds fed to the escape roll: spawned ships use their live engine, held-back comps the crew-scaled top speed.
	var held_speeds: Array[float] = []
	held_scene._collect_survivor_data(held_scene.player_ships, held_player.ship_compositions, held_scene._player_spawned_indices, held_speeds)
	if held_speeds.size() != 2:
		failures.append("held-back speeds: expected 2 speeds, got %s" % [held_speeds])
	else:
		if not is_equal_approx(held_speeds[0], held_scene.player_ships[0].engine.effective_max_speed()):
			failures.append("held-back speeds: expected the deployed ship's live engine speed, got %s" % held_speeds[0])
		if not is_equal_approx(held_speeds[1], ShipType.base_speed_for(ShipType.Kind.CORVETTE) * 0.625):
			failures.append("held-back speeds: expected the held-back corvette at base * 0.625 (crew 3 of 12), got %s" % held_speeds[1])
	if held_scene.enemy_ships.size() == 1:
		if not is_equal_approx(held_scene._pursuer_speed(held_scene.enemy_ships), held_scene.enemy_ships[0].engine.effective_max_speed()):
			failures.append("pursuer speed: expected the winner ship's live engine speed")
		var no_pursuers: Array[Ship] = []
		if held_scene._pursuer_speed(no_pursuers) != 0.0:
			failures.append("pursuer speed: expected 0 with no winner ships")
	for ship in held_scene.player_ships.duplicate():
		ship.hull.apply_damage(ship.hull.max_hp)
	if held_scene.result_label.text != "Defeat":
		failures.append("held-back defeat: expected 'Defeat' once every deployed player ship is destroyed, got '%s'" % held_scene.result_label.text)
	var held_next_scene: String = await _take_leaked_scene(tree, held_scene)

	var held_comps: Array[Dictionary] = campaign_state.player_fleet.ship_compositions
	if held_comps.size() != 1:
		failures.append("held-back defeat: expected only the held-back comp left, got %d comps" % held_comps.size())
	else:
		var held_after: Dictionary = held_comps[0].duplicate(true)
		# ensure_flagship reassigns the lost flagship role to the survivor.
		if held_after.get("flagship") != true:
			failures.append("held-back defeat: expected the surviving comp promoted to flagship")
		held_after.erase("flagship")
		var held_expected: Dictionary = held_reserve_before.duplicate(true)
		held_expected.erase("flagship")
		if held_after != held_expected:
			failures.append("held-back defeat: expected the held-back comp unchanged, got %s" % held_comps[0])
	if held_next_scene != "res://scenes/campaign/campaign_scene.tscn":
		failures.append("held-back defeat: expected the campaign scene (not game over), got '%s'" % held_next_scene)
	campaign_state.reset()
	if is_instance_valid(held_scene) and not held_scene.is_queued_for_deletion():
		held_scene.queue_free()

	# Total loss (nothing held back): respawn instead of game over.
	campaign_state.reset()
	var loss_player := CampaignFleet.new()
	loss_player.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	var loss_enemy := CampaignFleet.new()
	loss_enemy.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CAPITAL)])
	campaign_state.enemy_fleets.assign([loss_enemy])
	campaign_state.player_fleet = loss_player
	campaign_state.credits = 400
	campaign_state.start_engagement(loss_enemy)

	var loss_scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(loss_scene)
	await tree.process_frame
	await tree.process_frame
	for ship in loss_scene.player_ships.duplicate():
		ship.hull.apply_damage(ship.hull.max_hp)
	var loss_next_scene: String = await _take_leaked_scene(tree, loss_scene)
	if not campaign_state.pending_respawn:
		failures.append("total loss: expected pending_respawn set")
	if campaign_state.credits != 300:
		failures.append("total loss: expected the 25 percent credit penalty, got %s" % campaign_state.credits)
	if loss_next_scene != "res://scenes/campaign/campaign_scene.tscn":
		failures.append("total loss: expected the campaign scene (not game over), got '%s'" % loss_next_scene)
	tree.paused = false
	campaign_state.reset()
	if is_instance_valid(loss_scene) and not loss_scene.is_queued_for_deletion():
		loss_scene.queue_free()

	# An unarmed player fleet against an armed enemy is an immediate Defeat, then escape rolls.
	# The roll fails: the freighter joins the enemy fleet (flagship cleared) and the player respawns.
	campaign_state.reset()
	var unarmed_freighter := ShipType.new_composition(ShipType.Kind.FREIGHTER)
	unarmed_freighter["flagship"] = true
	var unarmed_player := CampaignFleet.new()
	unarmed_player.ship_compositions.assign([unarmed_freighter])
	var unarmed_enemy := CampaignFleet.new()
	unarmed_enemy.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	campaign_state.enemy_fleets.assign([unarmed_enemy])
	campaign_state.player_fleet = unarmed_player
	campaign_state.start_engagement(unarmed_enemy)

	var unarmed_scene: Node2D = CombatSceneScene.instantiate()
	unarmed_scene.escape_rng = _seeded_rng(CAPTURE_SEED)
	tree.root.add_child(unarmed_scene)
	await tree.process_frame
	await tree.process_frame
	if unarmed_scene.result_label.text != "Defeat" or not unarmed_scene.result_label.visible:
		failures.append("unarmed player: expected an immediate 'Defeat', got '%s' visible=%s" % [unarmed_scene.result_label.text, unarmed_scene.result_label.visible])
	var unarmed_next_scene: String = await _take_leaked_scene(tree, unarmed_scene)
	tree.paused = false
	if unarmed_next_scene != "res://scenes/campaign/campaign_scene.tscn":
		failures.append("unarmed player: expected a return to the campaign scene, got '%s'" % unarmed_next_scene)
	if not campaign_state.enemy_fleets.has(unarmed_enemy) or unarmed_enemy.ship_compositions.size() != 2:
		failures.append("unarmed player: expected the captured freighter appended to the enemy fleet, got %d enemy comps" % unarmed_enemy.ship_compositions.size())
	elif ShipType.kind_of(unarmed_enemy.ship_compositions[1]) != ShipType.Kind.FREIGHTER or CrewRules.is_flagship(unarmed_enemy.ship_compositions[1]):
		failures.append("unarmed player: expected the captured freighter with its flagship flag cleared, got %s" % unarmed_enemy.ship_compositions[1])
	if not campaign_state.pending_respawn or not campaign_state.player_fleet.ship_compositions.is_empty():
		failures.append("unarmed player: expected the emptied player fleet to respawn")
	campaign_state.reset()
	if is_instance_valid(unarmed_scene) and not unarmed_scene.is_queued_for_deletion():
		unarmed_scene.queue_free()

	# Review Focus 2: destroying the enemy's last weapon mount mid-battle (hulls intact) is a Victory.
	campaign_state.reset()
	var disarm_player := CampaignFleet.new()
	disarm_player.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	var disarm_enemy := CampaignFleet.new()
	disarm_enemy.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	campaign_state.enemy_fleets.assign([disarm_enemy])
	campaign_state.player_fleet = disarm_player
	campaign_state.start_engagement(disarm_enemy)

	var disarm_scene: Node2D = CombatSceneScene.instantiate()
	disarm_scene.escape_rng = _seeded_rng(ESCAPE_SEED)
	tree.root.add_child(disarm_scene)
	await tree.process_frame
	await tree.process_frame
	if disarm_scene.result_label.visible:
		failures.append("disarm: expected no immediate result with both sides armed, got '%s'" % disarm_scene.result_label.text)
	if disarm_scene.enemy_ships.size() == 1:
		var disarm_mounts: Array[WeaponMount] = disarm_scene.enemy_ships[0].weapon_mounts
		if disarm_mounts.is_empty():
			failures.append("disarm: expected the enemy corvette to have weapon mounts")
		for mount in disarm_mounts:
			mount.apply_damage(mount.max_hp)
		if disarm_scene.enemy_ships[0].hull.is_destroyed():
			failures.append("disarm: expected the enemy hull intact")
	if disarm_scene.result_label.text != "Victory":
		failures.append("disarm: expected 'Victory' once every enemy mount is destroyed, got '%s'" % disarm_scene.result_label.text)
	await _take_leaked_scene(tree, disarm_scene)
	if not campaign_state.enemy_fleets.has(disarm_enemy) or disarm_enemy.ship_compositions.size() != 1:
		failures.append("disarm: expected the disarmed enemy to escape with its ship")
	elif CrewRules.is_armed(disarm_enemy.ship_compositions[0]):
		failures.append("disarm: expected the escaper's comp to carry its destroyed mount back")
	tree.paused = false
	campaign_state.reset()
	if is_instance_valid(disarm_scene) and not disarm_scene.is_queued_for_deletion():
		disarm_scene.queue_free()

	return failures

static func _seeded_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

# Like _take_leaked_scene, but returns the loot offer the returned campaign scene opened
# (its _ready consumes pending_loot), or null when it opened none.
static func _take_loot_offer(tree: SceneTree, own_scene: Node) -> LootOffer:
	for i in 10:
		await tree.process_frame
		var current: Node = tree.current_scene
		if current != null and current != own_scene:
			var offer: LootOffer = current.loot_panel._offer if current.loot_panel.visible else null
			tree.current_scene = null
			if is_instance_valid(current) and not current.is_queued_for_deletion():
				current.queue_free()
			return offer
	return null

# change_scene_to_file applies a few frames later; poll for it, then free the
# swapped-in scene so it doesn't keep running for the rest of the test run.
# Returns the swapped-in scene's path, or "" if no change happened.
static func _take_leaked_scene(tree: SceneTree, own_scene: Node) -> String:
	for i in 10:
		await tree.process_frame
		var current: Node = tree.current_scene
		if current != null and current != own_scene:
			var path := current.scene_file_path
			tree.current_scene = null
			if is_instance_valid(current) and not current.is_queued_for_deletion():
				current.queue_free()
			return path
	return ""
