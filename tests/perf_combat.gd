extends SceneTree

# Manual frame-time check for N-v-N combat (not in the suite). Run headless and not:
#   Start-Process -FilePath $godot -ArgumentList '--path','.','--script','res://tests/perf_combat.gd' -RedirectStandardOutput perf_output.txt -Wait -NoNewWindow
# Pass bar (non-headless): average under 8 ms and max under 33 ms at both 1x and 5x.
# Gates DangerTier.SECURITY_MAX_SHIPS: the largest N that passes at every speed.
# Hulls are invulnerable so every battle keeps its full N-v-N for the whole measurement.
# Frame timing as in perf_galaxy.gd. --verbose (after --) also prints each battle's ship counts.

# load(), not preload(): combat_scene.gd names the CampaignState autoload, which a --script
# only registers after the first frame.
const COMBAT_SCENE_PATH := "res://scenes/combat/combat_scene.tscn"
const FLEET_SIZES: Array[int] = [10, 15, 20]
const FRAMES_PER_SPEED := 600
const SPEEDS: Array[float] = [1.0, 5.0]
const WARMUP_FRAMES := 30

var _physics_frames: int = 0

func _initialize() -> void:
	_run()

func _run() -> void:
	# Autoloads register after the first frame.
	await process_frame
	var verbose := OS.get_cmdline_user_args().has("--verbose")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	# Headless runs in low-processor mode, which sleeps ~7 ms a frame and would read as work.
	OS.low_processor_usage_mode = false
	physics_frame.connect(_on_physics_frame)
	print("perf_combat: headless=%s" % (DisplayServer.get_name() == "headless"))
	for size in FLEET_SIZES:
		await _run_battle(size, verbose)
	Engine.time_scale = 1.0
	quit()

func _run_battle(size: int, verbose: bool) -> void:
	var campaign_state = root.get_node("/root/CampaignState")
	campaign_state.reset()
	var player_fleet := CampaignFleet.new()
	var enemy_fleet := CampaignFleet.new()
	for _i in size:
		player_fleet.ship_compositions.append(ShipType.new_composition(ShipType.Kind.CORVETTE))
		enemy_fleet.ship_compositions.append(ShipType.new_composition(ShipType.Kind.CORVETTE))
	campaign_state.enemy_fleets.assign([enemy_fleet])
	campaign_state.player_fleet = player_fleet
	campaign_state.start_engagement(enemy_fleet)
	var scene: Node2D = load(COMBAT_SCENE_PATH).instantiate()
	root.add_child(scene)
	for _i in WARMUP_FRAMES:
		await process_frame
	for ship in scene.player_ships + scene.enemy_ships:
		ship.hull.invulnerable = true
	paused = false
	if verbose:
		print("battle %dv%d: spawned %d player, %d enemy ships" % [size, size, scene.player_ships.size(), scene.enemy_ships.size()])
	for speed in SPEEDS:
		Engine.time_scale = speed
		var samples := await _measure(FRAMES_PER_SPEED)
		_report(size, speed, samples)
	Engine.time_scale = 1.0
	scene.queue_free()
	campaign_state.reset()
	await process_frame

# Per main-loop iteration that ran a physics step, until `count` physics frames ran.
func _measure(count: int) -> Array[float]:
	var frames: Array[float] = []
	var start_physics := _physics_frames
	var last_usec := Time.get_ticks_usec()
	var last_physics := _physics_frames
	while _physics_frames - start_physics < count:
		await process_frame
		var now := Time.get_ticks_usec()
		if _physics_frames != last_physics:
			frames.append((now - last_usec) / 1000.0)
		last_usec = now
		last_physics = _physics_frames
	return frames

func _on_physics_frame() -> void:
	_physics_frames += 1

func _report(size: int, speed: float, values: Array[float]) -> void:
	var total := 0.0
	var worst := 0.0
	for ms in values:
		total += ms
		worst = maxf(worst, ms)
	print("%dv%d speed %.0fx: frames=%d avg=%.2f ms max=%.2f ms" % [size, size, speed, values.size(), total / maxf(1.0, values.size()), worst])
