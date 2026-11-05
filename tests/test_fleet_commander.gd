extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	_check_ship_at_point(failures)
	_check_ships_in_rect(failures)
	_check_assign_slots(failures)
	_check_frustum_polygon(failures)
	_check_hatch_segments(failures)
	_check_frustum_mounts(failures)
	_check_order_hold(failures)
	_check_order_flee_skips_fled(failures)
	_check_set_formation_emits(failures)
	_check_selection_changed(failures)
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

	var drone := _make_ship(Vector2(5, 0))
	drone.player_targetable = false
	var picked_over_drone := FleetCommander.ship_at_point([drone, near], Vector2.ZERO, 50.0)
	if picked_over_drone != near:
		failures.append("ship_at_point: expected a non-player_targetable ship to be skipped, got %s" % picked_over_drone)
	var only_drone := FleetCommander.ship_at_point([drone], Vector2.ZERO, 50.0)
	if only_drone != null:
		failures.append("ship_at_point: expected null when the only candidate is not player_targetable, got %s" % only_drone)
	drone.free()

	# Dead ships stay in the commander's roster; 'is' on a freed instance is a script error.
	var dead := _make_ship(Vector2(1, 0))
	dead.free()
	var picked_past_dead := FleetCommander.ship_at_point([dead, near], Vector2.ZERO, 50.0)
	if picked_past_dead != near:
		failures.append("ship_at_point: expected a freed candidate to be skipped, got %s" % picked_past_dead)

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

static func _check_frustum_polygon(failures: Array[String]) -> void:
	var origin := Vector2(10, 0)
	var wedge := FleetCommander.frustum_polygon(origin, 0.0, 90.0, 100.0, 8)
	if wedge.size() != 10 or wedge[0] != origin:
		failures.append("frustum_polygon: expected the mount plus 9 arc points, got %s" % wedge)
	else:
		for i in range(1, wedge.size()):
			if not is_equal_approx(wedge[i].distance_to(origin), 100.0):
				failures.append("frustum_polygon: expected arc point %d at the weapon range, got %s" % [i, wedge[i]])
		if not is_equal_approx((wedge[1] - origin).angle(), deg_to_rad(-45.0)) or not is_equal_approx((wedge[9] - origin).angle(), deg_to_rad(45.0)):
			failures.append("frustum_polygon: expected the arc to span -45..45 degrees, got %s" % wedge)

	var turned := FleetCommander.frustum_polygon(Vector2.ZERO, PI / 2.0, 10.0, 100.0, 2)
	if turned.size() != 4 or not turned[2].is_equal_approx(Vector2(0, 100)):
		failures.append("frustum_polygon: expected the arc centred on the facing, got %s" % turned)

	var circle := FleetCommander.frustum_polygon(origin, 0.0, 360.0, 50.0, 16)
	if circle.size() != 16 or circle.has(origin):
		failures.append("frustum_polygon: expected a full arc to be a 16-point circle without the mount, got %s" % circle)
	for point in circle:
		if not is_equal_approx(point.distance_to(origin), 50.0):
			failures.append("frustum_polygon: expected circle points at the range, got %s" % point)
			break

static func _check_hatch_segments(failures: Array[String]) -> void:
	var square := PackedVector2Array([Vector2(5, 5), Vector2(105, 5), Vector2(105, 105), Vector2(5, 105)])
	var segments := FleetCommander.hatch_segments(square, 20.0)
	# Diagonal offsets across the square run 7.07..148.5, so lines sit at 20, 40 ... 140.
	if segments.size() != 14:
		failures.append("hatch_segments: expected 7 clipped lines, got %d points" % segments.size())
	var normal := Vector2(1, 1).normalized()
	for i in range(0, segments.size() - 1, 2):
		var a: Vector2 = segments[i]
		var b: Vector2 = segments[i + 1]
		if absf((b - a).dot(normal)) > 0.001:
			failures.append("hatch_segments: expected diagonal lines, got %s -> %s" % [a, b])
			break
		if not Geometry2D.is_point_in_polygon((a + b) / 2.0, square):
			failures.append("hatch_segments: expected lines clipped to the polygon, got %s -> %s" % [a, b])
			break
		# World-anchored: every line sits on a multiple of the spacing, wherever the polygon is.
		var offset := a.dot(normal) / 20.0
		if absf(offset - roundf(offset)) > 0.001:
			failures.append("hatch_segments: expected lines on world-fixed offsets, got offset %s" % (offset * 20.0))
			break
	if not FleetCommander.hatch_segments(PackedVector2Array(), 20.0).is_empty():
		failures.append("hatch_segments: expected no lines for an empty polygon")

