extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	var engine: EngineCore = load("res://resources/engines/engine_freehold_racer.tres")
	if engine == null:
		failures.append("engine_freehold_racer.tres: failed to load")
		return failures
	if not is_equal_approx(engine.max_speed, 300.0):
		failures.append("engine_freehold_racer: expected max_speed 300.0, got %s" % engine.max_speed)
	if engine.rarity != PartRarity.Tier.RARE:
		failures.append("engine_freehold_racer: expected rarity RARE, got %s" % engine.rarity)

	var paths := [
		"res://resources/engines/engine_standard.tres",
		"res://resources/engines/engine_dominion_heavy.tres",
		"res://resources/engines/engine_dominion_titan.tres",
		"res://resources/engines/engine_freehold_scout.tres",
		"res://resources/engines/engine_freehold_racer.tres",
	]
	for path in paths:
		if not ResourceLoader.exists(path):
			failures.append("EngineCore pool: missing resource %s" % path)
	return failures
