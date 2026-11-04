extends RefCounted

static func _build() -> Galaxy:
	var galaxy := Galaxy.new()
	for id in ["a", "b", "c", "d", "e"]:
		var sys := StarSystem.new()
		sys.id = id
		galaxy.systems[id] = sys
	galaxy.start_system_id = "a"
	galaxy.link("a", "b")
	galaxy.link("b", "c")
	galaxy.link("c", "d")
	return galaxy

static func _station(id: String, system_id: String, owner: CampaignFleet.Faction) -> StationData:
	var st := StationData.new()
	st.id = id
	st.system_id = system_id
	st.owner = owner
	return st

static func run() -> Array[String]:
	var failures: Array[String] = []
	var galaxy := _build()

	if galaxy.path("a", "d") != ["b", "c", "d"]:
		failures.append("path a->d: expected [b, c, d], got %s" % [galaxy.path("a", "d")])
	if not galaxy.path("a", "a").is_empty():
		failures.append("path a->a: expected empty, got %s" % [galaxy.path("a", "a")])
	if not galaxy.path("a", "e").is_empty():
		failures.append("path a->e (unlinked): expected empty, got %s" % [galaxy.path("a", "e")])
	if galaxy.jump_distance("a", "e") != -1:
		failures.append("jump_distance a->e: expected -1, got %d" % galaxy.jump_distance("a", "e"))
	if galaxy.jump_distance("a", "d") != 3:
		failures.append("jump_distance a->d: expected 3, got %d" % galaxy.jump_distance("a", "d"))
	if not galaxy.are_linked("b", "a"):
		failures.append("are_linked b,a: expected true (link adds both directions)")
	if galaxy.are_linked("a", "c"):
		failures.append("are_linked a,c: expected false")
	if galaxy.neighbours("b").size() != 2:
		failures.append("neighbours b: expected 2, got %s" % [galaxy.neighbours("b")])
	if galaxy.system("c") == null or galaxy.system("c").id != "c":
		failures.append("system(c): expected the c system")

	galaxy.assign_tiers()
	var expected := {"a": 1, "b": 1, "c": 2, "d": 3}
	for id in expected:
		if galaxy.system(id).tier != expected[id]:
			failures.append("tier %s: expected %d, got %d" % [id, expected[id], galaxy.system(id).tier])

	galaxy.system("b").tier_override = 5
	galaxy.assign_tiers()
	if galaxy.system("b").tier != 5:
		failures.append("tier_override: expected b == 5, got %d" % galaxy.system("b").tier)

	var home := _station("home", "a", CampaignFleet.Faction.PLAYER)
	var other := _station("other", "b", CampaignFleet.Faction.PIRATE)
	var second := _station("second", "a", CampaignFleet.Faction.NEUTRAL)
	galaxy.stations = [home, other, second]
	var in_a := galaxy.stations_in("a")
	if in_a.size() != 2 or not in_a.has(home) or not in_a.has(second):
		failures.append("stations_in a: expected [home, second], got %d entries" % in_a.size())
	if galaxy.stations_in("c").size() != 0:
		failures.append("stations_in c: expected none")
	if galaxy.home_station() != home:
		failures.append("home_station: expected the PLAYER-owned station")
	if galaxy.station("other") != other:
		failures.append("station(other): expected the other station")
	if galaxy.station("nope") != null:
		failures.append("station(nope): expected null")
	return failures
