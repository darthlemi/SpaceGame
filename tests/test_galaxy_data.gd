extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	var galaxy := GalaxyData.build()

	if galaxy.systems.size() != 26:
		failures.append("system count: expected 26, got %d" % galaxy.systems.size())
	if galaxy.start_system_id != "haven":
		failures.append("start_system_id: expected haven, got %s" % galaxy.start_system_id)

	var link_entries := 0
	for id in galaxy.systems:
		var sys: StarSystem = galaxy.systems[id]
		link_entries += sys.links.size()
		for other in sys.links:
			if not galaxy.systems.has(other):
				failures.append("link %s -> %s: unknown system" % [id, other])
			elif not galaxy.are_linked(other, id):
				failures.append("link %s -> %s: not symmetric" % [id, other])
		if galaxy.jump_distance("haven", id) < 0:
			failures.append("system %s: unreachable from haven" % id)
		if galaxy.stations_in(id).is_empty():
			failures.append("system %s: has no stations" % id)
	if link_entries != 80:
		failures.append("link entries: expected 80 (40 pairs), got %d" % link_entries)

	var player_stations := 0
	var ids := {}
	for st in galaxy.stations:
		if st.is_home():
			player_stations += 1
			if st.system_id != "haven":
				failures.append("home station: expected in haven, got %s" % st.system_id)
		if ids.has(st.id):
			failures.append("station id %s: duplicate" % st.id)
		ids[st.id] = true
		if st.position.x < JumpRules.SYSTEM_MIN.x or st.position.y < JumpRules.SYSTEM_MIN.y \
				or st.position.x > JumpRules.SYSTEM_MAX.x or st.position.y > JumpRules.SYSTEM_MAX.y:
			failures.append("station %s: position %s outside system bounds" % [st.id, st.position])
		if not ResourceLoader.exists(st.texture_path()):
			failures.append("station %s: missing texture %s" % [st.id, st.texture_path()])
		if st.economy == null or st.economy.slots.is_empty() or st.economy.max_slots != 2:
			failures.append("station %s: expected an economy with roles and max_slots 2" % st.id)
		if not galaxy.systems.has(st.system_id):
			failures.append("station %s: unknown system %s" % [st.id, st.system_id])
	if player_stations != 1:
		failures.append("PLAYER stations: expected 1, got %d" % player_stations)

	var tiers := {"haven": 1, "wexford": 1, "greenreach": 2, "deadreach": 5, "ashfall": 5}
	for id in tiers:
		if galaxy.system(id).tier != tiers[id]:
			failures.append("tier %s: expected %d, got %d" % [id, tiers[id], galaxy.system(id).tier])

	var haven_exchange := galaxy.station("haven_exchange")
	if haven_exchange == null or haven_exchange.owner != CampaignFleet.Faction.NEUTRAL:
		failures.append("haven_exchange: expected a NEUTRAL station")
	elif haven_exchange.fleet_quota.get(CampaignFleet.Role.TRADER, 0) != 1:
		failures.append("haven_exchange: expected trader quota 1")

	# No trader ever serves a pirate station, so a pirate population slot must grow its own food.
	for st in galaxy.stations:
		if st.owner != CampaignFleet.Faction.PIRATE:
			continue
		var roles := {}
		for slot in st.economy.slots:
			roles[slot.role_type] = true
		if roles.has(EconomyRole.RoleType.POPULATION) and not roles.has(EconomyRole.RoleType.AGRICULTURE):
			failures.append("pirate station %s: a population slot with no agriculture starves" % st.id)
	_check_optional_keys(failures)
	return failures

static func _check_optional_keys(failures: Array[String]) -> void:
	var sys := GalaxyData._make_system({"id": "x", "name": "X", "map": Vector2.ZERO, "tier": 4})
	if sys.tier_override != 4:
		failures.append("optional tier: expected tier_override 4 from the data, got %d" % sys.tier_override)
	if GalaxyData._make_system({"id": "y", "name": "Y", "map": Vector2.ZERO}).tier_override != 0:
		failures.append("optional tier: expected no override when the key is absent")
	var entry := {"name": "Test Post", "system": "x", "owner": CampaignFleet.Faction.NEUTRAL, "pos": Vector2.ZERO, "art": "ring_2", "roles": ["mining"], "quota": {}, "stock": {Commodity.Type.ORE: 7.0}}
	var st := GalaxyData._make_station(entry)
	if st.starting_stock.get(Commodity.Type.ORE, -1.0) != 7.0:
		failures.append("optional stock: expected starting ORE 7 from the data, got %s" % [st.starting_stock])
