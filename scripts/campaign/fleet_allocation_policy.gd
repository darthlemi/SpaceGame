class_name FleetAllocationPolicy
extends RefCounted

enum EconomicHealth { DEFICIT, STABLE, STRONG }
enum Action { NONE, GROW_COMBAT, GROW_TRADE, REALLOCATE_TO_COMBAT }

const DANGER_THRESHOLD := 1.2
const SAFE_THRESHOLD := 0.6
const MAX_SHIPS_PER_FLEET := DangerTier.SECURITY_MAX_SHIPS

static func decide(economic_health: EconomicHealth, threat_ratio: float, trader_fleet_count: int) -> Action:
	if threat_ratio > DANGER_THRESHOLD:
		if economic_health != EconomicHealth.DEFICIT:
			return Action.GROW_COMBAT
		if trader_fleet_count > 1:
			return Action.REALLOCATE_TO_COMBAT
		return Action.NONE
	if economic_health == EconomicHealth.STRONG and threat_ratio < SAFE_THRESHOLD:
		return Action.GROW_TRADE
	return Action.NONE
