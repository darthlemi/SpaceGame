extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	_check_line(failures)
	_check_wedge(failures)
	_check_box(failures)
	_check_circle(failures)
	return failures

static func _check_line(failures: Array[String]) -> void:
	var anchor := Vector2(100, 100)
	var facing := Vector2.RIGHT
	var slots := Formation.compute_slots(Formation.Type.LINE, 3, anchor, facing, 50.0, 0.0)
	if slots.size() != 3:
		failures.append("LINE: expected 3 slots, got %d" % slots.size())
		return
	for slot in slots:
		var along: float = (slot - anchor).dot(facing)
		if not is_equal_approx(along, 0.0):
			failures.append("LINE: expected slot perpendicular to facing, got along-facing offset %s" % along)
	if not is_equal_approx(slots[0].distance_to(slots[1]), 50.0):
		failures.append("LINE: expected 50.0 spacing between slots 0 and 1, got %s" % slots[0].distance_to(slots[1]))
	if not is_equal_approx(slots[1].distance_to(slots[2]), 50.0):
		failures.append("LINE: expected 50.0 spacing between slots 1 and 2, got %s" % slots[1].distance_to(slots[2]))

static func _check_wedge(failures: Array[String]) -> void:
	var anchor := Vector2(0, 0)
	var facing := Vector2.RIGHT
	var slots := Formation.compute_slots(Formation.Type.WEDGE, 3, anchor, facing, 50.0, 0.0)
	if slots.size() != 3:
		failures.append("WEDGE: expected 3 slots, got %d" % slots.size())
		return
	if not slots[0].is_equal_approx(anchor):
		failures.append("WEDGE: expected apex slot at anchor, got %s" % slots[0])
	for i in range(1, slots.size()):
		var along: float = (slots[i] - anchor).dot(facing)
		if along >= 0.0:
			failures.append("WEDGE: expected trailing slot %d behind the apex, got along-facing offset %s" % [i, along])

static func _check_box(failures: Array[String]) -> void:
	var anchor := Vector2(0, 0)
	var slots := Formation.compute_slots(Formation.Type.BOX, 4, anchor, Vector2.RIGHT, 50.0, 0.0)
	if slots.size() != 4:
		failures.append("BOX: expected 4 slots, got %d" % slots.size())
		return
	var max_dist := 0.0
	for slot in slots:
		max_dist = max(max_dist, slot.distance_to(anchor))
	if max_dist > 100.0:
		failures.append("BOX: expected slots within a tight grid of anchor, farthest slot was %s away" % max_dist)

static func _check_circle(failures: Array[String]) -> void:
	var anchor := Vector2(0, 0)
	var slots := Formation.compute_slots(Formation.Type.CIRCLE, 4, anchor, Vector2.RIGHT, 50.0, 0.0)
	if slots.size() != 4:
		failures.append("CIRCLE: expected 4 slots, got %d" % slots.size())
		return
	for slot in slots:
		if not is_equal_approx(slot.distance_to(anchor), 50.0):
			failures.append("CIRCLE: expected slot at radius 50.0 from anchor, got %s" % slot.distance_to(anchor))
