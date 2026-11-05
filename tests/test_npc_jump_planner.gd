extends RefCounted

# Hand-built galaxy h - a - b: a pirate den in h, Freehold posts in a and b.

const PIRATE := CampaignFleet.Faction.PIRATE
const FREEHOLD := CampaignFleet.Faction.FREEHOLD
const COMBAT := CampaignFleet.Role.COMBAT
const TRADER := CampaignFleet.Role.TRADER

static func run() -> Array[String]:
	var failures: Array[String] = []
	var galaxy := _build()
	_check_pirates(galaxy, failures)
	_check_patrols(galaxy, failures)
	_check_traders(galaxy, failures)
	_check_planner_respects_round_trip_fuel(galaxy, failures)
	_check_dwell_limits(galaxy, failures)
	return failures

static func _build() -> Galaxy:
	var galaxy := Galaxy.new()
	for id in ["h", "a", "b"]:
		var sys := StarSystem.new()
		sys.id = id
		galaxy.systems[id] = sys
	galaxy.start_system_id = "h"
	galaxy.link("h", "a")
	galaxy.link("a", "b")
	galaxy.add_station(_station("h_den", "h", PIRATE))
	galaxy.add_station(_station("a_post", "a", FREEHOLD))
	galaxy.add_station(_station("b_post", "b", FREEHOLD))
	return galaxy

static func _station(id: String, system_id: String, owner: CampaignFleet.Faction) -> StationData:
	var st := StationData.new()
	st.id = id
	st.system_id = system_id
	st.owner = owner
	return st

static func _fleet(faction: CampaignFleet.Faction, role: CampaignFleet.Role, home_id: String, system_id: String, fuel_jumps: float = 4.0) -> CampaignFleet:
	var fleet := CampaignFleet.new()
	fleet.faction = faction
	fleet.role = role
	fleet.home_station_id = home_id
	fleet.system_id = system_id
	fleet.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	fleet.cargo = {Commodity.Type.FUEL: fuel_jumps * JumpRules.jump_cost(fleet)}
	return fleet

# CampaignState.are_hostile's rules with the power factions at war.
static func _hostile() -> Callable:
	return func(x: CampaignFleet, y: CampaignFleet) -> bool:
		var power := [CampaignFleet.Faction.DOMINION, FREEHOLD]
		if x.faction == PIRATE and power.has(y.faction):
			return true
		if y.faction == PIRATE and power.has(x.faction):
			return true
		return power.has(x.faction) and power.has(y.faction) and x.faction != y.faction

static func _plan(fleet: CampaignFleet, galaxy: Galaxy, fleets: Array[CampaignFleet]) -> Array[String]:
	return NpcJumpPlanner.plan(fleet, galaxy, fleets, _hostile())

static func _check_pirates(galaxy: Galaxy, failures: Array[String]) -> void:
	var pirate := _fleet(PIRATE, COMBAT, "h_den", "h")
	var trader := _fleet(FREEHOLD, TRADER, "a_post", "a")
	var fleets: Array[CampaignFleet] = [pirate, trader]
	var got := _plan(pirate, galaxy, fleets)
	if got != ["a"]:
		failures.append("pirate: expected a healthy pirate at home to raid ['a'] where a trader is, got %s" % [got])

	var alone: Array[CampaignFleet] = [pirate]
	got = _plan(pirate, galaxy, alone)
	if not got.is_empty():
		failures.append("pirate: expected a pirate to stay home with no traders anywhere, got %s" % [got])

	var raider := _fleet(PIRATE, COMBAT, "h_den", "a")
	fleets = [raider, trader]
	got = _plan(raider, galaxy, fleets)
	if not got.is_empty():
		failures.append("pirate: expected a healthy raider to stay where traders are, got %s" % [got])
	raider.apply_fractional_damage(0.6)
	got = _plan(raider, galaxy, fleets)
	if got != ["h"]:
		failures.append("pirate: expected a pirate below 50%% strength to head home ['h'], got %s" % [got])

	var idle_raider := _fleet(PIRATE, COMBAT, "h_den", "a")
	fleets = [idle_raider]
	got = _plan(idle_raider, galaxy, fleets)
	if got != ["h"]:
		failures.append("pirate: expected a raider with no traders left to head home ['h'], got %s" % [got])

static func _check_patrols(galaxy: Galaxy, failures: Array[String]) -> void:
	var patrol := _fleet(FREEHOLD, COMBAT, "a_post", "a")
	var pirate := _fleet(PIRATE, COMBAT, "h_den", "b")
	var fleets: Array[CampaignFleet] = [patrol, pirate]
	var got := _plan(patrol, galaxy, fleets)
	if got != ["b"]:
		failures.append("patrol: expected a hunt into owned system ['b'] where a pirate is, got %s" % [got])

	var away := _fleet(FREEHOLD, COMBAT, "a_post", "b")
	fleets = [away]
	got = _plan(away, galaxy, fleets)
	if got != ["a"]:
		failures.append("patrol: expected a patrol away with no pirates anywhere to head home ['a'], got %s" % [got])

	var at_home := _fleet(FREEHOLD, COMBAT, "a_post", "a")
	fleets = [at_home]
	got = _plan(at_home, galaxy, fleets)
	if not got.is_empty():
		failures.append("patrol: expected a patrol at home with no pirates to stay, got %s" % [got])

