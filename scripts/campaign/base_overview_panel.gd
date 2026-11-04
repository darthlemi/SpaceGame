class_name BaseOverviewPanel
extends Control

const WEALTH_NAMES := {
	BaseEconomy.WealthLevel.POOR: "Poor",
	BaseEconomy.WealthLevel.MIDDLING: "Middling",
	BaseEconomy.WealthLevel.WEALTHY: "Wealthy",
}
const TREND_NAMES := {-1: "declining", 0: "stable", 1: "growing"}

var _economy: BaseEconomy
# Null at stations no power faction owns (home, neutral, pirate): no reputation or fines there.
var _faction: PowerFaction

@onready var title_label: Label = $Layout/TitleLabel
@onready var population_label: Label = $Layout/PopulationLabel
@onready var economy_label: Label = $Layout/EconomyLabel
@onready var produces_label: Label = $Layout/ProducesLabel
@onready var consumes_label: Label = $Layout/ConsumesLabel
@onready var reputation_label: Label = $Layout/ReputationLabel
@onready var fine_label: Label = $Layout/FineLabel
@onready var trade_goods_button: Button = $Layout/TradeGoodsButton
@onready var shipyard_button: Button = $Layout/ShipyardButton
@onready var repair_button: Button = $Layout/RepairButton
@onready var missions_button: Button = $Layout/MissionsButton
@onready var pay_fine_button: Button = $Layout/PayFineButton
@onready var undock_button: Button = $Layout/UndockButton

func _ready() -> void:
	pay_fine_button.pressed.connect(_on_pay_fine_pressed)
	# TODO: missions are not designed yet; the button is a disabled placeholder.
	missions_button.disabled = true
	visible = false

func open_for(base_name: String, economy: BaseEconomy, faction: PowerFaction) -> void:
	title_label.text = base_name
	_economy = economy
	_faction = faction
	visible = true
	refresh()

func close() -> void:
	visible = false
	_economy = null
	_faction = null

func refresh() -> void:
	if _economy == null:
		return
	population_label.text = "Population: %d (%s)" % [roundi(_economy.population), TREND_NAMES[_economy.population_trend]]
	economy_label.text = "Economy: %s" % WEALTH_NAMES[_economy.wealth_level()]
	produces_label.text = "Produces: %s" % _commodity_list("produces")
	consumes_label.text = "Consumes: %s" % _commodity_list("consumes")
	var has_faction := _faction != null
	reputation_label.visible = has_faction
	var owes_fine := has_faction and _faction.fine > 0
	fine_label.visible = owes_fine
	pay_fine_button.visible = owes_fine
	if has_faction:
		var standing := " (hostile)" if _faction.reputation < CampaignState.HOSTILE_REPUTATION_THRESHOLD else ""
		reputation_label.text = "Reputation: %d%s" % [roundi(_faction.reputation), standing]
	if owes_fine:
		fine_label.text = "Outstanding fine: %d" % _faction.fine
		pay_fine_button.text = "Pay Fine (%d)" % _faction.fine
		pay_fine_button.disabled = CampaignState.credits < _faction.fine

# role_field is "produces" or "consumes"; listed in Commodity.Type order.
func _commodity_list(role_field: String) -> String:
	var names: Array[String] = []
	for commodity in Commodity.Type.values():
		for slot in _economy.slots:
			if (slot.get(role_field) as Dictionary).has(commodity):
				names.append(Commodity.NAMES[commodity])
				break
	return "nothing" if names.is_empty() else ", ".join(names)

func _on_pay_fine_pressed() -> void:
	if _faction != null:
		CampaignState.pay_fine(_faction.faction_enum)
	refresh()
