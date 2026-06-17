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
const RuntimeSessionContextController = preload("res://scripts/app/controllers/runtime_session_context_controller.gd")
const RuntimeSceneCoordinator = preload("res://scripts/app/controllers/runtime_scene_coordinator.gd")
const GameUiCoordinator = preload("res://scripts/app/controllers/game_ui_coordinator.gd")
const RuntimeDebugCoordinator = preload("res://scripts/app/controllers/runtime_debug_coordinator.gd")
const PlayerCommandCoordinator = preload("res://scripts/app/controllers/player_command_coordinator.gd")
const PlayerUiActionCoordinator = preload("res://scripts/app/controllers/player_ui_action_coordinator.gd")
const CraftingQueueCoordinator = preload("res://scripts/app/controllers/crafting_queue_coordinator.gd")
const WorldActionFlowController = preload("res://scripts/app/controllers/world_action_flow_controller.gd")
const PlayerCommandAuthorityAudit = preload("res://scripts/app/controllers/player_command_authority_audit.gd")
const PlayerCommandBlocker = preload("res://scripts/app/controllers/player_command_blocker.gd")
const AiDebugSnapshotBuilder = preload("res://scripts/app/controllers/ai_debug_snapshot_builder.gd")
const WorldTimeSnapshotBuilder = preload("res://scripts/app/controllers/world_time_snapshot_builder.gd")
const UiFeedbackStateController = preload("res://scripts/app/controllers/ui_feedback_state_controller.gd")
const SkillTargetingController = preload("res://scripts/app/controllers/skill_targeting_controller.gd")
const CraftingFeedbackController = preload("res://scripts/app/controllers/crafting_feedback_controller.gd")
const CraftingActionController = preload("res://scripts/app/controllers/crafting_action_controller.gd")
const CraftingContextBuilder = preload("res://scripts/app/controllers/crafting_context_builder.gd")
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
const PlayerActionRefreshController = preload("res://scripts/app/controllers/player_action_refresh_controller.gd")
const PlayerInteractionController = preload("res://scripts/app/controllers/player_interaction_controller.gd")
const TurnActionRunner = preload("res://scripts/app/controllers/turn_action_runner.gd")
const ActorViewController = preload("res://scripts/world/actor_view_controller.gd")
const AudioFeedbackController = preload("res://scripts/app/audio_feedback_controller.gd")
const HUD_ROOT_SCENE = preload("res://scenes/ui/hud_root.tscn")

var registry: ContentRegistry
var simulation: RefCounted
var world_result: Dictionary = {}
var interaction_controller: RefCounted
var runtime_input_controller: RefCounted
var panel_controller: RefCounted
var hud_root
var world_root: Node3D
var world_action_flow_controller: RefCounted = WorldActionFlowController.new()
var world_action_presenter: RefCounted:
	get:
		if world_action_flow_controller == null:
			return null
		return world_action_flow_controller.presenter
var audio_feedback_controller: Node
var _world_container_ref: Node3D
var _fog_overlay_ref: ColorRect
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
var player_action_refresh_controller: RefCounted = PlayerActionRefreshController.new()
var ui_feedback_state_controller: RefCounted = UiFeedbackStateController.new()
var active_trade_target: Dictionary:
	get:
		return ui_feedback_state_controller.active_trade_target if ui_feedback_state_controller != null else {}
	set(value):
		if ui_feedback_state_controller != null:
			ui_feedback_state_controller.active_trade_target = value.duplicate(true)
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
var crafting_context_builder: RefCounted = CraftingContextBuilder.new()
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
var latest_action_chain: Dictionary = {}
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
var runtime_session_context_controller: RefCounted = RuntimeSessionContextController.new()
var runtime_scene_coordinator: RefCounted = RuntimeSceneCoordinator.new()
var game_ui_coordinator: RefCounted = GameUiCoordinator.new()
var runtime_debug_coordinator: RefCounted = RuntimeDebugCoordinator.new()
var player_command_coordinator: RefCounted = PlayerCommandCoordinator.new()
var player_ui_action_coordinator: RefCounted = PlayerUiActionCoordinator.new()
var crafting_queue_coordinator: RefCounted = CraftingQueueCoordinator.new()
var turn_action_runner: RefCounted = TurnActionRunner.new()
var actor_view_controller: RefCounted = ActorViewController.new()
var latest_structural_refresh_boundary: Dictionary = {}

func _ready() -> void:
	runtime_scene_coordinator.call("configure", self)
	game_ui_coordinator.call("configure", self)
	runtime_debug_coordinator.call("configure", self)
	player_command_coordinator.call("configure", self)
	player_ui_action_coordinator.call("configure", self)
	crafting_queue_coordinator.call("configure", self)
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
	print("Godot game root runtime world: %s" % JSON.stringify(counts))


func _consume_startup_request() -> Dictionary:
	return _dictionary_or_empty(runtime_boot_controller.call("consume_startup_request"))


func _build_runtime_from_startup_request(request: Dictionary) -> Dictionary:
	return _dictionary_or_empty(runtime_boot_controller.call("build_runtime_from_startup_request", request))


func _process(delta: float) -> void:
	_update_runtime_performance(delta)
	game_input_router.process(runtime_input_controller, delta)
	if turn_action_runner != null and turn_action_runner.has_method("process"):
		turn_action_runner.call("process")
	_process_world_action_queue_completion()
	_update_tooltip_layer()
	_process_auto_tick(delta)


func _input(event: InputEvent) -> void:
	game_input_router.input(self, runtime_input_controller, event)


func _unhandled_input(event: InputEvent) -> void:
	game_input_router.unhandled_input(self, runtime_input_controller, event)


func refresh_hud(selected_prompt: Dictionary = {}) -> void:
	game_ui_coordinator.call("refresh_hud", selected_prompt)


func refresh_dialogue_panel() -> void:
	game_ui_coordinator.call("refresh_panel", "dialogue")


func refresh_inventory_panel() -> void:
	game_ui_coordinator.call("refresh_panel", "inventory", _ui_feedback_payload())


func refresh_trade_panel() -> void:
	game_ui_coordinator.call("refresh_trade_panel")


func refresh_container_panel() -> void:
	game_ui_coordinator.call("refresh_container_panel")


func refresh_character_panel() -> void:
	game_ui_coordinator.call("refresh_panel", "character", _ui_feedback_payload())


func refresh_journal_panel() -> void:
	game_ui_coordinator.call("refresh_panel", "journal")


