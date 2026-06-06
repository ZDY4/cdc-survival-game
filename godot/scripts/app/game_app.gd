extends Node3D

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")
const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")
const FogOverlayController = preload("res://scripts/world/fog_overlay_controller.gd")
const DebugOverlayController = preload("res://scripts/world/debug_overlay_controller.gd")
const DebugConsoleCommandRunner = preload("res://scripts/app/debug_console_command_runner.gd")
const GamePanelController = preload("res://scripts/app/controllers/game_panel_controller.gd")
const GameRuntimeInputController = preload("res://scripts/app/controllers/game_runtime_input_controller.gd")
const PlayerInteractionController = preload("res://scripts/app/controllers/player_interaction_controller.gd")
const AUTO_TICK_INTERVAL_SEC := 0.45
const OBSERVE_SPEEDS: Array[Dictionary] = [
	{"id": "x1", "multiplier": 1.0},
	{"id": "x2", "multiplier": 2.0},
	{"id": "x5", "multiplier": 5.0},
	{"id": "x10", "multiplier": 10.0},
]

var registry: ContentRegistry
var simulation: RefCounted
var world_result: Dictionary = {}
var interaction_controller: RefCounted
var runtime_input_controller: RefCounted
var panel_controller: RefCounted
var fog_overlay_controller: RefCounted = FogOverlayController.new()
var debug_overlay_controller: RefCounted = DebugOverlayController.new()
var world_container: Node3D
var fog_overlay: ColorRect
var hud: Control
var dialogue_panel: Control
var inventory_panel: Control
var trade_panel: Control
var container_panel: Control
var character_panel: Control
var journal_panel: Control
var map_panel: Control
var skills_panel: Control
var crafting_panel: Control
var settings_panel: Control
var active_trade_target: Dictionary = {}
var active_trade_feedback: Dictionary = {}
var active_container_feedback: Dictionary = {}
var active_character_feedback: Dictionary = {}
var active_inventory_feedback: Dictionary = {}
var debug_overlay_mode: String = "off"
var info_panel_pages: Array[Dictionary] = [
	{"id": "overview", "title": "Overview", "tab_label": "Overview"},
	{"id": "selection", "title": "Selection", "tab_label": "Select"},
	{"id": "actor", "title": "Selected Actor", "tab_label": "Actor"},
	{"id": "world", "title": "World", "tab_label": "World"},
	{"id": "interaction", "title": "Interaction", "tab_label": "Interact"},
	{"id": "turn_sys", "title": "Turn System", "tab_label": "Turn"},
	{"id": "events", "title": "Events", "tab_label": "Events"},
	{"id": "ai", "title": "AI", "tab_label": "AI"},
	{"id": "performance", "title": "Performance", "tab_label": "Perf"},
]
var active_info_panel_index: int = 0
var auto_tick_enabled := false
var auto_tick_elapsed_sec := 0.0
var observe_mode_enabled := false
var observe_speed_id := "x1"
var focused_actor_id: int = 0
var observed_map_level: int = 0
var active_skill_targeting: Dictionary = {}
var active_skill_target_preview: Dictionary = {}
var performance_frame_time_ms: float = 0.0
var performance_fps: float = 0.0
var performance_last_process_tick_msec: int = 0
var performance_last_hud_refresh_tick_msec: int = 0
var performance_last_render_counts: Dictionary = {}
var performance_render_sequence: int = 0
var _debug_console_command_runner := DebugConsoleCommandRunner.new()


func _ready() -> void:
	registry = ContentRegistry.new()
	var load_result := registry.load_all()
	if load_result.has_errors():
		push_error("failed to load content for Godot game root")
		for error in load_result.errors:
			push_error(error)
		return

	var startup_request := _consume_startup_request()
	var runtime_result: Dictionary = _build_runtime_from_startup_request(startup_request)
	simulation = runtime_result.get("simulation")
	var runtime_snapshot: Dictionary = runtime_result.get("snapshot", {})
	world_result = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(runtime_snapshot)
	if not bool(world_result.get("ok", false)):
		push_error(str(world_result.get("error", "world build failed")))
		return
	_sync_observed_level_to_map()

	interaction_controller = PlayerInteractionController.new(registry, simulation, world_result)
	_setup_world_container()
	var counts: Dictionary = _render_world()
	_setup_runtime_input_controller()
	_refresh_fog_overlay()
	_refresh_debug_overlay()
	_setup_panels()
	refresh_all_panels()
	print("Godot game root generated world: %s" % JSON.stringify(counts))


func _consume_startup_request() -> Dictionary:
	var request: Dictionary = _dictionary_or_empty(ProjectSettings.get_setting("cdc/startup_request", {})).duplicate(true)
	if not request.is_empty():
		ProjectSettings.set_setting("cdc/startup_request", {})
	return request


func _build_runtime_from_startup_request(request: Dictionary) -> Dictionary:
	var runtime_result: Dictionary = CoreRuntimeBootstrap.new(registry).build_new_game_runtime()
	var mode := str(request.get("mode", "new_game"))
	if mode != "continue":
		return runtime_result
	var snapshot: Dictionary = _dictionary_or_empty(request.get("runtime_snapshot", {}))
	var loaded_simulation: RefCounted = runtime_result.get("simulation")
	if loaded_simulation == null or snapshot.is_empty():
		push_warning("继续游戏请求缺少有效快照，回退到新游戏")
		return runtime_result
	loaded_simulation.load_snapshot(snapshot)
	return {
		"ok": true,
		"simulation": loaded_simulation,
		"snapshot": loaded_simulation.snapshot(),
	}


func _process(delta: float) -> void:
	_update_runtime_performance(delta)
	if runtime_input_controller != null:
		runtime_input_controller.process(delta)
	_process_auto_tick(delta)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and _handle_debug_console_key(event as InputEventKey):
		get_viewport().set_input_as_handled()
		return
	if runtime_input_controller != null:
		runtime_input_controller.input(event)


func _unhandled_input(event: InputEvent) -> void:
	if runtime_input_controller != null:
		runtime_input_controller.unhandled_input(event)


func _handle_debug_console_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	var key := event.keycode
	if key == 0:
		key = event.physical_keycode
	if key == KEY_QUOTELEFT:
		toggle_debug_console()
		return true
	if is_debug_console_open() and key == KEY_ESCAPE:
		if hud != null and hud.has_method("hide_debug_console"):
			hud.hide_debug_console()
		refresh_hud(current_interaction_prompt())
		return true
	return false


func refresh_hud(selected_prompt: Dictionary = {}) -> void:
	if panel_controller == null:
		return
	performance_last_hud_refresh_tick_msec = Time.get_ticks_msec()
	if selected_prompt.is_empty():
		selected_prompt = current_interaction_prompt()
	panel_controller.refresh_hud(selected_prompt)


func refresh_dialogue_panel() -> void:
	if panel_controller == null:
		return
	panel_controller.refresh_dialogue_panel()


func refresh_inventory_panel() -> void:
	if panel_controller == null:
		return
	panel_controller.active_inventory_feedback = active_inventory_feedback
	panel_controller.refresh_inventory_panel()


func refresh_trade_panel() -> void:
	if panel_controller == null:
		return
	if not _active_trade_target_available():
		close_trade_panel("target_unavailable")
		return
	panel_controller.active_trade_target = active_trade_target
	panel_controller.active_trade_feedback = active_trade_feedback
	panel_controller.refresh_trade_panel()


func refresh_container_panel() -> void:
	if panel_controller == null:
		return
	if simulation != null:
		var close_reason := _active_container_close_reason()
		if not close_reason.is_empty():
			active_container_feedback = {}
			simulation.close_container(1, close_reason)
	panel_controller.active_container_feedback = active_container_feedback
	panel_controller.refresh_container_panel()


func refresh_character_panel() -> void:
	if panel_controller == null:
		return
	panel_controller.active_character_feedback = active_character_feedback
	panel_controller.refresh_character_panel()


func refresh_journal_panel() -> void:
	if panel_controller == null:
		return
	panel_controller.refresh_journal_panel()


func refresh_map_panel() -> void:
	if panel_controller == null:
		return
	panel_controller.refresh_map_panel()


func refresh_skills_panel() -> void:
	if panel_controller == null:
		return
	panel_controller.refresh_skills_panel()


func refresh_crafting_panel() -> void:
	if panel_controller == null:
		return
	panel_controller.refresh_crafting_panel()


func refresh_all_panels(selected_prompt: Dictionary = {}) -> void:
	refresh_hud(selected_prompt)
	refresh_dialogue_panel()
	refresh_inventory_panel()
	refresh_trade_panel()
	refresh_container_panel()
	refresh_character_panel()
	refresh_journal_panel()
	refresh_map_panel()
	refresh_skills_panel()
	refresh_crafting_panel()


func toggle_stage_panel(panel_id: String) -> Dictionary:
	if panel_controller == null:
		return {"success": false, "reason": "panel_controller_missing"}
	var result: Dictionary = panel_controller.toggle_stage_panel(panel_id)
	if bool(result.get("success", false)):
		refresh_all_panels(current_interaction_prompt())
	return result


func close_stage_panels() -> Dictionary:
	if panel_controller == null:
		return {"success": false, "reason": "panel_controller_missing"}
	return panel_controller.close_stage_panels()


func any_stage_panel_open() -> bool:
	return panel_controller != null and panel_controller.any_stage_panel_open()


func is_settings_open() -> bool:
	return panel_controller != null and panel_controller.is_settings_open()


func gameplay_input_blocked_by_ui() -> bool:
	if is_debug_console_open():
		return true
	if panel_controller != null and panel_controller.gameplay_input_blocked():
		return true
	return hud != null and hud.has_method("is_interaction_menu_open") and bool(hud.is_interaction_menu_open())


func gameplay_input_blocker_name() -> String:
	if is_debug_console_open():
		return "debug_console"
	if hud != null and hud.has_method("is_interaction_menu_open") and bool(hud.is_interaction_menu_open()):
		return "interaction_menu"
	if panel_controller != null and panel_controller.has_method("gameplay_input_blocker_name"):
		return str(panel_controller.gameplay_input_blocker_name())
	return ""


func handle_trade_shortcut(event: InputEventKey) -> bool:
	if panel_controller == null:
		return false
	return panel_controller.handle_trade_shortcut(event)


