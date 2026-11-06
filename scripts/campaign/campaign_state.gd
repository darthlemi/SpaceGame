extends Node

signal skirmish_resolved(winner_fleet: CampaignFleet, loser_fleet: CampaignFleet)
signal fleet_spawn_requested(fleet: CampaignFleet)
signal fleet_role_changed(fleet: CampaignFleet)
signal faction_reputation_changed(faction_enum: CampaignFleet.Faction)
signal fleet_jumped(fleet: CampaignFleet, from_system: String)
# The fleet has already left enemy_fleets; its icon should go too.
signal fleet_retired(fleet: CampaignFleet)
# A trader re-picked its destination outside an arrival; its icon must re-aim.
signal trade_destination_changed(fleet: CampaignFleet)

const FINE_PER_KILL := 150
const REPUTATION_LOSS_PER_DEFEAT := 15.0
const HOSTILE_REPUTATION_THRESHOLD := 40.0
const ECONOMY_TICK_INTERVAL := 5.0
const REPAIR_COST := 75
# Tuning placeholders.
const CREW_HIRE_COST := 40
const WAGE_PER_10_CREW := 1
const CREW_PER_WAGE_GROUP := 10
const DESERTION_RATE := 0.2
const RESPAWN_CREDIT_PENALTY := 0.25
const PIRATE_CREW_REGEN := 1
const FLEET_RESPAWN_DELAY := 60.0
const REENGAGE_DELAY := 10.0
const NPC_SPEED := {CampaignFleet.Role.COMBAT: 100.0, CampaignFleet.Role.TRADER: 80.0}
const TRADE_RANGE_JUMPS := 2
# A full tank covers the longest trade trip there and back, so the round-trip fuel rule
# (NpcJumpPlanner.fuel_allows) never keeps a hauler home from a partner in range.
const NPC_FUEL_TARGET_JUMPS := 2 * TRADE_RANGE_JUMPS
# Economy ticks of a station's own FUEL use held back from NPC refuels and trade loads, so they never
# starve its slots (an industrial slot burns 2 a tick). A station that burns none keeps no reserve.
const STATION_FUEL_RESERVE_TICKS := 5
const NPC_SPAWN_SCATTER := 40.0
const PLAYER_SPEED := 120.0
const PLAYER_STARTING_FUEL := 30.0
# Bases start below housing capacity so population has room to grow.
const STARTING_POPULATION_FRACTION := 0.75
# Opening stock as a fraction of Commodity.TARGET_STOCK for goods a station makes or burns, so
# prices differ from day one (2.0 -> 0.6x price band, 0.15 -> 1.6x). Neutral goods start at target.
const STARTING_STOCK_PRODUCED := 2.0
const STARTING_STOCK_CONSUMED := 0.15

var player_fleet: CampaignFleet
var enemy_fleets: Array[CampaignFleet] = []
var active_enemy_fleet: CampaignFleet
var pending_loot: LootOffer = null
var pending_respawn: bool = false
var factions: Array[PowerFaction] = []
var factions_at_war: bool = true
var active_skirmishes: Array[Skirmish] = []
var credits: int = 500
var home_base_economy: BaseEconomy = null
var galaxy: Galaxy = null
# system_id -> true. Discovered systems show on the jump map; visited ones also have a last_seen.
var discovered: Dictionary = {}
var visited: Dictionary = {}
# system_id -> {"owners": Array, "stations": int, "pirates_seen": bool, "tier": int} at the last visit.
var last_seen: Dictionary = {}
# Not cleared by reset(), so a seed set before new_game() holds.
var rng := RandomNumberGenerator.new()
var _economy_tick_elapsed: float = 0.0
# Seconds left before a fleet fought moments ago can be engaged again.
var _reengage_block: Dictionary = {}

func start_engagement(enemy_fleet: CampaignFleet) -> void:
	_drop_skirmishes_of(enemy_fleet)
	# Combat interrupts a countdown on either side, as a skirmish does.
	enemy_fleet.cancel_warp()
	if player_fleet != null:
		player_fleet.cancel_warp()
	active_enemy_fleet = enemy_fleet

# Ends the fleet's skirmishes unresolved and frees the other side to move.
func _drop_skirmishes_of(fleet: CampaignFleet) -> void:
	for skirmish in active_skirmishes.duplicate():
		if skirmish.fleet_winner == fleet or skirmish.fleet_loser == fleet:
			active_skirmishes.erase(skirmish)
			var other: CampaignFleetIcon = skirmish.icon_loser if skirmish.fleet_winner == fleet else skirmish.icon_winner
			if is_instance_valid(other):
				other.frozen = false

# Survivors are each side's ships left after escape rolls; captured are the losing side's
# caught comps. The legacy 2-arg call (enemy wiped out) still loots and erases the enemy.
func resolve_engagement(player_survivors: Array[Dictionary], enemy_survivors: Array[Dictionary], player_won: bool = false, captured: Array[Dictionary] = []) -> void:
	if player_fleet == null:
		return
	player_fleet.ship_compositions = player_survivors.duplicate(true)
	var enemy := active_enemy_fleet
	active_enemy_fleet = null
	if enemy != null:
		if player_won:
			_settle_enemy_defeat(enemy, enemy_survivors, captured)
		else:
			_settle_player_defeat(enemy, enemy_survivors, captured)
	player_fleet.ensure_flagship()
	if enemy != null and enemy_fleets.has(enemy) and not player_fleet.is_destroyed():
		_reengage_block[enemy] = REENGAGE_DELAY

static func is_damaged(comp: Dictionary) -> bool:
	if comp["current_hp"] < comp["max_hp"] or comp["current_shield"] < comp["max_shield"]:
		return true
	var engine_max: float = comp.get("engine_max_hp", 0.0)
	if engine_max > 0.0 and comp.get("engine_current_hp", engine_max) < engine_max:
		return true
	var mount_max: Array = comp.get("weapon_mount_max_hp", [])
	var mount_cur: Array = comp.get("weapon_mount_current_hp", [])
	for i in mount_max.size():
		if i < mount_cur.size() and mount_cur[i] < mount_max[i]:
			return true
	return false

static func repair_cost_for(comp: Dictionary) -> int:
	return REPAIR_COST if is_damaged(comp) else 0

func repair_ship(comp: Dictionary) -> void:
	credits -= REPAIR_COST
	comp["current_hp"] = comp["max_hp"]
	comp["current_shield"] = comp["max_shield"]
	if comp.has("engine_max_hp"):
		comp["engine_current_hp"] = comp["engine_max_hp"]
	if comp.has("weapon_mount_max_hp"):
		comp["weapon_mount_current_hp"] = (comp["weapon_mount_max_hp"] as Array).duplicate()

