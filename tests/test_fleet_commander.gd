extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	_check_ship_at_point(failures)
	_check_ships_in_rect(failures)
	_check_assign_slots(failures)
	return failures

static func _make_ship(pos: Vector2) -> Ship:
	var ship := Ship.new()
	ship.position = pos
	return ship

static func _check_ship_at_point(failures: Array[String]) -> void:
	var near := _make_ship(Vector2(10, 0))
	var far := _make_ship(Vector2(200, 0))
	var picked := FleetCommander.ship_at_point([far, near], Vector2.ZERO, 50.0)
	if picked != near:
		failures.append("ship_at_point: expected the nearest ship within radius, got %s" % picked)
	var none := FleetCommander.ship_at_point([far], Vector2.ZERO, 50.0)
	if none != null:
		failures.append("ship_at_point: expected null when nothing is within radius, got %s" % none)
	near.free()
	far.free()

static func _check_ships_in_rect(failures: Array[String]) -> void:
	var inside := _make_ship(Vector2(10, 10))
	var outside := _make_ship(Vector2(1000, 1000))
	var rect := Rect2(Vector2(0, 0), Vector2(50, 50))
	var result := FleetCommander.ships_in_rect([inside, outside], rect)
	if result.size() != 1 or result[0] != inside:
		failures.append("ships_in_rect: expected only the ship inside the rect, got %s" % [result])
	inside.free()
	outside.free()

static func _check_assign_slots(failures: Array[String]) -> void:
	var ship_a := _make_ship(Vector2(0, 0))
	var ship_b := _make_ship(Vector2(100, 0))
	var slots: Array[Vector2] = [Vector2(90, 0), Vector2(0, 5)]
	var assignment := FleetCommander.assign_slots([ship_a, ship_b], slots)
	if assignment.get(ship_a) != Vector2(0, 5):
		failures.append("assign_slots: expected ship_a assigned its nearest slot (0,5), got %s" % assignment.get(ship_a))
	if assignment.get(ship_b) != Vector2(90, 0):
		failures.append("assign_slots: expected ship_b assigned its nearest slot (90,0), got %s" % assignment.get(ship_b))
	ship_a.free()
	ship_b.free()
