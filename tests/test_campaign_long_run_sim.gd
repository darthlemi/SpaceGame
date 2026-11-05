extends RefCounted

# Runs the real campaign scene on a new_game() galaxy forward 20 simulated minutes via
# manual physics-stepping (not real time): the scene's own tick (skirmishes, economy, warps,
# NPC jumps) plus every icon's movement. A real physics frame is awaited every few simulated
# seconds so Area2D contacts (skirmishes) register and freed icons leave the roster; more often
# costs suite time (each await is a real ~16 ms frame).
#
# Intent: the galaxy stays alive over a long run -- fleets keep existing and moving between
# systems at a rate that doesn't decay, traders never sit at home on a trip they can't make, and
# station economies keep their slots.
#
# The pirate-engagement assertion is EXPECTED TO FAIL today: pirates only ever
# target the player, never other fleets. This is a known, documented gap (see
# docs/superpowers/specs/2026-11-01-campaign-long-run-sim-design.md), not a bug
# in this test. Do not "fix" this test to make it pass -- the real fix is a
# separate future piece of work on pirate behavior. Only fleets the pirate is hostile to
# (CampaignState.are_hostile) count as opportunities: other pirates and neutral traders are
# never its prey.
#
# Distance-from-spawn output is report-only (informational, no "right"
# answer). Map bounds ARE asserted: every icon's position must stay within
# JumpRules.SYSTEM_MIN/SYSTEM_MAX (in its layer) at every sampled step -- unlike the
# pirate-engagement assertion above, this one is expected to pass; a failure
# here is a real bug in the clamp, not a documented gap. Reading `_move_target`
# (underscore-prefixed) is a deliberate one-file exception to verify internal
# pirate-targeting behavior, not a pattern to copy elsewhere.

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")

# One 20 min run: a shorter one would only repeat its first part.
const SIM_DURATIONS_SECONDS: Array[float] = [1200.0]
const STEP_DELTA := 1.0 / 60.0
const STEPS_PER_REAL_FRAME := 300
const ENGAGEMENT_EPSILON := 1.0
const RNG_SEED := 7
# Respawn refills quotas after FLEET_RESPAWN_DELAY, so the roster should never fall far.
const MIN_FLEET_FRACTION := 0.5
# The first third burns down every station's seeded stock, so some fall-off is expected. Measured at
# 0.50-0.59 after the final-review fixes; the frozen galaxy they fixed measured 0.35.
const MIN_JUMP_RATE_KEPT := 0.4
# A trader with a destination elsewhere decides within DECISION_INTERVAL + DECISION_JITTER.
const MAX_TRADER_IDLE_AT_HOME := 120.0

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")

	for duration in SIM_DURATIONS_SECONDS:
		campaign_state.reset()
		campaign_state.rng.seed = RNG_SEED
		campaign_state.new_game()
		var start_fleets: int = campaign_state.enemy_fleets.size()
		var seeded_slots := {}
		for station in campaign_state.galaxy.stations:
			seeded_slots[station.id] = station.economy.slots.size()
		# NPC jumps per third of the run; sim_time is shared with the step loop.
		var jumps_by_third := [0, 0, 0]
		var sim_time := [0.0]
		var on_jumped := func(fleet: CampaignFleet, _from: String):
			if fleet != campaign_state.player_fleet:
				jumps_by_third[mini(2, int(sim_time[0] / (duration / 3.0)))] += 1
		campaign_state.fleet_jumped.connect(on_jumped)
		var idle_since := {}
		var max_idle := [0.0, ""]

		var scene: Node2D = CampaignSceneScene.instantiate()
		tree.root.add_child(scene)
		await tree.process_frame
		tree.paused = false

		var icons := _live_icons(scene)
		var spawn_positions: Dictionary = {}
		var max_distance: Dictionary = {}
		var out_of_bounds: Dictionary = {}
		for icon in icons:
			spawn_positions[icon] = icon.position
			max_distance[icon] = 0.0

		# Untyped, like the rosters below: these can come to hold freed icons.
		var pirate_icon = null
		for icon in scene.enemy_icons:
			if icon.behavior_type == CampaignFleetIcon.BehaviorType.PIRATE:
				pirate_icon = icon
				break

		var found_pirate: bool = pirate_icon != null
		var others: Array = []
		if found_pirate:
			for icon in scene.enemy_icons:
				if icon != pirate_icon:
					others.append(icon)

		var opportunity_seen: Dictionary = {}
		var engaged: Dictionary = {}
		for other in others:
			opportunity_seen[other] = false
			engaged[other] = false

		# Rosters refresh only at real frames: nothing is freed between them, so the inner loops
		# need no validity checks (they run for every icon on every step).
		var prey := _prey(campaign_state, pirate_icon, others)
		var step_count := int(duration / STEP_DELTA)
		for step in step_count:
			if step > 0 and step % STEPS_PER_REAL_FRAME == 0:
				await tree.physics_frame
				tree.paused = false
				icons = _live_icons(scene)
				prey = _prey(campaign_state, pirate_icon, others)
				_track_idle_traders(campaign_state, sim_time[0], idle_since, max_idle)
			scene._physics_process(STEP_DELTA)
			sim_time[0] += STEP_DELTA
			for icon in icons:
				icon._physics_process(STEP_DELTA)
			for icon in icons:
				if spawn_positions.has(icon):
					var d: float = icon.position.distance_to(spawn_positions[icon])
					if d > max_distance[icon]:
						max_distance[icon] = d
				var pos: Vector2 = icon.position
				if not out_of_bounds.has(icon) and pos != JumpRules.clamp_to_system(pos):
					out_of_bounds[icon] = [_label(scene, icon), pos]
			for other in prey:
				var pirate_distance: float = pirate_icon.global_position.distance_to(other.global_position)
				if pirate_distance <= pirate_icon.detection_range:
					opportunity_seen[other] = true
				if pirate_icon._move_target.distance_to(other.global_position) <= ENGAGEMENT_EPSILON:
					engaged[other] = true

		for icon in spawn_positions:
			if _alive(icon):
				print("[sim %0.0fs] %s max distance from spawn: %.1f" % [duration, _label(scene, icon), max_distance[icon]])
		for icon in out_of_bounds:
			failures.append("[sim %0.0fs] %s went out of map bounds: %s" % [duration, out_of_bounds[icon][0], out_of_bounds[icon][1]])

		if not found_pirate:
			failures.append("[sim %0.0fs] no pirate icon found in bootstrap -- cannot check pirate engagement" % duration)
		for other in others:
			var other_label: String = _label(scene, other) if _alive(other) else "an icon since freed"
			if opportunity_seen[other] and not engaged[other]:
				failures.append("[sim %0.0fs] pirate never targeted %s despite coming within detection range" % [duration, other_label])

		_check_alive(campaign_state, duration, start_fleets, jumps_by_third, failures)
		_check_economy_and_traders(campaign_state, duration, seeded_slots, max_idle, failures)
		campaign_state.fleet_jumped.disconnect(on_jumped)
		scene.queue_free()
		await tree.process_frame
		tree.paused = false

	campaign_state.reset()
	return failures

