extends RefCounted

var registry: RefCounted


func _init(p_registry: RefCounted = null) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary, world_snapshot: Dictionary, selected_target: Dictionary = {}) -> Dictionary:
	var player := _player_actor(runtime_snapshot)
	var prompt := _prompt_summary(selected_target)
	return {
		"world": {
			"map_id": runtime_snapshot.get("active_map_id", ""),
			"actor_count": runtime_snapshot.get("actors", []).size(),
			"event_count": runtime_snapshot.get("events", []).size(),
		},
		"player": {
			"actor_id": int(player.get("actor_id", 0)),
			"display_name": player.get("display_name", ""),
			"grid_position": player.get("grid_position", {}),
			"inventory": player.get("inventory", {}),
			"active_dialogue_id": player.get("active_dialogue_id", ""),
		},
		"map": {
			"object_count": world_snapshot.get("map", {}).get("object_count", 0),
			"pickup_count": world_snapshot.get("map", {}).get("pickup_objects", []).size(),
			"trigger_count": world_snapshot.get("map", {}).get("trigger_objects", []).size(),
			"interactive_count": world_snapshot.get("map", {}).get("interactive_objects", []).size(),
		},
		"interaction": prompt,
		"hotbar": _hotbar_summary(runtime_snapshot),
		"tracked_quest": {"active": false, "quest_id": ""},
	}


func _player_actor(runtime_snapshot: Dictionary) -> Dictionary:
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if actor_data.get("kind", "") == "player":
			return actor_data
	return {}


func _prompt_summary(selected_target: Dictionary) -> Dictionary:
	if selected_target.is_empty():
		return {
			"has_target": false,
			"target_name": "",
			"target_kind": "",
			"target_type": "",
			"primary_option_id": "",
			"primary_option_kind": "",
			"action_label": "",
			"ap_cost": 0.0,
			"options": [],
			"disabled_options": [],
		}
	return {
		"has_target": true,
		"target_name": selected_target.get("target_name", selected_target.get("display_name", "")),
		"target_kind": selected_target.get("target_kind", ""),
		"target_type": selected_target.get("target_type", ""),
		"primary_option_id": selected_target.get("primary_option_id", ""),
		"primary_option_kind": selected_target.get("primary_option_kind", ""),
		"action_label": selected_target.get("action_label", ""),
		"ap_cost": float(selected_target.get("ap_cost", 0.0)),
		"options": selected_target.get("options", []),
		"disabled_options": selected_target.get("disabled_options", []),
	}


func _hotbar_summary(runtime_snapshot: Dictionary) -> Array[Dictionary]:
	var hotbar: Dictionary = _dictionary_or_empty(runtime_snapshot.get("hotbar", {}))
	var output: Array[Dictionary] = []
	for slot_index in range(1, 11):
		var slot_id := "slot_%d" % slot_index
		var slot_data: Dictionary = _dictionary_or_empty(hotbar.get(slot_id, {}))
		var kind := str(slot_data.get("kind", ""))
		var skill_id := str(slot_data.get("skill_id", ""))
		var item_id := str(slot_data.get("item_id", ""))
		var entry_id := item_id if kind == "item" else skill_id
		output.append({
			"slot_id": slot_id,
			"key": "0" if slot_index == 10 else str(slot_index),
			"kind": kind,
			"skill_id": skill_id,
			"item_id": item_id,
			"label": _hotbar_label(kind, entry_id),
			"cooldown_remaining": float(slot_data.get("cooldown_remaining", 0.0)),
			"empty": slot_data.is_empty() or entry_id.is_empty(),
		})
	return output


func _hotbar_label(kind: String, entry_id: String) -> String:
	if kind == "item":
		return _item_label(entry_id)
	return _skill_label(entry_id)


func _skill_label(skill_id: String) -> String:
	if skill_id.is_empty():
		return ""
	var parts := skill_id.split("_")
	for index in range(parts.size()):
		parts[index] = str(parts[index]).capitalize()
	return " ".join(parts)


func _item_label(item_id: String) -> String:
	if item_id.is_empty():
		return ""
	if registry != null:
		var record: Dictionary = _dictionary_or_empty(registry.get_library("items").get(item_id, {}))
		var data: Dictionary = _dictionary_or_empty(record.get("data", record))
		var name := str(data.get("name", ""))
		if not name.is_empty():
			return name
	return item_id


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