# Total loss: keeps reputation and fines, loses cargo, parts, ships and a share of credits.
# The new ship starts in the home station's system.
func begin_respawn() -> void:
	credits = floori(credits * (1.0 - RESPAWN_CREDIT_PENALTY))
	if player_fleet != null:
		player_fleet.cargo = {}
		player_fleet.part_inventory.clear()
		player_fleet.ship_compositions.clear()
		var home: StationData = galaxy.home_station() if galaxy != null else null
		if home != null:
			player_fleet.system_id = home.system_id
	pending_respawn = true

# buy false forces a free corvette; buy true pays SHIP_PRICE[kind] or fails.
func complete_respawn(kind: ShipType.Kind, buy: bool) -> bool:
	if player_fleet == null:
		return false
	var chosen := kind if buy else ShipType.Kind.CORVETTE
	if buy:
		if credits < ShipType.SHIP_PRICE[chosen]:
			return false
		credits -= ShipType.SHIP_PRICE[chosen]
	var comp := ShipType.new_composition(chosen)
	CrewRules.set_crew(comp, CrewRules.deploy_min_for(CrewRules.complement(comp)))
	player_fleet.ship_compositions.assign([comp])
	player_fleet.set_flagship(0)
	pending_respawn = false
	return true

# Game-time only, so it pauses with the game. A fleet that escaped would otherwise be
# re-engaged the same frame the player is still touching it.
func can_engage(fleet: CampaignFleet) -> bool:
	return not _reengage_block.has(fleet)

func tick_reengage(delta: float) -> void:
	for fleet in _reengage_block.keys():
		_reengage_block[fleet] -= delta
		if _reengage_block[fleet] <= 0.0 or not enemy_fleets.has(fleet):
			_reengage_block.erase(fleet)

func reset() -> void:
	player_fleet = null
	enemy_fleets = []
	active_enemy_fleet = null
	_reengage_block = {}
	pending_loot = null
	pending_respawn = false
	factions = []
	factions_at_war = true
	active_skirmishes = []
	credits = 500
	home_base_economy = null
	galaxy = null
	discovered = {}
	visited = {}
	last_seen = {}
	_economy_tick_elapsed = 0.0

func new_game() -> void:
	reset()
	galaxy = GalaxyData.build()
	for station in galaxy.stations:
		_seed_economy(station.economy, station.starting_stock)
	var home := galaxy.home_station()
	home_base_economy = home.economy
	factions.assign([_new_power_faction(CampaignFleet.Faction.DOMINION, "Dominion"), _new_power_faction(CampaignFleet.Faction.FREEHOLD, "Freehold")])
	factions_at_war = true
	player_fleet = _new_player_fleet(home)
	build_station_plans()
	for station in galaxy.stations:
		for role in station.fleet_plan:
			for variant in station.fleet_plan[role]:
				spawn_station_fleet(station, role, variant)
	record_visit(player_fleet.system_id)

# The quota is each role's minimum fleet count; a rich station gets more and bigger fleets on top.
func build_station_plans() -> void:
	for station in galaxy.stations:
		station.fleet_plan = {}
		var budget := FleetBudget.ship_budget(_tier_of(station), station.economy)
		for role in station.fleet_quota:
			station.fleet_plan[role] = FleetBudget.build_plan(_tier_of(station), role, budget, station.fleet_quota[role], rng)

# The snapshot is what the jump map shows for this system until the next visit.
func record_visit(system_id: String) -> void:
	var sys: StarSystem = galaxy.system(system_id) if galaxy != null else null
	if sys == null:
		return
	visited[system_id] = true
	discovered[system_id] = true
	for neighbour in sys.links:
		discovered[neighbour] = true
	var owners: Array = []
	for station in galaxy.stations_in(system_id):
		owners.append(station.owner)
	var pirates_seen := false
	for fleet in enemy_fleets:
		if fleet.system_id == system_id and fleet.faction == CampaignFleet.Faction.PIRATE:
			pirates_seen = true
			break
	last_seen[system_id] = {"owners": owners, "stations": owners.size(), "pirates_seen": pirates_seen, "tier": sys.tier}

# "" when the player may jump to dest_id; otherwise the first reason it can't.
func jump_block_reason(dest_id: String, hostile_contact: bool) -> String:
	if player_fleet == null or galaxy == null or not galaxy.are_linked(player_fleet.system_id, dest_id):
		return "Not connected"
	if player_fleet.is_warping():
		return "Warp already charging"
	if hostile_contact:
		return "Hostile fleet in contact"
	if not JumpRules.can_afford(player_fleet):
		return "Not enough fuel (need %.1f, have %.1f)" % [JumpRules.jump_cost(player_fleet), player_fleet.fuel_amount()]
	return ""

func begin_player_warp(dest_id: String, hostile_contact: bool) -> bool:
	if jump_block_reason(dest_id, hostile_contact) != "":
		return false
	player_fleet.start_warp(dest_id)
	return true

# Game time: the caller only ticks while unpaused, so warps pause and speed up with the game.
func tick_warps(delta: float) -> void:
	var fleets: Array[CampaignFleet] = []
	if player_fleet != null:
		fleets.append(player_fleet)
	fleets.append_array(enemy_fleets)
	for fleet in fleets:
		if not fleet.is_warping():
			continue
		fleet.warp_remaining -= delta
		if fleet.warp_remaining <= 0.0:
			complete_warp(fleet)

# Fuel is spent only here, so a cancelled countdown costs nothing.
func complete_warp(fleet: CampaignFleet) -> void:
	var from_id := fleet.system_id
	var origin: StarSystem = galaxy.system(from_id) if galaxy != null else null
	var dest: StarSystem = galaxy.system(fleet.warp_target) if galaxy != null else null
	assert(origin != null and dest != null, "complete_warp: unknown system %s or %s" % [from_id, fleet.warp_target])
	if origin == null or dest == null:
		fleet.cancel_warp()
		return
	# Fuel can fall (jettison) or the cost rise (a grown ship) during the countdown: no jump on fumes.
	if not JumpRules.can_afford(fleet):
		fleet.cancel_warp()
		if fleet != player_fleet:
			fleet.jump_path.clear()
		return
	fleet.cargo[Commodity.Type.FUEL] = maxf(0.0, fleet.fuel_amount() - JumpRules.jump_cost(fleet))
	fleet.system_id = dest.id
	fleet.position = JumpRules.arrival_point(origin.map_position, dest.map_position, rng)
	fleet.cancel_warp()
	if fleet == player_fleet:
		record_visit(from_id)
		record_visit(dest.id)
	else:
		_advance_npc_route(fleet, dest.id)
	fleet_jumped.emit(fleet, from_id)