func refresh_map_panel() -> void:
	game_ui_coordinator.call("refresh_panel", "map")


func refresh_skills_panel() -> void:
	game_ui_coordinator.call("refresh_panel", "skills")


func refresh_crafting_panel() -> void:
	game_ui_coordinator.call("refresh_panel", "crafting")


func refresh_all_panels(selected_prompt: Dictionary = {}) -> void:
	game_ui_coordinator.call("refresh_all_panels", selected_prompt)


func _close_stale_container_session() -> void:
	game_ui_coordinator.call("close_stale_container_session")


func _refresh_operation_panels(panel_ids: Array, selected_prompt: Dictionary = {}) -> void:
	game_ui_coordinator.call("refresh_operation_panels", panel_ids, selected_prompt)


func toggle_stage_panel(panel_id: String) -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("toggle_stage_panel", panel_id))


func close_stage_panels() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("close_stage_panels"))


func any_stage_panel_open() -> bool:
	return bool(game_ui_coordinator.call("any_stage_panel_open"))


func is_settings_open() -> bool:
	return bool(game_ui_coordinator.call("is_settings_open"))


func toggle_settings_panel() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("toggle_settings_panel"))


func gameplay_input_blocked_by_ui() -> bool:
	return bool(game_ui_coordinator.call("gameplay_input_blocked_by_ui"))


func gameplay_input_blocker_name() -> String:
	return str(game_ui_coordinator.call("gameplay_input_blocker_name"))


func gameplay_input_blocker_snapshot() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("gameplay_input_blocker_snapshot"))


func _hud_input_blocker_snapshot() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("hud_input_blocker_snapshot"))


func _close_hud_interaction_menu() -> bool:
	return bool(game_ui_coordinator.call("close_hud_interaction_menu"))


func show_interaction_menu(screen_position: Vector2, prompt: Dictionary = {}) -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("show_interaction_menu", screen_position, prompt))


func hide_interaction_menu() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("hide_interaction_menu"))


func is_interaction_menu_open() -> bool:
	return bool(game_ui_coordinator.call("is_interaction_menu_open"))


func _panel_modal_blocker_name() -> String:
	return str(game_ui_coordinator.call("panel_modal_blocker_name"))


func _panel_modal_blocker_snapshot() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("panel_modal_blocker_snapshot"))


func _panel_input_blocker_snapshot() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("panel_input_blocker_snapshot"))


func _world_action_presenter_blocks_input() -> bool:
	return bool(game_ui_coordinator.call("world_action_presenter_blocks_input"))


func _world_action_blocker_snapshot() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("world_action_blocker_snapshot"))


func modal_stack_snapshot() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("modal_stack_snapshot"))


func menu_state_snapshot() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("menu_state_snapshot"))


func _root_close_priority(panel_priority: Array = []) -> Array[String]:
	var priorities: Array[String] = []
	for item in _array_or_empty(game_ui_coordinator.call("root_close_priority", panel_priority)):
		priorities.append(str(item))
	return priorities


func _close_context_snapshot() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("close_context_snapshot"))


func ui_theme_snapshot() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("ui_theme_snapshot"))


func context_menu_snapshot() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("context_menu_snapshot"))


func _ui_overlay_controller() -> RefCounted:
	return game_ui_coordinator.call("ui_overlay_controller") as RefCounted


func hover_tooltip_snapshot(control: Control = null) -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("hover_tooltip_snapshot", control))


func hotbar_hit_test_snapshot(screen_position: Vector2 = Vector2(-1.0, -1.0)) -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("hotbar_hit_test_snapshot", screen_position))


func drag_state_snapshot(data: Variant = {}, hover_target: Control = null) -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("drag_state_snapshot", data, hover_target))


func ui_layer_stack_snapshot(drag_data: Variant = {}, drag_hover_target: Control = null, tooltip_control: Control = null) -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("ui_layer_stack_snapshot", drag_data, drag_hover_target, tooltip_control))


func _setup_tooltip_layer() -> void:
	game_ui_coordinator.call("setup_tooltip_layer")


func _update_tooltip_layer() -> void:
	game_ui_coordinator.call("update_tooltip_layer")


func _hide_tooltip_layer(reason: String) -> void:
	game_ui_coordinator.call("hide_tooltip_layer", reason)


func _render_tooltip_snapshot(snapshot: Dictionary) -> void:
	game_ui_coordinator.call("render_tooltip_snapshot", snapshot)


func render_tooltip_snapshot(snapshot: Dictionary) -> void:
	_render_tooltip_snapshot(snapshot)


func _setup_drag_preview_layer() -> void:
	game_ui_coordinator.call("setup_drag_preview_layer")


func render_drag_preview_for_snapshot(drag_data: Variant = {}, hover_target: Control = null) -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("render_drag_preview_for_snapshot", drag_data, hover_target))


func _hide_drag_preview_layer(reason: String) -> void:
	game_ui_coordinator.call("hide_drag_preview_layer", reason)


func _render_drag_preview_snapshot(drag: Dictionary) -> void:
	game_ui_coordinator.call("render_drag_preview_snapshot", drag)


func handle_trade_shortcut(event: InputEventKey) -> bool:
	return bool(game_ui_coordinator.call("handle_trade_shortcut", event))


func toggle_controls_hint() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("toggle_controls_hint"))


func controls_hint_visible() -> bool:
	return bool(runtime_debug_coordinator.call("controls_hint_visible"))


func toggle_debug_console() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("toggle_debug_console"))


func close_debug_console() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("close_debug_console"))


func is_debug_console_open() -> bool:
	return bool(runtime_debug_coordinator.call("is_debug_console_open"))


func debug_console_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("debug_console_snapshot"))


func clear_debug_console_history() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("clear_debug_console_history"))


func reset_debug_view_state() -> void:
	runtime_debug_coordinator.call("reset_debug_view_state")


func submit_debug_console_command(command_text: String) -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("submit_debug_console_command", command_text))


func _execute_debug_console_command(command: String) -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("execute_debug_console_command", command))


func _apply_debug_console_intent(result: Dictionary) -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("apply_debug_console_intent", result))


func _merge_debug_console_intent_result(base_result: Dictionary, action_result: Dictionary, message: String) -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("merge_debug_console_intent_result", base_result, action_result, message))


func controls_hint_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("controls_hint_snapshot"))


func toggle_debug_panel() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("toggle_debug_panel"))


func is_debug_panel_open() -> bool:
	return bool(runtime_debug_coordinator.call("is_debug_panel_open"))


