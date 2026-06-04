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

	var candidate_options: Array = _candidate_options_for_target(target_data)
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
			if actor.side == "hostile":
				return {
					"target_type": "actor",
					"actor_id": actor.actor_id,
					"definition_id": actor.definition_id,
					"display_name": actor.display_name,
					"grid_position": actor.grid_position.to_dictionary(),
					"kind": "attack",
				}
			return {
				"target_type": "actor",
				"actor_id": actor.actor_id,
				"definition_id": actor.definition_id,
				"display_name": actor.display_name,
				"grid_position": actor.grid_position.to_dictionary(),
				"kind": "talk",
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


func _candidate_options_for_target(target_data: Dictionary) -> Array:
	var kind: String = str(target_data.get("kind", ""))
	match kind:
		"pickup":
			return [
				_option_for_target(target_data),
				_disabled_option("open_container", "open_container", "打开容器", "target_not_container"),
				_disabled_option("talk", "talk", "对话", "target_not_actor"),
				_disabled_option("attack", "attack", "攻击", "target_not_actor"),
			]
		"talk":
			return [
				_option_for_target(target_data),
				_disabled_option("attack", "attack", "攻击", "target_not_hostile"),
			]
		"attack":
			return [
				_option_for_target(target_data),
				_disabled_option("talk", "talk", "对话", "target_hostile"),
			]
		"wait":
			return [
				_option_for_target(target_data),
				_disabled_option("talk", "talk", "对话", "self_target"),
				_disabled_option("attack", "attack", "攻击", "self_target"),
			]
		"move":
			return [
				_option_for_target(target_data),
				_disabled_option("pickup", "pickup", "拾取", "target_empty"),
				_disabled_option("open_container", "open_container", "打开容器", "target_empty"),
			]
		"enter_subscene", "enter_outdoor_location", "enter_overworld", "exit_to_outdoor":
			return [
				_option_for_target(target_data),
				_disabled_option("pickup", "pickup", "拾取", "target_not_pickup"),
				_disabled_option("open_container", "open_container", "打开容器", "target_not_container"),
			]
		"container":
			return [
				_option_for_target(target_data),
				_disabled_option("pickup", "pickup", "拾取", "target_not_pickup"),
				_disabled_option("talk", "talk", "对话", "target_not_actor"),
				_disabled_option("attack", "attack", "攻击", "target_not_actor"),
			]
		"door":
			return [
				_option_for_target(target_data),
				{
					"id": "inspect",
					"kind": "inspect",
					"display_name": "检查",
				},
				_disabled_option("pickup", "pickup", "拾取", "target_not_pickup"),
				_disabled_option("open_container", "open_container", "打开容器", "target_not_container"),
			]
	return [
		_disabled_option("inspect", "inspect", "检查", "unsupported_target_kind"),
	]


func _option_for_target(target_data: Dictionary) -> Dictionary:
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
			return {
				"id": kind,
				"kind": kind,
				"display_name": target_data.get("display_name", "进入"),
				"target_map_id": target_data.get("target_map_id", ""),
				"target_id": target_data.get("target_id", ""),
				"return_spawn_id": target_data.get("return_spawn_id", ""),
				"target_entry_point_id": target_data.get("target_entry_point_id", ""),
				"entry_point_id": target_data.get("entry_point_id", ""),
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
		"door":
			var door: Dictionary = _dictionary_or_empty(target_data.get("door", {}))
			var door_name := str(target_data.get("display_name", door.get("display_name", "门"))).strip_edges()
			if door_name.is_empty():
				door_name = "门"
			var is_open := bool(door.get("is_open", false))
			return {
				"id": "door_toggle",
				"kind": "door_toggle",
				"display_name": "关闭%s" % door_name if is_open else "打开%s" % door_name,
				"target_id": target_data.get("target_id", ""),
				"door_id": str(door.get("door_id", target_data.get("target_id", ""))),
				"disabled": bool(door.get("locked", false)),
				"disabled_reason": "door_locked" if bool(door.get("locked", false)) else "",
			}
	return {}


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


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