# Game time, like tick_warps. A fleet in a countdown or a skirmish makes no decisions.
func tick_npc_jumps(delta: float) -> void:
	if galaxy == null:
		return
	var stranded: Array[CampaignFleet] = []
	for fleet in enemy_fleets:
		var home := _home_station_of(fleet)
		fleet.away_time = fleet.away_time + delta if home != null and fleet.system_id != home.system_id else 0.0
		if fleet.is_warping() or _in_skirmish(fleet):
			continue
		fleet.jump_cooldown -= delta
		if fleet.jump_cooldown > 0.0:
			continue
		_decide_npc_jump(fleet)
		fleet.jump_cooldown = NpcJumpPlanner.DECISION_INTERVAL + rng.randf() * NpcJumpPlanner.DECISION_JITTER
		if not fleet.is_warping() and _is_stranded(fleet):
			stranded.append(fleet)
	for fleet in stranded:
		retire_npc(fleet)

# A fleet that can never act again leaves the roster, so its station's respawn replaces it.
func retire_npc(fleet: CampaignFleet) -> void:
	if fleet == active_enemy_fleet or not enemy_fleets.has(fleet):
		return
	_drop_skirmishes_of(fleet)
	fleet.cancel_warp()
	enemy_fleets.erase(fleet)
	fleet_retired.emit(fleet)

# Away, short of the fuel home, and in a system with no station it may ever refuel at.
func _is_stranded(fleet: CampaignFleet) -> bool:
	var home := _home_station_of(fleet)
	if home == null or fleet.system_id == home.system_id:
		return false
	if NpcJumpPlanner.fuel_allows(fleet, galaxy, NpcJumpPlanner.path_home(fleet, galaxy)):
		return false
	for station in galaxy.stations_in(fleet.system_id):
		if can_refuel_at(fleet, station):
			return false
	return true

# Pirates refuel only at pirate stations; every other NPC at any station it may trade with.
func can_refuel_at(fleet: CampaignFleet, station: StationData) -> bool:
	if fleet.faction == CampaignFleet.Faction.PIRATE:
		return station.owner == CampaignFleet.Faction.PIRATE
	return _is_trade_partner(fleet.faction, station.owner)

# Free, from the station's FUEL above its reserve, up to NPC_FUEL_TARGET_JUMPS jumps;
# a short stock gives what it can spare.
func refuel_npc(fleet: CampaignFleet, station: StationData) -> void:
	if station == null or station.economy == null:
		return
	var wanted := NPC_FUEL_TARGET_JUMPS * JumpRules.jump_cost(fleet) - fleet.fuel_amount()
	var spare: float = station.economy.stock.get(Commodity.Type.FUEL, 0.0) - _fuel_reserve(station.economy)
	var taken := minf(wanted, spare)
	if taken <= 0.0:
		return
	station.economy.stock[Commodity.Type.FUEL] -= taken
	fleet.cargo[Commodity.Type.FUEL] = fleet.fuel_amount() + taken

static func _fuel_reserve(economy: BaseEconomy) -> float:
	var per_tick := 0.0
	for slot in economy.slots:
		per_tick += slot.consumes.get(Commodity.Type.FUEL, 0.0)
	return per_tick * STATION_FUEL_RESERVE_TICKS

# A stored route resumes while fuel allows; otherwise replan, falling back to home, then to staying.
func _decide_npc_jump(fleet: CampaignFleet) -> void:
	if not fleet.jump_path.is_empty() and galaxy.are_linked(fleet.system_id, fleet.jump_path[0]) and NpcJumpPlanner.fuel_allows(fleet, galaxy, fleet.jump_path):
		fleet.start_warp(fleet.jump_path[0])
		return
	if fleet.role == CampaignFleet.Role.TRADER:
		_repick_trade_destination(fleet)
	var path := NpcJumpPlanner.plan(fleet, galaxy, enemy_fleets, are_hostile)
	if not NpcJumpPlanner.fuel_allows(fleet, galaxy, path):
		path = NpcJumpPlanner.path_home(fleet, galaxy)
		if not NpcJumpPlanner.fuel_allows(fleet, galaxy, path):
			path.clear()
	fleet.jump_path = path
	if not path.is_empty():
		fleet.start_warp(path[0])

# At home, a trader with no destination, or one it can't fuel, picks again rather than wait for ever.
func _repick_trade_destination(fleet: CampaignFleet) -> void:
	var home := _home_station_of(fleet)
	if home == null or fleet.system_id != home.system_id or fleet.dest_station_id == home.id:
		return
	var dest: StationData = galaxy.station(fleet.dest_station_id)
	if dest != null and NpcJumpPlanner.fuel_allows(fleet, galaxy, galaxy.path(fleet.system_id, dest.system_id)):
		return
	var picked := _best_trade_partner(fleet, home)
	if picked != fleet.dest_station_id:
		fleet.dest_station_id = picked
		trade_destination_changed.emit(fleet)

# Pops the hop just made; a stale route (the warp wasn't its next hop) is dropped.
func _advance_npc_route(fleet: CampaignFleet, arrived_id: String) -> void:
	if not fleet.jump_path.is_empty() and fleet.jump_path[0] == arrived_id:
		fleet.jump_path.remove_at(0)
	else:
		fleet.jump_path.clear()
	if not fleet.jump_path.is_empty():
		fleet.jump_cooldown = NpcJumpPlanner.HOP_DELAY
		return
	var home := _home_station_of(fleet)
	if fleet.role == CampaignFleet.Role.COMBAT and home != null and arrived_id == home.system_id:
		fleet.jump_cooldown = NpcJumpPlanner.HOME_REST

func _in_skirmish(fleet: CampaignFleet) -> bool:
	for skirmish in active_skirmishes:
		if skirmish.fleet_winner == fleet or skirmish.fleet_loser == fleet:
			return true
	return false

# Every NPC tops up at the stations it may use in its system, home first, so one that docked while
# a stock was short, or that ran low away from home, isn't stuck.
func _refuel_npcs() -> void:
	if galaxy == null:
		return
	for fleet in enemy_fleets:
		var home := _home_station_of(fleet)
		if home != null and fleet.system_id == home.system_id:
			refuel_npc(fleet, home)
		for station in galaxy.stations_in(fleet.system_id):
			if station != home and can_refuel_at(fleet, station):
				refuel_npc(fleet, station)

# Free and instant, like crew: a fleet that limped home can raid or patrol again.
func _repair_npcs_at_home() -> void:
	for fleet in enemy_fleets:
		var home := _home_station_of(fleet)
		if home != null and fleet.system_id == home.system_id and not _in_skirmish(fleet):
			fleet.repair_to_full()

# Buys exactly the shortfall for a jump at the distress premium; false when the quote isn't ok.
func send_distress() -> bool:
	if player_fleet == null:
		return false
	var quote := JumpRules.distress_quote(player_fleet, credits)
	if not quote["ok"]:
		return false
	credits -= int(quote["price"])
	player_fleet.cargo[Commodity.Type.FUEL] = player_fleet.fuel_amount() + float(quote["fuel"])
	return true

