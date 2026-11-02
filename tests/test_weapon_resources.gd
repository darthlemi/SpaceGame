extends RefCounted

const Weapon = preload("res://scripts/weapons/weapon.gd")

static func _check(failures: Array[String], path: String, expected: Dictionary) -> void:
	var weapon: Weapon = load(path)
	if weapon == null:
		failures.append("%s: failed to load" % path)
		return
	for key in expected:
		var actual = weapon.get(key)
		var exp = expected[key]
		if typeof(exp) == TYPE_FLOAT:
			if not is_equal_approx(actual, exp):
				failures.append("%s: expected %s=%s, got %s" % [path, key, exp, actual])
		elif actual != exp:
			failures.append("%s: expected %s=%s, got %s" % [path, key, exp, actual])

static func run() -> Array[String]:
	var failures: Array[String] = []

	_check(failures, "res://resources/weapons/kinetic_cannon.tres", {
		"damage": 10.0, "fire_rate": 2.0, "weapon_range": 300.0,
		"shield_mult": 0.7, "hull_mult": 1.1,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 100.0,
		"rarity": Weapon.Rarity.COMMON,
	})
	_check(failures, "res://resources/weapons/mass_driver.tres", {
		"damage": 14.0, "fire_rate": 0.8, "weapon_range": 400.0,
		"shield_mult": 1.0, "hull_mult": 1.0,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 120.0,
		"rarity": Weapon.Rarity.COMMON,
	})
	_check(failures, "res://resources/weapons/flak_cannon.tres", {
		"damage": 4.0, "fire_rate": 4.0, "weapon_range": 200.0,
		"shield_mult": 0.6, "hull_mult": 0.6,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 140.0,
		"rarity": Weapon.Rarity.UNCOMMON,
	})
	_check(failures, "res://resources/weapons/railgun.tres", {
		"damage": 35.0, "fire_rate": 0.25, "weapon_range": 500.0,
		"shield_mult": 0.5, "hull_mult": 1.3, "pierce_pct": 0.25,
		"mount_type": Weapon.MountType.FIXED, "fire_arc_degrees": 10.0,
		"rarity": Weapon.Rarity.RARE,
	})
	_check(failures, "res://resources/weapons/seeker_missile.tres", {
		"damage": 18.0, "fire_rate": 0.5, "weapon_range": 350.0,
		"shield_mult": 1.1, "hull_mult": 0.9,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 360.0,
		"rarity": Weapon.Rarity.COMMON,
	})
	_check(failures, "res://resources/weapons/swarm_missile.tres", {
		"damage": 5.0, "fire_rate": 0.33, "weapon_range": 300.0,
		"shield_mult": 1.2, "hull_mult": 0.7, "submissile_count": 4,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 360.0,
		"rarity": Weapon.Rarity.UNCOMMON,
	})
	_check(failures, "res://resources/weapons/torpedo.tres", {
		"damage": 60.0, "fire_rate": 0.2, "weapon_range": 450.0,
		"shield_mult": 1.0, "hull_mult": 1.2, "projectile_speed": 150.0,
		"mount_type": Weapon.MountType.FIXED, "fire_arc_degrees": 10.0,
		"rarity": Weapon.Rarity.RARE,
	})
	_check(failures, "res://resources/weapons/emp_missile.tres", {
		"damage": 6.0, "fire_rate": 0.4, "weapon_range": 250.0,
		"shield_mult": 0.8, "hull_mult": 0.5, "component_damage": 15.0,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 360.0,
		"rarity": Weapon.Rarity.RARE,
	})
	_check(failures, "res://resources/weapons/pulse_laser.tres", {
		"damage": 9.0, "fire_rate": 1.2, "weapon_range": 280.0,
		"shield_mult": 1.4, "hull_mult": 0.75,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 110.0,
		"rarity": Weapon.Rarity.COMMON,
	})
	_check(failures, "res://resources/weapons/heavy_beam.tres", {
		"damage": 16.0, "fire_rate": 1.0, "weapon_range": 220.0,
		"shield_mult": 1.3, "hull_mult": 0.85,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 90.0,
		"rarity": Weapon.Rarity.UNCOMMON,
	})
	_check(failures, "res://resources/weapons/disruptor_beam.tres", {
		"damage": 5.0, "fire_rate": 1.0, "weapon_range": 260.0,
		"shield_mult": 1.0, "hull_mult": 0.4, "component_damage": 10.0,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 100.0,
		"rarity": Weapon.Rarity.RARE,
	})
	_check(failures, "res://resources/weapons/lance_graser.tres", {
		"damage": 30.0, "fire_rate": 0.4, "weapon_range": 450.0,
		"shield_mult": 0.6, "hull_mult": 1.3, "pierce_pct": 0.2,
		"mount_type": Weapon.MountType.FIXED, "fire_arc_degrees": 10.0,
		"rarity": Weapon.Rarity.EPIC,
	})
	_check(failures, "res://resources/weapons/pd_flak_turret.tres", {
		"damage": 3.0, "fire_rate": 6.0, "weapon_range": 120.0,
		"shield_mult": 0.3, "hull_mult": 0.3,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 360.0,
		"rarity": Weapon.Rarity.COMMON,
	})
	_check(failures, "res://resources/weapons/pd_laser_turret.tres", {
		"damage": 6.0, "fire_rate": 3.0, "weapon_range": 150.0,
		"shield_mult": 0.3, "hull_mult": 0.3,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 360.0,
		"rarity": Weapon.Rarity.UNCOMMON,
	})

	return failures
