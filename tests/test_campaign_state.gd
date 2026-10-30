extends RefCounted

const CampaignState = preload("res://scripts/campaign/campaign_state.gd")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var state := CampaignState.new()
	var player := CampaignFleet.new()
	player.ship_compositions = [{"max_hp": 100.0, "current_hp": 50.0, "max_shield": 50.0, "current_shield": 10.0}]
	var enemy := CampaignFleet.new()
	enemy.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	state.player_fleet = player
	state.enemy_fleets = [enemy]

	state.start_engagement(enemy)
	if state.active_enemy_fleet != enemy:
		failures.append("start_engagement: expected active_enemy_fleet == enemy")

	state.resolve_engagement(
		[{"max_hp": 100.0, "current_hp": 30.0, "max_shield": 50.0, "current_shield": 0.0}],
		[]
	)
	if player.ship_compositions[0]["current_hp"] != 30.0:
		failures.append("resolve_engagement: expected player fleet updated with survivor data")
	if not enemy.is_destroyed():
		failures.append("resolve_engagement: expected enemy fleet marked destroyed with empty survivors")
	if state.enemy_fleets.has(enemy):
		failures.append("resolve_engagement: expected destroyed enemy fleet removed from enemy_fleets")
	if state.active_enemy_fleet != null:
		failures.append("resolve_engagement: expected active_enemy_fleet cleared after resolution")

	state.factions = [PowerFaction.new()]
	state.factions_at_war = false
	state.active_skirmishes = [Skirmish.new()]

	state.reset()
	if state.player_fleet != null or not state.enemy_fleets.is_empty() or state.active_enemy_fleet != null:
		failures.append("reset: expected all state cleared")
	if not state.factions.is_empty() or state.factions_at_war != true or not state.active_skirmishes.is_empty():
		failures.append("reset: expected factions, factions_at_war, and active_skirmishes cleared")

	return failures

