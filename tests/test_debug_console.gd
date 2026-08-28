extends RefCounted

const DebugConsole = preload("res://scripts/ui/debug_console.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []
	_check_matching_commands(failures)
	_check_resolve_command(failures)
	return failures

static func _check_matching_commands(failures: Array[String]) -> void:
	var commands: Array[String] = ["AddFriend", "AddEnemy", "GodMode", "KillAll"]

	var matches := DebugConsole.matching_commands("add", commands)
	if matches != ["AddFriend", "AddEnemy"]:
		failures.append("matching_commands: expected case-insensitive prefix match for 'add', got %s" % [matches])

	var empty_matches := DebugConsole.matching_commands("", commands)
	if not empty_matches.is_empty():
		failures.append("matching_commands: expected no suggestions for empty input, got %s" % [empty_matches])

	var no_matches := DebugConsole.matching_commands("zzz", commands)
	if not no_matches.is_empty():
		failures.append("matching_commands: expected no suggestions for unmatched prefix, got %s" % [no_matches])

static func _check_resolve_command(failures: Array[String]) -> void:
	var commands: Array[String] = ["AddFriend", "AddEnemy", "GodMode", "KillAll"]

	var resolved := DebugConsole.resolve_command("godmode", commands)
	if resolved != "GodMode":
		failures.append("resolve_command: expected case-insensitive exact match to 'GodMode', got '%s'" % resolved)

	var unresolved := DebugConsole.resolve_command("god", commands)
	if unresolved != "":
		failures.append("resolve_command: expected empty string for a partial (non-exact) match, got '%s'" % unresolved)
