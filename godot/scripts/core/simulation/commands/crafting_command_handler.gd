extends RefCounted

const CraftingService = preload("res://scripts/core/simulation/services/crafting_service.gd")

var _crafting_service := CraftingService.new()


func submit_craft(simulation: RefCounted, progression_rules: RefCounted, actor: RefCounted, command: Dictionary) -> Dictionary:
	var count: int = max(1, int(command.get("count", 1)))
	var recipes: Dictionary = _dictionary_or_empty(command.get("recipe_library", {}))
	var recipe_id := str(command.get("recipe_id", ""))
	var crafting_context: Dictionary = _dictionary_or_empty(command.get("crafting_context", {}))
	var validation: Dictionary = _crafting_service.validate_recipe(simulation, progression_rules, actor.actor_id, recipe_id, recipes, crafting_context)
	if not bool(validation.get("success", false)):
		return validation
	var total_cost: float = simulation._craft_command_ap_cost(recipe_id, recipes, count, command)
	if actor.ap < total_cost:
		var available_ap: float = max(0.0, actor.ap)
		if available_ap > 0.0:
			simulation._spend_ap(actor, available_ap, "craft_progress:%s" % recipe_id)
		simulation.pending_crafting = _pending_crafting_payload(actor, recipe_id, count, recipes, crafting_context, command, total_cost, available_ap, 0.0)
		simulation.emit_event("crafting_queued", simulation.pending_crafting.duplicate(true))
		return {
			"success": true,
			"kind": "pending_crafting",
			"reason": "ap_insufficient_craft_queued",
			"recipe_id": recipe_id,
			"count": count,
			"required_ap": total_cost,
			"available_ap": available_ap,
			"spent_ap": available_ap,
			"remaining_ap": float(simulation.pending_crafting.get("remaining_ap", total_cost)),
			"pending_crafting": simulation.pending_crafting.duplicate(true),
		}
	var result: Dictionary = craft_batch(simulation, progression_rules, actor.actor_id, recipe_id, count, recipes, crafting_context)
	if bool(result.get("success", false)) or bool(result.get("partial_success", false)):
		var completed_count: int = max(1, int(result.get("count", result.get("completed_count", 1))))
		var spent_cost: float = total_cost if bool(result.get("success", false)) else simulation._craft_command_ap_cost(recipe_id, recipes, completed_count, command)
		simulation._spend_ap(actor, spent_cost, "craft:%s" % recipe_id)
		result["ap_cost"] = spent_cost
		result["ap_remaining"] = actor.ap
		result["craft_time"] = simulation._recipe_craft_time(recipe_id, recipes) * float(completed_count)
	return result


func resume_pending_crafting(simulation: RefCounted, progression_rules: RefCounted, actor: RefCounted, _topology: Dictionary, movement_result: Dictionary = {}) -> Dictionary:
	if simulation.pending_crafting.is_empty():
		return {
			"success": true,
			"resumed": false,
			"movement_result": movement_result,
		}
	var queued: Dictionary = simulation.pending_crafting.duplicate(true)
	var recipe_id := str(queued.get("recipe_id", ""))
	var count: int = max(1, int(queued.get("count", 1)))
	var recipes: Dictionary = _dictionary_or_empty(queued.get("recipe_library", {}))
	var crafting_context: Dictionary = _dictionary_or_empty(queued.get("crafting_context", {}))
	var validation: Dictionary = _crafting_service.validate_recipe(simulation, progression_rules, actor.actor_id, recipe_id, recipes, crafting_context)
	if not bool(validation.get("success", false)):
		validation["pending_crafting"] = queued.duplicate(true)
		return validation
	var command: Dictionary = _dictionary_or_empty(queued.get("command", {}))
	var required_ap: float = max(0.0, float(queued.get("required_ap", simulation._craft_command_ap_cost(recipe_id, recipes, count, command))))
	var progress_ap: float = clampf(float(queued.get("progress_ap", 0.0)), 0.0, required_ap)
	var remaining_ap: float = max(0.0, required_ap - progress_ap)
	if remaining_ap > 0.0 and actor.ap > 0.0:
		var spent_ap: float = min(actor.ap, remaining_ap)
		simulation._spend_ap(actor, spent_ap, "pending_craft:%s" % recipe_id)
		progress_ap += spent_ap
		remaining_ap = max(0.0, required_ap - progress_ap)
	if remaining_ap > 0.0:
		simulation.pending_crafting = _pending_crafting_payload(actor, recipe_id, count, recipes, crafting_context, command, required_ap, 0.0, progress_ap)
		simulation.emit_event("crafting_queued", simulation.pending_crafting.duplicate(true))
		return {
			"success": true,
			"resumed": true,
			"completed": false,
			"kind": "pending_crafting",
			"reason": "ap_insufficient_craft_queued",
			"movement_result": movement_result,
			"pending_crafting": simulation.pending_crafting.duplicate(true),
		}
	simulation.pending_crafting.clear()
	var result: Dictionary = craft_batch(simulation, progression_rules, actor.actor_id, recipe_id, count, recipes, crafting_context)
	result["resumed"] = true
	result["auto_resumed_crafting"] = true
	result["resumed_pending_crafting"] = queued
	result["movement_result"] = movement_result
	result["ap_cost"] = required_ap
	result["ap_remaining"] = actor.ap
	if not result.has("craft_time"):
		result["craft_time"] = simulation._recipe_craft_time(recipe_id, recipes) * float(max(1, int(result.get("count", count))))
	simulation.emit_event("crafting_resumed", {
		"actor_id": actor.actor_id,
		"recipe_id": recipe_id,
		"count": count,
		"required_ap": required_ap,
		"progress_ap": progress_ap,
		"success": bool(result.get("success", false)),
	})
	return result


