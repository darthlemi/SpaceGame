extends RefCounted

const HomeBaseScene = preload("res://scenes/campaign/home_base.tscn")
const CampaignFleetIconScene = preload("res://scenes/campaign/campaign_fleet_icon.tscn")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

class DockedTracker:
	var fired := false
	func on_docked() -> void:
		fired = true

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var fleet := CampaignFleet.new()
	fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 10.0, "max_shield": 50.0, "current_shield": 0.0}]
	fleet.speed = 1000.0

	var base: Area2D = HomeBaseScene.instantiate()
	base.global_position = Vector2(0, 0)
	tree.root.add_child(base)

	var tracker := DockedTracker.new()
	base.player_docked.connect(tracker.on_docked)

	var icon: Area2D = CampaignFleetIconScene.instantiate()
	icon.behavior_type = icon.BehaviorType.PLAYER
	tree.root.add_child(icon)
	icon.setup(fleet, Vector2.ZERO)
	icon.global_position = Vector2(500, 0)
	icon.set_move_target(Vector2(0, 0))

	# Loop generously rather than a fixed frame count: at speed 1000 covering
	# 500px takes ~30 physics frames at 60Hz, so give plenty of margin and
	# stop early once docking has actually fired.
	for i in 120:
		await tree.physics_frame
		if tracker.fired:
			break

	if not tracker.fired:
		failures.append("HomeBase: expected player_docked to fire once the player icon reaches the base")
	if fleet.ship_compositions[0]["current_hp"] != 10.0 or fleet.ship_compositions[0]["current_shield"] != 0.0:
		failures.append("HomeBase: expected docking to NOT auto-repair (repair is now a paid station action), got %s" % fleet.ship_compositions[0])

	icon.queue_free()
	base.queue_free()
	return failures
