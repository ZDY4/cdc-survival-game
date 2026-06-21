extends Node3D

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const DebugRuntimeController = preload("res://scripts/app/controllers/debug_runtime_controller.gd")
const GameInputRouter = preload("res://scripts/app/controllers/game_input_router.gd")
const RuntimeBootController = preload("res://scripts/app/controllers/runtime_boot_controller.gd")
const RuntimeRefreshController = preload("res://scripts/app/controllers/runtime_refresh_controller.gd")
const RuntimePerformanceTracker = preload("res://scripts/app/controllers/runtime_performance_tracker.gd")
const RuntimeControlStateController = preload("res://scripts/app/controllers/runtime_control_state_controller.gd")
const RuntimeViewStateController = preload("res://scripts/app/controllers/runtime_view_state_controller.gd")
const RuntimeSessionContextController = preload("res://scripts/app/controllers/runtime_session_context_controller.gd")
const RuntimeSceneCoordinator = preload("res://scripts/app/controllers/runtime_scene_coordinator.gd")
const RuntimeViewCoordinator = preload("res://scripts/app/controllers/runtime_view_coordinator.gd")
const GameUiCoordinator = preload("res://scripts/app/controllers/game_ui_coordinator.gd")
const RuntimeDebugCoordinator = preload("res://scripts/app/controllers/runtime_debug_coordinator.gd")
const PlayerCommandCoordinator = preload("res://scripts/app/controllers/player_command_coordinator.gd")
const PlayerUiActionCoordinator = preload("res://scripts/app/controllers/player_ui_action_coordinator.gd")
const CraftingQueueCoordinator = preload("res://scripts/app/controllers/crafting_queue_coordinator.gd")
const InteractionWorldActionCoordinator = preload("res://scripts/app/controllers/interaction_world_action_coordinator.gd")
const PlayerInteractionUiCoordinator = preload("res://scripts/app/controllers/player_interaction_ui_coordinator.gd")
const RuntimeAudioCoordinator = preload("res://scripts/app/controllers/runtime_audio_coordinator.gd")
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
var runtime_view_coordinator: RefCounted = RuntimeViewCoordinator.new()
var game_ui_coordinator: RefCounted = GameUiCoordinator.new()
var runtime_debug_coordinator: RefCounted = RuntimeDebugCoordinator.new()
var player_command_coordinator: RefCounted = PlayerCommandCoordinator.new()
var player_ui_action_coordinator: RefCounted = PlayerUiActionCoordinator.new()
var crafting_queue_coordinator: RefCounted = CraftingQueueCoordinator.new()
var interaction_world_action_coordinator: RefCounted = InteractionWorldActionCoordinator.new()
var player_interaction_ui_coordinator: RefCounted = PlayerInteractionUiCoordinator.new()
var runtime_audio_coordinator: RefCounted = RuntimeAudioCoordinator.new()
var turn_action_runner: RefCounted = TurnActionRunner.new()
var actor_view_controller: RefCounted = ActorViewController.new()
var latest_structural_refresh_boundary: Dictionary = {}

func _ready() -> void:
	runtime_scene_coordinator.call("configure", self)
	runtime_view_coordinator.call("configure", self)
	game_ui_coordinator.call("configure", self)
	runtime_debug_coordinator.call("configure", self)
	player_command_coordinator.call("configure", self)
	player_ui_action_coordinator.call("configure", self)
	crafting_queue_coordinator.call("configure", self)
	interaction_world_action_coordinator.call("configure", self)
	player_interaction_ui_coordinator.call("configure", self)
	runtime_audio_coordinator.call("configure", self)
	interaction_world_action_coordinator.call("connect_world_action_flow_signals")
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
	if not bool(runtime_scene_coordinator.call("accept_runtime_refresh_result", startup_refresh, "world build failed")):
		return

	interaction_controller = PlayerInteractionController.new(registry, simulation, world_result)
	runtime_scene_coordinator.call("apply_existing_runtime_world_result", world_result, "startup_interaction_sync", "world build failed")
	var counts: Dictionary = _dictionary_or_empty(runtime_scene_coordinator.call("apply_world_root_snapshot", true))
	runtime_scene_coordinator.call("refresh_world_runtime_bindings")
	runtime_audio_coordinator.call("setup_audio_feedback_controller")
	runtime_audio_coordinator.call("configure_runtime_audio_layers")
	game_ui_coordinator.call("setup_panels")
	game_ui_coordinator.call("setup_tooltip_layer")
	game_ui_coordinator.call("setup_drag_preview_layer")
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
	interaction_world_action_coordinator.call("process_world_action_queue_completion")
	game_ui_coordinator.call("update_tooltip_layer")
	player_command_coordinator.call("process_auto_tick", delta)

func _input(event: InputEvent) -> void:
	game_input_router.input(self, runtime_input_controller, event)

func _unhandled_input(event: InputEvent) -> void:
	game_input_router.unhandled_input(self, runtime_input_controller, event)

func refresh_hud(selected_prompt: Dictionary = {}) -> void:
	game_ui_coordinator.call("refresh_hud", selected_prompt)

