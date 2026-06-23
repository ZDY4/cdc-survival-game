extends RefCounted

## 玩家交互命令处理：交互选项执行、接近后交互和 runner 交互起始。
## 无状态命令处理；pending_movement、pending_interaction、AP 和事件仍由 simulation 持有。

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")


func begin_interaction_for_runner(simulation: RefCounted, actor_id: int, target: Dictionary, option_id: String, topology: Dictionary) -> Dictionary:
	var event_start_index: int = simulation.events.size()
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "actor_id": actor_id}
	if not actor.turn_open:
		return {"success": false, "reason": "turn_closed", "actor_id": actor_id, "turn_state": simulation.turn_state.duplicate(true)}
	var prompt: Dictionary = simulation.query_interaction_options(actor_id, target)
	simulation.interaction_menu = prompt.duplicate(true)
	if not bool(prompt.get("ok", false)):
		return {"success": false, "reason": prompt.get("reason", "interaction_unavailable"), "prompt": prompt}
	var resolved_option_id: String = option_id
	if resolved_option_id.is_empty():
		resolved_option_id = str(prompt.get("primary_option_id", ""))
	var option: Dictionary = interaction_option(simulation, prompt, resolved_option_id)
	if option.is_empty():
		return {"success": false, "reason": "interaction_option_unavailable", "prompt": prompt, "option_id": resolved_option_id}
	if str(option.get("kind", "")) == "attack":
		return {
			"success": true,
			"kind": "attack_required",
			"actor_id": actor_id,
			"target_actor_id": int(option.get("target_actor_id", 0)),
			"target": target.duplicate(true),
			"option_id": resolved_option_id,
			"prompt": prompt,
			"turn_state": simulation.turn_state.duplicate(true),
			"events": simulation._events_since(event_start_index),
		}
	if not actor_can_reach_interaction(simulation, actor, prompt):
		return begin_interaction_approach_for_runner(simulation, actor, target, resolved_option_id, prompt, topology, event_start_index)
	var result: Dictionary = submit_interact_command(simulation, actor, {
		"kind": "interact",
		"actor_id": actor_id,
		"target": target,
		"option_id": resolved_option_id,
		"topology": topology,
	})
	result["actor_id"] = actor_id
	result["target"] = target.duplicate(true)
	result["option_id"] = resolved_option_id
	result["prompt"] = simulation._dictionary_or_empty(result.get("prompt", prompt)).duplicate(true)
	result["interaction_completed"] = bool(result.get("success", false))
	result["pending_movement"] = simulation.pending_movement.duplicate(true)
	result["pending_interaction"] = simulation.pending_interaction.duplicate(true)
	result["turn_state"] = simulation.turn_state.duplicate(true)
	result["events"] = simulation._events_since(event_start_index)
	return result


