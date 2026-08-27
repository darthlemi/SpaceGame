class_name Formation
extends RefCounted

enum Type { NONE, LINE, WEDGE, BOX, CIRCLE }

static func compute_slots(type: Type, count: int, anchor: Vector2, facing: Vector2, spacing: float, slop: float) -> Array[Vector2]:
	var effective_facing := facing if facing.length() > 0.01 else Vector2.RIGHT
	effective_facing = effective_facing.normalized()
	var slots: Array[Vector2] = []
	match type:
		Type.LINE:
			slots = _line_slots(count, anchor, effective_facing, spacing)
		Type.WEDGE:
			slots = _wedge_slots(count, anchor, effective_facing, spacing)
		Type.CIRCLE:
			slots = _circle_slots(count, anchor, spacing)
		_:
			slots = _box_slots(count, anchor, effective_facing, spacing)
	if slop > 0.0:
		for i in slots.size():
			var jitter := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * spacing * slop
			slots[i] += jitter
	return slots

static func _line_slots(count: int, anchor: Vector2, facing: Vector2, spacing: float) -> Array[Vector2]:
	var perpendicular := facing.rotated(PI / 2.0)
	var slots: Array[Vector2] = []
	var center_index := (count - 1) / 2.0
	for i in count:
		slots.append(anchor + perpendicular * spacing * (i - center_index))
	return slots

static func _wedge_slots(count: int, anchor: Vector2, facing: Vector2, spacing: float) -> Array[Vector2]:
	var perpendicular := facing.rotated(PI / 2.0)
	var slots: Array[Vector2] = [anchor]
	for i in range(1, count):
		var rank := ceili(i / 2.0)
		var side := 1.0 if i % 2 == 1 else -1.0
		slots.append(anchor - facing * spacing * rank + perpendicular * spacing * rank * side)
	return slots

static func _box_slots(count: int, anchor: Vector2, facing: Vector2, spacing: float) -> Array[Vector2]:
	var perpendicular := facing.rotated(PI / 2.0)
	var columns := ceili(sqrt(count))
	var row_count := ceili(float(count) / columns)
	var slots: Array[Vector2] = []
	for i in count:
		var row := i / columns
		var col := i % columns
		var row_offset := row - (row_count - 1) / 2.0
		var col_offset := col - (columns - 1) / 2.0
		slots.append(anchor + perpendicular * spacing * col_offset - facing * spacing * row_offset)
	return slots

static func _circle_slots(count: int, anchor: Vector2, spacing: float) -> Array[Vector2]:
	var slots: Array[Vector2] = []
	var angle_step := TAU / count
	for i in count:
		slots.append(anchor + Vector2(spacing, 0).rotated(angle_step * i))
	return slots
