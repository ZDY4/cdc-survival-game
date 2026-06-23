extends RefCounted

## 玩家移动命令处理：移动预览、命令提交、逐步移动、pending 快照与取消。
## 无状态命令处理；pending_movement、actor AP/位置和事件仍由 simulation 持有。

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")


func preview_move(simulation: RefCounted, actor_id: int, target_position: Dictionary, topology: Dictionary) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	var goal: RefCounted = GridCoord.from_dictionary(target_position)
	var plan: Dictionary = simulation._pathfinder.find_path(actor.grid_position, goal, topology, simulation._occupied_actor_cells(actor.actor_id))
	var steps: int = int(plan.get("steps", 0))
	var cost: float = float(max(0, steps))
	var affordable_steps: int = min(steps, int(floor(actor.ap)))
	var preview: Dictionary = {
		"success": bool(plan.get("success", false)),
		"target_position": goal.to_dictionary(),
		"reason": str(plan.get("reason", "")),
		"reachable": bool(plan.get("success", false)),
		"steps": steps,
		"path": simulation._array_or_empty(plan.get("path", [])).duplicate(true),
		"pathfinding_time_ms": float(plan.get("pathfinding_time_ms", 0.0)),
		"visited_cell_count": int(plan.get("visited_cell_count", 0)),
		"ap_cost": cost,
		"ap_available": actor.ap,
		"ap_affordable": actor.ap >= cost,
		"affordable_steps": affordable_steps,
		"requires_pending": actor.ap < cost,
		"pending_steps": max(0, steps - affordable_steps),
	}
	simulation._copy_failure_context(plan, preview)
	return preview


func submit_move_command(simulation: RefCounted, actor: RefCounted, command: Dictionary) -> Dictionary:
	var topology: Dictionary = simulation._dictionary_or_empty(command.get("topology", {}))
	if topology.is_empty():
		return {"success": false, "reason": "move_topology_missing"}
	var target_position: Dictionary = simulation._dictionary_or_empty(command.get("target_position", command.get("grid", {})))
	var goal: RefCounted = GridCoord.from_dictionary(target_position)
	var movement_topology: Dictionary = simulation._topology_with_auto_open_doors(actor.actor_id, topology)
	var plan: Dictionary = simulation._pathfinder.find_path(actor.grid_position, goal, movement_topology, simulation._occupied_actor_cells(actor.actor_id))
	if not bool(plan.get("success", false)):
		return plan
	var steps: int = int(plan.get("steps", 0))
	var cost: float = float(max(0, steps))
	if actor.ap < cost:
		simulation.pending_movement = {
			"actor_id": actor.actor_id,
			"target_position": goal.to_dictionary(),
			"path": simulation._array_or_empty(plan.get("path", [])).duplicate(true),
			"required_ap": cost,
			"available_ap": actor.ap,
			"remaining_steps": steps,
		}
		simulation._emit("movement_queued", simulation.pending_movement.duplicate(true))
		var partial_move: Dictionary = simulation._advance_pending_movement(actor, topology)
		if not bool(partial_move.get("success", false)):
			return partial_move
		if int(partial_move.get("steps", 0)) > 0:
			partial_move["reason"] = "movement_pending"
			partial_move["pending_movement"] = simulation.pending_movement.duplicate(true)
			return partial_move
		return {
			"success": false,
			"reason": "ap_insufficient_movement_queued",
			"pending_movement": simulation.pending_movement.duplicate(true),
		}

	var from: Dictionary = actor.grid_position.to_dictionary()
	simulation._spend_ap(actor, cost, "move")
	actor.grid_position = goal
	for step in simulation._array_or_empty(plan.get("path", [])).slice(1):
		simulation._auto_open_door_for_step(actor.actor_id, simulation._dictionary_or_empty(step), topology)
		simulation._emit("movement_step", {
			"actor_id": actor.actor_id,
			"to": simulation._dictionary_or_empty(step),
		})
	simulation._emit("actor_moved", {
		"actor_id": actor.actor_id,
		"from": from,
		"to": goal.to_dictionary(),
		"steps": steps,
	})
	simulation.pending_movement.clear()
	return {
		"success": true,
		"kind": "move",
		"actor_id": actor.actor_id,
		"to": goal.to_dictionary(),
		"path": plan.get("path", []),
		"steps": steps,
		"ap_remaining": actor.ap,
	}


func begin_move(simulation: RefCounted, actor_id: int, target_position: Dictionary, topology: Dictionary, precomputed_plan: Dictionary = {}) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	if not actor.turn_open:
		return {"success": false, "reason": "turn_closed", "turn_state": simulation.turn_state.duplicate(true)}
	if topology.is_empty():
		return {"success": false, "reason": "move_topology_missing"}
	var goal: RefCounted = GridCoord.from_dictionary(target_position)
	var movement_topology: Dictionary = simulation._topology_with_auto_open_doors(actor.actor_id, topology)
	var plan: Dictionary = precomputed_plan.duplicate(true)
	if plan.is_empty():
		plan = simulation._pathfinder.find_path(actor.grid_position, goal, movement_topology, simulation._occupied_actor_cells(actor.actor_id))
	if not bool(plan.get("success", false)):
		return plan
	var path: Array = simulation._array_or_empty(plan.get("path", [])).duplicate(true)
	simulation.pending_movement = {
		"actor_id": actor.actor_id,
		"target_position": goal.to_dictionary(),
		"path": path,
		"required_ap": float(max(0, int(plan.get("steps", 0)))),
		"available_ap": actor.ap,
		"remaining_steps": int(plan.get("steps", 0)),
		"step_mode": true,
	}
	simulation._emit("movement_started", simulation.pending_movement.duplicate(true))
	return {
		"success": true,
		"kind": "move",
		"actor_id": actor.actor_id,
		"target_position": goal.to_dictionary(),
		"path": path,
		"steps": int(plan.get("steps", 0)),
		"ap": actor.ap,
		"pending_movement": simulation.pending_movement.duplicate(true),
	}


