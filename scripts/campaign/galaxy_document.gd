class_name GalaxyDocument
extends RefCounted

# The galaxy as a plain Dictionary ("document"), read from and written to data/galaxy.json.
# Unknown keys are preserved: known keys come first in a fixed order, the rest follow sorted.

const PATH := "res://data/galaxy.json"
const VERSION := 1
const FLOAT_DECIMALS := 4

const REQUIRED_KEYS := ["version", "start_system", "presets", "systems", "links", "stations"]
const DOC_KEYS := ["version", "start_system", "presets", "systems", "links", "stations"]
const PRESET_KEYS := ["kind", "produces", "consumes", "housing"]
const SYSTEM_KEYS := ["id", "name", "map", "tier", "extra"]
const STATION_KEYS := ["name", "system", "owner", "pos", "art", "slots", "stock", "quota", "extra"]
const SLOT_KEYS := ["preset", "overrides"]
const OVERRIDE_KEYS := ["produces", "consumes", "housing"]
# Keys whose numbers are integers in the document (parse_string returns every number as float).
const INT_KEYS := ["version", "tier"]

static func station_id(name: String) -> String:
	return name.to_lower().replace(" ", "_")

static func parse(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "doc": {}, "error": "line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "doc": {}, "error": "the top level must be an object"}
	for key in REQUIRED_KEYS:
		if not data.has(key):
			return {"ok": false, "doc": {}, "error": "missing top-level key '%s'" % key}
	if typeof(data["presets"]) != TYPE_DICTIONARY:
		return {"ok": false, "doc": {}, "error": "'presets' must be an object"}
	for key in ["systems", "links", "stations"]:
		if typeof(data[key]) != TYPE_ARRAY:
			return {"ok": false, "doc": {}, "error": "'%s' must be an array" % key}
	return {"ok": true, "doc": data, "error": ""}

static func load_file(path: String = PATH) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "doc": {}, "error": "cannot open %s (error %d)" % [path, FileAccess.get_open_error()]}
	return parse(file.get_as_text())