func toggle_controls_hint() -> Dictionary:
	if hud == null or not hud.has_method("toggle_controls_hint"):
		return {"success": false, "reason": "hud_missing"}
	var result: Dictionary = hud.toggle_controls_hint()
	refresh_hud(current_interaction_prompt())
	return result


func controls_hint_visible() -> bool:
	return hud != null and hud.has_method("is_controls_hint_visible") and bool(hud.is_controls_hint_visible())


func toggle_debug_console() -> Dictionary:
	if hud == null or not hud.has_method("toggle_debug_console"):
		return {"success": false, "reason": "hud_missing"}
	var result: Dictionary = hud.toggle_debug_console()
	refresh_hud(current_interaction_prompt())
	return result


func is_debug_console_open() -> bool:
	return hud != null and hud.has_method("is_debug_console_open") and bool(hud.is_debug_console_open())


func debug_console_snapshot() -> Dictionary:
	if hud != null and hud.has_method("debug_console_snapshot"):
		return hud.debug_console_snapshot()
	return {"visible": false, "history": [], "history_count": 0, "suggestions": [], "suggestion_count": 0, "input_text": ""}


func submit_debug_console_command(command_text: String) -> Dictionary:
	var command := command_text.strip_edges()
	var result: Dictionary = _execute_debug_console_command(command)
	if hud != null and hud.has_method("set_debug_console_result"):
		hud.set_debug_console_result(command, result)
	refresh_all_panels(current_interaction_prompt())
	return result


func _execute_debug_console_command(command: String) -> Dictionary:
	var normalized := command.to_lower().strip_edges()
	var debug_result: Dictionary = _debug_console_command_runner.execute(self, command)
	if not debug_result.is_empty():
		return debug_result
	match normalized:
		"":
			return {"success": false, "reason": "empty_command", "message": "empty command"}
		"help":
			return {"success": true, "message": "commands: help, show fps, show overlays, observe mode, clear, restart, give item <id> [count], teleport <x> <z> [y], spawn <character_id> [x z y], unlock location <id>"}
		"show fps":
			var perf: Dictionary = runtime_performance_snapshot()
			return {"success": true, "message": "fps=%d frame=%.1fms path=%.2fms" % [
				int(round(float(perf.get("fps", 0.0)))),
				float(perf.get("frame_time_ms", 0.0)),
				float(perf.get("pathfinding_time_ms", 0.0)),
			]}
		"show overlays":
			var overlay_result: Dictionary = cycle_debug_overlay_mode()
			return {"success": bool(overlay_result.get("success", false)), "message": "overlay=%s" % str(overlay_result.get("mode", debug_overlay_mode))}
		"observe mode":
			var observe_result: Dictionary = toggle_observe_mode()
			return {"success": bool(observe_result.get("success", false)), "message": "observe=%s" % ("on" if bool(observe_result.get("observe_mode", observe_mode_enabled)) else "off")}
		"clear":
			if hud != null and hud.has_method("clear_debug_console_history"):
				hud.clear_debug_console_history()
			return {"success": true, "message": "console cleared"}
	return {"success": false, "reason": "unknown_command", "message": "unknown command: %s" % command}


func controls_hint_snapshot() -> Dictionary:
	if hud != null and hud.has_method("controls_hint_snapshot"):
		return hud.controls_hint_snapshot()
	return {"visible": false, "line_count": 0, "lines": []}


func toggle_debug_panel() -> Dictionary:
	if hud == null or not hud.has_method("toggle_debug_panel"):
		return {"success": false, "reason": "hud_missing"}
	var result: Dictionary = hud.toggle_debug_panel()
	refresh_hud(current_interaction_prompt())
	return result


func is_debug_panel_open() -> bool:
	return hud != null and hud.has_method("is_debug_panel_open") and bool(hud.is_debug_panel_open())


func debug_panel_snapshot() -> Dictionary:
	if hud != null and hud.has_method("debug_panel_snapshot"):
		return hud.debug_panel_snapshot()
	return {"visible": false, "line_count": 0, "lines": []}


func cycle_debug_overlay_mode() -> Dictionary:
	var modes := ["off", "walkable", "vision", "blocked_sight", "level"]
	var index := modes.find(debug_overlay_mode)
	if index < 0:
		index = 0
	debug_overlay_mode = modes[(index + 1) % modes.size()]
	_refresh_debug_overlay()
	refresh_hud(current_interaction_prompt())
	return {"success": true, "mode": debug_overlay_mode}


func current_debug_overlay_mode() -> String:
	return debug_overlay_mode


func debug_overlay_snapshot() -> Dictionary:
	if debug_overlay_controller != null and debug_overlay_controller.has_method("snapshot"):
		return debug_overlay_controller.snapshot()
	return {"active": false, "mode": "off", "cell_count": 0}


func toggle_auto_tick() -> Dictionary:
	if observe_mode_enabled:
		return toggle_observe_playback()
	if has_active_dialogue() or gameplay_input_blocked_by_ui():
		return {"success": false, "reason": "ui_blocked", "enabled": auto_tick_enabled}
	auto_tick_enabled = not auto_tick_enabled
	auto_tick_elapsed_sec = 0.0
	refresh_hud(current_interaction_prompt())
	return {"success": true, "enabled": auto_tick_enabled}


func is_auto_tick_enabled() -> bool:
	return auto_tick_enabled


func is_observe_mode_enabled() -> bool:
	return observe_mode_enabled


func can_issue_player_commands() -> bool:
	return not observe_mode_enabled


func toggle_observe_mode() -> Dictionary:
	return set_observe_mode(not observe_mode_enabled)


func set_observe_mode(enabled: bool) -> Dictionary:
	if gameplay_input_blocked_by_ui():
		return {"success": false, "reason": "ui_blocked", "observe_mode": observe_mode_enabled}
	observe_mode_enabled = enabled
	if not observe_mode_enabled:
		auto_tick_enabled = false
		auto_tick_elapsed_sec = 0.0
	refresh_hud(current_interaction_prompt())
	return {
		"success": true,
		"observe_mode": observe_mode_enabled,
		"observe_playback": _observe_playback_enabled(),
		"observe_speed": observe_speed_id,
	}


func toggle_observe_playback() -> Dictionary:
	if not observe_mode_enabled:
		return {"success": false, "reason": "observe_mode_disabled", "observe_playback": false}
	if has_active_dialogue() or gameplay_input_blocked_by_ui():
		return {"success": false, "reason": "ui_blocked", "observe_playback": _observe_playback_enabled()}
	auto_tick_enabled = not auto_tick_enabled
	auto_tick_elapsed_sec = 0.0
	refresh_hud(current_interaction_prompt())
	return {
		"success": true,
		"observe_playback": _observe_playback_enabled(),
		"auto_tick": auto_tick_enabled,
		"observe_speed": observe_speed_id,
	}


func cycle_observe_speed() -> Dictionary:
	if not observe_mode_enabled:
		return {"success": false, "reason": "observe_mode_disabled", "observe_speed": observe_speed_id}
	var current_index := _observe_speed_index(observe_speed_id)
	var next_index := (current_index + 1) % OBSERVE_SPEEDS.size()
	return set_observe_speed(str(OBSERVE_SPEEDS[next_index].get("id", "x1")))


func set_observe_speed(speed_id: String) -> Dictionary:
	if not observe_mode_enabled:
		return {"success": false, "reason": "observe_mode_disabled", "observe_speed": observe_speed_id}
	var normalized := speed_id.strip_edges().to_lower()
	if _observe_speed_index(normalized) < 0:
		return {"success": false, "reason": "unknown_observe_speed", "observe_speed": observe_speed_id}
	observe_speed_id = normalized
	auto_tick_elapsed_sec = 0.0
	refresh_hud(current_interaction_prompt())
	return {
		"success": true,
		"observe_speed": observe_speed_id,
		"interval_sec": _auto_tick_interval_sec(),
	}


func cycle_info_panel(direction: int) -> Dictionary:
	if info_panel_pages.size() <= 1:
		return {"success": false, "reason": "not_enough_info_pages"}
	active_info_panel_index = posmod(active_info_panel_index + direction, info_panel_pages.size())
	refresh_hud(current_interaction_prompt())
	var page := current_info_panel_page()
	return {
		"success": true,
		"page_id": page.get("id", ""),
		"title": page.get("title", ""),
		"index": active_info_panel_index,
		"count": info_panel_pages.size(),
	}


func current_info_panel_page() -> Dictionary:
	if info_panel_pages.is_empty():
		return {}
	active_info_panel_index = clampi(active_info_panel_index, 0, info_panel_pages.size() - 1)
	return info_panel_pages[active_info_panel_index].duplicate(true)


func info_panel_snapshot() -> Dictionary:
	var page := current_info_panel_page()
	return {
		"active_page": page,
		"enabled_pages": info_panel_pages.duplicate(true),
		"active_index": active_info_panel_index,
		"count": info_panel_pages.size(),
	}


func runtime_control_snapshot() -> Dictionary:
	return {
		"auto_tick": auto_tick_enabled,
		"observe_mode": observe_mode_enabled,
		"observe_playback": _observe_playback_enabled(),
		"observe_speed": observe_speed_id,
		"observe_speed_multiplier": _observe_speed_multiplier(),
		"observe_interval_sec": _auto_tick_interval_sec(),
		"map_level": map_level_snapshot(),
		"focused_actor": focused_actor_snapshot(),
		"ui_blocker": gameplay_input_blocker_name(),
		"controls_hint": controls_hint_snapshot(),
		"debug_console": debug_console_snapshot(),
		"debug_panel": debug_panel_snapshot(),
		"hover": runtime_hover_snapshot(),
		"selection_debug": runtime_selection_debug_snapshot(),
		"ai_debug": ai_debug_snapshot(),
		"debug_overlay": debug_overlay_snapshot(),
		"performance": runtime_performance_snapshot(),
		"skill_targeting": _skill_targeting_snapshot(),
	}


