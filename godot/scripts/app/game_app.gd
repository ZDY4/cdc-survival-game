extends Node3D

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const WorldRoot = preload("res://scripts/world/world_root.gd")
const DebugRuntimeController = preload("res://scripts/app/controllers/debug_runtime_controller.gd")
const GamePanelController = preload("res://scripts/app/controllers/game_panel_controller.gd")
const GameInputRouter = preload("res://scripts/app/controllers/game_input_router.gd")
const GameRuntimeInputController = preload("res://scripts/app/controllers/game_runtime_input_controller.gd")
const RuntimeBootController = preload("res://scripts/app/controllers/runtime_boot_controller.gd")
const RuntimeRefreshController = preload("res://scripts/app/controllers/runtime_refresh_controller.gd")
const RuntimePerformanceTracker = preload("res://scripts/app/controllers/runtime_performance_tracker.gd")
const RuntimeControlStateController = preload("res://scripts/app/controllers/runtime_control_state_controller.gd")
const RuntimeViewStateController = preload("res://scripts/app/controllers/runtime_view_state_controller.gd")
const WorldActionFlowController = preload("res://scripts/app/controllers/world_action_flow_controller.gd")
const PlayerCommandAuthorityAudit = preload("res://scripts/app/controllers/player_command_authority_audit.gd")
const AiDebugSnapshotBuilder = preload("res://scripts/app/controllers/ai_debug_snapshot_builder.gd")
const WorldTimeSnapshotBuilder = preload("res://scripts/app/controllers/world_time_snapshot_builder.gd")
const UiFeedbackStateController = preload("res://scripts/app/controllers/ui_feedback_state_controller.gd")
const SkillTargetingController = preload("res://scripts/app/controllers/skill_targeting_controller.gd")
const CraftingFeedbackController = preload("res://scripts/app/controllers/crafting_feedback_controller.gd")
const UiOverlayRenderController = preload("res://scripts/app/controllers/ui_overlay_render_controller.gd")
const TooltipSnapshotController = preload("res://scripts/app/controllers/tooltip_snapshot_controller.gd")
const DragSnapshotController = preload("res://scripts/app/controllers/drag_snapshot_controller.gd")
const PlayerInteractionController = preload("res://scripts/app/controllers/player_interaction_controller.gd")
const AudioFeedbackController = preload("res://scripts/app/audio_feedback_controller.gd")
const ReasonCatalog = preload("res://scripts/ui/snapshots/reason_catalog.gd")
const CRAFTING_QUEUE_ADVANCE_LIMIT := 16

var registry: ContentRegistry
var simulation: RefCounted
var world_result: Dictionary = {}
var interaction_controller: RefCounted
var runtime_input_controller: RefCounted
var panel_controller: RefCounted
var world_root: Node3D
var world_action_flow_controller: RefCounted = WorldActionFlowController.new()
var world_action_presenter: RefCounted:
	get:
		if world_action_flow_controller == null:
			return null
		return world_action_flow_controller.presenter
var audio_feedback_controller: Node
var reason_catalog: RefCounted = ReasonCatalog.new()
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
var ui_overlay_render_controller: RefCounted = UiOverlayRenderController.new()
var tooltip_snapshot_controller: RefCounted = TooltipSnapshotController.new()
var drag_snapshot_controller: RefCounted = DragSnapshotController.new()
var tooltip_layer: Control:
	get:
		return ui_overlay_render_controller.tooltip_layer if ui_overlay_render_controller != null else null
	set(value):
		if ui_overlay_render_controller != null:
			ui_overlay_render_controller.tooltip_layer = value
var tooltip_panel: PanelContainer:
	get:
		return ui_overlay_render_controller.tooltip_panel if ui_overlay_render_controller != null else null
	set(value):
		if ui_overlay_render_controller != null:
			ui_overlay_render_controller.tooltip_panel = value
var tooltip_label: Label:
	get:
		return ui_overlay_render_controller.tooltip_label if ui_overlay_render_controller != null else null
	set(value):
		if ui_overlay_render_controller != null:
			ui_overlay_render_controller.tooltip_label = value
var last_tooltip_render_snapshot: Dictionary:
	get:
		return ui_overlay_render_controller.last_tooltip_render_snapshot if ui_overlay_render_controller != null else {"active": false}
	set(value):
		if ui_overlay_render_controller != null:
			ui_overlay_render_controller.last_tooltip_render_snapshot = value.duplicate(true)
var drag_preview_layer: Control:
	get:
		return ui_overlay_render_controller.drag_preview_layer if ui_overlay_render_controller != null else null
	set(value):
		if ui_overlay_render_controller != null:
			ui_overlay_render_controller.drag_preview_layer = value
var drag_preview_panel: PanelContainer:
	get:
		return ui_overlay_render_controller.drag_preview_panel if ui_overlay_render_controller != null else null
	set(value):
		if ui_overlay_render_controller != null:
			ui_overlay_render_controller.drag_preview_panel = value
var drag_preview_label: Label:
	get:
		return ui_overlay_render_controller.drag_preview_label if ui_overlay_render_controller != null else null
	set(value):
		if ui_overlay_render_controller != null:
			ui_overlay_render_controller.drag_preview_label = value
var last_drag_preview_render_snapshot: Dictionary:
	get:
		return ui_overlay_render_controller.last_drag_preview_render_snapshot if ui_overlay_render_controller != null else {"active": false}
	set(value):
		if ui_overlay_render_controller != null:
			ui_overlay_render_controller.last_drag_preview_render_snapshot = value.duplicate(true)
var active_trade_target: Dictionary = {}
var ui_feedback_state_controller: RefCounted = UiFeedbackStateController.new()
var active_trade_feedback: Dictionary:
	get:
		return ui_feedback_state_controller.active_trade_feedback if ui_feedback_state_controller != null else {}
	set(value):
		if ui_feedback_state_controller != null:
			ui_feedback_state_controller.active_trade_feedback = value.duplicate(true)
var active_container_feedback: Dictionary:
	get:
		return ui_feedback_state_controller.active_container_feedback if ui_feedback_state_controller != null else {}
	set(value):
		if ui_feedback_state_controller != null:
			ui_feedback_state_controller.active_container_feedback = value.duplicate(true)
var active_character_feedback: Dictionary:
	get:
		return ui_feedback_state_controller.active_character_feedback if ui_feedback_state_controller != null else {}
	set(value):
		if ui_feedback_state_controller != null:
			ui_feedback_state_controller.active_character_feedback = value.duplicate(true)
var active_inventory_feedback: Dictionary:
	get:
		return ui_feedback_state_controller.active_inventory_feedback if ui_feedback_state_controller != null else {}
	set(value):
		if ui_feedback_state_controller != null:
			ui_feedback_state_controller.active_inventory_feedback = value.duplicate(true)
var crafting_feedback_controller: RefCounted = CraftingFeedbackController.new()
var latest_crafting_queue_result: Dictionary:
	get:
		return crafting_feedback_controller.latest_queue_result if crafting_feedback_controller != null else {}
	set(value):
		if crafting_feedback_controller != null:
			crafting_feedback_controller.latest_queue_result = value.duplicate(true)
var latest_pending_crafting_result: Dictionary:
	get:
		return crafting_feedback_controller.latest_pending_result if crafting_feedback_controller != null else {}
	set(value):
		if crafting_feedback_controller != null:
			crafting_feedback_controller.latest_pending_result = value.duplicate(true)
var skill_targeting_controller: RefCounted = SkillTargetingController.new()
var active_skill_targeting: Dictionary:
	get:
		return skill_targeting_controller.active_targeting if skill_targeting_controller != null else {}
	set(value):
		if skill_targeting_controller != null:
			skill_targeting_controller.active_targeting = value.duplicate(true)
var active_skill_target_preview: Dictionary:
	get:
		return skill_targeting_controller.active_preview if skill_targeting_controller != null else {}
	set(value):
		if skill_targeting_controller != null:
			skill_targeting_controller.active_preview = value.duplicate(true)
var debug_runtime_controller: RefCounted = DebugRuntimeController.new()
var debug_overlay_mode: String:
	get:
		return str(debug_runtime_controller.current_debug_overlay_mode()) if debug_runtime_controller != null else "off"
	set(value):
		if debug_runtime_controller != null:
			debug_runtime_controller.debug_overlay_mode = value
var game_input_router: RefCounted = GameInputRouter.new()
var player_command_authority_audit: RefCounted = PlayerCommandAuthorityAudit.new()
var ai_debug_snapshot_builder: RefCounted = AiDebugSnapshotBuilder.new()
var world_time_snapshot_builder: RefCounted = WorldTimeSnapshotBuilder.new()
var runtime_boot_controller: RefCounted = RuntimeBootController.new()
var runtime_refresh_controller: RefCounted = RuntimeRefreshController.new()
var runtime_performance_tracker: RefCounted = RuntimePerformanceTracker.new()
var runtime_control_state_controller: RefCounted = RuntimeControlStateController.new()
var runtime_view_state_controller: RefCounted = RuntimeViewStateController.new()
var focused_actor_id: int:
	get:
		return int(runtime_view_state_controller.focused_actor_id) if runtime_view_state_controller != null else 0
	set(value):
		if runtime_view_state_controller != null:
			runtime_view_state_controller.focused_actor_id = value
var observed_map_level: int:
	get:
		return int(runtime_view_state_controller.observed_map_level) if runtime_view_state_controller != null else 0
	set(value):
		if runtime_view_state_controller != null:
			runtime_view_state_controller.observed_map_level = value
var info_panel_pages: Array[Dictionary]:
	get:
		return runtime_control_state_controller.info_panel_pages if runtime_control_state_controller != null else []
	set(value):
		if runtime_control_state_controller != null:
			runtime_control_state_controller.info_panel_pages = value
var active_info_panel_index: int:
	get:
		return int(runtime_control_state_controller.active_info_panel_index) if runtime_control_state_controller != null else 0
	set(value):
		if runtime_control_state_controller != null:
			runtime_control_state_controller.active_info_panel_index = value
var auto_tick_enabled: bool:
	get:
		return bool(runtime_control_state_controller.auto_tick_enabled) if runtime_control_state_controller != null else false
	set(value):
		if runtime_control_state_controller != null:
			runtime_control_state_controller.auto_tick_enabled = value
var auto_tick_elapsed_sec: float:
	get:
		return float(runtime_control_state_controller.auto_tick_elapsed_sec) if runtime_control_state_controller != null else 0.0
	set(value):
		if runtime_control_state_controller != null:
			runtime_control_state_controller.auto_tick_elapsed_sec = value
var observe_mode_enabled: bool:
	get:
		return bool(runtime_control_state_controller.observe_mode_enabled) if runtime_control_state_controller != null else false
	set(value):
		if runtime_control_state_controller != null:
			runtime_control_state_controller.observe_mode_enabled = value
var observe_speed_id: String:
	get:
		return str(runtime_control_state_controller.observe_speed_id) if runtime_control_state_controller != null else "x1"
	set(value):
		if runtime_control_state_controller != null:
			runtime_control_state_controller.observe_speed_id = value
var performance_frame_time_ms: float:
	get:
		return float(runtime_performance_tracker.frame_time_ms) if runtime_performance_tracker != null else 0.0
var performance_fps: float:
	get:
		return float(runtime_performance_tracker.fps) if runtime_performance_tracker != null else 0.0
var performance_last_process_tick_msec: int:
	get:
		return int(runtime_performance_tracker.last_process_tick_msec) if runtime_performance_tracker != null else 0
var performance_last_hud_refresh_tick_msec: int:
	get:
		return int(runtime_performance_tracker.last_hud_refresh_tick_msec) if runtime_performance_tracker != null else 0
var performance_last_render_counts: Dictionary:
	get:
		return runtime_performance_tracker.last_render_counts.duplicate(true) if runtime_performance_tracker != null else {}
var performance_render_sequence: int:
	get:
		return int(runtime_performance_tracker.render_sequence) if runtime_performance_tracker != null else 0


func _ready() -> void:
	registry = ContentRegistry.new()
	var load_result := registry.load_all()
	if load_result.has_errors():
		push_error("failed to load content for Godot game root")
		for error in load_result.errors:
			push_error(error)
		return
	runtime_refresh_controller.configure(registry)
	runtime_boot_controller.configure(registry)

	var runtime_result: Dictionary = _dictionary_or_empty(runtime_boot_controller.call("build_startup_runtime"))
	simulation = runtime_result.get("simulation")
	var runtime_snapshot: Dictionary = runtime_result.get("snapshot", {})
	var startup_refresh: Dictionary = _dictionary_or_empty(runtime_refresh_controller.call("build_world_result_from_snapshot", runtime_snapshot, "startup"))
	if not _accept_runtime_refresh_result(startup_refresh, "world build failed"):
		return

	interaction_controller = PlayerInteractionController.new(registry, simulation, world_result)
	_apply_existing_runtime_world_result(world_result, "startup_interaction_sync", "world build failed")
	var counts: Dictionary = _apply_world_root_snapshot(true)
	_refresh_world_runtime_bindings()
	_setup_audio_feedback_controller()
	_configure_runtime_audio_layers()
	_setup_panels()
	_setup_tooltip_layer()
	_setup_drag_preview_layer()
	refresh_all_panels()
	print("Godot game root generated world: %s" % JSON.stringify(counts))


func _consume_startup_request() -> Dictionary:
	return _dictionary_or_empty(runtime_boot_controller.call("consume_startup_request"))


func _build_runtime_from_startup_request(request: Dictionary) -> Dictionary:
	return _dictionary_or_empty(runtime_boot_controller.call("build_runtime_from_startup_request", request))


func _process(delta: float) -> void:
	_update_runtime_performance(delta)
	if runtime_input_controller != null:
		runtime_input_controller.process(delta)
	_process_world_action_queue_completion()
	_update_tooltip_layer()
	_process_auto_tick(delta)


func _input(event: InputEvent) -> void:
	game_input_router.input(self, runtime_input_controller, event)