func submit_interact_command(simulation: RefCounted, actor: RefCounted, command: Dictionary) -> Dictionary:
	var target: Dictionary = simulation._dictionary_or_empty(command.get("target", {}))
	var prompt: Dictionary = simulation.query_interaction_options(actor.actor_id, target)
	simulation.interaction_menu = prompt.duplicate(true)
	if not bool(prompt.get("ok", false)):
		return {"success": false, "reason": prompt.get("reason", "interaction_unavailable"), "prompt": prompt}
	var option_id: String = str(command.get("option_id", prompt.get("primary_option_id", "")))
	var option: Dictionary = interaction_option(simulation, prompt, option_id)
	if option.is_empty():
		var disabled_option: Dictionary = disabled_interaction_option(simulation, prompt, option_id)
		if not disabled_option.is_empty():
			return {
				"success": false,
				"reason": str(disabled_option.get("disabled_reason", "interaction_option_unavailable")),
				"prompt": prompt,
			}
		return {"success": false, "reason": "interaction_option_unavailable", "prompt": prompt}
	match str(option.get("kind", "")):
		"wait":
			var wait_result: Dictionary = simulation._submit_wait_command(actor, command)
			if bool(wait_result.get("success", false)):
				simulation._emit("interaction_succeeded", interaction_success_payload(simulation, actor.actor_id, prompt, option, actor.actor_id))
				wait_result["prompt"] = prompt
			return wait_result
		"move":
			return simulation._submit_move_command(actor, {
				"kind": "move",
				"actor_id": actor.actor_id,
				"target_position": option.get("grid", {}),
				"topology": command.get("topology", {}),
			})
		"attack":
			return simulation._submit_attack_command(actor, {
				"kind": "attack",
				"actor_id": actor.actor_id,
				"target_actor_id": int(option.get("target_actor_id", 0)),
				"topology": command.get("topology", {}),
				"source_target": target,
				"source_option_id": option_id,
			})

	var topology: Dictionary = simulation._dictionary_or_empty(command.get("topology", {}))
	if not actor_can_reach_interaction(simulation, actor, prompt):
		return approach_then_execute_interaction(simulation, actor, target, option_id, prompt, topology)

	var cost: float = float(command.get("ap_cost", simulation.DEFAULT_INTERACTION_AP))
	if actor.ap < cost:
		simulation.pending_interaction = {
			"actor_id": actor.actor_id,
			"target": target.duplicate(true),
			"option_id": option_id,
			"required_ap": cost,
			"available_ap": actor.ap,
		}
		simulation._emit("interaction_queued", simulation.pending_interaction.duplicate(true))
		return {
			"success": false,
			"reason": "ap_insufficient_interaction_queued",
			"pending_interaction": simulation.pending_interaction.duplicate(true),
		}

	simulation._spend_ap(actor, cost, "interact:%s" % option_id)
	var result: Dictionary = simulation.execute_interaction(actor.actor_id, target, option_id)
	if bool(result.get("success", false)):
		simulation.pending_interaction.clear()
	return result


func interaction_option(simulation: RefCounted, prompt: Dictionary, option_id: String) -> Dictionary:
	for option in simulation._array_or_empty(prompt.get("options", [])):
		var option_data: Dictionary = simulation._dictionary_or_empty(option)
		if str(option_data.get("id", "")) == option_id:
			return option_data
	if option_id.is_empty():
		var options: Array = simulation._array_or_empty(prompt.get("options", []))
		return simulation._dictionary_or_empty(options.front() if not options.is_empty() else {})
	return {}


func disabled_interaction_option(simulation: RefCounted, prompt: Dictionary, option_id: String) -> Dictionary:
	if option_id.is_empty():
		return {}
	for option in simulation._array_or_empty(prompt.get("disabled_options", [])):
		var option_data: Dictionary = simulation._dictionary_or_empty(option)
		if str(option_data.get("id", "")) == option_id:
			return option_data
	return {}


func interaction_success_payload(simulation: RefCounted, actor_id: int, prompt: Dictionary, option: Dictionary, target_id: Variant) -> Dictionary:
	var target: Dictionary = simulation._dictionary_or_empty(prompt.get("target", {}))
	var target_name: String = str(prompt.get("target_name", target.get("display_name", ""))).strip_edges()
	if target_name.is_empty():
		target_name = str(target_id).strip_edges()
	return {
		"actor_id": actor_id,
		"target_id": target_id,
		"target_type": str(target.get("target_type", "")),
		"target_name": target_name,
		"target_grid": interaction_target_grid(simulation, target),
		"option_id": str(option.get("id", "")),
		"option_kind": str(option.get("kind", "")),
		"option_name": str(option.get("display_name", "")),
	}


func interaction_target_grid(simulation: RefCounted, target: Dictionary) -> Dictionary:
	for key in ["grid_position", "anchor", "grid"]:
		var grid: Dictionary = simulation._dictionary_or_empty(target.get(key, {}))
		if not grid.is_empty():
			return grid.duplicate(true)
	var cells: Array = simulation._array_or_empty(target.get("cells", []))
	if not cells.is_empty():
		return simulation._dictionary_or_empty(cells[0]).duplicate(true)
	return {}