func step_move(simulation: RefCounted, actor_id: int, topology: Dictionary) -> Dictionary:
	var event_start_index: int = simulation.events.size()
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor"}
	if simulation.pending_movement.is_empty():
		return {
			"success": true,
			"kind": "move",
			"actor_id": actor_id,
			"completed": true,
			"reason": "no_pending_movement",
			"ap_remaining": actor.ap,
		}
	if int(simulation.pending_movement.get("actor_id", actor_id)) != actor_id:
		return {"success": false, "reason": "pending_movement_actor_mismatch", "pending_movement": simulation.pending_movement.duplicate(true)}
	if actor.ap < 1.0:
		simulation.pending_movement["available_ap"] = actor.ap
		return {
			"success": true,
			"kind": "move",
			"actor_id": actor_id,
			"completed": true,
			"pending": true,
			"reason": "ap_insufficient_movement_pending",
			"pending_movement": simulation.pending_movement.duplicate(true),
			"ap_remaining": actor.ap,
			"events": simulation._events_since(event_start_index),
		}
	var path: Array = simulation._array_or_empty(simulation.pending_movement.get("path", []))
	if path.size() <= 1:
		simulation.pending_movement.clear()
		simulation._emit("movement_completed", {
			"actor_id": actor_id,
			"to": actor.grid_position.to_dictionary(),
		})
		return {
			"success": true,
			"kind": "move",
			"actor_id": actor_id,
			"completed": true,
			"to": actor.grid_position.to_dictionary(),
			"ap_remaining": actor.ap,
			"events": simulation._events_since(event_start_index),
		}
	var from: Dictionary = actor.grid_position.to_dictionary()
	var next_grid: Dictionary = simulation._dictionary_or_empty(path[1]).duplicate(true)
	simulation._spend_ap(actor, 1.0, "move_step")
	simulation._auto_open_door_for_step(actor.actor_id, next_grid, topology)
	actor.grid_position = GridCoord.from_dictionary(next_grid)
	simulation._emit("movement_step", {
		"actor_id": actor.actor_id,
		"from": from.duplicate(true),
		"to": next_grid.duplicate(true),
		"step_index": int(simulation.pending_movement.get("step_index", 0)) + 1,
	})
	path.remove_at(0)
	simulation.pending_movement["path"] = path
	simulation.pending_movement["available_ap"] = actor.ap
	simulation.pending_movement["required_ap"] = float(max(0, path.size() - 1))
	simulation.pending_movement["remaining_steps"] = max(0, path.size() - 1)
	simulation.pending_movement["step_index"] = int(simulation.pending_movement.get("step_index", 0)) + 1
	if path.size() <= 1:
		simulation.pending_movement.clear()
		simulation._emit("actor_moved", {
			"actor_id": actor.actor_id,
			"from": from.duplicate(true),
			"to": next_grid.duplicate(true),
			"steps": 1,
			"step_mode": true,
		})
		simulation._emit("movement_completed", {
			"actor_id": actor.actor_id,
			"to": next_grid.duplicate(true),
		})
	return {
		"success": true,
		"kind": "move",
		"actor_id": actor.actor_id,
		"from": from,
		"to": next_grid,
		"completed": simulation.pending_movement.is_empty(),
		"pending": not simulation.pending_movement.is_empty(),
		"pending_movement": simulation.pending_movement.duplicate(true),
		"ap_remaining": actor.ap,
		"events": simulation._events_since(event_start_index),
	}


func pending_move_snapshot(simulation: RefCounted, actor_id: int) -> Dictionary:
	if simulation.pending_movement.is_empty() or int(simulation.pending_movement.get("actor_id", actor_id)) != actor_id:
		return {}
	return simulation.pending_movement.duplicate(true)


func cancel_move(simulation: RefCounted, actor_id: int, reason: String = "cancelled") -> Dictionary:
	if simulation.pending_movement.is_empty() or int(simulation.pending_movement.get("actor_id", actor_id)) != actor_id:
		return {"success": true, "had_pending": false, "reason": reason}
	var movement: Dictionary = simulation.pending_movement.duplicate(true)
	simulation.pending_movement.clear()
	simulation._emit("movement_cancelled", {
		"actor_id": actor_id,
		"reason": reason,
		"pending_movement": movement.duplicate(true),
	})
	return {
		"success": true,
		"had_pending": true,
		"reason": reason,
		"pending_movement": movement,
	}
