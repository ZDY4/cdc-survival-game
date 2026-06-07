extends RefCounted


func query(simulation: RefCounted, actor_id: int, target: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return _failed_prompt("unknown_actor")

	var target_data: Dictionary = _resolve_target(simulation, target)
	if target_data.is_empty():
		return _failed_prompt("interaction_target_unavailable")
	var visibility: Dictionary = _visibility_check(simulation, actor_id, target_data)
	if not bool(visibility.get("success", true)):
		var failed: Dictionary = _failed_prompt(str(visibility.get("reason", "target_not_visible")))
		failed["target"] = target_data
		failed["target_name"] = target_data.get("display_name", "")
		failed["target_kind"] = target_data.get("kind", target_data.get("target_type", ""))
		failed["target_type"] = target_data.get("target_type", "")
		failed["target_grid"] = _dictionary_or_empty(visibility.get("target_grid", {}))
		return failed

	var candidate_options: Array = _candidate_options_for_target(simulation, actor, target_data)
	var enabled_options: Array = []
	var disabled_options: Array = []
	for candidate in candidate_options:
		var option: Dictionary = _enriched_option(_dictionary_or_empty(candidate))
		if bool(option.get("disabled", false)):
			disabled_options.append(option)
		else:
			enabled_options.append(option)
	if enabled_options.is_empty():
		return _failed_prompt("interaction_option_unavailable")

	var primary_option: Dictionary = _dictionary_or_empty(enabled_options[0])
	var target_grid: Dictionary = _target_grid(target_data)
	var target_distance: int = _target_distance(actor, target_grid)
	var interaction_range: int = int(primary_option.get("interaction_range", 1))
	return {
		"ok": true,
		"actor_id": actor_id,
		"target": target_data,
		"target_name": target_data.get("display_name", ""),
		"target_kind": target_data.get("kind", target_data.get("target_type", "")),
		"target_type": target_data.get("target_type", ""),
		"options": enabled_options,
		"disabled_options": disabled_options,
		"primary_option_id": primary_option.get("id", ""),
		"primary_option_kind": primary_option.get("kind", ""),
		"action_label": primary_option.get("display_name", primary_option.get("id", "")),
		"ap_cost": primary_option.get("ap_cost", 0.0),
		"interaction_range": interaction_range,
		"target_distance": target_distance,
		"requires_approach": target_distance > interaction_range if target_distance >= 0 else false,
	}


func _resolve_target(simulation: RefCounted, target: Dictionary) -> Dictionary:
	var target_type: String = str(target.get("target_type", "map_object"))
	match target_type:
		"actor":
			var actor_id: int = int(target.get("actor_id", 0))
			var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
			if actor == null:
				return {}
			if actor.actor_id == int(target.get("command_actor_id", 0)) or actor.actor_id == _player_actor_id(simulation):
				return {
					"target_type": "actor",
					"actor_id": actor.actor_id,
					"definition_id": actor.definition_id,
					"display_name": actor.display_name,
					"kind": "wait",
				}
			var hostility: Dictionary = _actor_hostility(simulation, _player_actor_id(simulation), actor.actor_id)
			if bool(hostility.get("hostile", actor.side == "hostile")):
				return {
					"target_type": "actor",
					"actor_id": actor.actor_id,
					"definition_id": actor.definition_id,
					"display_name": actor.display_name,
					"grid_position": actor.grid_position.to_dictionary(),
					"kind": "attack",
					"relationship_score": float(hostility.get("score", 0.0)),
					"hostility_reason": str(hostility.get("reason", "")),
				}
			return {
				"target_type": "actor",
				"actor_id": actor.actor_id,
				"definition_id": actor.definition_id,
				"display_name": actor.display_name,
				"grid_position": actor.grid_position.to_dictionary(),
				"kind": "talk",
				"relationship_score": float(hostility.get("score", 0.0)),
				"hostility_reason": str(hostility.get("reason", "")),
			}
		"self":
			var self_actor: RefCounted = simulation.actor_registry.get_actor(int(target.get("actor_id", _player_actor_id(simulation))))
			if self_actor == null:
				return {}
			return {
				"target_type": "actor",
				"actor_id": self_actor.actor_id,
				"definition_id": self_actor.definition_id,
				"display_name": self_actor.display_name,
				"kind": "wait",
			}
		"grid":
			var grid: Dictionary = _dictionary_or_empty(target.get("grid", target.get("target_position", {})))
			if grid.is_empty():
				return {}
			return {
				"target_type": "grid",
				"display_name": "移动",
				"kind": "move",
				"grid": grid,
			}
		_:
			var target_id: String = str(target.get("target_id", ""))
			if target_id.is_empty() or simulation.consumed_interaction_targets.has(target_id):
				return {}
			return simulation.map_interaction_targets.get(target_id, {})


func _visibility_check(simulation: RefCounted, actor_id: int, target_data: Dictionary) -> Dictionary:
	var target_grid: Dictionary = _target_grid(target_data)
	if target_grid.is_empty():
		return {"success": true}
	if simulation.has_method("is_cell_visible_to_actor") and not bool(simulation.call("is_cell_visible_to_actor", actor_id, target_grid)):
		return {
			"success": false,
			"reason": "target_not_visible",
			"target_grid": target_grid,
		}
	return {"success": true}


func _actor_hostility(simulation: RefCounted, actor_id: int, target_actor_id: int) -> Dictionary:
	if simulation != null and simulation.has_method("actor_hostility"):
		return _dictionary_or_empty(simulation.call("actor_hostility", actor_id, target_actor_id))
	return {"hostile": false, "reason": "hostility_api_missing", "score": 0.0}


func _target_grid(target_data: Dictionary) -> Dictionary:
	var grid: Dictionary = _dictionary_or_empty(target_data.get("grid_position", {}))
	if grid.is_empty():
		grid = _dictionary_or_empty(target_data.get("anchor", {}))
	if grid.is_empty():
		grid = _dictionary_or_empty(target_data.get("grid", {}))
	if grid.is_empty():
		var cells: Array = _array_or_empty(target_data.get("cells", []))
		if not cells.is_empty():
			grid = _dictionary_or_empty(cells[0])
	return grid


func _candidate_options_for_target(simulation: RefCounted, actor: RefCounted, target_data: Dictionary) -> Array:
	var kind: String = str(target_data.get("kind", ""))
	var station_option: Dictionary = _crafting_station_option(target_data)
	match kind:
		"pickup":
			var pickup_options := [
				_option_for_target(simulation, actor, target_data),
				_disabled_option("open_container", "open_container", "打开容器", "target_not_container"),
				_disabled_option("talk", "talk", "对话", "target_not_actor"),
				_disabled_option("attack", "attack", "攻击", "target_not_actor"),
			]
			_append_optional_enabled_option(pickup_options, station_option)
			return pickup_options
		"talk":
			return [
				_option_for_target(simulation, actor, target_data),
				_disabled_option("attack", "attack", "攻击", "target_not_hostile"),
			]
		"attack":
			return [
				_option_for_target(simulation, actor, target_data),
				_disabled_option("talk", "talk", "对话", "target_hostile"),
			]
		"wait":
			return [
				_option_for_target(simulation, actor, target_data),
				_disabled_option("talk", "talk", "对话", "self_target"),
				_disabled_option("attack", "attack", "攻击", "self_target"),
			]
		"move":
			return [
				_option_for_target(simulation, actor, target_data),
				_disabled_option("pickup", "pickup", "拾取", "target_empty"),
				_disabled_option("open_container", "open_container", "打开容器", "target_empty"),
			]
		"enter_subscene", "enter_outdoor_location", "enter_overworld", "exit_to_outdoor":
			return [
				_option_for_target(simulation, actor, target_data),
				{
					"id": "inspect",
					"kind": "inspect",
					"display_name": "检查",
				},
				_disabled_option("pickup", "pickup", "拾取", "target_not_pickup"),
				_disabled_option("open_container", "open_container", "打开容器", "target_not_container"),
			]
		"container":
			var container_options := [
				_option_for_target(simulation, actor, target_data),
				_disabled_option("pickup", "pickup", "拾取", "target_not_pickup"),
				_disabled_option("talk", "talk", "对话", "target_not_actor"),
				_disabled_option("attack", "attack", "攻击", "target_not_actor"),
			]
			_append_optional_enabled_option(container_options, station_option)
			return container_options
		"open_crafting":
			return [
				_option_for_target(simulation, actor, target_data),
				_disabled_option("pickup", "pickup", "拾取", "target_not_pickup"),
				_disabled_option("open_container", "open_container", "打开容器", "target_not_container"),
				_disabled_option("talk", "talk", "对话", "target_not_actor"),
				_disabled_option("attack", "attack", "攻击", "target_not_actor"),
			]
		"door":
			var door_options := [
				_option_for_target(simulation, actor, target_data),
				{
					"id": "inspect",
					"kind": "inspect",
					"display_name": "检查",
				},
				_disabled_option("pickup", "pickup", "拾取", "target_not_pickup"),
				_disabled_option("open_container", "open_container", "打开容器", "target_not_container"),
			]
			_append_optional_enabled_option(door_options, station_option)
			return door_options
	return [
		_disabled_option("inspect", "inspect", "检查", "unsupported_target_kind"),
	]


func _option_for_target(simulation: RefCounted, actor: RefCounted, target_data: Dictionary) -> Dictionary:
	var kind: String = str(target_data.get("kind", ""))
	match kind:
		"pickup":
			return {
				"id": "pickup",
				"kind": "pickup",
				"display_name": "拾取",
				"item_id": target_data.get("item_id", ""),
				"count": max(1, int(target_data.get("max_count", target_data.get("min_count", 1)))),
				"target_id": target_data.get("target_id", ""),
			}
		"talk":
			return {
				"id": "talk",
				"kind": "talk",
				"display_name": "对话",
				"dialogue_id": target_data.get("definition_id", target_data.get("target_id", "")),
			}
		"attack":
			return {
				"id": "attack",
				"kind": "attack",
				"display_name": "攻击",
				"target_actor_id": int(target_data.get("actor_id", 0)),
				"grid_position": target_data.get("grid_position", {}),
			}
		"wait":
			return {
				"id": "wait",
				"kind": "wait",
				"display_name": "等待",
				"target_actor_id": int(target_data.get("actor_id", 0)),
			}
		"move":
			return {
				"id": "move",
				"kind": "move",
				"display_name": "移动",
				"grid": target_data.get("grid", {}),
			}
		"enter_subscene", "enter_outdoor_location", "enter_overworld", "exit_to_outdoor":
			var permission: Dictionary = _transition_prompt_permission(simulation, target_data)
			var disabled_reason := str(permission.get("reason", ""))
			return {
				"id": kind,
				"kind": kind,
				"display_name": target_data.get("display_name", "进入"),
				"target_map_id": target_data.get("target_map_id", ""),
				"target_id": target_data.get("target_id", ""),
				"return_spawn_id": target_data.get("return_spawn_id", ""),
				"target_entry_point_id": target_data.get("target_entry_point_id", ""),
				"entry_point_id": target_data.get("entry_point_id", ""),
				"required_world_flags": _array_or_empty(target_data.get("required_world_flags", [])).duplicate(true),
				"blocked_world_flags": _array_or_empty(target_data.get("blocked_world_flags", [])).duplicate(true),
				"required_unlocked_locations": _array_or_empty(target_data.get("required_unlocked_locations", [])).duplicate(true),
				"blocked_unlocked_locations": _array_or_empty(target_data.get("blocked_unlocked_locations", [])).duplicate(true),
				"disabled": not disabled_reason.is_empty(),
				"disabled_reason": disabled_reason,
			}
		"container":
			var target_name := str(target_data.get("display_name", "容器")).strip_edges()
			if target_name.is_empty():
				target_name = "容器"
			return {
				"id": "open_container",
				"kind": "open_container",
				"display_name": "打开%s" % target_name,
				"target_id": target_data.get("target_id", ""),
			}
		"open_crafting":
			return _crafting_station_option(target_data)
		"door":
			var door: Dictionary = _dictionary_or_empty(target_data.get("door", {}))
			var door_name := str(target_data.get("display_name", door.get("display_name", "门"))).strip_edges()
			if door_name.is_empty():
				door_name = "门"
			var is_open := bool(door.get("is_open", false))
			var permission: Dictionary = _door_prompt_permission(actor, door)
			var disabled_reason := str(permission.get("reason", ""))
			return {
				"id": "door_toggle",
				"kind": "door_toggle",
				"display_name": "关闭%s" % door_name if is_open else "打开%s" % door_name,
				"target_id": target_data.get("target_id", ""),
				"door_id": str(door.get("door_id", target_data.get("target_id", ""))),
				"disabled": not disabled_reason.is_empty(),
				"disabled_reason": disabled_reason,
			}
	return {}


func _crafting_station_option(target_data: Dictionary) -> Dictionary:
	var station: Dictionary = _dictionary_or_empty(target_data.get("crafting_station", {}))
	var station_id := str(station.get("station_id", station.get("id", ""))).strip_edges()
	if station_id.is_empty():
		return {}
	var station_name := str(station.get("display_name", target_data.get("display_name", station_id))).strip_edges()
	if station_name.is_empty():
		station_name = station_id
	return {
		"id": "open_crafting",
		"kind": "open_crafting",
		"display_name": "使用%s" % station_name,
		"target_id": target_data.get("target_id", station.get("object_id", "")),
		"station_id": station_id,
		"station_name": station_name,
	}


func _append_optional_enabled_option(options: Array, option: Dictionary) -> void:
	if option.is_empty():
		return
	var option_id := str(option.get("id", ""))
	for existing in options:
		var existing_data: Dictionary = _dictionary_or_empty(existing)
		if str(existing_data.get("id", "")) == option_id:
			return
	options.append(option)


func _door_prompt_permission(actor: RefCounted, door: Dictionary) -> Dictionary:
	var unlock_consumed: bool = bool(door.get("unlock_requirements_consumed", false))
	var required_item_ids: Array[String] = [] if unlock_consumed else _required_item_ids(door)
	var missing_item_ids: Array[String] = _missing_actor_items(actor, required_item_ids)
	if not missing_item_ids.is_empty():
		return {"success": false, "reason": "door_key_missing", "item_id": missing_item_ids[0]}
	var required_tool_ids: Array[String] = [] if unlock_consumed else _required_tool_ids(door)
	var missing_tool_ids: Array[String] = _missing_actor_items(actor, required_tool_ids)
	if not missing_tool_ids.is_empty():
		return {"success": false, "reason": "door_tool_missing", "item_id": missing_tool_ids[0]}
	var has_unlock_requirements: bool = not required_item_ids.is_empty() or not required_tool_ids.is_empty()
	if bool(door.get("locked", false)) and not has_unlock_requirements:
		return {"success": false, "reason": "door_locked"}
	return {"success": true}


func _transition_prompt_permission(simulation: RefCounted, target_data: Dictionary) -> Dictionary:
	for flag_id in _string_array(target_data.get("required_world_flags", [])):
		if not _dictionary_or_empty(simulation.get("world_flags")).has(flag_id):
			return {"success": false, "reason": "scene_transition_world_flag_missing", "flag_id": flag_id}
	for flag_id in _string_array(target_data.get("blocked_world_flags", [])):
		if _dictionary_or_empty(simulation.get("world_flags")).has(flag_id):
			return {"success": false, "reason": "scene_transition_world_flag_blocked", "flag_id": flag_id}
	var unlocked_lookup: Dictionary = _string_lookup(simulation.get("unlocked_locations"))
	for location_id in _string_array(target_data.get("required_unlocked_locations", [])):
		if not unlocked_lookup.has(location_id):
			return {"success": false, "reason": "scene_transition_location_locked", "location_id": location_id}
	for location_id in _string_array(target_data.get("blocked_unlocked_locations", [])):
		if unlocked_lookup.has(location_id):
			return {"success": false, "reason": "scene_transition_location_blocked", "location_id": location_id}
	return {"success": true}


func _enriched_option(option: Dictionary) -> Dictionary:
	var enriched_option: Dictionary = option.duplicate(true)
	enriched_option["ap_cost"] = _ap_cost_for_option(enriched_option)
	enriched_option["interaction_range"] = _interaction_range_for_option(enriched_option)
	enriched_option["disabled"] = bool(enriched_option.get("disabled", false))
	if not enriched_option.has("disabled_reason"):
		enriched_option["disabled_reason"] = ""
	return enriched_option


func _disabled_option(id: String, kind: String, display_name: String, reason: String) -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"display_name": display_name,
		"disabled": true,
		"disabled_reason": reason,
	}