func ai_debug_snapshot() -> Dictionary:
	if simulation == null:
		return {"intent_count": 0, "intents": [], "focused_intent": {}}
	var runtime_snapshot: Dictionary = simulation.snapshot()
	var focused_actor: Dictionary = focused_actor_snapshot()
	var focused_actor_id := int(focused_actor.get("actor_id", 0))
	var intents: Array[Dictionary] = []
	var focused_intent: Dictionary = {}
	for entry in _array_or_empty(runtime_snapshot.get("ai_intents", [])):
		var intent: Dictionary = _ai_debug_intent_summary(_dictionary_or_empty(entry))
		if intent.is_empty():
			continue
		if focused_actor_id > 0 and int(intent.get("actor_id", 0)) == focused_actor_id:
			focused_intent = intent.duplicate(true)
		intents.append(intent)
	var latest: Dictionary = intents[intents.size() - 1].duplicate(true) if not intents.is_empty() else {}
	return {
		"intent_count": intents.size(),
		"intents": intents,
		"focused_actor_id": focused_actor_id,
		"focused_intent": focused_intent,
		"latest_intent": latest,
	}


func _ai_debug_intent_summary(intent: Dictionary) -> Dictionary:
	var actor_id := int(intent.get("actor_id", 0))
	if actor_id <= 0:
		return {}
	return {
		"actor_id": actor_id,
		"intent": str(intent.get("intent", "")),
		"reason": str(intent.get("reason", "")),
		"target_actor_id": int(intent.get("target_actor_id", 0)),
		"target_grid": _dictionary_or_empty(intent.get("target_grid", {})).duplicate(true),
		"path_length": _array_or_empty(intent.get("path", [])).size(),
		"ap": float(intent.get("ap", 0.0)),
		"distance": float(intent.get("distance", -1.0)),
		"aggro_range": float(intent.get("aggro_range", 0.0)),
		"attack_range": float(intent.get("attack_range", 0.0)),
		"weapon_item_id": str(intent.get("weapon_item_id", "")),
		"ammo_type": str(intent.get("ammo_type", "")),
		"ammo_ready": bool(intent.get("ammo_ready", true)),
		"can_reload": bool(intent.get("can_reload", false)),
		"failure_reason": str(intent.get("failure_reason", intent.get("reason", ""))),
	}


func runtime_performance_snapshot() -> Dictionary:
	var now_msec: int = Time.get_ticks_msec()
	var fps: float = performance_fps
	if fps <= 0.0:
		fps = float(Engine.get_frames_per_second())
	if fps <= 0.0:
		fps = 60.0
	return {
		"fps": fps,
		"frame_time_ms": performance_frame_time_ms,
		"pathfinding_time_ms": _last_pathfinding_time_ms(),
		"pathfinding_visited_cell_count": _last_pathfinding_visited_cell_count(),
		"last_process_tick_msec": performance_last_process_tick_msec,
		"last_hud_refresh_tick_msec": performance_last_hud_refresh_tick_msec,
		"hud_latency_ms": max(0, now_msec - performance_last_hud_refresh_tick_msec) if performance_last_hud_refresh_tick_msec > 0 else 0,
		"render_sequence": performance_render_sequence,
		"render_counts": performance_last_render_counts.duplicate(true),
		"render_count": int(performance_last_render_counts.get("total", 0)),
		"actor_count": int(performance_last_render_counts.get("actors", 0)),
		"object_count": int(performance_last_render_counts.get("objects", 0)),
		"collider_count": int(performance_last_render_counts.get("colliders", 0)),
		"light_count": int(performance_last_render_counts.get("lights", 0)),
		"camera_count": int(performance_last_render_counts.get("cameras", 0)),
	}


func runtime_hover_snapshot() -> Dictionary:
	if runtime_input_controller != null and runtime_input_controller.has_method("hover_state_snapshot"):
		return runtime_input_controller.hover_state_snapshot()
	return {"active": false}


func runtime_selection_debug_snapshot() -> Dictionary:
	if runtime_input_controller != null and runtime_input_controller.has_method("selection_debug_snapshot"):
		return runtime_input_controller.selection_debug_snapshot()
	return {"active": false, "kind": "", "hovered_grid": {}, "blocker_name": "", "prompt": {"has_prompt": false}}


func _update_runtime_performance(delta: float) -> void:
	performance_last_process_tick_msec = Time.get_ticks_msec()
	performance_frame_time_ms = max(0.0, delta * 1000.0)
	var current_fps: float = Performance.get_monitor(Performance.TIME_FPS)
	if current_fps <= 0.0 and delta > 0.0:
		current_fps = 1.0 / delta
	performance_fps = max(0.0, current_fps)


func _last_pathfinding_time_ms() -> float:
	var hover: Dictionary = runtime_hover_snapshot()
	var move_preview: Dictionary = _dictionary_or_empty(hover.get("move_preview", {}))
	return float(move_preview.get("pathfinding_time_ms", 0.0))


func _last_pathfinding_visited_cell_count() -> int:
	var hover: Dictionary = runtime_hover_snapshot()
	var move_preview: Dictionary = _dictionary_or_empty(hover.get("move_preview", {}))
	return int(move_preview.get("visited_cell_count", 0))


func settings_applied(_snapshot: Dictionary = {}) -> void:
	if panel_controller != null and panel_controller.has_method("apply_ui_scale"):
		panel_controller.apply_ui_scale()


func current_map_level() -> int:
	observed_map_level = _normalized_map_level(observed_map_level)
	return observed_map_level


func map_level_snapshot() -> Dictionary:
	return {
		"current": current_map_level(),
		"default": _default_map_level(),
		"available": _available_map_levels(),
	}


func change_observed_level(direction: int) -> Dictionary:
	var levels: Array[int] = _available_map_levels()
	if levels.is_empty():
		return {"success": false, "reason": "map_level_missing", "current": observed_map_level}
	var current_level := current_map_level()
	var current_index := levels.find(current_level)
	if current_index < 0:
		current_index = 0
	var step := 1 if direction > 0 else -1 if direction < 0 else 0
	var next_index := clampi(current_index + step, 0, levels.size() - 1)
	var next_level := int(levels[next_index])
	var changed := next_level != observed_map_level
	observed_map_level = next_level
	if runtime_input_controller != null and runtime_input_controller.has_method("focus_current_actor"):
		runtime_input_controller.focus_current_actor()
	refresh_hud(current_interaction_prompt())
	return {
		"success": true,
		"changed": changed,
		"current": observed_map_level,
		"available": levels,
	}


func cycle_focused_actor() -> Dictionary:
	if panel_controller != null and panel_controller.gameplay_input_blocked():
		return {"success": false, "reason": "ui_blocked", "actor_id": focused_actor_id}
	var focused_actor: Dictionary = _focused_actor_data()
	var busy_state: Dictionary = _focused_actor_busy_state(focused_actor)
	if not observe_mode_enabled and not busy_state.is_empty():
		return {
			"success": false,
			"reason": "actor_busy",
			"actor_id": int(focused_actor.get("actor_id", focused_actor_id)),
			"busy": busy_state,
		}
	var candidates: Array[Dictionary] = _focus_actor_candidates()
	if candidates.is_empty():
		return {"success": false, "reason": "focus_actor_missing", "actor_id": focused_actor_id}
	var current_index := -1
	for index in range(candidates.size()):
		if int(candidates[index].get("actor_id", 0)) == focused_actor_id:
			current_index = index
			break
	var next_actor: Dictionary = candidates[(current_index + 1) % candidates.size()]
	focused_actor_id = int(next_actor.get("actor_id", 0))
	_clear_focus_switch_ui_state()
	if runtime_input_controller != null and runtime_input_controller.has_method("focus_current_actor"):
		runtime_input_controller.focus_current_actor()
	refresh_hud(current_interaction_prompt())
	return {"success": true, "actor": next_actor.duplicate(true), "actor_id": focused_actor_id}


func focus_actor(actor_id: int) -> Dictionary:
	if panel_controller != null and panel_controller.gameplay_input_blocked():
		return {"success": false, "reason": "ui_blocked", "actor_id": focused_actor_id}
	var candidates: Array[Dictionary] = _focus_actor_candidates()
	for candidate in candidates:
		if int(candidate.get("actor_id", 0)) != actor_id:
			continue
		var busy_state: Dictionary = _focused_actor_busy_state(candidate)
		if not observe_mode_enabled and not busy_state.is_empty():
			return {
				"success": false,
				"reason": "actor_busy",
				"actor_id": actor_id,
				"busy": busy_state,
			}
		focused_actor_id = actor_id
		_clear_focus_switch_ui_state()
		if runtime_input_controller != null and runtime_input_controller.has_method("focus_current_actor"):
			runtime_input_controller.focus_current_actor()
		refresh_hud(current_interaction_prompt())
		return {"success": true, "actor": candidate.duplicate(true), "actor_id": focused_actor_id}
	return {"success": false, "reason": "focus_actor_missing", "actor_id": actor_id}


func focused_actor_snapshot() -> Dictionary:
	var actor: Dictionary = _focused_actor_data()
	if actor.is_empty():
		return {}
	return {
		"actor_id": int(actor.get("actor_id", 0)),
		"definition_id": str(actor.get("definition_id", "")),
		"display_name": str(actor.get("display_name", "")),
		"kind": str(actor.get("kind", "")),
		"side": str(actor.get("side", "")),
		"grid_position": _dictionary_or_empty(actor.get("grid_position", {})).duplicate(true),
	}


func focused_actor_grid_position() -> Dictionary:
	return _dictionary_or_empty(focused_actor_snapshot().get("grid_position", {})).duplicate(true)


func close_active_dialogue(reason: String = "closed") -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = simulation.close_dialogue(1, reason)
	if bool(result.get("success", false)):
		close_trade_panel("dialogue_closed:%s" % reason)
		refresh_dialogue_panel()
		refresh_hud()
	return result


func close_active_container(reason: String = "closed") -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = simulation.close_container(1, reason)
	if bool(result.get("success", false)):
		active_container_feedback = {}
		refresh_container_panel()
		refresh_hud()
	return result


