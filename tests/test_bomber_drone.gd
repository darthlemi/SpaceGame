extends RefCounted

const BomberDrone = preload("res://scripts/drones/bomber_drone.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var bomber := BomberDrone.new()
	var hull := Hull.new()
	hull.max_hp = 10.0
	hull._ready()
	var shield := Shield.new()
	shield.max_shield = 0.0
	shield._ready()
	bomber.hull = hull
	bomber.shield = shield
	bomber.detonate_radius = 15.0
	bomber.payload_weapon = Weapon.new()
	bomber.payload_weapon.damage = 40.0
	bomber.payload_weapon.hull_mult = 1.3

	if not is_equal_approx(bomber.attack_range(), 15.0):
		failures.append("attack_range: expected detonate_radius 15.0, got %s" % bomber.attack_range())

	var target := Ship.new()
	var target_hull := Hull.new()
	target_hull.max_hp = 100.0
	target_hull._ready()
	var target_shield := Shield.new()
	target_shield.max_shield = 0.0
	target_shield._ready()
	target.hull = target_hull
	target.shield = target_shield
	target.global_position = Vector2(10.0, 0.0)

	bomber.global_position = Vector2.ZERO
	bomber.execute_order(Order.attack_target(target))
	bomber._process_weapons()

	if not is_equal_approx(target_hull.current_hp, 100.0 - 40.0 * 1.3):
		failures.append("_process_weapons: expected the payload to hit the target on detonation, got hull=%s" % target_hull.current_hp)
	if not bomber.hull.is_destroyed():
		failures.append("_process_weapons: expected the bomber to self-destruct on detonation")

	hull.free()
	shield.free()
	bomber.free()
	target_hull.free()
	target_shield.free()
	target.free()
	return failures