func _unhandled_input(event: InputEvent) -> void:
	game_input_router.unhandled_input(self, runtime_input_controller, event)


func refresh_hud(selected_prompt: Dictionary = {}) -> void:
	if panel_controller == null:
		return
	_process_audio_feedback()
	runtime_performance_tracker.call("mark_hud_refresh")
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
	if _world_action_presenter_blocks_input():
		return _action_presenter_command_rejected("toggle_stage_panel:%s" % panel_id)
	var result: Dictionary = panel_controller.toggle_stage_panel(panel_id)
	if bool(result.get("success", false)):
		_play_ui_audio_feedback("stage_panel_opened" if bool(result.get("open", false)) else "stage_panel_closed", {
			"panel_id": panel_id,
			"action": "toggle_stage_panel",
		})
		refresh_all_panels(current_interaction_prompt())
	return result


func close_stage_panels() -> Dictionary:
	if panel_controller == null:
		return {"success": false, "reason": "panel_controller_missing"}
	var result: Dictionary = panel_controller.close_stage_panels()
	if bool(result.get("success", false)) and bool(result.get("closed", false)):
		_play_ui_audio_feedback("stage_panel_closed", {
			"panel_id": str(result.get("panel_id", "stage")),
			"action": "close_stage_panels",
		})
	return result


func any_stage_panel_open() -> bool:
	return panel_controller != null and panel_controller.any_stage_panel_open()


func is_settings_open() -> bool:
	return panel_controller != null and panel_controller.is_settings_open()


func gameplay_input_blocked_by_ui() -> bool:
	var hud_blocker := _hud_input_blocker_snapshot()
	if bool(hud_blocker.get("blocked", false)):
		return true
	if panel_controller != null and panel_controller.gameplay_input_blocked():
		return true
	if _world_action_presenter_blocks_input():
		return true
	return false


func gameplay_input_blocker_name() -> String:
	var hud_blocker := _hud_input_blocker_snapshot()
	if bool(hud_blocker.get("blocked", false)):
		return str(hud_blocker.get("name", ""))
	var panel_modal_name := _panel_modal_blocker_name()
	if not panel_modal_name.is_empty():
		return panel_modal_name
	var context_menu: Dictionary = context_menu_snapshot()
	if bool(context_menu.get("active", false)):
		return str(_dictionary_or_empty(context_menu.get("top", {})).get("id", "context_menu"))
	if _world_action_presenter_blocks_input():
		return "world_action_presenter"
	if panel_controller != null and panel_controller.has_method("gameplay_input_blocker_name"):
		return str(panel_controller.gameplay_input_blocker_name())
	return ""


func gameplay_input_blocker_snapshot() -> Dictionary:
	var hud_blocker := _hud_input_blocker_snapshot()
	if bool(hud_blocker.get("blocked", false)):
		return hud_blocker
	var panel_modal_snapshot := _panel_modal_blocker_snapshot()
	if not panel_modal_snapshot.is_empty():
		return panel_modal_snapshot
	var context_menu: Dictionary = context_menu_snapshot()
	if bool(context_menu.get("active", false)):
		var top_menu: Dictionary = _dictionary_or_empty(context_menu.get("top", {}))
		return {
			"blocked": true,
			"name": str(top_menu.get("id", "context_menu")),
			"kind": "context_menu",
			"modal_id": "",
			"panel_id": str(top_menu.get("owner_panel", "")),
			"mouse_blocks_world": bool(top_menu.get("mouse_blocks_world", true)),
			"option_count": int(top_menu.get("option_count", 0)),
		}
	if _world_action_presenter_blocks_input():
		var presenter: Dictionary = world_action_presenter_snapshot()
		return {
			"blocked": true,
			"name": "world_action_presenter",
			"kind": "world_action_presenter",
			"modal_id": "",
			"panel_id": "world",
			"mouse_blocks_world": true,
			"action_kind": str(presenter.get("kind", "")),
			"active_count": int(presenter.get("active_count", 0)),
			"sequence": int(presenter.get("sequence", 0)),
		}
	if panel_controller != null and panel_controller.has_method("gameplay_input_blocker_snapshot"):
		var snapshot: Dictionary = _dictionary_or_empty(panel_controller.call("gameplay_input_blocker_snapshot"))
		if not snapshot.is_empty():
			return snapshot
	var name := gameplay_input_blocker_name()
	return {
		"blocked": not name.is_empty(),
		"name": name,
		"kind": "",
		"modal_id": "",
		"panel_id": "",
		"mouse_blocks_world": not name.is_empty(),
	}


func _hud_input_blocker_snapshot() -> Dictionary:
	if hud != null and hud.has_method("input_blocker_snapshot"):
		return _dictionary_or_empty(hud.call("input_blocker_snapshot"))
	if is_debug_console_open():
		return {
			"blocked": true,
			"name": "debug_console",
			"kind": "debug_console",
			"modal_id": "",
			"panel_id": "hud",
			"mouse_blocks_world": true,
		}
	if hud != null and hud.has_method("is_interaction_menu_open") and bool(hud.is_interaction_menu_open()):
		return {
			"blocked": true,
			"name": "interaction_menu",
			"kind": "context_menu",
			"modal_id": "",
			"panel_id": "hud",
			"mouse_blocks_world": true,
		}
	return {}


func _close_hud_interaction_menu() -> bool:
	var hud_blocker := _hud_input_blocker_snapshot()
	if str(hud_blocker.get("name", "")) != "interaction_menu":
		return false
	if hud != null and hud.has_method("hide_interaction_menu"):
		hud.hide_interaction_menu()
		return true
	return false


func _panel_modal_blocker_name() -> String:
	var snapshot := _panel_modal_blocker_snapshot()
	return str(snapshot.get("name", ""))


func _panel_modal_blocker_snapshot() -> Dictionary:
	if panel_controller == null or not panel_controller.has_method("gameplay_input_blocker_snapshot"):
		return {}
	var snapshot: Dictionary = _dictionary_or_empty(panel_controller.call("gameplay_input_blocker_snapshot"))
	if str(snapshot.get("kind", "")) == "modal":
		return snapshot
	return {}


func _world_action_presenter_blocks_input() -> bool:
	if world_action_flow_controller == null:
		return false
	return bool(world_action_flow_controller.call("blocks_input"))


func modal_stack_snapshot() -> Dictionary:
	if panel_controller != null and panel_controller.has_method("modal_stack_snapshot"):
		return _dictionary_or_empty(panel_controller.call("modal_stack_snapshot"))
	return {"active": false, "count": 0, "top": {}, "stack": []}


func menu_state_snapshot() -> Dictionary:
	if panel_controller != null and panel_controller.has_method("menu_state_snapshot"):
		var panel_snapshot: Dictionary = _dictionary_or_empty(panel_controller.call("menu_state_snapshot")).duplicate(true)
		var panel_priority: Array = _array_or_empty(panel_snapshot.get("close_priority", []))
		panel_snapshot["panel_close_priority"] = panel_priority.duplicate(true)
		panel_snapshot["close_priority"] = _root_close_priority(panel_priority)
		_apply_modal_event_to_menu_state(panel_snapshot)
		_apply_context_menu_event_to_menu_state(panel_snapshot)
		return panel_snapshot
	var fallback_priority: Array[String] = ["settings"]
	var fallback := {
		"active_stage_panel": "",
		"stage_panel_open": false,
		"stage_panels": [],
		"stage_panel_ids": [],
		"settings_open": false,
		"open_panels": [],
		"open_panel_count": 0,
		"gameplay_blocked": false,
		"blocker": {},
		"panel_close_priority": fallback_priority.duplicate(true),
		"close_priority": _root_close_priority(fallback_priority),
	}
	_apply_modal_event_to_menu_state(fallback)
	_apply_context_menu_event_to_menu_state(fallback)
	return fallback


func _apply_modal_event_to_menu_state(menu_state: Dictionary) -> void:
	var modal_stack: Dictionary = modal_stack_snapshot()
	if not bool(modal_stack.get("active", false)):
		menu_state["modal_event"] = {}
		return
	var top_modal: Dictionary = _dictionary_or_empty(modal_stack.get("top", {}))
	var modal_id := str(top_modal.get("id", top_modal.get("modal_id", "modal")))
	var event := {
		"event": "modal_opened",
		"panel_id": modal_id,
		"kind": str(top_modal.get("kind", "modal")),
		"visible": true,
		"reason": "modal_stack_snapshot",
		"owner_panel": str(top_modal.get("owner_panel", "")),
		"mouse_blocks_world": bool(top_modal.get("mouse_blocks_world", true)),
		"blocks_gameplay": bool(top_modal.get("blocks_gameplay", true)),
	}
	if top_modal.has("item_id"):
		event["item_id"] = str(top_modal.get("item_id", ""))
	if top_modal.has("skill_id"):
		event["skill_id"] = str(top_modal.get("skill_id", ""))
	if top_modal.has("count"):
		event["count"] = int(top_modal.get("count", 0))
	event = _append_menu_state_event(menu_state, event)
	menu_state["modal_event"] = event.duplicate(true)


func _apply_context_menu_event_to_menu_state(menu_state: Dictionary) -> void:
	var context_menu: Dictionary = context_menu_snapshot()
	if not bool(context_menu.get("active", false)):
		menu_state["context_menu_event"] = {}
		return
	var top_menu: Dictionary = _dictionary_or_empty(context_menu.get("top", {}))
	var event := {
		"event": "context_menu_opened",
		"panel_id": str(top_menu.get("id", "context_menu")),
		"kind": str(top_menu.get("kind", "context_menu")),
		"visible": true,
		"reason": "context_menu_snapshot",
		"owner_panel": str(top_menu.get("owner_panel", "")),
		"mouse_blocks_world": bool(top_menu.get("mouse_blocks_world", true)),
	}
	event = _append_menu_state_event(menu_state, event)
	menu_state["context_menu_event"] = event.duplicate(true)


func _append_menu_state_event(menu_state: Dictionary, event: Dictionary) -> Dictionary:
	var enriched_event := event.duplicate(true)
	enriched_event["sequence"] = int(menu_state.get("recent_event_count", 0)) + 1
	var recent_events: Array = _array_or_empty(menu_state.get("recent_events", [])).duplicate(true)
	recent_events.append(enriched_event)
	while recent_events.size() > 8:
		recent_events.pop_front()
	menu_state["recent_events"] = recent_events
	menu_state["recent_event_count"] = recent_events.size()
	menu_state["latest_event"] = enriched_event.duplicate(true)
	return enriched_event


func _root_close_priority(panel_priority: Array = []) -> Array[String]:
	var priority: Array[String] = []
	var hud_blocker := _hud_input_blocker_snapshot()
	var hud_blocker_name := str(hud_blocker.get("name", ""))
	if bool(hud_blocker.get("blocked", false)) and not hud_blocker_name.is_empty():
		priority.append(hud_blocker_name)
	var modal_name := _panel_modal_blocker_name()
	if not modal_name.is_empty():
		priority.append(modal_name)
	var context_menu: Dictionary = context_menu_snapshot()
	if bool(context_menu.get("active", false)):
		var top_menu: Dictionary = _dictionary_or_empty(context_menu.get("top", {}))
		var context_menu_id := str(top_menu.get("id", "context_menu"))
		if not context_menu_id.is_empty() and not priority.has(context_menu_id):
			priority.append(context_menu_id)
	if _world_action_presenter_blocks_input():
		priority.append("world_action_presenter")
	if not active_skill_targeting.is_empty():
		priority.append("skill_targeting")
	if runtime_input_controller != null and runtime_input_controller.has_method("has_selection_state") and bool(runtime_input_controller.has_selection_state()):
		priority.append("selection")
	var has_pending := false
	var pending_state: Dictionary = _runtime_pending_state_snapshot()
	if not _dictionary_or_empty(pending_state.get("pending_movement", {})).is_empty() or not _dictionary_or_empty(pending_state.get("pending_interaction", {})).is_empty() or not _dictionary_or_empty(pending_state.get("pending_crafting", {})).is_empty():
		has_pending = true
	for item in panel_priority:
		var id := str(item)
		if id == "settings" and has_pending:
			continue
		if not id.is_empty() and not priority.has(id):
			priority.append(id)
	if has_pending:
		priority.append("pending")
	if priority.is_empty():
		priority.append("settings")
	return priority


func ui_theme_snapshot() -> Dictionary:
	if panel_controller != null and panel_controller.has_method("ui_theme_snapshot"):
		return _dictionary_or_empty(panel_controller.call("ui_theme_snapshot"))
	return {"applied": false, "reason": "panel_controller_missing"}


func context_menu_snapshot() -> Dictionary:
	var menus: Array[Dictionary] = []
	if hud != null and hud.has_method("interaction_menu_snapshot"):
		var interaction_menu: Dictionary = _dictionary_or_empty(hud.call("interaction_menu_snapshot"))
		if not interaction_menu.is_empty():
			menus.append(interaction_menu)
	if inventory_panel != null and inventory_panel.has_method("context_menu_snapshot"):
		var inventory_menu: Dictionary = _dictionary_or_empty(inventory_panel.call("context_menu_snapshot"))
		if not inventory_menu.is_empty():
			menus.append(inventory_menu)
	if container_panel != null and container_panel.has_method("context_menu_snapshot"):
		var container_menu: Dictionary = _dictionary_or_empty(container_panel.call("context_menu_snapshot"))
		if not container_menu.is_empty():
			menus.append(container_menu)
	if trade_panel != null and trade_panel.has_method("context_menu_snapshot"):
		var trade_menu: Dictionary = _dictionary_or_empty(trade_panel.call("context_menu_snapshot"))
		if not trade_menu.is_empty():
			menus.append(trade_menu)
	if skills_panel != null and skills_panel.has_method("context_menu_snapshot"):
		var skills_menu: Dictionary = _dictionary_or_empty(skills_panel.call("context_menu_snapshot"))
		if not skills_menu.is_empty():
			menus.append(skills_menu)
	if character_panel != null and character_panel.has_method("context_menu_snapshot"):
		var character_menu: Dictionary = _dictionary_or_empty(character_panel.call("context_menu_snapshot"))
		if not character_menu.is_empty():
			menus.append(character_menu)
	return {
		"active": not menus.is_empty(),
		"count": menus.size(),
		"top": menus[menus.size() - 1].duplicate(true) if not menus.is_empty() else {},
		"menus": menus,
	}


