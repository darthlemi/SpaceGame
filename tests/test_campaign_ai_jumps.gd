extends RefCounted

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")
const CampaignStateScript = preload("res://scripts/campaign/campaign_state.gd")
const COMBAT := CampaignFleet.Role.COMBAT
const TRADER := CampaignFleet.Role.TRADER
const TICK := 0.1
const FUEL := Commodity.Type.FUEL

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	_check_single_jump(failures)
	_check_multi_jump(failures)
	_check_round_trip_in_tick(failures)
	_check_refuel_npc(failures)
	_check_trade_refuels_after_unload(failures)
	_check_economy_tick_refuels(failures)
	_check_fuel_reserve(failures)
	_check_trade_keeps_tank(failures)
	_check_fuel_is_a_need_when_short(failures)
	_check_stock_drives_trade_goods(failures)
	_check_fuel_aware_destination(failures)
	_check_away_time_and_home_rest(failures)
	_check_home_repair(failures)
	_check_retire_stranded(failures)
	_check_warp_rechecks_fuel(failures)
	_check_skirmish_cancels_warp(failures)
	await _check_refuel_on_arrival(tree, campaign_state, failures)
	await _check_scene_ticks_npc_jumps(tree, campaign_state, failures)
	await _check_retire_frees_icon(tree, campaign_state, failures)
	tree.paused = false
	campaign_state.reset()
	return failures

static func _fresh_state() -> CampaignStateScript:
	var state := CampaignStateScript.new()
	state.rng.seed = 1
	state.new_game()
	# Spawns stagger the first decision; these checks want every fleet to decide on the next tick.
	for fleet in state.enemy_fleets:
		fleet.jump_cooldown = 0.0
	return state

static func _first_fleet(state, station_id: String, role: CampaignFleet.Role) -> CampaignFleet:
	var fleets: Array[CampaignFleet] = state.station_fleets(state.galaxy.station(station_id), role)
	return fleets[0] if not fleets.is_empty() else null

static func _tick(state, seconds: float) -> void:
	for _i in roundi(seconds / TICK):
		state.tick_npc_jumps(TICK)
		state.tick_warps(TICK)

# Earlier ticks may have started a warp or set a cooldown; make the next tick decide afresh.
static func _reset_jump_state(fleet: CampaignFleet) -> void:
	fleet.cancel_warp()
	fleet.jump_path.clear()
	fleet.jump_cooldown = 0.0

static func _target_fuel(fleet: CampaignFleet) -> float:
	return CampaignStateScript.NPC_FUEL_TARGET_JUMPS * JumpRules.jump_cost(fleet)

static func _check_single_jump(failures: Array[String]) -> void:
	var state := _fresh_state()
	var trader := _first_fleet(state, "wexford_outpost", TRADER)
	trader.dest_station_id = "cinder_market"
	var fuel_before := trader.fuel_amount()
	_tick(state, 5.0)
	if trader.system_id != "cinder":
		failures.append("single jump: expected the Wexford trader in cinder after 5 s, in %s" % trader.system_id)
	if not is_equal_approx(trader.fuel_amount(), fuel_before - JumpRules.jump_cost(trader)):
		failures.append("single jump: expected fuel %.2f after one jump, got %.2f" % [fuel_before - JumpRules.jump_cost(trader), trader.fuel_amount()])
	if not trader.jump_path.is_empty():
		failures.append("single jump: expected the path used up on arrival, got %s" % [trader.jump_path])
	state.free()

static func _check_multi_jump(failures: Array[String]) -> void:
	var state := _fresh_state()
	var trader := _first_fleet(state, "wexford_outpost", TRADER)
	trader.dest_station_id = "freeport"
	var limit := 2.0 * (JumpRules.WARP_DURATION + NpcJumpPlanner.HOP_DELAY) + 1.0
	var elapsed := 0.0
	var decided := false
	while elapsed < limit and trader.system_id != "freeport":
		state.tick_npc_jumps(TICK)
		state.tick_warps(TICK)
		elapsed += TICK
		if not decided:
			decided = true
			if trader.jump_path.size() != 2:
				failures.append("multi jump: expected a 2-hop path to freeport on the first decision, got %s" % [trader.jump_path])
	if trader.system_id != "freeport":
		failures.append("multi jump: expected the trader in freeport within %.1f s, in %s" % [limit, trader.system_id])
	if not trader.jump_path.is_empty():
		failures.append("multi jump: expected the path used up, got %s" % [trader.jump_path])
	state.free()

