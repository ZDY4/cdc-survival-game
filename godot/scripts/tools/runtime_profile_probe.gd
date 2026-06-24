extends SceneTree

const GameRootScene = preload("res://scenes/game/game_root.tscn")

const DEFAULT_SCENARIO := "MovementClickRepeat"
const DEFAULT_MAP_ID := "survivor_outpost_01"
const DEFAULT_ITERATIONS := 12
const DEFAULT_MAX_FRAMES_PER_MOVE := 720
const DEFAULT_VIEWPORT_SIZE := Vector2i(1440, 900)

var _output_path := ""
var _scenario := DEFAULT_SCENARIO
var _map_id := DEFAULT_MAP_ID
var _iterations := DEFAULT_ITERATIONS
var _max_frames_per_move := DEFAULT_MAX_FRAMES_PER_MOVE
var _game_root: Node
var _turn_runner_proxy: RefCounted
var _player_command_proxy: RefCounted
var _runtime_input_proxy: RefCounted
var _function_samples: Array[Dictionary] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := _parse_user_args()
	_output_path = str(args.get("output", ""))
	_scenario = str(args.get("scenario", DEFAULT_SCENARIO))
	_map_id = str(args.get("map", DEFAULT_MAP_ID))
	_iterations = max(1, int(args.get("iterations", DEFAULT_ITERATIONS)))
	_max_frames_per_move = max(1, int(args.get("max_frames_per_move", DEFAULT_MAX_FRAMES_PER_MOVE)))
	if _output_path.is_empty():
		_output_path = "user://runtime_profile_probe.json"
	if _scenario != "MovementClickRepeat":
		_finish({"success": false, "reason": "unsupported_profile_scenario", "scenario": _scenario})
		return

	get_root().content_scale_size = DEFAULT_VIEWPORT_SIZE
	_game_root = GameRootScene.instantiate()
	get_root().add_child(_game_root)
	await _wait_frames(8)
	var startup_error := _startup_error()
	if not startup_error.is_empty():
		_finish({"success": false, "reason": startup_error})
		return

	_install_timing_proxies()
	await _wait_frames(2)

	var target_sequence := _target_sequence()
	if target_sequence.is_empty():
		_finish({"success": false, "reason": "no_reachable_screen_targets", "startup": _capture_state()})
		return
	var iterations: Array[Dictionary] = []
	for index in range(_iterations):
		var target: Dictionary = _next_reachable_screen_target(index, target_sequence)
		if target.is_empty():
			var missing_target := {
				"success": false,
				"iteration": index + 1,
				"reason": "reachable_screen_target_missing",
				"before": _capture_state(),
				"after": _capture_state(),
			}
			iterations.append(missing_target)
			print("runtime_profile %s iteration %d/%d target=<missing> success=false reason=reachable_screen_target_missing" % [_scenario, index + 1, _iterations])
			continue
		var iteration_result: Dictionary = await _run_click_iteration(index + 1, target)
		iterations.append(iteration_result)
		print("runtime_profile %s iteration %d/%d target=%s success=%s frames=%d avg_frame_ms=%.3f request_ms=%.3f drain_ms=%.3f runner_process_total_ms=%.3f" % [
			_scenario,
			index + 1,
			_iterations,
			_grid_key(_dictionary_or_empty(target.get("grid", {}))),
			str(iteration_result.get("success", false)),
			int(iteration_result.get("frames", 0)),
			float(iteration_result.get("avg_frame_time_ms", 0.0)),
			float(iteration_result.get("request_player_move_ms", 0.0)),
			float(iteration_result.get("wait_total_ms", 0.0)),
			float(_dictionary_or_empty(iteration_result.get("function_summary", {})).get("TurnActionRunner.process.total_ms", 0.0)),
		])
		await _wait_frames(4)

	var result := {
		"success": true,
		"scenario": _scenario,
		"map": _map_id,
		"iterations_requested": _iterations,
		"iterations": iterations,
		"summary": _summarize_iterations(iterations),
		"function_summary": _summarize_function_samples(_function_samples),
		"final": _capture_state(),
		"output_path": _output_path,
	}
	_finish(result)