func debug_panel_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("debug_panel_snapshot"))


func cycle_debug_overlay_mode() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("cycle_debug_overlay_mode"))


func current_debug_overlay_mode() -> String:
	return str(runtime_debug_coordinator.call("current_debug_overlay_mode"))


func debug_overlay_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("debug_overlay_snapshot"))


func toggle_auto_tick() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("toggle_auto_tick"))


func is_auto_tick_enabled() -> bool:
	return bool(runtime_debug_coordinator.call("is_auto_tick_enabled"))


func is_observe_mode_enabled() -> bool:
	return bool(runtime_debug_coordinator.call("is_observe_mode_enabled"))


func can_issue_player_commands() -> bool:
	return bool(runtime_debug_coordinator.call("can_issue_player_commands"))


func toggle_observe_mode() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("toggle_observe_mode"))


func set_observe_mode(enabled: bool) -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("set_observe_mode", enabled))


func toggle_observe_playback() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("toggle_observe_playback"))


func cycle_observe_speed() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("cycle_observe_speed"))


func set_observe_speed(speed_id: String) -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("set_observe_speed", speed_id))


func cycle_info_panel(direction: int) -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("cycle_info_panel", direction))


func _apply_runtime_control_result(result: Dictionary) -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("apply_runtime_control_result", result))


func current_info_panel_page() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("current_info_panel_page"))


func info_panel_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("info_panel_snapshot"))


func runtime_control_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("runtime_control_snapshot"))


func tooltip_render_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("tooltip_render_snapshot"))


func drag_preview_render_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("drag_preview_render_snapshot"))


func player_command_authority_audit_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("player_command_authority_audit_snapshot"))


func _debug_console_mutation_authority_audit() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("debug_console_mutation_authority_audit"))


func ai_debug_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("ai_debug_snapshot"))


func runtime_world_time_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("runtime_world_time_snapshot"))


func world_action_presenter_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("world_action_presenter_snapshot"))


func world_action_queue_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("world_action_queue_snapshot"))


func turn_action_runner_snapshot() -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("turn_action_runner_snapshot"))


func drain_turn_action_runner(max_steps: int = 240) -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("drain_turn_action_runner", max_steps))


func settle_turn_action_runner_boundary(reason: String = "stable_boundary", max_steps: int = 8) -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("settle_turn_action_runner_boundary", reason, max_steps))


func prepare_runtime_save_boundary(reason: String = "save_boundary") -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("prepare_runtime_save_boundary", reason))


func actor_view_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("actor_view_snapshot"))


func camera_follow_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("camera_follow_snapshot"))


func world_render_policy_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("world_render_policy_snapshot"))


func audio_feedback_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("audio_feedback_snapshot"))


func runtime_refresh_report_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_scene_coordinator.call("runtime_refresh_report_snapshot"))


func structural_refresh_boundary_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_scene_coordinator.call("structural_refresh_boundary_snapshot"))


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
	var result: Dictionary = {}
	if turn_action_runner != null and turn_action_runner.has_method("snapshot"):
		var runner: Dictionary = turn_action_runner_snapshot()
		if bool(runner.get("active", false)) or bool(runner.get("presentation_active", false)):
			result = drain_turn_action_runner()
			result["reason"] = "finish_world_action_presentations"
	if world_action_flow_controller != null and world_action_flow_controller.has_method("finish_active_presentations"):
		var presenter_result: Dictionary = _dictionary_or_empty(world_action_flow_controller.call("finish_active_presentations"))
		if result.is_empty() or bool(presenter_result.get("active", false)) or int(presenter_result.get("finished_count", 0)) > 0:
			result = presenter_result
	elif result.is_empty():
		return world_action_presenter_snapshot()
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
	return _dictionary_or_empty(runtime_debug_coordinator.call("runtime_performance_snapshot"))


func runtime_hover_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("runtime_hover_snapshot"))


func runtime_selection_debug_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("runtime_selection_debug_snapshot"))


func _update_runtime_performance(delta: float) -> void:
	runtime_debug_coordinator.call("update_runtime_performance", delta)


func _last_pathfinding_time_ms() -> float:
	return float(runtime_debug_coordinator.call("last_pathfinding_time_ms"))


func _last_pathfinding_visited_cell_count() -> int:
	return int(runtime_debug_coordinator.call("last_pathfinding_visited_cell_count"))


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
	var result: Dictionary = _dictionary_or_empty(runtime_view_state_controller.call("cycle_focused_actor", world_result, simulation, is_observe_mode_enabled(), hud_root != null and hud_root.gameplay_input_blocked()))
	if bool(result.get("success", false)):
		_clear_focus_switch_ui_state()
		if runtime_input_controller != null and runtime_input_controller.has_method("focus_current_actor"):
			runtime_input_controller.focus_current_actor()
		refresh_hud(current_interaction_prompt())
	return result


func focus_actor(actor_id: int) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(runtime_view_state_controller.call("focus_actor", actor_id, world_result, simulation, is_observe_mode_enabled(), hud_root != null and hud_root.gameplay_input_blocked()))
	if bool(result.get("success", false)):
		_clear_focus_switch_ui_state()
		if runtime_input_controller != null and runtime_input_controller.has_method("focus_current_actor"):
			runtime_input_controller.focus_current_actor()
		refresh_hud(current_interaction_prompt())
	return result


func focused_actor_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_view_state_controller.call("focused_actor_snapshot", world_result, is_observe_mode_enabled()))


func focused_actor_grid_position() -> Dictionary:
	return _dictionary_or_empty(runtime_view_state_controller.call("focused_actor_grid_position", world_result, is_observe_mode_enabled()))


func focused_actor_visual_position() -> Variant:
	var node := focused_actor_node_for_camera_follow()
	if node != null:
		return node.global_position
	return null


func focused_actor_node_for_camera_follow() -> Node3D:
	var actor_id := _active_runner_actor_id()
	if actor_id <= 0:
		actor_id = int(_dictionary_or_empty(focused_actor_snapshot()).get("actor_id", _player_actor_id()))
	if actor_view_controller != null and actor_view_controller.has_method("active_actor_node"):
		var node := actor_view_controller.call("active_actor_node", actor_id) as Node3D
		if node != null:
			return node
	return null


func _active_runner_actor_id() -> int:
	var runner: Dictionary = turn_action_runner_snapshot()
	if bool(runner.get("active", false)) or bool(runner.get("presentation_active", false)):
		return int(runner.get("actor_id", 0))
	return 0


