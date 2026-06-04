extends RefCounted


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
