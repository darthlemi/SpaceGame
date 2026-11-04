extends Control

@onready var speed_1x_button: Button = $Row/Speed1xButton
@onready var speed_3x_button: Button = $Row/Speed3xButton
@onready var speed_5x_button: Button = $Row/Speed5xButton
@onready var pause_button: Button = $Row/PauseButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 1.0
	get_tree().paused = false
	speed_1x_button.pressed.connect(_on_speed_pressed.bind(1.0))
	speed_3x_button.pressed.connect(_on_speed_pressed.bind(3.0))
	speed_5x_button.pressed.connect(_on_speed_pressed.bind(5.0))
	pause_button.pressed.connect(_on_pause_pressed)
	_update_display()

func _process(_delta: float) -> void:
	_update_display()

# The respawn panel keeps the game paused until a ship is chosen.
func _on_speed_pressed(time_scale: float) -> void:
	if _respawn_pending():
		return
	Engine.time_scale = time_scale
	get_tree().paused = false
	_update_display()

func _on_pause_pressed() -> void:
	if _respawn_pending():
		return
	get_tree().paused = not get_tree().paused
	_update_display()

func _unhandled_input(event: InputEvent) -> void:
	if _respawn_pending():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		get_tree().paused = not get_tree().paused
		_update_display()

# Looked up by path: the autoload identifier is unavailable when tests compile this script standalone.
func _respawn_pending() -> bool:
	var state = get_node_or_null("/root/CampaignState")
	return state != null and state.pending_respawn

# Runs every frame, so the looks reassert themselves after a toggle-mode click flips them.
func _update_display() -> void:
	var paused := get_tree().paused
	pause_button.set_pressed_no_signal(paused)
	_show_speed(speed_1x_button, 1.0, paused)
	_show_speed(speed_3x_button, 3.0, paused)
	_show_speed(speed_5x_button, 5.0, paused)

# While paused, the speed the game will resume at shows the hover look instead of pressed.
func _show_speed(button: Button, time_scale: float, paused: bool) -> void:
	var active := is_equal_approx(Engine.time_scale, time_scale)
	button.set_pressed_no_signal(active and not paused)
	if active and paused:
		button.add_theme_stylebox_override("normal", get_theme_stylebox("hover", "Button"))
	else:
		button.remove_theme_stylebox_override("normal")