func _restore_actor_camera_follow(_reason: String = "") -> void:
	if runtime_input_controller != null and runtime_input_controller.has_method("focus_current_actor"):
		runtime_input_controller.focus_current_actor()


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
	var runner_before_close: Dictionary = turn_action_runner_snapshot()
	if bool(runner_before_close.get("active", false)) or bool(runner_before_close.get("presentation_active", false)):
		var pending_before: Dictionary = _runtime_pending_state_snapshot()
		var runner_result: Dictionary = settle_turn_action_runner_boundary(reason)
		refresh_hud(current_interaction_prompt())
		return {
			"success": true,
			"closed": "turn_action_runner",
			"result": runner_result,
			"pending_before": pending_before,
			"pending_after": _runtime_pending_state_snapshot(),
		}
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
	if interaction_controller == null:
		return {"success": false, "reason": "interaction_controller_missing"}
	var target: Dictionary = _dictionary_or_empty(interaction_controller.selected_target).duplicate(true)
	var prompt: Dictionary = _dictionary_or_empty(interaction_controller.selected_prompt)
	return request_player_interaction(target, str(prompt.get("primary_option_id", "")))


func execute_interaction_option(option_id: String) -> Dictionary:
	if interaction_controller == null:
		return {"success": false, "reason": "interaction_controller_missing"}
	var target: Dictionary = _dictionary_or_empty(interaction_controller.selected_target).duplicate(true)
	return request_player_interaction(target, option_id)


func _apply_interaction_action_operation(operation: Dictionary) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	if bool(operation.get("apply_result", false)):
		_apply_interaction_execution_result(result, _dictionary_or_empty(operation.get("executed_target", {})))
	return result


func select_grid_target(grid: Dictionary) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(interaction_action_controller.call("select_grid", interaction_controller, grid))
	return _apply_interaction_selection_operation(operation)


func execute_move_to_grid(grid: Dictionary) -> Dictionary:
	var selection: Dictionary = select_grid_target(grid)
	if not bool(selection.get("success", false)):
		return selection
	var result: Dictionary = request_player_move(grid)
	if not bool(result.get("success", false)):
		refresh_hud(current_interaction_prompt())
		return result
	refresh_hud(current_interaction_prompt())
	return result


func request_player_move(grid: Dictionary) -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("request_player_move", grid))


func _runner_allows_move_replacement() -> bool:
	return bool(player_command_coordinator.call("runner_allows_move_replacement"))


func request_player_attack(target_actor_id: int, options: Dictionary = {}) -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("request_player_attack", target_actor_id, options))


func request_player_interaction(target: Dictionary, option_id: String = "", options: Dictionary = {}) -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("request_player_interaction", target, option_id, options))


func request_player_wait(options: Dictionary = {}) -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("request_player_wait", options))


func request_player_craft(command: Dictionary, options: Dictionary = {}) -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("request_player_craft", command, options))


func sync_after_turn_action_step(step_result: Dictionary = {}, runner_snapshot: Dictionary = {}) -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("sync_after_turn_action_step", step_result, runner_snapshot))


func _turn_action_step_needs_world_result_sync(step_result: Dictionary, runner_snapshot: Dictionary, interaction_result: Dictionary, crafting_continuation: Dictionary = {}) -> bool:
	return bool(player_command_coordinator.call("turn_action_step_needs_world_result_sync", step_result, runner_snapshot, interaction_result, crafting_continuation))


func _turn_action_result_has_structural_change(result: Dictionary) -> bool:
	return bool(player_command_coordinator.call("turn_action_result_has_structural_change", result))


func _turn_action_runner_is_structural_refresh_boundary(runner_snapshot: Dictionary) -> bool:
	return bool(player_command_coordinator.call("turn_action_runner_is_structural_refresh_boundary", runner_snapshot))


func _runner_interaction_result(step_result: Dictionary, runner_snapshot: Dictionary) -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("runner_interaction_result", step_result, runner_snapshot))


func _is_final_interaction_result(result: Dictionary) -> bool:
	return bool(player_command_coordinator.call("is_final_interaction_result", result))


func _runner_step_should_continue_crafting_queue(step_result: Dictionary, runner_snapshot: Dictionary) -> bool:
	return bool(player_command_coordinator.call("runner_step_should_continue_crafting_queue", step_result, runner_snapshot))


func cancel_pending(reason: String = "cancelled", auto_end_turn: bool = false) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(interaction_action_controller.call("cancel_pending", interaction_controller, reason, auto_end_turn))
	return _apply_player_action_refresh_operation(operation, current_interaction_prompt(), _dictionary_or_empty(operation.get("result", {})))


func current_interaction_prompt() -> Dictionary:
	if interaction_controller == null:
		return {}
	return interaction_controller.current_prompt()


func close_trade_panel(reason: String = "closed") -> void:
	player_ui_action_coordinator.call("close_trade_panel", reason)


func choose_dialogue_option(option_ref: Variant) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("choose_dialogue_option", option_ref))


func choose_dialogue_option_by_index(option_index: int) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("choose_dialogue_option_by_index", option_index))


func advance_dialogue_without_choice() -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("advance_dialogue_without_choice"))


func _refresh_dialogue_operation(operation: Dictionary) -> void:
	player_ui_action_coordinator.call("refresh_dialogue_operation", operation)


func _apply_dialogue_trade_result(result: Dictionary) -> void:
	player_ui_action_coordinator.call("apply_dialogue_trade_result", result)


func has_active_dialogue() -> bool:
	return bool(player_ui_action_coordinator.call("has_active_dialogue"))


func press_space_action() -> Dictionary:
	var runner: Dictionary = turn_action_runner_snapshot()
	if (bool(runner.get("active", false)) or bool(runner.get("presentation_active", false))) and str(runner.get("action_kind", "")) == "wait":
		var drained: Dictionary = drain_turn_action_runner()
		if not bool(drained.get("drained", false)):
			return {"success": false, "reason": "turn_action_runner_active", "drain_result": drained}
	var operation: Dictionary = _dictionary_or_empty(wait_action_controller.call(
		"press_space_action",
		has_active_dialogue(),
		is_observe_mode_enabled(),
		Callable(self, "advance_dialogue_without_choice"),
		Callable(self, "toggle_observe_playback"),
		Callable(self, "cancel_pending"),
		simulation,
		_dictionary_or_empty(world_result.get("map", {}))
	))
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	if bool(result.get("success", false)) and str(result.get("kind", "")) == "wait_ready":
		return request_player_wait({"reason": "press_space_action"})
	return _apply_wait_action_operation(operation, "press_space_action")


