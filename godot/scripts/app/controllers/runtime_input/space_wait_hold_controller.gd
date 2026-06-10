extends RefCounted

const SPACE_HOLD_INITIAL_DELAY_SEC := 0.45
const SPACE_HOLD_REPEAT_INTERVAL_SEC := 0.30

var is_held := false
var elapsed_sec := 0.0
var repeated := false


func process(delta: float, repeat_allowed: bool, press_space_action: Callable) -> void:
	if not is_held:
		return
	if not repeat_allowed:
		stop()
		return
	elapsed_sec += delta
	var interval := SPACE_HOLD_REPEAT_INTERVAL_SEC if repeated else SPACE_HOLD_INITIAL_DELAY_SEC
	if elapsed_sec < interval:
		return
	elapsed_sec = 0.0
	repeated = true
	if press_space_action.is_valid():
		var result: Dictionary = _dictionary_or_empty(press_space_action.call())
		if not result_can_repeat(result):
			stop()


func start_if_allowed(result: Dictionary, repeat_allowed: bool) -> void:
	if not result_can_repeat(result) or not repeat_allowed:
		stop()
		return
	is_held = true
	elapsed_sec = 0.0
	repeated = false


func stop() -> void:
	is_held = false
	elapsed_sec = 0.0
	repeated = false


func result_can_repeat(result: Dictionary) -> bool:
	return bool(result.get("success", false)) and (bool(result.get("waited", false)) or str(result.get("kind", "")) == "wait")


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
