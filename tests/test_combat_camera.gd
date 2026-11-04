extends RefCounted

const VIEW := Vector2(1152, 648)
const ARENA := Vector2(2304, 1296)

static func run() -> Array[String]:
	var failures: Array[String] = []
	_check_fit_zoom(failures)
	_check_clamp_center(failures)
	_check_zoom_about(failures)
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