func repeat_space_wait_action() -> Dictionary:
	var runner: Dictionary = turn_action_runner_snapshot()
	if bool(runner.get("active", false)) or bool(runner.get("presentation_active", false)):
		if str(runner.get("action_kind", "")) == "craft":
			return _continue_active_crafting_runner("space_hold_repeat")
		var drained: Dictionary = drain_turn_action_runner()
		if not bool(drained.get("drained", false)):
			return {"success": false, "reason": "turn_action_runner_active", "drain_result": drained}
	if has_active_dialogue() or is_observe_mode_enabled() or gameplay_input_blocked_by_ui():
		return {"success": false, "reason": "space_repeat_blocked"}
	if _runtime_has_pending_action():
		return {"success": false, "reason": "pending_blocked"}
	return request_player_wait({"reason": "space_hold_repeat"})


func submit_wait_action() -> Dictionary:
	var runner: Dictionary = turn_action_runner_snapshot()
	if (bool(runner.get("active", false)) or bool(runner.get("presentation_active", false))) and str(runner.get("action_kind", "")) == "craft":
		return _continue_active_crafting_runner("submit_wait_action")
	return request_player_wait({"reason": "submit_wait_action"})


func _process_auto_tick(delta: float) -> void:
	if bool(runtime_control_state_controller.call("should_submit_auto_tick", delta)):
		_submit_auto_tick_wait()


func _submit_auto_tick_wait() -> Dictionary:
	var runner: Dictionary = turn_action_runner_snapshot()
	if (bool(runner.get("active", false)) or bool(runner.get("presentation_active", false))) and str(runner.get("action_kind", "")) == "wait":
		var drained: Dictionary = drain_turn_action_runner()
		if not bool(drained.get("drained", false)):
			return {"success": false, "reason": "turn_action_runner_active", "drain_result": drained}
		return {
			"success": true,
			"kind": "auto_tick_runner_drained",
			"reason": "auto_tick_wait",
			"drain_result": drained,
		}
	if (bool(runner.get("active", false)) or bool(runner.get("presentation_active", false))) and str(runner.get("action_kind", "")) == "craft":
		return _continue_active_crafting_runner("auto_tick_wait")
	var snapshot: Dictionary = simulation.snapshot() if simulation != null else {}
	var operation: Dictionary = _dictionary_or_empty(wait_action_controller.call(
		"auto_tick_wait",
		simulation,
		has_active_dialogue(),
		gameplay_input_blocked_by_ui(),
		snapshot,
		_dictionary_or_empty(world_result.get("map", {}))
	))
	var validation_result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	if not bool(validation_result.get("success", false)):
		return validation_result
	return request_player_wait({"reason": "auto_tick_wait"})


func _continue_active_crafting_runner(reason: String = "crafting_continue") -> Dictionary:
	var runner_before: Dictionary = turn_action_runner_snapshot()
	if str(runner_before.get("action_kind", "")) != "craft" or (not bool(runner_before.get("active", false)) and not bool(runner_before.get("presentation_active", false))):
		return {"success": false, "reason": "active_crafting_runner_missing", "runner": runner_before}
	var drained: Dictionary = drain_turn_action_runner()
	refresh_hud(current_interaction_prompt())
	return {
		"success": bool(drained.get("drained", false)),
		"kind": "active_crafting_runner_continued",
		"reason": reason,
		"drain_result": drained.duplicate(true),
		"runner_before": runner_before.duplicate(true),
		"runner_after": turn_action_runner_snapshot(),
		"pending": not _dictionary_or_empty(_runtime_pending_state_snapshot().get("pending_crafting", {})).is_empty(),
	}


func _runtime_has_pending_action() -> bool:
	var pending: Dictionary = _runtime_pending_state_snapshot()
	return not _dictionary_or_empty(pending.get("pending_movement", {})).is_empty() \
		or not _dictionary_or_empty(pending.get("pending_interaction", {})).is_empty() \
		or not _dictionary_or_empty(pending.get("pending_crafting", {})).is_empty()


func _apply_wait_action_operation(operation: Dictionary, refresh_reason: String) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(operation.get("result", {}))
	var refresh_steps: Array = _array_or_empty(operation.get("refresh", []))
	var crafting_continuation: Dictionary = {}
	if refresh_steps.has("runtime"):
		crafting_continuation = _continue_crafting_queue_after_wait(result)
		if _rebuild_runtime_world_result(refresh_reason):
			_apply_runtime_scene_refresh(true)
	if bool(crafting_continuation.get("continued", false)):
		_refresh_operation_panels(_array_or_empty(crafting_continuation.get("refresh", [])))
	if refresh_steps.has("all_panels"):
		refresh_all_panels(current_interaction_prompt())
	return result


func press_enter_action() -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("press_enter_action"))


func take_active_container_item(item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("take_active_container_item", item_id, count, stack_index))


func take_active_container_money(count: int = -1) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("take_active_container_money", count))


func take_all_active_container_items() -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("take_all_active_container_items"))


func store_active_container_item(item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("store_active_container_item", item_id, count, stack_index))


func store_all_active_container_items() -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("store_all_active_container_items"))


func transfer_active_container_item(source: String, item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("transfer_active_container_item", source, item_id, count, stack_index))


func transfer_all_active_container_items(source: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("transfer_all_active_container_items", source))


func _apply_container_action_operation(operation: Dictionary) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("apply_container_action_operation", operation))


func has_active_container_session() -> bool:
	return bool(player_ui_action_coordinator.call("has_active_container_session"))


func drop_player_item(item_id: String, count: int = 1) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("drop_player_item", item_id, count))


func deconstruct_player_item(item_id: String, count: int = 1) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("deconstruct_player_item", item_id, count))


func split_player_inventory_stack(item_id: String, count: int = 1, source_stack_index: int = 0) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("split_player_inventory_stack", item_id, count, source_stack_index))


func reorder_player_inventory_item(item_id: String, target_index: int) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("reorder_player_inventory_item", item_id, target_index))


func use_player_item(item_id: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("use_player_item", item_id))


func _apply_inventory_action_operation(operation: Dictionary) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("apply_inventory_action_operation", operation))


func buy_active_trade_item(item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("buy_active_trade_item", item_id, count, stack_index))


func sell_active_trade_item(item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("sell_active_trade_item", item_id, count, stack_index))


func sell_active_trade_equipment(slot_id: String, item_id: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("sell_active_trade_equipment", slot_id, item_id))


