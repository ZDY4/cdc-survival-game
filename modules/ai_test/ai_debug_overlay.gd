extends CanvasLayer

class_name AIDebugOverlay

@onready var _status_label: Label = $Panel/StatusLabel
@onready var _state_text: TextEdit = $Panel/StateText
@onready var _toggle_button: Button = $Panel/ToggleButton
@onready var _refresh_button: Button = $Panel/RefreshButton
@onready var _panel: Panel = $Panel

var _is_visible: bool = false

func _ready():
	_toggle_button.pressed.connect(_on_toggle_pressed)
	_refresh_button.pressed.connect(_on_refresh_pressed)
	
	# Hide by default
	_panel.visible = false
	
	# Connect to AI Test Bridge
	if AITestBridge:
		AITestBridge.state_requested.connect(_on_state_requested)
		AITestBridge.action_received.connect(_on_action_received)

func _input():
	if event is InputEventKey:
		if event.pressed && event.keycode == KEY_F12:
			_toggle_visibility()

func _toggle_visibility():
	_is_visible = not _is_visible
	_panel.visible = _is_visible
	
	if _is_visible:
		_refresh_state()

func _on_toggle_pressed():
	_toggle_visibility()

func _on_refresh_pressed():
	_refresh_state()

func _refresh_state():
	if not AITestBridge:
		_status_label.text = "AI Test Bridge: Not Available"
		return
	
	_status_label.text = "AI Test Bridge: " + ("Running" if AITestBridge.is_running() else "Stopped")
	_status_label.text += " | Port: " + str(AITestBridge.get_port())
	
	# Collect && display game state
	var state = _collect_game_state()
	_state_text.text = JSON.stringify(state, "\t")

func _collect_game_state(item: Dictionary = {}):
	var state = {
		"timestamp": Time.get_unix_time_from_system(),
		"player": {
			"hp": GameState.player_hp,
			"max_hp": GameState.player_max_hp,
			"hunger": GameState.player_hunger,
			"thirst": GameState.player_thirst,
			"stamina": GameState.player_stamina,
			"mental": GameState.player_mental,
			"position": GameState.player_position
		},
		"inventory": {
			"items_count": GameState.inventory_items.size(),
			"max_slots": GameState.inventory_max_slots
		},
		"world": {
		"time": WeatherModule.get_time_string() if WeatherModule else "N/A",
		"day": WeatherModule.get_current_day() if WeatherModule else 1,
		"danger_level": WeatherModule.get_danger_level() if WeatherModule else 0
		}
	}
	return state

func _on_state_requested():
	# Auto-refresh when state is requested via API
	if _is_visible:
		_refresh_state()

func _on_action_received():
	# Log actions in the overlay
	if _is_visible:
		var log_text = "[ACTION] " + action_type + "\n"
		log_text += "Parameters: " + JSON.stringify(parameters) + "\n\n"
		_state_text.text = log_text + _state_text.text