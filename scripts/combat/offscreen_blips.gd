class_name OffscreenBlips
extends Control

# Edge-of-screen markers for ships outside the camera view: small triangles pointing
# toward each off-screen ship, blue for the player's fleet and red for the enemy.

const BLIP_SIZE := 9.0
const EDGE_INSET := 14.0
const FRIENDLY_COLOR := Color(0.35, 0.6, 1.0, 0.9)
const ENEMY_COLOR := Color(1.0, 0.3, 0.3, 0.9)

var camera: Camera2D = null
var friendly_group: StringName = &""
var enemy_group: StringName = &""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep updating while the fight is paused

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if camera == null:
		return
	_draw_group(enemy_group, ENEMY_COLOR)
	_draw_group(friendly_group, FRIENDLY_COLOR)

func _draw_group(group: StringName, color: Color) -> void:
	var view := get_viewport_rect().size
	for member in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(member) or member.is_queued_for_deletion() or member.has_fled:
			continue
		var blip := edge_blip(member.global_position, camera.position, view, camera.zoom.x, EDGE_INSET)
		if blip.is_empty():
			continue
		var forward := Vector2.RIGHT.rotated(blip["angle"])
		var side := forward.orthogonal()
		var tip: Vector2 = blip["pos"] + forward * BLIP_SIZE
		var base: Vector2 = blip["pos"] - forward * BLIP_SIZE * 0.6
		draw_colored_polygon(PackedVector2Array([tip, base + side * BLIP_SIZE * 0.7,
			base - side * BLIP_SIZE * 0.7]), color)

# Where a world point's blip sits on the screen edge, or {} when the point is on screen.
# "pos" is the screen position inset from the edge; "angle" points from the view centre to
# the ship.
static func edge_blip(world: Vector2, centre: Vector2, view: Vector2, zoom_level: float, inset: float) -> Dictionary:
	var offset := (world - centre) * zoom_level
	var half := view / 2.0
	if absf(offset.x) <= half.x and absf(offset.y) <= half.y:
		return {}
	var limit := half - Vector2.ONE * inset
	var scale := minf(limit.x / maxf(absf(offset.x), 0.001), limit.y / maxf(absf(offset.y), 0.001))
	return {"pos": half + offset * scale, "angle": offset.angle()}
