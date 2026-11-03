extends RefCounted

const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")
const FleetManagementPanelScene = preload("res://scenes/campaign/fleet_management_panel.tscn")
const UiLayoutCheck = preload("res://tests/ui_layout_check.gd")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var panel = FleetManagementPanelScene.instantiate()
	tree.root.add_child(panel)
	await tree.process_frame
	if panel.visible:
		failures.append("FleetManagementPanel: expected hidden by default")

	var fleet := _make_fleet(6, 40, 6)
	panel.open_for(fleet, null)
	await tree.process_frame
	if not panel.visible:
		failures.append("FleetManagementPanel: expected visible after open_for")
	if panel.rows.size() != 3:
		failures.append("FleetManagementPanel: expected 3 rows, got %d" % panel.rows.size())
		panel.queue_free()
		return failures
	if panel.hire_row.visible:
		failures.append("FleetManagementPanel: expected hire row hidden when not docked")
	if not panel.rows[1]["flagship_button"].disabled:
		failures.append("FleetManagementPanel: expected the flagship's button disabled")
	if panel.rows[0]["label"].text != "Corvette 1":
		failures.append("FleetManagementPanel: expected label 'Corvette 1', got '%s'" % panel.rows[0]["label"].text)
	if panel.rows[0]["count_label"].text != "6/12 (min 4)":
		failures.append("FleetManagementPanel: unexpected count label '%s'" % panel.rows[0]["count_label"].text)

	panel.rows[0]["slider"].value = 12
	if CrewRules.crew_of(fleet.ship_compositions[0]) != 12 or fleet.crew_total() != 52:
		failures.append("FleetManagementPanel: expected corvette 12 and total 52, got %d / %d" % [CrewRules.crew_of(fleet.ship_compositions[0]), fleet.crew_total()])

	panel.balance_button.pressed.emit()
	var lo := 999.0
	var hi := -1.0
	for comp in fleet.ship_compositions:
		var expected_share: float = 52.0 * CrewRules.complement(comp) / fleet.crew_capacity()
		lo = minf(lo, CrewRules.crew_of(comp) - expected_share)
		hi = maxf(hi, CrewRules.crew_of(comp) - expected_share)
	if hi - lo >= 2.0 or fleet.crew_total() != 52:
		failures.append("FleetManagementPanel: expected Balance to equalize fractions within one crew")

	# Under the deploy minimum.
	fleet.ship_compositions[0]["crew"] = 2
	panel.refresh()
	var check: CheckBox = panel.rows[0]["deploy_check"]
	if not check.disabled or check.text != "Too few":
		failures.append("FleetManagementPanel: expected disabled 'Too few' check, got disabled=%s text='%s'" % [check.disabled, check.text])
	var freighter_check: CheckBox = panel.rows[2]["deploy_check"]
	freighter_check.button_pressed = false
	if fleet.ship_compositions[2].get("deploy", true) != false:
		failures.append("FleetManagementPanel: expected unchecking to set deploy false")
	panel.refresh()
	if panel.rows[2]["deploy_check"].button_pressed:
		failures.append("FleetManagementPanel: expected refreshed check to stay unchecked")

	panel.rows[2]["flagship_button"].pressed.emit()
	if fleet.flagship_index() != 2:
		failures.append("FleetManagementPanel: expected flagship_index 2, got %d" % fleet.flagship_index())
	if not panel.rows[2]["flagship_button"].disabled or panel.rows[1]["flagship_button"].disabled:
		failures.append("FleetManagementPanel: expected flagship button state to follow the new flagship")

	# Docked: hiring.
	var economy := BaseEconomy.new()
	economy.crew_pool = 10.0
	campaign_state.credits = 500.0
	var hire_fleet := _make_fleet(6, 40, 6)
	panel.open_for(hire_fleet, economy)
	await tree.process_frame
	if not panel.hire_row.visible:
		failures.append("FleetManagementPanel: expected hire row visible when docked")
	panel.hire_count.value = 3
	panel.hire_button.pressed.emit()
	if hire_fleet.crew_total() != 55 or not is_equal_approx(campaign_state.credits, 500.0 - 3 * campaign_state.CREW_HIRE_COST):
		failures.append("FleetManagementPanel: expected hire of 3 to add crew and charge credits, got crew %d credits %s" % [hire_fleet.crew_total(), campaign_state.credits])
	if not panel.header_label.text.begins_with("Crew 55 / 58"):
		failures.append("FleetManagementPanel: expected header to update, got '%s'" % panel.header_label.text)
	await tree.process_frame
	UiLayoutCheck.check_panel_layout(panel, failures)

	panel.close_button.pressed.emit()
	if panel.visible:
		failures.append("FleetManagementPanel: expected hidden after Close")

	campaign_state.reset()
	panel.queue_free()
	return failures

static func _make_fleet(corvette_crew: int, capital_crew: int, freighter_crew: int) -> CampaignFleet:
	var fleet := CampaignFleet.new()
	var corvette := ShipType.new_composition(ShipType.Kind.CORVETTE)
	var capital := ShipType.new_composition(ShipType.Kind.CAPITAL)
	var freighter := ShipType.new_composition(ShipType.Kind.FREIGHTER)
	corvette["crew"] = corvette_crew
	capital["crew"] = capital_crew
	freighter["crew"] = freighter_crew
	fleet.ship_compositions.assign([corvette, capital, freighter])
	fleet.set_flagship(1)
	return fleet
