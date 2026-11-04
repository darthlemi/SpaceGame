extends RefCounted

const LootPanelScene = preload("res://scenes/campaign/loot_panel.tscn")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")
const Commodity = preload("res://scripts/campaign/commodity.gd")
const UiLayoutCheck = preload("res://tests/ui_layout_check.gd")

const PART_PATH := "res://resources/weapons/kinetic_cannon.tres"

static func _comp(kind: ShipType.Kind, crew: int) -> Dictionary:
	var comp := ShipType.new_composition(kind)
	CrewRules.set_crew(comp, crew)
	return comp

static func _full_player() -> CampaignFleet:
	var player := CampaignFleet.new()
	var corvette := ShipType.new_composition(ShipType.Kind.CORVETTE)
	player.ship_compositions.assign([corvette])
	CrewRules.set_crew(corvette, CrewRules.complement(corvette))
	player.ensure_flagship()
	return player

static func _ship_offer() -> LootOffer:
	var offer := LootOffer.new()
	offer.ships.assign([_comp(ShipType.Kind.CORVETTE, 5), _comp(ShipType.Kind.FREIGHTER, 3)])
	return offer

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var panel: Control = LootPanelScene.instantiate()
	tree.root.add_child(panel)
	await tree.process_frame

	if panel.visible:
		failures.append("LootPanel: expected hidden by default")
	if panel.close_button.text != "Leave":
		failures.append("LootPanel: expected the close button to read 'Leave', got '%s'" % panel.close_button.text)

	var offer := LootOffer.new()
	offer.cargo = {Commodity.Type.ORE: 3.0, Commodity.Type.FOOD: 0.0}
	var player_fleet := CampaignFleet.new()
	player_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	panel.open_for(offer, player_fleet)
	if not panel.visible:
		failures.append("LootPanel: expected visible after open_for")
	if not panel._rows.has(Commodity.Type.ORE):
		failures.append("LootPanel: expected a row for Ore (nonzero cargo)")
	if panel._rows.has(Commodity.Type.FOOD):
		failures.append("LootPanel: expected no row for Food (zero cargo)")

	var ore_icon: TextureRect = panel._rows[Commodity.Type.ORE]["icon"]
	if ore_icon == null or ore_icon.texture == null:
		failures.append("LootPanel: expected a non-null icon texture for the Ore row")

	var take_button: Button = panel._rows[Commodity.Type.ORE]["take_button"]
	take_button.pressed.emit()
	if offer.cargo.get(Commodity.Type.ORE, 0.0) != 2.0:
		failures.append("LootPanel: expected Take to remove 1 unit from offer.cargo")
	if player_fleet.cargo.get(Commodity.Type.ORE, 0.0) != 1.0:
		failures.append("LootPanel: expected Take to add 1 unit to the player's cargo")

	# Take disabled once the player's cargo is full.
	player_fleet.cargo = {Commodity.Type.FUEL: player_fleet.cargo_capacity()}
	panel.refresh()
	if not take_button.disabled:
		failures.append("LootPanel: expected Take disabled when the player's cargo is full")

	# Take disabled once the offer's cargo for that commodity runs out.
	player_fleet.cargo = {}
	offer.cargo[Commodity.Type.ORE] = 0.0
	panel.refresh()
	if not take_button.disabled:
		failures.append("LootPanel: expected Take disabled once the offered cargo is exhausted")

	# Every commodity plus padding rows: no row count may push content
	# outside the panel or under the Leave button.
	for commodity in Commodity.Type.values():
		offer.cargo[commodity] = 5.0
	panel.open_for(offer, player_fleet)
	# Rebuilding again before freed rows are flushed must not stack them.
	panel.open_for(offer, player_fleet)
	if panel.rows_container.get_child_count() != Commodity.Type.size():
		failures.append("LootPanel: expected %d rows after a same-frame rebuild, got %d" % [Commodity.Type.size(), panel.rows_container.get_child_count()])
	for i in 6:
		var extra_row := HBoxContainer.new()
		var extra_button := Button.new()
		extra_button.text = "Take"
		extra_row.add_child(extra_button)
		panel.rows_container.add_child(extra_row)
	await tree.process_frame
	UiLayoutCheck.check_panel_layout(panel, failures)

	# Part rows: Take moves the part into part_inventory, subject to cargo capacity.
	var part_offer := LootOffer.new()
	part_offer.parts.assign([PART_PATH])
	var part_player := _full_player()
	panel.open_for(part_offer, part_player)
	if panel.part_rows.size() != 1:
		failures.append("LootPanel: expected 1 part row, got %d" % panel.part_rows.size())
	else:
		var part_take: Button = panel.part_rows[0]["take_button"]
		part_take.pressed.emit()
		if part_player.part_inventory != [PART_PATH]:
			failures.append("LootPanel: expected the part Take to add it to part_inventory, got %s" % [part_player.part_inventory])
		if not part_offer.parts.is_empty():
			failures.append("LootPanel: expected the taken part removed from offer.parts")
		if not panel.part_rows.is_empty():
			failures.append("LootPanel: expected the taken part's row removed")
	var full_part_offer := LootOffer.new()
	full_part_offer.parts.assign([PART_PATH])
	var full_player := _full_player()
	full_player.cargo = {Commodity.Type.FUEL: full_player.cargo_capacity()}
	panel.open_for(full_part_offer, full_player)
	if panel.part_rows.size() != 1 or not panel.part_rows[0]["take_button"].disabled:
		failures.append("LootPanel: expected the part Take disabled when cargo is full")

	# Captured ships: Keep checkboxes drive the crew slider's max.
	var ship_offer := _ship_offer()
	var ship_player := _full_player()
	panel.open_for(ship_offer, ship_player)
	if panel.ship_rows.size() != 2:
		failures.append("LootPanel: expected 2 ship rows, got %d" % panel.ship_rows.size())
	else:
		await tree.process_frame
		UiLayoutCheck.check_panel_layout(panel, failures)
		if panel.crew_slider.max_value != 0.0:
			failures.append("LootPanel: expected slider max 0 with no berths and nothing kept, got %s" % panel.crew_slider.max_value)
		var corvette_keep: CheckBox = panel.ship_rows[0]["keep_check"]
		var freighter_keep: CheckBox = panel.ship_rows[1]["keep_check"]
		corvette_keep.button_pressed = true
		if panel.crew_slider.max_value != 8.0 or panel.crew_slider.value != 8.0:
			failures.append("LootPanel: expected max 8 / value 8 after keeping the corvette, got %s / %s" % [panel.crew_slider.max_value, panel.crew_slider.value])
		freighter_keep.button_pressed = true
		if panel.crew_slider.max_value != 8.0:
			failures.append("LootPanel: expected max to stay 8 (pool-limited) with both kept, got %s" % panel.crew_slider.max_value)
		freighter_keep.button_pressed = false
		corvette_keep.button_pressed = false
		if panel.crew_slider.max_value != 0.0:
			failures.append("LootPanel: expected max 0 after unticking both, got %s" % panel.crew_slider.max_value)

		# Take: the kept corvette joins with the slider's crew, the freighter is left behind.
		corvette_keep.button_pressed = true
		panel.crew_slider.value = 5.0
		panel.take_button.pressed.emit()
		if ship_player.ship_compositions.size() != 2:
			failures.append("LootPanel: expected 2 player ships after Take, got %d" % ship_player.ship_compositions.size())
		elif CrewRules.crew_of(ship_player.ship_compositions[1]) != 5:
			failures.append("LootPanel: expected the new corvette to have 5 crew, got %d" % CrewRules.crew_of(ship_player.ship_compositions[1]))
		elif CrewRules.is_flagship(ship_player.ship_compositions[1]):
			failures.append("LootPanel: expected the captured ship not to be a flagship")
		if ship_player.crew_total() != 17:
			failures.append("LootPanel: expected 17 total crew after Take, got %d" % ship_player.crew_total())
		if panel.visible:
			failures.append("LootPanel: expected the panel closed after Take")

	# Leave: nothing is taken.
	var leave_offer := _ship_offer()
	var leave_player := _full_player()
	panel.open_for(leave_offer, leave_player)
	if panel.ship_rows.size() == 2:
		panel.ship_rows[0]["keep_check"].button_pressed = true
	panel.close_button.pressed.emit()
	if leave_player.ship_compositions.size() != 1 or leave_player.crew_total() != 12:
		failures.append("LootPanel: expected Leave to leave the player fleet unchanged")
	if panel.visible:
		failures.append("LootPanel: expected hidden after Leave")

	panel.queue_free()
	return failures
