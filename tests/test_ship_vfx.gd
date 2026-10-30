extends RefCounted

const ShipVfx = preload("res://scripts/ship/ship_vfx.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []
	_check_should_emit_smoke(failures)
	return failures

static func _check_should_emit_smoke(failures: Array[String]) -> void:
	if ShipVfx.should_emit_smoke(0.5, 0.25):
		failures.append("should_emit_smoke: expected false when hp_ratio is above threshold")
	if not ShipVfx.should_emit_smoke(0.25, 0.25):
		failures.append("should_emit_smoke: expected true when hp_ratio equals threshold (inclusive)")
	if not ShipVfx.should_emit_smoke(0.1, 0.25):
		failures.append("should_emit_smoke: expected true when hp_ratio is below threshold")
