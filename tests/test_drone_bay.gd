extends RefCounted

const DroneBay = preload("res://scripts/drones/drone_bay.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []
	var bay := DroneBay.new()
	bay.max_drones = 2
	bay.launch_interval = 0.3
	bay.respawn_delay = 15.0
	bay.drone_scene = preload("res://scenes/ship/ship.tscn")
	bay._ready()

	var target := Node2D.new()

	# Both slots start ready: first launch succeeds immediately.
	var first: Ship = bay.try_launch(target)
	if first == null:
		failures.append("try_launch: expected a drone from the first ready slot")

	# Second slot is still on its initial 0.0 cooldown too, but launch_interval
	# staggers it -- immediately re-calling try_launch before ticking should fail.
	var immediate_second: Ship = bay.try_launch(target)
	if immediate_second != null:
		failures.append("try_launch: expected the second slot to be staggered by launch_interval, got a drone immediately")

	bay._physics_process(0.3)
	var second: Ship = bay.try_launch(target)
	if second == null:
		failures.append("try_launch: expected the second slot ready after launch_interval elapses")

	# No slots left: a third call must fail.
	var third: Ship = bay.try_launch(target)
	if third != null:
		failures.append("try_launch: expected null once all max_drones slots are occupied")

	# Destroying a launched drone frees its slot, but only after respawn_delay.
	first.hull.apply_damage(first.hull.max_hp)
	var too_soon: Ship = bay.try_launch(target)
	if too_soon != null:
		failures.append("try_launch: expected null immediately after a drone dies (slot on respawn_delay)")
	bay._physics_process(15.0)
	var respawned: Ship = bay.try_launch(target)
	if respawned == null:
		failures.append("try_launch: expected the dead drone's slot to be ready after respawn_delay")

	target.free()
	if is_instance_valid(first):
		first.free()
	if is_instance_valid(second):
		second.free()
	if is_instance_valid(respawned):
		respawned.free()
	bay.free()
	return failures
