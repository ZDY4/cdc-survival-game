extends RefCounted

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")

const DEFAULT_ATTACK_AP := 2.0
const DEFAULT_INTERACTION_AP := 1.0


func resume_pending_for_actor(simulation: RefCounted, actor: RefCounted, topology: Dictionary) -> Dictionary:
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	if simulation.pending_movement.is_empty() and simulation.pending_interaction.is_empty() and simulation.pending_crafting.is_empty():
		return {"success": true, "resumed": false}
	if int(simulation.pending_movement.get("actor_id", actor.actor_id)) != actor.actor_id and int(simulation.pending_interaction.get("actor_id", actor.actor_id)) != actor.actor_id and int(simulation.pending_crafting.get("actor_id", actor.actor_id)) != actor.actor_id:
		return {"success": false, "reason": "pending_actor_mismatch"}

	var movement_result: Dictionary = {}
	if not simulation.pending_movement.is_empty():
		movement_result = advance_pending_movement(simulation, actor, topology)
		if not bool(movement_result.get("success", false)):
			return movement_result
		if not bool(movement_result.get("completed", false)):
			return {
				"success": true,
				"resumed": true,
				"kind": "pending_movement",
				"pending_movement": simulation.pending_movement.duplicate(true),
				"movement_result": movement_result,
			}
	if not simulation.pending_interaction.is_empty():
		return resume_pending_interaction(simulation, actor, topology, movement_result)
	if not simulation.pending_crafting.is_empty():
		return resume_pending_crafting(simulation, actor, topology, movement_result)
	return {
		"success": true,
		"resumed": not movement_result.is_empty(),
		"kind": "pending_movement_completed",
		"movement_result": movement_result,
	}


func resume_pending_crafting(simulation: RefCounted, actor: RefCounted, topology: Dictionary, movement_result: Dictionary = {}) -> Dictionary:
	return simulation._crafting_command_handler.resume_pending_crafting(simulation, simulation._progression_rules, actor, topology, movement_result)


func advance_pending_movement(simulation: RefCounted, actor: RefCounted, topology: Dictionary) -> Dictionary:
	if simulation.pending_movement.is_empty():
		return {"success": true, "completed": true, "steps": 0}
	if topology.is_empty():
		return {"success": false, "reason": "pending_move_topology_missing"}
	var goal: RefCounted = GridCoord.from_dictionary(_dictionary_or_empty(simulation.pending_movement.get("target_position", {})))
	var movement_topology: Dictionary = simulation._topology_with_auto_open_doors(actor.actor_id, topology)
	var plan: Dictionary = simulation._pathfinder.find_path(actor.grid_position, goal, movement_topology, simulation._occupied_actor_cells(actor.actor_id))
	if not bool(plan.get("success", false)):
		return {
			"success": false,
			"reason": plan.get("reason", "pending_move_path_unavailable"),
			"pending_movement": simulation.pending_movement.duplicate(true),
			"path_result": plan,
		}
	var path: Array = _array_or_empty(plan.get("path", []))
	var total_steps: int = int(plan.get("steps", 0))
	if total_steps <= 0:
		simulation.pending_movement.clear()
		return {"success": true, "completed": true, "steps": 0, "to": actor.grid_position.to_dictionary(), "path": path}
	var affordable_steps: int = min(total_steps, int(floor(actor.ap)))
	if affordable_steps <= 0:
		simulation.pending_movement["remaining_steps"] = total_steps
		simulation.pending_movement["required_ap"] = float(total_steps)
		simulation.pending_movement["available_ap"] = actor.ap
		return {
			"success": true,
			"completed": false,
			"reason": "ap_insufficient_movement_queued",
			"steps": 0,
			"pending_movement": simulation.pending_movement.duplicate(true),
		}
	var destination: Dictionary = _dictionary_or_empty(path[affordable_steps])
	var from: Dictionary = actor.grid_position.to_dictionary()
	simulation._spend_ap(actor, float(affordable_steps), "pending_move")
	actor.grid_position = GridCoord.from_dictionary(destination)
	for step in path.slice(1, affordable_steps + 1):
		simulation._auto_open_door_for_step(actor.actor_id, _dictionary_or_empty(step), topology)
		simulation.emit_event("movement_step", {
			"actor_id": actor.actor_id,
			"to": _dictionary_or_empty(step),
		})
	simulation.emit_event("actor_moved", {
		"actor_id": actor.actor_id,
		"from": from,
		"to": destination,
		"steps": affordable_steps,
	})
	var completed := affordable_steps >= total_steps
	if completed:
		simulation.pending_movement.clear()
	else:
		simulation.pending_movement["target_position"] = goal.to_dictionary()
		simulation.pending_movement["path"] = path.slice(affordable_steps)
		simulation.pending_movement["required_ap"] = float(total_steps - affordable_steps)
		simulation.pending_movement["available_ap"] = actor.ap
		simulation.pending_movement["remaining_steps"] = max(0, total_steps - affordable_steps)
		simulation.emit_event("movement_queued", simulation.pending_movement.duplicate(true))
	return {
		"success": true,
		"completed": completed,
		"kind": "move",
		"actor_id": actor.actor_id,
		"from": from,
		"to": destination,
		"path": path,
		"steps": affordable_steps,
		"remaining_steps": max(0, total_steps - affordable_steps),
		"ap_remaining": actor.ap,
	}


func resume_pending_interaction(simulation: RefCounted, actor: RefCounted, topology: Dictionary, movement_result: Dictionary = {}) -> Dictionary:
	if simulation.pending_interaction.is_empty():
		return {
			"success": true,
			"resumed": false,
			"approach_result": movement_result,
		}
	var queued: Dictionary = simulation.pending_interaction.duplicate(true)
	var prompt: Dictionary = simulation.query_interaction_options(actor.actor_id, _dictionary_or_empty(queued.get("target", {})))
	var option_id: String = str(queued.get("option_id", ""))
	var option: Dictionary = simulation._interaction_option(prompt, option_id)
	var cost: float = DEFAULT_ATTACK_AP if str(option.get("kind", "")) == "attack" else DEFAULT_INTERACTION_AP
	if actor.ap < cost:
		simulation.pending_interaction = queued
		simulation.pending_interaction["required_ap"] = cost
		simulation.pending_interaction["available_ap"] = actor.ap
		simulation.emit_event("interaction_queued", simulation.pending_interaction.duplicate(true))
		return {
			"success": true,
			"resumed": true,
			"kind": "pending_interaction",
			"reason": "ap_insufficient_interaction_queued",
			"approach_result": movement_result,
			"pending_interaction": simulation.pending_interaction.duplicate(true),
			"prompt": prompt,
		}
	simulation.pending_interaction.clear()
	var resumed: Dictionary = simulation._submit_interact_command(actor, {
		"kind": "interact",
		"actor_id": actor.actor_id,
		"target": _dictionary_or_empty(queued.get("target", {})),
		"option_id": option_id,
		"topology": topology,
	})
	resumed["approach_result"] = movement_result
	resumed["auto_resumed_interaction"] = true
	resumed["resumed_pending_interaction"] = queued
	simulation.emit_event("interaction_resumed", {
		"actor_id": actor.actor_id,
		"target": _dictionary_or_empty(queued.get("target", {})),
		"option_id": option_id,
		"option_kind": str(option.get("kind", "")),
		"success": bool(resumed.get("success", false)),
		"reason": str(resumed.get("reason", "ok" if bool(resumed.get("success", false)) else "unknown")),
		"result_kind": str(resumed.get("kind", "")),
	})
	return resumed


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