func _player_actor_id(simulation: RefCounted) -> int:
	for actor in simulation.actor_registry.actors():
		if actor.kind == "player":
			return actor.actor_id
	return 1


func _failed_prompt(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"options": [],
		"disabled_options": [],
	}


func _ap_cost_for_option(option: Dictionary) -> float:
	match str(option.get("kind", "")):
		"move":
			return 0.0
		"attack":
			return 2.0
		_:
			return 1.0


func _interaction_range_for_option(option: Dictionary) -> int:
	match str(option.get("kind", "")):
		"wait":
			return 0
		"talk":
			return 2
		"move":
			return 0
		"attack":
			return 1
		_:
			return 1


func _target_distance(actor: RefCounted, target_grid: Dictionary) -> int:
	if actor == null or target_grid.is_empty():
		return -1
	if actor.grid_position.y != int(target_grid.get("y", actor.grid_position.y)):
		return 999999
	return abs(actor.grid_position.x - int(target_grid.get("x", actor.grid_position.x))) + abs(actor.grid_position.z - int(target_grid.get("z", actor.grid_position.z)))


func _required_item_ids(value: Dictionary) -> Array[String]:
	var output: Array[String] = []
	_append_unique_normalized_item_id(output, value.get("required_item_ids", []))
	_append_unique_normalized_item_id(output, value.get("required_items", []))
	return output


