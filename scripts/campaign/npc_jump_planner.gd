class_name NpcJumpPlanner
extends RefCounted

# Where an NPC fleet jumps next, by role. Data-only: hostility comes in as a
# Callable(CampaignFleet, CampaignFleet) -> bool, so this never reads the CampaignState autoload.

const RETREAT_STRENGTH_FRACTION := 0.5
const DECISION_INTERVAL := 20.0
const DECISION_JITTER := 10.0
const HOP_DELAY := 2.0
# Away fleets never fight in-system yet, so a raid or hunt ends on time rather than on contact.
const RAID_DWELL := 75.0
const HUNT_DWELL := 75.0
# A combat fleet back home stays this long before its next decision, so dens and garrisons aren't
# empty most of the time.
const HOME_REST := 90.0

# The systems to travel through, ending at the goal; empty means stay.
static func plan(fleet: CampaignFleet, galaxy: Galaxy, fleets: Array[CampaignFleet], are_hostile: Callable) -> Array[String]:
	if fleet.role == CampaignFleet.Role.TRADER:
		return _plan_trader(fleet, galaxy)
	if fleet.faction == CampaignFleet.Faction.PIRATE:
		return _plan_raider(fleet, galaxy, fleets, are_hostile)
	return _plan_patrol(fleet, galaxy, fleets, are_hostile)

# The fuel must also cover the way home from the path's end, so no jump strands a fleet.
static func fuel_allows(fleet: CampaignFleet, galaxy: Galaxy, path: Array[String]) -> bool:
	if path.is_empty():
		return true
	var jumps := path.size()
	var home := _home_system(fleet, galaxy)
	if home != "":
		jumps += maxi(0, galaxy.jump_distance(path.back(), home))
	# Epsilon as in JumpRules.can_afford: exactly-enough fuel must pass.
	return fleet.fuel_amount() >= JumpRules.jump_cost(fleet) * jumps - CrewRules.ROUND_EPSILON

# Empty at home or with no known home.
static func path_home(fleet: CampaignFleet, galaxy: Galaxy) -> Array[String]:
	var home := _home_system(fleet, galaxy)
	if home == "":
		var none: Array[String] = []
		return none
	return galaxy.path(fleet.system_id, home)

static func _plan_trader(fleet: CampaignFleet, galaxy: Galaxy) -> Array[String]:
	var dest: StationData = galaxy.station(fleet.dest_station_id)
	if dest == null:
		return path_home(fleet, galaxy)
	return galaxy.path(fleet.system_id, dest.system_id)

# Raid the neighbour with the most prey; stay while prey is here, up to RAID_DWELL; otherwise, or
# when hurt, go home.
static func _plan_raider(fleet: CampaignFleet, galaxy: Galaxy, fleets: Array[CampaignFleet], are_hostile: Callable) -> Array[String]:
	var stay: Array[String] = []
	if not _is_healthy(fleet):
		return path_home(fleet, galaxy)
	var home := _home_system(fleet, galaxy)
	if home != "" and fleet.system_id != home:
		if fleet.away_time < RAID_DWELL and _count_prey(fleet, fleet.system_id, fleets, are_hostile) > 0:
			return stay
		return path_home(fleet, galaxy)
	var best := ""
	var best_count := 0
	for neighbour in galaxy.neighbours(fleet.system_id):
		var count := _count_prey(fleet, neighbour, fleets, are_hostile)
		if count > best_count:
			best = neighbour
			best_count = count
	if best == "":
		return stay
	var raid: Array[String] = [best]
	return raid

# Hold a system with hostiles in it (away, up to HUNT_DWELL); else hunt in the adjacent owned system
# with the most; else go home.
static func _plan_patrol(fleet: CampaignFleet, galaxy: Galaxy, fleets: Array[CampaignFleet], are_hostile: Callable) -> Array[String]:
	var stay: Array[String] = []
	var home_station: StationData = galaxy.station(fleet.home_station_id)
	if home_station == null:
		return stay
	if fleet.system_id != home_station.system_id and fleet.away_time >= HUNT_DWELL:
		return path_home(fleet, galaxy)
	if _count_hostiles(fleet, fleet.system_id, fleets, are_hostile) > 0:
		return stay
	var best := ""
	var best_count := 0
	for neighbour in galaxy.neighbours(fleet.system_id):
		if not _owns(galaxy, neighbour, home_station.owner):
			continue
		var count := _count_hostiles(fleet, neighbour, fleets, are_hostile)
		if count > best_count:
			best = neighbour
			best_count = count
	if best == "":
		return path_home(fleet, galaxy)
	var hunt: Array[String] = [best]
	return hunt

static func _is_healthy(fleet: CampaignFleet) -> bool:
	return fleet.total_strength() >= RETREAT_STRENGTH_FRACTION * fleet.max_strength()

static func _home_system(fleet: CampaignFleet, galaxy: Galaxy) -> String:
	var home: StationData = galaxy.station(fleet.home_station_id)
	return home.system_id if home != null else ""

static func _owns(galaxy: Galaxy, system_id: String, owner: CampaignFleet.Faction) -> bool:
	for station in galaxy.stations_in(system_id):
		if station.owner == owner:
			return true
	return false

# Prey is a hauler (TRADER role) the raider is hostile to, so neutral traders never draw a raid.
static func _count_prey(fleet: CampaignFleet, system_id: String, fleets: Array[CampaignFleet], are_hostile: Callable) -> int:
	var count := 0
	for other in fleets:
		if other != fleet and other.system_id == system_id and other.role == CampaignFleet.Role.TRADER and are_hostile.call(fleet, other):
			count += 1
	return count

static func _count_hostiles(fleet: CampaignFleet, system_id: String, fleets: Array[CampaignFleet], are_hostile: Callable) -> int:
	var count := 0
	for other in fleets:
		if other != fleet and other.system_id == system_id and are_hostile.call(fleet, other):
			count += 1
	return count