# True when the file already holds exactly this document. Git may check the file out with CRLF;
# that is not a change worth a rewrite.
static func matches_file(doc: Dictionary, path: String = PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var existing := FileAccess.open(path, FileAccess.READ)
	return existing != null and existing.get_as_text().replace("\r\n", "\n") == serialize(doc)

# Writes only when the text differs from the file, so saving an unchanged galaxy is a no-op.
# False means nothing was written: either already current (see matches_file) or the write failed.
static func save_file(doc: Dictionary, path: String = PATH) -> bool:
	if matches_file(doc, path):
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("GalaxyDocument: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(serialize(doc))
	return true

static func serialize(doc: Dictionary) -> String:
	var ordered := doc.duplicate()
	ordered["systems"] = _sorted_by(doc.get("systems", []), func(e): return str(e.get("id", "")))
	ordered["stations"] = _sorted_by(doc.get("stations", []), func(e): return station_id(str(e.get("name", ""))))
	var links: Array = []
	for pair in doc.get("links", []):
		links.append([pair[0], pair[1]] if str(pair[0]) <= str(pair[1]) else [pair[1], pair[0]])
	links.sort_custom(func(a, b): return str(a[0]) + "|" + str(a[1]) < str(b[0]) + "|" + str(b[1]))
	ordered["links"] = links
	return _emit(ordered, 0, "doc", "") + "\n"

static func _sorted_by(entries: Array, key_of: Callable) -> Array:
	var out := entries.duplicate()
	out.sort_custom(func(a, b): return key_of.call(a) < key_of.call(b))
	return out

static func _key_order(context: String) -> Array:
	match context:
		"doc":
			return DOC_KEYS
		"preset":
			return PRESET_KEYS
		"system":
			return SYSTEM_KEYS
		"station":
			return STATION_KEYS
		"slot":
			return SLOT_KEYS
		"overrides":
			return OVERRIDE_KEYS
	return []

# Context of a child value, from the parent's context and the child's key.
static func _child_context(context: String, key: String) -> String:
	# Free-form extra data keeps its numbers as written, whatever their key is called.
	if context == "extra" or (key == "extra" and context in ["station", "system"]):
		return "extra"
	match context:
		"doc":
			if key == "presets":
				return "presets"
			if key == "systems":
				return "system"
			if key == "stations":
				return "station"
		"presets":
			return "preset"
		"station":
			if key == "slots":
				return "slot"
		"slot":
			if key == "overrides":
				return "overrides"
	return ""

static func _emit(value, depth: int, context: String, key: String) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			return _emit_dict(value, depth, context)
		TYPE_ARRAY:
			return _emit_array(value, depth, context, key)
		TYPE_STRING, TYPE_STRING_NAME:
			return JSON.stringify(str(value))
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_NIL:
			return "null"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			return str(int(value)) if (key in INT_KEYS and context != "extra") or context == "quota" else _float(value)
	push_error("GalaxyDocument: cannot serialise a %s" % type_string(typeof(value)))
	return "null"

static func _float(value: float) -> String:
	var text := String.num(value, FLOAT_DECIMALS)
	if text.find(".") < 0 and text.find("e") < 0 and text.find("n") < 0:
		text += ".0"
	return text

static func _is_scalar(value) -> bool:
	return typeof(value) != TYPE_DICTIONARY and typeof(value) != TYPE_ARRAY

static func _ordered_keys(dict: Dictionary, context: String) -> Array:
	var order := _key_order(context)
	var keys: Array = dict.keys()
	keys.sort()
	if order.is_empty():
		return keys
	var known: Array = []
	for k in order:
		if dict.has(k):
			known.append(k)
	var rest: Array = []
	for k in keys:
		if not order.has(k):
			rest.append(k)
	return known + rest

static func _emit_dict(dict: Dictionary, depth: int, context: String) -> String:
	if dict.is_empty():
		return "{}"
	var keys := _ordered_keys(dict, context)
	var all_scalar := true
	for k in keys:
		if not _is_scalar(dict[k]):
			all_scalar = false
	# A dictionary of commodity amounts (or any flat map) stays on one line.
	if all_scalar and context != "doc":
		var parts: Array[String] = []
		for k in keys:
			parts.append("%s: %s" % [JSON.stringify(str(k)), _emit(dict[k], depth, context, str(k))])
		return "{" + ", ".join(parts) + "}"
	var pad := "  ".repeat(depth + 1)
	var lines: Array[String] = []
	for k in keys:
		var child_ctx := _child_context(context, str(k))
		if str(k) == "quota" and context == "station":
			child_ctx = "quota"
		lines.append("%s%s: %s" % [pad, JSON.stringify(str(k)), _emit(dict[k], depth + 1, child_ctx, str(k))])
	return "{\n" + ",\n".join(lines) + "\n" + "  ".repeat(depth) + "}"

static func _emit_array(array: Array, depth: int, context: String, key: String) -> String:
	if array.is_empty():
		return "[]"
	var all_scalar := true
	for v in array:
		if not _is_scalar(v):
			all_scalar = false
	if all_scalar:
		var parts: Array[String] = []
		for v in array:
			parts.append(_emit(v, depth, "", key))
		return "[" + ", ".join(parts) + "]"
	if key == "links":
		var pairs: Array[String] = []
		for v in array:
			pairs.append("  ".repeat(depth + 1) + _emit_array(v, depth + 1, "", key))
		return "[\n" + ",\n".join(pairs) + "\n" + "  ".repeat(depth) + "]"
	var pad := "  ".repeat(depth + 1)
	var lines: Array[String] = []
	for v in array:
		lines.append(pad + _emit(v, depth + 1, context, key))
	return "[\n" + ",\n".join(lines) + "\n" + "  ".repeat(depth) + "]"
