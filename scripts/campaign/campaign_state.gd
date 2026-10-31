extends Node

signal skirmish_resolved(winner_fleet: CampaignFleet, loser_fleet: CampaignFleet)

const REPUTATION_LOSS_PER_DEFEAT := 15.0
const HOSTILE_REPUTATION_THRESHOLD := 40.0
const ECONOMY_TICK_INTERVAL := 5.0

var player_fleet: CampaignFleet
var enemy_fleets: Array[CampaignFleet] = []
var active_enemy_fleet: CampaignFleet
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
	active_enemy_fleet = null

func reset() -> void:
	player_fleet = null
	enemy_fleets = []
	active_enemy_fleet = null
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
