extends RefCounted

const CRAFTING_QUEUE_ADVANCE_LIMIT := 16

var host


func configure(p_host) -> void:
	host = p_host


func craft_player_recipe(recipe_id: String, count: int = 1) -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var blocked: Dictionary = dictionary_or_empty(host.call("_player_command_rejection", "craft"))
	if not blocked.is_empty():
		return blocked
	var operation: Dictionary = dictionary_or_empty(host.crafting_action_controller.call("craft_recipe", host.simulation, recipe_id, count, host.registry.get_library("recipes"), crafting_context(), dictionary_or_empty(host.world_result.get("map", {})), host.crafting_feedback_controller, Callable(host, "_submit_craft_via_turn_action_runner")))
	return apply_crafting_action_operation(operation)


func confirm_crafting_queue(entries: Array) -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var blocked: Dictionary = dictionary_or_empty(host.call("_player_command_rejection", "crafting_queue"))
	if not blocked.is_empty():
		return blocked
	var operation: Dictionary = dictionary_or_empty(host.crafting_action_controller.call("confirm_queue", host.simulation, entries, host.registry.get_library("recipes"), crafting_context(), dictionary_or_empty(host.world_result.get("map", {})), host.crafting_feedback_controller, CRAFTING_QUEUE_ADVANCE_LIMIT, Callable(host, "_submit_craft_via_turn_action_runner")))
	return apply_crafting_action_operation(operation)


func advance_crafting_queue(reason: String) -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	return dictionary_or_empty(host.crafting_action_controller.call("advance_queue", host.simulation, reason, host.registry.get_library("recipes"), crafting_context(), dictionary_or_empty(host.world_result.get("map", {})), CRAFTING_QUEUE_ADVANCE_LIMIT, Callable(host, "_submit_craft_via_turn_action_runner")))


func submit_crafting_queue_entry(recipe_id: String, count: int) -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	return dictionary_or_empty(host.crafting_action_controller.call("_submit_craft", host.simulation, recipe_id, count, host.registry.get_library("recipes"), crafting_context(), dictionary_or_empty(host.world_result.get("map", {})), true, Callable(host, "_submit_craft_via_turn_action_runner")))


func continue_crafting_queue_after_wait(result: Dictionary, wait_runner_snapshot: Dictionary = {}) -> Dictionary:
	var continuation: Dictionary = dictionary_or_empty(host.crafting_action_controller.call("continue_queue_after_wait", host.simulation, result, host.registry.get_library("recipes"), crafting_context(), dictionary_or_empty(host.world_result.get("map", {})), host.crafting_feedback_controller, CRAFTING_QUEUE_ADVANCE_LIMIT, Callable(host, "_submit_craft_via_turn_action_runner")))
	if bool(continuation.get("continued", false)):
		continuation["refresh"] = ["inventory", "crafting", "skills"]
		continuation["wait_runner_snapshot"] = wait_runner_snapshot.duplicate(true)
		var action_kind := str(wait_runner_snapshot.get("action_kind", ""))
		host.latest_action_chain = {
			"kind": "craft_to_crafting_queue" if action_kind == "craft" else "wait_to_crafting_queue",
			"wait_result": result.duplicate(true),
			"wait_runner": wait_runner_snapshot.duplicate(true),
			"source_action_kind": action_kind,
			"queue_result": dictionary_or_empty(continuation.get("queue_result", {})).duplicate(true),
		}
	return continuation


func submit_craft_via_turn_action_runner(recipe_id: String, count: int, recipe_library: Dictionary, crafting_context_value: Dictionary, topology: Dictionary, queue_active: bool) -> Dictionary:
	var command := {
		"kind": "craft",
		"actor_id": int(host.call("_player_actor_id")),
		"recipe_id": recipe_id,
		"count": max(1, count),
		"recipe_library": recipe_library,
		"crafting_context": crafting_context_value.duplicate(true),
		"topology": topology.duplicate(true),
	}
	if queue_active:
		command["crafting_queue_active"] = true
	return dictionary_or_empty(host.request_player_craft(command, {"crafting_queue_active": queue_active}))


func wait_result_resumed_active_crafting_queue(result: Dictionary) -> bool:
	return bool(host.crafting_action_controller.call("wait_result_resumed_active_crafting_queue", result))


func completed_crafting_count_from_queue_result(result: Dictionary) -> int:
	return int(host.crafting_action_controller.call("completed_crafting_count_from_queue_result", host.simulation, result))


func update_crafting_queue(entries: Array) -> Dictionary:
	return dictionary_or_empty(host.crafting_action_controller.call("update_queue", host.simulation, entries, host.crafting_feedback_controller))


func crafting_queue_snapshot() -> Dictionary:
	return dictionary_or_empty(host.crafting_action_controller.call("queue_snapshot", host.simulation, host.crafting_feedback_controller))


func normalized_crafting_queue(entries: Array) -> Array[Dictionary]:
	return array_of_dictionaries(host.crafting_action_controller.call("normalize_queue", entries, host.crafting_feedback_controller))


func crafting_queue_total_count(entries: Array) -> int:
	return int(host.crafting_action_controller.call("queue_total_count", entries, host.crafting_feedback_controller))


func cancel_pending_crafting(reason: String = "crafting_ui") -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var operation: Dictionary = dictionary_or_empty(host.crafting_action_controller.call("cancel_pending", host.simulation, reason, dictionary_or_empty(host.world_result.get("map", {})), host.crafting_feedback_controller))
	return apply_crafting_action_operation(operation)


func set_latest_crafting_queue_result(result: Dictionary, trigger: String) -> void:
	host.crafting_action_controller.call("record_queue_result", host.crafting_feedback_controller, result, trigger, host.simulation)


func apply_crafting_action_operation(operation: Dictionary) -> Dictionary:
	var result: Dictionary = dictionary_or_empty(operation.get("result", {}))
	host.call("_refresh_operation_panels", array_or_empty(operation.get("refresh", [])))
	return result


func crafting_context() -> Dictionary:
	return dictionary_or_empty(host.crafting_context_builder.call("build", host.simulation, host.world_result, host.latest_crafting_queue_result, host.latest_pending_crafting_result))


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func array_of_dictionaries(value: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for entry in array_or_empty(value):
		output.append(dictionary_or_empty(entry).duplicate(true))
	return output
