extends RefCounted

const StarfieldAssignmentScript = preload("res://scripts/background/starfield_assignment.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var planets := ["planet_gas_purple.png", "planet_earthlike.png"]
	var asteroids := ["v1_round_a.png", "v2_elongated_a.png"]
	var result := SceneryRandomizer.generate(rng, planets, asteroids)

	if not StarfieldAssignmentScript.CATEGORIES.has(result["background"]["category"]):
		failures.append("generate: unexpected background category %s" % [result["background"]])
	if result["background"]["seed"] < 1 or result["background"]["seed"] > StarfieldAssignmentScript.SEED_COUNT:
		failures.append("generate: seed out of range, got %s" % [result["background"]])

	var scenery: Array = result["scenery"]
	var planet_count := 0
	var asteroid_count := 0
	for item in scenery:
		if item["type"] == "planet":
			planet_count += 1
		elif item["type"] == "asteroid":
			asteroid_count += 1
		else:
			failures.append("generate: unexpected type %s" % item["type"])
		var pos: Array = item["pos"]
		if pos[0] < 0.0 or pos[0] > SceneryRandomizer.SPACE.x or pos[1] < 0.0 or pos[1] > SceneryRandomizer.SPACE.y:
			failures.append("generate: position out of bounds, got %s" % [pos])
		if not SceneryRandomizer.LAYERS.has(item["layer"]):
			failures.append("generate: unexpected layer %s" % item["layer"])
	if planet_count < 1 or planet_count > 2:
		failures.append("generate: expected 1-2 planets, got %d" % planet_count)
	if asteroid_count < 1 or asteroid_count > 4:
		failures.append("generate: expected 1-4 asteroids, got %d" % asteroid_count)

	# Same-type overlap check (mirrors test_combat_scenery.gd's approach).
	for i in scenery.size():
		for j in range(i + 1, scenery.size()):
			var a: Dictionary = scenery[i]
			var b: Dictionary = scenery[j]
			if a["type"] != b["type"]:
				continue
			var pa := Vector2(a["pos"][0], a["pos"][1])
			var pb := Vector2(b["pos"][0], b["pos"][1])
			var base: float = SceneryRandomizer.PLANET_BASE_RADIUS if a["type"] == "planet" else SceneryRandomizer.ASTEROID_BASE_RADIUS
			var radii: float = (float(a["scale"]) + float(b["scale"])) * base
			if pa.distance_to(pb) < radii:
				failures.append("generate: %s and %s of the same type overlap (distance %.1f < %.1f)" % [a["texture"], b["texture"], pa.distance_to(pb), radii])

	var repeat := RandomNumberGenerator.new()
	repeat.seed = 42
	var result2 := SceneryRandomizer.generate(repeat, planets, asteroids)
	if result2 != result:
		failures.append("generate: expected the same seed to reproduce the same result")

	# Test empty texture arrays: should not crash, just skip placing items of that type.
	var rng_empty := RandomNumberGenerator.new()
	rng_empty.seed = 99

	# Empty planets: should produce zero planets.
	var result_no_planets := SceneryRandomizer.generate(rng_empty, [], asteroids)
	var planet_count_empty := 0
	for item in result_no_planets["scenery"]:
		if item["type"] == "planet":
			planet_count_empty += 1
	if planet_count_empty != 0:
		failures.append("generate: empty planet_textures should produce zero planets, got %d" % planet_count_empty)

	# Empty asteroids: should produce zero asteroids.
	rng_empty.seed = 99
	var result_no_asteroids := SceneryRandomizer.generate(rng_empty, planets, [])
	var asteroid_count_empty := 0
	for item in result_no_asteroids["scenery"]:
		if item["type"] == "asteroid":
			asteroid_count_empty += 1
	if asteroid_count_empty != 0:
		failures.append("generate: empty asteroid_textures should produce zero asteroids, got %d" % asteroid_count_empty)

	# Both empty: should produce no scenery items.
	rng_empty.seed = 99
	var result_no_scenery := SceneryRandomizer.generate(rng_empty, [], [])
	if result_no_scenery["scenery"].size() != 0:
		failures.append("generate: both empty texture arrays should produce zero scenery, got %d items" % result_no_scenery["scenery"].size())

	return failures
