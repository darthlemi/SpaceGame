extends RefCounted

const VIEW := Vector2(1152, 648)
const ARENA := Vector2(2304, 1296)

static func run() -> Array[String]:
	var failures: Array[String] = []
	_check_fit_zoom(failures)
	_check_clamp_center(failures)
	_check_min_zoom(failures)
	_check_zoom_about(failures)
	_check_edge_pan_dir(failures)
	_check_edge_blip(failures)
	return failures

static func _check_fit_zoom(failures: Array[String]) -> void:
	if not is_equal_approx(CombatCamera.fit_zoom(VIEW, ARENA), 0.5):
		failures.append("fit_zoom: expected 0.5 for a 2x arena, got %s" % CombatCamera.fit_zoom(VIEW, ARENA))
	# The tighter axis wins: a wide arena is limited by its height.
	var wide := CombatCamera.fit_zoom(VIEW, Vector2(4608, 1296))
	if not is_equal_approx(wide, 0.5):
		failures.append("fit_zoom: expected 0.5 (height-bound) for a wide arena, got %s" % wide)

static func _check_clamp_center(failures: Array[String]) -> void:
	var inside := CombatCamera.clamp_center(Vector2(1000, 600), VIEW, 1.0, ARENA)
	if not inside.is_equal_approx(Vector2(1000, 600)):
		failures.append("clamp_center: expected an in-bounds centre unchanged, got %s" % inside)
	var corner := CombatCamera.clamp_center(Vector2(-500, 5000), VIEW, 1.0, ARENA)
	if not corner.is_equal_approx(Vector2(576, 972)):
		failures.append("clamp_center: expected (576, 972) so the view stays inside, got %s" % corner)
	# Zoomed out past the arena: the view is centred instead of clamped to a negative range.
	var wider := CombatCamera.clamp_center(Vector2(0, 0), VIEW, 0.25, ARENA)
	if not wider.is_equal_approx(ARENA / 2.0):
		failures.append("clamp_center: expected the arena centre when the view is larger, got %s" % wider)

static func _check_zoom_about(failures: Array[String]) -> void:
	var centre := Vector2(1000, 600)
	var cursor := Vector2(900, 100)
	var old_zoom := 0.75
	var new_zoom := 1.5
	var world_before := centre + (cursor - VIEW / 2.0) / old_zoom
	var moved := CombatCamera.zoom_about(centre, VIEW, cursor, old_zoom, new_zoom)
	var world_after := moved + (cursor - VIEW / 2.0) / new_zoom
	if not world_after.is_equal_approx(world_before):
		failures.append("zoom_about: expected the point under the cursor to stay put, %s -> %s" % [world_before, world_after])
	var centred := CombatCamera.zoom_about(centre, VIEW, VIEW / 2.0, old_zoom, new_zoom)
	if not centred.is_equal_approx(centre):
		failures.append("zoom_about: expected zooming at the screen centre to keep the centre, got %s" % centred)

static func _check_edge_pan_dir(failures: Array[String]) -> void:
	var cases := {
		Vector2(576, 324): Vector2.ZERO,
		Vector2(0, 324): Vector2(-1, 0),
		Vector2(1151, 324): Vector2(47.0 / 48.0, 0),
		Vector2(24, 324): Vector2(-0.5, 0),
		Vector2(0, 647): Vector2(-1, 47.0 / 48.0),
		Vector2(-5, 324): Vector2.ZERO,  # cursor left the window
	}
	for cursor in cases:
		var got := CombatCamera.edge_pan_dir(cursor, VIEW, 48.0)
		if not got.is_equal_approx(cases[cursor]):
			failures.append("edge_pan_dir: expected %s at %s, got %s" % [cases[cursor], cursor, got])

static func _check_edge_blip(failures: Array[String]) -> void:
	var centre := Vector2(1000, 600)
	if not OffscreenBlips.edge_blip(Vector2(1100, 650), centre, VIEW, 1.0, 14.0).is_empty():
		failures.append("edge_blip: expected no blip for an on-screen ship")
	var right := OffscreenBlips.edge_blip(Vector2(5000, 600), centre, VIEW, 1.0, 14.0)
	if right.is_empty() or not (right["pos"] as Vector2).is_equal_approx(Vector2(1138, 324)):
		failures.append("edge_blip: expected (1138, 324) for a ship far right, got %s" % [right])
	var corner := OffscreenBlips.edge_blip(Vector2(-4000, -4000), centre, VIEW, 1.0, 14.0)
	var pos: Vector2 = corner["pos"]
	if pos.x < 14.0 or pos.y < 14.0 or pos.x > VIEW.x - 14.0 or pos.y > VIEW.y - 14.0:
		failures.append("edge_blip: expected the corner blip inside the inset view, got %s" % pos)

static func _check_min_zoom(failures: Array[String]) -> void:
	# Fullscreen 16:9 on the square arena: at min zoom the view must still be narrower than the arena.
	var big_view := Vector2(2560, 1440)
	var square := Vector2(3200, 3200)
	var z := CombatCamera.min_zoom(big_view, square)
	if big_view.x / z >= square.x or big_view.y / z >= square.y:
		failures.append("min_zoom: expected the view to fit inside the arena on both axes, zoom %s" % z)
	if CombatCamera.min_zoom(Vector2(9000, 9000), square) > CombatCamera.MAX_ZOOM:
		failures.append("min_zoom: expected a cap at MAX_ZOOM")
