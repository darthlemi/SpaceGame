extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	_check_valid(failures)
	_check_links(failures)
	_check_start_and_player(failures)
	_check_ids(failures)
	_check_slots_and_data(failures)
	_check_warnings(failures)
	return failures

# Three systems in a chain a-b-c; the player station is in a (the start system).
static func doc() -> Dictionary:
	return {
		"version": 1,
		"start_system": "a",
		"presets": GalaxyData.default_presets(),
		"systems": [
			{"id": "a", "name": "A", "map": [0.2, 0.5], "extra": {}},
			{"id": "b", "name": "B", "map": [0.5, 0.5], "extra": {}},
			{"id": "c", "name": "C", "map": [0.8, 0.5], "extra": {}},
		],
		"links": [["a", "b"], ["b", "c"]],
		"stations": [
			{"name": "Home Base", "system": "a", "owner": "PLAYER", "pos": [600.0, 400.0], "art": "ring_2",
				"slots": ["trade_hub"], "stock": {}, "quota": {}, "extra": {}},
			{"name": "Post B", "system": "b", "owner": "NEUTRAL", "pos": [300.0, 250.0], "art": "ring_2",
				"slots": ["mining", "refinery"], "stock": {"ORE": 7.0}, "quota": {"TRADER": 1}, "extra": {}},
			{"name": "Post C", "system": "c", "owner": "PIRATE", "pos": [300.0, 250.0], "art": "ring_2",
				"slots": ["refinery"], "stock": {}, "quota": {"COMBAT": 1}, "extra": {}},
		],
	}

static func _has(findings: Array[Dictionary], severity: String, kind: String, id: String) -> bool:
	for f in findings:
		if f["severity"] == severity and f["target"]["kind"] == kind and f["target"]["id"] == id \
				and not str(f["message"]).is_empty():
			return true
	return false

static func _expect_block(failures: Array[String], label: String, d: Dictionary, kind: String, id: String) -> void:
	var findings := GalaxyValidator.validate(d)
	if not _has(findings, "block", kind, id) or not GalaxyValidator.has_blockers(findings):
		failures.append("%s: expected a block on %s '%s', got %s" % [label, kind, id, findings])

static func _check_valid(failures: Array[String]) -> void:
	var findings := GalaxyValidator.validate(doc())
	if not findings.is_empty():
		failures.append("valid doc: expected no findings, got %s" % [findings])
	var single := doc()
	single["systems"] = [single["systems"][0]]
	single["links"] = []
	single["stations"] = [single["stations"][0]]
	if not GalaxyValidator.validate(single).is_empty():
		failures.append("single system: expected a valid galaxy with no links, got %s" % [GalaxyValidator.validate(single)])
	if GalaxyValidator.has_blockers([]):
		failures.append("has_blockers: expected false for no findings")

static func _check_links(failures: Array[String]) -> void:
	var d := doc()
	d["links"] = [["a", "b"]]
	_expect_block(failures, "system with no links", d, "system", "c")
	d = doc()
	d["systems"] = [d["systems"][0], d["systems"][1]]
	d["stations"] = [d["stations"][0], d["stations"][1]]
	d["links"] = []
	_expect_block(failures, "two systems, no link", d, "system", "b")
	d = doc()
	d["systems"].append({"id": "d", "name": "D", "map": [0.1, 0.1], "extra": {}})
	d["systems"].append({"id": "e", "name": "E", "map": [0.9, 0.9], "extra": {}})
	d["links"].append(["d", "e"])
	_expect_block(failures, "unreachable pair", d, "system", "d")
	d = doc()
	d["links"].append(["a", "zzz"])
	_expect_block(failures, "link to an unknown system", d, "link", "a|zzz")

static func _check_start_and_player(failures: Array[String]) -> void:
	var d := doc()
	d["start_system"] = ""
	_expect_block(failures, "missing start_system", d, "doc", "")
	d = doc()
	d["start_system"] = "nowhere"
	_expect_block(failures, "unknown start_system", d, "doc", "")
	d = doc()
	d["stations"][1]["owner"] = "PLAYER"
	_expect_block(failures, "two player stations", d, "doc", "")
	d = doc()
	d["stations"][0]["owner"] = "NEUTRAL"
	_expect_block(failures, "no player station", d, "doc", "")
	d = doc()
	d["start_system"] = "b"
	_expect_block(failures, "start system without the player station", d, "doc", "")

static func _check_ids(failures: Array[String]) -> void:
	var d := doc()
	d["systems"].append({"id": "b", "name": "B2", "map": [0.1, 0.1], "extra": {}})
	_expect_block(failures, "duplicate system id", d, "system", "b")
	d = doc()
	d["stations"][1]["name"] = "A B"
	d["stations"][2]["name"] = "a b"
	_expect_block(failures, "duplicate station id", d, "station", "a_b")
	d = doc()
	d["stations"][1]["system"] = "nowhere"
	_expect_block(failures, "station in an unknown system", d, "station", "post_b")

static func _check_slots_and_data(failures: Array[String]) -> void:
	var d := doc()
	d["stations"][1]["slots"] = ["nonsense"]
	_expect_block(failures, "unknown preset", d, "station", "post_b")
	d = doc()
	d["stations"][1]["slots"] = ["mining", "mining", "mining"]
	_expect_block(failures, "more than 2 slots", d, "station", "post_b")
	d = doc()
	d["stations"][1]["slots"] = [{"preset": "mining", "overrides": {"produces": {"UNOBTAINIUM": 1.0}}}]
	_expect_block(failures, "unknown commodity in an override", d, "station", "post_b")
	d = doc()
	d["stations"][1]["slots"] = [{"preset": "mining", "overrides": {"consumes": {"ORE": -1.0}}}]
	_expect_block(failures, "negative override amount", d, "station", "post_b")
	d = doc()
	d["stations"][1]["slots"] = [{"preset": "mining", "overrides": {"housing": -5.0}}]
	_expect_block(failures, "negative housing override", d, "station", "post_b")
	d = doc()
	d["stations"][1]["stock"] = {"UNOBTAINIUM": 1.0}
	_expect_block(failures, "unknown commodity in stock", d, "station", "post_b")
	d = doc()
	d["stations"][1]["stock"] = {"ORE": -1.0}
	_expect_block(failures, "negative stock", d, "station", "post_b")
	d = doc()
	d["presets"]["mining"]["produces"] = {"UNOBTAINIUM": 1.0}
	_expect_block(failures, "unknown commodity in a preset", d, "doc", "")
	d = doc()
	d["stations"][1]["owner"] = "MARTIANS"
	_expect_block(failures, "unknown owner", d, "station", "post_b")
	d = doc()
	d["stations"][1]["quota"] = {"BOGUS": 1}
	_expect_block(failures, "unknown quota role", d, "station", "post_b")

static func _check_warnings(failures: Array[String]) -> void:
	var d := doc()
	d["stations"] = [d["stations"][0], d["stations"][1]]
	var findings := GalaxyValidator.validate(d)
	if not _has(findings, "warn", "system", "c") or GalaxyValidator.has_blockers(findings):
		failures.append("system with no stations: expected only a warning on c, got %s" % [findings])
	d = doc()
	d["stations"][1]["slots"] = []
	findings = GalaxyValidator.validate(d)
	if not _has(findings, "warn", "station", "post_b") or GalaxyValidator.has_blockers(findings):
		failures.append("station with no slots: expected only a warning on post_b, got %s" % [findings])