func _run_click_iteration(index: int, target: Dictionary) -> Dictionary:
	var before_state := _capture_state()
	var target_grid: Dictionary = _dictionary_or_empty(target.get("grid", {}))
	var screen_position: Variant = target.get("screen_position", null)
	if typeof(screen_position) != TYPE_VECTOR2:
		return {
			"success": false,
			"iteration": index,
			"target_grid": target_grid.duplicate(true),
			"reason": "screen_position_unavailable",
			"before": before_state,
			"after": _capture_state(),
		}

	var sample_start := _function_samples.size()
	var request_started := Time.get_ticks_usec()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = screen_position
	event.global_position = screen_position
	Input.parse_input_event(event)
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = screen_position
	release.global_position = screen_position
	Input.parse_input_event(release)
	var request_elapsed := _elapsed_ms(request_started)

	var wait_started := Time.get_ticks_usec()
	var frame_times: Array[float] = []
	var fps_values: Array[float] = []
	var frames := 0
	var reached := false
	var drain_result: Dictionary = {}
	while frames < _max_frames_per_move:
		await process_frame
		frames += 1
		var perf := _runtime_performance_snapshot()
		frame_times.append(float(perf.get("frame_time_ms", 0.0)))
		fps_values.append(float(perf.get("fps", 0.0)))
		var runner := _turn_action_runner_snapshot()
		if bool(runner.get("active", false)) or bool(runner.get("presentation_active", false)):
			continue
		var player_grid := _player_grid()
		if _same_grid(player_grid, target_grid):
			reached = true
			break
	var wait_elapsed := _elapsed_ms(wait_started)
	if _game_root.has_method("drain_turn_action_runner"):
		drain_result = _dictionary_or_empty(_game_root.call("drain_turn_action_runner", 240))
		await process_frame

	var after_state := _capture_state()
	var samples := _function_samples.slice(sample_start)
	var summary := _summarize_function_samples(samples)
	var success := reached and _same_grid(_dictionary_or_empty(after_state.get("player_grid", {})), target_grid)
	return {
		"success": success,
		"iteration": index,
		"target_grid": target_grid.duplicate(true),
		"desired_grid": _dictionary_or_empty(target.get("desired_grid", {})).duplicate(true),
		"screen_position": {"x": float(screen_position.x), "y": float(screen_position.y)},
		"target_move_preview": _dictionary_or_empty(target.get("move_preview", {})).duplicate(true),
		"request_player_move_ms": request_elapsed,
		"wait_total_ms": wait_elapsed,
		"frames": frames,
		"reached": reached,
		"avg_frame_time_ms": _average(frame_times),
		"max_frame_time_ms": _max_float(frame_times),
		"min_fps": _min_positive(fps_values),
		"avg_fps": _average_positive(fps_values),
		"before": before_state,
		"after": after_state,
		"drain_result": drain_result,
		"function_summary": summary,
		"pathfinding": _pathfinding_from_performance(_runtime_performance_snapshot()),
		"sample_count": samples.size(),
		"reason": "" if success else "target_not_reached",
	}


func _install_timing_proxies() -> void:
	if _game_root == null:
		return
	var original_input: RefCounted = _game_root.get("runtime_input_controller")
	if original_input != null:
		_runtime_input_proxy = _TimedRuntimeInputControllerProxy.new(original_input, Callable(self, "_record_function_sample"))
		_game_root.set("runtime_input_controller", _runtime_input_proxy)
	var original_runner: RefCounted = _game_root.get("turn_action_runner")
	if original_runner != null:
		_turn_runner_proxy = _TimedTurnActionRunnerProxy.new(original_runner, Callable(self, "_record_function_sample"))
		_game_root.set("turn_action_runner", _turn_runner_proxy)
	var original_coordinator: RefCounted = _game_root.get("player_command_coordinator")
	if original_coordinator != null:
		_player_command_proxy = _TimedPlayerCommandCoordinatorProxy.new(original_coordinator, Callable(self, "_record_function_sample"))
		_game_root.set("player_command_coordinator", _player_command_proxy)
		if _player_command_proxy.has_method("configure"):
			_player_command_proxy.call("configure", _game_root)
	if _game_root.has_method("sync_after_turn_action_step"):
		_game_root.call("sync_after_turn_action_step", {}, {})


func _record_function_sample(function_name: String, elapsed_ms: float, extra: Dictionary = {}) -> void:
	var sample := {
		"function": function_name,
		"elapsed_ms": elapsed_ms,
		"tick_msec": Time.get_ticks_msec(),
	}
	for key in extra.keys():
		sample[key] = extra[key]
	_function_samples.append(sample)


