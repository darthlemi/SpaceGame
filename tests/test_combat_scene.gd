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

	for ship in campaign_scene.enemy_ships.duplicate():
		ship.hull.apply_damage(ship.hull.max_hp)
	# After the Victory: disarming first would end the battle as an unarmed Stalemate.
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
	deploy_enemy.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.FREIGHTER)])
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

	# Destroyed ending: destroying every deployed enemy ship is a Victory; the enemy fleet is
	# defeated.
	# TODO: Task 4 reworks the battle end and adds captured ships to the loot.
	campaign_state.reset()
	var disable_player := CampaignFleet.new()
	disable_player.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	var disable_reserve := ShipType.new_composition(ShipType.Kind.CAPITAL)
	disable_reserve["crew"] = 8  # Under the capital deploy minimum (12): held back.
	var disable_enemy := CampaignFleet.new()
	disable_enemy.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CAPITAL), ShipType.new_composition(ShipType.Kind.CAPITAL), disable_reserve])
	campaign_state.enemy_fleets.assign([disable_enemy])
	campaign_state.player_fleet = disable_player
	campaign_state.start_engagement(disable_enemy)

	var disable_scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(disable_scene)
	await tree.process_frame
	await tree.process_frame

	if disable_scene.enemy_ships.size() != 2:
		failures.append("destroyed ending: expected the 2 crewed capitals deployed and the reserve held back, got %d enemy ships" % disable_scene.enemy_ships.size())
	for ship in disable_scene.enemy_ships.duplicate():
		ship.hull.apply_damage(ship.hull.max_hp)
	if disable_scene.result_label.text != "Victory":
		failures.append("destroyed ending: expected 'Victory' once every enemy ship is destroyed, got '%s'" % disable_scene.result_label.text)
	# The returned campaign scene's _ready opens its loot panel from pending_loot and clears it,
	# so read the panel. This enemy carries no cargo or parts, so there is nothing to loot.
	var loot_panel_visible := true
	for i in 10:
		await tree.process_frame
		var returned_scene: Node = tree.current_scene
		if returned_scene != null and returned_scene != disable_scene:
			loot_panel_visible = returned_scene.loot_panel.visible
			tree.current_scene = null
			if is_instance_valid(returned_scene) and not returned_scene.is_queued_for_deletion():
				returned_scene.queue_free()
			break

	if campaign_state.enemy_fleets.has(disable_enemy):
		failures.append("destroyed ending: expected the defeated enemy fleet removed from enemy_fleets")
	if loot_panel_visible:
		failures.append("destroyed ending: expected no loot window for an enemy with nothing to loot")
	campaign_state.reset()
	if is_instance_valid(disable_scene) and not disable_scene.is_queued_for_deletion():
		disable_scene.queue_free()

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

	# Defeat with a held-back ship: the fleet continues with it instead of game over.
	campaign_state.reset()
	var held_flagship := ShipType.new_composition(ShipType.Kind.CORVETTE)
	held_flagship["flagship"] = true
	var held_reserve := ShipType.new_composition(ShipType.Kind.CORVETTE)
	held_reserve["crew"] = 3  # Under the corvette deploy minimum (4): held back.
	var held_player := CampaignFleet.new()
	held_player.ship_compositions.assign([held_flagship, held_reserve])
	var held_reserve_before: Dictionary = held_reserve.duplicate(true)
	var held_enemy := CampaignFleet.new()
	held_enemy.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.FREIGHTER)])
	campaign_state.enemy_fleets.assign([held_enemy])
	campaign_state.player_fleet = held_player
	campaign_state.start_engagement(held_enemy)

	var held_scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(held_scene)
	await tree.process_frame
	await tree.process_frame

	if held_scene.player_ships.size() != 1:
		failures.append("held-back defeat: expected 1 player ship deployed, got %d" % held_scene.player_ships.size())
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

	# Unarmed stalemate: no side has a working weapon, so the battle ends at once
	# with both fleets intact, the enemy kept on the map and nothing looted.
	campaign_state.reset()
	var stale_player := CampaignFleet.new()
	stale_player.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.FREIGHTER)])
	var stale_enemy := CampaignFleet.new()
	stale_enemy.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.FREIGHTER)])
	stale_enemy.cargo = {Commodity.Type.ORE: 10.0}
	campaign_state.enemy_fleets.assign([stale_enemy])
	campaign_state.player_fleet = stale_player
	campaign_state.start_engagement(stale_enemy)

	var stale_scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(stale_scene)
	await tree.process_frame
	await tree.process_frame
	if stale_scene.result_label.text != "Stalemate" or not stale_scene.result_label.visible:
		failures.append("stalemate: expected 'Stalemate' shown for freighter vs freighter, got '%s' visible=%s" % [stale_scene.result_label.text, stale_scene.result_label.visible])
	var stale_next_scene: String = await _take_leaked_scene(tree, stale_scene)
	if stale_next_scene != "res://scenes/campaign/campaign_scene.tscn":
		failures.append("stalemate: expected a return to the campaign scene, got '%s'" % stale_next_scene)
	if campaign_state.player_fleet.ship_compositions.size() != 1 or stale_enemy.ship_compositions.size() != 1:
		failures.append("stalemate: expected both fleets intact, got %d player / %d enemy comps" % [campaign_state.player_fleet.ship_compositions.size(), stale_enemy.ship_compositions.size()])
	if not campaign_state.enemy_fleets.has(stale_enemy):
		failures.append("stalemate: expected the enemy fleet kept in enemy_fleets")
	if campaign_state.pending_loot != null or campaign_state.pending_respawn:
		failures.append("stalemate: expected no loot and no respawn")
	tree.paused = false
	campaign_state.reset()
	if is_instance_valid(stale_scene) and not stale_scene.is_queued_for_deletion():
		stale_scene.queue_free()

	# An armed enemy prevents the stalemate until its last weapon mount is destroyed.
	campaign_state.reset()
	var armed_player := CampaignFleet.new()
	armed_player.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.FREIGHTER)])
	var armed_enemy := CampaignFleet.new()
	armed_enemy.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	campaign_state.enemy_fleets.assign([armed_enemy])
	campaign_state.player_fleet = armed_player
	campaign_state.start_engagement(armed_enemy)

	var armed_scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(armed_scene)
	await tree.process_frame
	await tree.process_frame
	if armed_scene.result_label.visible:
		failures.append("armed vs unarmed: expected no immediate result, got '%s'" % armed_scene.result_label.text)
	if armed_scene.enemy_ships.size() == 1:
		var armed_mounts: Array[WeaponMount] = armed_scene.enemy_ships[0].weapon_mounts
		if armed_mounts.is_empty():
			failures.append("armed vs unarmed: expected the enemy corvette to have weapon mounts")
		for mount in armed_mounts:
			mount.apply_damage(mount.max_hp)
		if armed_scene.result_label.text != "Stalemate":
			failures.append("armed vs unarmed: expected 'Stalemate' once every enemy mount is destroyed, got '%s'" % armed_scene.result_label.text)
	await _take_leaked_scene(tree, armed_scene)
	if not campaign_state.enemy_fleets.has(armed_enemy) or armed_enemy.ship_compositions.size() != 1:
		failures.append("armed vs unarmed: expected the disarmed enemy fleet kept with its ship")
	tree.paused = false
	campaign_state.reset()
	if is_instance_valid(armed_scene) and not armed_scene.is_queued_for_deletion():
		armed_scene.queue_free()

	return failures

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