func tick_economy(delta: float) -> void:
	_economy_tick_elapsed += delta
	while _economy_tick_elapsed >= ECONOMY_TICK_INTERVAL:
		_economy_tick_elapsed -= ECONOMY_TICK_INTERVAL
		pay_wages()
		if galaxy != null:
			for station in galaxy.stations:
				if station.economy != null:
					station.economy.tick()
					if _is_power_faction(station.owner):
						_apply_station_allocation(station)
				_tick_station_respawns(station, ECONOMY_TICK_INTERVAL)
		_refuel_npcs()
		_repair_npcs_at_home()
		_refill_npc_crew()

static func fleet_faction_for(owner: CampaignFleet.Faction, role: CampaignFleet.Role) -> CampaignFleet.Faction:
	if owner == CampaignFleet.Faction.NEUTRAL:
		return CampaignFleet.Faction.TRADER if role == CampaignFleet.Role.TRADER else CampaignFleet.Faction.NEUTRAL
	return owner

func spawn_station_fleet(station: StationData, role: CampaignFleet.Role, variant: DangerTier.Variant = DangerTier.Variant.PATROL) -> CampaignFleet:
	var fleet := CampaignFleet.new()
	fleet.ship_compositions = DangerTier.fleet_for_variant(_tier_of(station), variant, rng)
	fleet.variant = variant
	fleet.faction = fleet_faction_for(station.owner, role)
	fleet.role = role
	fleet.home_station_id = station.id
	fleet.system_id = station.system_id
	fleet.speed = NPC_SPEED[role]
	fleet.position = station.position + Vector2(rng.randf_range(-NPC_SPAWN_SCATTER, NPC_SPAWN_SCATTER), rng.randf_range(-NPC_SPAWN_SCATTER, NPC_SPAWN_SCATTER))
	fleet.cargo = {Commodity.Type.FUEL: NPC_FUEL_TARGET_JUMPS * JumpRules.jump_cost(fleet)}
	# Staggered, so a new galaxy's fleets don't all make their first jump decision in one frame.
	fleet.jump_cooldown = rng.randf() * NpcJumpPlanner.DECISION_INTERVAL
	enemy_fleets.append(fleet)
	fleet_spawn_requested.emit(fleet)
	return fleet

func is_hostile_to_player(fleet: CampaignFleet) -> bool:
	if fleet.faction == CampaignFleet.Faction.PIRATE:
		return true
	if not _is_power_faction(fleet.faction):
		return false
	var faction := power_faction_for(fleet.faction)
	return faction != null and faction.reputation < HOSTILE_REPUTATION_THRESHOLD

func stations_of(owner: CampaignFleet.Faction) -> Array[StationData]:
	var result: Array[StationData] = []
	if galaxy == null:
		return result
	for station in galaxy.stations:
		if station.owner == owner:
			result.append(station)
	return result

func station_fleets(station: StationData, role: CampaignFleet.Role) -> Array[CampaignFleet]:
	var result: Array[CampaignFleet] = []
	for fleet in enemy_fleets:
		if fleet.home_station_id == station.id and fleet.role == role:
			result.append(fleet)
	return result

