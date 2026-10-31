extends Node

signal skirmish_resolved(winner_fleet: CampaignFleet, loser_fleet: CampaignFleet)
signal fleet_spawn_requested(fleet: CampaignFleet)
signal fleet_role_changed(fleet: CampaignFleet)

const REPUTATION_LOSS_PER_DEFEAT := 15.0
const HOSTILE_REPUTATION_THRESHOLD := 40.0
const ECONOMY_TICK_INTERVAL := 5.0

var player_fleet: CampaignFleet
var enemy_fleets: Array[CampaignFleet] = []
var active_enemy_fleet: CampaignFleet
var pending_loot_fleet: CampaignFleet = null
var factions: Array[PowerFaction] = []
var factions_at_war: bool = true
var active_skirmishes: Array[Skirmish] = []
var credits: float = 500.0
var home_base_economy: BaseEconomy = null
var _economy_tick_elapsed: float = 0.0

func start_engagement(enemy_fleet: CampaignFleet) -> void:
	for skirmish in active_skirmishes.duplicate():
		if skirmish.fleet_winner == enemy_fleet or skirmish.fleet_loser == enemy_fleet:
			active_skirmishes.erase(skirmish)
			var other: CampaignFleetIcon = skirmish.icon_loser if skirmish.fleet_winner == enemy_fleet else skirmish.icon_winner
			if is_instance_valid(other):
				other.frozen = false
	active_enemy_fleet = enemy_fleet

func resolve_engagement(player_survivors: Array[Dictionary], enemy_survivors: Array[Dictionary]) -> void:
	if player_fleet == null:
		return
	player_fleet.ship_compositions = player_survivors.duplicate(true)
	if active_enemy_fleet != null:
		active_enemy_fleet.ship_compositions = enemy_survivors.duplicate(true)
		if active_enemy_fleet.is_destroyed():
			enemy_fleets.erase(active_enemy_fleet)
			_apply_reputation_loss(active_enemy_fleet.faction)
			if active_enemy_fleet.cargo_total() > 0.0:
				pending_loot_fleet = active_enemy_fleet
	active_enemy_fleet = null

func reset() -> void:
	player_fleet = null
	enemy_fleets = []
	active_enemy_fleet = null
	pending_loot_fleet = null
	factions = []
	factions_at_war = true
	active_skirmishes = []
	credits = 500.0
	home_base_economy = null
	_economy_tick_elapsed = 0.0

func tick_economy(delta: float) -> void:
	_economy_tick_elapsed += delta
	while _economy_tick_elapsed >= ECONOMY_TICK_INTERVAL:
		_economy_tick_elapsed -= ECONOMY_TICK_INTERVAL
		if home_base_economy != null:
			home_base_economy.tick()
		for faction in factions:
			if faction.economy != null:
				faction.economy.tick()
				_apply_fleet_allocation(faction)

func buy(base_economy: BaseEconomy, commodity: int, fleet: CampaignFleet) -> bool:
	var price := base_economy.price_for(commodity)
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
	var price := base_economy.sell_price_for(commodity)
	credits += price
	fleet.cargo[commodity] = held - 1.0
	base_economy.stock[commodity] = base_economy.stock.get(commodity, 0.0) + 1.0
	return true

func are_hostile(fleet_a: CampaignFleet, fleet_b: CampaignFleet) -> bool:
	var a := fleet_a.faction
	var b := fleet_b.faction
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
	enemy_fleets.erase(skirmish.fleet_loser)
	if is_instance_valid(skirmish.icon_loser):
		skirmish.icon_loser.queue_free()
	if is_instance_valid(skirmish.icon_winner):
		skirmish.icon_winner.frozen = false
	skirmish_resolved.emit(skirmish.fleet_winner, skirmish.fleet_loser)

func _is_power_faction(faction: CampaignFleet.Faction) -> bool:
	return faction == CampaignFleet.Faction.DOMINION or faction == CampaignFleet.Faction.FREEHOLD

func _apply_reputation_loss(defeated_faction: CampaignFleet.Faction) -> void:
	for power_faction in factions:
		if power_faction.faction_enum == defeated_faction:
			power_faction.reputation = max(0.0, power_faction.reputation - REPUTATION_LOSS_PER_DEFEAT)

func run_npc_trade_for_fleet(fleet: CampaignFleet, at_home: bool) -> void:
	var faction := _power_faction_for(fleet.faction)
	if faction == null or faction.economy == null or home_base_economy == null:
		return
	if at_home:
		_unload_and_load_surplus(fleet, faction.economy)
	else:
		_unload_and_load_deficit(fleet, faction.economy)

func _power_faction_for(faction_enum: CampaignFleet.Faction) -> PowerFaction:
	for faction in factions:
		if faction.faction_enum == faction_enum:
			return faction
	return null