func _required_tool_ids(value: Dictionary) -> Array[String]:
	var output: Array[String] = []
	_append_unique_normalized_item_id(output, value.get("required_tool_ids", []))
	_append_unique_normalized_item_id(output, value.get("required_tools", []))
	return output


func _missing_actor_items(actor: RefCounted, item_ids: Array[String]) -> Array[String]:
	var missing: Array[String] = []
	for item_id in item_ids:
		if _actor_has_item(actor, item_id):
			continue
		missing.append(item_id)
	return missing


func _actor_has_item(actor: RefCounted, item_id: String) -> bool:
	if actor == null or item_id.is_empty():
		return false
	if int(actor.inventory.get(item_id, 0)) > 0:
		return true
	for slot_id in actor.equipment.keys():
		if _normalize_content_id(actor.equipment.get(slot_id, "")) == item_id:
			return true
	return false


func _append_unique_normalized_item_id(output: Array[String], value: Variant) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		_append_one_normalized_item_id(output, value)
		return
	if typeof(value) == TYPE_ARRAY:
		for entry in value:
			_append_one_normalized_item_id(output, entry)
		return
	_append_one_normalized_item_id(output, value)


func _append_one_normalized_item_id(output: Array[String], value: Variant) -> void:
	var raw_value: Variant = value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = _dictionary_or_empty(value)
		raw_value = data.get("item_id", data.get("itemId", data.get("tool_id", data.get("toolId", data.get("id", "")))))
	var normalized_entry: String = _normalize_content_id(raw_value)
	if normalized_entry.is_empty() or output.has(normalized_entry):
		return
	output.append(normalized_entry)


func _normalize_content_id(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT:
		var float_value: float = value
		if is_equal_approx(float_value, roundf(float_value)):
			return str(int(float_value))
	if typeof(value) == TYPE_INT:
		return str(value)
	return str(value).strip_edges()


func _string_array(value: Variant) -> Array[String]:
	var output: Array[String] = []
	if typeof(value) == TYPE_STRING:
		var normalized_value := str(value).strip_edges()
		if not normalized_value.is_empty():
			output.append(normalized_value)
		return output
	for entry in _array_or_empty(value):
		var normalized_entry := str(entry).strip_edges()
		if not normalized_entry.is_empty():
			output.append(normalized_entry)
	return output


func _string_lookup(value: Variant) -> Dictionary:
	var output: Dictionary = {}
	for entry in _string_array(value):
		output[entry] = true
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
