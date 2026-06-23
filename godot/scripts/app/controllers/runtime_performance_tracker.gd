extends RefCounted

var frame_time_ms: float = 0.0
var fps: float = 0.0
var last_process_tick_msec: int = 0
var last_hud_refresh_tick_msec: int = 0
var last_render_counts: Dictionary = {}
var render_sequence: int = 0


func update_process(delta: float) -> void:
	last_process_tick_msec = Time.get_ticks_msec()
	frame_time_ms = max(0.0, delta * 1000.0)
	var current_fps: float = Performance.get_monitor(Performance.TIME_FPS)
	if current_fps <= 0.0 and delta > 0.0:
		current_fps = 1.0 / delta
	fps = max(0.0, current_fps)


func mark_hud_refresh() -> void:
	last_hud_refresh_tick_msec = Time.get_ticks_msec()


func record_world_render(counts: Dictionary, world_root: Node) -> void:
	if world_root != null and world_root.has_method("render_count_summary"):
		last_render_counts = _dictionary_or_empty(world_root.call("render_count_summary"))
	else:
		last_render_counts = _render_count_summary(counts)
	if world_root != null and world_root.get("render_sequence") != null:
		render_sequence = int(world_root.get("render_sequence"))
	else:
		render_sequence += 1


func snapshot(pathfinding_result: Dictionary) -> Dictionary:
	var now_msec: int = Time.get_ticks_msec()
	var resolved_fps := fps
	if resolved_fps <= 0.0:
		resolved_fps = float(Engine.get_frames_per_second())
	if resolved_fps <= 0.0:
		resolved_fps = 60.0
	var rendered_object_count := _rendered_object_count(last_render_counts)
	var pathfinding: Dictionary = _dictionary_or_empty(pathfinding_result)
	return {
		"fps": resolved_fps,
		"frame_time_ms": frame_time_ms,
		"pathfinding_time_ms": float(pathfinding.get("pathfinding_time_ms", 0.0)),
		"pathfinding_visited_cell_count": int(pathfinding.get("visited_cell_count", 0)),
		"pathfinding_expanded_cell_count": int(pathfinding.get("expanded_cell_count", 0)),
		"pathfinding_max_frontier_size": int(pathfinding.get("max_frontier_size", 0)),
		"pathfinding_algorithm": str(pathfinding.get("algorithm", "")),
		"pathfinding_goal_count": int(pathfinding.get("goal_count", 0)),
		"pathfinding_cache_hit": bool(pathfinding.get("cache_hit", false)),
		"pathfinding_budget_exceeded": bool(pathfinding.get("budget_exceeded", false)),
		"pathfinding_over_profiler_budget": bool(pathfinding.get("over_profiler_budget", false)),
		"pathfinding_profiler_budget_ms": float(pathfinding.get("profiler_budget_ms", 0.0)),
		"pathfinding_search_call_count": int(pathfinding.get("search_call_count", 0)),
		"pathfinding_search_execution_count": int(pathfinding.get("search_execution_count", 0)),
		"last_process_tick_msec": last_process_tick_msec,
		"last_hud_refresh_tick_msec": last_hud_refresh_tick_msec,
		"hud_latency_ms": max(0, now_msec - last_hud_refresh_tick_msec) if last_hud_refresh_tick_msec > 0 else 0,
		"render_sequence": render_sequence,
		"render_counts": last_render_counts.duplicate(true),
		"render_count": int(last_render_counts.get("total", 0)),
		"actor_count": int(last_render_counts.get("actors", 0)),
		"object_count": rendered_object_count,
		"collider_count": int(last_render_counts.get("colliders", 0)),
		"light_count": int(last_render_counts.get("lights", 0)),
		"camera_count": int(last_render_counts.get("cameras", 0)),
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _render_count_summary(counts: Dictionary) -> Dictionary:
	var summary: Dictionary = counts.duplicate(true)
	var total := 0
	for value in counts.values():
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			total += int(value)
	summary["total"] = total
	return summary


func _rendered_object_count(counts: Dictionary) -> int:
	if counts.has("objects"):
		return int(counts.get("objects", 0))
	var total := 0
	for key in ["interaction_targets", "markers", "corpses"]:
		total += int(counts.get(key, 0))
	return total
