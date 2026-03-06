extends Node

const BASE_MODULE_NAME: String = "BaseModule"
const VERSION: String = "1.0.0"

signal module_initialized()
signal module_error(error: String)

var _internal_state: Dictionary = {}

func initialize():
	
	pass

func shutdown():
	
	pass

func _ready():
	EventBus.subscribe(EventBus.EventType.GAME_STARTED, _on_game_started)

func _on_game_started():
	_internal_state = {}
	module_initialized.emit()

func _validate_input(data: Dictionary, required_fields: Array[String]):
	for field in required_fields:
		if not data.has(field):
			module_error.emit("Missing required field: " + field)
			return false
	return true
