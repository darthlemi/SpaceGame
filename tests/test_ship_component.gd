extends RefCounted

const ShipComponent = preload("res://scripts/ship/ship_component.gd")

class CallbackTracker:
	var fired := false
	func on_destroyed() -> void:
		fired = true

static func run() -> Array[String]:
	var failures: Array[String] = []
	var comp := ShipComponent.new()
	comp.max_hp = 40.0
	comp._ready()

	var tracker := CallbackTracker.new()
	comp.destroyed.connect(tracker.on_destroyed)

	if not is_equal_approx(comp.current_hp, 40.0):
		failures.append("_ready: expected current_hp seeded to max_hp, got %s" % comp.current_hp)
	if not is_equal_approx(comp.health_fraction(), 1.0):
		failures.append("health_fraction: expected 1.0 at full health, got %s" % comp.health_fraction())

	comp.apply_damage(10.0)
	if not is_equal_approx(comp.current_hp, 30.0):
		failures.append("apply_damage: expected 30.0 remaining, got %s" % comp.current_hp)
	if tracker.fired:
		failures.append("apply_damage: destroyed fired prematurely")
	if not is_equal_approx(comp.health_fraction(), 0.75):
		failures.append("health_fraction: expected 0.75, got %s" % comp.health_fraction())

	comp.apply_damage(1000.0)
	if comp.current_hp != 0.0:
		failures.append("apply_damage: expected 0.0 after overkill, got %s" % comp.current_hp)
	if not tracker.fired:
		failures.append("apply_damage: destroyed signal did not fire at 0 hp")
	if not comp.is_destroyed():
		failures.append("is_destroyed: expected true at 0 hp")

	tracker.fired = false
	comp.apply_damage(5.0)
	if tracker.fired:
		failures.append("apply_damage: destroyed re-fired on an already-dead component")

	comp.free()
	return failures