func _screen_position_for_grid(grid: Dictionary) -> Variant:
	var camera := _world_camera()
	if camera == null:
		return null
	var world_position := Vector3(float(grid.get("x", 0)), float(grid.get("y", 0)) + 0.5, float(grid.get("z", 0)))
	if camera.is_position_behind(world_position):
		return null
	return camera.unproject_position(world_position)


func _target_sequence() -> Array[Dictionary]:
	var offsets: Array[Vector2i] = [
		Vector2i(4, 0),
		Vector2i(-4, 0),
		Vector2i(0, 4),
		Vector2i(0, -4),
		Vector2i(5, 2),
		Vector2i(-5, -2),
		Vector2i(2, 5),
		Vector2i(-2, -5),
		Vector2i(6, 0),
		Vector2i(-6, 0),
		Vector2i(0, 6),
		Vector2i(0, -6),
	]
	var sequence: Array[Dictionary] = []
	for offset in offsets:
		sequence.append({"offset": offset})
	return sequence


func _next_reachable_screen_target(index: int, target_sequence: Array[Dictionary]) -> Dictionary:
	var player := _player_grid()
	if player.is_empty():
		return {}
	var map: Dictionary = _dictionary_or_empty(_game_root.get("world_result")).get("map", {})
	var blocking: Dictionary = _dictionary_or_empty(_dictionary_or_empty(map).get("blocking_cells", {}))
	var bounds: Dictionary = _dictionary_or_empty(_dictionary_or_empty(map).get("bounds", {}))
	for attempt in range(target_sequence.size()):
		var entry: Dictionary = target_sequence[(index + attempt) % target_sequence.size()]
		var offset: Vector2i = entry.get("offset", Vector2i.ZERO)
		var desired := {
			"x": int(player.get("x", 0)) + offset.x,
			"y": int(player.get("y", 0)),
			"z": int(player.get("z", 0)) + offset.y,
		}
		if not _grid_in_bounds(desired, bounds) or blocking.has(_grid_key(desired)):
			continue
		var screen_position: Variant = _screen_position_for_grid(desired)
		if typeof(screen_position) != TYPE_VECTOR2:
			continue
		var hover: Dictionary = _hover_at_screen_position(screen_position)
		if str(hover.get("kind", "")) != "ground":
			continue
		var actual_grid: Dictionary = _dictionary_or_empty(_dictionary_or_empty(hover.get("picking", {})).get("grid", {}))
		if actual_grid.is_empty():
			actual_grid = _grid_from_world_position(hover.get("position", Vector3.ZERO))
		if actual_grid.is_empty() or _same_grid(actual_grid, player):
			continue
		var move_preview: Dictionary = _dictionary_or_empty(_dictionary_or_empty(_runtime_hover_snapshot()).get("move_preview", {}))
		if not bool(move_preview.get("reachable", false)):
			continue
		return {
			"grid": actual_grid.duplicate(true),
			"desired_grid": desired.duplicate(true),
			"screen_position": screen_position,
			"move_preview": move_preview.duplicate(true),
		}
	return {}


func _capture_state() -> Dictionary:
	var perf := _runtime_performance_snapshot()
	var runner := _turn_action_runner_snapshot()
	return {
		"tick_msec": Time.get_ticks_msec(),
		"player_grid": _player_grid(),
		"runner_active": bool(runner.get("active", false)),
		"runner_phase": str(runner.get("phase", "")),
		"runner_action_kind": str(runner.get("action_kind", "")),
		"pending_kind": str(runner.get("pending_kind", "")),
		"render_count": int(perf.get("render_count", 0)),
		"render_counts": _dictionary_or_empty(perf.get("render_counts", {})).duplicate(true),
		"fps": float(perf.get("fps", 0.0)),
		"frame_time_ms": float(perf.get("frame_time_ms", 0.0)),
		"pathfinding": _pathfinding_from_performance(perf),
		"node_count": _node_count(get_root()),
		"orphan_node_count": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
	}


func _runtime_performance_snapshot() -> Dictionary:
	if _game_root != null and _game_root.has_method("runtime_performance_snapshot"):
		return _dictionary_or_empty(_game_root.call("runtime_performance_snapshot"))
	return {}


func _runtime_hover_snapshot() -> Dictionary:
	if _game_root != null and _game_root.has_method("runtime_hover_snapshot"):
		return _dictionary_or_empty(_game_root.call("runtime_hover_snapshot"))
	return {}


