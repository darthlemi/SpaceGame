extends RefCounted

const AttackDroneScene = preload("res://scenes/drones/attack_drone.tscn")
const InterceptorDroneScene = preload("res://scenes/drones/interceptor_drone.tscn")
const BomberDroneScene = preload("res://scenes/drones/bomber_drone.tscn")
const EwDroneScene = preload("res://scenes/drones/ew_drone.tscn")
const BomberDrone = preload("res://scripts/drones/bomber_drone.gd")
const EwDrone = preload("res://scripts/drones/ew_drone.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var attack: Ship = AttackDroneScene.instantiate()
	attack._ready()
	if attack.player_targetable:
		failures.append("attack_drone.tscn: expected player_targetable false")
	if attack.hull == null or not is_equal_approx(attack.hull.max_hp, 15.0):
		failures.append("attack_drone.tscn: expected Hull max_hp 15.0")
	attack.free()

	var interceptor: Ship = InterceptorDroneScene.instantiate()
	interceptor._ready()
	if interceptor.player_targetable:
		failures.append("interceptor_drone.tscn: expected player_targetable false")
	if interceptor.hull == null or not is_equal_approx(interceptor.hull.max_hp, 8.0):
		failures.append("interceptor_drone.tscn: expected Hull max_hp 8.0")
	interceptor.free()

	var bomber: BomberDrone = BomberDroneScene.instantiate()
	if not (bomber is BomberDrone):
		failures.append("bomber_drone.tscn: expected root script BomberDrone")
	if bomber.payload_weapon == null or not is_equal_approx(bomber.payload_weapon.damage, 40.0):
		failures.append("bomber_drone.tscn: expected payload_weapon damage 40.0")
	bomber.free()

	var ew: EwDrone = EwDroneScene.instantiate()
	if not (ew is EwDrone):
		failures.append("ew_drone.tscn: expected root script EwDrone")
	ew.free()

	return failures