# planner_respects_round_trip_fuel, end to end: never leave on a jump with no way back; head home from away.
static func _check_round_trip_in_tick(failures: Array[String]) -> void:
	var state := _fresh_state()
	var pirate := _first_fleet(state, "marrow_hideout", COMBAT)
	var cost := JumpRules.jump_cost(pirate)
	pirate.cargo[FUEL] = cost
	state.tick_npc_jumps(TICK)
	if pirate.is_warping() or not pirate.jump_path.is_empty():
		failures.append("round trip: expected a pirate with 1 jump of fuel to stay home, warping to '%s' path %s" % [pirate.warp_target, pirate.jump_path])
	pirate.cargo[FUEL] = 2.0 * cost
	pirate.jump_cooldown = 0.0
	state.tick_npc_jumps(TICK)
	if not pirate.is_warping() or not ["greenreach", "bastion"].has(pirate.warp_target):
		failures.append("round trip: expected a pirate with 2 jumps of fuel to raid a trader system, warping to '%s'" % pirate.warp_target)
	if pirate.jump_cooldown < NpcJumpPlanner.DECISION_INTERVAL:
		failures.append("round trip: expected the cooldown reset to at least %.0f, got %.2f" % [NpcJumpPlanner.DECISION_INTERVAL, pirate.jump_cooldown])

	var away := _first_fleet(state, "southdeep_den", COMBAT)
	_reset_jump_state(away)
	away.system_id = "thornfield"
	for fleet in state.enemy_fleets:
		if fleet.system_id == "thornfield" and fleet.role == TRADER:
			fleet.system_id = "bastion"
	away.cargo[FUEL] = JumpRules.jump_cost(away)
	state.tick_npc_jumps(TICK)
	if away.warp_target != "southdeep":
		failures.append("round trip: expected a raider with no prey and 1 jump of fuel to head home to southdeep, warping to '%s'" % away.warp_target)

	# A trader away whose destination is home goes home rather than idling.
	var trader := _first_fleet(state, "wexford_outpost", TRADER)
	_reset_jump_state(trader)
	trader.system_id = "cinder"
	trader.dest_station_id = "wexford_outpost"
	trader.cargo[FUEL] = JumpRules.jump_cost(trader)
	state.tick_npc_jumps(TICK)
	if trader.warp_target != "wexford":
		failures.append("round trip: expected an away trader heading home to warp to wexford, warping to '%s'" % trader.warp_target)
	state.free()

static func _check_refuel_npc(failures: Array[String]) -> void:
	var state := _fresh_state()
	var station: StationData = state.galaxy.station("wexford_outpost")
	var trader := _first_fleet(state, "wexford_outpost", TRADER)
	var target := _target_fuel(trader)
	trader.cargo[FUEL] = 0.0
	station.economy.stock[FUEL] = 2.0
	state.refuel_npc(trader, station)
	if not is_equal_approx(trader.fuel_amount(), 2.0) or not is_zero_approx(station.economy.stock[FUEL]):
		failures.append("refuel: expected a short stock to give all it has (2.0), fleet %.2f stock %.2f" % [trader.fuel_amount(), station.economy.stock[FUEL]])
	state.refuel_npc(trader, station)
	if not is_equal_approx(trader.fuel_amount(), 2.0):
		failures.append("refuel: expected an empty stock to leave the fleet waiting at 2.0, got %.2f" % trader.fuel_amount())
	station.economy.stock[FUEL] = 100.0
	state.refuel_npc(trader, station)
	if not is_equal_approx(trader.fuel_amount(), target):
		failures.append("refuel: expected a top-up to %.2f, got %.2f" % [target, trader.fuel_amount()])
	if not is_equal_approx(station.economy.stock[FUEL], 100.0 - (target - 2.0)):
		failures.append("refuel: expected the stock to drop by the top-up, got %.2f" % station.economy.stock[FUEL])
	state.refuel_npc(trader, station)
	if not is_equal_approx(trader.fuel_amount(), target):
		failures.append("refuel: expected a full fleet left at %.2f, got %.2f" % [target, trader.fuel_amount()])
	state.free()