func refresh_dialogue_panel() -> void:
	game_ui_coordinator.call("refresh_panel", "dialogue")

func refresh_inventory_panel() -> void:
	game_ui_coordinator.call("refresh_panel", "inventory", game_ui_coordinator.call("ui_feedback_payload"))

func refresh_trade_panel() -> void:
	game_ui_coordinator.call("refresh_trade_panel")

func refresh_container_panel() -> void:
	game_ui_coordinator.call("refresh_container_panel")

func refresh_character_panel() -> void:
	game_ui_coordinator.call("refresh_panel", "character", game_ui_coordinator.call("ui_feedback_payload"))

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

func show_interaction_menu(screen_position: Vector2, prompt: Dictionary = {}) -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("show_interaction_menu", screen_position, prompt))

func hide_interaction_menu() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("hide_interaction_menu"))

func is_interaction_menu_open() -> bool:
	return bool(game_ui_coordinator.call("is_interaction_menu_open"))

func modal_stack_snapshot() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("modal_stack_snapshot"))

func menu_state_snapshot() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("menu_state_snapshot"))

func ui_theme_snapshot() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("ui_theme_snapshot"))

func context_menu_snapshot() -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("context_menu_snapshot"))

func hover_tooltip_snapshot(control: Control = null) -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("hover_tooltip_snapshot", control))

func hotbar_hit_test_snapshot(screen_position: Vector2 = Vector2(-1.0, -1.0)) -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("hotbar_hit_test_snapshot", screen_position))

func drag_state_snapshot(data: Variant = {}, hover_target: Control = null) -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("drag_state_snapshot", data, hover_target))

func ui_layer_stack_snapshot(drag_data: Variant = {}, drag_hover_target: Control = null, tooltip_control: Control = null) -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("ui_layer_stack_snapshot", drag_data, drag_hover_target, tooltip_control))

func render_tooltip_snapshot(snapshot: Dictionary) -> void:
	game_ui_coordinator.call("render_tooltip_snapshot", snapshot)

func render_drag_preview_for_snapshot(drag_data: Variant = {}, hover_target: Control = null) -> Dictionary:
	return _dictionary_or_empty(game_ui_coordinator.call("render_drag_preview_for_snapshot", drag_data, hover_target))

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

func current_info_panel_page() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("current_info_panel_page"))

func info_panel_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("info_panel_snapshot"))

func runtime_control_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("runtime_control_snapshot"))

func runtime_hud_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("runtime_hud_snapshot"))

func tooltip_render_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("tooltip_render_snapshot"))

func drag_preview_render_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("drag_preview_render_snapshot"))

func player_command_authority_audit_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("player_command_authority_audit_snapshot"))

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
	return _dictionary_or_empty(runtime_audio_coordinator.call("play_ui_audio_feedback", event_kind, payload))

func play_spatial_audio_feedback(event_kind: String, payload: Dictionary = {}, position: Vector3 = Vector3.ZERO) -> Dictionary:
	return _dictionary_or_empty(runtime_audio_coordinator.call("play_spatial_audio_feedback", event_kind, payload, position))

func finish_world_action_presentations() -> Dictionary:
	return _dictionary_or_empty(interaction_world_action_coordinator.call("finish_world_action_presentations"))

func runtime_performance_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("runtime_performance_snapshot"))

func runtime_hover_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("runtime_hover_snapshot"))

func runtime_selection_debug_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_debug_coordinator.call("runtime_selection_debug_snapshot"))

func _update_runtime_performance(delta: float) -> void:
	runtime_debug_coordinator.call("update_runtime_performance", delta)

func settings_applied(snapshot: Dictionary = {}) -> void:
	runtime_audio_coordinator.call("settings_applied", snapshot)

func current_map_level() -> int:
	return int(runtime_view_coordinator.call("current_map_level"))

func map_level_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_view_coordinator.call("map_level_snapshot"))

func change_observed_level(direction: int) -> Dictionary:
	return _dictionary_or_empty(runtime_view_coordinator.call("change_observed_level", direction))

func cycle_focused_actor() -> Dictionary:
	return _dictionary_or_empty(runtime_view_coordinator.call("cycle_focused_actor"))

func focus_actor(actor_id: int) -> Dictionary:
	return _dictionary_or_empty(runtime_view_coordinator.call("focus_actor", actor_id))

func focused_actor_snapshot() -> Dictionary:
	return _dictionary_or_empty(runtime_view_coordinator.call("focused_actor_snapshot"))

func focused_actor_grid_position() -> Dictionary:
	return _dictionary_or_empty(runtime_view_coordinator.call("focused_actor_grid_position"))

func focused_actor_visual_position() -> Variant:
	var node := focused_actor_node_for_camera_follow()
	if node != null:
		return node.global_position
	return null

func focused_actor_node_for_camera_follow() -> Node3D:
	return runtime_view_coordinator.call("focused_actor_node_for_camera_follow") as Node3D

func close_active_dialogue(reason: String = "closed") -> Dictionary:
	return _dictionary_or_empty(player_interaction_ui_coordinator.call("close_active_dialogue", reason))

