extends RefCounted

const CampaignStateScript = preload("res://scripts/campaign/campaign_state.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	# Day counter: starts at 0, advances with unpaused time, resets with reset().
	var state := CampaignStateScript.new()
	if state.game_day() != 0:
		failures.append("game_day: expected 0 before any time has passed, got %d" % state.game_day())
	state.tick_economy(CampaignStateScript.DAY_LENGTH_SECONDS * 2.5)
	if state.game_day() != 2:
		failures.append("game_day: expected 2 after 2.5 day-lengths, got %d" % state.game_day())
	state.reset()
	if state.game_day() != 0:
		failures.append("game_day: expected reset() to clear the day counter, got %d" % state.game_day())

	# Station snapshot: taken by record_visit(), reflects the economy at that moment.
	var snap_state := CampaignStateScript.new()
	snap_state.new_game()
	var home := snap_state.galaxy.home_station()
	if not snap_state.station_snapshots.has(home.id):
		failures.append("snapshot: expected new_game() to snapshot the home station via record_visit()")
	var snapshot: Dictionary = snap_state.station_snapshots.get(home.id, {})
	if snapshot.get("day") != 0:
		failures.append("snapshot: expected day 0 at new game, got %s" % snapshot.get("day"))
	if snapshot.get("population") != home.economy.population:
		failures.append("snapshot: expected population copied from the economy")
	if snapshot.get("wealth_level") != home.economy.wealth_level():
		failures.append("snapshot: expected wealth_level copied from the economy")
	var expected_reputation = null
	var home_faction := snap_state.power_faction_for(home.owner)
	if home_faction != null:
		expected_reputation = home_faction.reputation
	if snapshot.get("reputation") != expected_reputation:
		failures.append("snapshot: expected reputation %s, got %s" % [expected_reputation, snapshot.get("reputation")])
	var net := home.economy.net_commodities()
	for row in snapshot.get("produces", []):
		if net.get(row["commodity"], 0.0) <= 0.0:
			failures.append("snapshot: '%s' in produces but net is %.2f" % [Commodity.NAMES[row["commodity"]], net.get(row["commodity"], 0.0)])
		if row["stock"] != home.economy.stock.get(row["commodity"], 0.0):
			failures.append("snapshot: produces row stock mismatch for %s" % Commodity.NAMES[row["commodity"]])
		if row["buy"] != home.economy.price_for(row["commodity"]):
			failures.append("snapshot: produces row buy price mismatch for %s" % Commodity.NAMES[row["commodity"]])
		if row["sell"] != home.economy.sell_price_for(row["commodity"]):
			failures.append("snapshot: produces row sell price mismatch for %s" % Commodity.NAMES[row["commodity"]])
	for row in snapshot.get("consumes", []):
		if net.get(row["commodity"], 0.0) >= 0.0:
			failures.append("snapshot: '%s' in consumes but net is %.2f" % [Commodity.NAMES[row["commodity"]], net.get(row["commodity"], 0.0)])
	var seen_commodities := []
	for row in snapshot.get("produces", []) + snapshot.get("consumes", []):
		seen_commodities.append(row["commodity"])
	var sorted_seen := seen_commodities.duplicate()
	sorted_seen.sort()
	if seen_commodities != sorted_seen:
		failures.append("snapshot: expected rows in Commodity.Type order, got %s" % [seen_commodities])

	# Re-visiting updates the snapshot (day advances, new economy numbers win).
	snap_state.tick_economy(CampaignStateScript.DAY_LENGTH_SECONDS * 3.0)
	home.economy.population = 999.0
	snap_state.record_visit(home.system_id)
	var refreshed: Dictionary = snap_state.station_snapshots[home.id]
	if refreshed.get("day") != 3 or refreshed.get("population") != 999.0:
		failures.append("snapshot: expected re-visiting to refresh day and population, got %s" % refreshed)

	snap_state.reset()
	return failures
