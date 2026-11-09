extends RefCounted

const CombatSceneryScript = preload("res://scripts/background/combat_scenery.gd")

# Keep in sync with the ship spawn points in combat_scene.tscn's exported defaults: the
# rectangle any scenery body must stay clear of so a planet/asteroid never reads as part of
# the fight.
const SHIP_BOX := Rect2(800, 1250, 1600, 700)

static func run() -> Array[String]:
	var failures: Array[String] = []

	var first := CombatSceneryScript.pick("sol")
	var second := CombatSceneryScript.pick("sol")
	if first != second:
		failures.append("pick: expected deterministic result for the same id")

	for recipe_index in CombatSceneryScript.RECIPES.size():
		var recipe: Array = CombatSceneryScript.RECIPES[recipe_index]
		for i in recipe.size():
			var a: Dictionary = recipe[i]
			if _circle_hits_rect(a.position, a.radius, SHIP_BOX):
				failures.append("recipe %d: %s overlaps the ship box" % [recipe_index, a.texture])
			for j in range(i + 1, recipe.size()):
				var b: Dictionary = recipe[j]
				var distance: float = a.position.distance_to(b.position)
				var same_type: bool = a.type == b.type
				if same_type and distance < a.radius + b.radius:
					failures.append("recipe %d: %s overlaps %s (distance %.1f < radii sum %.1f)" % [recipe_index, a.texture, b.texture, distance, a.radius + b.radius])

	return failures

static func _circle_hits_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var closest := Vector2(
		clampf(center.x, rect.position.x, rect.position.x + rect.size.x),
		clampf(center.y, rect.position.y, rect.position.y + rect.size.y))
	return center.distance_to(closest) < radius