class SkirmishResolvedTracker:
	var fired := false
	var winner_fleet: CampaignFleet
	var loser_fleet: CampaignFleet
	func on_skirmish_resolved(winner: CampaignFleet, loser: CampaignFleet) -> void:
		fired = true
		winner_fleet = winner
		loser_fleet = loser

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var state := CampaignState.new()

	var dominion := PowerFaction.new()
	dominion.faction_enum = CampaignFleet.Faction.DOMINION
	var freehold := PowerFaction.new()
	freehold.faction_enum = CampaignFleet.Faction.FREEHOLD
	state.factions = [dominion, freehold]
	state.factions_at_war = true

	var dominion_fleet := CampaignFleet.new()
	dominion_fleet.faction = CampaignFleet.Faction.DOMINION
	var freehold_fleet := CampaignFleet.new()
	freehold_fleet.faction = CampaignFleet.Faction.FREEHOLD
	var trader_fleet := CampaignFleet.new()
	trader_fleet.faction = CampaignFleet.Faction.TRADER

	if not state.are_hostile(dominion_fleet, freehold_fleet):
		failures.append("are_hostile: expected two warring power factions to be hostile")
	if state.are_hostile(dominion_fleet, trader_fleet):
		failures.append("are_hostile: expected a power faction and a trader to be non-hostile")
	state.factions_at_war = false
	if state.are_hostile(dominion_fleet, freehold_fleet):
		failures.append("are_hostile: expected power factions at peace to be non-hostile")
	state.factions_at_war = true

	var pirate_fleet := CampaignFleet.new()
	pirate_fleet.faction = CampaignFleet.Faction.PIRATE
	if not state.are_hostile(pirate_fleet, dominion_fleet):
		failures.append("are_hostile: expected a pirate and a power faction to be hostile")

	# start_skirmish + tick_skirmishes: stronger fleet wins, loser removed,
	# winner damaged proportionally, loser icon freed, winner icon unfrozen.
	var strong_fleet := CampaignFleet.new()
	strong_fleet.faction = CampaignFleet.Faction.DOMINION
	strong_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0}]
	var weak_fleet := CampaignFleet.new()
	weak_fleet.faction = CampaignFleet.Faction.FREEHOLD
	weak_fleet.ship_compositions = [{"max_hp": 20.0, "current_hp": 20.0, "max_shield": 0.0, "current_shield": 0.0}]

	state.enemy_fleets = [strong_fleet, weak_fleet]

	const CampaignFleetIconScene = preload("res://scenes/campaign/campaign_fleet_icon.tscn")
	var strong_icon: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(strong_icon)
	strong_icon.setup(strong_fleet, Vector2.ZERO)
	var weak_icon: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(weak_icon)
	weak_icon.setup(weak_fleet, Vector2.ZERO)

	var resolved_tracker := SkirmishResolvedTracker.new()
	state.skirmish_resolved.connect(resolved_tracker.on_skirmish_resolved)

	state.start_skirmish(strong_icon, weak_icon)
	if not strong_icon.frozen or not weak_icon.frozen:
		failures.append("start_skirmish: expected both icons frozen")
	if state.active_skirmishes.size() != 1:
		failures.append("start_skirmish: expected exactly one active skirmish, got %d" % state.active_skirmishes.size())

	var skirmish: Skirmish = state.active_skirmishes[0]
	if skirmish.fleet_winner != strong_fleet or skirmish.fleet_loser != weak_fleet:
		failures.append("start_skirmish: expected the stronger fleet to be recorded as winner")

	state.tick_skirmishes(skirmish.remaining_time + 1.0)
	if state.active_skirmishes.size() != 0:
		failures.append("tick_skirmishes: expected the skirmish to be resolved and removed")
	if state.enemy_fleets.has(weak_fleet):
		failures.append("tick_skirmishes: expected the loser fleet removed from enemy_fleets")
	if strong_fleet.ship_compositions[0]["current_hp"] >= 100.0:
		failures.append("tick_skirmishes: expected the winner to take proportional damage")
	if strong_icon.frozen:
		failures.append("tick_skirmishes: expected the winner icon to unfreeze")
	if not resolved_tracker.fired:
		failures.append("tick_skirmishes: expected skirmish_resolved to fire")
	elif resolved_tracker.winner_fleet != strong_fleet or resolved_tracker.loser_fleet != weak_fleet:
		failures.append("tick_skirmishes: expected skirmish_resolved to fire with the correct winner/loser fleets")

	await tree.process_frame

	if is_instance_valid(weak_icon):
		failures.append("tick_skirmishes: expected the loser icon to be freed")
	strong_icon.queue_free()

	# tick_skirmishes should drop (not resolve) a skirmish whose icons were
	# freed out-of-band (e.g. the scene that owned them was torn down across
	# a scene reload, as happens after a combat round-trip) -- no damage,
	# no fleet removal, no signal.
	var stale_fleet_winner := CampaignFleet.new()
	stale_fleet_winner.faction = CampaignFleet.Faction.DOMINION
	stale_fleet_winner.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0}]
	var stale_fleet_loser := CampaignFleet.new()
	stale_fleet_loser.faction = CampaignFleet.Faction.FREEHOLD
	stale_fleet_loser.ship_compositions = [{"max_hp": 20.0, "current_hp": 20.0, "max_shield": 0.0, "current_shield": 0.0}]
	state.enemy_fleets = [stale_fleet_winner, stale_fleet_loser]

	var stale_winner_icon: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(stale_winner_icon)
	stale_winner_icon.setup(stale_fleet_winner, Vector2.ZERO)
	var stale_loser_icon: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(stale_loser_icon)
	stale_loser_icon.setup(stale_fleet_loser, Vector2.ZERO)

	var stale_tracker := SkirmishResolvedTracker.new()
	state.skirmish_resolved.connect(stale_tracker.on_skirmish_resolved)

	state.start_skirmish(stale_winner_icon, stale_loser_icon)
	if state.active_skirmishes.size() != 1:
		failures.append("tick_skirmishes (stale icons): expected a skirmish to start")
	else:
		var stale_remaining_time: float = state.active_skirmishes[0].remaining_time
		# Simulate a scene reload: free both icons out-of-band, bypassing
		# CampaignState entirely, the way a real scene teardown would.
		stale_winner_icon.queue_free()
		stale_loser_icon.queue_free()
		await tree.process_frame

		state.tick_skirmishes(stale_remaining_time + 1.0)
		if state.active_skirmishes.size() != 0:
			failures.append("tick_skirmishes (stale icons): expected the stale skirmish to be dropped")
		if not state.enemy_fleets.has(stale_fleet_loser):
			failures.append("tick_skirmishes (stale icons): expected the loser fleet NOT erased from enemy_fleets when its icon is stale")
		if stale_fleet_winner.ship_compositions[0]["current_hp"] != 100.0:
			failures.append("tick_skirmishes (stale icons): expected no damage applied to the winner when icons are stale")
		if stale_tracker.fired:
			failures.append("tick_skirmishes (stale icons): expected skirmish_resolved NOT to fire for a dropped stale skirmish")

	state.skirmish_resolved.disconnect(stale_tracker.on_skirmish_resolved)

	# cancel_skirmish_for: starting a fresh skirmish and cancelling it
	# should unfreeze the untouched participant without resolving a winner.
	var fleet_c := CampaignFleet.new()
	fleet_c.faction = CampaignFleet.Faction.DOMINION
	fleet_c.ship_compositions = [{"max_hp": 50.0, "current_hp": 50.0, "max_shield": 0.0, "current_shield": 0.0}]
	var fleet_d := CampaignFleet.new()
	fleet_d.faction = CampaignFleet.Faction.FREEHOLD
	fleet_d.ship_compositions = [{"max_hp": 50.0, "current_hp": 50.0, "max_shield": 0.0, "current_shield": 0.0}]
	var icon_c: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(icon_c)
	icon_c.setup(fleet_c, Vector2.ZERO)
	var icon_d: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(icon_d)
	icon_d.setup(fleet_d, Vector2.ZERO)

	state.start_skirmish(icon_c, icon_d)
	state.cancel_skirmish_for(icon_c)
	if state.active_skirmishes.size() != 0:
		failures.append("cancel_skirmish_for: expected the skirmish removed")
	if icon_d.frozen:
		failures.append("cancel_skirmish_for: expected the other participant unfrozen")

	icon_c.queue_free()
	icon_d.queue_free()

	# start_engagement: engaging a fleet that's mid-skirmish should cancel
	# that skirmish and unfreeze the other participant.
	var fleet_e := CampaignFleet.new()
	fleet_e.faction = CampaignFleet.Faction.DOMINION
	fleet_e.ship_compositions = [{"max_hp": 50.0, "current_hp": 50.0, "max_shield": 0.0, "current_shield": 0.0}]
	var fleet_f := CampaignFleet.new()
	fleet_f.faction = CampaignFleet.Faction.FREEHOLD
	fleet_f.ship_compositions = [{"max_hp": 50.0, "current_hp": 50.0, "max_shield": 0.0, "current_shield": 0.0}]
	var icon_e: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(icon_e)
	icon_e.setup(fleet_e, Vector2.ZERO)
	var icon_f: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(icon_f)
	icon_f.setup(fleet_f, Vector2.ZERO)

	state.start_skirmish(icon_e, icon_f)
	state.start_engagement(fleet_e)
	if state.active_skirmishes.size() != 0:
		failures.append("start_engagement: expected the skirmish involving the engaged fleet to be cancelled")
	if icon_f.frozen:
		failures.append("start_engagement: expected the other participant unfrozen")

	icon_e.queue_free()
	icon_f.queue_free()

	# resolve_engagement reputation decay.
	var defeat_state := CampaignState.new()
	var defeat_dominion := PowerFaction.new()
	defeat_dominion.faction_enum = CampaignFleet.Faction.DOMINION
	defeat_dominion.reputation = 60.0
	defeat_state.factions = [defeat_dominion]
	var defeat_player := CampaignFleet.new()
	defeat_player.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	defeat_state.player_fleet = defeat_player
	var defeated_enemy := CampaignFleet.new()
	defeated_enemy.faction = CampaignFleet.Faction.DOMINION
	defeated_enemy.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	defeat_state.start_engagement(defeated_enemy)
	defeat_state.resolve_engagement(
		[{"max_hp": 100.0, "current_hp": 80.0, "max_shield": 50.0, "current_shield": 50.0}],
		[]
	)
	if abs(defeat_dominion.reputation - 45.0) > 0.001:
		failures.append("resolve_engagement: expected reputation reduced by REPUTATION_LOSS_PER_DEFEAT to 45.0, got %s" % defeat_dominion.reputation)

	return failures
