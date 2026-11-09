class_name CombatScenery
extends RefCounted

const PLANETS_DIR := "res://assets/sprites/backgrounds/planets/"
const ASTEROIDS_DIR := "res://assets/sprites/backgrounds/asteroids/"

enum BodyType { PLANET, ASTEROID }

# Hand-placed, not procedural -- only 5 combat backdrops exist, so curating each by eye is
# simpler than a general collision solver. "radius" is each body's approximate visible
# radius at its scale, used only by test_combat_scenery.gd's overlap check below, never at
# runtime. Rule enforced by that test: same-type pairs (planet-planet, asteroid-asteroid)
# never overlap and never reach into the ship/combat box; planet-asteroid pairs are allowed
# to sit close (an asteroid near a planet is fine; see the design feedback this followed).
const RECIPES := [
	# 0: lone_giant
	[
		{"type": BodyType.PLANET, "texture": "planet_gas_purple.png", "position": Vector2(1600, 650), "scale": 4.0, "radius": 512.0},
	],
	# 1: binary_giants -- two planets kept far apart, each with one nearby asteroid.
	[
		{"type": BodyType.PLANET, "texture": "planet_gas_red_ring.png", "position": Vector2(500, 550), "scale": 3.5, "radius": 448.0},
		{"type": BodyType.ASTEROID, "texture": "v1_round_a.png", "position": Vector2(950, 600), "scale": 1.5, "radius": 270.0},
		{"type": BodyType.PLANET, "texture": "planet_earthlike.png", "position": Vector2(2700, 2700), "scale": 3.2, "radius": 410.0},
		{"type": BodyType.ASTEROID, "texture": "v5_very_elongated_b.png", "position": Vector2(2250, 2650), "scale": 1.4, "radius": 252.0},
	],
	# 2: asteroid_field -- a pre-composed cluster plus two more scattered singles, no planet.
	[
		{"type": BodyType.ASTEROID, "texture": "cluster_v3_seed1.png", "position": Vector2(1600, 2700), "scale": 2.5, "radius": 325.0},
		{"type": BodyType.ASTEROID, "texture": "v2_elongated_a.png", "position": Vector2(950, 2400), "scale": 1.3, "radius": 234.0},
		{"type": BodyType.ASTEROID, "texture": "v4_elongated_cluster_c.png", "position": Vector2(2250, 2350), "scale": 1.3, "radius": 234.0},
	],
	# 3: moon_and_belt -- a moon with a loose asteroid belt near it.
	[
		{"type": BodyType.PLANET, "texture": "moon_icy.png", "position": Vector2(2700, 550), "scale": 3.0, "radius": 384.0},
		{"type": BodyType.ASTEROID, "texture": "v1_round_b.png", "position": Vector2(1850, 450), "scale": 1.0, "radius": 180.0},
		{"type": BodyType.ASTEROID, "texture": "v1_round_c.png", "position": Vector2(2300, 600), "scale": 1.0, "radius": 180.0},
		{"type": BodyType.ASTEROID, "texture": "v1_round_d.png", "position": Vector2(2750, 800), "scale": 1.0, "radius": 180.0},
	],
	# 4: busy_system -- two distant planets, each with its own nearby asteroid(s).
	[
		{"type": BodyType.PLANET, "texture": "planet_gas_purple.png", "position": Vector2(550, 600), "scale": 3.0, "radius": 384.0},
		{"type": BodyType.PLANET, "texture": "planet_earthlike.png", "position": Vector2(2650, 2600), "scale": 3.0, "radius": 384.0},
		{"type": BodyType.ASTEROID, "texture": "cluster_v3_seed1.png", "position": Vector2(950, 750), "scale": 2.0, "radius": 260.0},
		{"type": BodyType.ASTEROID, "texture": "v3_round_cluster_b.png", "position": Vector2(2300, 2450), "scale": 1.2, "radius": 216.0},
	],
]

static func pick(id: String) -> Array:
	return RECIPES[abs(hash(id)) % RECIPES.size()]

static func texture_path(placement: Dictionary) -> String:
	var dir: String = PLANETS_DIR if placement.type == BodyType.PLANET else ASTEROIDS_DIR
	return dir + placement.texture
