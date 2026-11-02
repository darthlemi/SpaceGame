extends RefCounted

const Weapon = preload("res://scripts/weapons/weapon.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []
	var weapon := Weapon.new()

	if not is_equal_approx(weapon.shield_mult, 1.0):
		failures.append("default shield_mult: expected 1.0, got %s" % weapon.shield_mult)
	if not is_equal_approx(weapon.hull_mult, 1.0):
		failures.append("default hull_mult: expected 1.0, got %s" % weapon.hull_mult)
	if not is_equal_approx(weapon.pierce_pct, 0.0):
		failures.append("default pierce_pct: expected 0.0, got %s" % weapon.pierce_pct)
	if not is_equal_approx(weapon.component_damage, 0.0):
		failures.append("default component_damage: expected 0.0, got %s" % weapon.component_damage)
	if weapon.mount_type != Weapon.MountType.TURRET:
		failures.append("default mount_type: expected TURRET, got %s" % weapon.mount_type)
	if not is_equal_approx(weapon.fire_arc_degrees, 360.0):
		failures.append("default fire_arc_degrees: expected 360.0, got %s" % weapon.fire_arc_degrees)
	if weapon.rarity != Weapon.Rarity.COMMON:
		failures.append("default rarity: expected COMMON, got %s" % weapon.rarity)
	if weapon.submissile_count != 1:
		failures.append("default submissile_count: expected 1, got %s" % weapon.submissile_count)
	if not is_equal_approx(weapon.projectile_speed, 0.0):
		failures.append("default projectile_speed: expected 0.0, got %s" % weapon.projectile_speed)

	return failures
