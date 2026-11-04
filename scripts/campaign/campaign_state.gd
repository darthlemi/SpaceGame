extends Node

signal skirmish_resolved(winner_fleet: CampaignFleet, loser_fleet: CampaignFleet)
signal fleet_spawn_requested(fleet: CampaignFleet)
signal fleet_role_changed(fleet: CampaignFleet)
signal faction_reputation_changed(faction_enum: CampaignFleet.Faction)

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
const NPC_SPEED := {CampaignFleet.Role.COMBAT: 100.0, CampaignFleet.Role.TRADER: 80.0}
# Task 5 raises this once traders can jump.
const TRADE_RANGE_JUMPS := 0
const NPC_FUEL_TARGET_JUMPS := 3
const NPC_SPAWN_SCATTER := 40.0
const PLAYER_SPEED := 120.0
const PLAYER_STARTING_FUEL := 30.0
# Bases start below housing capacity so population has room to grow.
const STARTING_POPULATION_FRACTION := 0.75

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
# Not cleared by reset(), so a seed set before new_game() holds.
var rng := RandomNumberGenerator.new()
var _economy_tick_elapsed: float = 0.0

func start_engagement(enemy_fleet: CampaignFleet) -> void:
	for skirmish in active_skirmishes.duplicate():
		if skirmish.fleet_winner == enemy_fleet or skirmish.fleet_loser == enemy_fleet:
			active_skirmishes.erase(skirmish)
			var other: CampaignFleetIcon = skirmish.icon_loser if skirmish.fleet_winner == enemy_fleet else skirmish.icon_winner
			if is_instance_valid(other):
				other.frozen = false
	active_enemy_fleet = enemy_fleet

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

func reset() -> void:
	player_fleet = null
	enemy_fleets = []
	active_enemy_fleet = null
	pending_loot = null
	pending_respawn = false
	factions = []
	factions_at_war = true
	active_skirmishes = []
	credits = 500
	home_base_economy = null
	galaxy = null
	_economy_tick_elapsed = 0.0

func new_game() -> void:
	reset()
	galaxy = GalaxyData.build()
	for station in galaxy.stations:
		_seed_economy(station.economy)
	var home := galaxy.home_station()
	home_base_economy = home.economy
	factions.assign([_new_power_faction(CampaignFleet.Faction.DOMINION, "Dominion"), _new_power_faction(CampaignFleet.Faction.FREEHOLD, "Freehold")])
	factions_at_war = true
	player_fleet = _new_player_fleet(home)
	for station in galaxy.stations:
		for role in station.fleet_quota:
			for _i in station.fleet_quota[role]:
				spawn_station_fleet(station, role)

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
		_refill_npc_crew()

static func fleet_faction_for(owner: CampaignFleet.Faction, role: CampaignFleet.Role) -> CampaignFleet.Faction:
	if owner == CampaignFleet.Faction.NEUTRAL:
		return CampaignFleet.Faction.TRADER if role == CampaignFleet.Role.TRADER else CampaignFleet.Faction.NEUTRAL
	return owner

func spawn_station_fleet(station: StationData, role: CampaignFleet.Role) -> CampaignFleet:
	var fleet := CampaignFleet.new()
	fleet.ship_compositions = DangerTier.fleet_for(_tier_of(station), role, rng)
	fleet.faction = fleet_faction_for(station.owner, role)
	fleet.role = role
	fleet.home_station_id = station.id
	fleet.system_id = station.system_id
	fleet.speed = NPC_SPEED[role]
	fleet.position = station.position + Vector2(rng.randf_range(-NPC_SPAWN_SCATTER, NPC_SPAWN_SCATTER), rng.randf_range(-NPC_SPAWN_SCATTER, NPC_SPAWN_SCATTER))
	fleet.cargo = {Commodity.Type.FUEL: NPC_FUEL_TARGET_JUMPS * JumpRules.jump_cost(fleet)}
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

func _seed_economy(economy: BaseEconomy) -> void:
	for commodity in Commodity.Type.values():
		economy.stock[commodity] = Commodity.TARGET_STOCK[commodity]
	economy.population = economy.population_capacity() * STARTING_POPULATION_FRACTION
	economy.crew_pool = economy.crew_pool_cap()

