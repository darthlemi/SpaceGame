class_name DebugConsole
extends Control

signal command_entered(command: String)

const COMMANDS: Array[String] = ["AddFriend", "AddEnemy", "GodMode", "KillAll"]

@onready var input: LineEdit = $VBoxContainer/CommandInput
@onready var suggestions: ItemList = $VBoxContainer/Suggestions

func _ready() -> void:
	suggestions.visible = false
	input.text_changed.connect(_on_text_changed)
	input.text_submitted.connect(_on_text_submitted)
	suggestions.item_selected.connect(_on_suggestion_selected)

func _on_text_changed(new_text: String) -> void:
	suggestions.clear()
	var matches := matching_commands(new_text, COMMANDS)
	for m in matches:
		suggestions.add_item(m)
	suggestions.visible = not matches.is_empty()

func _on_suggestion_selected(index: int) -> void:
	input.text = suggestions.get_item_text(index)
	input.caret_column = input.text.length()
	suggestions.visible = false
	input.grab_focus()

func _on_text_submitted(text: String) -> void:
	suggestions.visible = false
	input.text = ""
	var matched := resolve_command(text, COMMANDS)
	if matched != "":
		command_entered.emit(matched)

static func matching_commands(prefix: String, commands: Array[String]) -> Array[String]:
	var trimmed := prefix.strip_edges()
	if trimmed.is_empty():
		return []
	var lower_prefix := trimmed.to_lower()
	var result: Array[String] = []
	for c in commands:
		if c.to_lower().begins_with(lower_prefix):
			result.append(c)
	return result

static func resolve_command(text: String, commands: Array[String]) -> String:
	var trimmed := text.strip_edges()
	for c in commands:
		if c.to_lower() == trimmed.to_lower():
			return c
	return ""
