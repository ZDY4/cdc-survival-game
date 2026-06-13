extends RefCounted


func craft_recipe(simulation: RefCounted, recipe_id: String, count: int, recipe_library: Dictionary, crafting_context: Dictionary, topology: Dictionary, feedback_controller: RefCounted, submit_craft_action: Callable = Callable()) -> Dictionary:
	if simulation == null:
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	var result: Dictionary = _submit_craft(simulation, recipe_id, count, recipe_library, crafting_context, topology, false, submit_craft_action)
	if feedback_controller != null and feedback_controller.has_method("clear_pending_result"):
		feedback_controller.call("clear_pending_result")
	return _operation_result(result, ["inventory", "crafting", "skills"])


func confirm_queue(simulation: RefCounted, entries: Array, recipe_library: Dictionary, crafting_context: Dictionary, topology: Dictionary, feedback_controller: RefCounted, advance_limit_base: int, submit_craft_action: Callable = Callable()) -> Dictionary:
	if simulation == null:
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	simulation.crafting_queue = _normalized_queue(entries, feedback_controller)
	var queue_result: Dictionary = advance_queue(simulation, "confirm", recipe_library, crafting_context, topology, advance_limit_base, submit_craft_action)
	_record_queue_result(feedback_controller, queue_result, "confirm", simulation)
	if feedback_controller != null and feedback_controller.has_method("clear_pending_result"):
		feedback_controller.call("clear_pending_result")
	return _operation_result(queue_result, ["inventory", "crafting", "skills"])


func continue_queue_after_wait(simulation: RefCounted, wait_result: Dictionary, recipe_library: Dictionary, crafting_context: Dictionary, topology: Dictionary, feedback_controller: RefCounted, advance_limit_base: int, submit_craft_action: Callable = Callable()) -> Dictionary:
	if simulation == null or simulation.crafting_queue.is_empty():
		return {"continued": false, "reason": "queue_empty"}
	if not dictionary_or_empty(simulation.pending_crafting).is_empty():
		return {"continued": false, "reason": "pending_active"}
	if not wait_result_resumed_active_crafting_queue(wait_result):
		return {"continued": false, "reason": "wait_result_not_crafting_queue"}
	var queue_result: Dictionary = advance_queue(simulation, "pending_completed", recipe_library, crafting_context, topology, advance_limit_base, submit_craft_action)
	wait_result["crafting_queue_result"] = queue_result
	_record_queue_result(feedback_controller, queue_result, "pending_completed", simulation)
	return {"continued": true, "queue_result": queue_result}


func cancel_pending(simulation: RefCounted, reason: String, topology: Dictionary, feedback_controller: RefCounted) -> Dictionary:
	if simulation == null:
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	var result: Dictionary = dictionary_or_empty(simulation.cancel_pending(reason, false, topology.duplicate(true)))
	if feedback_controller != null:
		if bool(result.get("success", false)) and bool(result.get("had_pending", false)) and feedback_controller.has_method("record_pending_cancelled"):
			feedback_controller.call("record_pending_cancelled", result, reason, simulation.crafting_queue)
		elif bool(result.get("success", false)) and feedback_controller.has_method("clear_pending_result"):
			feedback_controller.call("clear_pending_result")
	return _operation_result(result, ["inventory", "crafting", "skills"])


func update_queue(simulation: RefCounted, entries: Array, feedback_controller: RefCounted) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	simulation.crafting_queue = _normalized_queue(entries, feedback_controller)
	if simulation.crafting_queue.is_empty() and feedback_controller != null and feedback_controller.has_method("record_queue_cleared"):
		feedback_controller.call("record_queue_cleared")
	return {
		"success": true,
		"entry_count": simulation.crafting_queue.size(),
		"crafting_queue": simulation.crafting_queue.duplicate(true),
	}


func queue_snapshot(simulation: RefCounted, feedback_controller: RefCounted) -> Dictionary:
	if simulation == null:
		return {"entries": [], "entry_count": 0, "total_count": 0}
	if feedback_controller != null and feedback_controller.has_method("queue_snapshot"):
		return dictionary_or_empty(feedback_controller.call("queue_snapshot", simulation.crafting_queue))
	return {"entries": simulation.crafting_queue.duplicate(true), "entry_count": simulation.crafting_queue.size(), "total_count": queue_total_count(simulation.crafting_queue, feedback_controller)}


func normalize_queue(entries: Array, feedback_controller: RefCounted) -> Array[Dictionary]:
	return _normalized_queue(entries, feedback_controller)


func queue_total_count(entries: Array, feedback_controller: RefCounted) -> int:
	if feedback_controller != null and feedback_controller.has_method("queue_total_count"):
		return int(feedback_controller.call("queue_total_count", entries))
	var total := 0
	for entry in entries:
		total += max(1, int(dictionary_or_empty(entry).get("count", 1)))
	return total


func record_queue_result(feedback_controller: RefCounted, result: Dictionary, trigger: String, simulation: RefCounted) -> void:
	_record_queue_result(feedback_controller, result, trigger, simulation)


