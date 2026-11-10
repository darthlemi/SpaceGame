extends RefCounted

const StarfieldAssignmentScript = preload("res://scripts/background/starfield_assignment.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var first := StarfieldAssignmentScript.pick("sol")
	var second := StarfieldAssignmentScript.pick("sol")
	if first != second:
		failures.append("pick: expected deterministic result for the same id, got %s then %s" % [first, second])

	var overridden := StarfieldAssignmentScript.pick("sol", StarfieldAssignmentScript.CATEGORIES, {"category": "dense", "seed": 2})
	if overridden != {"category": "dense", "seed": 2}:
		failures.append("pick: expected an explicit override to win outright, got %s" % [overridden])
	var overridden_path := StarfieldAssignmentScript.base_texture_path("sol", StarfieldAssignmentScript.CATEGORIES, {"category": "dense", "seed": 2})
	if overridden_path != "res://assets/sprites/backgrounds/starfield/dense/dense_02.png":
		failures.append("base_texture_path: expected the override path, got %s" % overridden_path)
	var empty_override := StarfieldAssignmentScript.pick("sol", StarfieldAssignmentScript.CATEGORIES, {})
	if empty_override != first:
		failures.append("pick: expected an empty override to fall back to the hash, got %s vs %s" % [empty_override, first])

	var seen_categories := {}
	for i in range(30):
		var choice := StarfieldAssignmentScript.pick("system_%d" % i)
		if not StarfieldAssignmentScript.CATEGORIES.has(choice.category):
			failures.append("pick: category %s not in CATEGORIES" % choice.category)
		if choice.seed < 1 or choice.seed > StarfieldAssignmentScript.SEED_COUNT:
			failures.append("pick: seed %d out of range 1..%d" % [choice.seed, StarfieldAssignmentScript.SEED_COUNT])
		seen_categories[choice.category] = true
	if seen_categories.size() < 2:
		failures.append("pick: expected a spread of categories across 30 ids, got only %s" % [seen_categories.keys()])

	var path := StarfieldAssignmentScript.base_texture_path("sol")
	var expected := "res://assets/sprites/backgrounds/starfield/%s/%s_%02d.png" % [first.category, first.category, first.seed]
	if path != expected:
		failures.append("base_texture_path: expected %s, got %s" % [expected, path])

	for i in range(20):
		var combat_choice := StarfieldAssignmentScript.pick("combat_%d" % i, StarfieldAssignmentScript.COMBAT_CATEGORIES)
		if combat_choice.category != "sparse":
			failures.append("pick: combat pool expected sparse, got %s" % combat_choice.category)

	var seen_system_categories := {}
	for i in range(20):
		var system_choice := StarfieldAssignmentScript.pick("system_pool_%d" % i, StarfieldAssignmentScript.SYSTEM_CATEGORIES)
		if not StarfieldAssignmentScript.SYSTEM_CATEGORIES.has(system_choice.category):
			failures.append("pick: system pool returned %s, outside SYSTEM_CATEGORIES" % system_choice.category)
		seen_system_categories[system_choice.category] = true
	if seen_system_categories.size() < 2:
		failures.append("pick: expected both SYSTEM_CATEGORIES to appear across 20 ids, got only %s" % [seen_system_categories.keys()])

	return failures
