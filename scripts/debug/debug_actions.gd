class_name DebugActions
extends RefCounted

# Cheat actions behind the F12 debug menu. Pure state changes on the campaign (no UI), so
# they work from the world and from combat and can be tested directly.

const SPAWN_RADIUS := 80.0

static func add_credits(amount: int) -> void:
	CampaignState.credits = maxi(0, CampaignState.credits + amount)

# Ignores cargo capacity on purpose: a cheat should always land.
static func add_fuel(fleet: CampaignFleet, amount: float) -> void:
	fleet.cargo[Commodity.Type.FUEL] = maxf(0.0, fleet.fuel_amount() + amount)

# Positive adds up to the fleet's complement, negative removes down to zero.
static func add_crew(fleet: CampaignFleet, amount: int) -> int:
	if amount >= 0:
		return CrewRules.add_crew(fleet.ship_compositions, amount)
	return -CrewRules.remove_crew(fleet.ship_compositions, -amount, -1, 0)

static func repair_fleet(fleet: CampaignFleet) -> void:
	fleet.repair_to_full()
	for comp in fleet.ship_compositions:
		if comp.has("engine_max_hp"):
			comp["engine_current_hp"] = comp["engine_max_hp"]
		if comp.has("weapon_mount_max_hp"):
			comp["weapon_mount_current_hp"] = (comp["weapon_mount_max_hp"] as Array).duplicate()

static func reveal_galaxy() -> void:
	if CampaignState.galaxy == null:
		return
	for system_id in CampaignState.galaxy.systems:
		CampaignState.discovered[system_id] = true

# Spawns an NPC fleet beside the player in their system; returns it, or null with no station
# to call home. The campaign scene turns it into an icon via fleet_spawn_requested.
static func spawn_fleet(faction: CampaignFleet.Faction, role: CampaignFleet.Role, tier: int) -> CampaignFleet:
	var player := CampaignState.player_fleet
	if player == null or CampaignState.galaxy == null:
		return null
	var stations := CampaignState.galaxy.stations_in(player.system_id)
	if stations.is_empty():
		return null
	var fleet := CampaignFleet.new()
	fleet.ship_compositions = DangerTier.fleet_for(tier, role, CampaignState.rng)
	fleet.faction = faction
	fleet.role = role
	fleet.home_station_id = stations[0].id
	fleet.system_id = player.system_id
	fleet.speed = CampaignState.NPC_SPEED[role]
	var angle := CampaignState.rng.randf() * TAU
	fleet.position = player.position + Vector2.from_angle(angle) * SPAWN_RADIUS
	fleet.cargo = {Commodity.Type.FUEL: CampaignState.NPC_FUEL_TARGET_JUMPS * JumpRules.jump_cost(fleet)}
	CampaignState.enemy_fleets.append(fleet)
	CampaignState.fleet_spawn_requested.emit(fleet)
	return fleet
