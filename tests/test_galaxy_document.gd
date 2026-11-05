extends RefCounted

const TMP_PATH := "user://galaxy_document_test.json"

static func run() -> Array[String]:
	var failures: Array[String] = []
	_check_round_trip(failures)
	_check_unknown_keys(failures)
	_check_key_order(failures)
	_check_floats(failures)
	_check_parse_errors(failures)
	_check_save_file(failures)
	_check_real_file(failures)
	return failures

static func _doc() -> Dictionary:
	return {
		"version": 1,
		"start_system": "haven",
		"presets": {"mining": {"kind": "MINING", "produces": {"ORE": 5.0}, "consumes": {}, "housing": 800.0}},
		"systems": [
			{"id": "wexford", "name": "Wexford", "map": [0.37, 0.54], "extra": {}},
			{"id": "haven", "name": "Haven", "map": [0.51, 0.5], "tier": 2, "extra": {}},
		],
		"links": [["wexford", "haven"]],
		"stations": [
			{"name": "Wexford Post", "system": "wexford", "owner": "FREEHOLD", "pos": [850.0, 420.0], "art": "truss_1",
				"slots": ["mining", {"preset": "mining", "overrides": {"produces": {"ORE": 9.0}}}],
				"stock": {"ORE": 7.0}, "quota": {"COMBAT": 1, "TRADER": 1}, "extra": {}},
			{"name": "Home Base", "system": "haven", "owner": "PLAYER", "pos": [600.0, 400.0], "art": "ring_2",
				"slots": [], "stock": {}, "quota": {}, "extra": {}},
		],
	}

static func _check_round_trip(failures: Array[String]) -> void:
	var first := GalaxyDocument.serialize(_doc())
	var parsed := GalaxyDocument.parse(first)
	if not parsed["ok"]:
		failures.append("round trip: parse failed: %s" % parsed["error"])
		return
	if GalaxyDocument.serialize(parsed["doc"]) != first:
		failures.append("round trip: serialize(parse(serialize(doc))) differs from serialize(doc)")
	var tier: int = int(parsed["doc"]["systems"][0].get("tier", -1))
	if tier != 2 or first.find("\"tier\": 2,") < 0 or first.find("\"COMBAT\": 1,") < 0:
		failures.append("round trip: expected tier and quota counts as integers, got:\n%s" % first)

static func _check_unknown_keys(failures: Array[String]) -> void:
	var doc := _doc()
	doc["future"] = {"a": 1}
	doc["systems"][0]["extra"] = {"mood": "calm"}
	doc["stations"][0]["zz"] = 5
	var back: Dictionary = GalaxyDocument.parse(GalaxyDocument.serialize(doc))["doc"]
	if back.get("future", {}).get("a", -1) != 1:
		failures.append("unknown keys: top-level 'future' lost")
	var wexford: Dictionary = {}
	for sys in back["systems"]:
		if sys["id"] == "wexford":
			wexford = sys
	if wexford.get("extra", {}).get("mood", "") != "calm":
		failures.append("unknown keys: system extra.mood lost")
	var post: Dictionary = {}
	for st in back["stations"]:
		if st["name"] == "Wexford Post":
			post = st
	if post.get("zz", -1) != 5:
		failures.append("unknown keys: station key 'zz' lost")

static func _check_key_order(failures: Array[String]) -> void:
	var shuffled := {}
	var doc := _doc()
	var keys := doc.keys()
	keys.reverse()
	for k in keys:
		shuffled[k] = doc[k]
	var reversed_station: Dictionary = {}
	var station_keys: Array = doc["stations"][0].keys()
	station_keys.reverse()
	for k in station_keys:
		reversed_station[k] = doc["stations"][0][k]
	shuffled["stations"] = [doc["stations"][1], reversed_station]
	shuffled["systems"] = [doc["systems"][1], doc["systems"][0]]
	var a := GalaxyDocument.serialize(doc)
	var b := GalaxyDocument.serialize(shuffled)
	if a != b:
		failures.append("key order: documents with different insertion order serialise differently")
	if a.find("\"haven\"") > a.find("\"wexford\"", a.find("\"systems\"")):
		failures.append("key order: systems are not sorted by id")
	if a.find("Home Base") > a.find("Wexford Post"):
		failures.append("key order: stations are not sorted by id")
	if a.find("\"version\"") != a.find("{\n") + 4 or a.find("\"start_system\"") > a.find("\"presets\""):
		failures.append("key order: top-level keys are not in the fixed order")

static func _check_floats(failures: Array[String]) -> void:
	var doc := _doc()
	doc["systems"][0]["map"] = [0.123456, 5.0]
	var text := GalaxyDocument.serialize(doc)
	if text.find("[0.1235, 5.0]") < 0:
		failures.append("floats: expected 0.123456 as 0.1235 and 5.0 as 5.0, got:\n%s" % text)
	if not text.ends_with("}\n") or text.ends_with("\n\n"):
		failures.append("floats: expected exactly one trailing newline")
	if text.find("\r") >= 0:
		failures.append("floats: output contains a carriage return")

static func _check_parse_errors(failures: Array[String]) -> void:
	for text in ["not json", "[]", "{}"]:
		var result := GalaxyDocument.parse(text)
		if result["ok"] or str(result["error"]).is_empty():
			failures.append("parse(%s): expected ok == false with an error" % text)
	var missing := GalaxyDocument.load_file("res://data/missing.json")
	if missing["ok"] or str(missing["error"]).is_empty():
		failures.append("load_file(missing): expected ok == false with an error")

static func _check_real_file(failures: Array[String]) -> void:
	var loaded := GalaxyDocument.load_file()
	if not loaded["ok"]:
		failures.append("real file: %s" % loaded["error"])
		return
	var on_disk := FileAccess.get_file_as_string(GalaxyDocument.PATH).replace("\r\n", "\n")
	if GalaxyDocument.serialize(loaded["doc"]) != on_disk:
		failures.append("real file: data/galaxy.json is not in canonical form (a Save would rewrite it)")

static func _check_save_file(failures: Array[String]) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))
	var doc := _doc()
	if not GalaxyDocument.save_file(doc, TMP_PATH):
		failures.append("save_file: first save should write")
	var first_time := FileAccess.get_modified_time(TMP_PATH)
	if GalaxyDocument.save_file(doc, TMP_PATH):
		failures.append("save_file: identical second save should not write")
	if FileAccess.get_modified_time(TMP_PATH) != first_time:
		failures.append("save_file: identical second save changed the modified time")
	var crlf_file := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	crlf_file.store_string(GalaxyDocument.serialize(doc).replace("\n", "\r\n"))
	crlf_file.close()
	if GalaxyDocument.save_file(doc, TMP_PATH) or not GalaxyDocument.matches_file(doc, TMP_PATH):
		failures.append("save_file: a CRLF copy of the same text must count as unchanged")
	if GalaxyDocument.save_file(doc, "user://no_such_dir/galaxy.json") or GalaxyDocument.matches_file(doc, "user://no_such_dir/galaxy.json"):
		failures.append("save_file: a failed write must return false and not claim the file is current")
	doc["start_system"] = "wexford"
	if not GalaxyDocument.save_file(doc, TMP_PATH):
		failures.append("save_file: an edited doc should write")
	if GalaxyDocument.load_file(TMP_PATH)["doc"].get("start_system", "") != "wexford":
		failures.append("save_file: the edit was not written")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))
