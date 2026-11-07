extends RefCounted

const OrderBarScene = preload("res://scenes/ui/order_bar.tscn")
const UiLayoutCheck = preload("res://tests/ui_layout_check.gd")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	await _check_buttons_disabled_without_selection(tree, failures)
	await _check_formation_popup_opens_and_closes(tree, failures)
	await _check_label_tracks_formation(tree, failures)
	await _check_bar_inside_viewport_and_stops_mouse(tree, failures)
	await _check_new_buttons_emit(tree, failures)
	await _check_show_armed_tracks_pressed_state(tree, failures)
	return failures

static func _open(tree: SceneTree) -> OrderBar:
	# The headless root viewport is tiny; a host the size of the real window makes the anchors resolve.
	var host := Control.new()
	host.size = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	tree.root.add_child(host)
	var bar: OrderBar = OrderBarScene.instantiate()
	host.add_child(bar)
	await tree.process_frame
	return bar

static func _check_buttons_disabled_without_selection(tree: SceneTree, failures: Array[String]) -> void:
	var bar := await _open(tree)
	var hold: Button = bar.get_node("Row/HoldButton")
	var flee: Button = bar.get_node("Row/FleeButton")
	if not hold.disabled or not flee.disabled:
		failures.append("order bar: expected Hold and Flee disabled with no selection, got hold=%s flee=%s" % [hold.disabled, flee.disabled])
	bar.set_has_selection(true)
	if hold.disabled or flee.disabled:
		failures.append("order bar: expected Hold and Flee enabled with a selection")
	var presses: Array[String] = []
	bar.hold_pressed.connect(func(): presses.append("hold"))
	bar.flee_pressed.connect(func(): presses.append("flee"))
	hold.pressed.emit()
	flee.pressed.emit()
	if presses != ["hold", "flee"]:
		failures.append("order bar: expected hold_pressed then flee_pressed, got %s" % [presses])
	bar.set_has_selection(false)
	if not hold.disabled or not flee.disabled:
		failures.append("order bar: expected Hold and Flee disabled again once the selection clears")
	bar.get_parent().queue_free()

static func _check_formation_popup_opens_and_closes(tree: SceneTree, failures: Array[String]) -> void:
	var bar := await _open(tree)
	var popup: Control = bar.get_node("Popup")
	var button: Button = bar.get_node("Row/FormationButton")
	var picks: Array[int] = []
	bar.formation_picked.connect(func(type: Formation.Type): picks.append(type))
	if popup.visible:
		failures.append("formation popup: expected it hidden at start")
	button.pressed.emit()
	if not popup.visible:
		failures.append("formation popup: expected the Formation button to open it")
	var buttons: Array[Node] = bar.get_node("Popup/Buttons").get_children()
	if buttons.size() != 5 or buttons[3].text != "Box 4" or buttons[0].text != "Free 1" or buttons[4].text != "Circle 5":
		failures.append("formation popup: expected 5 buttons 'Free 1'..'Circle 5', got %s" % [buttons.map(func(b): return b.text)])
	else:
		buttons[3].pressed.emit()
		if picks != [Formation.Type.BOX]:
			failures.append("formation popup: expected picking Box to emit BOX once, got %s" % [picks])
		if popup.visible:
			failures.append("formation popup: expected picking a formation to close it")
	button.pressed.emit()
	button.pressed.emit()
	if popup.visible:
		failures.append("formation popup: expected a second Formation click to close it")
	bar.get_parent().queue_free()

static func _check_label_tracks_formation(tree: SceneTree, failures: Array[String]) -> void:
	var bar := await _open(tree)
	var button: Button = bar.get_node("Row/FormationButton")
	if button.text != "Formation: Free ^":
		failures.append("order bar label: expected 'Formation: Free ^' at start, got '%s'" % button.text)
	bar.show_formation(Formation.Type.LINE)
	if button.text != "Formation: Line ^":
		failures.append("order bar label: expected 'Formation: Line ^', got '%s'" % button.text)
	var buttons: Array[Node] = bar.get_node("Popup/Buttons").get_children()
	if buttons.size() != 5 or not buttons[1].button_pressed or buttons[0].button_pressed:
		failures.append("order bar label: expected only the Line popup button highlighted")
	bar.get_parent().queue_free()