func hover_tooltip_snapshot(control: Control = null) -> Dictionary:
	return _dictionary_or_empty(tooltip_snapshot_controller.call("hover_tooltip_snapshot", get_viewport(), control))


func hotbar_hit_test_snapshot(screen_position: Vector2 = Vector2(-1.0, -1.0)) -> Dictionary:
	var viewport := get_viewport()
	var position := screen_position
	if position.x < 0.0 or position.y < 0.0:
		position = viewport.get_mouse_position() if viewport != null else Vector2.ZERO
	var inactive := {
		"active": false,
		"owner_panel": "hud",
		"target_kind": "",
		"target_id": "",
		"group_id": "",
		"source_path": "",
		"source_name": "",
		"mouse_blocks_world": false,
		"disabled": false,
		"tooltip": "",
		"screen_position": {"x": position.x, "y": position.y},
		"rect": {},
	}
	if hud == null:
		return inactive
	var controls: Array[Control] = []
	for container_name in ["HotbarDock", "HotbarGroupBar", "ObserveHotbarDock"]:
		_collect_hotbar_hit_controls(hud.find_child(container_name, true, false) as Control, controls)
	for control in controls:
		if control == null or not control.is_inside_tree() or not control.is_visible_in_tree():
			continue
		if not control.get_global_rect().has_point(position):
			continue
		return _hotbar_hit_control_snapshot(control, position)
	return inactive


func _collect_hotbar_hit_controls(control: Control, output: Array[Control]) -> void:
	if control == null:
		return
	if control.has_meta("hotbar_slot_id") or control.has_meta("hotbar_group_id") or _observe_hotbar_meta_key(control) != "":
		output.append(control)
	for child in control.get_children():
		_collect_hotbar_hit_controls(child as Control, output)


func _hotbar_hit_control_snapshot(control: Control, position: Vector2) -> Dictionary:
	var target_kind := "control"
	var target_id := str(control.name)
	var group_id := ""
	if control.has_meta("hotbar_slot_id"):
		target_kind = "hotbar_slot"
		target_id = str(control.get_meta("hotbar_slot_id"))
		group_id = str(control.get_meta("hotbar_group_id", ""))
	elif control.has_meta("hotbar_group_id"):
		target_kind = "hotbar_group"
		target_id = str(control.get_meta("hotbar_group_id"))
		group_id = target_id
	else:
		var observe_key := _observe_hotbar_meta_key(control)
		if not observe_key.is_empty():
			target_kind = "observe_hotbar"
			target_id = observe_key
	var rect := control.get_global_rect()
	var button := control as BaseButton
	var disabled_reason := str(control.get_meta("disabled_reason", ""))
	return {
		"active": true,
		"owner_panel": "hud",
		"target_kind": target_kind,
		"target_id": target_id,
		"group_id": group_id,
		"source_path": str(control.get_path()),
		"source_name": str(control.name),
		"mouse_blocks_world": control.mouse_filter == Control.MOUSE_FILTER_STOP,
		"disabled": button != null and button.disabled,
		"disabled_reason": disabled_reason,
		"disabled_reason_text": _hotbar_hit_disabled_reason_text(disabled_reason),
		"tooltip": str(control.tooltip_text),
		"screen_position": {"x": position.x, "y": position.y},
		"rect": {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y},
	}


func _hotbar_hit_disabled_reason_text(reason: String) -> String:
	if reason.is_empty():
		return ""
	if hud != null and hud.has_method("_disabled_reason_text"):
		return str(hud.call("_disabled_reason_text", reason))
	return reason


func _observe_hotbar_meta_key(control: Control) -> String:
	for key in ["observe_playback", "observe_speed", "auto_tick", "observe_level", "observe_mode"]:
		if control.has_meta(key):
			return key
	return ""


func drag_state_snapshot(data: Variant = {}, hover_target: Control = null) -> Dictionary:
	var drag_data: Dictionary = _dictionary_or_empty(data)
	var target: Dictionary = _drag_hover_target_snapshot(hover_target, drag_data)
	return _dictionary_or_empty(drag_snapshot_controller.call("drag_state_snapshot", get_viewport(), drag_data, target))


func ui_layer_stack_snapshot(drag_data: Variant = {}, drag_hover_target: Control = null, tooltip_control: Control = null) -> Dictionary:
	var blocker: Dictionary = gameplay_input_blocker_snapshot()
	var modal_stack: Dictionary = modal_stack_snapshot()
	var context_menu: Dictionary = context_menu_snapshot()
	var drag: Dictionary = drag_state_snapshot(drag_data, drag_hover_target)
	var tooltip: Dictionary = hover_tooltip_snapshot(tooltip_control)
	var layers: Array[Dictionary] = []
	if bool(blocker.get("blocked", false)) and (str(blocker.get("kind", "")) != "context_menu" or not bool(context_menu.get("active", false))):
		var blocker_kind := str(blocker.get("kind", ""))
		layers.append({
			"id": str(blocker.get("name", "")),
			"kind": blocker_kind,
			"owner_panel": str(blocker.get("panel_id", "")),
			"priority": _ui_layer_priority(blocker_kind, str(blocker.get("name", ""))),
			"mouse_blocks_world": bool(blocker.get("mouse_blocks_world", true)),
			"blocks_gameplay": true,
			"source": "blocker",
		})
	if bool(drag.get("active", false)):
		layers.append({
			"id": "drag_preview",
			"kind": "drag_preview",
			"owner_panel": str(_dictionary_or_empty(drag.get("source", {})).get("owner_panel", "")),
			"priority": _ui_layer_priority("drag_preview", "drag_preview"),
			"mouse_blocks_world": true,
			"blocks_gameplay": true,
			"source": "drag",
			"preview": _dictionary_or_empty(drag.get("preview", {})).duplicate(true),
			"target": _dictionary_or_empty(drag.get("target", {})).duplicate(true),
		})
	if bool(context_menu.get("active", false)):
		var top_menu: Dictionary = _dictionary_or_empty(context_menu.get("top", {}))
		layers.append({
			"id": str(top_menu.get("id", "context_menu")),
			"kind": str(top_menu.get("kind", "context_menu")),
			"owner_panel": str(top_menu.get("owner_panel", "hud")),
			"priority": _ui_layer_priority("context_menu", str(top_menu.get("id", ""))),
			"mouse_blocks_world": true,
			"blocks_gameplay": true,
			"source": "context_menu",
			"option_count": int(top_menu.get("option_count", 0)),
		})
	if bool(tooltip.get("active", false)):
		layers.append({
			"id": "tooltip",
			"kind": "tooltip",
			"owner_panel": str(tooltip.get("owner_panel", "")),
			"priority": _ui_layer_priority("tooltip", "tooltip"),
			"mouse_blocks_world": false,
			"blocks_gameplay": false,
			"source": "tooltip",
			"text": str(tooltip.get("text", "")),
			"source_path": str(tooltip.get("source_path", "")),
			"source_name": str(tooltip.get("source_name", "")),
			"screen_position": _dictionary_or_empty(tooltip.get("screen_position", {})).duplicate(true),
			"source_rect": _dictionary_or_empty(tooltip.get("source_rect", {})).duplicate(true),
			"viewport_size": _dictionary_or_empty(tooltip.get("viewport_size", {})).duplicate(true),
			"lifecycle_state": str(tooltip.get("lifecycle_state", "")),
			"delay_policy": str(tooltip.get("delay_policy", "")),
			"visual": _dictionary_or_empty(tooltip.get("visual", {})).duplicate(true),
			"recommended_rect": _dictionary_or_empty(tooltip.get("recommended_rect", {})).duplicate(true),
		})
	layers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ap := int(a.get("priority", 0))
		var bp := int(b.get("priority", 0))
		if ap == bp:
			return str(a.get("id", "")) < str(b.get("id", ""))
		return ap > bp
	)
	var top_blocking: Dictionary = {}
	for layer in layers:
		var layer_data: Dictionary = _dictionary_or_empty(layer)
		if bool(layer_data.get("blocks_gameplay", false)) or bool(layer_data.get("mouse_blocks_world", false)):
			top_blocking = layer_data.duplicate(true)
			break
	return {
		"active": not layers.is_empty(),
		"count": layers.size(),
		"blocks_world": not top_blocking.is_empty(),
		"top": layers[0].duplicate(true) if not layers.is_empty() else {},
		"top_blocking": top_blocking,
		"layers": layers,
		"blocker": blocker,
		"modal_stack": modal_stack,
		"context_menu": context_menu,
		"drag": drag,
		"tooltip": tooltip,
	}


func _setup_tooltip_layer() -> void:
	ui_overlay_render_controller.call("setup_tooltip_layer", self)


func _update_tooltip_layer() -> void:
	_setup_tooltip_layer()
	var snapshot: Dictionary = hover_tooltip_snapshot()
	if not bool(snapshot.get("active", false)):
		_hide_tooltip_layer(str(snapshot.get("lifecycle_state", "inactive")))
		return
	_render_tooltip_snapshot(snapshot)


func _hide_tooltip_layer(reason: String) -> void:
	ui_overlay_render_controller.call("hide_tooltip_layer", reason)


func _render_tooltip_snapshot(snapshot: Dictionary) -> void:
	ui_overlay_render_controller.call("render_tooltip_snapshot", self, snapshot)


func _setup_drag_preview_layer() -> void:
	ui_overlay_render_controller.call("setup_drag_preview_layer", self)


func render_drag_preview_for_snapshot(drag_data: Variant = {}, hover_target: Control = null) -> Dictionary:
	var drag: Dictionary = drag_state_snapshot(drag_data, hover_target)
	if not bool(drag.get("active", false)):
		_hide_drag_preview_layer("inactive")
		return drag_preview_render_snapshot()
	_render_drag_preview_snapshot(drag)
	return drag_preview_render_snapshot()


func _hide_drag_preview_layer(reason: String) -> void:
	ui_overlay_render_controller.call("hide_drag_preview_layer", reason)


func _render_drag_preview_snapshot(drag: Dictionary) -> void:
	ui_overlay_render_controller.call("render_drag_preview_snapshot", self, drag)


func handle_trade_shortcut(event: InputEventKey) -> bool:
	if panel_controller == null:
		return false
	return panel_controller.handle_trade_shortcut(event)


func toggle_controls_hint() -> Dictionary:
	if hud == null or not hud.has_method("toggle_controls_hint"):
		return {"success": false, "reason": "hud_missing"}
	var result: Dictionary = hud.toggle_controls_hint()
	refresh_hud(current_interaction_prompt())
	_play_hud_shortcut_audio("ui_button_pressed", "ControlsHintShortcut", "keyboard_shortcut", "toggle_controls_hint", {
		"value": "on" if bool(result.get("visible", false)) else "off",
	})
	return result


func controls_hint_visible() -> bool:
	return hud != null and hud.has_method("is_controls_hint_visible") and bool(hud.is_controls_hint_visible())


func toggle_debug_console() -> Dictionary:
	if hud == null or not hud.has_method("toggle_debug_console"):
		return {"success": false, "reason": "hud_missing"}
	var result: Dictionary = hud.toggle_debug_console()
	refresh_hud(current_interaction_prompt())
	_play_hud_shortcut_audio("ui_button_pressed", "DebugConsoleShortcut", "keyboard_shortcut", "toggle_debug_console", {
		"value": "open" if bool(result.get("visible", false)) else "close",
	})
	return result


func close_debug_console() -> Dictionary:
	if hud == null or not hud.has_method("hide_debug_console"):
		return {"success": false, "reason": "hud_missing"}
	hud.hide_debug_console()
	refresh_hud(current_interaction_prompt())
	return {"success": true, "visible": false}


func is_debug_console_open() -> bool:
	return hud != null and hud.has_method("is_debug_console_open") and bool(hud.is_debug_console_open())


func debug_console_snapshot() -> Dictionary:
	if hud != null and hud.has_method("debug_console_snapshot"):
		var snapshot: Dictionary = hud.debug_console_snapshot()
		snapshot["permission"] = debug_runtime_controller.permission_snapshot(self)
		return snapshot
	return {
		"visible": false,
		"history": [],
		"history_count": 0,
		"suggestions": [],
		"suggestion_count": 0,
		"input_text": "",
		"permission": debug_runtime_controller.permission_snapshot(self),
	}


func submit_debug_console_command(command_text: String) -> Dictionary:
	var command := command_text.strip_edges()
	var result: Dictionary = _execute_debug_console_command(command)
	if hud != null and hud.has_method("set_debug_console_result"):
		hud.set_debug_console_result(command, result)
	refresh_all_panels(current_interaction_prompt())
	_play_hud_shortcut_audio("ui_button_pressed", "DebugConsoleInput", "text_submit", "submit_debug_console_command", {
		"value": command,
		"reason": str(result.get("reason", "")),
	})
	return result


func _execute_debug_console_command(command: String) -> Dictionary:
	return debug_runtime_controller.execute(self, command)


func controls_hint_snapshot() -> Dictionary:
	if hud != null and hud.has_method("controls_hint_snapshot"):
		return hud.controls_hint_snapshot()
	return {"visible": false, "line_count": 0, "lines": []}


func toggle_debug_panel() -> Dictionary:
	if hud == null or not hud.has_method("toggle_debug_panel"):
		return {"success": false, "reason": "hud_missing"}
	var result: Dictionary = hud.toggle_debug_panel()
	refresh_hud(current_interaction_prompt())
	_play_hud_shortcut_audio("ui_button_pressed", "DebugPanelShortcut", "keyboard_shortcut", "toggle_debug_panel", {
		"value": "open" if bool(result.get("visible", false)) else "close",
	})
	return result


func is_debug_panel_open() -> bool:
	return hud != null and hud.has_method("is_debug_panel_open") and bool(hud.is_debug_panel_open())