static func _check_frustum_mounts(failures: Array[String]) -> void:
	var armed := WeaponMount.new()
	armed.weapon = Weapon.new()
	armed.current_hp = 5.0
	var empty := WeaponMount.new()
	empty.current_hp = 5.0
	var broken := WeaponMount.new()
	broken.weapon = Weapon.new()
	broken.current_hp = 0.0
	var mounts: Array[WeaponMount] = [armed, empty, broken]
	var shown := FleetCommander.frustum_mounts(mounts)
	if shown != [armed]:
		failures.append("frustum_mounts: expected only the armed, intact mount, got %s" % [shown])
	armed.free()
	empty.free()
	broken.free()

static func _selected_commander(ships: Array[Ship]) -> FleetCommander:
	var commander := FleetCommander.new()
	commander.selected_ships = ships
	return commander

static func _check_order_hold(failures: Array[String]) -> void:
	var a := _make_ship(Vector2.ZERO)
	var b := _make_ship(Vector2(50, 0))
	var commander := _selected_commander([a, b])
	commander.order_hold()
	for ship in [a, b]:
		if ship.current_order == null or ship.current_order.type != Order.Type.HOLD_POSITION:
			failures.append("order_hold: expected every selected ship on HOLD_POSITION, got %s" % [ship.current_order])
	if a.current_order != null and a.current_order == b.current_order:
		failures.append("order_hold: expected each ship to get its own Order")
	commander.free()
	a.free()
	b.free()

static func _check_order_flee_skips_fled(failures: Array[String]) -> void:
	var live := _make_ship(Vector2.ZERO)
	var fled := _make_ship(Vector2(50, 0))
	fled.has_fled = true
	var commander := _selected_commander([live, fled])
	commander.order_flee()
	if live.current_order == null or live.current_order.type != Order.Type.FLEE:
		failures.append("order_flee: expected the live ship on FLEE, got %s" % [live.current_order])
	if fled.current_order != null:
		failures.append("order_flee: expected the fled ship to get no order, got %s" % [fled.current_order])
	commander.free()
	live.free()
	fled.free()

static func _check_set_formation_emits(failures: Array[String]) -> void:
	var commander := FleetCommander.new()
	var seen: Array[int] = []
	commander.formation_changed.connect(func(type: Formation.Type): seen.append(type))
	commander.set_formation(Formation.Type.WEDGE)
	if commander.active_formation != Formation.Type.WEDGE or seen != [Formation.Type.WEDGE]:
		failures.append("set_formation: expected WEDGE active and formation_changed(WEDGE), got %s / %s" % [commander.active_formation, seen])
	commander.free()

static func _check_selection_changed(failures: Array[String]) -> void:
	var ship := _make_ship(Vector2.ZERO)
	var commander := FleetCommander.new()
	var seen: Array[bool] = []
	commander.selection_changed.connect(func(has_selection: bool): seen.append(has_selection))
	var picked: Array[Ship] = [ship]
	commander.selected_ships = picked
	commander._on_right_press()
	if seen != [true, false]:
		failures.append("selection_changed: expected true on select then false on right click, got %s" % [seen])
	# A selection holding only fled ships reads as none.
	var fled := _make_ship(Vector2(10, 0))
	fled.has_fled = true
	seen.clear()
	var only_fled: Array[Ship] = [fled]
	commander.selected_ships = only_fled
	if seen != [false]:
		failures.append("selection_changed: expected false for a selection of only fled ships, got %s" % [seen])
	commander.free()
	ship.free()
	fled.free()
