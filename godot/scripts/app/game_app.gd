extends Node3D

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const WorldRoot = preload("res://scripts/world/world_root.gd")
const WorldRootScene = preload("res://scenes/world/world_root.tscn")
const DebugRuntimeController = preload("res://scripts/app/controllers/debug_runtime_controller.gd")
const GameInputRouter = preload("res://scripts/app/controllers/game_input_router.gd")
const GameRuntimeInputController = preload("res://scripts/app/controllers/game_runtime_input_controller.gd")
const RuntimeBootController = preload("res://scripts/app/controllers/runtime_boot_controller.gd")
const RuntimeRefreshController = preload("res://scripts/app/controllers/runtime_refresh_controller.gd")
const RuntimePerformanceTracker = preload("res://scripts/app/controllers/runtime_performance_tracker.gd")
const RuntimeControlStateController = preload("res://scripts/app/controllers/runtime_control_state_controller.gd")
const RuntimeViewStateController = preload("res://scripts/app/controllers/runtime_view_state_controller.gd")
const WorldActionFlowController = preload("res://scripts/app/controllers/world_action_flow_controller.gd")
const PlayerCommandAuthorityAudit = preload("res://scripts/app/controllers/player_command_authority_audit.gd")
const PlayerCommandBlocker = preload("res://scripts/app/controllers/player_command_blocker.gd")
const AiDebugSnapshotBuilder = preload("res://scripts/app/controllers/ai_debug_snapshot_builder.gd")
const WorldTimeSnapshotBuilder = preload("res://scripts/app/controllers/world_time_snapshot_builder.gd")
const UiFeedbackStateController = preload("res://scripts/app/controllers/ui_feedback_state_controller.gd")
const SkillTargetingController = preload("res://scripts/app/controllers/skill_targeting_controller.gd")
const CraftingFeedbackController = preload("res://scripts/app/controllers/crafting_feedback_controller.gd")
const CraftingActionController = preload("res://scripts/app/controllers/crafting_action_controller.gd")
const UiBlockerStateController = preload("res://scripts/app/controllers/ui_blocker_state_controller.gd")
const ContainerActionController = preload("res://scripts/app/controllers/container_action_controller.gd")
const InventoryActionController = preload("res://scripts/app/controllers/inventory_action_controller.gd")
const TradeActionController = preload("res://scripts/app/controllers/trade_action_controller.gd")
const CharacterActionController = preload("res://scripts/app/controllers/character_action_controller.gd")
const SkillActionController = preload("res://scripts/app/controllers/skill_action_controller.gd")
const WorldPanelActionController = preload("res://scripts/app/controllers/world_panel_action_controller.gd")
const DialogueActionController = preload("res://scripts/app/controllers/dialogue_action_controller.gd")
const WaitActionController = preload("res://scripts/app/controllers/wait_action_controller.gd")
const InteractionActionController = preload("res://scripts/app/controllers/interaction_action_controller.gd")
const PlayerInteractionController = preload("res://scripts/app/controllers/player_interaction_controller.gd")
const AudioFeedbackController = preload("res://scripts/app/audio_feedback_controller.gd")
const HudRoot = preload("res://scripts/ui/hud_root.gd")
const CRAFTING_QUEUE_ADVANCE_LIMIT := 16

var registry: ContentRegistry
var simulation: RefCounted
var world_result: Dictionary = {}
var interaction_controller: RefCounted
var runtime_input_controller: RefCounted
var panel_controller: RefCounted
var hud_root: RefCounted
var world_root: Node3D
var world_action_flow_controller: RefCounted = WorldActionFlowController.new()
var world_action_presenter: RefCounted:
	get:
		if world_action_flow_controller == null:
			return null
		return world_action_flow_controller.presenter
var audio_feedback_controller: Node
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
var ui_blocker_state_controller: RefCounted = UiBlockerStateController.new()
var container_action_controller: RefCounted = ContainerActionController.new()
var inventory_action_controller: RefCounted = InventoryActionController.new()
var trade_action_controller: RefCounted = TradeActionController.new()
var character_action_controller: RefCounted = CharacterActionController.new()
var skill_action_controller: RefCounted = SkillActionController.new()
var world_panel_action_controller: RefCounted = WorldPanelActionController.new()
var dialogue_action_controller: RefCounted = DialogueActionController.new()
var wait_action_controller: RefCounted = WaitActionController.new()
var interaction_action_controller: RefCounted = InteractionActionController.new()
var tooltip_layer: Control:
	get:
		var controller := _ui_overlay_controller()
		return controller.tooltip_layer if controller != null else null
	set(value):
		var controller := _ui_overlay_controller()
		if controller != null:
			controller.tooltip_layer = value
var tooltip_panel: PanelContainer:
	get:
		var controller := _ui_overlay_controller()
		return controller.tooltip_panel if controller != null else null
	set(value):
		var controller := _ui_overlay_controller()
		if controller != null:
			controller.tooltip_panel = value
var tooltip_label: Label:
	get:
		var controller := _ui_overlay_controller()
		return controller.tooltip_label if controller != null else null
	set(value):
		var controller := _ui_overlay_controller()
		if controller != null:
			controller.tooltip_label = value
var last_tooltip_render_snapshot: Dictionary:
	get:
		var controller := _ui_overlay_controller()
		return controller.last_tooltip_render_snapshot if controller != null else {"active": false}
	set(value):
		var controller := _ui_overlay_controller()
		if controller != null:
			controller.last_tooltip_render_snapshot = value.duplicate(true)
var drag_preview_layer: Control:
	get:
		var controller := _ui_overlay_controller()
		return controller.drag_preview_layer if controller != null else null
	set(value):
		var controller := _ui_overlay_controller()
		if controller != null:
			controller.drag_preview_layer = value
var drag_preview_panel: PanelContainer:
	get:
		var controller := _ui_overlay_controller()
		return controller.drag_preview_panel if controller != null else null
	set(value):
		var controller := _ui_overlay_controller()
		if controller != null:
			controller.drag_preview_panel = value
var drag_preview_label: Label:
	get:
		var controller := _ui_overlay_controller()
		return controller.drag_preview_label if controller != null else null
	set(value):
		var controller := _ui_overlay_controller()
		if controller != null:
			controller.drag_preview_label = value
var last_drag_preview_render_snapshot: Dictionary:
	get:
		var controller := _ui_overlay_controller()
		return controller.last_drag_preview_render_snapshot if controller != null else {"active": false}
	set(value):
		var controller := _ui_overlay_controller()
		if controller != null:
			controller.last_drag_preview_render_snapshot = value.duplicate(true)
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
var crafting_action_controller: RefCounted = CraftingActionController.new()
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
var player_command_blocker: RefCounted = PlayerCommandBlocker.new()
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
	_connect_world_action_flow_signals()
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
	game_input_router.process(runtime_input_controller, delta)
	_process_world_action_queue_completion()
	_update_tooltip_layer()
	_process_auto_tick(delta)


func _input(event: InputEvent) -> void:
	game_input_router.input(self, runtime_input_controller, event)


func _unhandled_input(event: InputEvent) -> void:
	game_input_router.unhandled_input(self, runtime_input_controller, event)


func refresh_hud(selected_prompt: Dictionary = {}) -> void:
	if hud_root == null:
		return
	_process_audio_feedback()
	runtime_performance_tracker.call("mark_hud_refresh")
	if selected_prompt.is_empty():
		selected_prompt = current_interaction_prompt()
	hud_root.refresh_hud(selected_prompt)


