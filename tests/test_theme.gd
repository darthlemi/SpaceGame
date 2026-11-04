extends RefCounted

const THEME_PATH := "res://assets/ui/theme.tres"
const TEXT_COLOR := Color("#9fd0ff")
const DIM_ACCENT := Color("#1a4e8a")

static func run() -> Array[String]:
	var failures: Array[String] = []
	var theme: Theme = load(THEME_PATH)
	if theme == null:
		failures.append("theme: failed to load %s" % THEME_PATH)
		return failures

	var boxes := {
		"Panel/panel": theme.get_stylebox("panel", "Panel"),
		"Button/normal": theme.get_stylebox("normal", "Button"),
		"Button/hover": theme.get_stylebox("hover", "Button"),
		"Button/pressed": theme.get_stylebox("pressed", "Button"),
		"Button/disabled": theme.get_stylebox("disabled", "Button"),
	}
	for key in boxes:
		_check_stylebox(key, boxes[key], failures)

	_check_color(theme, "font_color", "Button", TEXT_COLOR, failures)
	_check_color(theme, "font_hover_color", "Button", Color.WHITE, failures)
	_check_color(theme, "font_pressed_color", "Button", Color.WHITE, failures)
	_check_color(theme, "font_hover_pressed_color", "Button", Color.WHITE, failures)
	_check_color(theme, "font_disabled_color", "Button", DIM_ACCENT, failures)
	_check_color(theme, "font_color", "Label", TEXT_COLOR, failures)
	return failures

static func _check_stylebox(key: String, box: StyleBox, failures: Array[String]) -> void:
	var tex_box := box as StyleBoxTexture
	if tex_box == null:
		failures.append("theme %s: expected StyleBoxTexture, got %s" % [key, box])
		return
	var tex := tex_box.texture
	if tex == null:
		failures.append("theme %s: texture is null" % key)
		return
	var margin_w := tex_box.texture_margin_left + tex_box.texture_margin_right
	var margin_h := tex_box.texture_margin_top + tex_box.texture_margin_bottom
	if margin_w >= tex.get_width():
		failures.append("theme %s: horizontal margins %s leave no centre in %d px" % [key, margin_w, tex.get_width()])
	if margin_h >= tex.get_height():
		failures.append("theme %s: vertical margins %s leave no centre in %d px" % [key, margin_h, tex.get_height()])
	# Tiling keeps scanline and dash pitch; stretching smears the pattern.
	if tex_box.axis_stretch_horizontal != StyleBoxTexture.AXIS_STRETCH_MODE_TILE:
		failures.append("theme %s: axis_stretch_horizontal is %d, expected TILE" % [key, tex_box.axis_stretch_horizontal])
	if tex_box.axis_stretch_vertical != StyleBoxTexture.AXIS_STRETCH_MODE_TILE:
		failures.append("theme %s: axis_stretch_vertical is %d, expected TILE" % [key, tex_box.axis_stretch_vertical])

static func _check_color(theme: Theme, color_name: String, type_name: String, expected: Color, failures: Array[String]) -> void:
	var actual := theme.get_color(color_name, type_name)
	if not actual.is_equal_approx(expected):
		failures.append("theme %s/%s: expected %s, got %s" % [type_name, color_name, expected.to_html(), actual.to_html()])