static func _check_alive(campaign_state, duration: float, start_fleets: int, jumps_by_third: Array, failures: Array[String]) -> void:
	var fleets: int = campaign_state.enemy_fleets.size()
	var systems_with_fleets := {}
	for fleet in campaign_state.enemy_fleets:
		systems_with_fleets[fleet.system_id] = true
	print("[sim %0.0fs] fleets %d (started %d), NPC jumps by third %s, systems with fleets %d/%d" % [duration, fleets, start_fleets, jumps_by_third, systems_with_fleets.size(), campaign_state.galaxy.systems.size()])
	if fleets < start_fleets * MIN_FLEET_FRACTION:
		failures.append("[sim %0.0fs] expected at least %d fleets alive, got %d" % [duration, ceili(start_fleets * MIN_FLEET_FRACTION), fleets])
	if jumps_by_third[0] <= 0 or jumps_by_third[2] < jumps_by_third[0] * MIN_JUMP_RATE_KEPT:
		failures.append("[sim %0.0fs] expected NPC jumps in the last third at least %.0f%% of the first, got %s" % [duration, 100.0 * MIN_JUMP_RATE_KEPT, jumps_by_third])

static func _check_economy_and_traders(campaign_state, duration: float, seeded_slots: Dictionary, max_idle: Array, failures: Array[String]) -> void:
	var lost: Array[String] = []
	for station in campaign_state.galaxy.stations:
		var economy: BaseEconomy = station.economy
		if economy == null:
			continue
		if economy.slots.size() < seeded_slots[station.id]:
			lost.append(station.id)
			failures.append("[sim %0.0fs] expected %s to keep its %d slots, it has %d" % [duration, station.id, seeded_slots[station.id], economy.slots.size()])
	print("[sim %0.0fs] stations below their seeded slots: %s; longest trader idle at home with a destination: %.0f s (%s)" % [duration, lost, max_idle[0], max_idle[1]])
	if max_idle[0] > MAX_TRADER_IDLE_AT_HOME:
		failures.append("[sim %0.0fs] expected no trader idle at home over %.0f s with a destination, %s waited %.0f s" % [duration, MAX_TRADER_IDLE_AT_HOME, max_idle[1], max_idle[0]])

# Idle: in its home system, not warping, with a destination station in another system.
static func _track_idle_traders(campaign_state, now: float, idle_since: Dictionary, max_idle: Array) -> void:
	for fleet in campaign_state.enemy_fleets:
		var home: StationData = campaign_state.galaxy.station(fleet.home_station_id)
		var dest: StationData = campaign_state.galaxy.station(fleet.dest_station_id)
		var idle: bool = fleet.role == CampaignFleet.Role.TRADER and home != null and dest != null \
				and fleet.system_id == home.system_id and dest.system_id != fleet.system_id and not fleet.is_warping()
		if not idle:
			idle_since.erase(fleet)
			continue
		if not idle_since.has(fleet):
			idle_since[fleet] = now
		if now - idle_since[fleet] > max_idle[0]:
			max_idle[0] = now - idle_since[fleet]
			max_idle[1] = fleet.home_station_id

# Live icons the pirate is hostile to; empty once the pirate itself is gone.
static func _prey(campaign_state, pirate_icon, others: Array) -> Array:
	var result: Array = []
	if not _alive(pirate_icon):
		return result
	for other in others:
		if _alive(other) and campaign_state.are_hostile(pirate_icon.fleet, other.fleet):
			result.append(other)
	return result

# Untyped: the roster can hold freed icons, which fail any typed parameter check.
static func _alive(icon) -> bool:
	return icon != null and is_instance_valid(icon) and not icon.is_queued_for_deletion()

static func _live_icons(scene: Node2D) -> Array:
	var icons: Array = [scene.player_icon]
	for icon in scene.enemy_icons:
		if _alive(icon):
			icons.append(icon)
	return icons

static func _label(scene: Node2D, icon: CampaignFleetIcon) -> String:
	if icon == scene.player_icon:
		return "player"
	return "enemy[%d] (%s, %s)" % [scene.enemy_icons.find(icon), CampaignFleetIcon.BehaviorType.keys()[icon.behavior_type], icon.fleet.system_id]