func close_active_ui(reason: String = "closed") -> Dictionary:
	if is_debug_console_open():
		if hud != null and hud.has_method("hide_debug_console"):
			hud.hide_debug_console()
		refresh_hud(current_interaction_prompt())
		return {"success": true, "closed": "debug_console"}
	if not active_skill_targeting.is_empty():
		return cancel_active_skill_targeting(reason)
	if runtime_input_controller != null and runtime_input_controller.has_method("has_selection_state") and bool(runtime_input_controller.has_selection_state()):
		runtime_input_controller.clear_selection_state()
		return {"success": true, "closed": "selection"}
	if hud != null and hud.has_method("is_interaction_menu_open") and bool(hud.is_interaction_menu_open()):
		hud.hide_interaction_menu()
		return {"success": true, "closed": "interaction_menu"}
	if runtime_input_controller != null:
		runtime_input_controller.clear_selection_state()
	if panel_controller != null and panel_controller.has_method("close_blocking_modal"):
		var modal_result: Dictionary = panel_controller.call("close_blocking_modal")
		if bool(modal_result.get("success", false)):
			return {"success": true, "closed": str(modal_result.get("closed", "modal")), "result": modal_result}
	var dialogue_result := close_active_dialogue(reason)
	if bool(dialogue_result.get("success", false)):
		return {"success": true, "closed": "dialogue", "result": dialogue_result}
	if not active_trade_target.is_empty():
		close_trade_panel(reason)
		return {"success": true, "closed": "trade"}
	var container_result := close_active_container(reason)
	if bool(container_result.get("success", false)):
		return {"success": true, "closed": "container", "result": container_result}
	if any_stage_panel_open():
		close_stage_panels()
		return {"success": true, "closed": "stage_panel"}
	if is_settings_open():
		panel_controller.close_settings_panel()
		refresh_all_panels(current_interaction_prompt())
		return {"success": true, "closed": "settings"}
	var pending_result: Dictionary = cancel_pending(reason, false)
	if bool(pending_result.get("had_pending", false)):
		return {"success": true, "closed": "pending", "result": pending_result}
	if panel_controller != null:
		panel_controller.open_settings_panel()
		refresh_all_panels(current_interaction_prompt())
		return {"success": true, "closed": "", "opened": "settings"}
	return {"success": false, "reason": "panel_controller_missing"}


func select_interaction_target(target: Dictionary) -> Dictionary:
	if interaction_controller == null:
		return {"success": false, "reason": "interaction_controller_missing"}
	var result: Dictionary = interaction_controller.select_target(target)
	refresh_hud(_dictionary_or_empty(result.get("prompt", {})))
	return result


func select_interaction_node(node: Node) -> Dictionary:
	if interaction_controller == null:
		return {"success": false, "reason": "interaction_controller_missing"}
	var result: Dictionary = interaction_controller.select_node(node)
	refresh_hud(_dictionary_or_empty(result.get("prompt", {})))
	return result


func clear_interaction_selection() -> Dictionary:
	if interaction_controller == null:
		return {"success": false, "reason": "interaction_controller_missing"}
	var result: Dictionary = interaction_controller.clear_selection()
	refresh_hud(_dictionary_or_empty(result.get("prompt", {})))
	return result


func execute_primary_interaction() -> Dictionary:
	if interaction_controller == null:
		return {"success": false, "reason": "interaction_controller_missing"}
	if not can_issue_player_commands():
		return _observe_command_rejected("interact")
	var executed_target: Dictionary = interaction_controller.selected_target.duplicate(true)
	var result: Dictionary = interaction_controller.execute_primary_interaction()
	_apply_interaction_execution_result(result, executed_target)
	return result


func execute_interaction_option(option_id: String) -> Dictionary:
	if interaction_controller == null:
		return {"success": false, "reason": "interaction_controller_missing"}
	if not can_issue_player_commands():
		return _observe_command_rejected("interact")
	var executed_target: Dictionary = interaction_controller.selected_target.duplicate(true)
	var result: Dictionary = interaction_controller.execute_selected_option(option_id)
	_apply_interaction_execution_result(result, executed_target)
	return result


func select_grid_target(grid: Dictionary) -> Dictionary:
	if interaction_controller == null:
		return {"success": false, "reason": "interaction_controller_missing"}
	var result: Dictionary = interaction_controller.select_grid(grid)
	refresh_hud(_dictionary_or_empty(result.get("prompt", {})))
	return result


func execute_move_to_grid(grid: Dictionary) -> Dictionary:
	if interaction_controller == null:
		return {"success": false, "reason": "interaction_controller_missing"}
	if not can_issue_player_commands():
		return _observe_command_rejected("move")
	var result: Dictionary = interaction_controller.execute_move_to_grid(grid)
	world_result = interaction_controller.world_result
	_rebuild_world_after_runtime_change(_dictionary_or_empty(result.get("prompt", {})))
	return result


func cancel_pending(reason: String = "cancelled", auto_end_turn: bool = false) -> Dictionary:
	if interaction_controller == null:
		return {"success": false, "reason": "interaction_controller_missing"}
	var result: Dictionary = interaction_controller.cancel_pending(reason, auto_end_turn)
	refresh_all_panels(current_interaction_prompt())
	return result


func current_interaction_prompt() -> Dictionary:
	if interaction_controller == null:
		return {}
	return interaction_controller.current_prompt()


func close_trade_panel(reason: String = "closed") -> void:
	var closed_target: Dictionary = active_trade_target.duplicate(true)
	active_trade_target = {}
	active_trade_feedback = {}
	if not closed_target.is_empty() and simulation != null:
		simulation.emit_event("trade_closed", _trade_closed_payload(closed_target, reason))
	refresh_trade_panel()


func choose_dialogue_option(option_ref: Variant) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = simulation.advance_dialogue(1, option_ref, registry.get_library("dialogues"))
	_apply_dialogue_trade_result(result)
	refresh_dialogue_panel()
	refresh_inventory_panel()
	refresh_trade_panel()
	refresh_journal_panel()
	refresh_skills_panel()
	refresh_crafting_panel()
	return result


func choose_dialogue_option_by_index(option_index: int) -> Dictionary:
	return choose_dialogue_option(option_index)


func advance_dialogue_without_choice() -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var dialogue_snapshot: Dictionary = _current_dialogue_snapshot()
	if not bool(dialogue_snapshot.get("active", false)):
		return {"success": false, "reason": "dialogue_session_missing"}
	if not _array_or_empty(dialogue_snapshot.get("options", [])).is_empty():
		return {
			"success": false,
			"reason": "dialogue_choice_required",
			"active_dialogue": true,
		}
	var result: Dictionary = simulation.advance_dialogue_without_choice(1, registry.get_library("dialogues"))
	_apply_dialogue_trade_result(result)
	refresh_dialogue_panel()
	refresh_inventory_panel()
	refresh_trade_panel()
	refresh_journal_panel()
	refresh_skills_panel()
	refresh_crafting_panel()
	refresh_hud()
	return result


func _apply_dialogue_trade_result(result: Dictionary) -> void:
	if not bool(result.get("success", false)):
		return
	if str(result.get("end_type", "")) == "trade":
		active_trade_target = _dialogue_trade_target(result)
		active_trade_feedback = {}
	elif bool(result.get("finished", false)) or result.has("end_type"):
		close_trade_panel("dialogue_finished:%s" % str(result.get("end_type", "")))


func has_active_dialogue() -> bool:
	if simulation == null:
		return false
	for actor in simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if actor_data.get("kind", "") == "player":
			return not str(actor_data.get("active_dialogue_id", "")).is_empty()
	return false


func press_space_action() -> Dictionary:
	if has_active_dialogue():
		return advance_dialogue_without_choice()
	if observe_mode_enabled:
		return toggle_observe_playback()
	var pending_result: Dictionary = cancel_pending("keyboard", true)
	if bool(pending_result.get("had_pending", false)):
		return pending_result
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = simulation.submit_player_command({
		"kind": "wait",
		"actor_id": 1,
		"topology": _dictionary_or_empty(world_result.get("map", {})),
	})
	if bool(result.get("success", false)):
		world_result = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
		if interaction_controller != null:
			interaction_controller.world_result = world_result
		_setup_world_container()
		_render_world()
		_setup_runtime_input_controller()
		_refresh_fog_overlay()
		_refresh_debug_overlay()
	refresh_all_panels(current_interaction_prompt())
	return result


func _process_auto_tick(delta: float) -> void:
	if not auto_tick_enabled:
		auto_tick_elapsed_sec = 0.0
		return
	auto_tick_elapsed_sec += delta
	if auto_tick_elapsed_sec < _auto_tick_interval_sec():
		return
	auto_tick_elapsed_sec = 0.0
	_submit_auto_tick_wait()


func _observe_playback_enabled() -> bool:
	return observe_mode_enabled and auto_tick_enabled


func _observe_speed_index(speed_id: String) -> int:
	for index in range(OBSERVE_SPEEDS.size()):
		if str(OBSERVE_SPEEDS[index].get("id", "")) == speed_id:
			return index
	return -1


func _observe_speed_multiplier() -> float:
	var index := _observe_speed_index(observe_speed_id)
	if index < 0:
		return 1.0
	return maxf(1.0, float(OBSERVE_SPEEDS[index].get("multiplier", 1.0)))


func _auto_tick_interval_sec() -> float:
	if not observe_mode_enabled:
		return AUTO_TICK_INTERVAL_SEC
	return maxf(0.01, AUTO_TICK_INTERVAL_SEC / _observe_speed_multiplier())


func _submit_auto_tick_wait() -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	if has_active_dialogue() or gameplay_input_blocked_by_ui():
		return {"success": false, "reason": "ui_blocked"}
	var snapshot: Dictionary = simulation.snapshot()
	if not _dictionary_or_empty(snapshot.get("pending_movement", {})).is_empty() or not _dictionary_or_empty(snapshot.get("pending_interaction", {})).is_empty():
		return {"success": false, "reason": "pending_blocked"}
	var result: Dictionary = simulation.submit_player_command({
		"kind": "wait",
		"actor_id": 1,
		"topology": _dictionary_or_empty(world_result.get("map", {})),
	})
	if bool(result.get("success", false)):
		world_result = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
		if interaction_controller != null:
			interaction_controller.world_result = world_result
		_setup_world_container()
		_render_world()
		_setup_runtime_input_controller()
		_refresh_fog_overlay()
		_refresh_debug_overlay()
		refresh_all_panels(current_interaction_prompt())
	return result


func press_enter_action() -> Dictionary:
	if has_active_dialogue():
		return advance_dialogue_without_choice()
	return {"success": false, "reason": "no_enter_action"}


func take_active_container_item(item_id: String, count: int = 1) -> Dictionary:
	var container_id: String = _active_container_id()
	if container_id.is_empty():
		var missing_result := {"success": false, "reason": "active_container_missing"}
		_record_container_feedback(missing_result, "take_container", "", item_id, count)
		return missing_result
	var result: Dictionary = _submit_inventory_action({
		"action": "take_container",
		"container_id": container_id,
		"item_id": item_id,
		"count": count,
	})
	_record_container_feedback(result, "take_container", container_id, item_id, count)
	refresh_inventory_panel()
	refresh_container_panel()
	refresh_journal_panel()
	return result