func _apply_fleet_allocation(faction: PowerFaction) -> void:
	var combat_fleets := _fleets_for(faction.faction_enum, CampaignFleet.Role.COMBAT)
	var trader_fleets := _fleets_for(faction.faction_enum, CampaignFleet.Role.TRADER)
	var economic_health := _economic_health(faction.economy)
	var threat_ratio := _threat_ratio(combat_fleets)
	var action := FleetAllocationPolicy.decide(economic_health, threat_ratio, trader_fleets.size())
	match action:
		FleetAllocationPolicy.Action.GROW_COMBAT:
			_grow_fleet(faction, combat_fleets, trader_fleets, CampaignFleet.Role.COMBAT)
		FleetAllocationPolicy.Action.GROW_TRADE:
			_grow_fleet(faction, combat_fleets, trader_fleets, CampaignFleet.Role.TRADER)
		FleetAllocationPolicy.Action.REALLOCATE_TO_COMBAT:
			if trader_fleets.size() > 1:
				trader_fleets[0].role = CampaignFleet.Role.COMBAT
				fleet_role_changed.emit(trader_fleets[0])
		FleetAllocationPolicy.Action.NONE:
			pass

func _fleets_for(faction_enum: CampaignFleet.Faction, role: CampaignFleet.Role) -> Array[CampaignFleet]:
	var result: Array[CampaignFleet] = []
	for fleet in enemy_fleets:
		if fleet.faction == faction_enum and fleet.role == role:
			result.append(fleet)
	return result

func _economic_health(economy: BaseEconomy) -> FleetAllocationPolicy.EconomicHealth:
	for streak in economy.deficit_streaks.values():
		if streak > 0:
			return FleetAllocationPolicy.EconomicHealth.DEFICIT
	if economy.surplus_streak >= BaseEconomy.SURPLUS_STREAK_THRESHOLD:
		return FleetAllocationPolicy.EconomicHealth.STRONG
	return FleetAllocationPolicy.EconomicHealth.STABLE

func _threat_ratio(combat_fleets: Array[CampaignFleet]) -> float:
	var pirate_strength := 0.0
	for fleet in enemy_fleets:
		if fleet.faction == CampaignFleet.Faction.PIRATE:
			pirate_strength += fleet.total_strength()
	var combat_strength := 0.0
	for fleet in combat_fleets:
		combat_strength += fleet.total_strength()
	return pirate_strength / max(combat_strength, 1.0)

func _grow_fleet(faction: PowerFaction, combat_fleets: Array[CampaignFleet], trader_fleets: Array[CampaignFleet], role: CampaignFleet.Role) -> void:
	var fleets_of_role := combat_fleets if role == CampaignFleet.Role.COMBAT else trader_fleets
	for fleet in fleets_of_role:
		if fleet.ship_compositions.size() < FleetAllocationPolicy.MAX_SHIPS_PER_FLEET:
			fleet.ship_compositions.append(_new_ship_template())
			return
	if combat_fleets.size() + trader_fleets.size() >= FleetAllocationPolicy.MAX_FLEETS:
		return
	var new_fleet := CampaignFleet.new()
	new_fleet.faction = faction.faction_enum
	new_fleet.role = role
	new_fleet.position = faction.base_position
	new_fleet.speed = 100.0
	new_fleet.ship_compositions = [_new_ship_template()]
	enemy_fleets.append(new_fleet)
	fleet_spawn_requested.emit(new_fleet)

func _new_ship_template() -> Dictionary:
	return {"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}

func _unload_and_load_surplus(fleet: CampaignFleet, economy: BaseEconomy) -> void:
	for commodity in fleet.cargo:
		var amount: float = fleet.cargo[commodity]
		if amount <= 0.0:
			continue
		economy.stock[commodity] = economy.stock.get(commodity, 0.0) + amount
	fleet.cargo = {}

	var net := economy.net_commodities()
	for commodity in net:
		if net[commodity] <= 0.0:
			continue
		var available: float = economy.stock.get(commodity, 0.0)
		var space: float = fleet.cargo_capacity() - fleet.cargo_total()
		var amount: float = min(available, space)
		if amount <= 0.0:
			continue
		economy.stock[commodity] = available - amount
		fleet.cargo[commodity] = fleet.cargo.get(commodity, 0.0) + amount

func _unload_and_load_deficit(fleet: CampaignFleet, economy: BaseEconomy) -> void:
	for commodity in fleet.cargo:
		var amount: float = fleet.cargo[commodity]
		if amount <= 0.0:
			continue
		home_base_economy.stock[commodity] = home_base_economy.stock.get(commodity, 0.0) + amount
	fleet.cargo = {}

	var net := economy.net_commodities()
	for commodity in net:
		if net[commodity] >= 0.0:
			continue
		var available: float = home_base_economy.stock.get(commodity, 0.0)
		var space: float = fleet.cargo_capacity() - fleet.cargo_total()
		var amount: float = min(available, space)
		if amount <= 0.0:
			continue
		home_base_economy.stock[commodity] = available - amount
		fleet.cargo[commodity] = fleet.cargo.get(commodity, 0.0) + amount
