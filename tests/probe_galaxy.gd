extends SceneTree

# Manual long-run probe of the AI galaxy (not in the suite): runs the real campaign scene on
# new_game() and reports jump rate, stranded fleets, fleets dry at home, station slot loss,
# NPC-vs-NPC skirmishes and the NPC ship count. Run non-interactively with:
#   Start-Process -FilePath $godot -ArgumentList '--headless','--path','.','--script','res://tests/probe_galaxy.gd','--','--seed=7','--dur=3600' -RedirectStandardOutput probe_output.txt -Wait -NoNewWindow
# Options (after --): --dur=<seconds, default 3600>, --seed=<int, default 7>, --free-fuel (isolates
# supply: tops every NPC fleet up each step), --verbose (prints a line per sample and per-station detail).
# Baseline before the fleet-scale work: ~1.33 jumps/s, 0 stranded, 0-4 dry at home, no slot loss.

const SAMPLE_EVERY := 120.0
const STEP := 1.0 / 60.0
const STEPS_PER_FRAME := 300

var _duration: float = 3600.0
var _seed: int = 7
var _skirmishes: int = 0

func _initialize() -> void:
	_run()

func _run() -> void:
	# Autoloads register after the first frame.
	await process_frame
	var args := OS.get_cmdline_user_args()
	var verbose := args.has("--verbose")
	var free_fuel := args.has("--free-fuel")
	for arg in args:
		if arg.begins_with("--dur="):
			_duration = float(arg.substr(6))
		elif arg.begins_with("--seed="):
			_seed = int(arg.substr(7))
	var campaign_state = root.get_node("/root/CampaignState")
	campaign_state.reset()
	campaign_state.rng.seed = _seed
	campaign_state.new_game()
	var jumps := [0]
	campaign_state.fleet_jumped.connect(func(fleet, _from): if fleet != campaign_state.player_fleet: jumps[0] += 1)
	campaign_state.skirmish_resolved.connect(func(_winner, _loser): _skirmishes += 1)
	var scene: Node2D = load("res://scenes/campaign/campaign_scene.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	paused = false
	var start_ships := _ship_count(campaign_state)
	print("probe_galaxy: seed=%d dur=%.0f fleets=%d ships=%d" % [_seed, _duration, campaign_state.enemy_fleets.size(), start_ships])
	var icons := _live_icons(scene)
	var first_loss := {}
	var peak_stranded := 0
	var peak_dry := 0
	var steps := int(_duration / STEP)
	var next_sample := 0.0
	var elapsed := 0.0
	var wall_start := Time.get_ticks_msec()
	for step in steps:
		if step > 0 and step % STEPS_PER_FRAME == 0:
			await physics_frame
			paused = false
			icons = _live_icons(scene)
		if free_fuel:
			_top_up_fuel(campaign_state)
		scene._physics_process(STEP)
		if step % 300 == 0:
			for station in campaign_state.galaxy.stations:
				if station.economy.slots.size() < 2 and not first_loss.has(station.id):
					first_loss[station.id] = int(elapsed)
		for icon in icons:
			icon._physics_process(STEP)
		elapsed += STEP
		if elapsed >= next_sample:
			var counts := _fleet_counts(campaign_state)
			peak_stranded = maxi(peak_stranded, counts.stranded)
			peak_dry = maxi(peak_dry, counts.dry_home)
			if verbose:
				print("[t=%5.0f] fleets=%d ships=%d jumps=%d skirmishes=%d away=%d stranded=%d dry_at_home=%d" % [elapsed, campaign_state.enemy_fleets.size(), _ship_count(campaign_state), jumps[0], _skirmishes, counts.away, counts.stranded, counts.dry_home])
			next_sample += SAMPLE_EVERY
	var counts := _fleet_counts(campaign_state)
	var hours := elapsed / 3600.0
	print("RESULT seed=%d t=%.0f jumps/s=%.2f stranded=%d (peak %d) dry_at_home=%d (peak %d) slot_loss=%s skirmishes=%d (%.1f/h) ships=%d -> %d (%.0f%%) fleets=%d" % [_seed, elapsed, jumps[0] / elapsed, counts.stranded, peak_stranded, counts.dry_home, peak_dry, str(first_loss), _skirmishes, _skirmishes / hours, start_ships, _ship_count(campaign_state), 100.0 * _ship_count(campaign_state) / maxf(1.0, start_ships), campaign_state.enemy_fleets.size()])
	if verbose:
		print("wall time %.1f s" % ((Time.get_ticks_msec() - wall_start) / 1000.0))
		_print_station_detail(campaign_state)
	quit()

# Fleets away from home that cannot afford the way back, and fleets at home that cannot afford 2 jumps.
func _fleet_counts(campaign_state) -> Dictionary:
	var away := 0
	var dry_home := 0
	var stranded := 0
	for fleet in campaign_state.enemy_fleets:
		var home = campaign_state.galaxy.station(fleet.home_station_id)
		if home == null:
			continue
		var cost: float = JumpRules.jump_cost(fleet)
		if fleet.system_id != home.system_id:
			away += 1
			var distance: int = campaign_state.galaxy.jump_distance(fleet.system_id, home.system_id)
			if fleet.fuel_amount() < cost * distance - 0.001:
				stranded += 1
		elif fleet.fuel_amount() < cost * 2 - 0.001:
			dry_home += 1
	return {"away": away, "dry_home": dry_home, "stranded": stranded}

func _live_icons(scene) -> Array:
	var icons: Array = [scene.player_icon]
	for icon in scene.enemy_icons:
		if icon != null and is_instance_valid(icon) and not icon.is_queued_for_deletion():
			icons.append(icon)
	return icons

func _print_station_detail(campaign_state) -> void:
	for station in campaign_state.galaxy.stations:
		var economy: BaseEconomy = station.economy
		var parts: Array = []
		for commodity in Commodity.Type.values():
			parts.append("%s=%.0f" % [Commodity.Type.keys()[commodity], economy.stock.get(commodity, 0.0)])
		var home_fleets := 0
		for fleet in campaign_state.enemy_fleets:
			if fleet.home_station_id == station.id:
				home_fleets += 1
		print("  %s [%s] slots=%d pop=%.0f fleets=%d %s" % [station.id, station.system_id, economy.slots.size(), economy.population, home_fleets, " ".join(parts)])

func _ship_count(campaign_state) -> int:
	var total := 0
	for fleet in campaign_state.enemy_fleets:
		total += fleet.ship_compositions.size()
	return total

func _top_up_fuel(campaign_state) -> void:
	for fleet in campaign_state.enemy_fleets:
		var wanted: float = campaign_state.NPC_FUEL_TARGET_JUMPS * JumpRules.jump_cost(fleet)
		if fleet.fuel_amount() < wanted:
			fleet.cargo[Commodity.Type.FUEL] = wanted
