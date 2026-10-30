class_name HomeBase
extends Area2D

signal player_docked

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	if area is CampaignFleetIcon and area.behavior_type == CampaignFleetIcon.BehaviorType.PLAYER and area.fleet != null:
		area.fleet.repair_to_full()
		player_docked.emit()