func _hover_at_screen_position(screen_position: Vector2) -> Dictionary:
	if _game_root == null:
		return {}
	var input_controller: RefCounted = _game_root.get("runtime_input_controller")
	if input_controller == null or not input_controller.has_method("update_hover_at_screen_position"):
		return {}
	return _dictionary_or_empty(input_controller.call("update_hover_at_screen_position", screen_position))


func _turn_action_runner_snapshot() -> Dictionary:
	if _game_root != null and _game_root.has_method("turn_action_runner_snapshot"):
		return _dictionary_or_empty(_game_root.call("turn_action_runner_snapshot"))
	return {}


func _player_grid() -> Dictionary:
	if _game_root == null:
		return {}
	var simulation: RefCounted = _game_root.get("simulation")
	if simulation == null:
		return {}
	var registry: Variant = simulation.get("actor_registry")
	if registry == null or not registry.has_method("get_actor"):
		return {}
	var actor: RefCounted = registry.call("get_actor", 1)
	if actor == null:
		return {}
	var coord: RefCounted = actor.get("grid_position")
	if coord == null or not coord.has_method("to_dictionary"):
		return {}
	return _dictionary_or_empty(coord.call("to_dictionary"))


func _world_camera() -> Camera3D:
	if _game_root == null:
		return null
	var world_root: Node = _game_root.get("world_root")
	if world_root == null:
		return null
	return world_root.find_child("WorldCamera", true, false) as Camera3D


func _grid_from_world_position(world_position: Vector3) -> Dictionary:
	return {
		"x": int(roundf(world_position.x)),
		"y": int(floorf(world_position.y)),
		"z": int(roundf(world_position.z)),
	}


func _startup_error() -> String:
	if _game_root == null:
		return "game_root_missing"
	if _game_root.get("simulation") == null:
		return "simulation_missing"
	if _game_root.get("world_root") == null:
		return "world_root_missing"
	if _game_root.get("runtime_input_controller") == null:
		return "runtime_input_controller_missing"
	if _world_camera() == null:
		return "world_camera_missing"
	var world_result: Dictionary = _dictionary_or_empty(_game_root.get("world_result"))
	var map: Dictionary = _dictionary_or_empty(world_result.get("map", {}))
	var map_id := str(map.get("map_id", map.get("id", "")))
	if map_id != _map_id:
		return "unexpected_map_%s" % map_id
	return ""


func _finish(result: Dictionary) -> void:
	var absolute_path := ProjectSettings.globalize_path(_output_path)
	var file := FileAccess.open(_output_path, FileAccess.WRITE)
	if file == null:
		printerr("无法写入性能 probe 结果: %s" % _output_path)
		print(JSON.stringify(result, "\t"))
		quit(1)
		return
	result["absolute_output_path"] = absolute_path
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("runtime_profile_probe result: %s" % absolute_path)
	print(JSON.stringify(_dictionary_or_empty(result.get("summary", {})), "\t"))
	quit(0 if bool(result.get("success", false)) else 1)


func _parse_user_args() -> Dictionary:
	var output := {}
	for raw_arg in OS.get_cmdline_user_args():
		var arg := str(raw_arg)
		if not arg.begins_with("--"):
			continue
		var parts := arg.substr(2).split("=", true, 1)
		var key := str(parts[0])
		var value := "true" if parts.size() < 2 else str(parts[1])
		match key:
			"scenario":
				output[key] = value
			"map":
				output[key] = value
			"iterations":
				output[key] = int(value)
			"max-frames-per-move":
				output["max_frames_per_move"] = int(value)
			"output":
				output[key] = value
	return output