func take_active_container_money(count: int = -1) -> Dictionary:
	var container_id: String = _active_container_id()
	if container_id.is_empty():
		var missing_result := {"success": false, "reason": "active_container_missing"}
		_record_container_feedback(missing_result, "take_container_money", "", "money", count)
		return missing_result
	var result: Dictionary = _submit_inventory_action({
		"action": "take_container_money",
		"container_id": container_id,
		"count": count,
	})
	_record_container_feedback(result, "take_container_money", container_id, "money", count)
	refresh_inventory_panel()
	refresh_container_panel()
	refresh_hud()
	return result


func take_all_active_container_items() -> Dictionary:
	var container_id: String = _active_container_id()
	if container_id.is_empty():
		var missing_result := {"success": false, "reason": "active_container_missing"}
		_record_container_feedback(missing_result, "take_all_container", "", "", 0)
		return missing_result
	var result: Dictionary = _submit_inventory_action({
		"action": "take_all_container",
		"container_id": container_id,
		"include_money": true,
	})
	_record_container_feedback(result, "take_all_container", container_id, str(result.get("item_id", "")), int(result.get("count", 0)))
	refresh_inventory_panel()
	refresh_container_panel()
	refresh_journal_panel()
	refresh_hud()
	return result


func store_active_container_item(item_id: String, count: int = 1) -> Dictionary:
	var container_id: String = _active_container_id()
	if container_id.is_empty():
		var missing_result := {"success": false, "reason": "active_container_missing"}
		_record_container_feedback(missing_result, "store_container", "", item_id, count)
		return missing_result
	var result: Dictionary = _submit_inventory_action({
		"action": "store_container",
		"container_id": container_id,
		"item_id": item_id,
		"count": count,
	})
	_record_container_feedback(result, "store_container", container_id, item_id, count)
	refresh_inventory_panel()
	refresh_container_panel()
	return result


func store_all_active_container_items() -> Dictionary:
	var container_id: String = _active_container_id()
	if container_id.is_empty():
		var missing_result := {"success": false, "reason": "active_container_missing"}
		_record_container_feedback(missing_result, "store_all_container", "", "", 0)
		return missing_result
	var result: Dictionary = _submit_inventory_action({
		"action": "store_all_container",
		"container_id": container_id,
	})
	_record_container_feedback(result, "store_all_container", container_id, str(result.get("item_id", "")), int(result.get("count", 0)))
	refresh_inventory_panel()
	refresh_container_panel()
	return result


func transfer_active_container_item(source: String, item_id: String, count: int = 1) -> Dictionary:
	match source:
		"container":
			if str(item_id) == "money":
				return take_active_container_money(count)
			return take_active_container_item(item_id, count)
		"player":
			return store_active_container_item(item_id, count)
		_:
			return {"success": false, "reason": "unknown_container_transfer_source", "source": source}


func transfer_all_active_container_items(source: String) -> Dictionary:
	match source:
		"container":
			return take_all_active_container_items()
		"player":
			return store_all_active_container_items()
		_:
			return {"success": false, "reason": "unknown_container_transfer_source", "source": source}


func has_active_container_session() -> bool:
	return not _active_container_id().is_empty()


func drop_player_item(item_id: String, count: int = 1) -> Dictionary:
	if simulation == null:
		var missing_result := {"success": false, "reason": "simulation_missing", "item_id": item_id, "count": count}
		_record_inventory_feedback(missing_result, "drop", item_id, count)
		refresh_inventory_panel()
		return missing_result
	var result: Dictionary = _submit_inventory_action({
		"action": "drop",
		"item_id": item_id,
		"count": count,
	})
	_record_inventory_feedback(result, "drop", item_id, count)
	if bool(result.get("success", false)):
		_rebuild_world_after_runtime_change()
	else:
		refresh_inventory_panel()
	return result


func deconstruct_player_item(item_id: String, count: int = 1) -> Dictionary:
	if simulation == null:
		var missing_result := {"success": false, "reason": "simulation_missing", "item_id": item_id, "count": count}
		_record_inventory_feedback(missing_result, "deconstruct", item_id, count)
		refresh_inventory_panel()
		return missing_result
	var result: Dictionary = _submit_inventory_action({
		"action": "deconstruct",
		"item_id": item_id,
		"count": count,
	})
	_record_inventory_feedback(result, "deconstruct", item_id, count)
	refresh_inventory_panel()
	refresh_crafting_panel()
	return result


func split_player_inventory_stack(item_id: String, count: int = 1) -> Dictionary:
	if simulation == null:
		var missing_result := {"success": false, "reason": "simulation_missing", "item_id": item_id, "count": count}
		_record_inventory_feedback(missing_result, "split_stack", item_id, count)
		refresh_inventory_panel()
		return missing_result
	var result: Dictionary = _submit_inventory_action({
		"action": "split_stack",
		"item_id": item_id,
		"count": count,
	})
	_record_inventory_feedback(result, "split_stack", item_id, count)
	refresh_inventory_panel()
	return result


func reorder_player_inventory_item(item_id: String, target_index: int) -> Dictionary:
	if simulation == null:
		var missing_result := {"success": false, "reason": "simulation_missing", "item_id": item_id, "target_index": target_index}
		_record_inventory_feedback(missing_result, "reorder_inventory", item_id, 1)
		refresh_inventory_panel()
		return missing_result
	var result: Dictionary = _submit_inventory_action({
		"action": "reorder_inventory",
		"item_id": item_id,
		"target_index": target_index,
	})
	_record_inventory_feedback(result, "reorder_inventory", item_id, 1)
	refresh_inventory_panel()
	return result


func use_player_item(item_id: String) -> Dictionary:
	if simulation == null:
		var missing_result := {"success": false, "reason": "simulation_missing", "item_id": item_id}
		_record_inventory_feedback(missing_result, "use_item", item_id, 1)
		refresh_inventory_panel()
		return missing_result
	var result: Dictionary = _submit_inventory_action({
		"action": "use_item",
		"item_id": item_id,
	})
	_record_inventory_feedback(result, "use_item", item_id, 1)
	refresh_hud()
	refresh_inventory_panel()
	refresh_character_panel()
	return result


func buy_active_trade_item(item_id: String, count: int = 1) -> Dictionary:
	var shop_id: String = _active_shop_id()
	if shop_id.is_empty():
		var missing_result := {"success": false, "reason": "active_trade_missing"}
		_record_trade_feedback(missing_result, "buy_shop", "", item_id, count)
		return missing_result
	var result: Dictionary = _submit_inventory_action({
		"action": "buy_shop",
		"shop_id": shop_id,
		"item_id": item_id,
		"count": count,
	})
	_record_trade_feedback(result, "buy_shop", shop_id, item_id, count)
	refresh_inventory_panel()
	refresh_trade_panel()
	return result


func sell_active_trade_item(item_id: String, count: int = 1) -> Dictionary:
	var shop_id: String = _active_shop_id()
	if shop_id.is_empty():
		var missing_result := {"success": false, "reason": "active_trade_missing"}
		_record_trade_feedback(missing_result, "sell_shop", "", item_id, count)
		return missing_result
	var result: Dictionary = _submit_inventory_action({
		"action": "sell_shop",
		"shop_id": shop_id,
		"item_id": item_id,
		"count": count,
	})
	_record_trade_feedback(result, "sell_shop", shop_id, item_id, count)
	refresh_inventory_panel()
	refresh_trade_panel()
	return result


func sell_active_trade_equipment(slot_id: String, item_id: String) -> Dictionary:
	var shop_id: String = _active_shop_id()
	if shop_id.is_empty():
		var missing_result := {"success": false, "reason": "active_trade_missing"}
		_record_trade_feedback(missing_result, "sell_equipped_shop", "", item_id, 1)
		return missing_result
	var result: Dictionary = _submit_inventory_action({
		"action": "sell_equipped_shop",
		"shop_id": shop_id,
		"slot_id": slot_id,
		"item_id": item_id,
		"count": 1,
	})
	_record_trade_feedback(result, "sell_equipped_shop", shop_id, item_id, 1)
	if bool(result.get("success", false)):
		_rebuild_world_after_runtime_change()
	else:
		refresh_inventory_panel()
		refresh_trade_panel()
	return result


func transfer_active_trade_item(source: String, item_id: String, count: int = 1) -> Dictionary:
	match source:
		"shop":
			return buy_active_trade_item(item_id, count)
		"player":
			return sell_active_trade_item(item_id, count)
	if source.begins_with("equipment:"):
		return sell_active_trade_equipment(source.trim_prefix("equipment:"), item_id)
	return {"success": false, "reason": "unknown_trade_transfer_source", "source": source}


func has_active_trade_session() -> bool:
	return not _active_shop_id().is_empty()


func confirm_active_trade_cart(entries: Array) -> Dictionary:
	if entries.is_empty():
		return {"success": false, "reason": "empty_trade_cart"}
	var shop_id: String = _active_shop_id()
	if shop_id.is_empty():
		var missing_result := {"success": false, "reason": "active_trade_missing"}
		_record_trade_feedback(missing_result, "trade_cart", "", "", 0)
		return missing_result
	var result: Dictionary = simulation.confirm_trade_cart(1, shop_id, entries, registry.get_library("items"))
	_record_trade_feedback(result, "trade_cart", shop_id, str(result.get("item_id", "")), int(result.get("count", 0)))
	refresh_inventory_panel()
	refresh_trade_panel()
	return result


func equip_player_item(item_id: String, slot_id: String) -> Dictionary:
	if simulation == null:
		var missing_result := {"success": false, "reason": "simulation_missing", "item_id": item_id, "slot_id": slot_id}
		_record_character_feedback(missing_result, "equip", slot_id, item_id)
		refresh_character_panel()
		return missing_result
	var result: Dictionary = _submit_inventory_action({
		"action": "equip",
		"item_id": item_id,
		"slot_id": slot_id,
	})
	_record_character_feedback(result, "equip", slot_id, item_id)
	if bool(result.get("success", false)):
		_rebuild_world_after_runtime_change()
	else:
		refresh_inventory_panel()
		refresh_character_panel()
	return result