func close_active_container(reason: String = "closed") -> Dictionary:
	return _dictionary_or_empty(player_interaction_ui_coordinator.call("close_active_container", reason))

func close_active_ui(reason: String = "closed") -> Dictionary:
	return _dictionary_or_empty(player_interaction_ui_coordinator.call("close_active_ui", reason))

func close_active_context_menu() -> Dictionary:
	return _dictionary_or_empty(player_interaction_ui_coordinator.call("close_active_context_menu"))

func select_interaction_target(target: Dictionary) -> Dictionary:
	return _dictionary_or_empty(player_interaction_ui_coordinator.call("select_interaction_target", target))

func select_interaction_node(node: Node) -> Dictionary:
	return _dictionary_or_empty(player_interaction_ui_coordinator.call("select_interaction_node", node))

func clear_interaction_selection(reason: String = "cleared") -> Dictionary:
	return _dictionary_or_empty(player_interaction_ui_coordinator.call("clear_interaction_selection", reason))

func execute_primary_interaction() -> Dictionary:
	return _dictionary_or_empty(player_interaction_ui_coordinator.call("execute_primary_interaction"))

func execute_interaction_option(option_id: String) -> Dictionary:
	return _dictionary_or_empty(player_interaction_ui_coordinator.call("execute_interaction_option", option_id))

func select_grid_target(grid: Dictionary) -> Dictionary:
	return _dictionary_or_empty(player_interaction_ui_coordinator.call("select_grid_target", grid))

func execute_move_to_grid(grid: Dictionary) -> Dictionary:
	return _dictionary_or_empty(player_interaction_ui_coordinator.call("execute_move_to_grid", grid))

func request_player_move(grid: Dictionary) -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("request_player_move", grid))

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

func has_active_dialogue() -> bool:
	return bool(player_ui_action_coordinator.call("has_active_dialogue"))

func press_space_action() -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("press_space_action"))

func repeat_space_wait_action() -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("repeat_space_wait_action"))

func submit_wait_action() -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("submit_wait_action"))

func _submit_auto_tick_wait() -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("submit_auto_tick_wait"))

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

func equip_player_item(item_id: String, slot_id: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("equip_player_item", item_id, slot_id))

func unequip_player_slot(slot_id: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("unequip_player_slot", slot_id))

func reload_player_equipped_slot(slot_id: String = "main_hand") -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("reload_player_equipped_slot", slot_id))

func allocate_player_attribute_point(attribute: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("allocate_player_attribute_point", attribute))

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

func update_crafting_queue(entries: Array) -> Dictionary:
	return _dictionary_or_empty(crafting_queue_coordinator.call("update_crafting_queue", entries))

func crafting_queue_snapshot() -> Dictionary:
	return _dictionary_or_empty(crafting_queue_coordinator.call("crafting_queue_snapshot"))

func cancel_pending_crafting(reason: String = "crafting_ui") -> Dictionary:
	return _dictionary_or_empty(crafting_queue_coordinator.call("cancel_pending_crafting", reason))

func _crafting_context() -> Dictionary:
	return _dictionary_or_empty(crafting_queue_coordinator.call("crafting_context"))

func crafting_context() -> Dictionary:
	return _dictionary_or_empty(crafting_queue_coordinator.call("crafting_context"))

func turn_in_player_quest(quest_id: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("turn_in_player_quest", quest_id))

func enter_overworld_location_from_panel(location_id: String) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("enter_overworld_location_from_panel", location_id))

func _apply_player_action_refresh_operation(operation: Dictionary, selected_prompt: Dictionary = {}, rebuild_command_result: Dictionary = {}, rebuild_selected_prompt: Variant = null) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("apply_player_action_refresh_operation", operation, selected_prompt, rebuild_command_result, rebuild_selected_prompt))

func refresh_world_visuals(render_world: bool = true) -> Dictionary:
	return _dictionary_or_empty(runtime_scene_coordinator.call("refresh_world_visuals", render_world))

func rebuild_runtime_world(selected_prompt: Dictionary = {}, command_result: Dictionary = {}) -> void:
	runtime_scene_coordinator.call("rebuild_world_after_runtime_change", selected_prompt, command_result)

func _submit_inventory_action(action: Dictionary) -> Dictionary:
	return _dictionary_or_empty(player_ui_action_coordinator.call("submit_inventory_action", action))

func _player_command_rejection(action: String) -> Dictionary:
	return _dictionary_or_empty(player_command_coordinator.call("player_command_rejection", action))

func _current_dialogue_snapshot() -> Dictionary:
	if simulation == null:
		return {}
	var DialogueSnapshot = preload("res://scripts/ui/snapshots/dialogue_snapshot.gd")
	return DialogueSnapshot.new(registry).build(simulation.snapshot())

func _trade_closed_payload(target: Dictionary, reason: String) -> Dictionary:
	return _dictionary_or_empty(runtime_session_context_controller.call("trade_closed_payload", registry, simulation, target, reason))

func _active_container_id() -> String:
	return str(runtime_session_context_controller.call("active_container_id", simulation))

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