func debug_panel_snapshot() -> Dictionary:
	if hud != null and hud.has_method("debug_panel_snapshot"):
		return hud.debug_panel_snapshot()
	return {"visible": false, "line_count": 0, "lines": []}


func cycle_debug_overlay_mode() -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(debug_runtime_controller.call("cycle_debug_overlay_mode"))
	_refresh_debug_overlay()
	refresh_hud(current_interaction_prompt())
	_play_hud_shortcut_audio("ui_option_selected", "DebugOverlayShortcut", "keyboard_shortcut", "cycle_debug_overlay", {
		"value": current_debug_overlay_mode(),
	})
	return result


func current_debug_overlay_mode() -> String:
	return str(debug_runtime_controller.call("current_debug_overlay_mode"))


func debug_overlay_snapshot() -> Dictionary:
	if world_root != null and world_root.has_method("debug_overlay_snapshot"):
		return _dictionary_or_empty(world_root.call("debug_overlay_snapshot"))
	return {"active": false, "mode": "off", "cell_count": 0}


func toggle_auto_tick() -> Dictionary:
	if has_active_dialogue() or gameplay_input_blocked_by_ui():
		return runtime_control_state_controller.call("toggle_auto_tick", true)
	var result: Dictionary = _dictionary_or_empty(runtime_control_state_controller.call("toggle_auto_tick", false))
	if bool(result.get("success", false)):
		refresh_hud(current_interaction_prompt())
	return result


func is_auto_tick_enabled() -> bool:
	return auto_tick_enabled


func is_observe_mode_enabled() -> bool:
	return observe_mode_enabled


func can_issue_player_commands() -> bool:
	return not observe_mode_enabled and not _world_action_presenter_blocks_input() and _panel_modal_blocker_name().is_empty()


func toggle_observe_mode() -> Dictionary:
	return set_observe_mode(not is_observe_mode_enabled())


func set_observe_mode(enabled: bool) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(runtime_control_state_controller.call("set_observe_mode", enabled, gameplay_input_blocked_by_ui()))
	if bool(result.get("success", false)):
		refresh_hud(current_interaction_prompt())
	return result


func toggle_observe_playback() -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(runtime_control_state_controller.call("toggle_observe_playback", has_active_dialogue() or gameplay_input_blocked_by_ui()))
	if bool(result.get("success", false)):
		refresh_hud(current_interaction_prompt())
	return result


func cycle_observe_speed() -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(runtime_control_state_controller.call("cycle_observe_speed"))
	if bool(result.get("success", false)):
		refresh_hud(current_interaction_prompt())
	return result


func set_observe_speed(speed_id: String) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(runtime_control_state_controller.call("set_observe_speed", speed_id))
	if bool(result.get("success", false)):
		refresh_hud(current_interaction_prompt())
	return result


func cycle_info_panel(direction: int) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(runtime_control_state_controller.call("cycle_info_panel", direction))
	if not bool(result.get("success", false)):
		return result
	refresh_hud(current_interaction_prompt())
	var page := current_info_panel_page()
	_play_hud_shortcut_audio("ui_option_selected", "InfoPanelShortcut", "keyboard_shortcut", "cycle_info_panel", {
		"value": str(page.get("id", "")),
		"count": int(result.get("count", info_panel_pages.size())),
		"option_index": int(result.get("index", active_info_panel_index)),
	})
	return result


func current_info_panel_page() -> Dictionary:
	return _dictionary_or_empty(runtime_control_state_controller.call("current_info_panel_page"))


func info_panel_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_control_state_controller.call("info_panel_snapshot"))


func runtime_control_snapshot() -> Dictionary:
	var snapshot: Dictionary = _dictionary_or_empty(runtime_control_state_controller.call("runtime_control_snapshot"))
	snapshot["observe_interval_sec"] = _auto_tick_interval_sec()
	snapshot["world_time"] = runtime_world_time_snapshot()
	snapshot["map_level"] = map_level_snapshot()
	snapshot["focused_actor"] = focused_actor_snapshot()
	snapshot["ui_blocker"] = gameplay_input_blocker_name()
	snapshot["ui_blocker_snapshot"] = gameplay_input_blocker_snapshot()
	snapshot["modal_stack"] = modal_stack_snapshot()
	snapshot["menu_state"] = menu_state_snapshot()
	snapshot["ui_theme"] = ui_theme_snapshot()
	snapshot["ui_layer_stack"] = ui_layer_stack_snapshot()
	snapshot["context_menu"] = context_menu_snapshot()
	snapshot["controls_hint"] = controls_hint_snapshot()
	snapshot["debug_console"] = debug_console_snapshot()
	snapshot["debug_panel"] = debug_panel_snapshot()
	snapshot["hover"] = runtime_hover_snapshot()
	snapshot["tooltip"] = hover_tooltip_snapshot()
	snapshot["tooltip_render"] = tooltip_render_snapshot()
	snapshot["hotbar_hit_test"] = hotbar_hit_test_snapshot()
	snapshot["drag"] = drag_state_snapshot()
	snapshot["drag_preview_render"] = drag_preview_render_snapshot()
	snapshot["selection_debug"] = runtime_selection_debug_snapshot()
	snapshot["action_presenter"] = world_action_presenter_snapshot()
	snapshot["world_action_queue"] = world_action_queue_snapshot()
	snapshot["ai_debug"] = ai_debug_snapshot()
	snapshot["debug_overlay"] = debug_overlay_snapshot()
	snapshot["audio_feedback"] = audio_feedback_snapshot()
	snapshot["performance"] = runtime_performance_snapshot()
	snapshot["skill_targeting"] = _skill_targeting_snapshot()
	snapshot["player_command_authority_audit"] = player_command_authority_audit_snapshot()
	return snapshot


func tooltip_render_snapshot() -> Dictionary:
	return last_tooltip_render_snapshot.duplicate(true)


func drag_preview_render_snapshot() -> Dictionary:
	return last_drag_preview_render_snapshot.duplicate(true)


func player_command_authority_audit_snapshot() -> Dictionary:
	return _dictionary_or_empty(player_command_authority_audit.call("snapshot", debug_runtime_controller, self))


func _debug_console_mutation_authority_audit() -> Dictionary:
	return _dictionary_or_empty(player_command_authority_audit.call("debug_console_mutation_authority_audit", debug_runtime_controller, self))


func ai_debug_snapshot() -> Dictionary:
	return _dictionary_or_empty(ai_debug_snapshot_builder.call("snapshot", simulation, focused_actor_snapshot()))


func runtime_world_time_snapshot() -> Dictionary:
	return _dictionary_or_empty(world_time_snapshot_builder.call("snapshot", simulation))


func world_action_presenter_snapshot() -> Dictionary:
	if world_action_flow_controller == null:
		return {"active": false, "kind": "missing"}
	return _dictionary_or_empty(world_action_flow_controller.call("presenter_snapshot"))


func world_action_queue_snapshot() -> Dictionary:
	if world_action_flow_controller == null:
		return {"active": false, "state": "idle", "sequence": 0}
	return _dictionary_or_empty(world_action_flow_controller.call("snapshot"))


func audio_feedback_snapshot() -> Dictionary:
	if audio_feedback_controller == null or not audio_feedback_controller.has_method("snapshot"):
		return {"enabled": false, "reason": "audio_feedback_missing"}
	return _dictionary_or_empty(audio_feedback_controller.call("snapshot"))


func play_ui_audio_feedback(event_kind: String, payload: Dictionary = {}) -> Dictionary:
	return _play_ui_audio_feedback(event_kind, payload)


func play_spatial_audio_feedback(event_kind: String, payload: Dictionary = {}, position: Vector3 = Vector3.ZERO) -> Dictionary:
	if audio_feedback_controller == null or not audio_feedback_controller.has_method("play_spatial_feedback"):
		return {"enabled": false, "reason": "audio_feedback_missing"}
	return _dictionary_or_empty(audio_feedback_controller.call("play_spatial_feedback", event_kind, payload, position))


func _play_hud_shortcut_audio(event_kind: String, control_name: String, control_kind: String, action: String, extra_payload: Dictionary = {}) -> Dictionary:
	var payload := {
		"audio_source": "ui",
		"panel_id": "hud",
		"control_name": control_name,
		"control_kind": control_kind,
		"action": action,
	}
	for key in extra_payload.keys():
		payload[key] = extra_payload[key]
	return _play_ui_audio_feedback(event_kind, payload)


func finish_world_action_presentations() -> Dictionary:
	if world_action_flow_controller == null or not world_action_flow_controller.has_method("finish_active_presentations"):
		return world_action_presenter_snapshot()
	var result: Dictionary = _dictionary_or_empty(world_action_flow_controller.call("finish_active_presentations"))
	var applied_refresh := _apply_pending_world_action_final_refresh("presenter_finished")
	if not _apply_pending_world_action_ui("presenter_finished") and not applied_refresh:
		refresh_hud(current_interaction_prompt())
	return result


func _ai_debug_intent_summary(intent: Dictionary) -> Dictionary:
	return _dictionary_or_empty(ai_debug_snapshot_builder.call("intent_summary", intent))


func _ai_life_status_id(intent_kind: String, planner_action_id: String, reason: String) -> String:
	return str(ai_debug_snapshot_builder.call("life_status_id", intent_kind, planner_action_id, reason))


func _ai_life_status_group(state_id: String, planner_action_id: String) -> String:
	return str(ai_debug_snapshot_builder.call("life_status_group", state_id, planner_action_id))


func runtime_performance_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_performance_tracker.call("snapshot", _last_pathfinding_time_ms(), _last_pathfinding_visited_cell_count()))


func runtime_hover_snapshot() -> Dictionary:
	if runtime_input_controller != null and runtime_input_controller.has_method("hover_state_snapshot"):
		return runtime_input_controller.hover_state_snapshot()
	return {"active": false}


func runtime_selection_debug_snapshot() -> Dictionary:
	if runtime_input_controller != null and runtime_input_controller.has_method("selection_debug_snapshot"):
		return runtime_input_controller.selection_debug_snapshot()
	return {"active": false, "kind": "", "hovered_grid": {}, "blocker_name": "", "prompt": {"has_prompt": false}}


func _update_runtime_performance(delta: float) -> void:
	runtime_performance_tracker.call("update_process", delta)


func _last_pathfinding_time_ms() -> float:
	var hover: Dictionary = runtime_hover_snapshot()
	var move_preview: Dictionary = _dictionary_or_empty(hover.get("move_preview", {}))
	return float(move_preview.get("pathfinding_time_ms", 0.0))


func _last_pathfinding_visited_cell_count() -> int:
	var hover: Dictionary = runtime_hover_snapshot()
	var move_preview: Dictionary = _dictionary_or_empty(hover.get("move_preview", {}))
	return int(move_preview.get("visited_cell_count", 0))


