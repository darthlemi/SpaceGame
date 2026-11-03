extends Control

@onready var speed_1x_button: Button = $Layout/SpeedRow/Speed1xButton
@onready var speed_3x_button: Button = $Layout/SpeedRow/Speed3xButton
@onready var speed_5x_button: Button = $Layout/SpeedRow/Speed5xButton
@onready var pause_button: Button = $Layout/PauseButton
@onready var paused_label: Label = $Layout/PausedLabel

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

func _on_speed_pressed(time_scale: float) -> void:
	Engine.time_scale = time_scale
	get_tree().paused = false
	_update_display()

func _on_pause_pressed() -> void:
	get_tree().paused = not get_tree().paused
	_update_display()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		get_tree().paused = not get_tree().paused
		_update_display()

func _update_display() -> void:
	paused_label.visible = get_tree().paused
	speed_1x_button.button_pressed = is_equal_approx(Engine.time_scale, 1.0)
	speed_3x_button.button_pressed = is_equal_approx(Engine.time_scale, 3.0)
	speed_5x_button.button_pressed = is_equal_approx(Engine.time_scale, 5.0)
