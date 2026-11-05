extends RefCounted

const Validator = preload("res://tests/test_galaxy_validator.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []
	_check_dirty(failures)
	_check_systems(failures)
	_check_links(failures)
	_check_stations(failures)
	_check_player_station(failures)
	_check_slots(failures)
	_check_stock_quota_presets(failures)
	_check_unknown_keys(failures)
	return failures

static func _model() -> MapEditModel:
	return MapEditModel.from_document(Validator.doc())

static func _check_dirty(failures: Array[String]) -> void:
	var m := _model()
	if m.dirty:
		failures.append("dirty: expected false after from_document")
	m.move_system("a", Vector2(0.3, 0.3))
	if not m.dirty:
		failures.append("dirty: expected true after a change")
	m = _model()
	m.link("a", "a")
	if m.dirty:
		failures.append("dirty: a refused change must not set dirty")

static func _check_systems(failures: Array[String]) -> void:
	var m := _model()
	m.move_system("a", Vector2(-3.0, 7.0))
	var map: Array = m.doc["systems"][0]["map"]
	if map != [0.0, 1.0]:
		failures.append("move_system: expected a clamp to [0, 1], got %s" % [map])
	var id1 := m.add_system("New Sys", Vector2(0.5, 0.5))
	var id2 := m.add_system("New Sys", Vector2(0.5, 0.5))
	if id1 != "new_sys" or id2 == id1 or id2 != id2.to_lower():
		failures.append("add_system: expected unique lower-case ids, got '%s' and '%s'" % [id1, id2])
	var before := Validator.doc()
	m = _model()
	m.add_station("c")
	if not m.delete_system("c"):
		failures.append("delete_system: expected c to be deletable")
	for pair in m.doc["links"]:
		if "c" in pair:
			failures.append("delete_system: a link to c survived")
	for st in m.doc["stations"]:
		if st["system"] == "c":
			failures.append("delete_system: a station in c survived")
	m = _model()
	if m.delete_system("a") or m.doc != before:
		failures.append("delete_system: the system holding the player station must be refused with no change")
	if m.delete_system("zzz"):
		failures.append("delete_system: an unknown system must be refused")
	m.set_system_field("b", "name", "Bee")
	m.set_system_field("b", "tier", 3)
	m.set_system_field("b", "tier", null)
	if m.doc["systems"][1]["name"] != "Bee" or m.doc["systems"][1].has("tier"):
		failures.append("set_system_field: expected the new name and a cleared tier, got %s" % [m.doc["systems"][1]])

static func _check_links(failures: Array[String]) -> void:
	var m := _model()
	var before: Dictionary = m.doc.duplicate(true)
	if m.link("a", "a") or m.doc != before:
		failures.append("link: a link to itself must be refused with no change")
	if m.link("a", "b") or m.link("b", "a") or m.doc != before:
		failures.append("link: a duplicate link must be refused with no change")
	if m.link("a", "zzz"):
		failures.append("link: a link to an unknown system must be refused")
	if not m.link("a", "c") or m.doc["links"].size() != 3:
		failures.append("link: expected a-c to be added")
	if not m.unlink("c", "a") or m.doc["links"].size() != 2:
		failures.append("unlink: expected a-c to be removed (either order)")
	if m.unlink("a", "c"):
		failures.append("unlink: a missing link must return false")

static func _check_stations(failures: Array[String]) -> void:
	var m := _model()
	var id := m.add_station("b")
	if id != "new_station" or m.station_index(id) < 0 or m.stations_in("b").size() != 2:
		failures.append("add_station: expected new_station in b, got '%s'" % id)
	var dup := m.duplicate_station("post_b")
	var dup2 := m.duplicate_station("post_b")
	if dup != "post_b_copy" or dup2 != "post_b_copy_2":
		failures.append("duplicate_station: expected post_b_copy and post_b_copy_2, got '%s' and '%s'" % [dup, dup2])
	m.set_station_field("post_b", "name", "Renamed Post")
	var idx := m.station_index("renamed_post")
	if idx < 0 or m.station_index("post_b") >= 0 or m.doc["stations"][idx]["system"] != "b":
		failures.append("set_station_field: expected the rename to change the derived id and keep the station")
	if m.station_id_of({"name": "Two  Words"}) != "two__words":
		failures.append("station_id_of: expected lower case with spaces as underscores")
	m.set_station_field("renamed_post", "pos", Vector2(10.0, 20.0))
	if m.doc["stations"][m.station_index("renamed_post")]["pos"] != [10.0, 20.0]:
		failures.append("set_station_field: expected a Vector2 stored as [x, y]")
	if not m.delete_station("renamed_post") or m.station_index("renamed_post") >= 0:
		failures.append("delete_station: expected the station to be removed")
	if m.delete_station("zzz") or m.duplicate_station("zzz") != "":
		failures.append("station ops on an unknown id must be refused")

static func _check_player_station(failures: Array[String]) -> void:
	var m := _model()
	var before: Dictionary = m.doc.duplicate(true)
	if m.delete_station("home_base") or m.doc != before:
		failures.append("delete_station: the player station must be refused with no change")
	if m.duplicate_station("home_base") != "" or m.doc != before:
		failures.append("duplicate_station: the player station must be refused with no change")

static func _check_slots(failures: Array[String]) -> void:
	var m := _model()
	if m.add_slot("post_b"):
		failures.append("add_slot: expected false at the 2-slot cap")
	if not m.add_slot("home_base") or m.doc["stations"][0]["slots"].size() != 2 or m.add_slot("home_base"):
		failures.append("add_slot: expected one slot to fit and then refuse")
	if not m.remove_slot("post_b", 1) or m.doc["stations"][1]["slots"].size() != 1 or m.remove_slot("post_b", 5):
		failures.append("remove_slot: expected the slot removed and a bad index refused")
	m.set_slot_preset("post_b", 0, "agriculture")
	if m.doc["stations"][1]["slots"][0] != "agriculture":
		failures.append("set_slot_preset: expected a bare preset name, got %s" % [m.doc["stations"][1]["slots"][0]])
	m.set_override("post_b", 0, "produces", {"FOOD": 9.0})
	var slot = m.doc["stations"][1]["slots"][0]
	if typeof(slot) != TYPE_DICTIONARY or slot["overrides"]["produces"] != {"FOOD": 9.0}:
		failures.append("set_override: expected an override on the slot, got %s" % [slot])
	m.reset_override("post_b", 0, "produces")
	slot = m.doc["stations"][1]["slots"][0]
	if slot != "agriculture":
		failures.append("reset_override: expected the slot back to the bare preset, got %s" % [slot])
	m.set_override("post_b", 0, "housing", 10.0)
	m.set_override("post_b", 0, "produces", {"FOOD": 1.0})
	m.reset_override("post_b", 0, "housing")
	slot = m.doc["stations"][1]["slots"][0]
	if typeof(slot) != TYPE_DICTIONARY or slot["overrides"].has("housing") or not slot["overrides"].has("produces"):
		failures.append("reset_override: expected only the housing key removed, got %s" % [slot])

static func _check_stock_quota_presets(failures: Array[String]) -> void:
	var m := _model()
	m.set_stock("post_b", "ORE", null)
	if m.doc["stations"][1]["stock"].has("ORE"):
		failures.append("set_stock: null must remove the key")
	m.set_stock("post_b", "FUEL", 12.0)
	if m.doc["stations"][1]["stock"].get("FUEL", -1.0) != 12.0:
		failures.append("set_stock: expected FUEL 12")
	m.set_stock("post_b", "FUEL", "")
	if m.doc["stations"][1]["stock"].has("FUEL"):
		failures.append("set_stock: an empty string must remove the key")
	m.set_quota("post_b", "COMBAT", 2)
	m.set_quota("post_b", "TRADER", 0)
	if m.doc["stations"][1]["quota"] != {"COMBAT": 2}:
		failures.append("set_quota: expected {COMBAT: 2}, got %s" % [m.doc["stations"][1]["quota"]])
	m.set_preset_field("mining", "housing", 900.0)
	if m.doc["presets"]["mining"]["housing"] != 900.0:
		failures.append("set_preset_field: expected housing 900")
	if not m.add_preset("scrapyard") or m.add_preset("scrapyard") or m.add_preset("") or not m.doc["presets"].has("scrapyard"):
		failures.append("add_preset: expected one new preset and refusals for a duplicate or empty name")

static func _check_unknown_keys(failures: Array[String]) -> void:
	var d := Validator.doc()
	d["systems"][1]["zz"] = {"keep": true}
	d["stations"][1]["zz"] = 5
	d["stations"][1]["extra"] = {"mood": "calm"}
	d["future"] = 1
	var m := MapEditModel.from_document(d)
	m.move_system("b", Vector2(0.4, 0.4))
	m.set_system_field("b", "name", "Bee")
	m.set_station_field("post_b", "art", "ring_3")
	m.set_slot_preset("post_b", 0, "agriculture")
	m.set_override("post_b", 0, "housing", 5.0)
	m.set_stock("post_b", "FUEL", 1.0)
	m.set_quota("post_b", "COMBAT", 1)
	m.set_station_extra("post_b", "note", "tense")
	m.set_station_extra("post_b", "note", null)
	m.set_station_extra("post_b", "tag", "x")
	var dup := m.duplicate_station("post_b")
	if m.doc["systems"][1].get("zz", {}).get("keep", false) != true:
		failures.append("unknown keys: system key lost")
	var st: Dictionary = m.doc["stations"][m.station_index("post_b")]
	if st["extra"].get("tag", "") != "x" or st["extra"].has("mood") == false:
		failures.append("set_station_extra: expected tag added and the existing mood kept, got %s" % [st["extra"]])
	if st.get("zz", -1) != 5 or st["extra"].get("mood", "") != "calm":
		failures.append("unknown keys: station key or extra lost")
	var copy: Dictionary = m.doc["stations"][m.station_index(dup)]
	if copy.get("zz", -1) != 5:
		failures.append("unknown keys: the duplicate lost a station key")
	if m.doc.get("future", -1) != 1:
		failures.append("unknown keys: top-level key lost")
	_check_slot_keys(failures)

static func _check_slot_keys(failures: Array[String]) -> void:
	var d := Validator.doc()
	d["stations"][1]["slots"][0] = {"preset": "mining", "note": "keep", "overrides": {"housing": 5.0}}
	var m := MapEditModel.from_document(d)
	m.set_override("post_b", 0, "produces", {"ORE": 9.0})
	m.reset_override("post_b", 0, "produces")
	m.reset_override("post_b", 0, "housing")
	var slot = m.doc["stations"][1]["slots"][0]
	if typeof(slot) != TYPE_DICTIONARY or slot.get("note", "") != "keep" or slot.has("overrides"):
		failures.append("slot keys: expected the unknown key kept and overrides gone, got %s" % [slot])
	m.dirty = false
	m.set_slot_preset("post_b", 0, "mining")
	if m.dirty:
		failures.append("set_slot_preset: choosing the current preset must not dirty the document")
	m.set_slot_preset("post_b", 0, "agriculture")
	slot = m.doc["stations"][1]["slots"][0]
	if typeof(slot) != TYPE_DICTIONARY or slot["preset"] != "agriculture" or slot.get("note", "") != "keep":
		failures.append("set_slot_preset: expected the new preset with the unknown key kept, got %s" % [slot])
