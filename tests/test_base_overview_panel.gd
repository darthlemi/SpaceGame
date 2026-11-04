extends RefCounted

const BaseOverviewPanelScene = preload("res://scenes/campaign/base_overview_panel.tscn")
const UiLayoutCheck = preload("res://tests/ui_layout_check.gd")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var panel: Control = BaseOverviewPanelScene.instantiate()
	tree.root.add_child(panel)
	await tree.process_frame
	if panel.visible:
		failures.append("BaseOverviewPanel: expected hidden by default")
	if not panel.missions_button.disabled:
		failures.append("BaseOverviewPanel: expected the Missions placeholder disabled")

	# Home base: no faction, so no reputation or fine rows.
	var home_economy := BaseEconomy.new()
	home_economy.slots = [EconomyRole.trade_hub(), EconomyRole.refinery()]
	home_economy.population = 1234.4
	home_economy.population_trend = 1
	panel.open_for("Home Base", home_economy, null)
	if not panel.visible:
		failures.append("BaseOverviewPanel: expected visible after open_for")
	if panel.title_label.text != "Home Base":
		failures.append("BaseOverviewPanel: expected title 'Home Base', got '%s'" % panel.title_label.text)
	if panel.population_label.text != "Population: 1234 (growing)":
		failures.append("BaseOverviewPanel: unexpected population text '%s'" % panel.population_label.text)
	if panel.economy_label.text != "Economy: Middling":
		failures.append("BaseOverviewPanel: expected a fresh economy to read Middling, got '%s'" % panel.economy_label.text)
	if panel.produces_label.text != "Produces: Fuel":
		failures.append("BaseOverviewPanel: expected 'Produces: Fuel', got '%s'" % panel.produces_label.text)
	if panel.consumes_label.text != "Consumes: nothing":
		failures.append("BaseOverviewPanel: expected 'Consumes: nothing', got '%s'" % panel.consumes_label.text)
	if panel.reputation_label.visible or panel.fine_label.visible or panel.pay_fine_button.visible:
		failures.append("BaseOverviewPanel: expected no reputation/fine UI at a factionless base")

	# Faction base with an outstanding fine, hostile standing.
	var faction := PowerFaction.new()
	faction.faction_enum = CampaignFleet.Faction.DOMINION
	faction.display_name = "Dominion"
	faction.reputation = 30.0
	faction.fine = 150
	faction.fine_reputation = 15.0
	var faction_economy := BaseEconomy.new()
	faction_economy.slots = [EconomyRole.industrial(), EconomyRole.population()]
	faction_economy.deficit_streaks = {0: 2}
	# assign(): campaign_state is untyped here, so a bare literal won't coerce to Array[PowerFaction].
	campaign_state.factions.assign([faction])
	campaign_state.credits = 100
	panel.open_for("Dominion Base", faction_economy, faction)
	if panel.economy_label.text != "Economy: Poor":
		failures.append("BaseOverviewPanel: expected a deficit economy to read Poor, got '%s'" % panel.economy_label.text)
	if panel.produces_label.text != "Produces: Weapons":
		failures.append("BaseOverviewPanel: expected 'Produces: Weapons', got '%s'" % panel.produces_label.text)
	if panel.consumes_label.text != "Consumes: Ore, Food, Fuel":
		failures.append("BaseOverviewPanel: expected consumes in Commodity order, got '%s'" % panel.consumes_label.text)
	if panel.reputation_label.text != "Reputation: 30 (hostile)":
		failures.append("BaseOverviewPanel: unexpected reputation text '%s'" % panel.reputation_label.text)
	if not panel.fine_label.visible or not panel.pay_fine_button.visible:
		failures.append("BaseOverviewPanel: expected fine row and Pay Fine button shown while a fine is owed")
	if not panel.pay_fine_button.disabled:
		failures.append("BaseOverviewPanel: expected Pay Fine disabled when credits cannot cover it")
	# Containers lay out children on the next frame.
	await tree.process_frame
	UiLayoutCheck.check_panel_layout(panel, failures)

	campaign_state.credits = 500
	panel.refresh()
	if panel.pay_fine_button.disabled:
		failures.append("BaseOverviewPanel: expected Pay Fine enabled once credits cover it")
	panel.pay_fine_button.pressed.emit()
	if faction.fine != 0 or faction.reputation != 45.0:
		failures.append("BaseOverviewPanel: expected Pay Fine to clear the fine and restore reputation, got fine=%s rep=%s" % [faction.fine, faction.reputation])
	if panel.fine_label.visible or panel.pay_fine_button.visible:
		failures.append("BaseOverviewPanel: expected fine UI hidden after paying")
	if panel.reputation_label.text != "Reputation: 45":
		failures.append("BaseOverviewPanel: expected non-hostile reputation text after paying, got '%s'" % panel.reputation_label.text)

	panel.close()
	if panel.visible:
		failures.append("BaseOverviewPanel: expected hidden after close")

	campaign_state.reset()
	panel.queue_free()
	return failures
