extends RefCounted

const StarfieldAssignmentScript = preload("res://scripts/background/starfield_assignment.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var first := StarfieldAssignmentScript.pick("sol")
	var second := StarfieldAssignmentScript.pick("sol")
	if first != second:
		failures.append("pick: expected deterministic result for the same id, got %s then %s" % [first, second])

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

	return failures