func refresh_dialogue_panel() -> void:
	if hud_root == null:
		return
	hud_root.refresh_panel("dialogue")


func refresh_inventory_panel() -> void:
	if hud_root == null:
		return
	hud_root.refresh_panel("inventory", _ui_feedback_payload())


func refresh_trade_panel() -> void:
	if hud_root == null:
		return
	if not _active_trade_target_available():
		close_trade_panel("target_unavailable")
		return
	hud_root.refresh_panel("trade", _ui_feedback_payload())


func refresh_container_panel() -> void:
	if hud_root == null:
		return
	_close_stale_container_session()
	hud_root.refresh_panel("container", _ui_feedback_payload())


func refresh_character_panel() -> void:
	if hud_root == null:
		return
	hud_root.refresh_panel("character", _ui_feedback_payload())


func refresh_journal_panel() -> void:
	if hud_root == null:
		return
	hud_root.refresh_panel("journal")


func refresh_map_panel() -> void:
	if hud_root == null:
		return
	hud_root.refresh_panel("map")


func refresh_skills_panel() -> void:
	if hud_root == null:
		return
	hud_root.refresh_panel("skills")


func refresh_crafting_panel() -> void:
	if hud_root == null:
		return
	hud_root.refresh_panel("crafting")


func refresh_all_panels(selected_prompt: Dictionary = {}) -> void:
	if hud_root == null:
		return
	if not _active_trade_target_available():
		close_trade_panel("target_unavailable")
	_close_stale_container_session()
	_process_audio_feedback()
	runtime_performance_tracker.call("mark_hud_refresh")
	if selected_prompt.is_empty():
		selected_prompt = current_interaction_prompt()
	hud_root.refresh_all(selected_prompt, _ui_feedback_payload())


func _close_stale_container_session() -> void:
	if simulation == null:
		return
	var close_reason := _active_container_close_reason()
	if close_reason.is_empty():
		return
	active_container_feedback = {}
	simulation.close_container(1, close_reason)


func _refresh_operation_panels(panel_ids: Array, selected_prompt: Dictionary = {}) -> void:
	if hud_root == null:
		return
	var pending_panels: Array = []
	for panel_id in panel_ids:
		if str(panel_id) == "hud":
			if not pending_panels.is_empty():
				hud_root.refresh_panels(pending_panels, _ui_feedback_payload())
				pending_panels.clear()
			refresh_hud(selected_prompt)
		else:
			pending_panels.append(str(panel_id))
	if not pending_panels.is_empty():
		hud_root.refresh_panels(pending_panels, _ui_feedback_payload())


func toggle_stage_panel(panel_id: String) -> Dictionary:
	if hud_root == null:
		return {"success": false, "reason": "panel_controller_missing"}
	if _world_action_presenter_blocks_input():
		return _action_presenter_command_rejected("toggle_stage_panel:%s" % panel_id)
	var result: Dictionary = _dictionary_or_empty(hud_root.toggle_stage_panel(panel_id))
	if bool(result.get("success", false)):
		_play_ui_audio_feedback("stage_panel_opened" if bool(result.get("open", false)) else "stage_panel_closed", {
			"panel_id": panel_id,
			"action": "toggle_stage_panel",
		})
		refresh_all_panels(current_interaction_prompt())
	return result


func close_stage_panels() -> Dictionary:
	if hud_root == null:
		return {"success": false, "reason": "panel_controller_missing"}
	var result: Dictionary = _dictionary_or_empty(hud_root.close_stage_panels())
	if bool(result.get("success", false)) and bool(result.get("closed", false)):
		_play_ui_audio_feedback("stage_panel_closed", {
			"panel_id": str(result.get("panel_id", "stage")),
			"action": "close_stage_panels",
		})
	return result


func any_stage_panel_open() -> bool:
	return hud_root != null and hud_root.any_stage_panel_open()


func is_settings_open() -> bool:
	return hud_root != null and hud_root.is_settings_open()


func gameplay_input_blocked_by_ui() -> bool:
	var hud_blocker := _hud_input_blocker_snapshot()
	var panel_blocked: bool = hud_root != null and hud_root.gameplay_input_blocked()
	return bool(ui_blocker_state_controller.call("gameplay_input_blocked", hud_blocker, panel_blocked, _world_action_presenter_blocks_input()))


func gameplay_input_blocker_name() -> String:
	var hud_blocker := _hud_input_blocker_snapshot()
	var context_menu: Dictionary = context_menu_snapshot()
	var panel_blocker_name: String = hud_root.gameplay_input_blocker_name() if hud_root != null else ""
	return str(ui_blocker_state_controller.call("blocker_name", hud_blocker, _panel_modal_blocker_snapshot(), context_menu, _world_action_presenter_blocks_input(), panel_blocker_name))


func gameplay_input_blocker_snapshot() -> Dictionary:
	var hud_blocker := _hud_input_blocker_snapshot()
	var context_menu: Dictionary = context_menu_snapshot()
	var world_blocks := _world_action_presenter_blocks_input()
	var panel_blocker: Dictionary = _panel_input_blocker_snapshot()
	var fallback_name := gameplay_input_blocker_name()
	return _dictionary_or_empty(ui_blocker_state_controller.call("blocker_snapshot", hud_blocker, _panel_modal_blocker_snapshot(), context_menu, world_action_presenter_snapshot(), world_blocks, panel_blocker, fallback_name))


func _hud_input_blocker_snapshot() -> Dictionary:
	if hud_root != null:
		return _dictionary_or_empty(hud_root.hud_input_blocker_snapshot(is_debug_console_open()))
	return {}


func _close_hud_interaction_menu() -> bool:
	var hud_blocker := _hud_input_blocker_snapshot()
	if str(hud_blocker.get("name", "")) != "interaction_menu":
		return false
	return hud_root != null and hud_root.close_hud_interaction_menu()


func _panel_modal_blocker_name() -> String:
	var snapshot := _panel_modal_blocker_snapshot()
	return str(snapshot.get("name", ""))


func _panel_modal_blocker_snapshot() -> Dictionary:
	return _dictionary_or_empty(ui_blocker_state_controller.call("panel_modal_blocker_snapshot", _panel_input_blocker_snapshot()))


func _panel_input_blocker_snapshot() -> Dictionary:
	if hud_root == null:
		return {}
	return _dictionary_or_empty(hud_root.gameplay_input_blocker_snapshot())


func _world_action_presenter_blocks_input() -> bool:
	if world_action_flow_controller == null:
		return false
	return bool(world_action_flow_controller.call("blocks_input"))


func modal_stack_snapshot() -> Dictionary:
	if hud_root != null:
		return _dictionary_or_empty(hud_root.modal_stack_snapshot())
	return {"active": false, "count": 0, "top": {}, "stack": []}


func menu_state_snapshot() -> Dictionary:
	var panel_snapshot: Dictionary = {}
	var fallback_priority: Array[String] = ["settings"]
	if hud_root != null:
		panel_snapshot = _dictionary_or_empty(hud_root.menu_state_snapshot()).duplicate(true)
	return _dictionary_or_empty(ui_blocker_state_controller.call("menu_state_snapshot", panel_snapshot, fallback_priority, modal_stack_snapshot(), context_menu_snapshot(), _close_context_snapshot()))