func actor_can_reach_interaction(simulation: RefCounted, actor: RefCounted, prompt: Dictionary) -> bool:
	var target: Dictionary = simulation._dictionary_or_empty(prompt.get("target", {}))
	var interaction_range: int = max(0, int(prompt.get("interaction_range", 1)))
	match str(target.get("target_type", "")):
		"actor":
			var target_actor: RefCounted = simulation.actor_registry.get_actor(int(target.get("actor_id", 0)))
			if target_actor == null:
				return false
			return simulation._grid_distance(actor.grid_position, target_actor.grid_position) <= interaction_range
		"map_object":
			for cell in simulation._array_or_empty(target.get("cells", [])):
				var cell_coord: RefCounted = GridCoord.from_dictionary(simulation._dictionary_or_empty(cell))
				if simulation._grid_distance(actor.grid_position, cell_coord) <= interaction_range:
					return true
			var anchor: RefCounted = GridCoord.from_dictionary(simulation._dictionary_or_empty(target.get("anchor", {})))
			return simulation._grid_distance(actor.grid_position, anchor) <= interaction_range
		_:
			return true


func approach_then_execute_interaction(simulation: RefCounted, actor: RefCounted, target: Dictionary, option_id: String, prompt: Dictionary, topology: Dictionary) -> Dictionary:
	if topology.is_empty():
		return {"success": false, "reason": "approach_topology_missing", "prompt": prompt}
	var approach_plan: Dictionary = approach_plan_for_prompt(simulation, actor, prompt, topology)
	if not bool(approach_plan.get("success", false)):
		return {
			"success": false,
			"reason": approach_plan.get("reason", "approach_target_unreachable"),
			"prompt": prompt,
			"approach_result": approach_plan,
			"interaction_range": int(prompt.get("interaction_range", 1)),
			"target_distance": int(prompt.get("target_distance", -1)),
		}
	var approach_goal: Dictionary = simulation._dictionary_or_empty(approach_plan.get("chosen_goal", {})).duplicate(true)
	simulation.pending_movement = {
		"actor_id": actor.actor_id,
		"target_position": approach_goal.duplicate(true),
		"path": simulation._array_or_empty(approach_plan.get("path", [])).duplicate(true),
		"required_ap": float(max(0, int(approach_plan.get("steps", 0)))),
		"available_ap": actor.ap,
		"after_movement_interaction": {
			"target": target.duplicate(true),
			"option_id": option_id,
		},
	}
	simulation.pending_interaction = {
		"actor_id": actor.actor_id,
		"target": target.duplicate(true),
		"option_id": option_id,
		"after_movement": true,
	}
	simulation._emit("movement_queued", simulation.pending_movement.duplicate(true))
	simulation._emit("interaction_queued", simulation.pending_interaction.duplicate(true))
	var move_result: Dictionary = simulation._advance_pending_movement(actor, topology)
	if not bool(move_result.get("success", false)):
		return {
			"success": false,
			"reason": move_result.get("reason", "approach_move_failed"),
			"move_result": move_result,
			"pending_interaction": simulation.pending_interaction.duplicate(true),
			"prompt": prompt,
		}
	if not bool(move_result.get("completed", false)):
		return {
			"success": true,
			"kind": "approach_queued",
			"reason": "approach_movement_pending",
			"approach_result": move_result,
			"pending_movement": simulation.pending_movement.duplicate(true),
			"pending_interaction": simulation.pending_interaction.duplicate(true),
			"prompt": prompt,
		}
	return simulation._resume_pending_interaction(actor, topology, move_result)