# run_npc_trade_at unloads all cargo, fuel included; the refuel must come after, so the trader leaves fuelled.
static func _check_trade_refuels_after_unload(failures: Array[String]) -> void:
	var state := _fresh_state()
	var trader := _first_fleet(state, "wexford_outpost", TRADER)
	var market: StationData = state.galaxy.station("cinder_market")
	trader.cargo[FUEL] = 1.0
	var stock_before: float = market.economy.stock.get(FUEL, 0.0)
	state.run_npc_trade_at(trader, market)
	if trader.fuel_amount() < _target_fuel(trader) - CrewRules.ROUND_EPSILON:
		failures.append("trade refuel: expected at least %.2f fuel after trading, got %.2f" % [_target_fuel(trader), trader.fuel_amount()])
	var stock_after: float = market.economy.stock.get(FUEL, 0.0)
	if not is_equal_approx(stock_before + 1.0 - stock_after, trader.fuel_amount()):
		failures.append("trade refuel: expected the station's fuel to move to the trader, stock %.2f -> %.2f, fleet %.2f" % [stock_before, stock_after, trader.fuel_amount()])
	state.free()

# C1(b): every NPC tops up at any station in its system it may use; pirates only at pirate stations.
static func _check_economy_tick_refuels(failures: Array[String]) -> void:
	var state := _fresh_state()
	state.galaxy.station("wexford_outpost").economy.stock[FUEL] = 500.0
	var patrol := _first_fleet(state, "wexford_outpost", COMBAT)
	# Traders too: one that docked while home's FUEL was short would otherwise wait forever.
	var hauler := _first_fleet(state, "wexford_outpost", TRADER)
	var roamer := _first_fleet(state, "cinder_works", COMBAT)
	roamer.system_id = "wexford"
	var enemy := _first_fleet(state, "greenreach", COMBAT)
	enemy.system_id = "kestrel"
	var pirate_at_post := _first_fleet(state, "marrow_hideout", COMBAT)
	pirate_at_post.system_id = "wexford"
	var pirate_at_den := _first_fleet(state, "southdeep_den", COMBAT)
	pirate_at_den.system_id = "redtide"
	for fleet in [patrol, hauler, roamer, enemy, pirate_at_post, pirate_at_den]:
		fleet.cargo[FUEL] = 0.0
	state.tick_economy(CampaignStateScript.ECONOMY_TICK_INTERVAL)
	if not is_equal_approx(patrol.fuel_amount(), _target_fuel(patrol)):
		failures.append("economy refuel: expected a patrol at home topped up to %.2f, got %.2f" % [_target_fuel(patrol), patrol.fuel_amount()])
	if not is_equal_approx(hauler.fuel_amount(), _target_fuel(hauler)):
		failures.append("economy refuel: expected a trader at home topped up to %.2f, got %.2f" % [_target_fuel(hauler), hauler.fuel_amount()])
	if not is_equal_approx(roamer.fuel_amount(), _target_fuel(roamer)):
		failures.append("economy refuel: expected a fleet away topped up at a friendly station to %.2f, got %.2f" % [_target_fuel(roamer), roamer.fuel_amount()])
	if not is_zero_approx(enemy.fuel_amount()):
		failures.append("economy refuel: expected no fuel at a hostile power's station, got %.2f" % enemy.fuel_amount())
	if not is_zero_approx(pirate_at_post.fuel_amount()):
		failures.append("economy refuel: expected a pirate refused at a non-pirate station, got %.2f" % pirate_at_post.fuel_amount())
	if not is_equal_approx(pirate_at_den.fuel_amount(), _target_fuel(pirate_at_den)):
		failures.append("economy refuel: expected a pirate away topped up at another pirate den to %.2f, got %.2f" % [_target_fuel(pirate_at_den), pirate_at_den.fuel_amount()])
	state.free()

# C1(c): a station that burns FUEL keeps STATION_FUEL_RESERVE_TICKS of it back from refuels.
static func _check_fuel_reserve(failures: Array[String]) -> void:
	var state := _fresh_state()
	var picket: StationData = state.galaxy.station("kestrel_picket")
	var reserve := 2.0 * CampaignStateScript.STATION_FUEL_RESERVE_TICKS
	var patrol := _first_fleet(state, "kestrel_picket", COMBAT)
	patrol.cargo[FUEL] = 0.0
	picket.economy.stock[FUEL] = reserve + 2.0
	state.refuel_npc(patrol, picket)
	if not is_equal_approx(patrol.fuel_amount(), 2.0) or not is_equal_approx(picket.economy.stock[FUEL], reserve):
		failures.append("reserve: expected only the 2.0 above kestrel_picket's %.0f reserve taken, fleet %.2f stock %.2f" % [reserve, patrol.fuel_amount(), picket.economy.stock[FUEL]])
	picket.economy.tick()
	if picket.economy.deficit_streaks.get(0, 0) != 0:
		failures.append("reserve: expected the industrial slot fed from the reserve on the next tick")
	state.free()

