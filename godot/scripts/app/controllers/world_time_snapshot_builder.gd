extends RefCounted


func snapshot(simulation: RefCounted) -> Dictionary:
	if simulation == null:
		return {
			"day": "monday",
			"minute_of_day": 540,
			"hour": 9,
			"minute": 0,
			"display_time": "09:00",
			"display_label": "monday 09:00",
		}
	var runtime_snapshot: Dictionary = simulation.snapshot()
	var world_time: Dictionary = _dictionary_or_empty(runtime_snapshot.get("world_time", {}))
	var minute_of_day: int = posmod(int(world_time.get("minute_of_day", 540)), 1440)
	var hour := int(minute_of_day / 60)
	var minute := minute_of_day % 60
	var display_time := "%02d:%02d" % [hour, minute]
	var day := str(world_time.get("day", "monday"))
	return {
		"day": day,
		"minute_of_day": minute_of_day,
		"hour": hour,
		"minute": minute,
		"display_time": display_time,
		"display_label": "%s %s" % [day, display_time],
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
