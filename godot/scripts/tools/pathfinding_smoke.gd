extends SceneTree

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const Pathfinder = preload("res://scripts/core/movement/pathfinder.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")


func _init() -> void:
	var errors := _run_checks()
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return
	print("pathfinding_smoke passed")
	quit(0)


func _run_checks() -> Array[String]:
	var errors: Array[String] = []
	var pathfinder := Pathfinder.new()
	var topology: Dictionary = _open_topology()
	var start := GridCoord.new(0, 0, 0)
	var goal := GridCoord.new(20, 0, 20)
	var plan: Dictionary = pathfinder.find_path(start, goal, topology, {})
	if not bool(plan.get("success", false)):
		errors.append("single-target A* should reach far goal: %s" % JSON.stringify(plan))
	elif str(plan.get("algorithm", "")) != "astar":
		errors.append("single-target result should report astar")
	elif int(plan.get("steps", -1)) != 20:
		errors.append("single-target A* should use 8-direction shortest steps, got %d" % int(plan.get("steps", -1)))
	elif int(plan.get("expanded_cell_count", 999999)) > 80:
		errors.append("single-target A* expanded too many cells: %d" % int(plan.get("expanded_cell_count", 0)))

	var before_execution_count: int = int(plan.get("search_execution_count", 0))
	var candidates: Array[RefCounted] = [
		GridCoord.new(20, 0, 21),
		GridCoord.new(21, 0, 20),
		GridCoord.new(20, 0, 19),
		GridCoord.new(19, 0, 20),
	]
	var multi: Dictionary = pathfinder.find_path_to_any(start, candidates, topology, {})
	if not bool(multi.get("success", false)):
		errors.append("multi-target A* should reach one candidate: %s" % JSON.stringify(multi))
	elif str(multi.get("algorithm", "")) != "multi_goal_astar":
		errors.append("multi-target result should report multi_goal_astar")
	elif int(multi.get("goal_count", 0)) != candidates.size():
		errors.append("multi-target result should preserve goal_count")
	elif int(multi.get("search_execution_count", 0)) != before_execution_count + 1:
		errors.append("multi-target approach should execute exactly one bottom-level search")

	var cached: Dictionary = pathfinder.find_path_to_any(start, candidates, topology, {})
	if not bool(cached.get("success", false)):
		errors.append("cached multi-target A* should still succeed")
	elif not bool(cached.get("cache_hit", false)):
		errors.append("second identical multi-target search should hit cache")
	elif int(cached.get("search_execution_count", 0)) != int(multi.get("search_execution_count", 0)):
		errors.append("cache hit should not increment search execution count")

	var blocked_topology: Dictionary = _open_topology()
	blocked_topology["blocking_cells"] = {
		"5:0:5": "wall",
		"5:0:6": "wall",
		"6:0:5": "wall",
	}
	var blocked_candidates: Array[RefCounted] = [
		GridCoord.new(5, 0, 5),
		GridCoord.new(6, 0, 6),
	]
	var filtered: Dictionary = pathfinder.find_path_to_any(GridCoord.new(4, 0, 4), blocked_candidates, blocked_topology, {})
	if not bool(filtered.get("success", false)):
		errors.append("multi-target search should prefilter blocked goals and use remaining legal candidates: %s" % JSON.stringify(filtered))
	elif int(filtered.get("valid_goal_count", 0)) != 1:
		errors.append("multi-target search should report one legal candidate after prefilter")

	var enclosed_topology: Dictionary = _open_topology()
	for x in range(8, 13):
		enclosed_topology["blocking_cells"]["%d:0:8" % x] = "wall"
		enclosed_topology["blocking_cells"]["%d:0:12" % x] = "wall"
	for z in range(8, 13):
		enclosed_topology["blocking_cells"]["8:0:%d" % z] = "wall"
		enclosed_topology["blocking_cells"]["12:0:%d" % z] = "wall"
	enclosed_topology["blocking_cell_count"] = enclosed_topology["blocking_cells"].size()
	var enclosed_goals: Array[RefCounted] = [
		GridCoord.new(10, 0, 10),
		GridCoord.new(10, 0, 9),
		GridCoord.new(9, 0, 10),
	]
	var enclosed: Dictionary = pathfinder.find_path_to_any(start, enclosed_goals, enclosed_topology, {})
	if bool(enclosed.get("success", false)) or str(enclosed.get("reason", "")) != "path_unreachable":
		errors.append("enclosed multi-target search should be unreachable")
	elif int(enclosed.get("visited_cell_count", 999999)) > 32:
		errors.append("enclosed multi-target reverse search should scan enclosed island, not player region: %s" % JSON.stringify(enclosed))

	var unreachable_topology: Dictionary = _open_topology()
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			unreachable_topology["blocking_cells"]["%d:0:%d" % [10 + dx, 10 + dz]] = "wall"
	unreachable_topology["blocking_cell_count"] = unreachable_topology["blocking_cells"].size()
	var unreachable_pathfinder := Pathfinder.new()
	unreachable_pathfinder.time_budget_ms = 0.0
	var unreachable: Dictionary = unreachable_pathfinder.find_path(start, GridCoord.new(10, 0, 10), unreachable_topology, {})
	if bool(unreachable.get("success", false)) or str(unreachable.get("reason", "")) != "path_unreachable":
		errors.append("unreachable goal should return path_unreachable: %s" % JSON.stringify(unreachable))
	elif str(unreachable.get("algorithm", "")) != "astar":
		errors.append("unreachable result should keep algorithm diagnostics")
	var budgeted_pathfinder := Pathfinder.new()
	budgeted_pathfinder.native_grid_enabled = false
	budgeted_pathfinder.max_visited_cells = 16
	var budgeted: Dictionary = budgeted_pathfinder.find_path(start, GridCoord.new(40, 0, 40), topology, {})
	if bool(budgeted.get("success", false)) or str(budgeted.get("reason", "")) != "pathfinding_budget_exceeded":
		errors.append("pathfinding should enforce visited-cell budget: %s" % JSON.stringify(budgeted))
	elif not bool(budgeted.get("budget_exceeded", false)):
		errors.append("budgeted pathfinding failure should report budget_exceeded")
	elif int(budgeted.get("visited_cell_count", 0)) < budgeted_pathfinder.max_visited_cells:
		errors.append("budgeted pathfinding should report visited count at the limit")
	errors.append_array(_expect_far_npc_interaction_approach())
	errors.append_array(_expect_far_map_object_interaction_approach())
	return errors