func begin_interaction_approach_for_runner(simulation: RefCounted, actor: RefCounted, target: Dictionary, option_id: String, prompt: Dictionary, topology: Dictionary, event_start_index: int) -> Dictionary:
	if topology.is_empty():
		return {"success": false, "reason": "approach_topology_missing", "prompt": prompt}
	var approach_plan: Dictionary = approach_plan_for_prompt(simulation, actor, prompt, topology)
	if not bool(approach_plan.get("success", false)):
		return {
			"success": false,
			"reason": approach_plan.get("reason", "approach_target_unreachable"),
			"prompt": prompt,
			"approach_result": approach_plan,
			"interaction_range": int(prompt.get("interaction_range", 1)),
			"target_distance": int(prompt.get("target_distance", -1)),
		}
	var approach_goal: Dictionary = simulation._dictionary_or_empty(approach_plan.get("chosen_goal", {})).duplicate(true)
	simulation.pending_interaction = {
		"actor_id": actor.actor_id,
		"target": target.duplicate(true),
		"option_id": option_id,
		"after_movement": true,
		"runner_step_mode": true,
	}
	var begin: Dictionary = simulation.begin_move(actor.actor_id, approach_goal, topology, approach_plan)
	if not bool(begin.get("success", false)):
		simulation.pending_interaction.clear()
		begin["prompt"] = prompt
		return begin
	simulation.pending_movement["after_movement_interaction"] = {
		"target": target.duplicate(true),
		"option_id": option_id,
	}
	simulation.pending_movement["runner_interaction_approach"] = true
	simulation._emit("interaction_queued", simulation.pending_interaction.duplicate(true))
	return {
		"success": true,
		"kind": "interaction_approach_started",
		"actor_id": actor.actor_id,
		"target": target.duplicate(true),
		"option_id": option_id,
		"prompt": prompt,
		"approach_required": true,
		"target_position": simulation._dictionary_or_empty(begin.get("target_position", approach_goal)).duplicate(true),
		"path": simulation._array_or_empty(begin.get("path", [])).duplicate(true),
		"steps": int(begin.get("steps", 0)),
		"pending_movement": simulation.pending_movement.duplicate(true),
		"pending_interaction": simulation.pending_interaction.duplicate(true),
		"turn_state": simulation.turn_state.duplicate(true),
		"events": simulation._events_since(event_start_index),
	}


func approach_goal_for_prompt(simulation: RefCounted, actor: RefCounted, prompt: Dictionary, topology: Dictionary) -> Variant:
	var plan: Dictionary = approach_plan_for_prompt(simulation, actor, prompt, topology)
	if not bool(plan.get("success", false)):
		return null
	return simulation._dictionary_or_empty(plan.get("chosen_goal", {})).duplicate(true)


func approach_plan_for_prompt(simulation: RefCounted, actor: RefCounted, prompt: Dictionary, topology: Dictionary) -> Dictionary:
	var target: Dictionary = simulation._dictionary_or_empty(prompt.get("target", {}))
	var interaction_range: int = max(0, int(prompt.get("interaction_range", 1)))
	var candidates: Array[RefCounted] = []
	var movement_topology: Dictionary = simulation._topology_with_auto_open_doors(actor.actor_id, topology)
	match str(target.get("target_type", "")):
		"actor":
			var target_actor: RefCounted = simulation.actor_registry.get_actor(int(target.get("actor_id", 0)))
			if target_actor != null:
				candidates = interaction_goals(simulation, target_actor.grid_position, interaction_range)
		"map_object":
			for cell in simulation._array_or_empty(target.get("cells", [])):
				var cell_coord: RefCounted = GridCoord.from_dictionary(simulation._dictionary_or_empty(cell))
				candidates.append_array(interaction_goals(simulation, cell_coord, interaction_range))
			if candidates.is_empty():
				candidates = interaction_goals(simulation, GridCoord.from_dictionary(simulation._dictionary_or_empty(target.get("anchor", {}))), interaction_range)
	if candidates.is_empty():
		return {
			"success": false,
			"reason": "approach_target_unreachable",
			"goal_count": 0,
		}
	var plan: Dictionary = simulation._pathfinder.find_path_to_any(actor.grid_position, candidates, movement_topology, simulation._occupied_actor_cells(actor.actor_id))
	if not bool(plan.get("success", false)) and str(plan.get("reason", "")) == "path_unreachable":
		plan["reason"] = "approach_target_unreachable"
	return plan


func interaction_goals(_simulation: RefCounted, center: RefCounted, interaction_range: int) -> Array[RefCounted]:
	var output: Array[RefCounted] = []
	var resolved_range: int = max(1, interaction_range)
	for dx in range(-resolved_range, resolved_range + 1):
		for dz in range(-resolved_range, resolved_range + 1):
			var distance: int = abs(dx) + abs(dz)
			if distance <= 0 or distance > resolved_range:
				continue
			output.append(GridCoord.new(center.x + dx, center.y, center.z + dz))
	return output
