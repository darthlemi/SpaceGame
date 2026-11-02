extends RefCounted

const LootPanelScene = preload("res://scenes/campaign/loot_panel.tscn")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")
const Commodity = preload("res://scripts/campaign/commodity.gd")

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

	panel.close()
	if panel.visible:
		failures.append("LootPanel: expected hidden after close")

	panel.queue_free()
	return failures
