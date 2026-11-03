extends Control

const EMPTY_FUEL_COLOR := Color(1.0, 0.3, 0.3, 1.0)

@onready var ships_label: Label = $Layout/ShipsLabel
@onready var fuel_label: Label = $Layout/FuelLabel
@onready var crew_label: Label = $Layout/CrewLabel
@onready var credits_label: Label = $Layout/CreditsLabel
@onready var cargo_label: Label = $Layout/CargoLabel
@onready var fleet_button: Button = $Layout/FleetButton

func _ready() -> void:
	# Keep refreshing while docked (tree paused) so trades show up immediately.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_update_display()

func _process(_delta: float) -> void:
	_update_display()

func _update_display() -> void:
	# CampaignScene bootstraps the player fleet in its own _ready, after ours.
	var fleet: CampaignFleet = CampaignState.player_fleet
	if fleet == null:
		return
	ships_label.text = "Ships: %d" % fleet.ship_compositions.size()
	var fuel := fleet.fuel_amount()
	if fuel > 0.0:
		fuel_label.text = "Fuel: %.1f (-%.2f/s moving)" % [fuel, fleet.fuel_burn_rate()]
		fuel_label.remove_theme_color_override("font_color")
	else:
		fuel_label.text = "Fuel: EMPTY (%d%% speed)" % roundi(CampaignFleet.EMPTY_FUEL_SPEED_FACTOR * 100.0)
		fuel_label.add_theme_color_override("font_color", EMPTY_FUEL_COLOR)
	crew_label.text = "Crew: %d/%d (-%.1f cr/tick)" % [fleet.crew_total(), fleet.crew_capacity(), CampaignState.wage_bill(fleet)]
	credits_label.text = "Credits: %d" % CampaignState.credits
	cargo_label.text = "Cargo: %.1f/%d" % [fleet.cargo_total(), fleet.cargo_capacity()]
