extends RefCounted


func build(simulation: RefCounted, world_result: Dictionary, latest_queue_result: Dictionary, latest_pending_result: Dictionary) -> Dictionary:
	return {
		"crafting_stations": array_or_empty(dictionary_or_empty(world_result.get("map", {})).get("crafting_stations", [])).duplicate(true),
		"world_flags": dictionary_or_empty(simulation.world_flags if simulation != null else {}).duplicate(true),
		"nearby_tool_containers": nearby_tool_containers(simulation),
		"latest_crafting_queue_result": latest_queue_result.duplicate(true),
		"latest_pending_crafting_result": latest_pending_result.duplicate(true),
	}


func nearby_tool_containers(simulation: RefCounted) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if simulation == null:
		return output
	var actor: RefCounted = simulation.actor_registry.get_actor(1)
	if actor == null or actor.grid_position == null:
		return output
	var actor_grid: Dictionary = actor.grid_position.to_dictionary()
	var target_ids: Array = simulation.map_interaction_targets.keys()
	target_ids.sort()
	for target_id in target_ids:
		var target: Dictionary = dictionary_or_empty(simulation.map_interaction_targets.get(target_id, {}))
		if target.is_empty() or str(target.get("kind", "")) != "container":
			continue
		if not container_target_in_range(actor_grid, target, 1):
			continue
		var inventory: Array = container_inventory_for_crafting(simulation, str(target_id), target)
		if inventory.is_empty():
			continue
		output.append({
			"container_id": str(target_id),
			"display_name": str(target.get("display_name", target_id)),
			"inventory": inventory,
		})
	return output


func container_target_in_range(actor_grid: Dictionary, target: Dictionary, max_distance: int) -> bool:
	for cell in array_or_empty(target.get("cells", [])):
		if grid_distance(actor_grid, dictionary_or_empty(cell)) <= max_distance:
			return true
	return grid_distance(actor_grid, dictionary_or_empty(target.get("anchor", {}))) <= max_distance


func container_inventory_for_crafting(simulation: RefCounted, container_id: String, target: Dictionary) -> Array:
	if simulation != null and simulation.container_sessions.has(container_id):
		return array_or_empty(dictionary_or_empty(simulation.container_sessions[container_id]).get("inventory", [])).duplicate(true)
	if simulation != null and simulation.corpse_containers.has(container_id):
		return array_or_empty(dictionary_or_empty(simulation.corpse_containers[container_id]).get("inventory", [])).duplicate(true)
	return array_or_empty(target.get("container_inventory", [])).duplicate(true)


func grid_distance(left: Dictionary, right: Dictionary) -> int:
	return abs(int(left.get("x", 0)) - int(right.get("x", 0))) + abs(int(left.get("z", 0)) - int(right.get("z", 0))) + abs(int(left.get("y", 0)) - int(right.get("y", 0)))


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