func unequip_player_slot(slot_id: String) -> Dictionary:
	if simulation == null:
		var missing_result := {"success": false, "reason": "simulation_missing", "slot_id": slot_id}
		_record_character_feedback(missing_result, "unequip", slot_id, "")
		refresh_character_panel()
		return missing_result
	var result: Dictionary = _submit_inventory_action({
		"action": "unequip",
		"slot_id": slot_id,
	})
	_record_character_feedback(result, "unequip", slot_id, str(result.get("item_id", "")))
	if bool(result.get("success", false)):
		_rebuild_world_after_runtime_change()
	else:
		refresh_inventory_panel()
		refresh_character_panel()
	return result


func reload_player_equipped_slot(slot_id: String = "main_hand") -> Dictionary:
	if simulation == null:
		var missing_result := {"success": false, "reason": "simulation_missing", "slot_id": slot_id}
		_record_character_feedback(missing_result, "reload", slot_id, "")
		refresh_character_panel()
		return missing_result
	var result: Dictionary = _submit_inventory_action({
		"action": "reload_equipped",
		"slot_id": slot_id,
	})
	_record_character_feedback(result, "reload", slot_id, str(result.get("item_id", "")))
	refresh_hud()
	refresh_inventory_panel()
	refresh_character_panel()
	return result