func _expect_far_npc_interaction_approach() -> Array[String]:
	var errors: Array[String] = []
	var registry := ContentRegistry.new()
	var load_result = registry.load_all()
	if load_result.has_errors():
		return ["pathfinding smoke could not load registry"]
	var simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	var trader: RefCounted = simulation.actor_registry.get_actor(2)
	player.grid_position = GridCoord.new(24, 0, 39)
	trader.grid_position = GridCoord.new(1, 0, 0)
	var topology: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot()).get("map", {})
	var prompt: Dictionary = simulation.query_interaction_options(1, {
		"target_type": "actor",
		"actor_id": 2,
	})
	var result: Dictionary = simulation.begin_interaction_for_runner(1, {
		"target_type": "actor",
		"actor_id": 2,
	}, "talk", topology)
	if not bool(result.get("success", false)):
		errors.append("far NPC talk should start auto-approach: %s" % JSON.stringify(result))
	elif str(result.get("kind", "")) != "interaction_approach_started":
		errors.append("far NPC talk should use runner interaction approach, got %s" % str(result.get("kind", "")))
	var last_path: Dictionary = simulation.last_pathfinding_result()
	if str(last_path.get("algorithm", "")) != "multi_goal_astar":
		errors.append("far NPC talk approach should use multi_goal_astar")
	if int(last_path.get("goal_count", 0)) < int(prompt.get("interaction_range", 1)):
		errors.append("far NPC talk approach should expose multi-target goal_count")
	if int(last_path.get("search_execution_count", 0)) != 1:
		errors.append("far NPC talk approach should use one bottom-level search, got %d" % int(last_path.get("search_execution_count", 0)))
	if bool(last_path.get("over_profiler_budget", false)) or bool(last_path.get("budget_exceeded", false)):
		errors.append("far NPC talk pathfinding should stay within budget: %s" % JSON.stringify(last_path))
	return errors


func _expect_far_map_object_interaction_approach() -> Array[String]:
	var errors: Array[String] = []
	var registry := ContentRegistry.new()
	var load_result = registry.load_all()
	if load_result.has_errors():
		return ["pathfinding smoke could not load registry for map object approach"]
	var simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	player.grid_position = GridCoord.new(24, 0, 39)
	var topology: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot()).get("map", {})
	var result: Dictionary = simulation.begin_interaction_for_runner(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_interior_door",
	}, "enter_subscene", topology)
	if not bool(result.get("success", false)):
		errors.append("far map object interaction should start auto-approach: %s" % JSON.stringify(result))
	elif str(result.get("kind", "")) != "interaction_approach_started":
		errors.append("far map object interaction should use runner approach, got %s" % str(result.get("kind", "")))
	var last_path: Dictionary = simulation.last_pathfinding_result()
	if str(last_path.get("algorithm", "")) != "multi_goal_astar":
		errors.append("far map object approach should use multi_goal_astar")
	if int(last_path.get("search_execution_count", 0)) != 1:
		errors.append("far map object approach should use one bottom-level search, got %d" % int(last_path.get("search_execution_count", 0)))
	if bool(last_path.get("over_profiler_budget", false)) or bool(last_path.get("budget_exceeded", false)):
		errors.append("far map object pathfinding should stay within budget: %s" % JSON.stringify(last_path))
	return errors


func _open_topology() -> Dictionary:
	return {
		"map_id": "pathfinding_smoke",
		"topology_revision": "pathfinding_smoke_v1",
		"bounds": {
			"min_x": 0,
			"max_x": 40,
			"min_z": 0,
			"max_z": 40,
		},
		"blocking_cells": {},
		"blocking_cell_count": 0,
	}