func advance_queue(simulation: RefCounted, reason: String, recipe_library: Dictionary, crafting_context: Dictionary, topology: Dictionary, advance_limit_base: int, submit_craft_action: Callable = Callable()) -> Dictionary:
	var results: Array[Dictionary] = []
	var completed_count: int = 0
	var failed: Array[Dictionary] = []
	var started_pending := false
	var runner_active := false
	var advanced_entry_count := 0
	if dictionary_or_empty(simulation.pending_crafting).is_empty() and not simulation.crafting_queue.is_empty():
		var entry_data: Dictionary = dictionary_or_empty(simulation.crafting_queue[0])
		var recipe_id := str(entry_data.get("recipe_id", "")).strip_edges()
		var count: int = max(1, int(entry_data.get("count", 1)))
		if recipe_id.is_empty():
			var missing_recipe_id_result := {"success": false, "reason": "recipe_id_missing", "entry": entry_data.duplicate(true)}
			results.append(missing_recipe_id_result)
			failed.append(missing_recipe_id_result)
		else:
			var result: Dictionary = _submit_craft(simulation, recipe_id, count, recipe_library, crafting_context, topology, true, submit_craft_action)
			result["queued_recipe_id"] = recipe_id
			result["queued_count"] = count
			results.append(result)
			advanced_entry_count = 1
			var completed_entry_count: int = completed_crafting_count_from_queue_result(simulation, result)
			completed_count += completed_entry_count
			runner_active = bool(result.get("runner_active_after", false))
			if not dictionary_or_empty(simulation.pending_crafting).is_empty():
				simulation.crafting_queue.remove_at(0)
				started_pending = true
			elif bool(result.get("success", false)):
				simulation.crafting_queue.remove_at(0)
			else:
				if bool(result.get("partial_success", false)) and completed_entry_count > 0:
					var remaining_count: int = max(0, count - completed_entry_count)
					if remaining_count > 0:
						var remaining_entry: Dictionary = entry_data.duplicate(true)
						remaining_entry["count"] = remaining_count
						simulation.crafting_queue[0] = remaining_entry
					else:
						simulation.crafting_queue.remove_at(0)
				failed.append(result.duplicate(true))
	return {
		"success": failed.is_empty(),
		"partial_success": completed_count > 0 and not failed.is_empty(),
		"completed_count": completed_count,
		"failed_count": failed.size(),
		"results": results,
		"failed": failed,
		"pending": not dictionary_or_empty(simulation.pending_crafting).is_empty(),
		"runner_active": runner_active,
		"started_pending": started_pending,
		"advanced_entry_count": advanced_entry_count,
		"queue_step_limited": advanced_entry_count > 0 and not simulation.crafting_queue.is_empty() and dictionary_or_empty(simulation.pending_crafting).is_empty() and failed.is_empty(),
		"advance_limit_base": advance_limit_base,
		"remaining_queue": simulation.crafting_queue.duplicate(true),
		"remaining_queue_count": simulation.crafting_queue.size(),
		"queue_empty": simulation.crafting_queue.is_empty(),
		"reason": reason,
	}


func wait_result_resumed_active_crafting_queue(result: Dictionary) -> bool:
	var pending_result: Dictionary = dictionary_or_empty(result.get("pending_result", {}))
	if pending_result.is_empty():
		return false
	var resumed: Dictionary = dictionary_or_empty(pending_result.get("resumed_pending_crafting", {}))
	if resumed.is_empty():
		return false
	var command: Dictionary = dictionary_or_empty(resumed.get("command", {}))
	return bool(command.get("crafting_queue_active", false))


func completed_crafting_count_from_queue_result(simulation: RefCounted, result: Dictionary) -> int:
	if simulation != null and not dictionary_or_empty(simulation.pending_crafting).is_empty():
		return 0
	if bool(result.get("partial_success", false)):
		return max(0, int(result.get("completed_count", 0)))
	if not bool(result.get("success", false)):
		return 0
	if result.has("completed_count"):
		return max(0, int(result.get("completed_count", 0)))
	return max(1, int(result.get("count", result.get("queued_count", 1))))


func _submit_craft(simulation: RefCounted, recipe_id: String, count: int, recipe_library: Dictionary, crafting_context: Dictionary, topology: Dictionary, queue_active: bool, submit_craft_action: Callable = Callable()) -> Dictionary:
	if submit_craft_action.is_valid():
		return dictionary_or_empty(submit_craft_action.call(recipe_id, count, recipe_library, crafting_context, topology, queue_active))
	var command := {
		"kind": "craft",
		"actor_id": 1,
		"recipe_id": recipe_id,
		"count": max(1, count),
		"recipe_library": recipe_library,
		"crafting_context": crafting_context.duplicate(true),
		"topology": topology.duplicate(true),
	}
	if queue_active:
		command["crafting_queue_active"] = true
	return dictionary_or_empty(simulation.submit_player_command(command))


func _normalized_queue(entries: Array, feedback_controller: RefCounted) -> Array[Dictionary]:
	if feedback_controller != null and feedback_controller.has_method("normalize_queue"):
		var normalized: Array[Dictionary] = []
		for entry in array_or_empty(feedback_controller.call("normalize_queue", entries)):
			normalized.append(dictionary_or_empty(entry))
		return normalized
	var output: Array[Dictionary] = []
	for entry in array_or_empty(entries):
		var data: Dictionary = dictionary_or_empty(entry)
		var recipe_id := str(data.get("recipe_id", "")).strip_edges()
		if recipe_id.is_empty():
			continue
		output.append({"recipe_id": recipe_id, "count": max(1, int(data.get("count", 1)))})
	return output


func _record_queue_result(feedback_controller: RefCounted, result: Dictionary, trigger: String, simulation: RefCounted) -> void:
	if feedback_controller != null and feedback_controller.has_method("record_queue_result"):
		feedback_controller.call("record_queue_result", result, trigger, dictionary_or_empty(simulation.pending_crafting) if simulation != null else {})


func _operation_result(result: Dictionary, refresh_panels: Array) -> Dictionary:
	return {
		"result": result.duplicate(true),
		"refresh": refresh_panels.duplicate(true),
	}


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
