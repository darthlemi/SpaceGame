extends RefCounted

const Shield = preload("res://scripts/ship/shield.gd")

class SignalTracker:
	var depleted_count := 0
	var restored_count := 0
	func on_depleted() -> void:
		depleted_count += 1
	func on_restored() -> void:
		restored_count += 1

static func run() -> Array[String]:
	var failures: Array[String] = []
	var shield := Shield.new()
	shield.max_shield = 50.0
	shield.current_shield = 50.0

	var overflow := shield.absorb(20.0)
	if overflow != 0.0:
		failures.append("absorb: expected 0 overflow, got %s" % overflow)
	if shield.current_shield != 30.0:
		failures.append("absorb: expected 30.0 remaining shield, got %s" % shield.current_shield)

	overflow = shield.absorb(50.0)
	if overflow != 20.0:
		failures.append("absorb: expected 20.0 overflow, got %s" % overflow)
	if shield.current_shield != 0.0:
		failures.append("absorb: expected 0.0 remaining shield, got %s" % shield.current_shield)

	overflow = shield.absorb(10.0)
	if overflow != 10.0:
		failures.append("absorb: expected full passthrough at 0 shield, got %s" % overflow)

	shield.free()

	var debuffed := Shield.new()
	debuffed.max_shield = 50.0
	debuffed.current_shield = 0.0
	debuffed.regen_rate = 10.0
	debuffed.regen_multiplier = 0.5
	debuffed._physics_process(1.0)
	if not is_equal_approx(debuffed.current_shield, 5.0):
		failures.append("regen_multiplier: expected 10.0*0.5*1.0=5.0 regen, got %s" % debuffed.current_shield)
	if not is_equal_approx(debuffed.regen_multiplier, 1.0):
		failures.append("regen_multiplier: expected reset to 1.0 after one frame, got %s" % debuffed.regen_multiplier)
	debuffed.free()

	var signaled := Shield.new()
	signaled.max_shield = 20.0
	signaled.current_shield = 20.0
	var tracker := SignalTracker.new()
	signaled.depleted.connect(tracker.on_depleted)
	signaled.restored.connect(tracker.on_restored)

	signaled.absorb(20.0)
	if tracker.depleted_count != 1:
		failures.append("depleted: expected exactly 1 emission on exact depletion, got %s" % tracker.depleted_count)
	if not is_equal_approx(signaled.health_fraction(), 0.0):
		failures.append("health_fraction: expected 0.0 when depleted, got %s" % signaled.health_fraction())

	signaled.absorb(5.0)
	if tracker.depleted_count != 1:
		failures.append("depleted: expected no re-emission while already at 0, got count=%s" % tracker.depleted_count)

	signaled._physics_process(1.0)  # regen_rate default 5.0 -> current_shield rises above 0
	if tracker.restored_count != 1:
		failures.append("restored: expected exactly 1 emission when regen crosses back above 0, got %s" % tracker.restored_count)

	signaled.free()

	return failures
