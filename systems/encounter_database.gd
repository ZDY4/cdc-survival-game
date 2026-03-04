extends Node
# EncounterDatabase - 遭遇数据库
# 数据从 DataManager 加载

# 遭遇数据缓存（从 DataManager 加载）
var _encounters: Dictionary = {}


func _get_encounter(encounter_id: String) -> Dictionary:
	return _encounters.get(encounter_id, {})


func _ready():
	_load_encounters_from_manager()


func _load_encounters_from_manager():
	var dm = get_node_or_null("/root/DataManager")
	if dm:
		_encounters = dm.get_all_encounters()

	if _encounters.is_empty():
		push_warning("[EncounterDatabase] 无法从 DataManager 加载遭遇数据")


func get_all_encounters() -> Dictionary:
	return _encounters.duplicate()


func get_encounter(encounter_id: String) -> Dictionary:
	return _get_encounter(encounter_id).duplicate()


func get_encounters_by_location(location: String) -> Array:
	var result = []
	for encounter_id in _encounters.keys():
		var encounter = _encounters[encounter_id]
		if encounter.has("locations") and location in encounter.locations:
			result.append(encounter)
	return result