func transfer_active_trade_item(source: String, item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("transfer_active_trade_item", source, item_id, count, stack_index))


func has_active_trade_session() -> bool:
	return bool(player_ui_action_coordinator.call("has_active_trade_session"))


func confirm_active_trade_cart(entries: Array) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("confirm_active_trade_cart", entries))


func _apply_trade_action_operation(operation: Dictionary) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("apply_trade_action_operation", operation))


func _confirm_trade_cart_action(shop_id: String, entries: Array) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("confirm_trade_cart_action", shop_id, entries))


func equip_player_item(item_id: String, slot_id: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("equip_player_item", item_id, slot_id))


func unequip_player_slot(slot_id: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("unequip_player_slot", slot_id))


func reload_player_equipped_slot(slot_id: String = "main_hand") -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("reload_player_equipped_slot", slot_id))


func allocate_player_attribute_point(attribute: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("allocate_player_attribute_point", attribute))


func _apply_character_action_operation(operation: Dictionary) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("apply_character_action_operation", operation))


func _allocate_attribute_action(attribute: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("allocate_attribute_action", attribute))


func learn_player_skill(skill_id: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("learn_player_skill", skill_id))


func bind_player_skill_to_hotbar(slot_id: String, skill_id: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("bind_player_skill_to_hotbar", slot_id, skill_id))


func bind_player_item_to_hotbar(slot_id: String, item_id: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("bind_player_item_to_hotbar", slot_id, item_id))


func set_hotbar_group(group_id: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("set_hotbar_group", group_id))


func set_hotbar_group_label(group_id: String, label: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("set_hotbar_group_label", group_id, label))


func cycle_hotbar_group(direction: int) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("cycle_hotbar_group", direction))


func _apply_skill_action_operation(operation: Dictionary) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("apply_skill_action_operation", operation))


func _submit_player_command_action(command: Dictionary) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("submit_player_command_action", command))


func _preview_skill_target_action(skill_id: String, target: Dictionary) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("preview_skill_target_action", skill_id, target))


func use_hotbar_slot(slot_id: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("use_hotbar_slot", slot_id))


func begin_skill_targeting(slot_id: String, skill_id: String = "") -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("begin_skill_targeting", slot_id, skill_id))


func preview_active_skill_target(target: Dictionary) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("preview_active_skill_target", target))


func confirm_active_skill_target(target: Dictionary = {}) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("confirm_active_skill_target", target))


func cancel_active_skill_targeting(reason: String = "cancelled") -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("cancel_active_skill_targeting", reason))


func has_active_skill_targeting() -> bool:
	return bool(player_ui_action_coordinator.call("has_active_skill_targeting"))


func active_skill_targeting_snapshot() -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("active_skill_targeting_snapshot"))


func craft_player_recipe(recipe_id: String, count: int = 1) -> Dictionary:
	return _dictionary_or_empty(crafting_queue_coordinator.call("craft_player_recipe", recipe_id, count))


func confirm_crafting_queue(entries: Array) -> Dictionary:
	return _dictionary_or_empty(crafting_queue_coordinator.call("confirm_crafting_queue", entries))


func _advance_crafting_queue(reason: String) -> Dictionary:
	return _dictionary_or_empty(crafting_queue_coordinator.call("advance_crafting_queue", reason))


func _submit_crafting_queue_entry(recipe_id: String, count: int) -> Dictionary:
	return _dictionary_or_empty(crafting_queue_coordinator.call("submit_crafting_queue_entry", recipe_id, count))


func _continue_crafting_queue_after_wait(result: Dictionary, wait_runner_snapshot: Dictionary = {}) -> Dictionary:
	return _dictionary_or_empty(crafting_queue_coordinator.call("continue_crafting_queue_after_wait", result, wait_runner_snapshot))


func _submit_craft_via_turn_action_runner(recipe_id: String, count: int, recipe_library: Dictionary, crafting_context: Dictionary, topology: Dictionary, queue_active: bool) -> Dictionary:
	return _dictionary_or_empty(crafting_queue_coordinator.call("submit_craft_via_turn_action_runner", recipe_id, count, recipe_library, crafting_context, topology, queue_active))


func _wait_result_resumed_active_crafting_queue(result: Dictionary) -> bool:
	return bool(crafting_queue_coordinator.call("wait_result_resumed_active_crafting_queue", result))


func _completed_crafting_count_from_queue_result(result: Dictionary) -> int:
	return int(crafting_queue_coordinator.call("completed_crafting_count_from_queue_result", result))


func update_crafting_queue(entries: Array) -> Dictionary:
	return _dictionary_or_empty(crafting_queue_coordinator.call("update_crafting_queue", entries))


func crafting_queue_snapshot() -> Dictionary:
	return _dictionary_or_empty(crafting_queue_coordinator.call("crafting_queue_snapshot"))


func _normalized_crafting_queue(entries: Array) -> Array[Dictionary]:
	return _array_of_dictionaries(crafting_queue_coordinator.call("normalized_crafting_queue", entries))


func _crafting_queue_total_count(entries: Array) -> int:
	return int(crafting_queue_coordinator.call("crafting_queue_total_count", entries))


func cancel_pending_crafting(reason: String = "crafting_ui") -> Dictionary:
	return _dictionary_or_empty(crafting_queue_coordinator.call("cancel_pending_crafting", reason))


func _set_latest_crafting_queue_result(result: Dictionary, trigger: String) -> void:
	crafting_queue_coordinator.call("set_latest_crafting_queue_result", result, trigger)


func _apply_crafting_action_operation(operation: Dictionary) -> Dictionary:
	return _dictionary_or_empty(crafting_queue_coordinator.call("apply_crafting_action_operation", operation))


func _crafting_context() -> Dictionary:
	return _dictionary_or_empty(crafting_queue_coordinator.call("crafting_context"))


func crafting_context() -> Dictionary:
	return _crafting_context()


func turn_in_player_quest(quest_id: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("turn_in_player_quest", quest_id))


func enter_overworld_location_from_panel(location_id: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("enter_overworld_location_from_panel", location_id))


func _turn_in_quest_action(quest_id: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("turn_in_quest_action", quest_id))


func _enter_overworld_location_action(location_id: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("enter_overworld_location_action", location_id))


func _apply_world_panel_action_operation(operation: Dictionary) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("apply_world_panel_action_operation", operation))