# A stop holding no spare FUEL must not keep the trader's own tank, or it could never get home.
static func _check_trade_keeps_tank(failures: Array[String]) -> void:
	var state := _fresh_state()
	var trader := _first_fleet(state, "bastion", TRADER)
	var picket: StationData = state.galaxy.station("kestrel_picket")
	var tank := 2.0 * JumpRules.jump_cost(trader)
	trader.cargo = {FUEL: tank}
	picket.economy.stock[FUEL] = 0.0
	state.run_npc_trade_at(trader, picket)
	if not is_equal_approx(trader.fuel_amount(), tank):
		failures.append("tank: expected the trader to keep its %.2f tank at a dry stop, got %.2f" % [tank, trader.fuel_amount()])
	if not is_zero_approx(picket.economy.stock[FUEL]):
		failures.append("tank: expected no FUEL unloaded from the tank, stock %.2f" % picket.economy.stock[FUEL])
	# Hauled FUEL past a full tank still unloads.
	var full := _target_fuel(trader)
	trader.cargo = {FUEL: full + 5.0}
	state.run_npc_trade_at(trader, picket)
	if not is_equal_approx(picket.economy.stock[FUEL], 5.0) or not is_equal_approx(trader.fuel_amount(), full):
		failures.append("tank: expected 5.0 hauled FUEL unloaded past a %.2f tank, stock %.2f fleet %.2f" % [full, picket.economy.stock[FUEL], trader.fuel_amount()])
	state.free()

# A home that makes no FUEL hauls it in while short, since its fleets refuel from its stock.
static func _check_fuel_is_a_need_when_short(failures: Array[String]) -> void:
	var state := _fresh_state()
	var greenreach: StationData = state.galaxy.station("greenreach")
	greenreach.economy.stock[FUEL] = Commodity.TARGET_STOCK[FUEL]
	if state._home_trade_goods(greenreach, false).has(FUEL):
		failures.append("fuel need: expected no FUEL need at TARGET_STOCK")
	greenreach.economy.stock[FUEL] = 20.0
	if not state._home_trade_goods(greenreach, false).has(FUEL):
		failures.append("fuel need: expected a short, non-refining home to need FUEL")
	var wexford: StationData = state.galaxy.station("wexford_outpost")
	wexford.economy.stock[FUEL] = 0.0
	if state._home_trade_goods(wexford, false).has(FUEL):
		failures.append("fuel need: expected a refining home never to haul FUEL in")
	state.free()

# Stock, not slot type, decides the rest: short goods are wanted, goods above TARGET_STOCK are spare,
# a maker never wants its own product, a burner never ships out its input; NPCs skip player stations.
static func _check_stock_drives_trade_goods(failures: Array[String]) -> void:
	var state := _fresh_state()
	var market: StationData = state.galaxy.station("cinder_market")
	var ore: int = Commodity.Type.ORE
	var luxury: int = Commodity.Type.LUXURY_GOODS
	market.economy.stock[luxury] = 10.0
	if not state._home_trade_goods(market, false).has(luxury):
		failures.append("stock goods: expected a short good to be wanted by a station that doesn't make it")
	market.economy.stock[luxury] = Commodity.TARGET_STOCK[luxury] + 5.0
	if not state._home_trade_goods(market, true).has(luxury):
		failures.append("stock goods: expected a good above TARGET_STOCK to be spare")
	var spire: StationData = state.galaxy.station("aurum_spire")
	spire.economy.stock[Commodity.Type.FUEL] = 0.0
	spire.economy.stock[ore] = Commodity.TARGET_STOCK[ore] + 50.0
	if state._home_trade_goods(spire, false).has(Commodity.Type.FUEL):
		failures.append("stock goods: expected a refinery never to want FUEL")
	if state._home_trade_goods(spire, true).has(ore):
		failures.append("stock goods: expected an Ore burner never to export Ore")
	var home_base: StationData = state.galaxy.station("home_base")
	if state.can_refuel_at(_first_fleet(state, "aurum_bazaar", TRADER), home_base):
		failures.append("stock goods: expected NPCs never to refuel at a player-owned station")
	state.free()

