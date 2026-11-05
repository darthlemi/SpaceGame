extends SceneTree

# Manual frame-time check for the fully populated galaxy (not in the suite). Run headless and not:
#   Start-Process -FilePath $godot -ArgumentList '--path','.','--script','res://tests/perf_galaxy.gd' -RedirectStandardOutput perf_output.txt -Wait -NoNewWindow
# Pass bar (non-headless): average under 8 ms and max under 33 ms at both 1x and 5x.
# A "frame" is one main-loop iteration (physics + process + render) that ran at least one
# physics step; vsync, the fps cap and low-processor sleep are off so the interval is work.
# --verbose (after --) also prints the average of every 100 frames.

# load(), not preload(): campaign_scene.gd names the CampaignState autoload, which a --script
# only registers after the first frame.
const CAMPAIGN_SCENE_PATH := "res://scenes/campaign/campaign_scene.tscn"
const FRAMES_PER_SPEED := 600
const SPEEDS: Array[float] = [1.0, 5.0]
const VERBOSE_BUCKET := 100
const WARMUP_FRAMES := 30

var _physics_frames: int = 0
var _first_physics_usec: int = -1

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
	var campaign_state = root.get_node("/root/CampaignState")
	campaign_state.new_game()
	var scene: Node2D = load(CAMPAIGN_SCENE_PATH).instantiate()
	root.add_child(scene)
	for _i in WARMUP_FRAMES:
		await process_frame
	paused = false
	print("perf_galaxy: headless=%s fleets=%d systems=%d" % [DisplayServer.get_name() == "headless", campaign_state.enemy_fleets.size(), campaign_state.galaxy.systems.size()])
	for speed in SPEEDS:
		Engine.time_scale = speed
		var samples := await _measure(FRAMES_PER_SPEED)
		_report(speed, samples, campaign_state.enemy_fleets.size(), verbose)
	Engine.time_scale = 1.0
	scene.queue_free()
	await process_frame
	quit()

# Per main-loop iteration that ran physics, until `count` physics frames ran: "frame" is the whole
# iteration's wall time, "physics" the stretch from its first physics step to its process step
# (the simulation alone, which headless pacing can't inflate).
func _measure(count: int) -> Dictionary:
	var frames: Array[float] = []
	var physics: Array[float] = []
	var start_physics := _physics_frames
	var last_usec := Time.get_ticks_usec()
	var last_physics := _physics_frames
	while _physics_frames - start_physics < count:
		await process_frame
		var now := Time.get_ticks_usec()
		if _physics_frames != last_physics:
			frames.append((now - last_usec) / 1000.0)
			physics.append((now - _first_physics_usec) / 1000.0)
		_first_physics_usec = -1
		last_usec = now
		last_physics = _physics_frames
	return {"frame": frames, "physics": physics}

func _on_physics_frame() -> void:
	_physics_frames += 1
	if _first_physics_usec < 0:
		_first_physics_usec = Time.get_ticks_usec()

func _report(speed: float, samples: Dictionary, fleets: int, verbose: bool) -> void:
	for kind in ["frame", "physics"]:
		var values: Array[float] = samples[kind]
		var total := 0.0
		var worst := 0.0
		for ms in values:
			total += ms
			worst = maxf(worst, ms)
		print("speed %.0fx %s: fleets=%d frames=%d avg=%.2f ms max=%.2f ms" % [speed, kind, fleets, values.size(), total / maxf(1.0, values.size()), worst])
		if not verbose:
			continue
		for bucket_start in range(0, values.size(), VERBOSE_BUCKET):
			var bucket := values.slice(bucket_start, bucket_start + VERBOSE_BUCKET)
			var bucket_total := 0.0
			var bucket_max := 0.0
			for ms in bucket:
				bucket_total += ms
				bucket_max = maxf(bucket_max, ms)
			print("  %s %d-%d: avg=%.2f ms max=%.2f ms" % [kind, bucket_start, bucket_start + bucket.size() - 1, bucket_total / bucket.size(), bucket_max])
