class_name DebugMenu
extends CanvasLayer

# F12 toggles a click-only cheat panel. Scenes add their own sections; add_campaign_sections
# adds the ones that work anywhere there is a campaign (fuel, credits, crew, repair).

const FUEL_STEP := 100.0
const CREDIT_STEP := 1000
const CREW_STEP := 10

var _sections: VBoxContainer
var _panel: PanelContainer

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.position = Vector2(10, 10)
	_panel.visible = false
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 520)
	_panel.add_child(scroll)
	_sections = VBoxContainer.new()
	scroll.add_child(_sections)
	var title := Label.new()
	title.text = "Debug (F12)"
	_sections.add_child(title)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()

# entries: Array of [label: String, action: Callable].
func add_section(title: String, entries: Array) -> void:
	var header := Label.new()
	header.text = "-- %s --" % title
	_sections.add_child(header)
	for entry in entries:
		var button := Button.new()
		button.text = entry[0]
		button.focus_mode = Control.FOCUS_NONE  # keep key input on the game
		button.pressed.connect(entry[1])
		_sections.add_child(button)

func add_campaign_sections() -> void:
	add_section("Resources", [
		["+%d fuel" % FUEL_STEP, func(): _with_fleet(func(f): DebugActions.add_fuel(f, FUEL_STEP))],
		["-%d fuel" % FUEL_STEP, func(): _with_fleet(func(f): DebugActions.add_fuel(f, -FUEL_STEP))],
		["+%d credits" % CREDIT_STEP, func(): DebugActions.add_credits(CREDIT_STEP)],
		["-%d credits" % CREDIT_STEP, func(): DebugActions.add_credits(-CREDIT_STEP)],
		["+%d crew" % CREW_STEP, func(): _with_fleet(func(f): DebugActions.add_crew(f, CREW_STEP))],
		["-%d crew" % CREW_STEP, func(): _with_fleet(func(f): DebugActions.add_crew(f, -CREW_STEP))],
		["Repair fleet", func(): _with_fleet(DebugActions.repair_fleet)],
	])

func _with_fleet(action: Callable) -> void:
	if CampaignState.player_fleet != null:
		action.call(CampaignState.player_fleet)
