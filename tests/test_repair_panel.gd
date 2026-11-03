extends RefCounted

const RepairPanelScene = preload("res://scenes/campaign/repair_panel.tscn")
const CampaignState = preload("res://scripts/campaign/campaign_state.gd")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var panel: Control = RepairPanelScene.instantiate()
	tree.root.add_child(panel)
	await tree.process_frame
	if panel.visible:
		failures.append("RepairPanel: expected hidden by default")

	var fleet := CampaignFleet.new()
	fleet.ship_compositions = [
		{
			"max_hp": 100.0, "current_hp": 40.0, "max_shield": 50.0, "current_shield": 50.0,
			"engine_max_hp": 20.0, "engine_current_hp": 20.0,
			"weapon_mount_max_hp": [], "weapon_mount_current_hp": [],
		},
		{
			"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0,
			"engine_max_hp": 20.0, "engine_current_hp": 20.0,
			"weapon_mount_max_hp": [], "weapon_mount_current_hp": [],
		},
	]
	campaign_state.credits = 1000.0
	panel.open_for(fleet)
	if not panel.visible:
		failures.append("RepairPanel: expected visible after open_for")

	if _repair_rows(panel).size() != 1:
		failures.append("RepairPanel: expected exactly 1 repair row for 1 damaged ship, got %d" % _repair_rows(panel).size())
	if panel.repair_all_button.disabled:
		failures.append("RepairPanel: expected Repair All enabled when credits cover the damaged ship")

	var repair_button: Button = _repair_rows(panel)[0].get_child(1)
	var credits_before_repair: float = campaign_state.credits
	repair_button.pressed.emit()
	if not is_equal_approx(campaign_state.credits, credits_before_repair - CampaignState.REPAIR_COST):
		failures.append("RepairPanel: expected pressing Repair to deduct REPAIR_COST, got credits=%s" % campaign_state.credits)
	if fleet.ship_compositions[0]["current_hp"] != 100.0:
		failures.append("RepairPanel: expected pressing Repair to fully heal the ship")
	if not _repair_rows(panel).is_empty():
		failures.append("RepairPanel: expected 0 repair rows once no ship is damaged")
	if panel.repair_container.get_child_count() != 1 or not (panel.repair_container.get_child(0) is Label):
		failures.append("RepairPanel: expected a single 'fully repaired' label when nothing needs repair")
	if not panel.repair_all_button.disabled:
		failures.append("RepairPanel: expected Repair All disabled when nothing needs repair")

	fleet.ship_compositions[0]["current_hp"] = 1.0
	fleet.ship_compositions[1]["current_hp"] = 1.0
	campaign_state.credits = 10.0
	panel.refresh()
	if not panel.repair_all_button.disabled:
		failures.append("RepairPanel: expected Repair All disabled when credits can't cover every damaged ship")

	campaign_state.credits = 1000.0
	panel.refresh()
	panel.repair_all_button.pressed.emit()
	if fleet.ship_compositions[0]["current_hp"] != 100.0 or fleet.ship_compositions[1]["current_hp"] != 100.0:
		failures.append("RepairPanel: expected Repair All to heal every damaged ship")

	panel.close_button.pressed.emit()
	if panel.visible:
		failures.append("RepairPanel: expected hidden after Close")

	campaign_state.reset()
	panel.queue_free()
	return failures

static func _repair_rows(panel: Control) -> Array[HBoxContainer]:
	var rows: Array[HBoxContainer] = []
	for child in panel.repair_container.get_children():
		if child is HBoxContainer:
			rows.append(child)
	return rows
