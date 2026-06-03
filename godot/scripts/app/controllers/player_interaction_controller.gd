extends RefCounted

const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")

var registry: RefCounted
var simulation: RefCounted
var world_result: Dictionary = {}
var player_actor_id: int = 0
var selected_target: Dictionary = {}
var selected_prompt: Dictionary = {}


func _init(p_registry: RefCounted, p_simulation: RefCounted, p_world_result: Dictionary) -> void:
	registry = p_registry
	simulation = p_simulation
	world_result = p_world_result
	player_actor_id = _find_player_actor_id()


func select_target(target: Dictionary) -> Dictionary:
	selected_target = target.duplicate(true)
	selected_prompt = {}
	if selected_target.is_empty():
		return _selection_result(true)
	if player_actor_id <= 0:
		selected_prompt = _failed_prompt("player_actor_missing")
		return _selection_result(false)

	# 查询阶段只生成可展示的交互提示，不改变运行时状态。
	selected_prompt = simulation.query_interaction_options(player_actor_id, selected_target)
	return _selection_result(bool(selected_prompt.get("ok", false)))


func select_node(node: Node) -> Dictionary:
	if node == null or not node.has_meta("interaction_target"):
		return clear_selection()
	var metadata: Variant = node.get_meta("interaction_target")
	if typeof(metadata) != TYPE_DICTIONARY:
		selected_prompt = _failed_prompt("interaction_target_metadata_invalid")
		return _selection_result(false)
	return select_target(metadata)


func clear_selection() -> Dictionary:
	selected_target = {}
	selected_prompt = {}
	return _selection_result(true)


func execute_primary_interaction() -> Dictionary:
	return execute_selected_option(str(selected_prompt.get("primary_option_id", "")))


func execute_selected_option(option_id: String) -> Dictionary:
	if selected_target.is_empty():
		return _execution_result(false, "interaction_target_not_selected", {})
	if player_actor_id <= 0:
		return _execution_result(false, "player_actor_missing", {})

	var resolved_option_id := option_id
	if resolved_option_id.is_empty():
		resolved_option_id = str(selected_prompt.get("primary_option_id", ""))
	var result: Dictionary = simulation.submit_player_command({
		"kind": "interact",
		"actor_id": player_actor_id,
		"target": selected_target,
		"option_id": resolved_option_id,
		"topology": _dictionary_or_empty(world_result.get("map", {})),
	})
	if bool(result.get("success", false)):
		_refresh_world_after_success(result)
		# 交互成功后重新查询，已消费目标会自然变成不可用提示。
		select_target(selected_target)
	else:
		selected_prompt = _failed_prompt(str(result.get("reason", "interaction_failed")))
	return _execution_result(bool(result.get("success", false)), str(result.get("reason", "")), result)


func select_grid(grid: Dictionary) -> Dictionary:
	return select_target({
		"target_type": "grid",
		"grid": grid.duplicate(true),
	})


func execute_move_to_grid(grid: Dictionary) -> Dictionary:
	if player_actor_id <= 0:
		return _execution_result(false, "player_actor_missing", {})
	selected_target = {
		"target_type": "grid",
		"grid": grid.duplicate(true),
	}
	selected_prompt = simulation.query_interaction_options(player_actor_id, selected_target)
	var result: Dictionary = simulation.submit_player_command({
		"kind": "move",
		"actor_id": player_actor_id,
		"target_position": grid,
		"topology": _dictionary_or_empty(world_result.get("map", {})),
	})
	if bool(result.get("success", false)):
		_refresh_world_after_success(result)
		select_grid(_dictionary_or_empty(result.get("to", grid)))
	else:
		selected_prompt = _failed_prompt(str(result.get("reason", "move_failed")))
	return _execution_result(bool(result.get("success", false)), str(result.get("reason", "")), result)


func cancel_pending(reason: String = "cancelled", auto_end_turn: bool = false) -> Dictionary:
	var result: Dictionary = simulation.cancel_pending(reason, auto_end_turn, _dictionary_or_empty(world_result.get("map", {})))
	selected_prompt = _failed_prompt("pending_cancelled:%s" % reason) if bool(result.get("had_pending", false)) else current_prompt()
	return result


func current_prompt() -> Dictionary:
	return selected_prompt.duplicate(true)


func _refresh_world_after_success(result: Dictionary) -> void:
	var context_snapshot: Dictionary = _dictionary_or_empty(result.get("context_snapshot", {}))
	var map_changed: bool = context_snapshot.has("active_map_id")
	var target_consumed: bool = bool(result.get("consumed_target", false))
	var defeated: bool = bool(result.get("defeated", false))
	var moved: bool = str(result.get("kind", "")) == "move"
	var approached: bool = not _dictionary_or_empty(result.get("approach_result", {})).is_empty()
	if map_changed or target_consumed or defeated or moved or approached:
		_rebuild_world_for_active_map()


func _rebuild_world_for_active_map() -> void:
	var rebuilt: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
	if bool(rebuilt.get("ok", false)):
		world_result = rebuilt
		var map: Dictionary = _dictionary_or_empty(world_result.get("map", {}))
		simulation.configure_map_interactions(_dictionary_or_empty(map.get("interaction_targets", {})))
	else:
		push_error("交互后重建地图快照失败: %s" % rebuilt.get("error", "unknown"))


func _selection_result(success: bool) -> Dictionary:
	return {
		"success": success,
		"target": selected_target.duplicate(true),
		"prompt": current_prompt(),
	}


func _execution_result(success: bool, reason: String, result: Dictionary) -> Dictionary:
	return {
		"success": success,
		"reason": reason,
		"result": result,
		"prompt": current_prompt(),
		"world_result": world_result,
	}


func _find_player_actor_id() -> int:
	for actor in simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = actor
		if actor_data.get("kind", "") == "player":
			return int(actor_data.get("actor_id", 0))
	return 0


func _failed_prompt(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