func _new_player_fleet(home: StationData) -> CampaignFleet:
	var player := CampaignFleet.new()
	player.faction = CampaignFleet.Faction.PLAYER
	player.system_id = home.system_id
	player.position = home.position
	player.speed = PLAYER_SPEED
	player.ship_compositions = [
		{"ship_type": ShipType.Kind.CORVETTE, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"ship_type": ShipType.Kind.CAPITAL, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"ship_type": ShipType.Kind.FREIGHTER, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
	]
	player.cargo = {Commodity.Type.FUEL: PLAYER_STARTING_FUEL}
	player.ensure_flagship()
	return player

func _new_power_faction(faction_enum: CampaignFleet.Faction, display_name: String) -> PowerFaction:
	var faction := PowerFaction.new()
	faction.faction_enum = faction_enum
	faction.display_name = display_name
	faction.reputation = 60.0
	return faction

func _seed_economy(economy: BaseEconomy, starting_stock: Dictionary) -> void:
	for commodity in Commodity.Type.values():
		economy.stock[commodity] = float(starting_stock.get(commodity, _default_start_stock(economy, commodity)))
	economy.population = economy.population_capacity() * STARTING_POPULATION_FRACTION
	economy.crew_pool = economy.crew_pool_cap()

# Net producers open overstocked (cheap), net consumers open short (dear); explicit data wins.
func _default_start_stock(economy: BaseEconomy, commodity: int) -> float:
	var net: float = economy.net_commodities().get(commodity, 0.0)
	var factor := 1.0
	if net > 0.0:
		factor = STARTING_STOCK_PRODUCED
	elif net < 0.0:
		factor = STARTING_STOCK_CONSUMED
	return Commodity.TARGET_STOCK[commodity] * factor

func _tier_of(station: StationData) -> int:
	var sys: StarSystem = galaxy.system(station.system_id) if galaxy != null else null
	return sys.tier if sys != null else DangerTier.MIN_TIER

# A variant slot under plan accumulates time; at the delay the whole deficit returns and the timer
# restarts. Slots count by variant, not role, so a trader flipped to COMBAT still fills its convoy slot.
func _tick_station_respawns(station: StationData, elapsed: float) -> void:
	if station.fleet_plan.is_empty():
		return
	var budget := FleetBudget.ship_budget(_tier_of(station), station.economy)
	for role in station.fleet_plan:
		var planned := {}
		for variant in station.fleet_plan[role]:
			planned[variant] = planned.get(variant, 0) + 1
		for variant in planned:
			var key := "%d:%d" % [role, variant]
			var deficit: int = planned[variant] - _variant_fleet_count(station, variant)
			if deficit <= 0:
				station.respawn_timers[key] = 0.0
				continue
			station.respawn_timers[key] = station.respawn_timers.get(key, 0.0) + elapsed
			if station.respawn_timers[key] >= FleetBudget.respawn_delay(variant, _tier_of(station), budget):
				for _i in deficit:
					spawn_station_fleet(station, role, variant)
				station.respawn_timers[key] = 0.0

func _variant_fleet_count(station: StationData, variant: int) -> int:
	var count := 0
	for fleet in enemy_fleets:
		if fleet.home_station_id == station.id and fleet.variant == variant:
			count += 1
	return count

# The flagship's deploy minimum is never billed or deserted, so the player can't be stranded.
func flagship_floor(fleet: CampaignFleet) -> int:
	var index := fleet.flagship_index()
	if index < 0:
		return 0
	return CrewRules.deploy_min_for(CrewRules.complement(fleet.ship_compositions[index]))

# Crew moves to free berths on the other ships; only the excess is lost.
func scuttle_check(fleet: CampaignFleet, index: int) -> Dictionary:
	var result := {"allowed": false, "crew_lost": 0, "cargo_overflow": 0.0, "reason": ""}
	if index < 0 or index >= fleet.ship_compositions.size():
		result["reason"] = "No such ship"
		return result
	if CrewRules.is_flagship(fleet.ship_compositions[index]):
		result["reason"] = "Flagship"
		return result
	if fleet.ship_compositions.size() <= 1:
		result["reason"] = "Last ship"
		return result
	var comp: Dictionary = fleet.ship_compositions[index]
	result["allowed"] = true
	result["crew_lost"] = maxi(0, CrewRules.crew_of(comp) - CrewRules.free_berths(_others(fleet, index)))
	var capacity_without := fleet.cargo_capacity() - ShipType.cargo_capacity_for(ShipType.kind_of(comp))
	result["cargo_overflow"] = maxf(0.0, fleet.cargo_total() - capacity_without)
	return result

func scuttle_ship(fleet: CampaignFleet, index: int) -> bool:
	var check := scuttle_check(fleet, index)
	if not check["allowed"] or check["cargo_overflow"] > 0.0:
		return false
	var others := _others(fleet, index)
	CrewRules.add_crew(others, CrewRules.crew_of(fleet.ship_compositions[index]))
	fleet.ship_compositions.remove_at(index)
	fleet.ensure_flagship()
	return true

# crew_by_ship maps ship index -> crew to throw overboard.
func jettison(fleet: CampaignFleet, cargo_amounts: Dictionary, part_indices: Array[int], crew_by_ship: Dictionary) -> void:
	for commodity in cargo_amounts:
		var held: float = fleet.cargo.get(commodity, 0.0)
		fleet.cargo[commodity] = held - clampf(cargo_amounts[commodity], 0.0, held)
	var sorted_indices := part_indices.duplicate()
	sorted_indices.sort()
	sorted_indices.reverse()
	var last := -1
	for part_index in sorted_indices:
		if part_index == last or part_index < 0 or part_index >= fleet.part_inventory.size():
			continue
		fleet.part_inventory.remove_at(part_index)
		last = part_index
	var floor_crew := flagship_floor(fleet)
	var flagship := fleet.flagship_index()
	for ship_index in crew_by_ship:
		if ship_index < 0 or ship_index >= fleet.ship_compositions.size():
			continue
		var comp: Dictionary = fleet.ship_compositions[ship_index]
		var lowest := floor_crew if ship_index == flagship else 0
		CrewRules.set_crew(comp, maxi(lowest, CrewRules.crew_of(comp) - maxi(0, int(crew_by_ship[ship_index]))))

func _others(fleet: CampaignFleet, index: int) -> Array[Dictionary]:
	var others: Array[Dictionary] = []
	for i in fleet.ship_compositions.size():
		if i != index:
			others.append(fleet.ship_compositions[i])
	return others

# Wages are paid per full group of CREW_PER_WAGE_GROUP billable crew; a remainder is free.
func wage_bill(fleet: CampaignFleet) -> int:
	return _wage_groups(fleet) * WAGE_PER_10_CREW

func pay_wages() -> void:
	if player_fleet == null:
		return
	var payable := _billable_crew(player_fleet)
	var groups := _wage_groups(player_fleet)
	if groups <= 0:
		return
	if credits >= groups * WAGE_PER_10_CREW:
		credits -= groups * WAGE_PER_10_CREW
		return
	var paid_groups := mini(groups, floori(credits / float(WAGE_PER_10_CREW)))
	credits -= paid_groups * WAGE_PER_10_CREW
	var unpaid_groups := groups - paid_groups
	var deserters := clampi(maxi(1, roundi(unpaid_groups * CREW_PER_WAGE_GROUP * DESERTION_RATE)), 0, payable)
	CrewRules.remove_crew(player_fleet.ship_compositions, deserters, player_fleet.flagship_index(), flagship_floor(player_fleet))

func hire_crew(economy: BaseEconomy, fleet: CampaignFleet, count: int) -> bool:
	if count < 1 or count > floori(economy.crew_pool) or count > CrewRules.free_berths(fleet.ship_compositions):
		return false
	var cost := count * CREW_HIRE_COST
	if credits < cost:
		return false
	credits -= cost
	economy.crew_pool -= count
	CrewRules.add_crew(fleet.ship_compositions, count)
	return true

func buy(base_economy: BaseEconomy, commodity: int, fleet: CampaignFleet) -> bool:
	var price: int = base_economy.price_for(commodity)
	var stock: float = base_economy.stock.get(commodity, 0.0)
	if credits < price or stock < 1.0 or fleet.cargo_total() + 1.0 > fleet.cargo_capacity():
		return false
	credits -= price
	base_economy.stock[commodity] = stock - 1.0
	fleet.cargo[commodity] = fleet.cargo.get(commodity, 0.0) + 1.0
	return true

func sell(base_economy: BaseEconomy, commodity: int, fleet: CampaignFleet) -> bool:
	var held: float = fleet.cargo.get(commodity, 0.0)
	if held < 1.0:
		return false
	var price: int = base_economy.sell_price_for(commodity)
	credits += price
	fleet.cargo[commodity] = held - 1.0
	base_economy.stock[commodity] = base_economy.stock.get(commodity, 0.0) + 1.0
	return true

func buy_part(path: String, fleet: CampaignFleet) -> bool:
	var item: Resource = load(path)
	var price: int = PartRarity.price_for(item.rarity)
	if credits < price or fleet.cargo_total() + 1.0 > fleet.cargo_capacity():
		return false
	credits -= price
	fleet.part_inventory.append(path)
	return true

func sell_part(fleet: CampaignFleet, inventory_index: int) -> bool:
	if inventory_index < 0 or inventory_index >= fleet.part_inventory.size():
		return false
	var path: String = fleet.part_inventory[inventory_index]
	var item: Resource = load(path)
	credits += PartRarity.sell_price_for(item.rarity)
	fleet.part_inventory.remove_at(inventory_index)
	return true

func equip_part(comp: Dictionary, fleet: CampaignFleet, slot_type: ShipType.SlotType, slot_index: int, inventory_index: int) -> bool:
	if is_damaged(comp):
		return false
	if inventory_index < 0 or inventory_index >= fleet.part_inventory.size():
		return false
	var new_path: String = fleet.part_inventory[inventory_index]
	var new_item: Resource = load(new_path)
	match slot_type:
		ShipType.SlotType.WEAPON:
			if not new_item is Weapon:
				return false
		ShipType.SlotType.SHIELD:
			if not new_item is ShieldGenerator:
				return false
		ShipType.SlotType.ENGINE:
			if not new_item is EngineCore:
				return false
	var old_path := ShipType.equipped_path(comp, slot_type, slot_index)
	var budget := ShipType.points_budget_for(ShipType.kind_of(comp))
	var projected := ShipType.points_used(comp) - ShipType.points_of_path(old_path) + PartRarity.points_for(new_item.rarity)
	if projected > budget:
		return false
	fleet.part_inventory.remove_at(inventory_index)
	if old_path != "":
		fleet.part_inventory.append(old_path)
	ShipType.set_equipped_path(comp, slot_type, slot_index, new_path)
	if slot_type == ShipType.SlotType.SHIELD:
		var old_max: float = comp["max_shield"]
		comp["max_shield"] = new_item.max_shield
		comp["current_shield"] = new_item.max_shield if old_max <= 0.0 else comp["current_shield"] * (new_item.max_shield / old_max)
	return true

func pay_fine(faction_enum: CampaignFleet.Faction) -> bool:
	var faction := power_faction_for(faction_enum)
	if faction == null or faction.fine <= 0 or credits < faction.fine:
		return false
	credits -= faction.fine
	faction.reputation += faction.fine_reputation
	faction.fine = 0
	faction.fine_reputation = 0.0
	faction_reputation_changed.emit(faction_enum)
	return true

func are_hostile(fleet_a: CampaignFleet, fleet_b: CampaignFleet) -> bool:
	return _factions_hostile(fleet_a.faction, fleet_b.faction)

# Pirates fight every patrol, power or NEUTRAL. A NEUTRAL fleet is always a patrol: neutral haulers
# are TRADER (fleet_faction_for).
func _factions_hostile(a: CampaignFleet.Faction, b: CampaignFleet.Faction) -> bool:
	var pirate := CampaignFleet.Faction.PIRATE
	if a == pirate or b == pirate:
		var other := b if a == pirate else a
		return _is_power_faction(other) or other == CampaignFleet.Faction.NEUTRAL
	if _is_power_faction(a) and _is_power_faction(b) and a != b:
		return factions_at_war
	return false

func start_skirmish(icon_a: CampaignFleetIcon, icon_b: CampaignFleetIcon) -> void:
	if icon_a.frozen or icon_b.frozen:
		return
	icon_a.fleet.cancel_warp()
	icon_b.fleet.cancel_warp()
	var strength_a := icon_a.fleet.total_strength()
	var strength_b := icon_b.fleet.total_strength()
	var imbalance_value := SkirmishResolution.imbalance(strength_a, strength_b)

	var skirmish := Skirmish.new()
	skirmish.remaining_time = SkirmishResolution.duration(imbalance_value)
	skirmish.winner_damage_fraction = SkirmishResolution.winner_damage_fraction(imbalance_value)
	if strength_a >= strength_b:
		skirmish.fleet_winner = icon_a.fleet
		skirmish.fleet_loser = icon_b.fleet
		skirmish.icon_winner = icon_a
		skirmish.icon_loser = icon_b
	else:
		skirmish.fleet_winner = icon_b.fleet
		skirmish.fleet_loser = icon_a.fleet
		skirmish.icon_winner = icon_b
		skirmish.icon_loser = icon_a

	icon_a.frozen = true
	icon_b.frozen = true
	active_skirmishes.append(skirmish)

func tick_skirmishes(delta: float) -> void:
	for skirmish in active_skirmishes.duplicate():
		skirmish.remaining_time -= delta
		if skirmish.remaining_time <= 0.0:
			_resolve_skirmish(skirmish)

func cancel_skirmish_for(icon: CampaignFleetIcon) -> void:
	for skirmish in active_skirmishes.duplicate():
		if skirmish.icon_winner == icon or skirmish.icon_loser == icon:
			active_skirmishes.erase(skirmish)
			var other: CampaignFleetIcon = skirmish.icon_loser if skirmish.icon_winner == icon else skirmish.icon_winner
			if is_instance_valid(other):
				other.frozen = false

func _resolve_skirmish(skirmish: Skirmish) -> void:
	if not (is_instance_valid(skirmish.icon_winner) and is_instance_valid(skirmish.icon_loser)):
		active_skirmishes.erase(skirmish)
		return
	active_skirmishes.erase(skirmish)
	skirmish.fleet_winner.apply_fractional_damage(skirmish.winner_damage_fraction)
	_apply_winner_crew_loss(skirmish.fleet_winner, skirmish.winner_damage_fraction)
	enemy_fleets.erase(skirmish.fleet_loser)
	if is_instance_valid(skirmish.icon_loser):
		skirmish.icon_loser.queue_free()
	if is_instance_valid(skirmish.icon_winner):
		skirmish.icon_winner.frozen = false
	skirmish_resolved.emit(skirmish.fleet_winner, skirmish.fleet_loser)

# Crew falls with the same fraction as hull, but a surviving NPC ship is never emptied.
func _apply_winner_crew_loss(fleet: CampaignFleet, damage_fraction: float) -> void:
	for comp in fleet.ship_compositions:
		CrewRules.set_crew(comp, maxi(CrewRules.NPC_CREW_FLOOR, roundi(CrewRules.crew_of(comp) * (1.0 - damage_fraction))))
	CrewRules.balance(fleet.ship_compositions)

# Pirates regenerate for free; every other NPC draws from its home station's pool.
func _refill_npc_crew() -> void:
	for fleet in enemy_fleets:
		if fleet.faction == CampaignFleet.Faction.PIRATE:
			CrewRules.add_crew(fleet.ship_compositions, PIRATE_CREW_REGEN)
		else:
			var home: StationData = galaxy.station(fleet.home_station_id) if galaxy != null else null
			if home == null or home.economy == null:
				continue
			var added := CrewRules.add_crew(fleet.ship_compositions, floori(home.economy.crew_pool))
			home.economy.crew_pool -= added
		CrewRules.balance(fleet.ship_compositions)

func _wage_groups(fleet: CampaignFleet) -> int:
	return floori(_billable_crew(fleet) / float(CREW_PER_WAGE_GROUP))

func _billable_crew(fleet: CampaignFleet) -> int:
	var index := fleet.flagship_index()
	var exempt := 0
	if index >= 0:
		exempt = mini(CrewRules.crew_of(fleet.ship_compositions[index]), flagship_floor(fleet))
	return fleet.crew_total() - exempt

func _is_power_faction(faction: CampaignFleet.Faction) -> bool:
	return faction == CampaignFleet.Faction.DOMINION or faction == CampaignFleet.Faction.FREEHOLD

# escapers stay on the map with the cargo share they carry; captured ships go to the loot.
func _settle_enemy_defeat(enemy: CampaignFleet, escapers: Array[Dictionary], captured: Array[Dictionary]) -> void:
	var lost_ships := not captured.is_empty() or escapers.size() < enemy.ship_compositions.size()
	var survivors := CampaignFleet.new()
	survivors.ship_compositions.assign(captured + escapers)
	survivors.cargo = enemy.cargo
	survivors.part_inventory = enemy.part_inventory
	var captured_indices: Array[int] = []
	for i in captured.size():
		captured_indices.append(i)
	var split := BattleResolution.split_cargo(survivors, captured_indices)
	enemy.ship_compositions = escapers.duplicate(true)
	enemy.cargo = split["kept_cargo"]
	enemy.part_inventory.assign(split["kept_parts"])
	if lost_ships:
		_apply_reputation_loss(enemy.faction)
	if enemy.ship_compositions.is_empty():
		enemy_fleets.erase(enemy)
	# A total loss respawns at home base; there is no one left to take the loot.
	if player_fleet.is_destroyed():
		return
	var offer := LootOffer.new()
	offer.cargo = split["loot_cargo"]
	offer.parts.assign(split["loot_parts"])
	offer.ships.assign(captured.duplicate(true))
	if not offer.is_empty():
		pending_loot = offer

# Captured comps keep their crew and bring their cargo share; extras past the fleet cap are scuttled.
func _settle_player_defeat(enemy: CampaignFleet, enemy_survivors: Array[Dictionary], captured: Array[Dictionary]) -> void:
	var comps: Array[Dictionary] = enemy_survivors.duplicate(true)
	for comp in captured:
		if comps.size() >= FleetAllocationPolicy.MAX_SHIPS_PER_FLEET:
			break
		var taken: Dictionary = comp.duplicate(true)
		taken["flagship"] = false
		taken["deploy"] = true
		comps.append(taken)
	if comps.is_empty():
		# Mutual wipe: the enemy is gone too.
		_settle_enemy_defeat(enemy, comps, [])
		return
	# Symmetric to an enemy defeat: the captured ships' share of the player's cargo goes to the enemy.
	var holdings := CampaignFleet.new()
	holdings.ship_compositions.assign(player_fleet.ship_compositions + captured)
	holdings.cargo = player_fleet.cargo
	holdings.part_inventory = player_fleet.part_inventory
	var captured_indices: Array[int] = []
	for i in captured.size():
		captured_indices.append(player_fleet.ship_compositions.size() + i)
	var split := BattleResolution.split_cargo(holdings, captured_indices)
	player_fleet.cargo = split["kept_cargo"]
	player_fleet.part_inventory.assign(split["kept_parts"])
	for commodity in split["loot_cargo"]:
		enemy.cargo[commodity] = enemy.cargo.get(commodity, 0.0) + split["loot_cargo"][commodity]
	enemy.part_inventory.append_array(split["loot_parts"])
	enemy.ship_compositions = comps
	CrewRules.balance(enemy.ship_compositions)

func _apply_reputation_loss(defeated_faction: CampaignFleet.Faction) -> void:
	for power_faction in factions:
		if power_faction.faction_enum == defeated_faction:
			# Track the actual loss (clamped at 0) so paying the fine restores exactly that.
			var loss: float = min(power_faction.reputation, REPUTATION_LOSS_PER_DEFEAT)
			power_faction.reputation -= loss
			power_faction.fine += FINE_PER_KILL
			power_faction.fine_reputation += loss
			faction_reputation_changed.emit(defeated_faction)

# At home: unload everything, then load home's surplus. Elsewhere: unload there, then load what home
# needs out of that station's own surplus, so a trader never strips a partner of what it consumes.
func run_npc_trade_at(fleet: CampaignFleet, station: StationData) -> void:
	var home := _home_station_of(fleet)
	if home == null or station == null or home.economy == null or station.economy == null:
		return
	# The jump tank stays aboard; only hauled FUEL above it unloads, so a stop below its reserve can't
	# keep the fuel the trader needs to get home.
	var tank := minf(fleet.fuel_amount(), NPC_FUEL_TARGET_JUMPS * JumpRules.jump_cost(fleet))
	for commodity in fleet.cargo:
		var amount: float = fleet.cargo[commodity]
		if commodity == Commodity.Type.FUEL:
			amount -= tank
		if amount > 0.0:
			station.economy.stock[commodity] = station.economy.stock.get(commodity, 0.0) + amount
	fleet.cargo = {Commodity.Type.FUEL: tank}
	refuel_npc(fleet, station)
	var goods := _home_trade_goods(home, station == home)
	if station == home:
		goods = _goods_wanted_by(goods, galaxy.station(_best_trade_partner(fleet, home)))
	_load_trade_goods(fleet, goods, station.economy)

# Home after every away stop. From home: see _best_trade_partner.
func next_trade_destination(fleet: CampaignFleet) -> String:
	var home := _home_station_of(fleet)
	if home == null:
		return ""
	if fleet.dest_station_id != home.id:
		return home.id
	return _best_trade_partner(fleet, home)

# The in-range partner whose haul is worth most (see _route_value), among those the fleet can fuel
# there and back; ties to fewer jumps, then the shorter in-system distance; "" when there is none.
func _best_trade_partner(fleet: CampaignFleet, home: StationData) -> String:
	var needs := _home_trade_goods(home, false)
	var exports := _home_trade_goods(home, true)
	var best: StationData = null
	var best_score := 0.0
	var best_jumps := 0
	var best_dist := 0.0
	var neutral_trader := fleet.faction == CampaignFleet.Faction.TRADER
	for station in galaxy.stations:
		if station == home or not _is_trade_partner(fleet.faction, station.owner):
			continue
		# Neutral traders haul between neutral stations only.
		if neutral_trader and station.owner != CampaignFleet.Faction.NEUTRAL:
			continue
		var jumps := galaxy.jump_distance(home.system_id, station.system_id)
		if jumps < 0 or jumps > TRADE_RANGE_JUMPS:
			continue
		if not NpcJumpPlanner.fuel_allows(fleet, galaxy, galaxy.path(home.system_id, station.system_id)):
			continue
		var score := _route_value(home, station, needs, exports)
		var dist := home.position.distance_to(station.position)
		if best != null:
			var tied := is_equal_approx(score, best_score)
			if not tied and score < best_score:
				continue
			if tied and (jumps > best_jumps or (jumps == best_jumps and dist >= best_dist)):
				continue
		best = station
		best_score = score
		best_jumps = jumps
		best_dist = dist
	return best.id if best != null else ""

func power_faction_for(faction_enum: CampaignFleet.Faction) -> PowerFaction:
	for faction in factions:
		if faction.faction_enum == faction_enum:
			return faction
	return null

func _home_station_of(fleet: CampaignFleet) -> StationData:
	return galaxy.station(fleet.home_station_id) if galaxy != null else null

func _is_trade_partner(fleet_faction: CampaignFleet.Faction, owner: CampaignFleet.Faction) -> bool:
	# NPCs never trade or refuel at a player-owned station, so they can't drain the player's stock.
	if owner == CampaignFleet.Faction.PLAYER or owner == CampaignFleet.Faction.PIRATE:
		return false
	return not _factions_hostile(fleet_faction, owner)

func _apply_station_allocation(station: StationData) -> void:
	var combat_fleets := station_fleets(station, CampaignFleet.Role.COMBAT)
	var trader_fleets := station_fleets(station, CampaignFleet.Role.TRADER)
	# No combat fleets means nothing to grow or reallocate into; skip the danger branch so trade can still grow.
	var threat := _threat_ratio_for(station) if not combat_fleets.is_empty() else 0.0
	var action := FleetAllocationPolicy.decide(_economic_health(station.economy), threat, trader_fleets.size())
	match action:
		FleetAllocationPolicy.Action.GROW_COMBAT:
			_grow_station_fleet(combat_fleets, ShipType.Kind.CORVETTE)
		FleetAllocationPolicy.Action.GROW_TRADE:
			_grow_station_fleet(trader_fleets, ShipType.Kind.FREIGHTER)
		FleetAllocationPolicy.Action.REALLOCATE_TO_COMBAT:
			# Unreachable with trader quotas of 1. Above 1 it goes live, and respawn then replaces each
			# flipped trader, so the station's fleet count grows with no cap.
			if trader_fleets.size() > 1:
				trader_fleets[0].role = CampaignFleet.Role.COMBAT
				fleet_role_changed.emit(trader_fleets[0])
		FleetAllocationPolicy.Action.NONE:
			pass

func _economic_health(economy: BaseEconomy) -> FleetAllocationPolicy.EconomicHealth:
	match economy.wealth_level():
		BaseEconomy.WealthLevel.POOR:
			return FleetAllocationPolicy.EconomicHealth.DEFICIT
		BaseEconomy.WealthLevel.WEALTHY:
			return FleetAllocationPolicy.EconomicHealth.STRONG
	return FleetAllocationPolicy.EconomicHealth.STABLE

# Pirates in the station's system and its neighbours, over this station's own combat strength.
func _threat_ratio_for(station: StationData) -> float:
	var nearby: Array[String] = []
	if galaxy != null:
		nearby = galaxy.neighbours(station.system_id)
	nearby.append(station.system_id)
	var pirate_strength := 0.0
	for fleet in enemy_fleets:
		if fleet.faction == CampaignFleet.Faction.PIRATE and nearby.has(fleet.system_id):
			pirate_strength += fleet.total_strength()
	var combat_strength := 0.0
	for fleet in station_fleets(station, CampaignFleet.Role.COMBAT):
		combat_strength += fleet.total_strength()
	return pirate_strength / max(combat_strength, 1.0)

# Growth only adds a ship under the fleet's variant maximum (global cap if it has no variant); lost fleets come back through respawn instead. Only a fleet
# at home grows, so a new ship never raises the jump cost of one that is away on what it carries.
func _grow_station_fleet(fleets: Array[CampaignFleet], kind: ShipType.Kind) -> void:
	for fleet in fleets:
		var home := _home_station_of(fleet)
		if home == null or fleet.system_id != home.system_id:
			continue
		var cap := FleetAllocationPolicy.MAX_SHIPS_PER_FLEET if fleet.variant < 0 else DangerTier.ship_count_range(fleet.variant).y
		if fleet.ship_compositions.size() < cap:
			fleet.ship_compositions.append(ShipType.new_composition(kind))
			return

# Home's surplus (exports true) or needs (false): goods its slots net-produce or net-consume, plus
# whatever its stock makes spare (above TARGET_STOCK) or short (see BaseEconomy.is_short_of). Home's own
# fleets refuel from its stock, so a home that makes no FUEL also needs it while below TARGET_STOCK.
func _home_trade_goods(home: StationData, exports: bool) -> Array:
	var goods: Array = []
	if home.economy == null:
		return goods
	var net := home.economy.net_commodities()
	for commodity in net:
		if (exports and net[commodity] > 0.0) or (not exports and net[commodity] < 0.0):
			goods.append(commodity)
	# A station never hauls in what it makes, nor ships out what it burns.
	for commodity in Commodity.TARGET_STOCK:
		var made: float = net.get(commodity, 0.0)
		if goods.has(commodity) or (made > 0.0 and not exports) or (made < 0.0 and exports):
			continue
		var spare: bool = home.economy.stock.get(commodity, 0.0) > Commodity.TARGET_STOCK[commodity]
		if (exports and spare) or (not exports and home.economy.is_short_of(commodity)):
			goods.append(commodity)
	var fuel := Commodity.Type.FUEL
	var short_of_fuel: bool = net.get(fuel, 0.0) <= 0.0 and home.economy.stock.get(fuel, 0.0) < Commodity.TARGET_STOCK[fuel]
	if not exports and short_of_fuel and not goods.has(fuel):
		goods.append(fuel)
	return goods

# Units a fleet can haul between home and a partner, each weighted by how much dearer the good is at
# its destination: what home needs from the partner (also weighted by how empty home is of it, so a dry
# FUEL tank outbids a plentiful Ore run) plus what the partner is short of from home.
func _route_value(home: StationData, partner: StationData, needs: Array, exports: Array) -> float:
	if partner.economy == null:
		return 0.0
	var value := 0.0
	for commodity in needs:
		var emptiness := clampf(1.0 - home.economy.stock.get(commodity, 0.0) / Commodity.TARGET_STOCK[commodity], 0.0, 1.0)
		value += _trade_surplus(partner.economy, commodity) * _price_pull(partner.economy, home.economy, commodity) * (1.0 + 2.0 * emptiness)
	for commodity in exports:
		if partner.economy.is_short_of(commodity):
			value += _trade_surplus(home.economy, commodity) * _price_pull(home.economy, partner.economy, commodity)
	return value

# 1.0 plus how much dearer the good is at the destination, in base prices; never below 1.0.
static func _price_pull(source: BaseEconomy, destination: BaseEconomy, commodity: int) -> float:
	return 1.0 + maxf(0.0, float(destination.price_for(commodity) - source.price_for(commodity))) / Commodity.BASE_PRICE[commodity]

# The goods the partner is short of, or all of them when it is short of none (a trader still sells).
func _goods_wanted_by(goods: Array, partner: StationData) -> Array:
	if partner == null or partner.economy == null:
		return goods
	var wanted := goods.filter(func(commodity): return partner.economy.is_short_of(commodity))
	return wanted if not wanted.is_empty() else goods

# What a trader may take: all of a good the station makes, only the excess over TARGET_STOCK of
# anything else, and never the station's FUEL reserve.
func _trade_surplus(economy: BaseEconomy, commodity: int) -> float:
	var keep: float = 0.0 if economy.net_commodities().get(commodity, 0.0) > 0.0 else Commodity.TARGET_STOCK[commodity]
	if commodity == Commodity.Type.FUEL:
		keep = maxf(keep, _fuel_reserve(economy))
	return maxf(0.0, economy.stock.get(commodity, 0.0) - keep)

# Free cargo is split evenly across the goods the station can spare.
func _load_trade_goods(fleet: CampaignFleet, goods: Array, economy: BaseEconomy) -> void:
	var qualifying: Array = []
	for commodity in goods:
		if _trade_surplus(economy, commodity) > 0.0:
			qualifying.append(commodity)
	if qualifying.is_empty():
		return

	var share: float = (fleet.cargo_capacity() - fleet.cargo_total()) / qualifying.size()
	for commodity in qualifying:
		var amount: float = minf(_trade_surplus(economy, commodity), share)
		if amount <= 0.0:
			continue
		economy.stock[commodity] = economy.stock.get(commodity, 0.0) - amount
		fleet.cargo[commodity] = fleet.cargo.get(commodity, 0.0) + amount
