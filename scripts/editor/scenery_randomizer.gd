class_name SceneryRandomizer
extends RefCounted

# Generates random system scenery: same spirit as CombatScenery's hand-placed recipes, but
# procedural, since every system (not 5 combat backdrops) needs its own look. PLANET/ASTEROID_
# BASE_RADIUS are approximate visible radii at scale 1.0 (same idea as CombatScenery's per-body
# "radius", tuned by eye against its existing values), used only for the overlap check below.

const SPACE := Vector2(3200.0, 3200.0)
const LAYERS := ["deep_background", "mid_distance", "foreground"]
const PLANET_SCALE_MIN := 3.0
const PLANET_SCALE_MAX := 4.0
const ASTEROID_SCALE_MIN := 1.0
const ASTEROID_SCALE_MAX := 2.5
const PLANET_BASE_RADIUS := 128.0
const ASTEROID_BASE_RADIUS := 160.0
const MAX_RETRIES := 8

static func generate(rng: RandomNumberGenerator, planet_textures: Array, asteroid_textures: Array) -> Dictionary:
	var background := {
		"category": StarfieldAssignment.CATEGORIES[rng.randi_range(0, StarfieldAssignment.CATEGORIES.size() - 1)],
		"seed": rng.randi_range(1, StarfieldAssignment.SEED_COUNT),
	}
	var scenery: Array = []
	for i in rng.randi_range(1, 2):
		scenery.append(_place(rng, "planet", planet_textures, PLANET_SCALE_MIN, PLANET_SCALE_MAX, PLANET_BASE_RADIUS, scenery))
	for i in rng.randi_range(1, 4):
		scenery.append(_place(rng, "asteroid", asteroid_textures, ASTEROID_SCALE_MIN, ASTEROID_SCALE_MAX, ASTEROID_BASE_RADIUS, scenery))
	return {"background": background, "scenery": scenery}

static func _place(rng: RandomNumberGenerator, type: String, textures: Array, scale_min: float, scale_max: float, base_radius: float, placed: Array) -> Dictionary:
	var texture: String = textures[rng.randi_range(0, textures.size() - 1)]
	var scale: float = rng.randf_range(scale_min, scale_max)
	var layer: String = LAYERS[rng.randi_range(0, LAYERS.size() - 1)]
	var pos := Vector2.ZERO
	for attempt in MAX_RETRIES:
		pos = Vector2(rng.randf_range(0.0, SPACE.x), rng.randf_range(0.0, SPACE.y))
		if not _overlaps(pos, scale, base_radius, type, placed):
			break
	return {"type": type, "texture": texture, "pos": [pos.x, pos.y], "scale": scale, "layer": layer}

static func _overlaps(pos: Vector2, scale: float, base_radius: float, type: String, placed: Array) -> bool:
	for item in placed:
		if item["type"] != type:
			continue
		var other_pos := Vector2(item["pos"][0], item["pos"][1])
		var other_radius: float = float(item["scale"]) * base_radius
		if pos.distance_to(other_pos) < scale * base_radius + other_radius:
			return true
	return false