static func _check_bar_inside_viewport_and_stops_mouse(tree: SceneTree, failures: Array[String]) -> void:
	var bar := await _open(tree)
	var viewport := Rect2(Vector2.ZERO, (bar.get_parent() as Control).size)
	var background: Control = bar.get_node("Background")
	if not viewport.encloses(background.get_global_rect()):
		failures.append("order bar: expected the bar inside the viewport %s, got %s" % [viewport, background.get_global_rect()])
	if background.mouse_filter != Control.MOUSE_FILTER_STOP:
		failures.append("order bar: expected the Background to stop mouse input, got filter %s" % background.mouse_filter)
	UiLayoutCheck.check_panel_layout(bar, failures)
	bar.get_node("Row/FormationButton").pressed.emit()
	await tree.process_frame
	var popup_background: Control = bar.get_node("Popup/PopupBackground")
	if popup_background.mouse_filter != Control.MOUSE_FILTER_STOP:
		failures.append("order bar: expected the popup background to stop mouse input, got filter %s" % popup_background.mouse_filter)
	var popup_rect: Rect2 = popup_background.get_global_rect()
	if not viewport.encloses(popup_rect):
		failures.append("order bar: expected the open popup inside the viewport %s, got %s" % [viewport, popup_rect])
	for b in bar.get_node("Popup/Buttons").get_children():
		if not popup_rect.encloses(b.get_global_rect()):
			failures.append("order bar: popup button '%s' %s spills outside the popup %s" % [b.text, b.get_global_rect(), popup_rect])
	if popup_rect.intersects(background.get_global_rect()):
		failures.append("order bar: expected the popup above the bar, not overlapping it")
	bar.get_parent().queue_free()

static func _check_new_buttons_emit(tree: SceneTree, failures: Array[String]) -> void:
	var bar := await _open(tree)
	var move_btn: Button = bar.get_node("Row/MoveButton")
	var attack_btn: Button = bar.get_node("Row/AttackButton")
	var protect_btn: Button = bar.get_node("Row/ProtectButton")
	var presses: Array[String] = []
	bar.move_pressed.connect(func(): presses.append("move"))
	bar.attack_pressed.connect(func(): presses.append("attack"))
	bar.protect_pressed.connect(func(): presses.append("protect"))
	move_btn.pressed.emit()
	attack_btn.pressed.emit()
	protect_btn.pressed.emit()
	if presses != ["move", "attack", "protect"]:
		failures.append("order bar: expected move_pressed, attack_pressed, protect_pressed in order, got %s" % [presses])
	bar.get_parent().queue_free()

static func _check_show_armed_tracks_pressed_state(tree: SceneTree, failures: Array[String]) -> void:
	var bar := await _open(tree)
	var move_btn: Button = bar.get_node("Row/MoveButton")
	var attack_btn: Button = bar.get_node("Row/AttackButton")
	var protect_btn: Button = bar.get_node("Row/ProtectButton")
	bar.show_armed(true, Order.Type.ATTACK_TARGET)
	if move_btn.button_pressed or not attack_btn.button_pressed or protect_btn.button_pressed:
		failures.append("order bar: expected only Attack pressed when ATTACK_TARGET is armed, got move=%s attack=%s protect=%s" % [move_btn.button_pressed, attack_btn.button_pressed, protect_btn.button_pressed])
	bar.show_armed(false, Order.Type.ATTACK_TARGET)
	if move_btn.button_pressed or attack_btn.button_pressed or protect_btn.button_pressed:
		failures.append("order bar: expected all three cleared when nothing is armed, got move=%s attack=%s protect=%s" % [move_btn.button_pressed, attack_btn.button_pressed, protect_btn.button_pressed])
	bar.get_parent().queue_free()
