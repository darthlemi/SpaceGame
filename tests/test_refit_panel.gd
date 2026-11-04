extends RefCounted

const RefitPanelScene = preload("res://scenes/campaign/refit_panel.tscn")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()
	campaign_state.credits = 2000

	var panel: Control = RefitPanelScene.instantiate()
	tree.root.add_child(panel)
	await tree.process_frame

	if panel.visible:
		failures.append("RefitPanel: expected hidden by default")

	var fleet := CampaignFleet.new()
	fleet.ship_compositions = [ShipType.new_composition(ShipType.Kind.CORVETTE)]
	var catalog: Array[String] = ["res://resources/weapons/mass_driver.tres", "res://resources/shields/shield_dominion_aegis.tres", "res://resources/weapons/lance_graser.tres", "res://resources/shields/shield_light.tres"]

	panel.open_for(fleet, catalog)
	if not panel.visible:
		failures.append("RefitPanel: expected visible after open_for")
	if panel.catalog_rows_container.get_child_count() != catalog.size():
		failures.append("RefitPanel: expected one catalog row per catalog entry, got %d" % panel.catalog_rows_container.get_child_count())

	var buy_row: HBoxContainer = panel.catalog_rows_container.get_child(0)
	var buy_button: Button = buy_row.get_child(1)
	var credits_before: float = campaign_state.credits
	buy_button.pressed.emit()
	if campaign_state.credits >= credits_before:
		failures.append("RefitPanel: expected pressing Buy to deduct credits")
	if fleet.part_inventory != ["res://resources/weapons/mass_driver.tres"]:
		failures.append("RefitPanel: expected the bought part added to fleet.part_inventory, got %s" % fleet.part_inventory)

	if panel.inventory_rows_container.get_child_count() != 1:
		failures.append("RefitPanel: expected 1 inventory row after buying 1 part, got %d" % panel.inventory_rows_container.get_child_count())

	panel.equip_button.pressed.emit()
	if panel.slots_container.get_child_count() != 3:
		failures.append("RefitPanel: expected 3 equip slot rows for a corvette (1 weapon + shield + engine), got %d" % panel.slots_container.get_child_count())

	var weapon_slot_row: HBoxContainer = panel.slots_container.get_child(0)
	var weapon_equip_button: Button = weapon_slot_row.get_child(2)
	if weapon_equip_button.disabled:
		failures.append("RefitPanel: expected the weapon slot's Equip button enabled with a compatible part in inventory")
	weapon_equip_button.pressed.emit()
	if ShipType.equipped_path(fleet.ship_compositions[0], ShipType.SlotType.WEAPON, 0) != "res://resources/weapons/mass_driver.tres":
		failures.append("RefitPanel: expected pressing Equip to call CampaignState.equip_part and assign the weapon")

	# Budget exclusion: swap the weapon slot to the EPIC lance_graser (20/20
	# points, maxing the corvette's budget), then buy a shield -- it must not
	# appear as an equippable option since 20 + any shield cost > 20.
	var lance_buy_row: HBoxContainer = panel.catalog_rows_container.get_child(2)
	var lance_buy_button: Button = lance_buy_row.get_child(1)
	lance_buy_button.pressed.emit()
	var light_shield_buy_row: HBoxContainer = panel.catalog_rows_container.get_child(3)
	var light_shield_buy_button: Button = light_shield_buy_row.get_child(1)
	light_shield_buy_button.pressed.emit()
	var weapon_slot_row_2: HBoxContainer = panel.slots_container.get_child(0)
	var weapon_picker_2: OptionButton = weapon_slot_row_2.get_child(1)
	for i in weapon_picker_2.item_count:
		if weapon_picker_2.get_item_text(i) == "Lance/Graser":
			weapon_picker_2.selected = i
	var weapon_equip_button_2: Button = weapon_slot_row_2.get_child(2)
	weapon_equip_button_2.pressed.emit()
	if ShipType.equipped_path(fleet.ship_compositions[0], ShipType.SlotType.WEAPON, 0) != "res://resources/weapons/lance_graser.tres":
		failures.append("RefitPanel: expected swapping the weapon slot to the lance_graser to succeed (20/20 points)")
	var shield_slot_row_2: HBoxContainer = panel.slots_container.get_child(1)
	var shield_picker_2: OptionButton = shield_slot_row_2.get_child(1)
	var shield_equip_button_2: Button = shield_slot_row_2.get_child(2)
	if shield_picker_2.item_count != 0 or not shield_equip_button_2.disabled:
		failures.append("RefitPanel: expected the shield slot to exclude an over-budget shield once the weapon slot uses the full 20 points")

	# Damaged ship blocks the Equip tab's buttons.
	fleet.ship_compositions[0]["current_hp"] = 1.0
	panel.refresh()
	var shield_slot_row: HBoxContainer = panel.slots_container.get_child(1)
	var shield_equip_button: Button = shield_slot_row.get_child(2)
	if not shield_equip_button.disabled:
		failures.append("RefitPanel: expected Equip buttons disabled while the selected ship is damaged")

	panel.close()
	if panel.visible:
		failures.append("RefitPanel: expected hidden after close")

	campaign_state.reset()
	panel.queue_free()

	# Regression: the real campaign bootstraps ship_compositions with bare dict
	# literals (ship_type/max_hp/current_hp/max_shield/current_shield only --
	# no weapon_mount_items key at all). Weapon slot count must be derived from
	# the ship class's BASE_STATS, not from a (possibly absent) items array.
	campaign_state.reset()
	campaign_state.credits = 2000
	var bare_panel: Control = RefitPanelScene.instantiate()
	tree.root.add_child(bare_panel)
	await tree.process_frame

	var bare_fleet := CampaignFleet.new()
	bare_fleet.ship_compositions = [
		{"ship_type": ShipType.Kind.CORVETTE, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"ship_type": ShipType.Kind.CAPITAL, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
	]
	var empty_catalog: Array[String] = []
	bare_panel.open_for(bare_fleet, empty_catalog)
	bare_panel.equip_button.pressed.emit()
	if bare_panel.slots_container.get_child_count() != 3:
		failures.append("RefitPanel: expected a bare-dict corvette composition (no weapon_mount_items key) to get 1 weapon slot row + shield + engine = 3, got %d" % bare_panel.slots_container.get_child_count())

	bare_panel.ship_selector.item_selected.emit(1)
	if bare_panel.slots_container.get_child_count() != 5:
		failures.append("RefitPanel: expected a bare-dict capital composition (no weapon_mount_items key) to get 3 weapon slot rows + shield + engine = 5, got %d" % bare_panel.slots_container.get_child_count())

	campaign_state.reset()
	bare_panel.queue_free()
	return failures
