extends RefCounted

const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")
const JettisonPanelScene = preload("res://scenes/campaign/jettison_panel.tscn")
const UiLayoutCheck = preload("res://tests/ui_layout_check.gd")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var panel = JettisonPanelScene.instantiate()
	tree.root.add_child(panel)
	# Standalone it has no parent rect to fill; give it the fleet panel's size.
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.size = Vector2(500, 500)
	await tree.process_frame
	if panel.visible:
		failures.append("JettisonPanel: expected hidden by default")

	var fleet := CampaignFleet.new()
	var capital := ShipType.new_composition(ShipType.Kind.CAPITAL)
	var freighter := ShipType.new_composition(ShipType.Kind.FREIGHTER)
	fleet.ship_compositions.assign([capital, freighter])
	fleet.set_flagship(0)
	fleet.cargo = {Commodity.Type.ORE: 10.0, Commodity.Type.FOOD: 4.0}
	fleet.part_inventory.assign(["res://resources/weapons/kinetic_cannon.tres"])

	var results: Array = []
	panel.finished.connect(func(confirmed: bool): results.append(confirmed))
	panel.open_for(fleet, 5.0)
	await tree.process_frame
	if not panel.visible:
		failures.append("JettisonPanel: expected visible after open_for")
	if panel.cargo_rows.size() != 2 or panel.crew_rows.size() != 2 or panel.part_checks.size() != 1:
		failures.append("JettisonPanel: expected 2 cargo rows, 2 crew checks, 1 part check, got %d/%d/%d" % [panel.cargo_rows.size(), panel.crew_rows.size(), panel.part_checks.size()])
		panel.queue_free()
		return failures
	if not panel.confirm_button.disabled:
		failures.append("JettisonPanel: expected confirm disabled with nothing selected")
	var ore_slider: HSlider = panel.cargo_rows[0]["slider"]
	ore_slider.value = 3
	if not panel.confirm_button.disabled:
		failures.append("JettisonPanel: expected confirm disabled at 3 of 5 required")
	ore_slider.value = 5
	if panel.confirm_button.disabled:
		failures.append("JettisonPanel: expected confirm enabled at 5 of 5 required")
	await tree.process_frame
	UiLayoutCheck.check_panel_layout(panel, failures)

	panel.confirm_button.pressed.emit()
	if not is_equal_approx(fleet.cargo[Commodity.Type.ORE], 5.0):
		failures.append("JettisonPanel: expected 5 ore jettisoned, got %s" % fleet.cargo[Commodity.Type.ORE])
	if results != [true]:
		failures.append("JettisonPanel: expected one finished(true), got %s" % [results])
	if panel.visible:
		failures.append("JettisonPanel: expected hidden after confirm")

	# Parts count as one cargo unit each, and cancel changes nothing.
	panel.open_for(fleet, 1.0)
	await tree.process_frame
	panel.part_checks[0].button_pressed = true
	if panel.confirm_button.disabled:
		failures.append("JettisonPanel: expected a checked part to satisfy 1 required")
	panel.cancel_button.pressed.emit()
	if fleet.part_inventory.size() != 1 or results != [true, false]:
		failures.append("JettisonPanel: expected cancel to change nothing and emit finished(false), got %s" % [results])

	# Crew: slider max honours the flagship floor, and a partial amount applies exactly.
	var crew_fleet := CampaignFleet.new()
	var crew_capital := ShipType.new_composition(ShipType.Kind.CAPITAL)
	var corvette := ShipType.new_composition(ShipType.Kind.CORVETTE)
	crew_capital["crew"] = 40
	corvette["crew"] = 10
	crew_fleet.ship_compositions.assign([crew_capital, corvette])
	crew_fleet.set_flagship(0)
	panel.open_for(crew_fleet, 0.0)
	await tree.process_frame
	var flagship_slider: HSlider = panel.crew_rows[0]["slider"]
	var corvette_slider: HSlider = panel.crew_rows[1]["slider"]
	if flagship_slider.max_value != 40 - campaign_state.flagship_floor(crew_fleet) or corvette_slider.max_value != 10:
		failures.append("JettisonPanel: expected crew slider maxes 28 and 10, got %s / %s" % [flagship_slider.max_value, corvette_slider.max_value])
	corvette_slider.value = 3
	panel.confirm_button.pressed.emit()
	if CrewRules.crew_of(crew_fleet.ship_compositions[1]) != 7 or CrewRules.crew_of(crew_fleet.ship_compositions[0]) != 40:
		failures.append("JettisonPanel: expected partial crew jettison 10 -> 7 and flagship untouched, got %d / %d" % [CrewRules.crew_of(crew_fleet.ship_compositions[1]), CrewRules.crew_of(crew_fleet.ship_compositions[0])])

	campaign_state.reset()
	panel.queue_free()
	return failures