func _tier_of(station: StationData) -> int:
	var sys: StarSystem = galaxy.system(station.system_id) if galaxy != null else null
	return sys.tier if sys != null else DangerTier.MIN_TIER

# A role under quota accumulates time; at the delay the whole deficit returns and the timer restarts.
func _tick_station_respawns(station: StationData, elapsed: float) -> void:
	for role in station.fleet_quota:
		var deficit: int = station.fleet_quota[role] - station_fleets(station, role).size()
		if deficit <= 0:
			station.respawn_timers[role] = 0.0
			continue
		station.respawn_timers[role] = station.respawn_timers.get(role, 0.0) + elapsed
		if station.respawn_timers[role] >= FLEET_RESPAWN_DELAY:
			for _i in deficit:
				spawn_station_fleet(station, role)
			station.respawn_timers[role] = 0.0

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

func _factions_hostile(a: CampaignFleet.Faction, b: CampaignFleet.Faction) -> bool:
	var pirate := CampaignFleet.Faction.PIRATE
	if a == pirate and _is_power_faction(b):
		return true
	if b == pirate and _is_power_faction(a):
		return true
	if _is_power_faction(a) and _is_power_faction(b) and a != b:
		return factions_at_war
	return false

func start_skirmish(icon_a: CampaignFleetIcon, icon_b: CampaignFleetIcon) -> void:
	if icon_a.frozen or icon_b.frozen:
		return
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

# At home: unload everything, then load home's surplus. Elsewhere: unload there, then load what home needs.
func run_npc_trade_at(fleet: CampaignFleet, station: StationData) -> void:
	var home := _home_station_of(fleet)
	if home == null or station == null or home.economy == null or station.economy == null:
		return
	for commodity in fleet.cargo:
		var amount: float = fleet.cargo[commodity]
		if amount > 0.0:
			station.economy.stock[commodity] = station.economy.stock.get(commodity, 0.0) + amount
	fleet.cargo = {}
	_load_qualifying_commodities(fleet, home.economy.net_commodities(), station == home, station.economy.stock)

# Home after every away stop. From home: the in-range partner best stocked with what home needs,
# ties to fewer jumps then the shorter in-system distance; "" when there is no partner.
func next_trade_destination(fleet: CampaignFleet) -> String:
	var home := _home_station_of(fleet)
	if home == null:
		return ""
	if fleet.dest_station_id != home.id:
		return home.id
	var needs: Array = []
	if home.economy != null:
		var net := home.economy.net_commodities()
		for commodity in net:
			if net[commodity] < 0.0:
				needs.append(commodity)
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
		var score := 0.0
		if station.economy != null:
			for commodity in needs:
				score += station.economy.stock.get(commodity, 0.0)
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
	return owner != CampaignFleet.Faction.PIRATE and not _factions_hostile(fleet_faction, owner)

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

# Growth only adds a ship under the cap; lost fleets come back through respawn instead.
func _grow_station_fleet(fleets: Array[CampaignFleet], kind: ShipType.Kind) -> void:
	for fleet in fleets:
		if fleet.ship_compositions.size() < FleetAllocationPolicy.MAX_SHIPS_PER_FLEET:
			fleet.ship_compositions.append(ShipType.new_composition(kind))
			return

func _load_qualifying_commodities(fleet: CampaignFleet, net: Dictionary, positive: bool, stock: Dictionary) -> void:
	var qualifying: Array = []
	for commodity in net:
		var qualifies: bool = net[commodity] > 0.0 if positive else net[commodity] < 0.0
		if not qualifies or stock.get(commodity, 0.0) <= 0.0:
			continue
		qualifying.append(commodity)
	if qualifying.is_empty():
		return

	var share: float = (fleet.cargo_capacity() - fleet.cargo_total()) / qualifying.size()
	for commodity in qualifying:
		var available: float = stock.get(commodity, 0.0)
		var amount: float = min(available, share)
		if amount <= 0.0:
			continue
		stock[commodity] = available - amount
		fleet.cargo[commodity] = fleet.cargo.get(commodity, 0.0) + amount
