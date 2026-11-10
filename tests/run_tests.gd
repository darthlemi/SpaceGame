extends SceneTree

func _initialize() -> void:
	_run_all()

func _run_all() -> void:
	var test_scripts := [
		preload("res://tests/test_order.gd"),
		preload("res://tests/test_ship_component.gd"),
		preload("res://tests/test_weapon.gd"),
		preload("res://tests/test_weapon_resources.gd"),
		preload("res://tests/test_drone_bay.gd"),
		preload("res://tests/test_bomber_drone.gd"),
		preload("res://tests/test_ew_drone.gd"),
		preload("res://tests/test_drone_scenes.gd"),
		preload("res://tests/test_hull.gd"),
		preload("res://tests/test_shield.gd"),
		preload("res://tests/test_ship_engine.gd"),
		preload("res://tests/test_weapon_mount.gd"),
		preload("res://tests/test_projectile.gd"),
		preload("res://tests/test_ship.gd"),
		preload("res://tests/test_ai_controller_state.gd"),
		preload("res://tests/test_combat_tactics.gd"),
		preload("res://tests/test_combat_camera.gd"),
		preload("res://tests/test_formation.gd"),
		preload("res://tests/test_fleet_commander.gd"),
		load("res://tests/test_debug_actions.gd"),
		preload("res://tests/test_debug_console.gd"),
		preload("res://tests/test_ship_vfx.gd"),
		preload("res://tests/test_campaign_fleet.gd"),
		preload("res://tests/test_ship_type.gd"),
		preload("res://tests/test_crew_rules.gd"),
		preload("res://tests/test_patrol_behavior.gd"),
		preload("res://tests/test_trader_behavior.gd"),
		preload("res://tests/test_pirate_behavior.gd"),
		preload("res://tests/test_campaign_state.gd"),
		preload("res://tests/test_power_faction.gd"),
		preload("res://tests/test_commodity.gd"),
		preload("res://tests/test_fleet_allocation_policy.gd"),
		preload("res://tests/test_economy_role.gd"),
		preload("res://tests/test_base_economy.gd"),
		preload("res://tests/test_part_rarity.gd"),
		preload("res://tests/test_shield_generator.gd"),
		preload("res://tests/test_engine_core.gd"),
		preload("res://tests/test_skirmish_resolution.gd"),
		preload("res://tests/test_battle_resolution.gd"),
		preload("res://tests/test_refit_catalog.gd"),
		preload("res://tests/test_theme.gd"),
		preload("res://tests/test_galaxy.gd"),
		preload("res://tests/test_galaxy_data.gd"),
		preload("res://tests/test_campaign_start_stock.gd"),
		preload("res://tests/test_campaign_station_snapshots.gd"),
		preload("res://tests/test_galaxy_document.gd"),
		preload("res://tests/test_galaxy_validator.gd"),
		preload("res://tests/test_map_edit_model.gd"),
		preload("res://tests/test_jump_rules.gd"),
		preload("res://tests/test_editor_fields.gd"),
		preload("res://tests/test_scenery_randomizer.gd"),
		preload("res://tests/test_scenery_canvas.gd"),
		preload("res://tests/test_scenery_editor.gd"),
		preload("res://tests/test_danger_tier.gd"),
		preload("res://tests/test_fleet_budget.gd"),
		preload("res://tests/test_npc_jump_planner.gd"),
		preload("res://tests/test_starfield_assignment.gd"),
		preload("res://tests/test_combat_scenery.gd"),
	]
	var total_failures := 0
	for script in test_scripts:
		var failures: Array[String] = script.run()
		for f in failures:
			print("FAIL [%s]: %s" % [script.resource_path, f])
		total_failures += failures.size()

	# Async integration test: requires a live SceneTree and a process frame for
	# _ready() to actually run, so it can't use the synchronous run() pattern above.
	var ship_test = preload("res://tests/test_ship.gd")
	var async_failures: Array[String] = await ship_test.run_async(self)
	for f in async_failures:
		print("FAIL [%s]: %s" % [ship_test.resource_path, f])
	total_failures += async_failures.size()

	var ai_targeting_test = preload("res://tests/test_ai_controller_targeting.gd")
	var ai_targeting_failures: Array[String] = await ai_targeting_test.run_async(self)
	for f in ai_targeting_failures:
		print("FAIL [%s]: %s" % [ai_targeting_test.resource_path, f])
	total_failures += ai_targeting_failures.size()

	var target_scoring_test = load("res://tests/test_target_scoring_async.gd")
	var target_scoring_failures: Array[String] = await target_scoring_test.run_async(self)
	for f in target_scoring_failures:
		print("FAIL [%s]: %s" % [target_scoring_test.resource_path, f])
	total_failures += target_scoring_failures.size()

	var flee_async_test = load("res://tests/test_flee_async.gd")
	var flee_async_failures: Array[String] = await flee_async_test.run_async(self)
	for f in flee_async_failures:
		print("FAIL [%s]: %s" % [flee_async_test.resource_path, f])
	total_failures += flee_async_failures.size()

	var protect_and_retarget_test = load("res://tests/test_protect_and_retarget_async.gd")
	var protect_and_retarget_failures: Array[String] = await protect_and_retarget_test.run_async(self)
	for f in protect_and_retarget_failures:
		print("FAIL [%s]: %s" % [protect_and_retarget_test.resource_path, f])
	total_failures += protect_and_retarget_failures.size()

	var order_bar_test = load("res://tests/test_order_bar.gd")
	var order_bar_failures: Array[String] = await order_bar_test.run_async(self)
	for f in order_bar_failures:
		print("FAIL [%s]: %s" % [order_bar_test.resource_path, f])
	total_failures += order_bar_failures.size()

	var ship_tactics_test = load("res://tests/test_ship_tactics.gd")
	var ship_tactics_failures: Array[String] = await ship_tactics_test.run_async(self)
	for f in ship_tactics_failures:
		print("FAIL [%s]: %s" % [ship_tactics_test.resource_path, f])
	total_failures += ship_tactics_failures.size()

	var ship_vfx_test = preload("res://tests/test_ship_vfx.gd")
	var ship_vfx_failures: Array[String] = await ship_vfx_test.run_async(self)
	for f in ship_vfx_failures:
		print("FAIL [%s]: %s" % [ship_vfx_test.resource_path, f])
	total_failures += ship_vfx_failures.size()

	var ship_randomize_loadout_test = preload("res://tests/test_ship_randomize_loadout.gd")
	var ship_randomize_loadout_failures: Array[String] = await ship_randomize_loadout_test.run_async(self)
	for f in ship_randomize_loadout_failures:
		print("FAIL [%s]: %s" % [ship_randomize_loadout_test.resource_path, f])
	total_failures += ship_randomize_loadout_failures.size()

	var weapon_mount_async_test = preload("res://tests/test_weapon_mount.gd")
	var weapon_mount_async_failures: Array[String] = await weapon_mount_async_test.run_async(self)
	for f in weapon_mount_async_failures:
		print("FAIL [%s]: %s" % [weapon_mount_async_test.resource_path, f])
	total_failures += weapon_mount_async_failures.size()

	var ship_type_scenes_test = preload("res://tests/test_ship_type_scenes.gd")
	var ship_type_scenes_failures: Array[String] = await ship_type_scenes_test.run_async(self)
	for f in ship_type_scenes_failures:
		print("FAIL [%s]: %s" % [ship_type_scenes_test.resource_path, f])
	total_failures += ship_type_scenes_failures.size()

	var weapon_loadout_test = preload("res://tests/test_weapon_loadout.gd")
	var weapon_loadout_failures: Array[String] = await weapon_loadout_test.run_async(self)
	for f in weapon_loadout_failures:
		print("FAIL [%s]: %s" % [weapon_loadout_test.resource_path, f])
	total_failures += weapon_loadout_failures.size()

	var speed_controls_test = preload("res://tests/test_speed_controls.gd")
	var speed_controls_failures: Array[String] = await speed_controls_test.run_async(self)
	for f in speed_controls_failures:
		print("FAIL [%s]: %s" % [speed_controls_test.resource_path, f])
	total_failures += speed_controls_failures.size()

	# Loaded (not preloaded) because combat_scene.gd now bare-references the
	# CampaignState autoload at the top of its _ready(); preload() would resolve
	# this chain at compile-time of run_tests.gd itself, before any frame has
	# elapsed and before CampaignState is registered as a global identifier in
	# --script mode. By this point several run_async calls above have already
	# awaited frames, so the autoload is registered by the time load() runs.
	var combat_scene_test = load("res://tests/test_combat_scene.gd")
	var combat_scene_failures: Array[String] = await combat_scene_test.run_async(self)
	for f in combat_scene_failures:
		print("FAIL [%s]: %s" % [combat_scene_test.resource_path, f])
	total_failures += combat_scene_failures.size()

	# Loaded (not preloaded) because campaign_scene.gd bare-references the
	# CampaignState autoload; preload() would resolve this chain at
	# compile-time of run_tests.gd itself, before CampaignState is registered
	# as a global identifier in --script mode. By this point several run_async
	# calls above have already awaited frames, so the autoload is registered
	# by the time load() runs. Positioned after combat_scene_test (rather than
	# right after the first run_async block) because its Engage-button path
	# triggers a real, several-frames-deferred change_scene_to_file that was
	# found to race with test_ai_controller_targeting's single-frame timing
	# assumption when placed immediately before it.
	var campaign_scene_test = load("res://tests/test_campaign_scene.gd")
	var campaign_scene_failures: Array[String] = await campaign_scene_test.run_async(self)
	for f in campaign_scene_failures:
		print("FAIL [%s]: %s" % [campaign_scene_test.resource_path, f])
	total_failures += campaign_scene_failures.size()

	var campaign_layers_test = load("res://tests/test_campaign_layers.gd")
	var campaign_layers_failures: Array[String] = await campaign_layers_test.run_async(self)
	for f in campaign_layers_failures:
		print("FAIL [%s]: %s" % [campaign_layers_test.resource_path, f])
	total_failures += campaign_layers_failures.size()

	var campaign_jumping_test = load("res://tests/test_campaign_jumping.gd")
	var campaign_jumping_failures: Array[String] = await campaign_jumping_test.run_async(self)
	for f in campaign_jumping_failures:
		print("FAIL [%s]: %s" % [campaign_jumping_test.resource_path, f])
	total_failures += campaign_jumping_failures.size()

	var campaign_ai_jumps_test = load("res://tests/test_campaign_ai_jumps.gd")
	var campaign_ai_jumps_failures: Array[String] = await campaign_ai_jumps_test.run_async(self)
	for f in campaign_ai_jumps_failures:
		print("FAIL [%s]: %s" % [campaign_ai_jumps_test.resource_path, f])
	total_failures += campaign_ai_jumps_failures.size()

	var jump_map_panel_test = load("res://tests/test_jump_map_panel.gd")
	var jump_map_panel_failures: Array[String] = await jump_map_panel_test.run_async(self)
	for f in jump_map_panel_failures:
		print("FAIL [%s]: %s" % [jump_map_panel_test.resource_path, f])
	total_failures += jump_map_panel_failures.size()

	var systems_stations_panel_test = load("res://tests/test_systems_stations_panel.gd")
	var systems_stations_panel_failures: Array[String] = await systems_stations_panel_test.run_async(self)
	for f in systems_stations_panel_failures:
		print("FAIL [%s]: %s" % [systems_stations_panel_test.resource_path, f])
	total_failures += systems_stations_panel_failures.size()

	var campaign_galaxy_state_test = load("res://tests/test_campaign_galaxy_state.gd")
	var campaign_galaxy_state_failures: Array[String] = await campaign_galaxy_state_test.run_async(self)
	for f in campaign_galaxy_state_failures:
		print("FAIL [%s]: %s" % [campaign_galaxy_state_test.resource_path, f])
	total_failures += campaign_galaxy_state_failures.size()

	var campaign_economy_bootstrap_test = load("res://tests/test_campaign_economy_bootstrap.gd")
	var campaign_economy_bootstrap_failures: Array[String] = await campaign_economy_bootstrap_test.run_async(self)
	for f in campaign_economy_bootstrap_failures:
		print("FAIL [%s]: %s" % [campaign_economy_bootstrap_test.resource_path, f])
	total_failures += campaign_economy_bootstrap_failures.size()

	var campaign_scene_trading_test = load("res://tests/test_campaign_scene_trading.gd")
	var campaign_scene_trading_failures: Array[String] = await campaign_scene_trading_test.run_async(self)
	for f in campaign_scene_trading_failures:
		print("FAIL [%s]: %s" % [campaign_scene_trading_test.resource_path, f])
	total_failures += campaign_scene_trading_failures.size()

	# Loaded (not preloaded) for the same reason as campaign_scene_test above:
	# campaign_scene.gd bare-references the CampaignState autoload.
	var campaign_long_run_sim_test = load("res://tests/test_campaign_long_run_sim.gd")
	var campaign_long_run_sim_failures: Array[String] = await campaign_long_run_sim_test.run_async(self)
	for f in campaign_long_run_sim_failures:
		print("FAIL [%s]: %s" % [campaign_long_run_sim_test.resource_path, f])
	total_failures += campaign_long_run_sim_failures.size()

	var campaign_fleet_icon_test = preload("res://tests/test_campaign_fleet_icon.gd")
	var campaign_fleet_icon_failures: Array[String] = await campaign_fleet_icon_test.run_async(self)
	for f in campaign_fleet_icon_failures:
		print("FAIL [%s]: %s" % [campaign_fleet_icon_test.resource_path, f])
	total_failures += campaign_fleet_icon_failures.size()

	# Loaded (not preloaded): loot_panel.gd bare-references the CampaignState autoload.
	var loot_panel_test = load("res://tests/test_loot_panel.gd")
	var loot_panel_failures: Array[String] = await loot_panel_test.run_async(self)
	for f in loot_panel_failures:
		print("FAIL [%s]: %s" % [loot_panel_test.resource_path, f])
	total_failures += loot_panel_failures.size()

	# Loaded (not preloaded) because trade_panel.gd bare-references the
	# CampaignState autoload; preload() would resolve this chain at
	# compile-time of run_tests.gd itself, before CampaignState is registered
	# as a global identifier in --script mode. By this point several
	# run_async calls above have already awaited frames, so the autoload is
	# registered by the time load() runs.
	var trade_panel_test = load("res://tests/test_trade_panel.gd")
	var trade_panel_failures: Array[String] = await trade_panel_test.run_async(self)
	for f in trade_panel_failures:
		print("FAIL [%s]: %s" % [trade_panel_test.resource_path, f])
	total_failures += trade_panel_failures.size()

	# Loaded (not preloaded) because refit_panel.gd bare-references the
	# CampaignState autoload; preload() would resolve this chain at
	# compile-time of run_tests.gd itself, before CampaignState is registered
	# as a global identifier in --script mode. By this point several
	# run_async calls above have already awaited frames, so the autoload is
	# registered by the time load() runs.
	var refit_panel_test = load("res://tests/test_refit_panel.gd")
	var refit_panel_failures: Array[String] = await refit_panel_test.run_async(self)
	for f in refit_panel_failures:
		print("FAIL [%s]: %s" % [refit_panel_test.resource_path, f])
	total_failures += refit_panel_failures.size()

	# Loaded (not preloaded) for the same CampaignState-autoload reason as above.
	var repair_panel_test = load("res://tests/test_repair_panel.gd")
	var repair_panel_failures: Array[String] = await repair_panel_test.run_async(self)
	for f in repair_panel_failures:
		print("FAIL [%s]: %s" % [repair_panel_test.resource_path, f])
	total_failures += repair_panel_failures.size()

	var fleet_management_panel_test = load("res://tests/test_fleet_management_panel.gd")
	var fleet_management_panel_failures: Array[String] = await fleet_management_panel_test.run_async(self)
	for f in fleet_management_panel_failures:
		print("FAIL [%s]: %s" % [fleet_management_panel_test.resource_path, f])
	total_failures += fleet_management_panel_failures.size()

	var base_overview_panel_test = load("res://tests/test_base_overview_panel.gd")
	var base_overview_panel_failures: Array[String] = await base_overview_panel_test.run_async(self)
	for f in base_overview_panel_failures:
		print("FAIL [%s]: %s" % [base_overview_panel_test.resource_path, f])
	total_failures += base_overview_panel_failures.size()

	var map_editor_test = load("res://tests/test_map_editor.gd")
	var map_editor_failures: Array[String] = await map_editor_test.run_async(self)
	for f in map_editor_failures:
		print("FAIL [%s]: %s" % [map_editor_test.resource_path, f])
	total_failures += map_editor_failures.size()

	var game_over_test = preload("res://tests/test_game_over.gd")
	var game_over_failures: Array[String] = await game_over_test.run_async(self)
	for f in game_over_failures:
		print("FAIL [%s]: %s" % [game_over_test.resource_path, f])
	total_failures += game_over_failures.size()

	var campaign_state_test = preload("res://tests/test_campaign_state.gd")
	var campaign_state_async_failures: Array[String] = await campaign_state_test.run_async(self)
	for f in campaign_state_async_failures:
		print("FAIL [%s]: %s" % [campaign_state_test.resource_path, f])
	total_failures += campaign_state_async_failures.size()

	var ship_crew_test = load("res://tests/test_ship_crew.gd")
	var ship_crew_failures: Array[String] = await ship_crew_test.run_async(self)
	for f in ship_crew_failures:
		print("FAIL [%s]: %s" % [ship_crew_test.resource_path, f])
	total_failures += ship_crew_failures.size()

	var campaign_scene_fleet_panel_test = load("res://tests/test_campaign_scene_fleet_panel.gd")
	var campaign_scene_fleet_panel_failures: Array[String] = await campaign_scene_fleet_panel_test.run_async(self)
	for f in campaign_scene_fleet_panel_failures:
		print("FAIL [%s]: %s" % [campaign_scene_fleet_panel_test.resource_path, f])
	total_failures += campaign_scene_fleet_panel_failures.size()

	var campaign_scene_systems_stations_test = load("res://tests/test_campaign_scene_systems_stations.gd")
	var campaign_scene_systems_stations_failures: Array[String] = await campaign_scene_systems_stations_test.run_async(self)
	for f in campaign_scene_systems_stations_failures:
		print("FAIL [%s]: %s" % [campaign_scene_systems_stations_test.resource_path, f])
	total_failures += campaign_scene_systems_stations_failures.size()

	var jettison_panel_test = load("res://tests/test_jettison_panel.gd")
	var jettison_panel_failures: Array[String] = await jettison_panel_test.run_async(self)
	for f in jettison_panel_failures:
		print("FAIL [%s]: %s" % [jettison_panel_test.resource_path, f])
	total_failures += jettison_panel_failures.size()

	var respawn_panel_test = load("res://tests/test_respawn_panel.gd")
	var respawn_panel_failures: Array[String] = await respawn_panel_test.run_async(self)
	for f in respawn_panel_failures:
		print("FAIL [%s]: %s" % [respawn_panel_test.resource_path, f])
	total_failures += respawn_panel_failures.size()

	var weapon_focus_and_dodge_test = load("res://tests/test_weapon_focus_and_dodge_async.gd")
	var weapon_focus_and_dodge_failures: Array[String] = await weapon_focus_and_dodge_test.run_async(self)
	for f in weapon_focus_and_dodge_failures:
		print("FAIL [%s]: %s" % [weapon_focus_and_dodge_test.resource_path, f])
	total_failures += weapon_focus_and_dodge_failures.size()

	var fleet_commander_test = preload("res://tests/test_fleet_commander.gd")
	var fleet_commander_failures: Array[String] = await fleet_commander_test.run_async(self)
	for f in fleet_commander_failures:
		print("FAIL [%s]: %s" % [fleet_commander_test.resource_path, f])
	total_failures += fleet_commander_failures.size()

	if total_failures == 0:
		print("All tests passed.")
	else:
		print("%d test failure(s)." % total_failures)
	quit(1 if total_failures > 0 else 0)