func _vector2_snapshot(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


func _owner_panel_for_control(control: Control) -> String:
	var current: Node = control
	while current != null:
		match str(current.name):
			"Hud":
				return "hud"
			"HUD":
				return "hud"
			"InventoryPanel":
				return "inventory"
			"CharacterPanel":
				return "character"
			"SkillsPanel":
				return "skills"
			"JournalPanel":
				return "journal"
			"CraftingPanel":
				return "crafting"
			"TradePanel":
				return "trade"
			"ContainerPanel":
				return "container"
			"DialoguePanel":
				return "dialogue"
			"SettingsPanel":
				return "settings"
		current = current.get_parent()
	return ""


func _ui_layer_priority(kind: String, layer_id: String) -> int:
	if layer_id == "debug_console" or kind == "debug_console":
		return 1000
	if kind == "modal" or layer_id.begins_with("modal:"):
		return 900
	if kind == "drag_preview":
		return 800
	if kind == "context_menu" or layer_id == "interaction_menu":
		return 700
	if kind in ["stage", "settings", "panel", "world_action_presenter"]:
		return 600
	if kind == "tooltip":
		return 100
	return 0


func _drag_hover_target_snapshot(control: Control, drag_data: Dictionary = {}) -> Dictionary:
	if control == null:
		return _enrich_drag_hover_target_reason({"active": false, "owner_panel": "", "target_kind": "", "target_id": "", "source_path": "", "accepts": "", "last_accept": false, "reject_reason": "", "reject_reason_text": "", "hover_highlight": _drag_hover_highlight(false, "", "", "", false)})
	var target := {
		"active": true,
		"owner_panel": _owner_panel_for_control(control),
		"target_kind": "control",
		"target_id": str(control.name),
		"source_path": str(control.get_path()),
		"accepts": "",
		"last_accept": false,
		"reject_reason": "",
		"reject_reason_text": "",
		"hover_highlight": _drag_hover_highlight(false, "", "", "", false),
	}
	if control.has_meta("equipment_slot"):
		var equipment_target: Dictionary = _equipment_drag_hover_target_snapshot(control, drag_data)
		for key in equipment_target:
			target[key] = equipment_target[key]
	elif control.has_meta("hotbar_slot_id"):
		var hotbar_target: Dictionary = _hotbar_slot_drag_hover_target_snapshot(control, drag_data)
		for key in hotbar_target:
			target[key] = hotbar_target[key]
	elif control.has_meta("hotbar_group_id"):
		var hotbar_group_target: Dictionary = _hotbar_group_drag_hover_target_snapshot(control, drag_data)
		for key in hotbar_group_target:
			target[key] = hotbar_group_target[key]
	elif control.has_meta("inventory_action_target"):
		var inventory_action_target: Dictionary = _inventory_action_drag_hover_target_snapshot(control, drag_data)
		for key in inventory_action_target:
			target[key] = inventory_action_target[key]
	elif control.has_meta("container_source"):
		var container_target: Dictionary = _container_drag_hover_target_snapshot(control, drag_data)
		for key in container_target:
			target[key] = container_target[key]
	elif control.has_meta("trade_drop_zone"):
		var trade_drop_target: Dictionary = _trade_drop_zone_drag_hover_target_snapshot(control, drag_data)
		for key in trade_drop_target:
			target[key] = trade_drop_target[key]
	elif control.has_meta("cart_index"):
		var cart_entry_target: Dictionary = _trade_cart_drag_hover_target_snapshot(control, drag_data, "trade_cart_entry", str(control.get_meta("cart_index")))
		for key in cart_entry_target:
			target[key] = cart_entry_target[key]
	elif control.has_meta("trade_cart_target"):
		var cart_target: Dictionary = _trade_cart_drag_hover_target_snapshot(control, drag_data, "trade_cart", str(control.get_meta("trade_cart_target")))
		for key in cart_target:
			target[key] = cart_target[key]
	else:
		var observe_key := _observe_hotbar_meta_key(control)
		if not observe_key.is_empty():
			var observe_target: Dictionary = _observe_hotbar_drag_hover_target_snapshot(control, drag_data, observe_key)
			for key in observe_target:
				target[key] = observe_target[key]
	return _enrich_drag_hover_target_reason(target)


func _enrich_drag_hover_target_reason(target: Dictionary) -> Dictionary:
	var reject_reason := str(target.get("reject_reason", ""))
	var reject_text := _drag_reject_reason_text(reject_reason)
	target["reject_reason_text"] = reject_text
	var highlight: Dictionary = _dictionary_or_empty(target.get("hover_highlight", {})).duplicate(true)
	highlight["reject_reason_text"] = reject_text
	target["hover_highlight"] = highlight
	return target


func _drag_reject_reason_text(reason: String) -> String:
	if reason.is_empty():
		return ""
	return str(reason_catalog.call("disabled_text_for", reason))


func _observe_hotbar_drag_hover_target_snapshot(_control: Control, drag_data: Dictionary, observe_key: String) -> Dictionary:
	var reject_reason := "observe_hotbar_drag_unsupported" if not drag_data.is_empty() else ""
	return {
		"target_kind": "observe_hotbar",
		"target_id": observe_key,
		"observe_key": observe_key,
		"accepts": "",
		"last_accept": false,
		"reject_reason": reject_reason,
		"hover_highlight": _drag_hover_highlight(not drag_data.is_empty(), "observe_hotbar", observe_key, reject_reason, false),
	}


func _hotbar_slot_drag_hover_target_snapshot(control: Control, drag_data: Dictionary) -> Dictionary:
	var slot_id := str(control.get_meta("hotbar_slot_id", ""))
	var group_id := str(control.get_meta("hotbar_group_id", ""))
	var acceptance: Dictionary = _hotbar_slot_drag_acceptance(slot_id, drag_data)
	var last_accept := bool(acceptance.get("accept", false))
	var reject_reason := str(acceptance.get("reason", ""))
	return {
		"target_kind": "hotbar_slot",
		"target_id": slot_id,
		"slot_id": slot_id,
		"group_id": group_id,
		"accepts": "skill_hotbar",
		"last_accept": last_accept,
		"reject_reason": reject_reason,
		"hover_highlight": _drag_hover_highlight(not drag_data.is_empty(), "hotbar_slot", slot_id, reject_reason, last_accept),
	}


func _hotbar_slot_drag_acceptance(slot_id: String, drag_data: Dictionary) -> Dictionary:
	if drag_data.is_empty():
		return {"accept": false, "reason": ""}
	if str(drag_data.get("kind", "")) != "skill_hotbar":
		return {"accept": false, "reason": "hotbar_slot_requires_skill_hotbar"}
	if str(drag_data.get("skill_id", "")).is_empty():
		return {"accept": false, "reason": "hotbar_slot_missing_skill"}
	if slot_id.is_empty():
		return {"accept": false, "reason": "hotbar_slot_missing_slot"}
	return {"accept": true, "reason": ""}


func _hotbar_group_drag_hover_target_snapshot(control: Control, drag_data: Dictionary) -> Dictionary:
	var group_id := str(control.get_meta("hotbar_group_id", ""))
	var reject_reason := "hotbar_group_drag_unsupported" if not drag_data.is_empty() else ""
	return {
		"target_kind": "hotbar_group",
		"target_id": group_id,
		"group_id": group_id,
		"accepts": "",
		"last_accept": false,
		"reject_reason": reject_reason,
		"hover_highlight": _drag_hover_highlight(not drag_data.is_empty(), "hotbar_group", group_id, reject_reason, false),
	}


func _trade_cart_drag_hover_target_snapshot(control: Control, drag_data: Dictionary, target_kind: String, target_id: String) -> Dictionary:
	var acceptance: Dictionary = _trade_cart_drag_acceptance(control, drag_data)
	var last_accept := bool(acceptance.get("accept", false))
	var reject_reason := str(acceptance.get("reason", ""))
	return {
		"target_kind": target_kind,
		"target_id": target_id,
		"accepts": "trade_item,inventory_item,trade_cart_entry",
		"last_accept": last_accept,
		"reject_reason": reject_reason,
		"hover_highlight": _drag_hover_highlight(not drag_data.is_empty(), target_kind, target_id, reject_reason, last_accept),
	}


func _trade_drop_zone_drag_hover_target_snapshot(control: Control, drag_data: Dictionary) -> Dictionary:
	var zone_id := str(control.get_meta("trade_drop_zone", ""))
	var acceptance: Dictionary = _trade_drop_zone_drag_acceptance(control, drag_data)
	var last_accept := bool(acceptance.get("accept", false))
	var reject_reason := str(acceptance.get("reason", ""))
	return {
		"target_kind": "trade_drop_zone",
		"target_id": zone_id,
		"zone_id": zone_id,
		"accepts": str(control.get_meta("trade_drop_accepts", "")),
		"last_accept": last_accept,
		"reject_reason": reject_reason,
		"last_source": str(acceptance.get("source", control.get_meta("trade_drop_last_source", ""))),
		"last_preview_text": str(control.get_meta("trade_drop_last_preview_text", "")),
		"hover_highlight": _drag_hover_highlight(not drag_data.is_empty(), "trade_drop_zone", zone_id, reject_reason, last_accept),
	}


func _trade_drop_zone_drag_acceptance(control: Control, drag_data: Dictionary) -> Dictionary:
	if drag_data.is_empty():
		return {"accept": bool(control.get_meta("trade_drop_last_accept", false)), "reason": str(control.get_meta("trade_drop_last_reject_reason", "")), "source": str(control.get_meta("trade_drop_last_source", ""))}
	var zone_id := str(control.get_meta("trade_drop_zone", ""))
	match str(drag_data.get("kind", "")):
		"trade_item":
			var source := str(drag_data.get("source", ""))
			if source.is_empty():
				return {"accept": false, "reason": "unknown_trade_item", "source": source}
			if not _trade_drop_zone_source_matches(zone_id, source):
				return {"accept": false, "reason": str(control.get_meta("trade_drop_reject_reason", "drop_zone_source_mismatch")), "source": source}
			return {"accept": true, "reason": "", "source": source}
		"inventory_item":
			var item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
			var item_id := str(drag_data.get("item_id", item.get("item_id", "")))
			if item_id.is_empty():
				return {"accept": false, "reason": "unknown_trade_item", "source": "player"}
			if not _trade_drop_zone_source_matches(zone_id, "player"):
				return {"accept": false, "reason": str(control.get_meta("trade_drop_reject_reason", "drop_zone_source_mismatch")), "source": "player"}
			return {"accept": true, "reason": "", "source": "player"}
		"trade_cart_entry":
			return {"accept": false, "reason": "cart_entry_requires_cart_target", "source": "cart"}
	return {"accept": false, "reason": "trade_cart_unsupported_drag_data", "source": ""}


func _trade_drop_zone_source_matches(zone_id: String, source: String) -> bool:
	match zone_id:
		"buy":
			return source == "shop"
		"sell":
			return source == "player" or source.begins_with("equipment:")
	return true


func _trade_cart_drag_acceptance(control: Control, drag_data: Dictionary) -> Dictionary:
	if drag_data.is_empty():
		return {"accept": false, "reason": ""}
	match str(drag_data.get("kind", "")):
		"trade_item":
			var item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
			if item.is_empty():
				return {"accept": false, "reason": "unknown_trade_item"}
			return {"accept": true, "reason": ""}
		"inventory_item":
			var item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
			var item_id := str(drag_data.get("item_id", item.get("item_id", "")))
			if item_id.is_empty():
				return {"accept": false, "reason": "unknown_trade_item"}
			return {"accept": true, "reason": ""}
		"trade_cart_entry":
			var index := int(drag_data.get("index", -1))
			if index < 0:
				return {"accept": false, "reason": "cart_entry_missing_index"}
			if control != null and control.has_meta("trade_drop_zone"):
				return {"accept": false, "reason": "cart_entry_requires_cart_target"}
			return {"accept": true, "reason": ""}
	return {"accept": false, "reason": "trade_cart_unsupported_drag_data"}


func _container_drag_hover_target_snapshot(control: Control, drag_data: Dictionary) -> Dictionary:
	var column_source := str(control.get_meta("container_source", ""))
	var acceptance: Dictionary = _container_drag_acceptance(column_source, drag_data)
	var last_accept := bool(acceptance.get("accept", false))
	var reject_reason := str(acceptance.get("reason", ""))
	return {
		"target_kind": "container_column",
		"target_id": column_source,
		"column_source": column_source,
		"accepts": "container_item,inventory_item",
		"last_accept": last_accept,
		"reject_reason": reject_reason,
		"hover_highlight": _drag_hover_highlight(not drag_data.is_empty(), "container_column", column_source, reject_reason, last_accept),
	}


func _container_drag_acceptance(column_source: String, drag_data: Dictionary) -> Dictionary:
	if drag_data.is_empty():
		return {"accept": false, "reason": ""}
	if column_source.is_empty():
		return {"accept": false, "reason": "container_drop_target_missing"}
	match str(drag_data.get("kind", "")):
		"container_item":
			var source := str(drag_data.get("source", ""))
			var item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
			var item_id := str(item.get("item_id", ""))
			if source.is_empty():
				return {"accept": false, "reason": "container_drop_source_missing"}
			if item_id.is_empty():
				return {"accept": false, "reason": "container_drop_item_missing"}
			if source == column_source:
				return {"accept": false, "reason": "container_drop_same_column"}
			return {"accept": true, "reason": ""}
		"inventory_item":
			var item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
			var item_id := str(drag_data.get("item_id", item.get("item_id", "")))
			if item_id.is_empty():
				return {"accept": false, "reason": "container_drop_item_missing"}
			if column_source != "container":
				return {"accept": false, "reason": "container_drop_requires_container_column"}
			return {"accept": true, "reason": ""}
	return {"accept": false, "reason": "container_drop_unsupported_drag_data"}


func _inventory_action_drag_hover_target_snapshot(control: Control, drag_data: Dictionary) -> Dictionary:
	var action_id := str(control.get_meta("inventory_action_target", ""))
	var acceptance: Dictionary = _inventory_action_drag_acceptance(action_id, drag_data)
	var last_accept := bool(acceptance.get("accept", false))
	var reject_reason := str(acceptance.get("reason", ""))
	return {
		"target_kind": "inventory_action",
		"target_id": action_id,
		"action_id": action_id,
		"accepts": "inventory_item",
		"last_accept": last_accept,
		"reject_reason": reject_reason,
		"hover_highlight": _drag_hover_highlight(not drag_data.is_empty(), "inventory_action", action_id, reject_reason, last_accept),
	}


func _inventory_action_drag_acceptance(action_id: String, drag_data: Dictionary) -> Dictionary:
	if drag_data.is_empty():
		return {"accept": false, "reason": ""}
	if str(drag_data.get("kind", "")) != "inventory_item":
		return {"accept": false, "reason": "inventory_action_requires_inventory_item"}
	var item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
	var item_id := str(drag_data.get("item_id", item.get("item_id", "")))
	if item_id.is_empty():
		return {"accept": false, "reason": "inventory_action_missing_item"}
	match action_id:
		"equip":
			if _array_or_empty(item.get("equip_slots", [])).is_empty():
				return {"accept": false, "reason": "item_not_equippable"}
			return {"accept": true, "reason": ""}
		"drop":
			if not bool(item.get("droppable", true)):
				return {"accept": false, "reason": "item_not_droppable"}
			if int(item.get("count", 0)) <= 0:
				return {"accept": false, "reason": "invalid_quantity"}
			return {"accept": true, "reason": ""}
	return {"accept": false, "reason": "unknown_inventory_action"}


func _equipment_drag_hover_target_snapshot(control: Control, drag_data: Dictionary) -> Dictionary:
	var slot_id := str(control.get_meta("equipment_slot", ""))
	var display_slot := str(control.get_meta("equipment_display_slot", slot_id))
	var equipment_data: Dictionary = _dictionary_or_empty(control.get_meta("equipment_data", {}))
	var acceptance: Dictionary = _equipment_drag_acceptance(slot_id, drag_data)
	var last_accept := bool(acceptance.get("accept", false))
	var reject_reason := str(acceptance.get("reason", ""))
	return {
		"target_kind": "equipment_slot",
		"target_id": slot_id,
		"slot_id": slot_id,
		"display_slot": display_slot,
		"accepts": "inventory_item",
		"last_accept": last_accept,
		"reject_reason": reject_reason,
		"current_item_id": str(equipment_data.get("item_id", "")),
		"current_item_name": str(equipment_data.get("name", equipment_data.get("item_id", ""))),
		"hover_highlight": _drag_hover_highlight(not drag_data.is_empty(), "equipment_slot", slot_id, reject_reason, last_accept),
	}


func _equipment_drag_acceptance(slot_id: String, drag_data: Dictionary) -> Dictionary:
	if drag_data.is_empty():
		return {"accept": false, "reason": ""}
	if str(drag_data.get("kind", "")) != "inventory_item":
		return {"accept": false, "reason": "equipment_slot_requires_inventory_item"}
	var item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
	var item_id := str(drag_data.get("item_id", item.get("item_id", "")))
	if item_id.is_empty():
		return {"accept": false, "reason": "equipment_slot_missing_item"}
	if slot_id.is_empty():
		return {"accept": false, "reason": "equipment_slot_missing_slot"}
	for candidate in _array_or_empty(item.get("equip_slots", [])):
		if str(candidate) == slot_id:
			return {"accept": true, "reason": ""}
	return {"accept": false, "reason": "equipment_slot_incompatible"}


func _drag_hover_highlight(active: bool, target_kind: String, target_id: String, reject_reason: String, accepted: bool) -> Dictionary:
	var style := "accept" if accepted else "reject"
	var color := "#4ecb71" if accepted else "#e25c5c"
	if not active:
		style = "inactive"
		color = "#00000000"
	return {
		"active": active,
		"style": style,
		"color": color,
		"target_kind": target_kind,
		"target_id": target_id,
		"accepted": accepted,
		"reject_reason": reject_reason,
		"reject_reason_text": _drag_reject_reason_text(reject_reason),
		"outline_width": 2.0 if active else 0.0,
	}


func settings_applied(snapshot: Dictionary = {}) -> void:
	if audio_feedback_controller != null and audio_feedback_controller.has_method("apply_settings_snapshot"):
		audio_feedback_controller.call("apply_settings_snapshot", snapshot)


func current_map_level() -> int:
	return int(runtime_view_state_controller.call("current_map_level", world_result))


func map_level_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_view_state_controller.call("map_level_snapshot", world_result))


