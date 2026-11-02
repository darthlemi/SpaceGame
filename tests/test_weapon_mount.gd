extends RefCounted

const WeaponMount = preload("res://scripts/weapons/weapon_mount.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var weapon := Weapon.new()
	weapon.weapon_name = "Kinetic Cannon"
	weapon.damage = 10.0
	weapon.fire_rate = 2.0
	weapon.weapon_range = 300.0

	var mount := WeaponMount.new()
	mount.weapon = weapon
	mount._ready()  # seed current_hp = max_hp now that WeaponMount extends ShipComponent

	if not mount.can_fire():
		failures.append("can_fire: expected true initially, got false")

	# Target beyond weapon range: try_fire should return false and not fire.
	var far_target := Node2D.new()
	far_target.global_position = Vector2(500.0, 0.0)
	mount.global_position = Vector2.ZERO
	var fired_far := mount.try_fire(far_target)
	if fired_far:
		failures.append("try_fire: expected false for target beyond range, got true")
	if mount.cooldown_remaining != 0.0:
		failures.append("try_fire: expected no cooldown to be set when out of range, got %s" % mount.cooldown_remaining)
	if not mount.can_fire():
		failures.append("can_fire: expected true after failed out-of-range fire attempt")

	# In-range success branch: try_fire() with target within range should return true
	# and set cooldown_remaining (even though projectile_scene is null, _spawn_projectile
	# returns early without calling get_tree()).
	var close_target := Node2D.new()
	close_target.global_position = Vector2(200.0, 0.0)
	mount.global_position = Vector2.ZERO
	mount.cooldown_remaining = 0.0  # Reset cooldown for this test
	var fired_close := mount.try_fire(close_target)
	if not fired_close:
		failures.append("try_fire: expected true for target within range, got false")
	if not is_equal_approx(mount.cooldown_remaining, 1.0 / weapon.fire_rate):
		failures.append("try_fire: expected cooldown_remaining to be 0.5 after successful fire, got %s" % mount.cooldown_remaining)
	if mount.can_fire():
		failures.append("can_fire: expected false immediately after successful fire (on cooldown)")

	# Immediate second fire attempt should fail (cooldown blocks it)
	var fired_again := mount.try_fire(close_target)
	if fired_again:
		failures.append("try_fire: expected false on second immediate fire attempt (still on cooldown), got true")

	# Cooldown bookkeeping: simulate cooldown_remaining being set and ticking down,
	# without invoking _spawn_projectile (which requires a live SceneTree).
	mount.cooldown_remaining = 1.0 / weapon.fire_rate
	if mount.can_fire():
		failures.append("can_fire: expected false immediately after cooldown is set")
	if not is_equal_approx(mount.cooldown_remaining, 0.5):
		failures.append("cooldown_remaining: expected 0.5 for fire_rate 2.0, got %s" % mount.cooldown_remaining)

	mount._physics_process(0.5)
	if mount.cooldown_remaining > 0.0:
		failures.append("_physics_process: expected cooldown to reach 0 after ticking 0.5s, got %s" % mount.cooldown_remaining)
	if not mount.can_fire():
		failures.append("can_fire: expected true after cooldown fully elapsed")

	var dying_mount := WeaponMount.new()
	dying_mount.weapon = weapon
	dying_mount.max_hp = 15.0
	dying_mount._ready()
	if not dying_mount.can_fire():
		failures.append("can_fire: expected true before any damage")
	dying_mount.apply_damage(15.0)
	if dying_mount.can_fire():
		failures.append("can_fire: expected false once the mount is destroyed")
	if dying_mount.try_fire(close_target):
		failures.append("try_fire: expected false once the mount is destroyed, even with target in range")
	dying_mount.free()

	# Fire-arc gating: a narrow-arc (e.g. Fixed) weapon mounted facing +X (rotation 0)
	# should refuse to fire at a target far off to the side, and accept one dead ahead.
	var narrow_weapon := Weapon.new()
	narrow_weapon.weapon_name = "Railgun"
	narrow_weapon.damage = 35.0
	narrow_weapon.fire_rate = 1.0
	narrow_weapon.weapon_range = 500.0
	narrow_weapon.fire_arc_degrees = 10.0

	var narrow_mount := WeaponMount.new()
	narrow_mount.weapon = narrow_weapon
	narrow_mount.global_position = Vector2.ZERO
	narrow_mount.rotation = 0.0

	var ahead_target := Node2D.new()
	ahead_target.global_position = Vector2(200.0, 0.0)
	if not narrow_mount._within_arc(ahead_target):
		failures.append("_within_arc: expected target dead ahead to be within a 10-degree arc")

	var side_target := Node2D.new()
	side_target.global_position = Vector2(0.0, 200.0)
	if narrow_mount._within_arc(side_target):
		failures.append("_within_arc: expected target 90 degrees off-axis to be outside a 10-degree arc")

	# Default 360-degree arc (e.g. the existing Kinetic Cannon) must accept any angle.
	if not mount._within_arc(side_target):
		failures.append("_within_arc: expected default 360-degree arc to accept any target angle")

	ahead_target.free()
	side_target.free()
	narrow_mount.free()

	far_target.free()
	close_target.free()
	mount.free()
	return failures

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var weapon := Weapon.new()
	weapon.weapon_name = "Kinetic Cannon"
	weapon.damage = 10.0
	weapon.fire_rate = 2.0
	weapon.weapon_range = 300.0
	weapon.projectile_scene = preload("res://scenes/weapons/projectile.tscn")

	var mount := WeaponMount.new()
	mount.weapon = weapon
	mount._ready()
	tree.root.add_child(mount)
	mount.global_position = Vector2.ZERO

	var target := Node2D.new()
	target.global_position = Vector2(100.0, 0.0)
	tree.root.add_child(target)

	var particles_before := tree.root.get_children().filter(func(c): return c is CPUParticles2D).size()
	var fired := mount.try_fire(target)
	if not fired:
		failures.append("try_fire: expected true for an in-range target with a real projectile scene")

	var particles_after: Array = tree.root.get_children().filter(func(c): return c is CPUParticles2D)
	if particles_after.size() != particles_before + 1:
		failures.append("_spawn_projectile: expected exactly one new muzzle flash particle node, got %d new" % (particles_after.size() - particles_before))
	elif not particles_after[particles_after.size() - 1].global_position.is_equal_approx(mount.global_position):
		failures.append("_spawn_projectile: expected muzzle flash at mount position %s, got %s" % [mount.global_position, particles_after[particles_after.size() - 1].global_position])

	# Submissile volley: a weapon with submissile_count 4 should spawn 4 projectiles
	# but still exactly one muzzle flash, and projectile_speed should be applied.
	var swarm_weapon := Weapon.new()
	swarm_weapon.weapon_name = "Swarm Missile"
	swarm_weapon.damage = 5.0
	swarm_weapon.fire_rate = 1.0
	swarm_weapon.weapon_range = 300.0
	swarm_weapon.submissile_count = 4
	swarm_weapon.projectile_speed = 80.0
	swarm_weapon.projectile_scene = preload("res://scenes/weapons/projectile.tscn")

	var swarm_mount := WeaponMount.new()
	swarm_mount.weapon = swarm_weapon
	swarm_mount._ready()
	tree.root.add_child(swarm_mount)
	swarm_mount.global_position = Vector2.ZERO

	var projectiles_before: Array = tree.root.get_children().filter(func(c): return c is Projectile)
	var flashes_before: Array = tree.root.get_children().filter(func(c): return c is CPUParticles2D)

	var swarm_fired := swarm_mount.try_fire(target)
	if not swarm_fired:
		failures.append("try_fire: expected true for swarm volley with an in-range target")

	var projectiles_after: Array = tree.root.get_children().filter(func(c): return c is Projectile)
	if projectiles_after.size() != projectiles_before.size() + 4:
		failures.append("_spawn_projectile: expected 4 new projectiles for submissile_count 4, got %d new" % (projectiles_after.size() - projectiles_before.size()))
	for p in projectiles_after:
		if p is Projectile and not projectiles_before.has(p):
			if not is_equal_approx(p.speed, 80.0):
				failures.append("_spawn_projectile: expected submissile speed 80.0, got %s" % p.speed)

	var flashes_after: Array = tree.root.get_children().filter(func(c): return c is CPUParticles2D)
	if flashes_after.size() != flashes_before.size() + 1:
		failures.append("_spawn_projectile: expected exactly 1 new muzzle flash for a 4-submissile volley, got %d new" % (flashes_after.size() - flashes_before.size()))

	for c in tree.root.get_children():
		if (c == swarm_mount or (c is Projectile and not projectiles_before.has(c)) or (c is CPUParticles2D and not flashes_before.has(c))) and is_instance_valid(c):
			c.queue_free()

	for c in tree.root.get_children():
		if (c == target or c == mount or c is CPUParticles2D or c is Projectile) and is_instance_valid(c):
			c.queue_free()

	return failures