func _root_close_priority(panel_priority: Array = []) -> Array[String]:
	return _array_or_empty(ui_blocker_state_controller.call("root_close_priority", panel_priority, _close_context_snapshot()))


func _close_context_snapshot() -> Dictionary:
	var pending_state: Dictionary = _runtime_pending_state_snapshot()
	return {
		"hud_blocker": _hud_input_blocker_snapshot(),
		"panel_modal": _panel_modal_blocker_snapshot(),
		"context_menu": context_menu_snapshot(),
		"world_action_blocks": _world_action_presenter_blocks_input(),
		"skill_targeting_active": not active_skill_targeting.is_empty(),
		"selection_active": runtime_input_controller != null and runtime_input_controller.has_method("has_selection_state") and bool(runtime_input_controller.has_selection_state()),
		"has_pending": not _dictionary_or_empty(pending_state.get("pending_movement", {})).is_empty() or not _dictionary_or_empty(pending_state.get("pending_interaction", {})).is_empty() or not _dictionary_or_empty(pending_state.get("pending_crafting", {})).is_empty(),
	}


func ui_theme_snapshot() -> Dictionary:
	if hud_root != null:
		return _dictionary_or_empty(hud_root.ui_theme_snapshot())
	return {"applied": false, "reason": "panel_controller_missing"}


func context_menu_snapshot() -> Dictionary:
	if hud_root != null:
		return _dictionary_or_empty(hud_root.context_menu_snapshot())
	return {"active": false, "count": 0, "top": {}, "menus": []}


func _ui_overlay_controller() -> RefCounted:
	return hud_root.ui_overlay_render_controller if hud_root != null else null


func hover_tooltip_snapshot(control: Control = null) -> Dictionary:
	if hud_root != null:
		return _dictionary_or_empty(hud_root.hover_tooltip_snapshot(get_viewport(), control))
	return {
		"active": false,
		"requested_source": "hover",
		"source_name": "",
		"owner_panel": "",
		"text": "",
	}


