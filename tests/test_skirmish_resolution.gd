extends RefCounted

const SkirmishResolution = preload("res://scripts/campaign/skirmish_resolution.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var even := SkirmishResolution.imbalance(100.0, 100.0)
	if even != 0.0:
		failures.append("imbalance: expected 0.0 for an even fight, got %s" % even)

	var lopsided := SkirmishResolution.imbalance(190.0, 10.0)
	if abs(lopsided - 0.9) > 0.001:
		failures.append("imbalance: expected ~0.9 for a 190/10 split, got %s" % lopsided)

	var zero_total := SkirmishResolution.imbalance(0.0, 0.0)
	if zero_total != 1.0:
		failures.append("imbalance: expected 1.0 when both strengths are 0, got %s" % zero_total)

	var long_duration := SkirmishResolution.duration(0.0)
	if abs(long_duration - SkirmishResolution.MAX_SKIRMISH_TIME) > 0.001:
		failures.append("duration: expected MAX_SKIRMISH_TIME at imbalance 0.0, got %s" % long_duration)

	var short_duration := SkirmishResolution.duration(1.0)
	if abs(short_duration - SkirmishResolution.MIN_SKIRMISH_TIME) > 0.001:
		failures.append("duration: expected MIN_SKIRMISH_TIME at imbalance 1.0, got %s" % short_duration)

	var even_damage := SkirmishResolution.winner_damage_fraction(0.0)
	if abs(even_damage - SkirmishResolution.MAX_WINNER_DAMAGE_FRACTION) > 0.001:
		failures.append("winner_damage_fraction: expected MAX_WINNER_DAMAGE_FRACTION at imbalance 0.0, got %s" % even_damage)

	var lopsided_damage := SkirmishResolution.winner_damage_fraction(1.0)
	if abs(lopsided_damage - 0.0) > 0.001:
		failures.append("winner_damage_fraction: expected ~0.0 at imbalance 1.0, got %s" % lopsided_damage)

	return failures