func _summarize_iterations(iterations: Array[Dictionary]) -> Dictionary:
	var avg_frames: Array[float] = []
	var avg_frame_ms: Array[float] = []
	var max_frame_ms: Array[float] = []
	var wait_ms: Array[float] = []
	var request_ms: Array[float] = []
	var render_counts: Array[float] = []
	var node_counts: Array[float] = []
	var pathfinding_ms: Array[float] = []
	for iteration in iterations:
		avg_frames.append(float(iteration.get("frames", 0)))
		avg_frame_ms.append(float(iteration.get("avg_frame_time_ms", 0.0)))
		max_frame_ms.append(float(iteration.get("max_frame_time_ms", 0.0)))
		wait_ms.append(float(iteration.get("wait_total_ms", 0.0)))
		request_ms.append(float(iteration.get("request_player_move_ms", 0.0)))
		var after_state: Dictionary = _dictionary_or_empty(iteration.get("after", {}))
		render_counts.append(float(after_state.get("render_count", 0)))
		node_counts.append(float(after_state.get("node_count", 0)))
		pathfinding_ms.append(float(_dictionary_or_empty(iteration.get("pathfinding", {})).get("pathfinding_time_ms", 0.0)))
	return {
		"iteration_count": iterations.size(),
		"success_count": _success_count(iterations),
		"avg_frames": _average(avg_frames),
		"first_half_avg_frame_time_ms": _iteration_metric_average(iterations, "avg_frame_time_ms", true),
		"last_half_avg_frame_time_ms": _iteration_metric_average(iterations, "avg_frame_time_ms", false),
		"first_half_wait_total_ms": _iteration_metric_average(iterations, "wait_total_ms", true),
		"last_half_wait_total_ms": _iteration_metric_average(iterations, "wait_total_ms", false),
		"first_half_request_player_move_ms": _iteration_metric_average(iterations, "request_player_move_ms", true),
		"last_half_request_player_move_ms": _iteration_metric_average(iterations, "request_player_move_ms", false),
		"first_avg_frame_time_ms": avg_frame_ms[0] if not avg_frame_ms.is_empty() else 0.0,
		"last_avg_frame_time_ms": avg_frame_ms[avg_frame_ms.size() - 1] if not avg_frame_ms.is_empty() else 0.0,
		"max_frame_time_ms": _max_float(max_frame_ms),
		"avg_wait_total_ms": _average(wait_ms),
		"avg_request_player_move_ms": _average(request_ms),
		"first_render_count": render_counts[0] if not render_counts.is_empty() else 0.0,
		"last_render_count": render_counts[render_counts.size() - 1] if not render_counts.is_empty() else 0.0,
		"first_node_count": node_counts[0] if not node_counts.is_empty() else 0.0,
		"last_node_count": node_counts[node_counts.size() - 1] if not node_counts.is_empty() else 0.0,
		"max_pathfinding_time_ms": _max_float(pathfinding_ms),
	}


func _iteration_metric_average(iterations: Array[Dictionary], metric: String, first_half: bool) -> float:
	if iterations.is_empty():
		return 0.0
	var split: int = max(1, int(ceil(float(iterations.size()) / 2.0)))
	var start: int = 0 if first_half else split
	var end: int = split if first_half else iterations.size()
	var values: Array[float] = []
	for index in range(start, end):
		values.append(float(iterations[index].get(metric, 0.0)))
	return _average(values)


func _summarize_function_samples(samples: Array[Dictionary]) -> Dictionary:
	var grouped := {}
	for sample in samples:
		var key := str(sample.get("function", ""))
		if key.is_empty():
			continue
		if not grouped.has(key):
			grouped[key] = []
		grouped[key].append(float(sample.get("elapsed_ms", 0.0)))
	var output := {}
	for key in grouped.keys():
		var values: Array = grouped[key]
		output["%s.count" % key] = values.size()
		output["%s.total_ms" % key] = _sum(values)
		output["%s.avg_ms" % key] = _average(values)
		output["%s.max_ms" % key] = _max_float(values)
	return output


func _pathfinding_from_performance(perf: Dictionary) -> Dictionary:
	return {
		"pathfinding_time_ms": float(perf.get("pathfinding_time_ms", 0.0)),
		"visited_cell_count": int(perf.get("pathfinding_visited_cell_count", 0)),
		"expanded_cell_count": int(perf.get("pathfinding_expanded_cell_count", 0)),
		"max_frontier_size": int(perf.get("pathfinding_max_frontier_size", 0)),
		"search_call_count": int(perf.get("pathfinding_search_call_count", 0)),
		"search_execution_count": int(perf.get("pathfinding_search_execution_count", 0)),
		"cache_hit": bool(perf.get("pathfinding_cache_hit", false)),
	}


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _grid_in_bounds(grid: Dictionary, bounds: Dictionary) -> bool:
	if bounds.is_empty():
		return true
	var x := int(grid.get("x", 0))
	var z := int(grid.get("z", 0))
	return x >= int(bounds.get("min_x", -999999)) and x <= int(bounds.get("max_x", 999999)) \
		and z >= int(bounds.get("min_z", -999999)) and z <= int(bounds.get("max_z", 999999))