# C1(a): a trader only picks a partner it can fuel there and back, and re-picks at home when the
# stored one is out of reach.
static func _check_fuel_aware_destination(failures: Array[String]) -> void:
	var state := _fresh_state()
	var trader := _first_fleet(state, "wexford_outpost", TRADER)
	var cost := JumpRules.jump_cost(trader)
	trader.dest_station_id = "wexford_outpost"
	trader.cargo[FUEL] = cost
	if state.next_trade_destination(trader) != "":
		failures.append("fuel-aware: expected no partner with 1 jump of fuel (wexford has no second station), got '%s'" % state.next_trade_destination(trader))
	trader.cargo[FUEL] = 2.0 * cost
	var picked: StationData = state.galaxy.station(state.next_trade_destination(trader))
	if picked == null or state.galaxy.jump_distance("wexford", picked.system_id) != 1:
		failures.append("fuel-aware: expected a 1-jump partner with 2 jumps of fuel, got '%s'" % (picked.id if picked != null else ""))

	_reset_jump_state(trader)
	trader.dest_station_id = "freeport"
	var changed := [0]
	state.trade_destination_changed.connect(func(fleet: CampaignFleet): if fleet == trader: changed[0] += 1)
	state.tick_npc_jumps(TICK)
	var dest: StationData = state.galaxy.station(trader.dest_station_id)
	if trader.dest_station_id == "freeport" or dest == null or not NpcJumpPlanner.fuel_allows(trader, state.galaxy, state.galaxy.path("wexford", dest.system_id)):
		failures.append("fuel-aware: expected an unaffordable stored destination re-picked at home, got '%s'" % trader.dest_station_id)
	elif dest.system_id != "wexford" and trader.warp_target != dest.system_id:
		failures.append("fuel-aware: expected the trader to leave for the re-picked %s, warping to '%s'" % [dest.system_id, trader.warp_target])
	if changed[0] != 1:
		failures.append("fuel-aware: expected one trade_destination_changed, got %d" % changed[0])
	state.free()

# I2: away_time counts outside home and resets there; a combat fleet back home rests HOME_REST.
static func _check_away_time_and_home_rest(failures: Array[String]) -> void:
	var state := _fresh_state()
	var pirate := _first_fleet(state, "marrow_hideout", COMBAT)
	pirate.system_id = "bastion"
	pirate.jump_cooldown = 1000.0
	for _i in 3:
		state.tick_npc_jumps(1.0)
	if not is_equal_approx(pirate.away_time, 3.0):
		failures.append("away time: expected 3.0 s counted away from home, got %.2f" % pirate.away_time)
	pirate.away_time = NpcJumpPlanner.RAID_DWELL
	pirate.jump_cooldown = 0.0
	_tick(state, JumpRules.WARP_DURATION + TICK * 2.0)
	if pirate.system_id != "marrow":
		failures.append("home rest: expected a raider past RAID_DWELL back in marrow, in %s" % pirate.system_id)
	elif not is_zero_approx(pirate.away_time):
		failures.append("away time: expected a reset at home, got %.2f" % pirate.away_time)
	elif pirate.jump_cooldown < NpcJumpPlanner.HOME_REST - 1.0:
		failures.append("home rest: expected the cooldown near HOME_REST %.0f after getting home, got %.2f" % [NpcJumpPlanner.HOME_REST, pirate.jump_cooldown])
	state.free()

# I3: NPCs repair free at their home station on the economy tick, and only there.
static func _check_home_repair(failures: Array[String]) -> void:
	var state := _fresh_state()
	var at_home := _first_fleet(state, "marrow_hideout", COMBAT)
	var away := _first_fleet(state, "southdeep_den", COMBAT)
	away.system_id = "marrow"
	at_home.apply_fractional_damage(0.6)
	away.apply_fractional_damage(0.6)
	var away_strength := away.total_strength()
	state.tick_economy(CampaignStateScript.ECONOMY_TICK_INTERVAL)
	if not is_equal_approx(at_home.total_strength(), at_home.max_strength()):
		failures.append("repair: expected a damaged fleet at home repaired to %.1f, got %.1f" % [at_home.max_strength(), at_home.total_strength()])
	if not is_equal_approx(away.total_strength(), away_strength):
		failures.append("repair: expected a fleet away from home left damaged at %.1f, got %.1f" % [away_strength, away.total_strength()])
	state.free()

