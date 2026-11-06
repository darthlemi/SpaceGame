extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	CampaignState.new_game()
	var fleet := CampaignState.player_fleet
	_check_fuel(failures, fleet)
	_check_credits(failures)
	_check_crew(failures, fleet)
	_check_spawn(failures)
	CampaignState.reset()
	return failures

static func _check_fuel(failures: Array[String], fleet: CampaignFleet) -> void:
	var before := fleet.fuel_amount()
	DebugActions.add_fuel(fleet, 100.0)
	if not is_equal_approx(fleet.fuel_amount(), before + 100.0):
		failures.append("add_fuel: expected %s, got %s" % [before + 100.0, fleet.fuel_amount()])
	DebugActions.add_fuel(fleet, -100000.0)
	if fleet.fuel_amount() != 0.0:
		failures.append("add_fuel: expected a floor of 0, got %s" % fleet.fuel_amount())

static func _check_credits(failures: Array[String]) -> void:
	CampaignState.credits = 500
	DebugActions.add_credits(1000)
	if CampaignState.credits != 1500:
		failures.append("add_credits: expected 1500, got %d" % CampaignState.credits)
	DebugActions.add_credits(-5000)
	if CampaignState.credits != 0:
		failures.append("add_credits: expected a floor of 0, got %d" % CampaignState.credits)

static func _check_crew(failures: Array[String], fleet: CampaignFleet) -> void:
	DebugActions.add_crew(fleet, -100000)
	if fleet.crew_total() != 0:
		failures.append("add_crew: expected 0 crew after a huge removal, got %d" % fleet.crew_total())
	var added := DebugActions.add_crew(fleet, 10)
	if added != 10 or fleet.crew_total() != 10:
		failures.append("add_crew: expected +10, got %d (total %d)" % [added, fleet.crew_total()])
	DebugActions.add_crew(fleet, 100000)
	if fleet.crew_total() != fleet.crew_capacity():
		failures.append("add_crew: expected a cap at complement %d, got %d" % [fleet.crew_capacity(), fleet.crew_total()])

static func _check_spawn(failures: Array[String]) -> void:
	var count := CampaignState.enemy_fleets.size()
	var fleet := DebugActions.spawn_fleet(CampaignFleet.Faction.PIRATE, CampaignFleet.Role.COMBAT, 3)
	if fleet == null or CampaignState.enemy_fleets.size() != count + 1:
		failures.append("spawn_fleet: expected one new enemy fleet")
		return
	if fleet.system_id != CampaignState.player_fleet.system_id:
		failures.append("spawn_fleet: expected the player's system, got %s" % fleet.system_id)