func _apply_player_action_refresh_operation(operation: Dictionary, selected_prompt: Dictionary = {}, rebuild_command_result: Dictionary = {}, rebuild_selected_prompt: Variant = null) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("apply_player_action_refresh_operation", operation, selected_prompt, rebuild_command_result, rebuild_selected_prompt))


func _rebuild_world_after_runtime_change(selected_prompt: Dictionary = {}, command_result: Dictionary = {}) -> void:
	runtime_scene_coordinator.call("rebuild_world_after_runtime_change", selected_prompt, command_result)


func _rebuild_runtime_world_result(source: String) -> bool:
	return bool(runtime_scene_coordinator.call("rebuild_runtime_world_result", source))


func _apply_existing_runtime_world_result(next_world_result: Dictionary, source: String, fallback_error: String = "world refresh failed") -> bool:
	return bool(runtime_scene_coordinator.call("apply_existing_runtime_world_result", next_world_result, source, fallback_error))


func _accept_runtime_refresh_result(refresh: Dictionary, fallback_error: String) -> bool:
	return bool(runtime_scene_coordinator.call("accept_runtime_refresh_result", refresh, fallback_error))


func _world_container_node() -> Node3D:
	return runtime_scene_coordinator.call("world_container_node") as Node3D


func _player_actor_id() -> int:
	return int(runtime_scene_coordinator.call("player_actor_id"))


func _setup_world_container() -> void:
	runtime_scene_coordinator.call("setup_world_container")


func _setup_runtime_input_controller() -> void:
	runtime_scene_coordinator.call("setup_runtime_input_controller")


func _configure_turn_action_runner() -> void:
	runtime_scene_coordinator.call("configure_turn_action_runner")


func _refresh_world_runtime_bindings() -> void:
	runtime_scene_coordinator.call("refresh_world_runtime_bindings")


func refresh_world_visuals(render_world: bool = true) -> Dictionary:
	return _dictionary_or_empty(runtime_scene_coordinator.call("refresh_world_visuals", render_world))


func rebuild_runtime_world(selected_prompt: Dictionary = {}, command_result: Dictionary = {}) -> void:
	_rebuild_world_after_runtime_change(selected_prompt, command_result)


func _apply_runtime_scene_refresh(render_world: bool = true, selected_prompt: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	return _dictionary_or_empty(runtime_scene_coordinator.call("apply_runtime_scene_refresh", render_world, selected_prompt, options))


func _prepare_structural_refresh_boundary(source: String, render_world: bool = true) -> Dictionary:
	return _dictionary_or_empty(runtime_scene_coordinator.call("prepare_structural_refresh_boundary", source, render_world))


func _record_structural_refresh_boundary(boundary: Dictionary, source: String, counts: Dictionary) -> void:
	runtime_scene_coordinator.call("record_structural_refresh_boundary", boundary, source, counts)


func _apply_world_root_snapshot(render_world: bool = true) -> Dictionary:
	return _dictionary_or_empty(runtime_scene_coordinator.call("apply_world_root_snapshot", render_world))


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
	game_ui_coordinator.call("setup_panels")


func _ui_feedback_payload() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("ui_feedback_payload"))


func _sync_panel_refs_from_hud_root() -> void:
	game_ui_coordinator.call("sync_panel_refs_from_hud_root")


func _sync_debug_console_schema() -> void:
	if hud_root == null:
		return
	hud_root.set_debug_console_schema(
		debug_runtime_controller.command_schema(),
		debug_runtime_controller.command_suggestions(),
		debug_runtime_controller.permission_snapshot(self)
	)


func _apply_interaction_execution_result(result: Dictionary, executed_target: Dictionary) -> void:
	var presentation_result: Dictionary = _interaction_world_action_result(result, executed_target)
	var followup: Dictionary = _dictionary_or_empty(interaction_action_controller.call("execution_followup", result, executed_target))
	ui_feedback_state_controller.call("apply_interaction_followup", followup)
	var stage_panel_to_open := str(followup.get("stage_panel", ""))
	var final_world_result: Dictionary = _build_interaction_final_world_result()
	var presenter_result: Dictionary = _dictionary_or_empty(world_action_flow_controller.call("present_result", self, _world_container_node(), presentation_result, world_result))
	var presenter_active := bool(presenter_result.get("active", false))
	if presenter_active:
		_queue_deferred_world_refresh(final_world_result, _dictionary_or_empty(result.get("prompt", {})), presentation_result, "interaction_final_refresh", true)
	else:
		_apply_interaction_final_world_result(final_world_result, presentation_result)
	var deferred_ui := false
	if not stage_panel_to_open.is_empty():
		deferred_ui = _queue_or_open_stage_panel_after_world_action(stage_panel_to_open, presentation_result)
	elif _queue_or_refresh_all_panels_after_world_action(presentation_result):
		deferred_ui = true
	if deferred_ui:
		refresh_hud(_dictionary_or_empty(result.get("prompt", {})))
	else:
		refresh_all_panels(_dictionary_or_empty(result.get("prompt", {})))


func _build_interaction_final_world_result() -> Dictionary:
	if runtime_refresh_controller == null or simulation == null:
		return world_result.duplicate(true)
	var built: Dictionary = _dictionary_or_empty(runtime_refresh_controller.call("build_world_result_from_snapshot", simulation.snapshot(), "interaction_final_refresh"))
	if bool(built.get("ok", false)):
		return _dictionary_or_empty(built.get("world_result", {})).duplicate(true)
	push_error("交互最终地图快照构建失败: %s" % str(built.get("error", built.get("reason", "unknown"))))
	return world_result.duplicate(true)


func _apply_interaction_final_world_result(final_world_result: Dictionary, presentation_result: Dictionary) -> void:
	_apply_existing_runtime_world_result(final_world_result, "interaction_final_refresh")
	_apply_runtime_scene_refresh(true, {}, {
		"present_world_action": false,
		"command_result": presentation_result,
		"source": "interaction_final_refresh",
	})


func _interaction_world_action_result(result: Dictionary, executed_target: Dictionary) -> Dictionary:
	var output: Dictionary = result.duplicate(true)
	var events: Array = _interaction_result_events(output)
	if not _interaction_events_include_success(events):
		var payload: Dictionary = _interaction_success_payload_for_presentation(output, executed_target)
		if not payload.is_empty():
			events.append({
				"kind": "interaction_succeeded",
				"payload": payload,
			})
	if not events.is_empty():
		output["events"] = events.duplicate(true)
	return output