func allocate_player_attribute_point(attribute: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = simulation.allocate_attribute_point(1, attribute)
	refresh_hud()
	refresh_character_panel()
	refresh_skills_panel()
	return result


func learn_player_skill(skill_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = simulation.submit_player_command({
		"kind": "learn_skill",
		"actor_id": 1,
		"skill_id": skill_id,
		"skill_library": registry.get_library("skills"),
	})
	refresh_character_panel()
	refresh_skills_panel()
	return result


func bind_player_skill_to_hotbar(slot_id: String, skill_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = simulation.submit_player_command({
		"kind": "bind_hotbar",
		"actor_id": 1,
		"slot_id": slot_id,
		"skill_id": skill_id,
		"skill_library": registry.get_library("skills"),
	})
	refresh_hud()
	refresh_skills_panel()
	return result


func bind_player_item_to_hotbar(slot_id: String, item_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = simulation.submit_player_command({
		"kind": "bind_hotbar",
		"actor_id": 1,
		"slot_id": slot_id,
		"hotbar_kind": "item",
		"item_id": item_id,
		"item_library": registry.get_library("items"),
		"effect_library": registry.get_library("json"),
	})
	refresh_hud()
	refresh_inventory_panel()
	return result


func set_hotbar_group(group_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	if not simulation.has_method("set_active_hotbar_group"):
		return {"success": false, "reason": "hotbar_group_unsupported"}
	var result: Dictionary = simulation.set_active_hotbar_group(group_id)
	refresh_hud()
	refresh_skills_panel()
	refresh_inventory_panel()
	return result


func set_hotbar_group_label(group_id: String, label: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	if not simulation.has_method("set_hotbar_group_label"):
		return {"success": false, "reason": "hotbar_group_label_unsupported"}
	var result: Dictionary = simulation.set_hotbar_group_label(group_id, label)
	refresh_hud()
	refresh_skills_panel()
	return result


func cycle_hotbar_group(direction: int) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	if not simulation.has_method("cycle_hotbar_group"):
		return {"success": false, "reason": "hotbar_group_unsupported"}
	var result: Dictionary = simulation.cycle_hotbar_group(direction)
	refresh_hud()
	refresh_skills_panel()
	refresh_inventory_panel()
	return result


func use_hotbar_slot(slot_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	if not can_issue_player_commands():
		return _observe_command_rejected("hotbar")
	var slot: Dictionary = _dictionary_or_empty(_dictionary_or_empty(simulation.snapshot().get("hotbar", {})).get(slot_id, {}))
	if str(slot.get("kind", "")) == "item":
		var result: Dictionary = _submit_inventory_action({
			"action": "use_item",
			"item_id": str(slot.get("item_id", "")),
			"item_library": registry.get_library("items"),
			"effect_library": registry.get_library("json"),
		})
		refresh_hud()
		refresh_character_panel()
		refresh_inventory_panel()
		return result
	var skill_id := str(slot.get("skill_id", ""))
	if _skill_requires_runtime_target(skill_id):
		return begin_skill_targeting(slot_id, skill_id)
	var result: Dictionary = simulation.submit_player_command({
		"kind": "use_skill",
		"actor_id": 1,
		"slot_id": slot_id,
		"skill_library": registry.get_library("skills"),
		"target": {"target_type": "self"},
	})
	refresh_hud()
	refresh_character_panel()
	refresh_skills_panel()
	return result


func begin_skill_targeting(slot_id: String, skill_id: String = "") -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	if not can_issue_player_commands():
		return _observe_command_rejected("use_skill")
	var resolved_skill_id := skill_id
	if resolved_skill_id.is_empty():
		var slot: Dictionary = _dictionary_or_empty(_dictionary_or_empty(simulation.snapshot().get("hotbar", {})).get(slot_id, {}))
		resolved_skill_id = str(slot.get("skill_id", ""))
	if resolved_skill_id.is_empty():
		return {"success": false, "reason": "skill_missing", "slot_id": slot_id}
	var skill: Dictionary = _skill_data(resolved_skill_id)
	if skill.is_empty():
		return {"success": false, "reason": "unknown_skill", "skill_id": resolved_skill_id}
	var targeting: Dictionary = _skill_targeting_definition(_dictionary_or_empty(skill.get("activation", {})))
	var target_kind := _skill_target_kind(targeting)
	if target_kind == "self":
		return simulation.submit_player_command({
			"kind": "use_skill",
			"actor_id": 1,
			"slot_id": slot_id,
			"skill_library": registry.get_library("skills"),
			"target": {"target_type": "self"},
		})
	active_skill_targeting = {
		"active": true,
		"slot_id": slot_id,
		"skill_id": resolved_skill_id,
		"skill_name": str(skill.get("name", resolved_skill_id)),
		"target_kind": target_kind,
		"target_policy": str(targeting.get("policy", "")),
		"range": int(targeting.get("range", targeting.get("max_range", -1))),
		"radius": int(targeting.get("radius", targeting.get("aoe_radius", -1))),
		"length": int(targeting.get("length", targeting.get("max_length", -1))),
		"width": int(targeting.get("width", targeting.get("half_width", -1))),
	}
	active_skill_target_preview = {
		"success": false,
		"reason": "skill_target_pending",
		"skill_id": resolved_skill_id,
		"target_shape": target_kind,
	}
	refresh_hud(current_interaction_prompt())
	return {"success": true, "targeting": active_skill_targeting.duplicate(true), "preview": active_skill_target_preview.duplicate(true)}


func preview_active_skill_target(target: Dictionary) -> Dictionary:
	if active_skill_targeting.is_empty() or simulation == null:
		return {"success": false, "reason": "skill_targeting_inactive"}
	var skill_id := str(active_skill_targeting.get("skill_id", ""))
	var preview: Dictionary = simulation.preview_skill_target(1, skill_id, registry.get_library("skills"), target, _dictionary_or_empty(world_result.get("map", {})))
	active_skill_target_preview = preview.duplicate(true)
	if runtime_input_controller != null and runtime_input_controller.has_method("update_skill_target_preview_markers"):
		runtime_input_controller.update_skill_target_preview_markers(active_skill_target_preview)
	refresh_hud(current_interaction_prompt())
	return preview


func confirm_active_skill_target(target: Dictionary = {}) -> Dictionary:
	if active_skill_targeting.is_empty() or simulation == null:
		return {"success": false, "reason": "skill_targeting_inactive"}
	var command_target: Dictionary = _dictionary_or_empty(target).duplicate(true)
	if command_target.is_empty():
		command_target = _dictionary_or_empty(active_skill_target_preview.get("target", {})).duplicate(true)
	var slot_id := str(active_skill_targeting.get("slot_id", ""))
	var skill_id := str(active_skill_targeting.get("skill_id", ""))
	var result: Dictionary = simulation.submit_player_command({
		"kind": "use_skill",
		"actor_id": 1,
		"slot_id": slot_id,
		"skill_id": skill_id,
		"skill_library": registry.get_library("skills"),
		"target": command_target,
		"topology": _dictionary_or_empty(world_result.get("map", {})),
	})
	if bool(result.get("success", false)):
		active_skill_targeting = {}
		active_skill_target_preview = {}
		if runtime_input_controller != null and runtime_input_controller.has_method("update_skill_target_preview_markers"):
			runtime_input_controller.update_skill_target_preview_markers({})
	refresh_hud(current_interaction_prompt())
	refresh_character_panel()
	refresh_skills_panel()
	return result


func cancel_active_skill_targeting(reason: String = "cancelled") -> Dictionary:
	if active_skill_targeting.is_empty():
		return {"success": false, "reason": "skill_targeting_inactive"}
	var cancelled := active_skill_targeting.duplicate(true)
	active_skill_targeting = {}
	active_skill_target_preview = {}
	if runtime_input_controller != null and runtime_input_controller.has_method("update_skill_target_preview_markers"):
		runtime_input_controller.update_skill_target_preview_markers({})
	refresh_hud(current_interaction_prompt())
	return {"success": true, "closed": "skill_targeting", "reason": reason, "targeting": cancelled}


func has_active_skill_targeting() -> bool:
	return not active_skill_targeting.is_empty()


func active_skill_targeting_snapshot() -> Dictionary:
	return _skill_targeting_snapshot()


func craft_player_recipe(recipe_id: String, count: int = 1) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = simulation.submit_player_command({
		"kind": "craft",
		"actor_id": 1,
		"recipe_id": recipe_id,
		"count": max(1, count),
		"recipe_library": registry.get_library("recipes"),
		"crafting_context": _crafting_context(),
		"topology": _dictionary_or_empty(world_result.get("map", {})),
	})
	refresh_inventory_panel()
	refresh_crafting_panel()
	refresh_skills_panel()
	return result


func confirm_crafting_queue(entries: Array) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var results: Array[Dictionary] = []
	var completed_count: int = 0
	for entry in _array_or_empty(entries):
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var recipe_id := str(entry_data.get("recipe_id", ""))
		var count: int = max(1, int(entry_data.get("count", 1)))
		if recipe_id.is_empty():
			results.append({"success": false, "reason": "recipe_id_missing", "entry": entry_data.duplicate(true)})
			continue
		var result: Dictionary = simulation.submit_player_command({
			"kind": "craft",
			"actor_id": 1,
			"recipe_id": recipe_id,
			"count": count,
			"recipe_library": registry.get_library("recipes"),
			"crafting_context": _crafting_context(),
			"topology": _dictionary_or_empty(world_result.get("map", {})),
		})
		result["queued_recipe_id"] = recipe_id
		result["queued_count"] = count
		results.append(result)
		if bool(result.get("success", false)):
			completed_count += count
	var failed: Array[Dictionary] = []
	for result in results:
		var result_data: Dictionary = _dictionary_or_empty(result)
		if not bool(result_data.get("success", false)):
			failed.append(result_data.duplicate(true))
	refresh_inventory_panel()
	refresh_crafting_panel()
	refresh_skills_panel()
	return {
		"success": failed.is_empty(),
		"partial_success": completed_count > 0 and not failed.is_empty(),
		"completed_count": completed_count,
		"failed_count": failed.size(),
		"results": results,
		"failed": failed,
	}


func _crafting_context() -> Dictionary:
	return {
		"crafting_stations": _array_or_empty(_dictionary_or_empty(world_result.get("map", {})).get("crafting_stations", [])).duplicate(true),
		"nearby_tool_containers": _nearby_tool_containers(),
	}


func _nearby_tool_containers() -> Array[Dictionary]:
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
		var target: Dictionary = _dictionary_or_empty(simulation.map_interaction_targets.get(target_id, {}))
		if target.is_empty() or str(target.get("kind", "")) != "container":
			continue
		if not _container_target_in_range(actor_grid, target, 1):
			continue
		var inventory: Array = _container_inventory_for_crafting(str(target_id), target)
		if inventory.is_empty():
			continue
		output.append({
			"container_id": str(target_id),
			"display_name": str(target.get("display_name", target_id)),
			"inventory": inventory,
		})
	return output


func _container_target_in_range(actor_grid: Dictionary, target: Dictionary, max_distance: int) -> bool:
	for cell in _array_or_empty(target.get("cells", [])):
		if _grid_distance(actor_grid, _dictionary_or_empty(cell)) <= max_distance:
			return true
	return _grid_distance(actor_grid, _dictionary_or_empty(target.get("anchor", {}))) <= max_distance


func _container_inventory_for_crafting(container_id: String, target: Dictionary) -> Array:
	if simulation != null and simulation.container_sessions.has(container_id):
		return _array_or_empty(_dictionary_or_empty(simulation.container_sessions[container_id]).get("inventory", [])).duplicate(true)
	if simulation != null and simulation.corpse_containers.has(container_id):
		return _array_or_empty(_dictionary_or_empty(simulation.corpse_containers[container_id]).get("inventory", [])).duplicate(true)
	return _array_or_empty(target.get("container_inventory", [])).duplicate(true)


func turn_in_player_quest(quest_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = simulation.turn_in_quest(1, quest_id)
	refresh_inventory_panel()
	refresh_journal_panel()
	refresh_skills_panel()
	refresh_crafting_panel()
	return result


func _rebuild_world_after_runtime_change(selected_prompt: Dictionary = {}) -> void:
	world_result = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
	if not bool(world_result.get("ok", false)):
		push_error(str(world_result.get("error", "world rebuild failed")))
		return
	_sync_observed_level_to_map()
	if simulation != null:
		var map: Dictionary = _dictionary_or_empty(world_result.get("map", {}))
		simulation.configure_map_interactions(_dictionary_or_empty(map.get("interaction_targets", {})))
	if interaction_controller != null:
		interaction_controller.world_result = world_result
	_setup_world_container()
	_render_world()
	_setup_runtime_input_controller()
	_refresh_fog_overlay()
	_refresh_debug_overlay()
	_setup_panels()
	refresh_all_panels(selected_prompt)


func _setup_world_container() -> void:
	if world_container != null:
		return
	world_container = Node3D.new()
	world_container.name = "WorldContainer"
	add_child(world_container)


func _setup_runtime_input_controller() -> void:
	if runtime_input_controller == null:
		runtime_input_controller = GameRuntimeInputController.new(self)
	runtime_input_controller.attach_world(world_container, world_result)


func _render_world() -> Dictionary:
	if world_container == null:
		return {}
	var counts: Dictionary = WorldSceneRenderer.new().render_world(world_container, world_result)
	performance_last_render_counts = _render_count_summary(counts)
	performance_render_sequence += 1
	return counts


func _render_count_summary(counts: Dictionary) -> Dictionary:
	var summary: Dictionary = counts.duplicate(true)
	var total: int = 0
	for value in counts.values():
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			total += int(value)
	summary["total"] = total
	return summary


func _refresh_fog_overlay() -> void:
	if simulation == null or world_result.is_empty():
		return
	fog_overlay = fog_overlay_controller.ensure_overlay(self, _dictionary_or_empty(world_result.get("map", {})), simulation.snapshot())


func _refresh_debug_overlay() -> void:
	if debug_overlay_controller == null or world_container == null:
		return
	var runtime_snapshot: Dictionary = simulation.snapshot() if simulation != null else {}
	debug_overlay_controller.apply_overlay(world_container, debug_overlay_mode, _dictionary_or_empty(world_result.get("map", {})), runtime_snapshot)


func _setup_panels() -> void:
	if panel_controller == null:
		panel_controller = GamePanelController.new(self, registry, simulation, world_result)
	panel_controller.update_world_result(world_result)
	panel_controller.active_trade_target = active_trade_target
	panel_controller.active_trade_feedback = active_trade_feedback
	panel_controller.active_container_feedback = active_container_feedback
	panel_controller.active_character_feedback = active_character_feedback
	panel_controller.active_inventory_feedback = active_inventory_feedback
	panel_controller.setup_panels()
	# 对外保留面板引用，方便既有 smoke 和编辑器入口继续做状态复核。
	hud = panel_controller.hud
	dialogue_panel = panel_controller.dialogue_panel
	inventory_panel = panel_controller.inventory_panel
	trade_panel = panel_controller.trade_panel
	container_panel = panel_controller.container_panel
	character_panel = panel_controller.character_panel
	journal_panel = panel_controller.journal_panel
	map_panel = panel_controller.map_panel
	skills_panel = panel_controller.skills_panel
	crafting_panel = panel_controller.crafting_panel
	settings_panel = panel_controller.settings_panel


func _update_trade_target_after_interaction(result: Dictionary, executed_target: Dictionary) -> void:
	if not bool(result.get("success", false)):
		return
	var interaction_result: Dictionary = _dictionary_or_empty(result.get("result", {}))
	var prompt: Dictionary = _dictionary_or_empty(interaction_result.get("prompt", {}))
	var option_kind: String = ""
	var options: Array = prompt.get("options", [])
	if not options.is_empty():
		var option: Dictionary = _dictionary_or_empty(options[0])
		option_kind = str(option.get("kind", ""))
	if option_kind == "talk" and executed_target.get("target_type", "") == "actor":
		active_trade_target = executed_target.duplicate(true)
		active_trade_feedback = {}


func _apply_interaction_execution_result(result: Dictionary, executed_target: Dictionary) -> void:
	_update_trade_target_after_interaction(result, executed_target)
	if _interaction_result_opens_container(result):
		active_container_feedback = {}
	world_result = interaction_controller.world_result
	_sync_observed_level_to_map()
	# 地图切换、对象消费、移动和击杀后需要重绘世界，保证 scene tree 与运行时快照一致。
	_setup_world_container()
	_render_world()
	_setup_runtime_input_controller()
	_refresh_fog_overlay()
	_refresh_debug_overlay()
	_setup_panels()
	refresh_all_panels(_dictionary_or_empty(result.get("prompt", {})))


func _submit_inventory_action(action: Dictionary) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	if not can_issue_player_commands():
		return _observe_command_rejected(str(action.get("action", "inventory_action")))
	var command: Dictionary = action.duplicate(true)
	command["kind"] = "inventory_action"
	command["actor_id"] = 1
	command["item_library"] = registry.get_library("items")
	command["effect_library"] = registry.get_library("json")
	command["topology"] = _dictionary_or_empty(world_result.get("map", {}))
	return simulation.submit_player_command(command)


func _observe_command_rejected(action: String) -> Dictionary:
	refresh_hud(current_interaction_prompt())
	return {
		"success": false,
		"reason": "observe_mode_blocks_player_commands",
		"action": action,
		"observe_mode": observe_mode_enabled,
	}


func _record_container_feedback(result: Dictionary, action: String, container_id: String, item_id: String, count: int) -> void:
	if bool(result.get("success", false)) and not bool(result.get("partial_success", false)):
		active_container_feedback = {}
		return
	active_container_feedback = result.duplicate(true)
	active_container_feedback["type"] = "error"
	active_container_feedback["action"] = action
	active_container_feedback["container_id"] = str(result.get("container_id", container_id))
	active_container_feedback["item_id"] = str(result.get("item_id", item_id))
	active_container_feedback["count"] = count


func _record_trade_feedback(result: Dictionary, action: String, shop_id: String, item_id: String, count: int) -> void:
	if bool(result.get("success", false)):
		active_trade_feedback = {}
		return
	active_trade_feedback = result.duplicate(true)
	active_trade_feedback["type"] = "error"
	active_trade_feedback["action"] = action
	active_trade_feedback["shop_id"] = str(result.get("shop_id", shop_id))
	active_trade_feedback["item_id"] = str(result.get("item_id", item_id))
	active_trade_feedback["count"] = count


func _record_inventory_feedback(result: Dictionary, action: String, item_id: String, count: int) -> void:
	active_inventory_feedback = result.duplicate(true)
	active_inventory_feedback["type"] = "success" if bool(result.get("success", false)) else "error"
	active_inventory_feedback["action"] = action
	active_inventory_feedback["item_id"] = str(result.get("item_id", item_id))
	active_inventory_feedback["count"] = int(result.get("count", count))


func _record_character_feedback(result: Dictionary, action: String, slot_id: String, item_id: String) -> void:
	if bool(result.get("success", false)):
		active_character_feedback = {}
		return
	active_character_feedback = result.duplicate(true)
	active_character_feedback["type"] = "error"
	active_character_feedback["action"] = action
	active_character_feedback["slot_id"] = str(result.get("slot_id", slot_id))
	active_character_feedback["item_id"] = str(result.get("item_id", item_id))


func _interaction_result_opens_container(result: Dictionary) -> bool:
	if result.has("container"):
		return true
	var nested_result: Dictionary = _dictionary_or_empty(result.get("result", {}))
	return nested_result.has("container")


func _dialogue_trade_target(result: Dictionary = {}) -> Dictionary:
	var shop_id := _dialogue_trade_shop_id(result)
	if not shop_id.is_empty():
		return {
			"target_type": "shop",
			"shop_id": shop_id,
		}
	if active_trade_target.get("target_type", "") == "actor":
		return active_trade_target.duplicate(true)
	return {
		"target_type": "shop",
	}


func _active_trade_target_available() -> bool:
	if active_trade_target.is_empty() or simulation == null:
		return true
	if str(active_trade_target.get("target_type", "")) == "shop" and not str(active_trade_target.get("shop_id", "")).is_empty():
		return registry != null and registry.get_library("shops").has(str(active_trade_target.get("shop_id", "")))
	if str(active_trade_target.get("target_type", "")) != "actor":
		return true
	var actor_id := int(active_trade_target.get("actor_id", 0))
	if actor_id <= 0:
		return false
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return false
	if not str(actor.map_id).is_empty() and not simulation.active_map_id.is_empty() and str(actor.map_id) != simulation.active_map_id:
		return false
	var shop_id := "%s_shop" % actor.definition_id
	return registry != null and registry.get_library("shops").has(shop_id)


func _dialogue_trade_shop_id(result: Dictionary) -> String:
	for action in _array_or_empty(result.get("emitted_actions", [])):
		var action_data: Dictionary = _dictionary_or_empty(action)
		if str(action_data.get("type", "")) != "open_trade":
			continue
		var shop_id := str(action_data.get("shop_id", "")).strip_edges()
		if not shop_id.is_empty():
			return shop_id
	return ""


func _current_dialogue_snapshot() -> Dictionary:
	if panel_controller == null or simulation == null:
		return {}
	var DialogueSnapshot = preload("res://scripts/ui/snapshots/dialogue_snapshot.gd")
	return DialogueSnapshot.new(registry).build(simulation.snapshot())


func _active_shop_id() -> String:
	if registry == null or simulation == null:
		return ""
	var TradeSnapshot = preload("res://scripts/ui/snapshots/trade_snapshot.gd")
	var session: Dictionary = TradeSnapshot.new(registry).resolve_trade_session(simulation.snapshot(), active_trade_target)
	return str(session.get("shop_id", ""))


func _trade_closed_payload(target: Dictionary, reason: String) -> Dictionary:
	var payload := {
		"actor_id": 1,
		"reason": reason,
		"target_type": str(target.get("target_type", "")),
		"target_actor_id": int(target.get("actor_id", 0)),
	}
	if registry != null and simulation != null:
		var TradeSnapshot = preload("res://scripts/ui/snapshots/trade_snapshot.gd")
		var session: Dictionary = TradeSnapshot.new(registry).resolve_trade_session(simulation.snapshot(), target)
		payload["shop_id"] = str(session.get("shop_id", ""))
		payload["target_name"] = str(session.get("target_name", ""))
	return payload


func _active_container_id() -> String:
	if simulation == null:
		return ""
	var snapshot: Dictionary = simulation.snapshot()
	for actor in snapshot.get("actors", []):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if actor_data.get("kind", "") == "player":
			return str(actor_data.get("active_container_id", ""))
	return ""


func _active_container_close_reason() -> String:
	var container_id := _active_container_id()
	if container_id.is_empty() or simulation == null:
		return ""
	if not simulation.container_sessions.has(container_id):
		return "target_unavailable"
	if not _active_container_in_range(container_id):
		return "out_of_range"
	return ""


func _active_container_in_range(container_id: String) -> bool:
	var target: Dictionary = _dictionary_or_empty(simulation.map_interaction_targets.get(container_id, {}))
	if target.is_empty():
		return true
	var actor: RefCounted = simulation.actor_registry.get_actor(1)
	if actor == null or actor.grid_position == null:
		return true
	var actor_grid: Dictionary = actor.grid_position.to_dictionary()
	for cell in _array_or_empty(target.get("cells", [])):
		if _grid_distance(actor_grid, _dictionary_or_empty(cell)) <= 1:
			return true
	if _grid_distance(actor_grid, _dictionary_or_empty(target.get("anchor", {}))) <= 1:
		return true
	return false


func _grid_distance(left: Dictionary, right: Dictionary) -> int:
	if left.is_empty() or right.is_empty() or int(left.get("y", 0)) != int(right.get("y", 0)):
		return 999999
	return abs(int(left.get("x", 0)) - int(right.get("x", 0))) + abs(int(left.get("z", 0)) - int(right.get("z", 0)))


func _focused_actor_data() -> Dictionary:
	var candidates: Array[Dictionary] = _focus_actor_candidates()
	if candidates.is_empty():
		focused_actor_id = 0
		return {}
	for candidate in candidates:
		if int(candidate.get("actor_id", 0)) == focused_actor_id:
			return candidate.duplicate(true)
	focused_actor_id = int(candidates[0].get("actor_id", 0))
	return candidates[0].duplicate(true)


func _focus_actor_candidates() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if world_result.is_empty():
		return candidates
	var focused_level := current_map_level()
	for actor in _array_or_empty(world_result.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if actor_data.is_empty():
			continue
		if not observe_mode_enabled and not _is_player_side_actor(actor_data):
			continue
		var grid: Dictionary = _dictionary_or_empty(actor_data.get("grid_position", {}))
		if int(grid.get("y", 0)) != focused_level:
			continue
		candidates.append(actor_data.duplicate(true))
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("actor_id", 0)) < int(b.get("actor_id", 0))
	)
	return candidates


func _current_focus_level() -> int:
	return current_map_level()


func _is_player_side_actor(actor_data: Dictionary) -> bool:
	return str(actor_data.get("side", "")) == "player" or str(actor_data.get("kind", "")) == "player"


func _focused_actor_busy_state(focused_actor: Dictionary) -> Dictionary:
	if focused_actor.is_empty() or simulation == null:
		return {}
	var actor_id := int(focused_actor.get("actor_id", 0))
	var snapshot: Dictionary = simulation.snapshot()
	var pending_movement: Dictionary = _dictionary_or_empty(snapshot.get("pending_movement", {}))
	if not pending_movement.is_empty() and int(pending_movement.get("actor_id", 0)) == actor_id:
		return {"kind": "pending_movement", "state": pending_movement.duplicate(true)}
	var pending_interaction: Dictionary = _dictionary_or_empty(snapshot.get("pending_interaction", {}))
	if not pending_interaction.is_empty() and int(pending_interaction.get("actor_id", 0)) == actor_id:
		return {"kind": "pending_interaction", "state": pending_interaction.duplicate(true)}
	return {}


func _clear_focus_switch_ui_state() -> void:
	if runtime_input_controller != null and runtime_input_controller.has_method("clear_selection_state"):
		runtime_input_controller.clear_selection_state()
	if interaction_controller != null:
		interaction_controller.clear_selection()
	if hud != null and hud.has_method("hide_interaction_menu"):
		hud.hide_interaction_menu()


func _sync_observed_level_to_map() -> void:
	observed_map_level = _normalized_map_level(observed_map_level if not _available_map_levels().is_empty() else _default_map_level())


func _normalized_map_level(level: int) -> int:
	var levels: Array[int] = _available_map_levels()
	if levels.is_empty():
		return _default_map_level()
	if levels.has(level):
		return level
	var nearest := int(levels[0])
	var nearest_distance := absi(nearest - level)
	for candidate in levels:
		var distance := absi(int(candidate) - level)
		if distance < nearest_distance:
			nearest = int(candidate)
			nearest_distance = distance
	return nearest


func _default_map_level() -> int:
	var map: Dictionary = _dictionary_or_empty(world_result.get("map", {}))
	return int(map.get("default_level", 0))


func _available_map_levels() -> Array[int]:
	var seen: Dictionary = {}
	var map: Dictionary = _dictionary_or_empty(world_result.get("map", {}))
	for level in _array_or_empty(map.get("levels", [])):
		var level_data: Dictionary = _dictionary_or_empty(level)
		seen[int(level_data.get("y", _default_map_level()))] = true
	seen[_default_map_level()] = true
	for actor in _array_or_empty(world_result.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		var grid: Dictionary = _dictionary_or_empty(actor_data.get("grid_position", {}))
		if not grid.is_empty():
			seen[int(grid.get("y", _default_map_level()))] = true
	var levels: Array[int] = []
	for key in seen.keys():
		levels.append(int(key))
	levels.sort()
	return levels


func _skill_requires_runtime_target(skill_id: String) -> bool:
	if skill_id.is_empty():
		return false
	var skill: Dictionary = _skill_data(skill_id)
	if skill.is_empty():
		return false
	var targeting: Dictionary = _skill_targeting_definition(_dictionary_or_empty(skill.get("activation", {})))
	return _skill_target_kind(targeting) != "self"


func _skill_data(skill_id: String) -> Dictionary:
	if registry == null or skill_id.is_empty():
		return {}
	var record: Dictionary = _dictionary_or_empty(registry.get_library("skills").get(skill_id, {}))
	return _dictionary_or_empty(record.get("data", record)).duplicate(true)


func _skill_targeting_definition(activation: Dictionary) -> Dictionary:
	var targeting: Dictionary = _dictionary_or_empty(activation.get("targeting", {})).duplicate(true)
	if targeting.is_empty():
		targeting = _dictionary_or_empty(activation.get("target", {})).duplicate(true)
	if targeting.is_empty():
		targeting = {
			"kind": "self",
			"policy": "self",
		}
	if not targeting.has("policy"):
		targeting["policy"] = _default_skill_target_policy(_skill_target_kind(targeting))
	return targeting


func _skill_target_kind(targeting: Dictionary) -> String:
	return str(targeting.get("kind", targeting.get("target_kind", targeting.get("shape", "self"))))


func _default_skill_target_policy(target_kind: String) -> String:
	match target_kind:
		"self":
			return "self"
		"single", "actor", "single_actor":
			return "any_actor"
		"grid", "point", "radius", "circle", "line", "cone":
			return "any_grid"
	return "any"


func _skill_targeting_snapshot() -> Dictionary:
	if active_skill_targeting.is_empty():
		return {"active": false}
	var snapshot: Dictionary = active_skill_targeting.duplicate(true)
	snapshot["preview"] = active_skill_target_preview.duplicate(true)
	return snapshot


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
