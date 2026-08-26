extends RefCounted

const Hull = preload("res://scripts/ship/hull.gd")

class CallbackTracker:
	var fired := false
	func on_destroyed() -> void:
		fired = true

static func run() -> Array[String]:
	var failures: Array[String] = []
	var hull := Hull.new()
	hull.max_hp = 100.0
	hull.current_hp = 100.0

	var tracker = CallbackTracker.new()
	hull.destroyed.connect(tracker.on_destroyed)

	hull.apply_damage(30.0)
	if hull.current_hp != 70.0:
		failures.append("apply_damage: expected 70.0 remaining, got %s" % hull.current_hp)
	if tracker.fired:
		failures.append("apply_damage: destroyed fired prematurely")

	hull.apply_damage(1000.0)
	if hull.current_hp != 0.0:
		failures.append("apply_damage: expected 0.0 after overkill, got %s" % hull.current_hp)
	if not tracker.fired:
		failures.append("apply_damage: destroyed signal did not fire at 0 hp")

	hull.free()
	return failures