static func _check_traders(galaxy: Galaxy, failures: Array[String]) -> void:
	var trader := _fleet(FREEHOLD, TRADER, "a_post", "h")
	trader.dest_station_id = "b_post"
	var fleets: Array[CampaignFleet] = [trader]
	var got := _plan(trader, galaxy, fleets)
	if got != ["a", "b"]:
		failures.append("trader: expected the route ['a', 'b'] to a destination in b, got %s" % [got])
	trader.system_id = "b"
	got = _plan(trader, galaxy, fleets)
	if not got.is_empty():
		failures.append("trader: expected no jump once in the destination's system, got %s" % [got])

static func _check_planner_respects_round_trip_fuel(galaxy: Galaxy, failures: Array[String]) -> void:
	var to_a: Array[String] = ["a"]
	var to_h: Array[String] = ["h"]
	var pirate := _fleet(PIRATE, COMBAT, "h_den", "h", 1.0)
	if NpcJumpPlanner.fuel_allows(pirate, galaxy, to_a):
		failures.append("round trip: expected 1 jump of fuel to refuse ['a'] from home (no way back)")
	pirate.cargo[Commodity.Type.FUEL] = 2.0 * JumpRules.jump_cost(pirate)
	if not NpcJumpPlanner.fuel_allows(pirate, galaxy, to_a):
		failures.append("round trip: expected 2 jumps of fuel to allow ['a'] from home")
	var away := _fleet(PIRATE, COMBAT, "h_den", "a", 1.0)
	if not NpcJumpPlanner.fuel_allows(away, galaxy, to_h):
		failures.append("round trip: expected 1 jump of fuel to allow the path home ['h']")
	var stranded := _fleet(PIRATE, COMBAT, "h_den", "a", 0.5)
	if NpcJumpPlanner.fuel_allows(stranded, galaxy, to_h):
		failures.append("round trip: expected half a jump of fuel to refuse even the path home")
	if NpcJumpPlanner.path_home(away, galaxy) != to_h:
		failures.append("round trip: expected path_home ['h'] from a, got %s" % [NpcJumpPlanner.path_home(away, galaxy)])
	if not NpcJumpPlanner.path_home(pirate, galaxy).is_empty():
		failures.append("round trip: expected an empty path_home at home")

# Away fleets never fight in-system, so raids and hunts end on away_time, not on contact.
static func _check_dwell_limits(galaxy: Galaxy, failures: Array[String]) -> void:
	var raider := _fleet(PIRATE, COMBAT, "h_den", "a")
	var prey := _fleet(FREEHOLD, TRADER, "a_post", "a")
	var fleets: Array[CampaignFleet] = [raider, prey]
	raider.away_time = NpcJumpPlanner.RAID_DWELL - 1.0
	var got := _plan(raider, galaxy, fleets)
	if not got.is_empty():
		failures.append("dwell: expected a raider with prey to stay before RAID_DWELL, got %s" % [got])
	raider.away_time = NpcJumpPlanner.RAID_DWELL
	got = _plan(raider, galaxy, fleets)
	if got != ["h"]:
		failures.append("dwell: expected a raider past RAID_DWELL to head home ['h'] despite prey, got %s" % [got])

	var hunter := _fleet(FREEHOLD, COMBAT, "a_post", "b")
	var quarry := _fleet(PIRATE, COMBAT, "h_den", "b")
	fleets = [hunter, quarry]
	hunter.away_time = NpcJumpPlanner.HUNT_DWELL - 1.0
	got = _plan(hunter, galaxy, fleets)
	if not got.is_empty():
		failures.append("dwell: expected a hunting patrol to hold before HUNT_DWELL, got %s" % [got])
	hunter.away_time = NpcJumpPlanner.HUNT_DWELL
	got = _plan(hunter, galaxy, fleets)
	if got != ["a"]:
		failures.append("dwell: expected a patrol past HUNT_DWELL to head home ['a'] despite the pirate, got %s" % [got])
	# At home the dwell never applies: a patrol holds its own system against a raider.
	var home_guard := _fleet(FREEHOLD, COMBAT, "a_post", "a")
	var raiding := _fleet(PIRATE, COMBAT, "h_den", "a")
	fleets = [home_guard, raiding]
	home_guard.away_time = NpcJumpPlanner.HUNT_DWELL * 2.0
	got = _plan(home_guard, galaxy, fleets)
	if not got.is_empty():
		failures.append("dwell: expected a patrol at home to hold against a raider, got %s" % [got])
