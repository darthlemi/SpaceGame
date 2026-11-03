extends RefCounted

const LootPanelScene = preload("res://scenes/campaign/loot_panel.tscn")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")
const Commodity = preload("res://scripts/campaign/commodity.gd")
const UiLayoutCheck = preload("res://tests/ui_layout_check.gd")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var panel: Control = LootPanelScene.instantiate()
	tree.root.add_child(panel)
	await tree.process_frame

	if panel.visible:
		failures.append("LootPanel: expected hidden by default")

	var defeated_fleet := CampaignFleet.new()
	defeated_fleet.cargo = {Commodity.Type.ORE: 3.0, Commodity.Type.FOOD: 0.0}
	var player_fleet := CampaignFleet.new()
	player_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	panel.open_for(defeated_fleet, player_fleet)
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
	if defeated_fleet.cargo.get(Commodity.Type.ORE, 0.0) != 2.0:
		failures.append("LootPanel: expected Take to remove 1 unit from the defeated fleet's cargo")
	if player_fleet.cargo.get(Commodity.Type.ORE, 0.0) != 1.0:
		failures.append("LootPanel: expected Take to add 1 unit to the player's cargo")

	# Take disabled once the player's cargo is full.
	player_fleet.cargo = {Commodity.Type.FUEL: player_fleet.cargo_capacity()}
	panel.refresh()
	if not take_button.disabled:
		failures.append("LootPanel: expected Take disabled when the player's cargo is full")

	# Take disabled once the defeated fleet's cargo for that commodity runs out.
	player_fleet.cargo = {}
	defeated_fleet.cargo[Commodity.Type.ORE] = 0.0
	panel.refresh()
	if not take_button.disabled:
		failures.append("LootPanel: expected Take disabled once the defeated fleet's cargo is exhausted")

	# Every commodity plus padding rows: no row count may push content
	# outside the panel or under the Close button.
	for commodity in Commodity.Type.values():
		defeated_fleet.cargo[commodity] = 5.0
	panel.open_for(defeated_fleet, player_fleet)
	# Rebuilding again before freed rows are flushed must not stack them.
	panel.open_for(defeated_fleet, player_fleet)
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

	# Captured crew: take is capped by free berths, the remainder stays available.
	var crew_player := CampaignFleet.new()
	var crew_comp: Dictionary = {"ship_type": ShipType.Kind.CORVETTE, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}
	crew_comp["crew"] = CrewRules.complement(crew_comp) - 3
	crew_player.ship_compositions.assign([crew_comp])
	var crew_loot := CampaignFleet.new()
	panel.open_for(crew_loot, crew_player, 5)
	if panel.crew_take_button == null:
		failures.append("LootPanel: expected a crew row when captured_crew > 0")
	else:
		panel.crew_take_button.pressed.emit()
		if CrewRules.crew_of(crew_player.ship_compositions[0]) != CrewRules.complement(crew_comp):
			failures.append("LootPanel: expected Take to fill the 3 free berths")
		if panel._captured_crew != 2:
			failures.append("LootPanel: expected 2 captured crew left, got %d" % panel._captured_crew)
		if not panel.crew_take_button.disabled:
			failures.append("LootPanel: expected crew Take disabled at 0 free berths")
	panel.open_for(crew_loot, crew_player)
	if panel.crew_take_button != null:
		failures.append("LootPanel: expected no crew row when captured_crew == 0")

	panel.close()
	if panel.visible:
		failures.append("LootPanel: expected hidden after close")

	panel.queue_free()
	return failures
