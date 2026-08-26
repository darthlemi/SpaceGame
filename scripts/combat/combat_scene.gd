extends Node2D

@onready var player_ship: Ship = $PlayerShip
@onready var enemy_ship: Ship = $EnemyShip
@onready var rts_commander: RTSCommander = $RTSCommander
@onready var direct_pilot: DirectPilot = $DirectPilot
@onready var control_toggle: ControlToggle = $ControlToggle
@onready var ai_controller: AIController = $AIController
@onready var result_label: Label = $ResultLabel

func _ready() -> void:
	result_label.visible = false
	rts_commander.setup(player_ship, enemy_ship)
	direct_pilot.setup(player_ship, enemy_ship)
	control_toggle.setup(player_ship, rts_commander, direct_pilot)
	ai_controller.setup(enemy_ship, player_ship)

	player_ship.hull.destroyed.connect(_on_player_destroyed)
	enemy_ship.hull.destroyed.connect(_on_enemy_destroyed)

func _on_player_destroyed() -> void:
	_show_result("Defeat")

func _on_enemy_destroyed() -> void:
	_show_result("Victory")

func _show_result(text: String) -> void:
	result_label.text = text
	result_label.visible = true
	set_physics_process(false)