func _same_grid(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("x", -999999)) == int(b.get("x", -888888)) \
		and int(a.get("y", -999999)) == int(b.get("y", -888888)) \
		and int(a.get("z", -999999)) == int(b.get("z", -888888))


func _grid_key(grid: Dictionary) -> String:
	return "%d:%d:%d" % [int(grid.get("x", 0)), int(grid.get("y", 0)), int(grid.get("z", 0))]


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _elapsed_ms(started_usec: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000.0


func _average(values: Array) -> float:
	if values.is_empty():
		return 0.0
	return _sum(values) / float(values.size())


func _average_positive(values: Array[float]) -> float:
	var positive: Array[float] = []
	for value in values:
		if value > 0.0:
			positive.append(value)
	return _average(positive)


func _sum(values: Array) -> float:
	var total := 0.0
	for value in values:
		total += float(value)
	return total


func _max_float(values: Array) -> float:
	var max_value := 0.0
	for value in values:
		max_value = max(max_value, float(value))
	return max_value


func _min_positive(values: Array[float]) -> float:
	var min_value := INF
	for value in values:
		if value > 0.0:
			min_value = min(min_value, value)
	return 0.0 if is_inf(min_value) else min_value


func _success_count(iterations: Array[Dictionary]) -> int:
	var count := 0
	for iteration in iterations:
		if bool(iteration.get("success", false)):
			count += 1
	return count


func _node_count(root: Node) -> int:
	if root == null:
		return 0
	var count := 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		count += 1
		for child in node.get_children():
			pending.append(child)
	return count


class _TimedTurnActionRunnerProxy:
	extends RefCounted

	var target: RefCounted
	var recorder: Callable

	func _init(p_target: RefCounted, p_recorder: Callable) -> void:
		target = p_target
		recorder = p_recorder

	func configure(p_simulation: RefCounted, p_actor_view: RefCounted, p_host: Node, p_world_result: Dictionary) -> void:
		_call_timed("TurnActionRunner.configure", [p_simulation, p_actor_view, p_host, p_world_result])

	func request_move(actor_id: int, target_grid: Dictionary, topology: Dictionary) -> Dictionary:
		return _dictionary_or_empty(_call_timed("TurnActionRunner.request_move", [actor_id, target_grid, topology]))

	func request_attack(actor_id: int, target_actor_id: int, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
		return _dictionary_or_empty(_call_timed("TurnActionRunner.request_attack", [actor_id, target_actor_id, topology, options]))

	func request_interact(actor_id: int, target_data: Dictionary, option_id: String, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
		return _dictionary_or_empty(_call_timed("TurnActionRunner.request_interact", [actor_id, target_data, option_id, topology, options]))

	func request_wait(actor_id: int, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
		return _dictionary_or_empty(_call_timed("TurnActionRunner.request_wait", [actor_id, topology, options]))

	func request_craft(actor_id: int, command: Dictionary, topology: Dictionary, options: Dictionary = {}) -> Dictionary:
		return _dictionary_or_empty(_call_timed("TurnActionRunner.request_craft", [actor_id, command, topology, options]))

	func process() -> void:
		_call_timed("TurnActionRunner.process", [])

	func snapshot() -> Dictionary:
		return _dictionary_or_empty(_call_timed("TurnActionRunner.snapshot", []))

	func drain_status() -> Dictionary:
		return _dictionary_or_empty(_call_timed("TurnActionRunner.drain_status", []))

	func finish_active(reason: String = "fast_forward") -> Dictionary:
		return _dictionary_or_empty(_call_timed("TurnActionRunner.finish_active", [reason]))

	func settle_stable_boundary(reason: String = "stable_boundary") -> Dictionary:
		return _dictionary_or_empty(_call_timed("TurnActionRunner.settle_stable_boundary", [reason]))

	func _call_timed(function_name: String, args: Array) -> Variant:
		var started := Time.get_ticks_usec()
		var result: Variant = null
		if target != null and target.has_method(function_name.get_slice(".", 1)):
			result = target.callv(function_name.get_slice(".", 1), args)
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		if recorder.is_valid():
			recorder.call(function_name, elapsed, _result_extra(result))
		return result

	func _result_extra(result: Variant) -> Dictionary:
		if typeof(result) != TYPE_DICTIONARY:
			return {}
		return {
			"success": bool(result.get("success", true)),
			"phase": str(result.get("phase", "")),
			"reason": str(result.get("reason", "")),
		}

	func _dictionary_or_empty(value: Variant) -> Dictionary:
		return value if typeof(value) == TYPE_DICTIONARY else {}


class _TimedPlayerCommandCoordinatorProxy:
	extends RefCounted

	var target: RefCounted
	var recorder: Callable

	func _init(p_target: RefCounted, p_recorder: Callable) -> void:
		target = p_target
		recorder = p_recorder

	func configure(p_host) -> void:
		_call_timed("PlayerCommandCoordinator.configure", [p_host])

	func turn_action_runner_snapshot() -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.turn_action_runner_snapshot", []))

	func drain_turn_action_runner(max_steps: int = 240) -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.drain_turn_action_runner", [max_steps]))

	func settle_turn_action_runner_boundary(reason: String = "stable_boundary", max_steps: int = 8) -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.settle_turn_action_runner_boundary", [reason, max_steps]))

	func prepare_runtime_save_boundary(reason: String = "save_boundary") -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.prepare_runtime_save_boundary", [reason]))

	func request_player_move(grid: Dictionary) -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.request_player_move", [grid]))

	func request_player_attack(target_actor_id: int, options: Dictionary = {}) -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.request_player_attack", [target_actor_id, options]))

	func request_player_interaction(target_data: Dictionary, option_id: String = "", options: Dictionary = {}) -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.request_player_interaction", [target_data, option_id, options]))

	func request_player_wait(options: Dictionary = {}) -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.request_player_wait", [options]))

	func request_player_craft(command: Dictionary, options: Dictionary = {}) -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.request_player_craft", [command, options]))

	func sync_after_turn_action_step(step_result: Dictionary = {}, runner_snapshot: Dictionary = {}) -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.sync_after_turn_action_step", [step_result, runner_snapshot]))

	func player_command_rejection(action: String) -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.player_command_rejection", [action]))

	func observe_command_rejected(action: String) -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.observe_command_rejected", [action]))

	func action_presenter_command_rejected(action: String) -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.action_presenter_command_rejected", [action]))

	func ui_modal_command_rejected(action: String, modal_name: String) -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.ui_modal_command_rejected", [action, modal_name]))

	func restore_actor_camera_follow() -> void:
		_call_timed("PlayerCommandCoordinator.restore_actor_camera_follow", [])

	func press_space_action() -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.press_space_action", []))

	func repeat_space_wait_action() -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.repeat_space_wait_action", []))

	func submit_wait_action() -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.submit_wait_action", []))

	func process_auto_tick(delta: float) -> void:
		_call_timed("PlayerCommandCoordinator.process_auto_tick", [delta])

	func submit_auto_tick_wait() -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.submit_auto_tick_wait", []))

	func continue_active_crafting_runner(reason: String = "crafting_continue") -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.continue_active_crafting_runner", [reason]))

	func runtime_has_pending_action() -> bool:
		return bool(_call_timed("PlayerCommandCoordinator.runtime_has_pending_action", []))

	func apply_wait_action_operation(operation: Dictionary, refresh_reason: String) -> Dictionary:
		return _dictionary_or_empty(_call_timed("PlayerCommandCoordinator.apply_wait_action_operation", [operation, refresh_reason]))

	func _call_timed(function_name: String, args: Array) -> Variant:
		var started := Time.get_ticks_usec()
		var result: Variant = null
		if target != null and target.has_method(function_name.get_slice(".", 1)):
			result = target.callv(function_name.get_slice(".", 1), args)
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		if recorder.is_valid():
			recorder.call(function_name, elapsed, _result_extra(result))
		return result

	func _result_extra(result: Variant) -> Dictionary:
		if typeof(result) != TYPE_DICTIONARY:
			return {}
		return {
			"success": bool(result.get("success", true)),
			"phase": str(result.get("phase", "")),
			"reason": str(result.get("reason", "")),
		}

	func _dictionary_or_empty(value: Variant) -> Dictionary:
		return value if typeof(value) == TYPE_DICTIONARY else {}


class _TimedRuntimeInputControllerProxy:
	extends RefCounted

	var target: RefCounted
	var recorder: Callable
	var game_root: Node:
		get:
			return target.get("game_root") if target != null else null
		set(value):
			if target != null:
				target.set("game_root", value)
	var world_container: Node3D:
		get:
			return target.get("world_container") as Node3D if target != null else null
		set(value):
			if target != null:
				target.set("world_container", value)
	var world_result: Dictionary:
		get:
			return _dictionary_or_empty(target.get("world_result")) if target != null else {}
		set(value):
			if target != null:
				target.set("world_result", value.duplicate(true))
	var camera: Camera3D:
		get:
			return target.get("camera") as Camera3D if target != null else null
		set(value):
			if target != null:
				target.set("camera", value)

	func _init(p_target: RefCounted, p_recorder: Callable) -> void:
		target = p_target
		recorder = p_recorder

	func attach_world(p_world_container: Node3D, p_world_result: Dictionary) -> void:
		_call_timed("GameRuntimeInputController.attach_world", [p_world_container, p_world_result])

	func process(delta: float) -> void:
		_call_timed("GameRuntimeInputController.process", [delta])

	func input(event: InputEvent) -> void:
		_call_timed("GameRuntimeInputController.input", [event])

	func unhandled_input(event: InputEvent) -> void:
		_call_timed("GameRuntimeInputController.unhandled_input", [event])

	func mouse_over_blocking_ui() -> bool:
		return bool(_call_timed("GameRuntimeInputController.mouse_over_blocking_ui", []))

	func camera_drag_active() -> bool:
		return bool(_call_timed("GameRuntimeInputController.camera_drag_active", []))

	func camera_drag_allowed_while_gameplay_blocked() -> bool:
		return bool(_call_timed("GameRuntimeInputController.camera_drag_allowed_while_gameplay_blocked", []))

	func close_context_menu_on_outside_click(mouse_event: InputEventMouseButton) -> bool:
		return bool(_call_timed("GameRuntimeInputController.close_context_menu_on_outside_click", [mouse_event]))

	func handle_world_mouse_motion(mouse_event: InputEventMouseMotion) -> void:
		_call_timed("GameRuntimeInputController.handle_world_mouse_motion", [mouse_event])

	func handle_world_mouse_button(mouse_event: InputEventMouseButton) -> bool:
		return bool(_call_timed("GameRuntimeInputController.handle_world_mouse_button", [mouse_event]))

	func update_hover_at_screen_position(screen_position: Vector2) -> Dictionary:
		return _dictionary_or_empty(_call_timed("GameRuntimeInputController.update_hover_at_screen_position", [screen_position]))

	func hover_state_snapshot() -> Dictionary:
		return _dictionary_or_empty(_call_timed("GameRuntimeInputController.hover_state_snapshot", []))

	func selection_debug_snapshot() -> Dictionary:
		return _dictionary_or_empty(_call_timed("GameRuntimeInputController.selection_debug_snapshot", []))

	func camera_follow_snapshot() -> Dictionary:
		return _dictionary_or_empty(_call_timed("GameRuntimeInputController.camera_follow_snapshot", []))

	func clear_selection_state(reason: String = "cleared") -> Dictionary:
		return _dictionary_or_empty(_call_timed("GameRuntimeInputController.clear_selection_state", [reason]))

	func update_skill_target_preview_markers(preview: Dictionary) -> void:
		_call_timed("GameRuntimeInputController.update_skill_target_preview_markers", [preview])

	func focus_current_actor() -> void:
		_call_timed("GameRuntimeInputController.focus_current_actor", [])

	func handle_space_key_pressed() -> bool:
		return bool(_call_timed("GameRuntimeInputController.handle_space_key_pressed", []))

	func stop_space_wait_hold() -> void:
		_call_timed("GameRuntimeInputController.stop_space_wait_hold", [])

	func scale_camera_zoom(multiplier: float) -> void:
		_call_timed("GameRuntimeInputController.scale_camera_zoom", [multiplier])

	func reset_camera_zoom() -> void:
		_call_timed("GameRuntimeInputController.reset_camera_zoom", [])

	func _call_timed(function_name: String, args: Array) -> Variant:
		var started := Time.get_ticks_usec()
		var result: Variant = null
		if target != null and target.has_method(function_name.get_slice(".", 1)):
			result = target.callv(function_name.get_slice(".", 1), args)
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		if recorder.is_valid():
			recorder.call(function_name, elapsed, _result_extra(result))
		return result

	func _result_extra(result: Variant) -> Dictionary:
		if typeof(result) != TYPE_DICTIONARY:
			return {}
		return {
			"success": bool(result.get("success", true)),
			"kind": str(result.get("kind", "")),
			"reason": str(result.get("reason", "")),
		}

	func _dictionary_or_empty(value: Variant) -> Dictionary:
		return value if typeof(value) == TYPE_DICTIONARY else {}
