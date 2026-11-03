extends RefCounted

# Shared layout assertions for hand-built UI panels (no test_ prefix: not a
# test file itself, preloaded by the panel tests).

# Theme-driven control sizes (e.g. the 8px button margins) must never push
# content outside the panel chrome or on top of other content.
static func check_panel_layout(panel: Control, failures: Array[String]) -> void:
	var bg_rect: Rect2 = panel.get_node("Background").get_global_rect()
	var controls: Array[Control] = []
	_collect_visible_widgets(panel, controls)
	# Compare what is actually drawn: ScrollContainer clips its content.
	var names: Array[String] = []
	var rects: Array[Rect2] = []
	for c in controls:
		var rect: Rect2 = c.get_global_rect()
		var scroll := _scroll_ancestor(c, panel)
		if scroll != null:
			rect = rect.intersection(scroll.get_global_rect())
			if not rect.has_area():
				continue
		if not bg_rect.encloses(rect):
			failures.append("%s: %s %s spills outside Background %s" % [panel.name, c.name, rect, bg_rect])
		names.append(c.name)
		rects.append(rect)
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				failures.append("%s: %s overlaps %s" % [panel.name, names[i], names[j]])

static func _collect_visible_widgets(node: Node, out: Array[Control]) -> void:
	for child in node.get_children():
		if not (child is Control) or not child.visible:
			continue
		if child is Button or child is Label:
			out.append(child)
		_collect_visible_widgets(child, out)

static func _scroll_ancestor(node: Node, stop_at: Node) -> ScrollContainer:
	var parent := node.get_parent()
	while parent != null and parent != stop_at:
		if parent is ScrollContainer:
			return parent
		parent = parent.get_parent()
	return null