func hotbar_hit_test_snapshot(screen_position: Vector2 = Vector2(-1.0, -1.0)) -> Dictionary:
	if hud_root != null:
		return _dictionary_or_empty(hud_root.hotbar_hit_test_snapshot(get_viewport(), screen_position))
	var position := screen_position
	if position.x < 0.0 or position.y < 0.0:
		var viewport := get_viewport()
		position = viewport.get_mouse_position() if viewport != null else Vector2.ZERO
	return {
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


func drag_state_snapshot(data: Variant = {}, hover_target: Control = null) -> Dictionary:
	var drag_data: Dictionary = _dictionary_or_empty(data)
	var target: Dictionary = _drag_hover_target_snapshot(hover_target, drag_data)
	if hud_root != null:
		return _dictionary_or_empty(hud_root.drag_state_snapshot(get_viewport(), drag_data, target))
	return {
		"active": false,
		"kind": "",
		"source": {},
		"target": target,
		"preview": {},
		"payload": {},
	}


func ui_layer_stack_snapshot(drag_data: Variant = {}, drag_hover_target: Control = null, tooltip_control: Control = null) -> Dictionary:
	var blocker: Dictionary = gameplay_input_blocker_snapshot()
	var modal_stack: Dictionary = modal_stack_snapshot()
	var context_menu: Dictionary = context_menu_snapshot()
	var drag: Dictionary = drag_state_snapshot(drag_data, drag_hover_target)
	var tooltip: Dictionary = hover_tooltip_snapshot(tooltip_control)
	return _dictionary_or_empty(ui_blocker_state_controller.call("layer_stack_snapshot", blocker, modal_stack, context_menu, drag, tooltip))


func _setup_tooltip_layer() -> void:
	if hud_root != null:
		hud_root.setup_tooltip_layer(self)


func _update_tooltip_layer() -> void:
	if hud_root == null:
		return
	var snapshot: Dictionary = hover_tooltip_snapshot()
	hud_root.update_tooltip_layer(snapshot, self)


func _hide_tooltip_layer(reason: String) -> void:
	if hud_root != null:
		hud_root.hide_tooltip_layer(reason)


func _render_tooltip_snapshot(snapshot: Dictionary) -> void:
	if hud_root != null:
		hud_root.render_tooltip_snapshot(snapshot, self)


func _setup_drag_preview_layer() -> void:
	if hud_root != null:
		hud_root.setup_drag_preview_layer(self)


func render_drag_preview_for_snapshot(drag_data: Variant = {}, hover_target: Control = null) -> Dictionary:
	var drag: Dictionary = drag_state_snapshot(drag_data, hover_target)
	if not bool(drag.get("active", false)):
		_hide_drag_preview_layer("inactive")
		return drag_preview_render_snapshot()
	_render_drag_preview_snapshot(drag)
	return drag_preview_render_snapshot()


func _hide_drag_preview_layer(reason: String) -> void:
	if hud_root != null:
		hud_root.hide_drag_preview_layer(reason)


func _render_drag_preview_snapshot(drag: Dictionary) -> void:
	if hud_root != null:
		hud_root.render_drag_preview_snapshot(drag, self)


func handle_trade_shortcut(event: InputEventKey) -> bool:
	if hud_root == null:
		return false
	return hud_root.handle_trade_shortcut(event)


func toggle_controls_hint() -> Dictionary:
	if hud_root == null:
		return {"success": false, "reason": "hud_root_missing"}
	var result: Dictionary = _dictionary_or_empty(hud_root.toggle_controls_hint())
	refresh_hud(current_interaction_prompt())
	_play_hud_shortcut_audio("ui_button_pressed", "ControlsHintShortcut", "keyboard_shortcut", "toggle_controls_hint", {
		"value": "on" if bool(result.get("visible", false)) else "off",
	})
	return result


func controls_hint_visible() -> bool:
	return hud_root != null and bool(hud_root.controls_hint_visible())


func toggle_debug_console() -> Dictionary:
	if hud_root == null:
		return {"success": false, "reason": "hud_root_missing"}
	var result: Dictionary = _dictionary_or_empty(hud_root.toggle_debug_console())
	refresh_hud(current_interaction_prompt())
	_play_hud_shortcut_audio("ui_button_pressed", "DebugConsoleShortcut", "keyboard_shortcut", "toggle_debug_console", {
		"value": "open" if bool(result.get("visible", false)) else "close",
	})
	return result


func close_debug_console() -> Dictionary:
	if hud_root == null:
		return {"success": false, "reason": "hud_root_missing"}
	var result: Dictionary = _dictionary_or_empty(hud_root.close_debug_console())
	refresh_hud(current_interaction_prompt())
	return result


func is_debug_console_open() -> bool:
	return hud_root != null and bool(hud_root.is_debug_console_open())


func debug_console_snapshot() -> Dictionary:
	var permission: Dictionary = debug_runtime_controller.permission_snapshot(self)
	if hud_root != null:
		return _dictionary_or_empty(hud_root.debug_console_snapshot(permission))
	return {
		"visible": false,
		"history": [],
		"history_count": 0,
		"suggestions": [],
		"suggestion_count": 0,
		"input_text": "",
		"permission": permission,
	}


func submit_debug_console_command(command_text: String) -> Dictionary:
	var command := command_text.strip_edges()
	var result: Dictionary = _execute_debug_console_command(command)
	if hud_root != null:
		hud_root.set_debug_console_result(command, result)
	refresh_all_panels(current_interaction_prompt())
	_play_hud_shortcut_audio("ui_button_pressed", "DebugConsoleInput", "text_submit", "submit_debug_console_command", {
		"value": command,
		"reason": str(result.get("reason", "")),
	})
	return result


func _execute_debug_console_command(command: String) -> Dictionary:
	return debug_runtime_controller.execute(self, command)


func controls_hint_snapshot() -> Dictionary:
	if hud_root != null:
		return _dictionary_or_empty(hud_root.controls_hint_snapshot())
	return {"visible": false, "line_count": 0, "lines": []}


func toggle_debug_panel() -> Dictionary:
	if hud_root == null:
		return {"success": false, "reason": "hud_root_missing"}
	var result: Dictionary = _dictionary_or_empty(hud_root.toggle_debug_panel())
	refresh_hud(current_interaction_prompt())
	_play_hud_shortcut_audio("ui_button_pressed", "DebugPanelShortcut", "keyboard_shortcut", "toggle_debug_panel", {
		"value": "open" if bool(result.get("visible", false)) else "close",
	})
	return result


func is_debug_panel_open() -> bool:
	return hud_root != null and bool(hud_root.is_debug_panel_open())


func debug_panel_snapshot() -> Dictionary:
	if hud_root != null:
		return _dictionary_or_empty(hud_root.debug_panel_snapshot())
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


func _ui_layer_priority(kind: String, layer_id: String) -> int:
	return int(ui_blocker_state_controller.call("layer_priority", kind, layer_id))


func _drag_hover_target_snapshot(control: Control, drag_data: Dictionary = {}) -> Dictionary:
	if hud_root != null:
		return _dictionary_or_empty(hud_root.drag_hover_target_snapshot(control, drag_data))
	return {
		"active": false,
		"owner_panel": "",
		"target_kind": "",
		"target_id": "",
		"source_path": "",
		"accepts": "",
		"last_accept": false,
		"reject_reason": "",
		"reject_reason_text": "",
		"hover_highlight": {},
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
	var result: Dictionary = _dictionary_or_empty(runtime_view_state_controller.call("cycle_focused_actor", world_result, simulation, observe_mode_enabled, hud_root != null and hud_root.gameplay_input_blocked()))
	if bool(result.get("success", false)):
		_clear_focus_switch_ui_state()
		if runtime_input_controller != null and runtime_input_controller.has_method("focus_current_actor"):
			runtime_input_controller.focus_current_actor()
		refresh_hud(current_interaction_prompt())
	return result


func focus_actor(actor_id: int) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(runtime_view_state_controller.call("focus_actor", actor_id, world_result, simulation, observe_mode_enabled, hud_root != null and hud_root.gameplay_input_blocked()))
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
	var operation: Dictionary = _dictionary_or_empty(dialogue_action_controller.call("close_dialogue", simulation, reason))
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	if bool(result.get("success", false)):
		close_trade_panel("dialogue_closed:%s" % reason)
		_refresh_dialogue_operation(operation)
	return result


func close_active_container(reason: String = "closed") -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(container_action_controller.call("close_container", simulation, reason))
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	if bool(result.get("success", false)):
		active_container_feedback = {}
	return _apply_container_action_operation(operation)


func close_active_ui(reason: String = "closed") -> Dictionary:
	if is_debug_console_open():
		if hud_root != null:
			hud_root.close_debug_console()
		refresh_hud(current_interaction_prompt())
		return {"success": true, "closed": "debug_console"}
	if hud_root != null:
		var modal_result: Dictionary = _dictionary_or_empty(hud_root.close_blocking_modal())
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
		hud_root.close_settings_panel()
		_play_ui_audio_feedback("settings_panel_closed", {
			"panel_id": "settings",
			"action": "close_settings_panel",
		})
		refresh_all_panels(current_interaction_prompt())
		return {"success": true, "closed": "settings"}
	var pending_result: Dictionary = cancel_pending(reason, false)
	if bool(pending_result.get("had_pending", false)):
		return {"success": true, "closed": "pending", "result": pending_result}
	if hud_root != null:
		hud_root.open_settings_panel()
		_play_ui_audio_feedback("settings_panel_opened", {
			"panel_id": "settings",
			"action": "open_settings_panel",
		})
		refresh_all_panels(current_interaction_prompt())
		return {"success": true, "closed": "", "opened": "settings"}
	return {"success": false, "reason": "panel_controller_missing"}


func close_active_context_menu() -> Dictionary:
	if hud_root == null:
		return {"success": false, "reason": "hud_root_missing"}
	return _dictionary_or_empty(hud_root.close_active_context_menu())


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
	var operation: Dictionary = _dictionary_or_empty(interaction_action_controller.call("select_target", interaction_controller, target))
	return _apply_interaction_selection_operation(operation)


func select_interaction_node(node: Node) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(interaction_action_controller.call("select_node", interaction_controller, node))
	return _apply_interaction_selection_operation(operation)


func clear_interaction_selection(reason: String = "cleared") -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(interaction_action_controller.call("clear_selection", interaction_controller, reason))
	return _apply_interaction_selection_operation(operation)


func _apply_interaction_selection_operation(operation: Dictionary) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	if bool(operation.get("refresh_hud", false)):
		refresh_hud(_dictionary_or_empty(result.get("prompt", {})))
	return result


func execute_primary_interaction() -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(interaction_action_controller.call("execute_primary", interaction_controller, Callable(self, "_player_command_rejection")))
	return _apply_interaction_action_operation(operation)


func execute_interaction_option(option_id: String) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(interaction_action_controller.call("execute_option", interaction_controller, option_id, Callable(self, "_player_command_rejection")))
	return _apply_interaction_action_operation(operation)


func _apply_interaction_action_operation(operation: Dictionary) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	if bool(operation.get("apply_result", false)):
		_apply_interaction_execution_result(result, _dictionary_or_empty(operation.get("executed_target", {})))
	return result


func select_grid_target(grid: Dictionary) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(interaction_action_controller.call("select_grid", interaction_controller, grid))
	return _apply_interaction_selection_operation(operation)


func execute_move_to_grid(grid: Dictionary) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(interaction_action_controller.call("execute_move", interaction_controller, grid, Callable(self, "_player_command_rejection")))
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	if not bool(operation.get("apply_result", false)):
		return result
	var final_world_result: Dictionary = _dictionary_or_empty(operation.get("final_world_result", {}))
	var move_plan: Dictionary = _dictionary_or_empty(world_action_flow_controller.call("movement_execution_plan", result, final_world_result))
	if bool(move_plan.get("present_before_refresh", false)):
		_setup_world_container()
		_present_world_action(result)
		move_plan = _dictionary_or_empty(world_action_flow_controller.call("movement_execution_plan", result, final_world_result))
		if bool(move_plan.get("defer_final_refresh", false)):
			_queue_deferred_world_refresh(_dictionary_or_empty(move_plan.get("final_world_result", {})), _dictionary_or_empty(result.get("prompt", {})), result, "execute_move_to_grid", false)
			refresh_hud(_dictionary_or_empty(result.get("prompt", {})))
			return result
	world_result = _dictionary_or_empty(move_plan.get("final_world_result", final_world_result))
	_rebuild_world_after_runtime_change(_dictionary_or_empty(result.get("prompt", {})), result)
	return result


func cancel_pending(reason: String = "cancelled", auto_end_turn: bool = false) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(interaction_action_controller.call("cancel_pending", interaction_controller, reason, auto_end_turn))
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	if bool(operation.get("rebuild_world", false)):
		_rebuild_world_after_runtime_change(current_interaction_prompt(), result)
	elif bool(operation.get("refresh_all_panels", false)):
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
	var dialogue_library: Dictionary = registry.get_library("dialogues") if registry != null else {}
	var operation: Dictionary = _dictionary_or_empty(dialogue_action_controller.call("choose_option", simulation, option_ref, dialogue_library))
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	_apply_dialogue_trade_result(result)
	_refresh_dialogue_operation(operation)
	return result


func choose_dialogue_option_by_index(option_index: int) -> Dictionary:
	return choose_dialogue_option(option_index)


func advance_dialogue_without_choice() -> Dictionary:
	var dialogue_snapshot: Dictionary = _current_dialogue_snapshot()
	var dialogue_library: Dictionary = registry.get_library("dialogues") if registry != null else {}
	var operation: Dictionary = _dictionary_or_empty(dialogue_action_controller.call("continue_without_choice", simulation, dialogue_snapshot, dialogue_library))
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	_apply_dialogue_trade_result(result)
	_refresh_dialogue_operation(operation)
	return result


func _refresh_dialogue_operation(operation: Dictionary) -> void:
	_refresh_operation_panels(_array_or_empty(operation.get("refresh", [])))


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
	var operation: Dictionary = _dictionary_or_empty(wait_action_controller.call("submit_wait", simulation, _dictionary_or_empty(world_result.get("map", {}))))
	return _apply_wait_action_operation(operation, "press_space_action")


func _process_auto_tick(delta: float) -> void:
	if bool(runtime_control_state_controller.call("should_submit_auto_tick", delta)):
		_submit_auto_tick_wait()


func _submit_auto_tick_wait() -> Dictionary:
	var snapshot: Dictionary = simulation.snapshot() if simulation != null else {}
	var operation: Dictionary = _dictionary_or_empty(wait_action_controller.call(
		"auto_tick_wait",
		simulation,
		has_active_dialogue(),
		gameplay_input_blocked_by_ui(),
		snapshot,
		_dictionary_or_empty(world_result.get("map", {}))
	))
	return _apply_wait_action_operation(operation, "auto_tick_wait")


func _apply_wait_action_operation(operation: Dictionary, refresh_reason: String) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	var refresh_steps: Array = _array_or_empty(operation.get("refresh", []))
	if refresh_steps.has("runtime"):
		_continue_crafting_queue_after_wait(result)
		if _rebuild_runtime_world_result(refresh_reason):
			_apply_world_root_snapshot(true)
			_refresh_world_runtime_bindings()
	if refresh_steps.has("all_panels"):
		refresh_all_panels(current_interaction_prompt())
	return result


func press_enter_action() -> Dictionary:
	if has_active_dialogue():
		return advance_dialogue_without_choice()
	return {"success": false, "reason": "no_enter_action"}


func take_active_container_item(item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(container_action_controller.call("take_item", _active_container_id(), item_id, count, stack_index, Callable(self, "_submit_inventory_action"), Callable(self, "_record_container_feedback")))
	return _apply_container_action_operation(operation)


func take_active_container_money(count: int = -1) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(container_action_controller.call("take_money", _active_container_id(), count, Callable(self, "_submit_inventory_action"), Callable(self, "_record_container_feedback")))
	return _apply_container_action_operation(operation)


func take_all_active_container_items() -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(container_action_controller.call("take_all", _active_container_id(), Callable(self, "_submit_inventory_action"), Callable(self, "_record_container_feedback")))
	return _apply_container_action_operation(operation)


func store_active_container_item(item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(container_action_controller.call("store_item", _active_container_id(), item_id, count, stack_index, Callable(self, "_submit_inventory_action"), Callable(self, "_record_container_feedback")))
	return _apply_container_action_operation(operation)


func store_all_active_container_items() -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(container_action_controller.call("store_all", _active_container_id(), Callable(self, "_submit_inventory_action"), Callable(self, "_record_container_feedback")))
	return _apply_container_action_operation(operation)


func transfer_active_container_item(source: String, item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(container_action_controller.call("transfer_item", source, _active_container_id(), item_id, count, stack_index, Callable(self, "_submit_inventory_action"), Callable(self, "_record_container_feedback")))
	return _apply_container_action_operation(operation)


func transfer_all_active_container_items(source: String) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(container_action_controller.call("transfer_all", source, _active_container_id(), Callable(self, "_submit_inventory_action"), Callable(self, "_record_container_feedback")))
	return _apply_container_action_operation(operation)


func _apply_container_action_operation(operation: Dictionary) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	_refresh_operation_panels(_array_or_empty(operation.get("refresh", [])))
	return result


func has_active_container_session() -> bool:
	return not _active_container_id().is_empty()


func drop_player_item(item_id: String, count: int = 1) -> Dictionary:
	var submit := Callable(self, "_submit_inventory_action") if simulation != null else Callable()
	var operation: Dictionary = _dictionary_or_empty(inventory_action_controller.call("drop_item", item_id, count, submit, Callable(self, "_record_inventory_feedback")))
	return _apply_inventory_action_operation(operation)


func deconstruct_player_item(item_id: String, count: int = 1) -> Dictionary:
	var submit := Callable(self, "_submit_inventory_action") if simulation != null else Callable()
	var operation: Dictionary = _dictionary_or_empty(inventory_action_controller.call("deconstruct_item", item_id, count, _crafting_context(), submit, Callable(self, "_record_inventory_feedback")))
	return _apply_inventory_action_operation(operation)


func split_player_inventory_stack(item_id: String, count: int = 1, source_stack_index: int = 0) -> Dictionary:
	var submit := Callable(self, "_submit_inventory_action") if simulation != null else Callable()
	var operation: Dictionary = _dictionary_or_empty(inventory_action_controller.call("split_stack", item_id, count, source_stack_index, submit, Callable(self, "_record_inventory_feedback")))
	return _apply_inventory_action_operation(operation)


func reorder_player_inventory_item(item_id: String, target_index: int) -> Dictionary:
	var submit := Callable(self, "_submit_inventory_action") if simulation != null else Callable()
	var operation: Dictionary = _dictionary_or_empty(inventory_action_controller.call("reorder_item", item_id, target_index, submit, Callable(self, "_record_inventory_feedback")))
	return _apply_inventory_action_operation(operation)


func use_player_item(item_id: String) -> Dictionary:
	var submit := Callable(self, "_submit_inventory_action") if simulation != null else Callable()
	var operation: Dictionary = _dictionary_or_empty(inventory_action_controller.call("use_item", item_id, submit, Callable(self, "_record_inventory_feedback")))
	return _apply_inventory_action_operation(operation)


func _apply_inventory_action_operation(operation: Dictionary) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	if bool(operation.get("rebuild_world", false)):
		_rebuild_world_after_runtime_change()
	_refresh_operation_panels(_array_or_empty(operation.get("refresh", [])))
	return result


func buy_active_trade_item(item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(trade_action_controller.call("buy_item", _active_shop_id(), item_id, count, stack_index, Callable(self, "_submit_inventory_action"), Callable(self, "_record_trade_feedback")))
	return _apply_trade_action_operation(operation)


func sell_active_trade_item(item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(trade_action_controller.call("sell_item", _active_shop_id(), item_id, count, stack_index, Callable(self, "_submit_inventory_action"), Callable(self, "_record_trade_feedback")))
	return _apply_trade_action_operation(operation)


func sell_active_trade_equipment(slot_id: String, item_id: String) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(trade_action_controller.call("sell_equipment", _active_shop_id(), slot_id, item_id, Callable(self, "_submit_inventory_action"), Callable(self, "_record_trade_feedback")))
	return _apply_trade_action_operation(operation)


func transfer_active_trade_item(source: String, item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(trade_action_controller.call("transfer_item", source, _active_shop_id(), item_id, count, stack_index, Callable(self, "_submit_inventory_action"), Callable(self, "_record_trade_feedback")))
	return _apply_trade_action_operation(operation)


func has_active_trade_session() -> bool:
	return not _active_shop_id().is_empty()


func confirm_active_trade_cart(entries: Array) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(trade_action_controller.call("confirm_cart", entries, _active_shop_id(), Callable(self, "_confirm_trade_cart_action"), Callable(self, "_record_trade_feedback")))
	return _apply_trade_action_operation(operation)


func _apply_trade_action_operation(operation: Dictionary) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	if bool(operation.get("rebuild_world", false)):
		_rebuild_world_after_runtime_change()
	_refresh_operation_panels(_array_or_empty(operation.get("refresh", [])))
	return result


func _confirm_trade_cart_action(shop_id: String, entries: Array) -> Dictionary:
	if simulation == null or registry == null:
		return {"success": false, "reason": "simulation_missing"}
	return _dictionary_or_empty(simulation.confirm_trade_cart(1, shop_id, entries, registry.get_library("items")))


func equip_player_item(item_id: String, slot_id: String) -> Dictionary:
	var submit := Callable(self, "_submit_inventory_action") if simulation != null else Callable()
	var operation: Dictionary = _dictionary_or_empty(character_action_controller.call("equip_item", item_id, slot_id, submit, Callable(self, "_record_character_feedback")))
	return _apply_character_action_operation(operation)


func unequip_player_slot(slot_id: String) -> Dictionary:
	var submit := Callable(self, "_submit_inventory_action") if simulation != null else Callable()
	var operation: Dictionary = _dictionary_or_empty(character_action_controller.call("unequip_slot", slot_id, submit, Callable(self, "_record_character_feedback")))
	return _apply_character_action_operation(operation)


func reload_player_equipped_slot(slot_id: String = "main_hand") -> Dictionary:
	var submit := Callable(self, "_submit_inventory_action") if simulation != null else Callable()
	var operation: Dictionary = _dictionary_or_empty(character_action_controller.call("reload_slot", slot_id, submit, Callable(self, "_record_character_feedback")))
	return _apply_character_action_operation(operation)


func allocate_player_attribute_point(attribute: String) -> Dictionary:
	var allocate := Callable(self, "_allocate_attribute_action") if simulation != null else Callable()
	var operation: Dictionary = _dictionary_or_empty(character_action_controller.call("allocate_attribute", attribute, allocate))
	return _apply_character_action_operation(operation)


func _apply_character_action_operation(operation: Dictionary) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	if bool(operation.get("rebuild_world", false)):
		_rebuild_world_after_runtime_change()
	_refresh_operation_panels(_array_or_empty(operation.get("refresh", [])))
	return result


func _allocate_attribute_action(attribute: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	return _dictionary_or_empty(simulation.allocate_attribute_point(1, attribute))


func learn_player_skill(skill_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var blocked: Dictionary = _player_command_rejection("learn_skill")
	if not blocked.is_empty():
		return blocked
	var operation: Dictionary = _dictionary_or_empty(skill_action_controller.call("learn_skill", skill_id, Callable(self, "_submit_player_command_action"), registry.get_library("skills")))
	return _apply_skill_action_operation(operation)


func bind_player_skill_to_hotbar(slot_id: String, skill_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var blocked: Dictionary = _player_command_rejection("bind_hotbar")
	if not blocked.is_empty():
		return blocked
	var operation: Dictionary = _dictionary_or_empty(skill_action_controller.call("bind_skill_to_hotbar", slot_id, skill_id, Callable(self, "_submit_player_command_action"), registry.get_library("skills")))
	return _apply_skill_action_operation(operation)


func bind_player_item_to_hotbar(slot_id: String, item_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var blocked: Dictionary = _player_command_rejection("bind_hotbar")
	if not blocked.is_empty():
		return blocked
	var operation: Dictionary = _dictionary_or_empty(skill_action_controller.call("bind_item_to_hotbar", slot_id, item_id, Callable(self, "_submit_player_command_action"), registry.get_library("items"), registry.get_library("json")))
	return _apply_skill_action_operation(operation)


func set_hotbar_group(group_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	if _world_action_presenter_blocks_input():
		return _action_presenter_command_rejected("set_hotbar_group")
	var set_group := Callable(simulation, "set_active_hotbar_group") if simulation.has_method("set_active_hotbar_group") else Callable()
	var operation: Dictionary = _dictionary_or_empty(skill_action_controller.call("set_hotbar_group", group_id, set_group))
	return _apply_skill_action_operation(operation)


func set_hotbar_group_label(group_id: String, label: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var set_label := Callable(simulation, "set_hotbar_group_label") if simulation.has_method("set_hotbar_group_label") else Callable()
	var operation: Dictionary = _dictionary_or_empty(skill_action_controller.call("set_hotbar_group_label", group_id, label, set_label))
	return _apply_skill_action_operation(operation)


func cycle_hotbar_group(direction: int) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	if _world_action_presenter_blocks_input():
		return _action_presenter_command_rejected("cycle_hotbar_group")
	var cycle_group := Callable(simulation, "cycle_hotbar_group") if simulation.has_method("cycle_hotbar_group") else Callable()
	var operation: Dictionary = _dictionary_or_empty(skill_action_controller.call("cycle_hotbar_group", direction, cycle_group))
	return _apply_skill_action_operation(operation)


func _apply_skill_action_operation(operation: Dictionary) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	if operation.has("target_markers") and runtime_input_controller != null and runtime_input_controller.has_method("update_skill_target_preview_markers"):
		runtime_input_controller.update_skill_target_preview_markers(_dictionary_or_empty(operation.get("target_markers", {})))
	var selected_prompt: Dictionary = current_interaction_prompt() if bool(operation.get("selected_prompt", false)) else {}
	_refresh_operation_panels(_array_or_empty(operation.get("refresh", [])), selected_prompt)
	return result


func _submit_player_command_action(command: Dictionary) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	return _dictionary_or_empty(simulation.submit_player_command(command))


func _preview_skill_target_action(skill_id: String, target: Dictionary) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	return _dictionary_or_empty(simulation.preview_skill_target(1, skill_id, registry.get_library("skills"), target, _dictionary_or_empty(world_result.get("map", {}))))


func use_hotbar_slot(slot_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var blocked: Dictionary = _player_command_rejection("hotbar")
	if not blocked.is_empty():
		return blocked
	var operation: Dictionary = _dictionary_or_empty(skill_action_controller.call(
		"use_hotbar_slot",
		slot_id,
		simulation.snapshot(),
		registry.get_library("skills"),
		registry.get_library("items"),
		registry.get_library("json"),
		Callable(self, "_submit_player_command_action"),
		Callable(self, "_submit_inventory_action"),
		skill_targeting_controller
	))
	return _apply_skill_action_operation(operation)


func begin_skill_targeting(slot_id: String, skill_id: String = "") -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var blocked: Dictionary = _player_command_rejection("use_skill")
	if not blocked.is_empty():
		return blocked
	var operation: Dictionary = _dictionary_or_empty(skill_action_controller.call(
		"begin_skill_targeting",
		slot_id,
		skill_id,
		simulation.snapshot(),
		registry.get_library("skills"),
		Callable(self, "_submit_player_command_action"),
		skill_targeting_controller
	))
	return _apply_skill_action_operation(operation)


func preview_active_skill_target(target: Dictionary) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(skill_action_controller.call(
		"preview_active_skill_target",
		target,
		Callable(self, "_preview_skill_target_action") if simulation != null else Callable(),
		skill_targeting_controller
	))
	return _apply_skill_action_operation(operation)


func confirm_active_skill_target(target: Dictionary = {}) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "skill_targeting_inactive"}
	var blocked: Dictionary = _player_command_rejection("use_skill")
	if not blocked.is_empty():
		return blocked
	var operation: Dictionary = _dictionary_or_empty(skill_action_controller.call(
		"confirm_active_skill_target",
		target,
		Callable(self, "_submit_player_command_action"),
		registry.get_library("skills"),
		_dictionary_or_empty(world_result.get("map", {})),
		skill_targeting_controller
	))
	return _apply_skill_action_operation(operation)


func cancel_active_skill_targeting(reason: String = "cancelled") -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(skill_action_controller.call("cancel_active_skill_targeting", reason, skill_targeting_controller))
	return _apply_skill_action_operation(operation)


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
	var operation: Dictionary = _dictionary_or_empty(crafting_action_controller.call("craft_recipe", simulation, recipe_id, count, registry.get_library("recipes"), _crafting_context(), _dictionary_or_empty(world_result.get("map", {})), crafting_feedback_controller))
	return _apply_crafting_action_operation(operation)


func confirm_crafting_queue(entries: Array) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var blocked: Dictionary = _player_command_rejection("crafting_queue")
	if not blocked.is_empty():
		return blocked
	var operation: Dictionary = _dictionary_or_empty(crafting_action_controller.call("confirm_queue", simulation, entries, registry.get_library("recipes"), _crafting_context(), _dictionary_or_empty(world_result.get("map", {})), crafting_feedback_controller, CRAFTING_QUEUE_ADVANCE_LIMIT))
	return _apply_crafting_action_operation(operation)


func _advance_crafting_queue(reason: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	return _dictionary_or_empty(crafting_action_controller.call("advance_queue", simulation, reason, registry.get_library("recipes"), _crafting_context(), _dictionary_or_empty(world_result.get("map", {})), CRAFTING_QUEUE_ADVANCE_LIMIT))


func _submit_crafting_queue_entry(recipe_id: String, count: int) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	return _dictionary_or_empty(crafting_action_controller.call("_submit_craft", simulation, recipe_id, count, registry.get_library("recipes"), _crafting_context(), _dictionary_or_empty(world_result.get("map", {})), true))


func _continue_crafting_queue_after_wait(result: Dictionary) -> void:
	crafting_action_controller.call("continue_queue_after_wait", simulation, result, registry.get_library("recipes"), _crafting_context(), _dictionary_or_empty(world_result.get("map", {})), crafting_feedback_controller, CRAFTING_QUEUE_ADVANCE_LIMIT)


func _wait_result_resumed_active_crafting_queue(result: Dictionary) -> bool:
	return bool(crafting_action_controller.call("wait_result_resumed_active_crafting_queue", result))


func _completed_crafting_count_from_queue_result(result: Dictionary) -> int:
	return int(crafting_action_controller.call("completed_crafting_count_from_queue_result", simulation, result))


func update_crafting_queue(entries: Array) -> Dictionary:
	return _dictionary_or_empty(crafting_action_controller.call("update_queue", simulation, entries, crafting_feedback_controller))


func crafting_queue_snapshot() -> Dictionary:
	return _dictionary_or_empty(crafting_action_controller.call("queue_snapshot", simulation, crafting_feedback_controller))


func _normalized_crafting_queue(entries: Array) -> Array[Dictionary]:
	return _array_of_dictionaries(crafting_action_controller.call("normalize_queue", entries, crafting_feedback_controller))


func _crafting_queue_total_count(entries: Array) -> int:
	return int(crafting_action_controller.call("queue_total_count", entries, crafting_feedback_controller))


func cancel_pending_crafting(reason: String = "crafting_ui") -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var operation: Dictionary = _dictionary_or_empty(crafting_action_controller.call("cancel_pending", simulation, reason, _dictionary_or_empty(world_result.get("map", {})), crafting_feedback_controller))
	return _apply_crafting_action_operation(operation)


func _set_latest_crafting_queue_result(result: Dictionary, trigger: String) -> void:
	crafting_action_controller.call("record_queue_result", crafting_feedback_controller, result, trigger, simulation)


func _apply_crafting_action_operation(operation: Dictionary) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	_refresh_operation_panels(_array_or_empty(operation.get("refresh", [])))
	return result


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
	var operation: Dictionary = _dictionary_or_empty(world_panel_action_controller.call(
		"turn_in_quest",
		quest_id,
		Callable(self, "_turn_in_quest_action") if simulation != null else Callable()
	))
	return _apply_world_panel_action_operation(operation)


func enter_overworld_location_from_panel(location_id: String) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(world_panel_action_controller.call(
		"enter_overworld_location",
		location_id,
		Callable(self, "_enter_overworld_location_action") if simulation != null else Callable()
	))
	return _apply_world_panel_action_operation(operation)


func _turn_in_quest_action(quest_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	return _dictionary_or_empty(simulation.turn_in_quest(1, quest_id))


func _enter_overworld_location_action(location_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing", "location_id": location_id}
	return _dictionary_or_empty(simulation.enter_location(1, location_id, registry.get_library("overworld")))


func _apply_world_panel_action_operation(operation: Dictionary) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	if bool(operation.get("rebuild_world", false)):
		_rebuild_world_after_runtime_change({}, result)
		return result
	_refresh_operation_panels(_array_or_empty(operation.get("refresh", [])), current_interaction_prompt())
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
	var accepted: Dictionary = _dictionary_or_empty(runtime_refresh_controller.call("accept_refresh_result", refresh, fallback_error))
	world_result = _dictionary_or_empty(accepted.get("world_result", {}))
	if not bool(accepted.get("ok", false)):
		push_error(str(accepted.get("error_message", fallback_error)))
		return false
	if bool(accepted.get("sync_observed_level", false)):
		_sync_observed_level_to_map()
	return true


func _setup_world_container() -> void:
	if world_root == null or not is_instance_valid(world_root):
		world_root = WorldRootScene.instantiate() as Node3D
		if world_root == null:
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
	runtime_performance_tracker.call("record_world_render", counts, world_root)
	if world_root.has_method("ensure_world_container"):
		world_container = world_root.call("ensure_world_container")
	return counts


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
	if hud_root == null:
		hud_root = HudRoot.new(self)
	hud_root.setup_panels(registry, simulation, world_result, _ui_feedback_payload())
	panel_controller = hud_root.panel_controller
	_sync_panel_refs_from_hud_root()
	# 对外保留面板引用，方便既有 smoke 和编辑器入口继续做状态复核。
	_sync_debug_console_schema()


func _ui_feedback_payload() -> Dictionary:
	return {
		"active_trade_target": active_trade_target,
		"active_trade_feedback": active_trade_feedback,
		"active_container_feedback": active_container_feedback,
		"active_character_feedback": active_character_feedback,
		"active_inventory_feedback": active_inventory_feedback,
	}


func _sync_panel_refs_from_hud_root() -> void:
	if hud_root == null:
		return
	var refs: Dictionary = _dictionary_or_empty(hud_root.panel_refs())
	hud = refs.get("hud", null) as Control
	dialogue_panel = refs.get("dialogue", null) as Control
	inventory_panel = refs.get("inventory", null) as Control
	trade_panel = refs.get("trade", null) as Control
	container_panel = refs.get("container", null) as Control
	character_panel = refs.get("character", null) as Control
	journal_panel = refs.get("journal", null) as Control
	map_panel = refs.get("map", null) as Control
	skills_panel = refs.get("skills", null) as Control
	crafting_panel = refs.get("crafting", null) as Control
	settings_panel = refs.get("settings", null) as Control


func _sync_debug_console_schema() -> void:
	if hud_root == null:
		return
	hud_root.set_debug_console_schema(
		debug_runtime_controller.command_schema(),
		debug_runtime_controller.command_suggestions(),
		debug_runtime_controller.permission_snapshot(self)
	)


func _apply_interaction_execution_result(result: Dictionary, executed_target: Dictionary) -> void:
	var followup: Dictionary = _dictionary_or_empty(interaction_action_controller.call("execution_followup", result, executed_target))
	_apply_interaction_followup(followup)
	var stage_panel_to_open := str(followup.get("stage_panel", ""))
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


func _apply_interaction_followup(followup: Dictionary) -> void:
	if bool(followup.get("reset_container_feedback", false)):
		active_container_feedback = {}
	var trade_target: Dictionary = _dictionary_or_empty(followup.get("trade_target", {}))
	if not trade_target.is_empty():
		active_trade_target = trade_target.duplicate(true)
	if bool(followup.get("reset_trade_feedback", false)):
		active_trade_feedback = {}


func _open_stage_panel_from_interaction(panel_id: String) -> void:
	if hud_root == null or not ["crafting"].has(panel_id):
		return
	hud_root.open_stage_panel(panel_id)


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
	if world_action_flow_controller == null:
		return
	world_action_flow_controller.call("process_completion")


func _queue_deferred_world_refresh(final_world_result: Dictionary, selected_prompt: Dictionary, command_result: Dictionary, source: String, render_world: bool = true) -> void:
	world_action_flow_controller.call("queue_deferred_world_refresh", final_world_result, selected_prompt, command_result, source, render_world)


func _apply_pending_world_action_final_refresh(trigger: String, pending_refresh: Dictionary = {}) -> bool:
	if pending_refresh.is_empty() and world_action_flow_controller != null:
		pending_refresh = _dictionary_or_empty(world_action_flow_controller.call("take_pending_final_refresh"))
	if pending_refresh.is_empty():
		return false
	var refresh: Dictionary = _dictionary_or_empty(runtime_refresh_controller.call("apply_pending_final_refresh", simulation, interaction_controller, pending_refresh, "world refresh failed"))
	world_result = _dictionary_or_empty(refresh.get("world_result", {}))
	if not bool(refresh.get("ok", false)):
		push_error(str(refresh.get("error_message", "world refresh failed")))
		return false
	if bool(refresh.get("sync_observed_level", false)):
		_sync_observed_level_to_map()
	_apply_world_root_snapshot(bool(refresh.get("render_world", true)))
	_refresh_world_runtime_bindings()
	world_action_flow_controller.call("mark_final_refresh_applied", pending_refresh, trigger)
	if bool(refresh.get("refresh_all_panels", false)):
		refresh_all_panels(_dictionary_or_empty(refresh.get("prompt", {})))
	return true


func _deferred_world_refresh_public_snapshot(source: Dictionary) -> Dictionary:
	return _dictionary_or_empty(world_action_flow_controller.call("deferred_world_refresh_public_snapshot", source))


func _apply_pending_world_action_ui(trigger: String, pending_ui: Dictionary = {}) -> bool:
	if pending_ui.is_empty() and world_action_flow_controller != null:
		pending_ui = _dictionary_or_empty(world_action_flow_controller.call("take_pending_ui"))
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


func _connect_world_action_flow_signals() -> void:
	if world_action_flow_controller == null:
		return
	var final_callable := Callable(self, "_on_world_action_final_refresh_ready")
	if not world_action_flow_controller.is_connected("final_refresh_ready", final_callable):
		world_action_flow_controller.connect("final_refresh_ready", final_callable)
	var ui_callable := Callable(self, "_on_world_action_deferred_ui_ready")
	if not world_action_flow_controller.is_connected("deferred_ui_ready", ui_callable):
		world_action_flow_controller.connect("deferred_ui_ready", ui_callable)


func _on_world_action_final_refresh_ready(pending_refresh: Dictionary) -> void:
	_apply_pending_world_action_final_refresh("presenter_finished", pending_refresh)


func _on_world_action_deferred_ui_ready(pending_ui: Dictionary) -> void:
	_apply_pending_world_action_ui("presenter_finished", pending_ui)


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
	var modal_name := _panel_modal_blocker_name()
	var result: Dictionary = _dictionary_or_empty(player_command_blocker.call(
		"player_command_rejection",
		action,
		observe_mode_enabled,
		modal_name,
		_world_action_presenter_blocks_input(),
		gameplay_input_blocker_snapshot()
	))
	if not result.is_empty():
		refresh_hud(current_interaction_prompt())
	return result


func _observe_command_rejected(action: String) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(player_command_blocker.call("observe_command_rejected", action, observe_mode_enabled))
	refresh_hud(current_interaction_prompt())
	return result


func _action_presenter_command_rejected(action: String) -> Dictionary:
	var blocker: Dictionary = gameplay_input_blocker_snapshot()
	var result: Dictionary = _dictionary_or_empty(player_command_blocker.call("action_presenter_command_rejected", action, blocker))
	refresh_hud(current_interaction_prompt())
	return result


func _ui_modal_command_rejected(action: String, modal_name: String) -> Dictionary:
	var blocker: Dictionary = gameplay_input_blocker_snapshot()
	var result: Dictionary = _dictionary_or_empty(player_command_blocker.call("ui_modal_command_rejected", action, modal_name, blocker))
	refresh_hud(current_interaction_prompt())
	return result


func _record_container_feedback(result: Dictionary, action: String, container_id: String, item_id: String, count: int) -> void:
	ui_feedback_state_controller.call("record_container_feedback", result, action, container_id, item_id, count)


func _record_trade_feedback(result: Dictionary, action: String, shop_id: String, item_id: String, count: int) -> void:
	ui_feedback_state_controller.call("record_trade_feedback", result, action, shop_id, item_id, count)


func _record_inventory_feedback(result: Dictionary, action: String, item_id: String, count: int) -> void:
	ui_feedback_state_controller.call("record_inventory_feedback", result, action, item_id, count)


func _record_character_feedback(result: Dictionary, action: String, slot_id: String, item_id: String) -> void:
	ui_feedback_state_controller.call("record_character_feedback", result, action, slot_id, item_id)


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
	if simulation == null:
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
		interaction_action_controller.call("clear_selection", interaction_controller, "focus_switch", false)
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
