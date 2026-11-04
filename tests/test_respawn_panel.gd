extends RefCounted

const RespawnPanelScene = preload("res://scenes/campaign/respawn_panel.tscn")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")
const UiLayoutCheck = preload("res://tests/ui_layout_check.gd")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var fleet := CampaignFleet.new()
	campaign_state.player_fleet = fleet
	campaign_state.credits = 10
	campaign_state.begin_respawn()

	var panel = RespawnPanelScene.instantiate()
	tree.root.add_child(panel)
	await tree.process_frame
	if panel.visible:
		failures.append("RespawnPanel: expected hidden by default")

	var finished_count: Array[int] = [0]
	panel.finished.connect(func(): finished_count[0] += 1)
	panel.open_for()
	await tree.process_frame
	if not panel.visible:
		failures.append("RespawnPanel: expected visible after open_for")
	if campaign_state.credits != 7:
		failures.append("RespawnPanel: expected 7 credits after the penalty, got %s" % campaign_state.credits)
	# Respawn keeps floori(10 * 0.75) = 7 credits.
	if panel.credits_label.text != "Credits: 7":
		failures.append("RespawnPanel: expected credits label 'Credits: 7', got '%s'" % panel.credits_label.text)
	if panel.buy_buttons.size() != ShipType.Kind.size():
		failures.append("RespawnPanel: expected one buy button per ship kind, got %d" % panel.buy_buttons.size())
	for kind in panel.buy_buttons:
		var button: Button = panel.buy_buttons[kind]
		if not button.disabled:
			failures.append("RespawnPanel: expected buy button for kind %d disabled at 7 credits" % kind)
		var expected := "Buy %s (%d cr)" % [ShipType.Kind.keys()[kind].capitalize(), ShipType.SHIP_PRICE[kind]]
		if button.text != expected:
			failures.append("RespawnPanel: expected button text '%s', got '%s'" % [expected, button.text])
	if panel.free_button.disabled:
		failures.append("RespawnPanel: expected the free ship enabled with no credits")
	UiLayoutCheck.check_panel_layout(panel, failures)

	panel.free_button.pressed.emit()
	if finished_count[0] != 1:
		failures.append("RespawnPanel: expected one finished signal, got %d" % finished_count[0])
	if panel.visible:
		failures.append("RespawnPanel: expected hidden after finishing")
	if fleet.ship_compositions.size() != 1 or campaign_state.pending_respawn:
		failures.append("RespawnPanel: expected one ship and pending_respawn cleared after the free pick")

	# Affordable buy: only the corvette at 450 credits.
	fleet.ship_compositions.clear()
	campaign_state.credits = 450
	panel.open_for()
	if panel.buy_buttons[ShipType.Kind.CORVETTE].disabled or not panel.buy_buttons[ShipType.Kind.FREIGHTER].disabled:
		failures.append("RespawnPanel: expected only the corvette affordable at 450 credits")
	panel.buy_buttons[ShipType.Kind.CORVETTE].pressed.emit()
	if campaign_state.credits != 50 or fleet.ship_compositions.size() != 1:
		failures.append("RespawnPanel: expected the corvette bought for 400 credits")
	if finished_count[0] != 2:
		failures.append("RespawnPanel: expected finished after a buy")

	panel.queue_free()
	campaign_state.reset()
	return failures