func change_observed_level(direction: int) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(runtime_view_state_controller.call("change_observed_level", direction, world_result))
	if bool(result.get("success", false)):
		if runtime_input_controller != null and runtime_input_controller.has_method("focus_current_actor"):
			runtime_input_controller.focus_current_actor()
		refresh_hud(current_interaction_prompt())
	return result


func cycle_focused_actor() -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(runtime_view_state_controller.call("cycle_focused_actor", world_result, simulation, observe_mode_enabled, panel_controller != null and panel_controller.gameplay_input_blocked()))
	if bool(result.get("success", false)):
		_clear_focus_switch_ui_state()
		if runtime_input_controller != null and runtime_input_controller.has_method("focus_current_actor"):
			runtime_input_controller.focus_current_actor()
		refresh_hud(current_interaction_prompt())
	return result


func focus_actor(actor_id: int) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(runtime_view_state_controller.call("focus_actor", actor_id, world_result, simulation, observe_mode_enabled, panel_controller != null and panel_controller.gameplay_input_blocked()))
	if bool(result.get("success", false)):
		_clear_focus_switch_ui_state()
		if runtime_input_controller != null and runtime_input_controller.has_method("focus_current_actor"):
			runtime_input_controller.focus_current_actor()
		refresh_hud(current_interaction_prompt())
	return result


func focused_actor_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_view_state_controller.call("focused_actor_snapshot", world_result, observe_mode_enabled))


func focused_actor_grid_position() -> Dictionary:
	return _dictionary_or_empty(runtime_view_state_controller.call("focused_actor_grid_position", world_result, observe_mode_enabled))


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
	if panel_controller != null and panel_controller.has_method("close_blocking_modal"):
		var modal_result: Dictionary = panel_controller.call("close_blocking_modal")
		if bool(modal_result.get("success", false)):
			return {"success": true, "closed": str(modal_result.get("closed", "modal")), "result": modal_result}
	if _world_action_presenter_blocks_input():
		var pending_before: Dictionary = _runtime_pending_state_snapshot()
		var result: Dictionary = finish_world_action_presentations()
		return {
			"success": true,
			"closed": "world_action_presenter",
			"result": result,
			"pending_before": pending_before,
			"pending_after": _runtime_pending_state_snapshot(),
		}
	if not active_skill_targeting.is_empty():
		return cancel_active_skill_targeting(reason)
	if runtime_input_controller != null and runtime_input_controller.has_method("has_selection_state") and bool(runtime_input_controller.has_selection_state()):
		var selection_result: Dictionary = runtime_input_controller.clear_selection_state(reason)
		return {"success": true, "closed": "selection", "result": selection_result}
	if _close_hud_interaction_menu():
		return {"success": true, "closed": "interaction_menu"}
	var context_menu_close_result: Dictionary = close_active_context_menu()
	if bool(context_menu_close_result.get("success", false)):
		return context_menu_close_result
	if runtime_input_controller != null:
		runtime_input_controller.clear_selection_state(reason)
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
		_play_ui_audio_feedback("settings_panel_closed", {
			"panel_id": "settings",
			"action": "close_settings_panel",
		})
		refresh_all_panels(current_interaction_prompt())
		return {"success": true, "closed": "settings"}
	var pending_result: Dictionary = cancel_pending(reason, false)
	if bool(pending_result.get("had_pending", false)):
		return {"success": true, "closed": "pending", "result": pending_result}
	if panel_controller != null:
		panel_controller.open_settings_panel()
		_play_ui_audio_feedback("settings_panel_opened", {
			"panel_id": "settings",
			"action": "open_settings_panel",
		})
		refresh_all_panels(current_interaction_prompt())
		return {"success": true, "closed": "", "opened": "settings"}
	return {"success": false, "reason": "panel_controller_missing"}


func close_active_context_menu() -> Dictionary:
	var snapshot: Dictionary = context_menu_snapshot()
	if not bool(snapshot.get("active", false)):
		return {"success": false, "reason": "context_menu_inactive"}
	var top_menu: Dictionary = _dictionary_or_empty(snapshot.get("top", {}))
	var owner_panel := str(top_menu.get("owner_panel", ""))
	var menu_id := str(top_menu.get("id", "context_menu"))
	var panel := _context_menu_owner_panel(owner_panel)
	if panel == null or not panel.has_method("close_context_menu"):
		return {
			"success": false,
			"reason": "context_menu_owner_missing",
			"closed": menu_id,
			"owner_panel": owner_panel,
		}
	panel.call("close_context_menu")
	return {
		"success": true,
		"closed": menu_id,
		"owner_panel": owner_panel,
	}


func _context_menu_owner_panel(owner_panel: String) -> Node:
	match owner_panel:
		"inventory":
			return inventory_panel
		"container":
			return container_panel
		"trade":
			return trade_panel
		"skills":
			return skills_panel
		"character":
			return character_panel
	return null


func _runtime_pending_state_snapshot() -> Dictionary:
	if simulation == null:
		return {"pending_movement": {}, "pending_interaction": {}, "pending_crafting": {}}
	var snapshot: Dictionary = simulation.snapshot()
	return {
		"pending_movement": _dictionary_or_empty(snapshot.get("pending_movement", {})).duplicate(true),
		"pending_interaction": _dictionary_or_empty(snapshot.get("pending_interaction", {})).duplicate(true),
		"pending_crafting": _dictionary_or_empty(snapshot.get("pending_crafting", {})).duplicate(true),
	}


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


func clear_interaction_selection(reason: String = "cleared") -> Dictionary:
	if interaction_controller == null:
		return {"success": false, "reason": "interaction_controller_missing"}
	var result: Dictionary = interaction_controller.clear_selection(reason)
	refresh_hud(_dictionary_or_empty(result.get("prompt", {})))
	return result


func execute_primary_interaction() -> Dictionary:
	if interaction_controller == null:
		return {"success": false, "reason": "interaction_controller_missing"}
	var blocked: Dictionary = _player_command_rejection("interact")
	if not blocked.is_empty():
		return blocked
	var executed_target: Dictionary = interaction_controller.selected_target.duplicate(true)
	var result: Dictionary = interaction_controller.execute_primary_interaction()
	_apply_interaction_execution_result(result, executed_target)
	return result


func execute_interaction_option(option_id: String) -> Dictionary:
	if interaction_controller == null:
		return {"success": false, "reason": "interaction_controller_missing"}
	var blocked: Dictionary = _player_command_rejection("interact")
	if not blocked.is_empty():
		return blocked
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
	var blocked: Dictionary = _player_command_rejection("move")
	if not blocked.is_empty():
		return blocked
	var result: Dictionary = interaction_controller.execute_move_to_grid(grid)
	if bool(result.get("success", false)) and _world_action_command_kind(result) == "move":
		var final_world_result: Dictionary = interaction_controller.world_result.duplicate(true)
		_setup_world_container()
		_present_world_action(result)
		if _world_action_presenter_blocks_input():
			_queue_deferred_world_refresh(final_world_result, _dictionary_or_empty(result.get("prompt", {})), result, "execute_move_to_grid", false)
			refresh_hud(_dictionary_or_empty(result.get("prompt", {})))
			return result
	world_result = interaction_controller.world_result
	_rebuild_world_after_runtime_change(_dictionary_or_empty(result.get("prompt", {})), result)
	return result


func cancel_pending(reason: String = "cancelled", auto_end_turn: bool = false) -> Dictionary:
	if interaction_controller == null:
		return {"success": false, "reason": "interaction_controller_missing"}
	var result: Dictionary = interaction_controller.cancel_pending(reason, auto_end_turn)
	if bool(result.get("had_pending", false)):
		_rebuild_world_after_runtime_change(current_interaction_prompt(), result)
	else:
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
		_continue_crafting_queue_after_wait(result)
		if _rebuild_runtime_world_result("press_space_action"):
			_apply_world_root_snapshot(true)
			_refresh_world_runtime_bindings()
	refresh_all_panels(current_interaction_prompt())
	return result


func _process_auto_tick(delta: float) -> void:
	if bool(runtime_control_state_controller.call("should_submit_auto_tick", delta)):
		_submit_auto_tick_wait()


func _observe_playback_enabled() -> bool:
	return bool(runtime_control_state_controller.call("observe_playback_enabled"))


func _observe_speed_index(speed_id: String) -> int:
	return int(runtime_control_state_controller.call("observe_speed_index", speed_id))


func _observe_speed_multiplier() -> float:
	return float(runtime_control_state_controller.call("observe_speed_multiplier"))


func _auto_tick_interval_sec() -> float:
	return float(runtime_control_state_controller.call("auto_tick_interval_sec"))


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
		_continue_crafting_queue_after_wait(result)
		if _rebuild_runtime_world_result("auto_tick_wait"):
			_apply_world_root_snapshot(true)
			_refresh_world_runtime_bindings()
		refresh_all_panels(current_interaction_prompt())
	return result


func press_enter_action() -> Dictionary:
	if has_active_dialogue():
		return advance_dialogue_without_choice()
	return {"success": false, "reason": "no_enter_action"}


func take_active_container_item(item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
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
		"stack_index": stack_index,
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


func store_active_container_item(item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
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
		"stack_index": stack_index,
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


func transfer_active_container_item(source: String, item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	match source:
		"container":
			if str(item_id) == "money":
				return take_active_container_money(count)
			return take_active_container_item(item_id, count, stack_index)
		"player":
			return store_active_container_item(item_id, count, stack_index)
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
		"crafting_context": _crafting_context(),
	})
	_record_inventory_feedback(result, "deconstruct", item_id, count)
	refresh_inventory_panel()
	refresh_crafting_panel()
	return result


func split_player_inventory_stack(item_id: String, count: int = 1, source_stack_index: int = 0) -> Dictionary:
	if simulation == null:
		var missing_result := {"success": false, "reason": "simulation_missing", "item_id": item_id, "count": count}
		_record_inventory_feedback(missing_result, "split_stack", item_id, count)
		refresh_inventory_panel()
		return missing_result
	var command := {
		"action": "split_stack",
		"item_id": item_id,
		"count": count,
	}
	if source_stack_index > 0:
		command["source_stack_index"] = source_stack_index
	var result: Dictionary = _submit_inventory_action(command)
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


func buy_active_trade_item(item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
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
		"stack_index": stack_index,
	})
	_record_trade_feedback(result, "buy_shop", shop_id, item_id, count)
	refresh_inventory_panel()
	refresh_trade_panel()
	return result