# I3: a fleet that can't fuel the way home, in a system with no station it may refuel at, retires.
static func _check_retire_stranded(failures: Array[String]) -> void:
	var state := _fresh_state()
	var retired: Array[CampaignFleet] = []
	state.fleet_retired.connect(func(fleet: CampaignFleet): retired.append(fleet))
	var lost := _first_fleet(state, "marrow_hideout", COMBAT)
	lost.system_id = "wexford"
	var waiting := _first_fleet(state, "southdeep_den", COMBAT)
	waiting.system_id = "redtide"
	var behind_lines := _first_fleet(state, "greenreach", COMBAT)
	behind_lines.system_id = "kestrel"
	for fleet in [lost, waiting, behind_lines]:
		_reset_jump_state(fleet)
		fleet.cargo[FUEL] = 0.0
	var den: StationData = state.galaxy.station("marrow_hideout")
	var den_fleets_before := state.station_fleets(den, COMBAT).size()
	state.tick_npc_jumps(TICK)
	if state.enemy_fleets.has(lost) or not retired.has(lost):
		failures.append("retire: expected a dry pirate in a system with no pirate station retired")
	if state.enemy_fleets.has(behind_lines) or not retired.has(behind_lines):
		failures.append("retire: expected a dry patrol among only hostile stations retired")
	if not state.enemy_fleets.has(waiting) or retired.has(waiting):
		failures.append("retire: expected a dry pirate at another pirate den kept, waiting for fuel")
	if state.station_fleets(den, COMBAT).size() != den_fleets_before - 1:
		failures.append("retire: expected the den one fleet under quota, so respawn replaces it")
	state.free()

# M4: fuel lost (or cost risen) during the countdown cancels the jump: no move, no fuel spent.
static func _check_warp_rechecks_fuel(failures: Array[String]) -> void:
	var state := _fresh_state()
	var trader := _first_fleet(state, "wexford_outpost", TRADER)
	trader.dest_station_id = "cinder_market"
	state.tick_npc_jumps(TICK)
	if not trader.is_warping():
		failures.append("warp recheck: setup expected the trader warping")
	var short := 0.5 * JumpRules.jump_cost(trader)
	trader.cargo[FUEL] = short
	state.tick_warps(JumpRules.WARP_DURATION + TICK)
	if trader.system_id != "wexford" or trader.is_warping() or not trader.jump_path.is_empty():
		failures.append("warp recheck: expected the NPC warp cancelled in wexford, in %s warping %s path %s" % [trader.system_id, trader.is_warping(), trader.jump_path])
	if not is_equal_approx(trader.fuel_amount(), short):
		failures.append("warp recheck: expected no NPC fuel spent, got %.2f" % trader.fuel_amount())

	var player: CampaignFleet = state.player_fleet
	if not state.begin_player_warp("wexford", false):
		failures.append("warp recheck: setup expected the player warp to start")
	var player_short := 0.5 * JumpRules.jump_cost(player)
	player.cargo[FUEL] = player_short
	state.tick_warps(JumpRules.WARP_DURATION + TICK)
	if player.system_id != "haven" or player.is_warping() or not is_equal_approx(player.fuel_amount(), player_short):
		failures.append("warp recheck: expected the player's warp cancelled in haven with %.2f fuel, in %s warping %s fuel %.2f" % [player_short, player.system_id, player.is_warping(), player.fuel_amount()])
	state.free()

static func _check_skirmish_cancels_warp(failures: Array[String]) -> void:
	var state := _fresh_state()
	var trader := _first_fleet(state, "wexford_outpost", TRADER)
	trader.dest_station_id = "cinder_market"
	state.tick_npc_jumps(TICK)
	if not trader.is_warping():
		failures.append("skirmish: setup expected the trader warping")
	var pirate := _first_fleet(state, "marrow_hideout", COMBAT)
	var icon_a := CampaignFleetIcon.new()
	icon_a.fleet = trader
	var icon_b := CampaignFleetIcon.new()
	icon_b.fleet = pirate
	state.start_skirmish(icon_a, icon_b)
	_tick(state, JumpRules.WARP_DURATION + NpcJumpPlanner.HOP_DELAY)
	if trader.is_warping() or trader.system_id != "wexford":
		failures.append("skirmish: expected the trader's warp lost and it still in wexford, in %s warping %s" % [trader.system_id, trader.is_warping()])
	icon_a.free()
	icon_b.free()
	state.free()

