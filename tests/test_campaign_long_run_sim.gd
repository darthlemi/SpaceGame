extends RefCounted

# Runs the real campaign scene forward 5 and 20 simulated minutes via manual
# physics-stepping (not real time), observing fleet drift and pirate-targeting
# behavior.
#
# The pirate-engagement assertion is EXPECTED TO FAIL today: pirates only ever
# target the player, never other fleets. This is a known, documented gap (see
# docs/superpowers/specs/2026-11-01-campaign-long-run-sim-design.md), not a bug
# in this test. Do not "fix" this test to make it pass — the real fix is a
# separate future piece of work on pirate behavior.
#
# Distance-from-spawn output is report-only (informational, no "right"
# answer). Map bounds ARE asserted: every icon's position must stay within
# JumpRules.SYSTEM_MIN/SYSTEM_MAX (in its layer) at every sampled step -- unlike the
# pirate-engagement assertion above, this one is expected to pass; a failure
# here is a real bug in the clamp, not a documented gap. Reading `_move_target`
# (underscore-prefixed) is a deliberate one-file exception to verify internal
# pirate-targeting behavior, not a pattern to copy elsewhere.

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")

const SIM_DURATIONS_SECONDS: Array[float] = [300.0, 1200.0]  # 5 min, 20 min
const STEP_DELTA := 1.0 / 60.0
const ENGAGEMENT_EPSILON := 1.0

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")

	for duration in SIM_DURATIONS_SECONDS:
		campaign_state.reset()

		var scene: Node2D = CampaignSceneScene.instantiate()
		tree.root.add_child(scene)
		await tree.process_frame

		var icons: Array[CampaignFleetIcon] = [scene.player_icon]
		icons.append_array(scene.enemy_icons)

		var spawn_positions: Dictionary = {}
		var max_distance: Dictionary = {}
		var out_of_bounds: Dictionary = {}
		for icon in icons:
			spawn_positions[icon] = icon.global_position
			max_distance[icon] = 0.0

		var pirate_icon: CampaignFleetIcon = null
		for icon in scene.enemy_icons:
			if icon.behavior_type == CampaignFleetIcon.BehaviorType.PIRATE:
				pirate_icon = icon
				break

		var others: Array[CampaignFleetIcon] = []
		if pirate_icon != null:
			for icon in scene.enemy_icons:
				if icon != pirate_icon:
					others.append(icon)

		var opportunity_seen: Dictionary = {}
		var engaged: Dictionary = {}
		for other in others:
			opportunity_seen[other] = false
			engaged[other] = false

		var step_count := int(duration / STEP_DELTA)
		for step in step_count:
			for icon in icons:
				icon._physics_process(STEP_DELTA)
			for icon in icons:
				var d: float = icon.global_position.distance_to(spawn_positions[icon])
				if d > max_distance[icon]:
					max_distance[icon] = d
				var pos: Vector2 = icon.position
				if not out_of_bounds.has(icon) and pos != JumpRules.clamp_to_system(pos):
					out_of_bounds[icon] = pos
			if pirate_icon != null:
				for other in others:
					var pirate_distance: float = pirate_icon.global_position.distance_to(other.global_position)
					if pirate_distance <= pirate_icon.detection_range:
						opportunity_seen[other] = true
					if pirate_icon._move_target.distance_to(other.global_position) <= ENGAGEMENT_EPSILON:
						engaged[other] = true

		for icon in icons:
			var label: String = "player" if icon == scene.player_icon else "enemy[%d] (%s)" % [scene.enemy_icons.find(icon), CampaignFleetIcon.BehaviorType.keys()[icon.behavior_type]]
			print("[sim %0.0fs] %s max distance from spawn: %.1f" % [duration, label, max_distance[icon]])
			if out_of_bounds.has(icon):
				failures.append("[sim %0.0fs] %s went out of map bounds: %s" % [duration, label, out_of_bounds[icon]])

		if pirate_icon == null:
			failures.append("[sim %0.0fs] no pirate icon found in bootstrap — cannot check pirate engagement" % duration)
		for other in others:
			var other_label: String = "enemy[%d] (%s)" % [scene.enemy_icons.find(other), CampaignFleetIcon.BehaviorType.keys()[other.behavior_type]]
			print("[sim %0.0fs] pirate vs %s: opportunity_seen=%s engaged=%s" % [duration, other_label, opportunity_seen[other], engaged[other]])
			if opportunity_seen[other] and not engaged[other]:
				failures.append("[sim %0.0fs] pirate never targeted %s despite coming within detection range" % [duration, other_label])

		scene.queue_free()
		await tree.process_frame

	return failures