func sell_active_trade_item(item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
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
		"stack_index": stack_index,
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


func transfer_active_trade_item(source: String, item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	match source:
		"shop":
			return buy_active_trade_item(item_id, count, stack_index)
		"player":
			return sell_active_trade_item(item_id, count, stack_index)
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
	var blocked: Dictionary = _player_command_rejection("learn_skill")
	if not blocked.is_empty():
		return blocked
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
	var blocked: Dictionary = _player_command_rejection("bind_hotbar")
	if not blocked.is_empty():
		return blocked
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
	var blocked: Dictionary = _player_command_rejection("bind_hotbar")
	if not blocked.is_empty():
		return blocked
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
	if _world_action_presenter_blocks_input():
		return _action_presenter_command_rejected("set_hotbar_group")
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
	if _world_action_presenter_blocks_input():
		return _action_presenter_command_rejected("cycle_hotbar_group")
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
	var blocked: Dictionary = _player_command_rejection("hotbar")
	if not blocked.is_empty():
		return blocked
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
	var blocked: Dictionary = _player_command_rejection("use_skill")
	if not blocked.is_empty():
		return blocked
	var result: Dictionary = _dictionary_or_empty(skill_targeting_controller.call(
		"begin_targeting",
		slot_id,
		skill_id,
		simulation.snapshot(),
		registry.get_library("skills")
	))
	if not bool(result.get("success", false)):
		return result
	if bool(result.get("immediate", false)):
		return simulation.submit_player_command({
			"kind": "use_skill",
			"actor_id": 1,
			"slot_id": slot_id,
			"skill_id": str(result.get("skill_id", skill_id)),
			"skill_library": registry.get_library("skills"),
			"target": _dictionary_or_empty(result.get("target", {"target_type": "self"})),
		})
	refresh_hud(current_interaction_prompt())
	return result


func preview_active_skill_target(target: Dictionary) -> Dictionary:
	if active_skill_targeting.is_empty() or simulation == null:
		return {"success": false, "reason": "skill_targeting_inactive"}
	var skill_id := str(active_skill_targeting.get("skill_id", ""))
	var preview: Dictionary = simulation.preview_skill_target(1, skill_id, registry.get_library("skills"), target, _dictionary_or_empty(world_result.get("map", {})))
	skill_targeting_controller.call("record_preview", preview)
	if runtime_input_controller != null and runtime_input_controller.has_method("update_skill_target_preview_markers"):
		runtime_input_controller.update_skill_target_preview_markers(active_skill_target_preview)
	refresh_hud(current_interaction_prompt())
	return preview


func confirm_active_skill_target(target: Dictionary = {}) -> Dictionary:
	if active_skill_targeting.is_empty() or simulation == null:
		return {"success": false, "reason": "skill_targeting_inactive"}
	var blocked: Dictionary = _player_command_rejection("use_skill")
	if not blocked.is_empty():
		return blocked
	var confirm: Dictionary = _dictionary_or_empty(skill_targeting_controller.call("confirm_target", target))
	if not bool(confirm.get("success", false)):
		return confirm
	var result: Dictionary = simulation.submit_player_command({
		"kind": "use_skill",
		"actor_id": 1,
		"slot_id": str(confirm.get("slot_id", "")),
		"skill_id": str(confirm.get("skill_id", "")),
		"skill_library": registry.get_library("skills"),
		"target": _dictionary_or_empty(confirm.get("target", {})),
		"topology": _dictionary_or_empty(world_result.get("map", {})),
	})
	skill_targeting_controller.call("complete_confirm", bool(result.get("success", false)))
	if bool(result.get("success", false)):
		if runtime_input_controller != null and runtime_input_controller.has_method("update_skill_target_preview_markers"):
			runtime_input_controller.update_skill_target_preview_markers({})
	refresh_hud(current_interaction_prompt())
	refresh_character_panel()
	refresh_skills_panel()
	return result


func cancel_active_skill_targeting(reason: String = "cancelled") -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(skill_targeting_controller.call("cancel", reason))
	if not bool(result.get("success", false)):
		return result
	if runtime_input_controller != null and runtime_input_controller.has_method("update_skill_target_preview_markers"):
		runtime_input_controller.update_skill_target_preview_markers({})
	refresh_hud(current_interaction_prompt())
	return result


func has_active_skill_targeting() -> bool:
	return bool(skill_targeting_controller.call("has_active_targeting"))


func active_skill_targeting_snapshot() -> Dictionary:
	return _dictionary_or_empty(skill_targeting_controller.call("snapshot"))


func craft_player_recipe(recipe_id: String, count: int = 1) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var blocked: Dictionary = _player_command_rejection("craft")
	if not blocked.is_empty():
		return blocked
	var result: Dictionary = simulation.submit_player_command({
		"kind": "craft",
		"actor_id": 1,
		"recipe_id": recipe_id,
		"count": max(1, count),
		"recipe_library": registry.get_library("recipes"),
		"crafting_context": _crafting_context(),
		"topology": _dictionary_or_empty(world_result.get("map", {})),
	})
	crafting_feedback_controller.call("clear_pending_result")
	refresh_inventory_panel()
	refresh_crafting_panel()
	refresh_skills_panel()
	return result


func confirm_crafting_queue(entries: Array) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var blocked: Dictionary = _player_command_rejection("crafting_queue")
	if not blocked.is_empty():
		return blocked
	simulation.crafting_queue = _normalized_crafting_queue(entries)
	var queue_result: Dictionary = _advance_crafting_queue("confirm")
	_set_latest_crafting_queue_result(queue_result, "confirm")
	crafting_feedback_controller.call("clear_pending_result")
	refresh_inventory_panel()
	refresh_crafting_panel()
	refresh_skills_panel()
	return queue_result


func _advance_crafting_queue(reason: String) -> Dictionary:
	var results: Array[Dictionary] = []
	var completed_count: int = 0
	var failed: Array[Dictionary] = []
	var started_pending := false
	var guard := 0
	var advance_limit: int = max(CRAFTING_QUEUE_ADVANCE_LIMIT, simulation.crafting_queue.size() + 1)
	while guard < advance_limit:
		guard += 1
		if not _dictionary_or_empty(simulation.pending_crafting).is_empty():
			break
		if simulation.crafting_queue.is_empty():
			break
		var entry_data: Dictionary = _dictionary_or_empty(simulation.crafting_queue[0])
		var recipe_id := str(entry_data.get("recipe_id", "")).strip_edges()
		var count: int = max(1, int(entry_data.get("count", 1)))
		if recipe_id.is_empty():
			var missing_recipe_id_result := {"success": false, "reason": "recipe_id_missing", "entry": entry_data.duplicate(true)}
			results.append(missing_recipe_id_result)
			failed.append(missing_recipe_id_result)
			break
		var result: Dictionary = _submit_crafting_queue_entry(recipe_id, count)
		result["queued_recipe_id"] = recipe_id
		result["queued_count"] = count
		results.append(result)
		var completed_entry_count: int = _completed_crafting_count_from_queue_result(result)
		completed_count += completed_entry_count
		if not _dictionary_or_empty(simulation.pending_crafting).is_empty():
			simulation.crafting_queue.remove_at(0)
			started_pending = true
			break
		if bool(result.get("success", false)):
			simulation.crafting_queue.remove_at(0)
			continue
		if bool(result.get("partial_success", false)) and completed_entry_count > 0:
			var remaining_count: int = max(0, count - completed_entry_count)
			if remaining_count > 0:
				var remaining_entry: Dictionary = entry_data.duplicate(true)
				remaining_entry["count"] = remaining_count
				simulation.crafting_queue[0] = remaining_entry
			else:
				simulation.crafting_queue.remove_at(0)
		failed.append(result.duplicate(true))
		break
	var limit_reached: bool = guard >= advance_limit and not simulation.crafting_queue.is_empty() and _dictionary_or_empty(simulation.pending_crafting).is_empty()
	if limit_reached:
		var limit_result := {
			"success": false,
			"reason": "crafting_queue_advance_limit_reached",
			"limit": advance_limit,
			"remaining_queue": simulation.crafting_queue.duplicate(true),
		}
		results.append(limit_result)
		failed.append(limit_result)
	return {
		"success": failed.is_empty(),
		"partial_success": completed_count > 0 and not failed.is_empty(),
		"completed_count": completed_count,
		"failed_count": failed.size(),
		"results": results,
		"failed": failed,
		"pending": not _dictionary_or_empty(simulation.pending_crafting).is_empty(),
		"started_pending": started_pending,
		"remaining_queue": simulation.crafting_queue.duplicate(true),
		"remaining_queue_count": simulation.crafting_queue.size(),
		"queue_empty": simulation.crafting_queue.is_empty(),
		"reason": reason,
	}


func _submit_crafting_queue_entry(recipe_id: String, count: int) -> Dictionary:
	return simulation.submit_player_command({
		"kind": "craft",
		"actor_id": 1,
		"recipe_id": recipe_id,
		"count": max(1, count),
		"recipe_library": registry.get_library("recipes"),
		"crafting_context": _crafting_context(),
		"topology": _dictionary_or_empty(world_result.get("map", {})),
		"crafting_queue_active": true,
	})


func _continue_crafting_queue_after_wait(result: Dictionary) -> void:
	if simulation == null or simulation.crafting_queue.is_empty():
		return
	if not _dictionary_or_empty(simulation.pending_crafting).is_empty():
		return
	if not _wait_result_resumed_active_crafting_queue(result):
		return
	result["crafting_queue_result"] = _advance_crafting_queue("pending_completed")
	_set_latest_crafting_queue_result(_dictionary_or_empty(result.get("crafting_queue_result", {})), "pending_completed")


func _wait_result_resumed_active_crafting_queue(result: Dictionary) -> bool:
	var pending_result: Dictionary = _dictionary_or_empty(result.get("pending_result", {}))
	if pending_result.is_empty():
		return false
	var resumed: Dictionary = _dictionary_or_empty(pending_result.get("resumed_pending_crafting", {}))
	if resumed.is_empty():
		return false
	var command: Dictionary = _dictionary_or_empty(resumed.get("command", {}))
	return bool(command.get("crafting_queue_active", false))


func _completed_crafting_count_from_queue_result(result: Dictionary) -> int:
	if not _dictionary_or_empty(simulation.pending_crafting).is_empty():
		return 0
	if bool(result.get("partial_success", false)):
		return max(0, int(result.get("completed_count", 0)))
	if not bool(result.get("success", false)):
		return 0
	if result.has("completed_count"):
		return max(0, int(result.get("completed_count", 0)))
	return max(1, int(result.get("count", result.get("queued_count", 1))))


func update_crafting_queue(entries: Array) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	simulation.crafting_queue = _normalized_crafting_queue(entries)
	if simulation.crafting_queue.is_empty():
		crafting_feedback_controller.call("record_queue_cleared")
	return {
		"success": true,
		"entry_count": simulation.crafting_queue.size(),
		"crafting_queue": simulation.crafting_queue.duplicate(true),
	}


func crafting_queue_snapshot() -> Dictionary:
	if simulation == null:
		return {"entries": [], "entry_count": 0, "total_count": 0}
	return _dictionary_or_empty(crafting_feedback_controller.call("queue_snapshot", simulation.crafting_queue))


func _normalized_crafting_queue(entries: Array) -> Array[Dictionary]:
	return _array_of_dictionaries(crafting_feedback_controller.call("normalize_queue", entries))


func _crafting_queue_total_count(entries: Array) -> int:
	return int(crafting_feedback_controller.call("queue_total_count", entries))


func cancel_pending_crafting(reason: String = "crafting_ui") -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = simulation.submit_player_command({
		"kind": "cancel_pending",
		"actor_id": 1,
		"reason": reason,
		"topology": _dictionary_or_empty(world_result.get("map", {})),
	})
	if bool(result.get("success", false)) and bool(result.get("had_pending", false)):
		crafting_feedback_controller.call("record_pending_cancelled", result, reason, simulation.crafting_queue)
	elif bool(result.get("success", false)):
		crafting_feedback_controller.call("clear_pending_result")
	refresh_inventory_panel()
	refresh_crafting_panel()
	refresh_skills_panel()
	return result


func _set_latest_crafting_queue_result(result: Dictionary, trigger: String) -> void:
	crafting_feedback_controller.call(
		"record_queue_result",
		result,
		trigger,
		_dictionary_or_empty(simulation.pending_crafting) if simulation != null else {}
	)


func _crafting_context() -> Dictionary:
	return {
		"crafting_stations": _array_or_empty(_dictionary_or_empty(world_result.get("map", {})).get("crafting_stations", [])).duplicate(true),
		"world_flags": _dictionary_or_empty(simulation.world_flags if simulation != null else {}).duplicate(true),
		"nearby_tool_containers": _nearby_tool_containers(),
		"latest_crafting_queue_result": latest_crafting_queue_result.duplicate(true),
		"latest_pending_crafting_result": latest_pending_crafting_result.duplicate(true),
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


func enter_overworld_location_from_panel(location_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing", "location_id": location_id}
	var result: Dictionary = simulation.enter_location(1, location_id, registry.get_library("overworld"))
	if bool(result.get("success", false)):
		_rebuild_world_after_runtime_change({}, result)
	else:
		refresh_hud(current_interaction_prompt())
		refresh_map_panel()
	return result


func _rebuild_world_after_runtime_change(selected_prompt: Dictionary = {}, command_result: Dictionary = {}) -> void:
	if not _rebuild_runtime_world_result("runtime_change"):
		return
	_apply_world_root_snapshot(true)
	_present_world_action(command_result)
	_refresh_world_runtime_bindings()
	refresh_all_panels(selected_prompt)


func _rebuild_runtime_world_result(source: String) -> bool:
	var refresh: Dictionary = _dictionary_or_empty(runtime_refresh_controller.call("rebuild_world_result", simulation, interaction_controller, source))
	return _accept_runtime_refresh_result(refresh, "world rebuild failed")


func _apply_existing_runtime_world_result(next_world_result: Dictionary, source: String, fallback_error: String = "world refresh failed") -> bool:
	var refresh: Dictionary = _dictionary_or_empty(runtime_refresh_controller.call("apply_existing_world_result", simulation, interaction_controller, next_world_result, source))
	return _accept_runtime_refresh_result(refresh, fallback_error)


func _accept_runtime_refresh_result(refresh: Dictionary, fallback_error: String) -> bool:
	world_result = _dictionary_or_empty(refresh.get("world_result", {}))
	if not bool(refresh.get("ok", false)):
		push_error(str(refresh.get("error", refresh.get("reason", fallback_error))))
		return false
	_sync_observed_level_to_map()
	return true


func _setup_world_container() -> void:
	if world_root == null or not is_instance_valid(world_root):
		world_root = WorldRoot.new()
		world_root.name = "WorldRoot"
		add_child(world_root)
	if world_root.has_method("ensure_world_container"):
		world_container = world_root.call("ensure_world_container")


func _setup_runtime_input_controller() -> void:
	if runtime_input_controller == null:
		runtime_input_controller = GameRuntimeInputController.new(self)
	runtime_input_controller.attach_world(world_container, world_result)


func _refresh_world_runtime_bindings() -> void:
	_setup_runtime_input_controller()
	_configure_runtime_audio_layers()
	_setup_panels()


func _apply_world_root_snapshot(render_world: bool = true) -> Dictionary:
	_setup_world_container()
	var counts: Dictionary = {}
	if render_world:
		counts = _render_world()
	elif runtime_input_controller != null:
		runtime_input_controller.world_result = world_result
	_refresh_fog_overlay()
	_refresh_debug_overlay()
	return counts


func _render_world() -> Dictionary:
	if world_root == null:
		return {}
	var runtime_snapshot: Dictionary = simulation.snapshot() if simulation != null else {}
	var counts: Dictionary = _dictionary_or_empty(world_root.call("apply_world_snapshot", world_result, runtime_snapshot))
	runtime_performance_tracker.call("record_world_render", counts, world_root, Callable(self, "_render_count_summary"))
	if world_root.has_method("ensure_world_container"):
		world_container = world_root.call("ensure_world_container")
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
	if simulation == null or world_result.is_empty() or world_root == null:
		return
	world_root.call("refresh_fog", world_result, simulation.snapshot())
	fog_overlay = world_root.get("fog_overlay")


func _refresh_debug_overlay() -> void:
	if world_root == null:
		return
	var runtime_snapshot: Dictionary = simulation.snapshot() if simulation != null else {}
	world_root.call("refresh_debug_overlay", current_debug_overlay_mode(), world_result, runtime_snapshot)
	if world_root.has_method("ensure_world_container"):
		world_container = world_root.call("ensure_world_container")


func _setup_audio_feedback_controller() -> void:
	if audio_feedback_controller != null:
		return
	audio_feedback_controller = AudioFeedbackController.new()
	audio_feedback_controller.name = "AudioFeedbackController"
	add_child(audio_feedback_controller)


func _configure_runtime_audio_layers() -> void:
	if audio_feedback_controller == null or simulation == null:
		return
	if audio_feedback_controller.has_method("configure_runtime_audio"):
		audio_feedback_controller.call("configure_runtime_audio", simulation.snapshot(), world_result)


func _process_audio_feedback() -> void:
	if audio_feedback_controller == null or simulation == null:
		return
	if audio_feedback_controller.has_method("process_runtime_snapshot"):
		audio_feedback_controller.call("process_runtime_snapshot", simulation.snapshot())


func _play_ui_audio_feedback(event_kind: String, payload: Dictionary = {}) -> Dictionary:
	if audio_feedback_controller == null or not audio_feedback_controller.has_method("play_ui_feedback"):
		return {"enabled": false, "reason": "audio_feedback_missing"}
	return _dictionary_or_empty(audio_feedback_controller.call("play_ui_feedback", event_kind, payload))


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
	_sync_debug_console_schema()
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


func _sync_debug_console_schema() -> void:
	if hud == null:
		return
	if hud.has_method("set_debug_console_schema"):
		hud.set_debug_console_schema(
			debug_runtime_controller.command_schema(),
			debug_runtime_controller.command_suggestions(),
			debug_runtime_controller.permission_snapshot(self)
		)


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
	var stage_panel_to_open := _interaction_result_stage_panel(result)
	world_result = interaction_controller.world_result
	_sync_observed_level_to_map()
	# 地图切换、对象消费、移动和击杀后需要重绘世界，保证 scene tree 与运行时快照一致。
	_apply_world_root_snapshot(true)
	_present_world_action(result)
	_refresh_world_runtime_bindings()
	var deferred_ui := false
	if not stage_panel_to_open.is_empty():
		deferred_ui = _queue_or_open_stage_panel_after_world_action(stage_panel_to_open, result)
	elif _queue_or_refresh_all_panels_after_world_action(result):
		deferred_ui = true
	if deferred_ui:
		refresh_hud(_dictionary_or_empty(result.get("prompt", {})))
	else:
		refresh_all_panels(_dictionary_or_empty(result.get("prompt", {})))


func _interaction_result_stage_panel(result: Dictionary) -> String:
	if not bool(result.get("success", false)):
		return ""
	var panel_id := str(result.get("open_panel", "")).strip_edges()
	if not panel_id.is_empty():
		return panel_id
	var prompt: Dictionary = _dictionary_or_empty(result.get("prompt", {}))
	var option_id := str(prompt.get("primary_option_id", ""))
	for option in _array_or_empty(prompt.get("options", [])):
		var option_data: Dictionary = _dictionary_or_empty(option)
		if option_id.is_empty() or str(option_data.get("id", "")) == option_id:
			if str(option_data.get("kind", "")) == "open_crafting":
				return "crafting"
	return ""


func _open_stage_panel_from_interaction(panel_id: String) -> void:
	if panel_controller == null or not ["crafting"].has(panel_id):
		return
	if panel_controller.has_method("open_stage_panel"):
		panel_controller.call("open_stage_panel", panel_id)
		return
	if panel_controller.has_method("toggle_stage_panel"):
		var menu_state: Dictionary = _dictionary_or_empty(panel_controller.call("menu_state_snapshot"))
		var already_open := false
		for stage in _array_or_empty(menu_state.get("stage_panels", [])):
			var stage_data: Dictionary = _dictionary_or_empty(stage)
			if str(stage_data.get("id", "")) == panel_id and bool(stage_data.get("active", false)):
				already_open = true
				break
		if not already_open:
			panel_controller.call("toggle_stage_panel", panel_id)


func _queue_or_open_stage_panel_after_world_action(panel_id: String, result: Dictionary) -> bool:
	if panel_id.is_empty():
		return false
	if _world_action_presenter_blocks_input():
		world_action_flow_controller.call("queue_open_stage_panel", panel_id, result, _dictionary_or_empty(result.get("prompt", {})))
		return true
	_open_stage_panel_from_interaction(panel_id)
	return false


func _queue_or_refresh_all_panels_after_world_action(result: Dictionary) -> bool:
	if not _world_action_presenter_blocks_input():
		return false
	world_action_flow_controller.call("queue_refresh_all_panels", result, _dictionary_or_empty(result.get("prompt", {})))
	return true


func _process_world_action_queue_completion() -> void:
	if not bool(world_action_flow_controller.call("should_process_completion")):
		return
	if _world_action_presenter_blocks_input():
		return
	world_action_flow_controller.call("mark_presenter_finished_if_needed")
	_apply_pending_world_action_final_refresh("presenter_finished")
	_apply_pending_world_action_ui("presenter_finished")


func _queue_deferred_world_refresh(final_world_result: Dictionary, selected_prompt: Dictionary, command_result: Dictionary, source: String, render_world: bool = true) -> void:
	world_action_flow_controller.call("queue_deferred_world_refresh", final_world_result, selected_prompt, command_result, source, render_world)


func _apply_pending_world_action_final_refresh(trigger: String) -> bool:
	var pending_refresh: Dictionary = _dictionary_or_empty(world_action_flow_controller.call("take_pending_final_refresh"))
	if pending_refresh.is_empty():
		return false
	var final_world_result: Dictionary = _dictionary_or_empty(pending_refresh.get("world_result", {}))
	if final_world_result.is_empty() or not bool(final_world_result.get("ok", false)):
		var fallback_refresh: Dictionary = _dictionary_or_empty(runtime_refresh_controller.call("build_world_result_from_snapshot", simulation.snapshot(), "pending_final_refresh_fallback"))
		final_world_result = _dictionary_or_empty(fallback_refresh.get("world_result", {}))
	if not _apply_world_result_without_present(final_world_result, bool(pending_refresh.get("render_world", true))):
		return false
	world_action_flow_controller.call("mark_final_refresh_applied", pending_refresh, trigger)
	if bool(pending_refresh.get("refresh_all_panels", false)):
		refresh_all_panels(_dictionary_or_empty(pending_refresh.get("prompt", {})))
	return true


func _deferred_world_refresh_public_snapshot(source: Dictionary) -> Dictionary:
	return _dictionary_or_empty(world_action_flow_controller.call("deferred_world_refresh_public_snapshot", source))


func _apply_world_result_without_present(next_world_result: Dictionary, render_world: bool = true) -> bool:
	if not _apply_existing_runtime_world_result(next_world_result, "world_result_without_present", "world refresh failed"):
		return false
	_apply_world_root_snapshot(render_world)
	_refresh_world_runtime_bindings()
	return true


func _apply_pending_world_action_ui(trigger: String) -> bool:
	var pending_ui: Dictionary = _dictionary_or_empty(world_action_flow_controller.call("take_pending_ui"))
	if pending_ui.is_empty():
		return false
	if str(pending_ui.get("kind", "")) == "open_stage_panel":
		_open_stage_panel_from_interaction(str(pending_ui.get("panel_id", "")))
	if bool(pending_ui.get("refresh_all_panels", false)) or str(pending_ui.get("kind", "")) == "refresh_all_panels":
		refresh_all_panels(_dictionary_or_empty(pending_ui.get("prompt", {})))
	world_action_flow_controller.call("mark_deferred_ui_applied", pending_ui, trigger)
	return true


func _present_world_action(command_result: Dictionary) -> void:
	world_action_flow_controller.call("present_result", self, world_container, command_result, world_result)


func _record_world_action_queue_presented(command_result: Dictionary, presenter_result: Dictionary) -> void:
	world_action_flow_controller.call("record_presented", command_result, presenter_result)


func _record_world_action_queue_finished(finish_result: Dictionary) -> void:
	world_action_flow_controller.call("record_finished", finish_result)


func _world_action_command_kind(command_result: Dictionary) -> String:
	return str(world_action_flow_controller.call("command_kind", command_result))


func _world_action_event_count(command_result: Dictionary) -> int:
	return int(world_action_flow_controller.call("event_count", command_result))


func _world_action_events_from_result(command_result: Dictionary) -> Array:
	return _array_or_empty(world_action_flow_controller.call("events_from_result", command_result))


func _submit_inventory_action(action: Dictionary) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var blocked: Dictionary = _player_command_rejection(str(action.get("action", "inventory_action")))
	if not blocked.is_empty():
		return blocked
	var command: Dictionary = action.duplicate(true)
	command["kind"] = "inventory_action"
	command["actor_id"] = 1
	command["item_library"] = registry.get_library("items")
	command["effect_library"] = registry.get_library("json")
	command["topology"] = _dictionary_or_empty(world_result.get("map", {}))
	return simulation.submit_player_command(command)


func _player_command_rejection(action: String) -> Dictionary:
	if observe_mode_enabled:
		return _observe_command_rejected(action)
	var modal_name := _panel_modal_blocker_name()
	if not modal_name.is_empty():
		return _ui_modal_command_rejected(action, modal_name)
	if _world_action_presenter_blocks_input():
		return _action_presenter_command_rejected(action)
	return {}


func _observe_command_rejected(action: String) -> Dictionary:
	refresh_hud(current_interaction_prompt())
	return {
		"success": false,
		"reason": "observe_mode_blocks_player_commands",
		"action": action,
		"observe_mode": observe_mode_enabled,
	}


func _action_presenter_command_rejected(action: String) -> Dictionary:
	var blocker: Dictionary = gameplay_input_blocker_snapshot()
	refresh_hud(current_interaction_prompt())
	return {
		"success": false,
		"reason": "world_action_presenter_blocks_player_commands",
		"action": action,
		"blocker": blocker,
		"action_kind": str(blocker.get("action_kind", "")),
	}


func _ui_modal_command_rejected(action: String, modal_name: String) -> Dictionary:
	var blocker: Dictionary = gameplay_input_blocker_snapshot()
	refresh_hud(current_interaction_prompt())
	return {
		"success": false,
		"reason": "ui_modal_blocks_player_commands",
		"action": action,
		"modal_id": modal_name.trim_prefix("modal:"),
		"blocker": blocker,
	}


func _record_container_feedback(result: Dictionary, action: String, container_id: String, item_id: String, count: int) -> void:
	ui_feedback_state_controller.call("record_container_feedback", result, action, container_id, item_id, count)


func _record_trade_feedback(result: Dictionary, action: String, shop_id: String, item_id: String, count: int) -> void:
	ui_feedback_state_controller.call("record_trade_feedback", result, action, shop_id, item_id, count)


func _record_inventory_feedback(result: Dictionary, action: String, item_id: String, count: int) -> void:
	ui_feedback_state_controller.call("record_inventory_feedback", result, action, item_id, count)


func _record_character_feedback(result: Dictionary, action: String, slot_id: String, item_id: String) -> void:
	ui_feedback_state_controller.call("record_character_feedback", result, action, slot_id, item_id)


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
	return _dictionary_or_empty(runtime_view_state_controller.call("focused_actor_data", world_result, observe_mode_enabled))


func _focus_actor_candidates() -> Array[Dictionary]:
	return _array_or_empty(runtime_view_state_controller.call("focus_actor_candidates", world_result, observe_mode_enabled))


func _current_focus_level() -> int:
	return current_map_level()


func _is_player_side_actor(actor_data: Dictionary) -> bool:
	return bool(runtime_view_state_controller.call("is_player_side_actor", actor_data))


func _focused_actor_busy_state(focused_actor: Dictionary) -> Dictionary:
	return _dictionary_or_empty(runtime_view_state_controller.call("focused_actor_busy_state", focused_actor, simulation))


func _clear_focus_switch_ui_state() -> void:
	if runtime_input_controller != null and runtime_input_controller.has_method("clear_selection_state"):
		runtime_input_controller.clear_selection_state("focus_switch")
	if interaction_controller != null:
		interaction_controller.clear_selection("focus_switch")
	_close_hud_interaction_menu()


func _sync_observed_level_to_map() -> void:
	runtime_view_state_controller.call("sync_observed_level_to_map", world_result)


func _normalized_map_level(level: int) -> int:
	return int(runtime_view_state_controller.call("normalized_map_level", level, world_result))


func _default_map_level() -> int:
	return int(runtime_view_state_controller.call("default_map_level", world_result))


func _available_map_levels() -> Array[int]:
	return _array_or_empty(runtime_view_state_controller.call("available_map_levels", world_result))


func _skill_requires_runtime_target(skill_id: String) -> bool:
	return bool(skill_targeting_controller.call("skill_requires_runtime_target", skill_id, registry.get_library("skills") if registry != null else {}))


func _skill_data(skill_id: String) -> Dictionary:
	return _dictionary_or_empty(skill_targeting_controller.call("skill_data", skill_id, registry.get_library("skills") if registry != null else {}))


func _skill_targeting_definition(activation: Dictionary) -> Dictionary:
	return _dictionary_or_empty(skill_targeting_controller.call("skill_targeting_definition", activation))


func _skill_target_kind(targeting: Dictionary) -> String:
	return str(skill_targeting_controller.call("skill_target_kind", targeting))


func _default_skill_target_policy(target_kind: String) -> String:
	return str(skill_targeting_controller.call("default_skill_target_policy", target_kind))


func _skill_targeting_snapshot() -> Dictionary:
	return _dictionary_or_empty(skill_targeting_controller.call("snapshot"))


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _array_of_dictionaries(value: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for entry in _array_or_empty(value):
		output.append(_dictionary_or_empty(entry).duplicate(true))
	return output