func _interaction_result_events(result: Dictionary) -> Array:
	var events: Array = []
	for source in [
		result.get("events", []),
		result.get("emitted_events", []),
		_dictionary_or_empty(result.get("runtime_snapshot_delta", {})).get("events", []),
		_dictionary_or_empty(result.get("pending_result", {})).get("events", []),
		_dictionary_or_empty(result.get("result", {})).get("events", []),
		_dictionary_or_empty(_dictionary_or_empty(result.get("result", {})).get("runtime_snapshot_delta", {})).get("events", []),
	]:
		for event_value in _array_or_empty(source):
			var event: Dictionary = _dictionary_or_empty(event_value)
			if not event.is_empty():
				events.append(event.duplicate(true))
	return events


func _interaction_events_include_success(events: Array) -> bool:
	for event_value in events:
		var event: Dictionary = _dictionary_or_empty(event_value)
		if str(event.get("kind", "")) == "interaction_succeeded":
			return true
	return false


func _interaction_success_payload_for_presentation(result: Dictionary, executed_target: Dictionary) -> Dictionary:
	if not bool(result.get("success", false)):
		return {}
	var prompt: Dictionary = _dictionary_or_empty(result.get("prompt", {}))
	var target: Dictionary = _dictionary_or_empty(prompt.get("target", {}))
	if target.is_empty():
		target = executed_target.duplicate(true)
	var option_id := str(result.get("option_id", prompt.get("primary_option_id", "")))
	var option: Dictionary = _interaction_prompt_option(prompt, option_id)
	var target_id: Variant = _interaction_target_id_for_presentation(result, target)
	var target_name := str(prompt.get("target_name", target.get("display_name", ""))).strip_edges()
	if target_name.is_empty():
		target_name = str(target_id).strip_edges()
	return {
		"actor_id": int(result.get("actor_id", _player_actor_id())),
		"target_id": target_id,
		"target_type": str(target.get("target_type", "")),
		"target_name": target_name,
		"target_grid": _interaction_target_grid_for_presentation(target),
		"option_id": str(option.get("id", option_id)),
		"option_kind": str(option.get("kind", result.get("kind", "interact"))),
		"option_name": str(option.get("display_name", "")),
	}


func _interaction_prompt_option(prompt: Dictionary, option_id: String) -> Dictionary:
	for option_value in _array_or_empty(prompt.get("options", [])):
		var option: Dictionary = _dictionary_or_empty(option_value)
		if option_id.is_empty() or str(option.get("id", "")) == option_id:
			return option.duplicate(true)
	return {}


func _interaction_target_id_for_presentation(result: Dictionary, target: Dictionary) -> Variant:
	if result.has("target_id"):
		return result.get("target_id")
	if target.has("target_id"):
		return target.get("target_id")
	if target.has("actor_id"):
		return target.get("actor_id")
	return ""


func _interaction_target_grid_for_presentation(target: Dictionary) -> Dictionary:
	for key in ["grid_position", "anchor", "grid"]:
		var grid: Dictionary = _dictionary_or_empty(target.get(key, {}))
		if not grid.is_empty():
			return grid.duplicate(true)
	var cells: Array = _array_or_empty(target.get("cells", []))
	if not cells.is_empty():
		return _dictionary_or_empty(cells[0]).duplicate(true)
	return {}


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
		return false
	if bool(refresh.get("sync_observed_level", false)):
		runtime_view_state_controller.call("sync_observed_level_to_map", world_result)
	_apply_runtime_scene_refresh(bool(refresh.get("render_world", true)))
	var completion: Dictionary = _dictionary_or_empty(world_action_flow_controller.call("complete_final_refresh", pending_refresh, refresh, trigger))
	if bool(completion.get("refresh_all_panels", false)):
		refresh_all_panels(_dictionary_or_empty(completion.get("prompt", {})))
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
	world_action_flow_controller.call("present_result", self, _world_container_node(), command_result, world_result)


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
	return _dictionary_or_empty(player_command_coordinator.call("player_command_rejection", action))


func _observe_command_rejected(action: String) -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("observe_command_rejected", action))


func _action_presenter_command_rejected(action: String) -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("action_presenter_command_rejected", action))


func _ui_modal_command_rejected(action: String, modal_name: String) -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("ui_modal_command_rejected", action, modal_name))


func _record_container_feedback(result: Dictionary, action: String, container_id: String, item_id: String, count: int) -> void:
	ui_feedback_state_controller.call("record_container_feedback", result, action, container_id, item_id, count)


func _record_trade_feedback(result: Dictionary, action: String, shop_id: String, item_id: String, count: int) -> void:
	ui_feedback_state_controller.call("record_trade_feedback", result, action, shop_id, item_id, count)


func _record_inventory_feedback(result: Dictionary, action: String, item_id: String, count: int) -> void:
	ui_feedback_state_controller.call("record_inventory_feedback", result, action, item_id, count)


func _record_character_feedback(result: Dictionary, action: String, slot_id: String, item_id: String) -> void:
	ui_feedback_state_controller.call("record_character_feedback", result, action, slot_id, item_id)


func _dialogue_trade_target(result: Dictionary = {}) -> Dictionary:
	return _dictionary_or_empty(runtime_session_context_controller.call("dialogue_trade_target", result, active_trade_target))


func _active_trade_target_available() -> bool:
	return bool(runtime_session_context_controller.call("active_trade_target_available", registry, simulation, active_trade_target))


func _current_dialogue_snapshot() -> Dictionary:
	if simulation == null:
		return {}
	var DialogueSnapshot = preload("res://scripts/ui/snapshots/dialogue_snapshot.gd")
	return DialogueSnapshot.new(registry).build(simulation.snapshot())


func _active_shop_id() -> String:
	return str(runtime_session_context_controller.call("active_shop_id", registry, simulation, active_trade_target))


func _trade_closed_payload(target: Dictionary, reason: String) -> Dictionary:
	return _dictionary_or_empty(runtime_session_context_controller.call("trade_closed_payload", registry, simulation, target, reason))


func _active_container_id() -> String:
	return str(runtime_session_context_controller.call("active_container_id", simulation))


func _active_container_close_reason() -> String:
	return str(runtime_session_context_controller.call("active_container_close_reason", simulation))


func _clear_focus_switch_ui_state() -> void:
	if runtime_input_controller != null and runtime_input_controller.has_method("clear_selection_state"):
		runtime_input_controller.clear_selection_state("focus_switch")
	if interaction_controller != null:
		interaction_action_controller.call("clear_selection", interaction_controller, "focus_switch", false)
	_close_hud_interaction_menu()


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