func craft_batch(simulation: RefCounted, progression_rules: RefCounted, actor_id: int, recipe_id: String, count: int, recipes: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	if count <= 1:
		return _crafting_service.craft_recipe(simulation, progression_rules, actor_id, recipe_id, recipes, crafting_context)
	var completed := 0
	var output_item_id := ""
	var output_count := 0
	var consumed_tools: Array[Dictionary] = []
	var last_result: Dictionary = {}
	for _index in range(count):
		last_result = _crafting_service.craft_recipe(simulation, progression_rules, actor_id, recipe_id, recipes, crafting_context)
		if not bool(last_result.get("success", false)):
			if completed > 0:
				last_result["partial_success"] = true
				last_result["completed_count"] = completed
				last_result["requested_count"] = count
				last_result["output_item_id"] = output_item_id
				last_result["output_count"] = output_count
				last_result["consumed_tools"] = consumed_tools.duplicate(true)
			return last_result
		completed += 1
		output_item_id = str(last_result.get("output_item_id", output_item_id))
		output_count += int(last_result.get("output_count", 0))
		for consumed_tool in _array_or_empty(last_result.get("consumed_tools", [])):
			_merge_consumed_tool(consumed_tools, _dictionary_or_empty(consumed_tool))
	return {
		"success": true,
		"recipe_id": recipe_id,
		"count": completed,
		"requested_count": count,
		"output_item_id": output_item_id,
		"output_count": output_count,
		"consumed_tools": consumed_tools,
	}


func submit_deconstruct(simulation: RefCounted, actor: RefCounted, command: Dictionary, items: Dictionary) -> Dictionary:
	var item_id: String = str(command.get("item_id", ""))
	var count: int = max(1, int(command.get("count", 1)))
	var crafting_context: Dictionary = _dictionary_or_empty(command.get("crafting_context", {}))
	var requirements: Dictionary = _crafting_service.deconstruct_requirement_check(actor, item_id, items, crafting_context)
	if not bool(requirements.get("success", false)):
		return requirements
	var cost: float = _crafting_service.deconstruct_ap_cost(item_id, items, count, command)
	if actor.ap < cost:
		return {
			"success": false,
			"reason": "ap_insufficient_deconstruct",
			"item_id": _crafting_service.normalize_item_id(item_id),
			"count": count,
			"required_ap": cost,
			"available_ap": actor.ap,
		}
	var tool_source_check: Dictionary = _crafting_service.deconstruct_tool_consumption_sources_available(simulation, actor, _array_or_empty(requirements.get("tool_consumption", [])), items)
	if not bool(tool_source_check.get("success", false)):
		return tool_source_check
	var result: Dictionary = _crafting_service.deconstruct_actor_item(simulation, actor.actor_id, item_id, count, items)
	if bool(result.get("success", false)):
		var consumed_tools: Array[Dictionary] = _crafting_service.consume_deconstruct_tools(simulation, actor, _array_or_empty(requirements.get("tool_consumption", [])))
		simulation._spend_ap(actor, cost, "deconstruct:%s" % _crafting_service.normalize_item_id(item_id))
		result["ap_cost"] = cost
		result["ap_remaining"] = actor.ap
		result["consumed_tools"] = consumed_tools
		simulation._attach_consumed_tools_to_last_event("item_deconstructed", consumed_tools)
	return result


func _pending_crafting_payload(actor: RefCounted, recipe_id: String, count: int, recipes: Dictionary, crafting_context: Dictionary, command: Dictionary, required_ap: float, spent_ap: float, previous_progress: float) -> Dictionary:
	return {
		"kind": "pending_crafting",
		"actor_id": actor.actor_id if actor != null else 0,
		"recipe_id": recipe_id,
		"count": max(1, count),
		"recipe_library": recipes.duplicate(true),
		"crafting_context": crafting_context.duplicate(true),
		"command": command.duplicate(true),
		"required_ap": max(0.0, required_ap),
		"progress_ap": max(0.0, previous_progress + spent_ap),
		"remaining_ap": max(0.0, required_ap - previous_progress - spent_ap),
		"available_ap": actor.ap if actor != null else 0.0,
	}


func _merge_consumed_tool(consumed_tools: Array[Dictionary], consumed_tool: Dictionary) -> void:
	var item_id := str(consumed_tool.get("item_id", ""))
	if item_id.is_empty():
		return
	for index in range(consumed_tools.size()):
		var existing: Dictionary = _dictionary_or_empty(consumed_tools[index])
		if str(existing.get("item_id", "")) != item_id:
			continue
		existing["count"] = int(existing.get("count", 0)) + int(consumed_tool.get("count", 0))
		existing["inventory_after"] = int(consumed_tool.get("inventory_after", existing.get("inventory_after", 0)))
		consumed_tools[index] = existing
		return
	consumed_tools.append(consumed_tool.duplicate(true))


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