static func _open_scene(tree: SceneTree, campaign_state) -> Node2D:
	campaign_state.reset()
	var scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(scene)
	await tree.process_frame
	await tree.process_frame
	tree.paused = false
	return scene

static func _close_scene(tree: SceneTree, campaign_state, scene: Node2D) -> void:
	tree.paused = false
	scene.queue_free()
	await tree.process_frame
	campaign_state.reset()

static func _icon_for(scene: Node2D, fleet: CampaignFleet) -> CampaignFleetIcon:
	for icon in scene.enemy_icons:
		if is_instance_valid(icon) and icon.fleet == fleet:
			return icon
	return null

# Arriving through the icon's signal runs the trade, and the trader leaves with fuel from the station.
static func _check_refuel_on_arrival(tree: SceneTree, campaign_state, failures: Array[String]) -> void:
	var scene: Node2D = await _open_scene(tree, campaign_state)
	var trader := _first_fleet(campaign_state, "haven_exchange", TRADER)
	var icon := _icon_for(scene, trader)
	var station: StationData = campaign_state.galaxy.station("haven_exchange")
	if icon == null:
		failures.append("arrival refuel: expected an icon for the haven_exchange trader")
	else:
		trader.cargo = {FUEL: 1.0}
		var stock_before: float = station.economy.stock.get(FUEL, 0.0)
		icon.trader_arrived_at.emit("haven_exchange")
		var stock_after: float = station.economy.stock.get(FUEL, 0.0)
		if trader.fuel_amount() < _target_fuel(trader) - CrewRules.ROUND_EPSILON:
			failures.append("arrival refuel: expected at least %.2f fuel, got %.2f" % [_target_fuel(trader), trader.fuel_amount()])
		if not is_equal_approx(stock_before + 1.0 - stock_after, trader.fuel_amount()):
			failures.append("arrival refuel: expected the station's FUEL to drop by what the trader took, stock %.2f -> %.2f, fleet %.2f" % [stock_before, stock_after, trader.fuel_amount()])
	await _close_scene(tree, campaign_state, scene)

# The scene drives tick_npc_jumps, and an NPC that jumps lands in its new system's layer.
static func _check_scene_ticks_npc_jumps(tree: SceneTree, campaign_state, failures: Array[String]) -> void:
	var scene: Node2D = await _open_scene(tree, campaign_state)
	var trader := _first_fleet(campaign_state, "wexford_outpost", TRADER)
	var icon := _icon_for(scene, trader)
	_reset_jump_state(trader)
	trader.dest_station_id = "cinder_market"
	for _i in 50:
		scene._physics_process(TICK)
		if trader.system_id == "cinder":
			break
	if trader.system_id != "cinder":
		failures.append("scene: expected the scene's physics tick to jump the trader to cinder, in %s" % trader.system_id)
	elif icon == null or icon.get_parent() != scene.layer_for("cinder"):
		failures.append("scene: expected the trader's icon moved to the cinder layer")
	elif not icon.has_destination or icon.dest_position != campaign_state.galaxy.station("cinder_market").position:
		failures.append("scene: expected the trader aimed at cinder_market on arrival")
	await _close_scene(tree, campaign_state, scene)

# I3, scene side: a retired fleet's icon is freed and the player stops steering at it.
static func _check_retire_frees_icon(tree: SceneTree, campaign_state, failures: Array[String]) -> void:
	var scene: Node2D = await _open_scene(tree, campaign_state)
	var pirate := _first_fleet(campaign_state, "marrow_hideout", COMBAT)
	var icon := _icon_for(scene, pirate)
	if icon == null:
		failures.append("retire icon: expected an icon for the marrow_hideout pirate")
	else:
		scene._travel_target = icon
		campaign_state.retire_npc(pirate)
		if campaign_state.enemy_fleets.has(pirate):
			failures.append("retire icon: expected the fleet off the roster")
		if not icon.is_queued_for_deletion() or scene.enemy_icons.has(icon):
			failures.append("retire icon: expected the icon queued for deletion and off enemy_icons")
		if scene._travel_target != null:
			failures.append("retire icon: expected the player's travel target cleared")
	await _close_scene(tree, campaign_state, scene)
