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
const CRAFTING_QUEUE_ADVANCE_LIMIT := 16

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
var turn_action_runner: RefCounted = TurnActionRunner.new()
var actor_view_controller: RefCounted = ActorViewController.new()
var latest_structural_refresh_boundary: Dictionary = {}

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
	hud_root.refresh_operation_panels(panel_ids, selected_prompt, _ui_feedback_payload())


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


func toggle_settings_panel() -> Dictionary:
	if hud_root == null:
		return {"success": false, "reason": "panel_controller_missing"}
	if _world_action_presenter_blocks_input():
		return _action_presenter_command_rejected("toggle_settings_panel")
	var opened := not is_settings_open()
	var result: Dictionary = {}
	if opened:
		result = _dictionary_or_empty(hud_root.open_settings_panel())
		if bool(result.get("success", false)):
			_play_ui_audio_feedback("settings_panel_opened", {
				"panel_id": "settings",
				"action": "open_settings_panel",
			})
	else:
		result = _dictionary_or_empty(hud_root.close_settings_panel())
		if bool(result.get("success", false)):
			_play_ui_audio_feedback("settings_panel_closed", {
				"panel_id": "settings",
				"action": "close_settings_panel",
			})
	if bool(result.get("success", false)):
		result["open"] = opened
		refresh_all_panels(current_interaction_prompt())
	return result


func gameplay_input_blocked_by_ui() -> bool:
	var hud_blocker := _hud_input_blocker_snapshot()
	var panel_blocked: bool = hud_root != null and hud_root.gameplay_input_blocked()
	return bool(ui_blocker_state_controller.call("gameplay_input_blocked", hud_blocker, panel_blocked, _world_action_presenter_blocks_input()))


func gameplay_input_blocker_name() -> String:
	var hud_blocker := _hud_input_blocker_snapshot()
	var context_menu: Dictionary = context_menu_snapshot()
	var panel_blocker_name: String = hud_root.gameplay_input_blocker_name() if hud_root != null else ""
	return str(ui_blocker_state_controller.call("blocker_name", hud_blocker, _panel_modal_blocker_snapshot(), context_menu, _world_action_blocker_snapshot(), panel_blocker_name))


func gameplay_input_blocker_snapshot() -> Dictionary:
	var hud_blocker := _hud_input_blocker_snapshot()
	var context_menu: Dictionary = context_menu_snapshot()
	var world_blocks := _world_action_presenter_blocks_input()
	var panel_blocker: Dictionary = _panel_input_blocker_snapshot()
	var fallback_name := gameplay_input_blocker_name()
	return _dictionary_or_empty(ui_blocker_state_controller.call("blocker_snapshot", hud_blocker, _panel_modal_blocker_snapshot(), context_menu, world_action_presenter_snapshot(), _world_action_blocker_snapshot(), world_blocks, panel_blocker, fallback_name))


func _hud_input_blocker_snapshot() -> Dictionary:
	if hud_root != null:
		return _dictionary_or_empty(hud_root.hud_input_blocker_snapshot(is_debug_console_open()))
	return {}


func _close_hud_interaction_menu() -> bool:
	var hud_blocker := _hud_input_blocker_snapshot()
	if str(hud_blocker.get("name", "")) != "interaction_menu":
		return false
	return hud_root != null and hud_root.close_hud_interaction_menu()


func show_interaction_menu(screen_position: Vector2, prompt: Dictionary = {}) -> Dictionary:
	if hud_root == null:
		return {"success": false, "reason": "hud_root_missing", "visible": false}
	return _dictionary_or_empty(hud_root.show_interaction_menu(screen_position, prompt))


func hide_interaction_menu() -> Dictionary:
	if hud_root == null:
		return {"success": false, "reason": "hud_root_missing", "visible": false}
	return _dictionary_or_empty(hud_root.hide_interaction_menu())


func is_interaction_menu_open() -> bool:
	return hud_root != null and hud_root.is_interaction_menu_open()


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
	var presenter_blocks := world_action_flow_controller != null and bool(world_action_flow_controller.call("blocks_input"))
	var runner: Dictionary = turn_action_runner_snapshot()
	return presenter_blocks or bool(runner.get("active", false)) or bool(runner.get("presentation_active", false))


func _world_action_blocker_snapshot() -> Dictionary:
	var presenter: Dictionary = world_action_presenter_snapshot()
	if world_action_flow_controller != null and bool(world_action_flow_controller.call("blocks_input")):
		return {
			"blocked": true,
			"name": "world_action_presenter",
			"kind": "world_action_presenter",
			"source": "world_action_presenter",
			"action_kind": str(presenter.get("kind", "")),
			"phase": str(presenter.get("current_phase", presenter.get("state", ""))),
			"active_count": int(presenter.get("active_count", 0)),
			"sequence": int(presenter.get("sequence", 0)),
			"mouse_blocks_world": true,
			"camera_drag_allowed": true,
		}
	var runner: Dictionary = turn_action_runner_snapshot()
	if bool(runner.get("active", false)) or bool(runner.get("presentation_active", false)):
		return {
			"blocked": true,
			"name": "turn_action_runner",
			"kind": "turn_action_runner",
			"source": "turn_action_runner",
			"action_kind": str(runner.get("action_kind", "")),
			"phase": str(runner.get("phase", "")),
			"turn_phase": str(runner.get("turn_phase", "")),
			"actor_id": int(runner.get("actor_id", 0)),
			"presentation_active": bool(runner.get("presentation_active", false)),
			"mouse_blocks_world": true,
			"camera_drag_allowed": true,
		}
	return {}


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
		"world_action_blocker": _world_action_blocker_snapshot(),
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


func clear_debug_console_history() -> Dictionary:
	if hud_root == null:
		return {"success": false, "reason": "hud_root_missing"}
	return _dictionary_or_empty(hud_root.clear_debug_console_history())


func reset_debug_view_state() -> void:
	active_trade_target = {}
	active_trade_feedback = {}
	active_container_feedback = {}
	active_character_feedback = {}
	active_inventory_feedback = {}
	active_skill_targeting = {}
	active_skill_target_preview = {}
	if runtime_view_state_controller != null:
		runtime_view_state_controller.focused_actor_id = 0
		runtime_view_state_controller.observed_map_level = 0
	if runtime_control_state_controller != null:
		runtime_control_state_controller.auto_tick_enabled = false
		runtime_control_state_controller.auto_tick_elapsed_sec = 0.0


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
	var result: Dictionary = _dictionary_or_empty(debug_runtime_controller.execute(self, command))
	return _apply_debug_console_intent(result)


func _apply_debug_console_intent(result: Dictionary) -> Dictionary:
	var intent := str(result.get("debug_intent", ""))
	if intent.is_empty():
		return result
	var output := result.duplicate(true)
	output.erase("debug_intent")
	match intent:
		"toggle_fps_panel":
			if not has_method("toggle_debug_panel"):
				return {"success": false, "reason": "debug_panel_missing", "message": "debug panel missing"}
			var panel_result: Dictionary = toggle_debug_panel()
			return _merge_debug_console_intent_result(output, panel_result, "fps panel=%s" % ("on" if bool(panel_result.get("visible", false)) else "off"))
		"cycle_debug_overlay":
			if not has_method("cycle_debug_overlay_mode"):
				return {"success": false, "reason": "debug_overlay_missing", "message": "debug overlay missing"}
			var overlay_result: Dictionary = cycle_debug_overlay_mode()
			return _merge_debug_console_intent_result(output, overlay_result, "overlay=%s" % str(overlay_result.get("mode", "")))
		"toggle_observe_mode":
			if not has_method("toggle_observe_mode"):
				return {"success": false, "reason": "observe_mode_missing", "message": "observe mode missing"}
			var observe_result: Dictionary = toggle_observe_mode()
			var observe_mode := bool(observe_result.get("observe_mode", false))
			return _merge_debug_console_intent_result(output, observe_result, "observe=%s" % ("on" if observe_mode else "off"))
		"clear_console":
			if not has_method("clear_debug_console_history"):
				return {"success": false, "reason": "debug_console_missing", "message": "debug console missing"}
			var clear_result: Dictionary = clear_debug_console_history()
			return _merge_debug_console_intent_result(output, clear_result, "console cleared" if bool(clear_result.get("success", false)) else "debug console missing")
	return {"success": false, "reason": "unknown_debug_intent", "debug_intent": intent, "message": "unknown debug intent: %s" % intent}


func _merge_debug_console_intent_result(base_result: Dictionary, action_result: Dictionary, message: String) -> Dictionary:
	var output := base_result.duplicate(true)
	for key in action_result.keys():
		output[key] = action_result[key]
	output["success"] = bool(action_result.get("success", output.get("success", false)))
	output["message"] = message
	return output


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
	refresh_world_visuals(false)
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
	return _apply_runtime_control_result(result)


func is_auto_tick_enabled() -> bool:
	return bool(runtime_control_state_controller.auto_tick_enabled) if runtime_control_state_controller != null else false


func is_observe_mode_enabled() -> bool:
	return bool(runtime_control_state_controller.observe_mode_enabled) if runtime_control_state_controller != null else false


func can_issue_player_commands() -> bool:
	return not is_observe_mode_enabled() and not _world_action_presenter_blocks_input() and _panel_modal_blocker_name().is_empty()


func toggle_observe_mode() -> Dictionary:
	return set_observe_mode(not is_observe_mode_enabled())


func set_observe_mode(enabled: bool) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(runtime_control_state_controller.call("set_observe_mode", enabled, gameplay_input_blocked_by_ui()))
	return _apply_runtime_control_result(result)


func toggle_observe_playback() -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(runtime_control_state_controller.call("toggle_observe_playback", has_active_dialogue() or gameplay_input_blocked_by_ui()))
	return _apply_runtime_control_result(result)


func cycle_observe_speed() -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(runtime_control_state_controller.call("cycle_observe_speed"))
	return _apply_runtime_control_result(result)


func set_observe_speed(speed_id: String) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(runtime_control_state_controller.call("set_observe_speed", speed_id))
	return _apply_runtime_control_result(result)


func cycle_info_panel(direction: int) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(runtime_control_state_controller.call("cycle_info_panel", direction))
	return _apply_runtime_control_result(result)


func _apply_runtime_control_result(result: Dictionary) -> Dictionary:
	if not bool(result.get("success", false)):
		return result
	if bool(result.get("refresh_hud", false)):
		refresh_hud(current_interaction_prompt())
	var audio: Dictionary = _dictionary_or_empty(result.get("hud_audio", {}))
	if not audio.is_empty():
		_play_hud_shortcut_audio(
			str(audio.get("event_kind", "")),
			str(audio.get("control_name", "")),
			str(audio.get("control_kind", "")),
			str(audio.get("action", "")),
			_dictionary_or_empty(audio.get("payload", {}))
		)
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
	snapshot["turn_action_runner"] = turn_action_runner_snapshot()
	snapshot["latest_action_chain"] = latest_action_chain.duplicate(true)
	snapshot["actor_view"] = actor_view_snapshot()
	snapshot["camera_follow"] = camera_follow_snapshot()
	snapshot["world_render_policy"] = world_render_policy_snapshot()
	snapshot["structural_refresh_boundary"] = structural_refresh_boundary_snapshot()
	snapshot["ai_debug"] = ai_debug_snapshot()
	snapshot["debug_overlay"] = debug_overlay_snapshot()
	snapshot["runtime_refresh"] = runtime_refresh_report_snapshot()
	snapshot["audio_feedback"] = audio_feedback_snapshot()
	snapshot["performance"] = runtime_performance_snapshot()
	snapshot["skill_targeting"] = active_skill_targeting_snapshot()
	snapshot["player_command_authority_audit"] = player_command_authority_audit_snapshot()
	return snapshot


func tooltip_render_snapshot() -> Dictionary:
	var controller := _ui_overlay_controller()
	if controller == null:
		return {"active": false}
	return _dictionary_or_empty(controller.call("tooltip_render_snapshot"))


func drag_preview_render_snapshot() -> Dictionary:
	var controller := _ui_overlay_controller()
	if controller == null:
		return {"active": false}
	return _dictionary_or_empty(controller.call("drag_preview_render_snapshot"))


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


func turn_action_runner_snapshot() -> Dictionary:
	if turn_action_runner == null or not turn_action_runner.has_method("snapshot"):
		return {"active": false, "phase": "missing"}
	return _dictionary_or_empty(turn_action_runner.call("snapshot"))


func drain_turn_action_runner(max_steps: int = 240) -> Dictionary:
	if turn_action_runner == null or not turn_action_runner.has_method("snapshot"):
		return {"active": false, "phase": "missing", "drained": false}
	var steps := 0
	var runner: Dictionary = turn_action_runner_snapshot()
	while steps < max_steps and bool(runner.get("active", false)):
		steps += 1
		if bool(runner.get("presentation_active", false)) and actor_view_controller != null and actor_view_controller.has_method("finish_active_actor_presentation"):
			actor_view_controller.call("finish_active_actor_presentation", int(runner.get("presenting_npc_actor_id", runner.get("actor_id", 0))))
		if turn_action_runner.has_method("process"):
			turn_action_runner.call("process")
		runner = turn_action_runner_snapshot()
	runner["drained"] = not bool(runner.get("active", false))
	runner["drain_steps"] = steps
	runner["drain_limit"] = max_steps
	return runner


func settle_turn_action_runner_boundary(reason: String = "stable_boundary", max_steps: int = 8) -> Dictionary:
	if turn_action_runner == null or not turn_action_runner.has_method("snapshot"):
		return {"active": false, "phase": "missing", "settled": false}
	var before: Dictionary = turn_action_runner_snapshot()
	if bool(before.get("active", false)) or bool(before.get("presentation_active", false)):
		if turn_action_runner.has_method("settle_stable_boundary"):
			var settled: Dictionary = _dictionary_or_empty(turn_action_runner.call("settle_stable_boundary", reason))
			settled["before"] = before.duplicate(true)
			settled["settle_steps"] = 1
			settled["settle_limit"] = max_steps
			settled["settled"] = not bool(settled.get("active", false)) and not bool(settled.get("presentation_active", false))
			return settled
	var steps := 0
	var runner: Dictionary = before.duplicate(true)
	while steps < max_steps and (bool(runner.get("active", false)) or bool(runner.get("presentation_active", false))):
		steps += 1
		if bool(runner.get("presentation_active", false)) and actor_view_controller != null and actor_view_controller.has_method("finish_active_actor_presentation"):
			actor_view_controller.call("finish_active_actor_presentation", int(runner.get("presenting_npc_actor_id", runner.get("actor_id", 0))))
		if turn_action_runner.has_method("process"):
			turn_action_runner.call("process")
		runner = turn_action_runner_snapshot()
		if str(runner.get("phase", "")) == "player_turn_end" or str(runner.get("phase", "")) == "pending_resume":
			break
		if bool(runner.get("active", false)) and not bool(runner.get("presentation_active", false)) and not str(runner.get("pending_kind", "")).is_empty():
			break
	runner["settled"] = not bool(runner.get("presentation_active", false))
	runner["settle_steps"] = steps
	runner["settle_limit"] = max_steps
	runner["reason"] = reason
	runner["before"] = before.duplicate(true)
	return runner


func prepare_runtime_save_boundary(reason: String = "save_boundary") -> Dictionary:
	var before_runner: Dictionary = turn_action_runner_snapshot()
	var before_policy: Dictionary = world_render_policy_snapshot()
	var drain_result: Dictionary = {}
	if bool(before_runner.get("active", false)) or bool(before_runner.get("presentation_active", false)):
		drain_result = drain_turn_action_runner()
		drain_result["reason"] = reason
		refresh_hud(current_interaction_prompt())
	var after_runner: Dictionary = turn_action_runner_snapshot()
	var after_policy: Dictionary = world_render_policy_snapshot()
	var stable := not bool(after_runner.get("active", false)) and not bool(after_runner.get("presentation_active", false))
	var structural_allowed := bool(after_policy.get("structural_render_allowed", false))
	return {
		"success": stable and structural_allowed,
		"reason": reason if stable and structural_allowed else "save_boundary_unstable",
		"stable": stable,
		"save_allowed": stable and structural_allowed,
		"drained_turn_action_runner": not drain_result.is_empty() and bool(drain_result.get("drained", false)),
		"drain_result": drain_result.duplicate(true),
		"before_runner": before_runner.duplicate(true),
		"after_runner": after_runner.duplicate(true),
		"before_policy": before_policy.duplicate(true),
		"after_policy": after_policy.duplicate(true),
	}


func actor_view_snapshot() -> Dictionary:
	if actor_view_controller == null or not actor_view_controller.has_method("snapshot"):
		return {"active": false}
	return _dictionary_or_empty(actor_view_controller.call("snapshot"))


func camera_follow_snapshot() -> Dictionary:
	var input_snapshot: Dictionary = {}
	if runtime_input_controller != null and runtime_input_controller.has_method("camera_follow_snapshot"):
		input_snapshot = _dictionary_or_empty(runtime_input_controller.call("camera_follow_snapshot"))
	else:
		input_snapshot = {"has_camera": false, "reason": "runtime_input_missing"}
	var world_snapshot: Dictionary = {}
	if world_root != null and world_root.has_method("camera_follow_snapshot"):
		world_snapshot = _dictionary_or_empty(world_root.call("camera_follow_snapshot"))
	var output: Dictionary = input_snapshot.duplicate(true)
	output["input_controller"] = input_snapshot.duplicate(true)
	output["world_camera"] = world_snapshot.duplicate(true)
	if not world_snapshot.is_empty():
		output["has_world_camera"] = bool(world_snapshot.get("has_camera", false))
		output["world_follow_source"] = str(world_snapshot.get("follow_source", ""))
		output["world_follow_actor_id"] = int(world_snapshot.get("follow_actor_id", 0))
		output["world_follow_node_active"] = bool(world_snapshot.get("follow_node_active", false))
		output["world_follow_node_instance_id"] = int(world_snapshot.get("follow_node_instance_id", 0))
	return output


func world_render_policy_snapshot() -> Dictionary:
	var runner: Dictionary = turn_action_runner_snapshot()
	var queue: Dictionary = world_action_queue_snapshot()
	var performance: Dictionary = runtime_performance_snapshot()
	var runner_active := bool(runner.get("active", false)) or bool(runner.get("presentation_active", false))
	var queue_active := bool(queue.get("active", false))
	return {
		"render_sequence": int(performance.get("render_sequence", 0)),
		"last_render_count": int(performance.get("render_count", 0)),
		"last_render_counts": _dictionary_or_empty(performance.get("render_counts", {})).duplicate(true),
		"runner_active": runner_active,
		"runner_action_kind": str(runner.get("action_kind", "")),
		"runner_phase": str(runner.get("phase", "")),
		"world_action_queue_active": queue_active,
		"ordinary_action_render_world": false,
		"structural_render_allowed": not runner_active,
		"policy": "runner_actions_update_actor_view_without_full_world_render" if runner_active else "idle_structural_refresh_allowed",
	}


func audio_feedback_snapshot() -> Dictionary:
	if audio_feedback_controller == null or not audio_feedback_controller.has_method("snapshot"):
		return {"enabled": false, "reason": "audio_feedback_missing"}
	return _dictionary_or_empty(audio_feedback_controller.call("snapshot"))


func runtime_refresh_report_snapshot() -> Dictionary:
	if runtime_refresh_controller != null and runtime_refresh_controller.has_method("refresh_report_snapshot"):
		return _dictionary_or_empty(runtime_refresh_controller.call("refresh_report_snapshot"))
	return {}


func structural_refresh_boundary_snapshot() -> Dictionary:
	return latest_structural_refresh_boundary.duplicate(true)


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
	_setup_world_container()
	_configure_turn_action_runner()
	if not _runner_allows_move_replacement():
		var blocked: Dictionary = _player_command_rejection("move")
		if not blocked.is_empty():
			return blocked
	var player_id := _player_actor_id()
	var topology: Dictionary = _dictionary_or_empty(world_result.get("map", {}))
	var result: Dictionary = _dictionary_or_empty(turn_action_runner.call("request_move", player_id, grid, topology))
	return result


func _runner_allows_move_replacement() -> bool:
	if is_observe_mode_enabled() or not _panel_modal_blocker_name().is_empty():
		return false
	if world_action_flow_controller != null and bool(world_action_flow_controller.call("blocks_input")):
		return false
	var runner: Dictionary = turn_action_runner_snapshot()
	return (bool(runner.get("active", false)) or bool(runner.get("presentation_active", false))) and str(runner.get("action_kind", "")) == "move"


func request_player_attack(target_actor_id: int, options: Dictionary = {}) -> Dictionary:
	var blocked: Dictionary = _player_command_rejection("attack")
	if not blocked.is_empty():
		return blocked
	_setup_world_container()
	_configure_turn_action_runner()
	var player_id := _player_actor_id()
	var topology: Dictionary = _dictionary_or_empty(world_result.get("map", {}))
	var result: Dictionary = _dictionary_or_empty(turn_action_runner.call("request_attack", player_id, target_actor_id, topology, options))
	if bool(result.get("success", false)):
		_restore_actor_camera_follow("player_attack")
	return result


func request_player_interaction(target: Dictionary, option_id: String = "", options: Dictionary = {}) -> Dictionary:
	var blocked: Dictionary = _player_command_rejection("interact")
	if not blocked.is_empty():
		return blocked
	if target.is_empty():
		return {"success": false, "reason": "interaction_target_not_selected"}
	_setup_world_container()
	_configure_turn_action_runner()
	var player_id := _player_actor_id()
	var topology: Dictionary = _dictionary_or_empty(world_result.get("map", {}))
	var result: Dictionary = _dictionary_or_empty(turn_action_runner.call("request_interact", player_id, target, option_id, topology, options))
	if bool(result.get("success", false)):
		_restore_actor_camera_follow("player_interaction")
	return result


func request_player_wait(options: Dictionary = {}) -> Dictionary:
	var blocked: Dictionary = _player_command_rejection("wait")
	if not blocked.is_empty():
		return blocked
	_setup_world_container()
	_configure_turn_action_runner()
	var player_id := _player_actor_id()
	var topology: Dictionary = _dictionary_or_empty(world_result.get("map", {}))
	var result: Dictionary = _dictionary_or_empty(turn_action_runner.call("request_wait", player_id, topology, options))
	return result


func request_player_craft(command: Dictionary, options: Dictionary = {}) -> Dictionary:
	var blocked: Dictionary = _player_command_rejection("craft")
	if not blocked.is_empty():
		return blocked
	_setup_world_container()
	_configure_turn_action_runner()
	var player_id := _player_actor_id()
	var topology: Dictionary = _dictionary_or_empty(command.get("topology", world_result.get("map", {})))
	return _dictionary_or_empty(turn_action_runner.call("request_craft", player_id, command, topology, options))


func sync_after_turn_action_step(step_result: Dictionary = {}, runner_snapshot: Dictionary = {}) -> Dictionary:
	var crafting_continuation: Dictionary = {}
	if _runner_step_should_continue_crafting_queue(step_result, runner_snapshot):
		crafting_continuation = _continue_crafting_queue_after_wait(step_result, runner_snapshot)
	var interaction_result: Dictionary = _runner_interaction_result(step_result, runner_snapshot)
	if not interaction_result.is_empty():
		_apply_world_root_snapshot(false)
		_configure_turn_action_runner()
		_configure_runtime_audio_layers()
		if bool(crafting_continuation.get("continued", false)):
			_refresh_operation_panels(_array_or_empty(crafting_continuation.get("refresh", [])))
		_apply_interaction_execution_result(interaction_result, _dictionary_or_empty(runner_snapshot.get("target", {})))
		return {
			"success": true,
			"render_world": true,
			"world_result_synced": false,
			"world_result_deferred": true,
			"step_result": step_result.duplicate(true),
			"turn_action_runner": runner_snapshot.duplicate(true),
		}
	var needs_world_result_sync := _turn_action_step_needs_world_result_sync(step_result, runner_snapshot, interaction_result, crafting_continuation)
	if needs_world_result_sync and not _rebuild_runtime_world_result("turn_action_runner_step"):
		return {"success": false, "reason": "world_result_sync_failed"}
	_apply_world_root_snapshot(false)
	_configure_turn_action_runner()
	_configure_runtime_audio_layers()
	if bool(crafting_continuation.get("continued", false)):
		_refresh_operation_panels(_array_or_empty(crafting_continuation.get("refresh", [])))
	refresh_hud(current_interaction_prompt())
	return {
		"success": true,
		"render_world": false,
		"world_result_synced": needs_world_result_sync,
		"step_result": step_result.duplicate(true),
		"turn_action_runner": runner_snapshot.duplicate(true),
	}


func _turn_action_step_needs_world_result_sync(step_result: Dictionary, runner_snapshot: Dictionary, interaction_result: Dictionary, crafting_continuation: Dictionary = {}) -> bool:
	if not interaction_result.is_empty():
		return true
	if bool(crafting_continuation.get("continued", false)):
		return true
	return _turn_action_result_has_structural_change(step_result) \
		or _turn_action_result_has_structural_change(_dictionary_or_empty(step_result.get("attack_result", {}))) \
		or _turn_action_result_has_structural_change(_dictionary_or_empty(step_result.get("npc_attack_result", {}))) \
		or _turn_action_result_has_structural_change(_dictionary_or_empty(step_result.get("pending_result", {}))) \
		or _turn_action_runner_is_structural_refresh_boundary(runner_snapshot)


func _turn_action_result_has_structural_change(result: Dictionary) -> bool:
	if result.is_empty():
		return false
	if result.has("context_snapshot"):
		return true
	if result.has("container") or result.has("shop"):
		return true
	if bool(result.get("consumed_target", false)) or bool(result.get("door_toggled", false)):
		return true
	if bool(result.get("defeated", false)) or bool(result.get("corpse_created", false)):
		return true
	for event_value in _interaction_result_events(result):
		var event: Dictionary = _dictionary_or_empty(event_value)
		match str(event.get("kind", "")):
			"actor_defeated", "corpse_created", "interaction_succeeded", "scene_transition", "door_toggled", "door_auto_opened", "container_opened":
				return true
	return false


func _turn_action_runner_is_structural_refresh_boundary(runner_snapshot: Dictionary) -> bool:
	if bool(runner_snapshot.get("active", false)) or bool(runner_snapshot.get("presentation_active", false)):
		return false
	var pending_kind := str(runner_snapshot.get("pending_kind", ""))
	if not pending_kind.is_empty():
		return false
	var action_kind := str(runner_snapshot.get("action_kind", ""))
	return action_kind in ["interact", "attack"]


func _runner_interaction_result(step_result: Dictionary, runner_snapshot: Dictionary) -> Dictionary:
	if str(runner_snapshot.get("action_kind", "")) != "interact":
		return {}
	var pending_result: Dictionary = _dictionary_or_empty(step_result.get("pending_result", {}))
	if _is_final_interaction_result(pending_result):
		return pending_result
	if _is_final_interaction_result(step_result):
		return step_result
	return {}


func _is_final_interaction_result(result: Dictionary) -> bool:
	if result.is_empty() or not bool(result.get("success", false)):
		return false
	return bool(result.get("consumed_target", false)) \
		or result.has("dialogue_id") \
		or result.has("container") \
		or result.has("context_snapshot") \
		or bool(result.get("defeated", false)) \
		or bool(result.get("interaction_completed", false))


func _runner_step_should_continue_crafting_queue(step_result: Dictionary, runner_snapshot: Dictionary) -> bool:
	if not ["wait", "craft"].has(str(runner_snapshot.get("action_kind", ""))):
		return false
	if not bool(step_result.get("success", false)):
		return false
	var pending_result: Dictionary = _dictionary_or_empty(step_result.get("pending_result", {}))
	if pending_result.is_empty():
		return false
	if _wait_result_resumed_active_crafting_queue(step_result):
		return true
	if str(runner_snapshot.get("action_kind", "")) != "craft":
		return false
	var resumed: Dictionary = _dictionary_or_empty(pending_result.get("resumed_pending_crafting", {}))
	if resumed.is_empty():
		return false
	var command: Dictionary = _dictionary_or_empty(resumed.get("command", {}))
	return bool(command.get("crafting_queue_active", false))


func cancel_pending(reason: String = "cancelled", auto_end_turn: bool = false) -> Dictionary:
	var operation: Dictionary = _dictionary_or_empty(interaction_action_controller.call("cancel_pending", interaction_controller, reason, auto_end_turn))
	return _apply_player_action_refresh_operation(operation, current_interaction_prompt(), _dictionary_or_empty(operation.get("result", {})))


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
	return _apply_player_action_refresh_operation(operation)


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
	return _apply_player_action_refresh_operation(operation)


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
	return _apply_player_action_refresh_operation(operation)


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
	var operation: Dictionary = _dictionary_or_empty(crafting_action_controller.call("craft_recipe", simulation, recipe_id, count, registry.get_library("recipes"), _crafting_context(), _dictionary_or_empty(world_result.get("map", {})), crafting_feedback_controller, Callable(self, "_submit_craft_via_turn_action_runner")))
	return _apply_crafting_action_operation(operation)


func confirm_crafting_queue(entries: Array) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var blocked: Dictionary = _player_command_rejection("crafting_queue")
	if not blocked.is_empty():
		return blocked
	var operation: Dictionary = _dictionary_or_empty(crafting_action_controller.call("confirm_queue", simulation, entries, registry.get_library("recipes"), _crafting_context(), _dictionary_or_empty(world_result.get("map", {})), crafting_feedback_controller, CRAFTING_QUEUE_ADVANCE_LIMIT, Callable(self, "_submit_craft_via_turn_action_runner")))
	return _apply_crafting_action_operation(operation)


func _advance_crafting_queue(reason: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	return _dictionary_or_empty(crafting_action_controller.call("advance_queue", simulation, reason, registry.get_library("recipes"), _crafting_context(), _dictionary_or_empty(world_result.get("map", {})), CRAFTING_QUEUE_ADVANCE_LIMIT, Callable(self, "_submit_craft_via_turn_action_runner")))


func _submit_crafting_queue_entry(recipe_id: String, count: int) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	return _dictionary_or_empty(crafting_action_controller.call("_submit_craft", simulation, recipe_id, count, registry.get_library("recipes"), _crafting_context(), _dictionary_or_empty(world_result.get("map", {})), true, Callable(self, "_submit_craft_via_turn_action_runner")))


func _continue_crafting_queue_after_wait(result: Dictionary, wait_runner_snapshot: Dictionary = {}) -> Dictionary:
	var continuation: Dictionary = _dictionary_or_empty(crafting_action_controller.call("continue_queue_after_wait", simulation, result, registry.get_library("recipes"), _crafting_context(), _dictionary_or_empty(world_result.get("map", {})), crafting_feedback_controller, CRAFTING_QUEUE_ADVANCE_LIMIT, Callable(self, "_submit_craft_via_turn_action_runner")))
	if bool(continuation.get("continued", false)):
		continuation["refresh"] = ["inventory", "crafting", "skills"]
		continuation["wait_runner_snapshot"] = wait_runner_snapshot.duplicate(true)
		var action_kind := str(wait_runner_snapshot.get("action_kind", ""))
		latest_action_chain = {
			"kind": "craft_to_crafting_queue" if action_kind == "craft" else "wait_to_crafting_queue",
			"wait_result": result.duplicate(true),
			"wait_runner": wait_runner_snapshot.duplicate(true),
			"source_action_kind": action_kind,
			"queue_result": _dictionary_or_empty(continuation.get("queue_result", {})).duplicate(true),
		}
	return continuation


func _submit_craft_via_turn_action_runner(recipe_id: String, count: int, recipe_library: Dictionary, crafting_context: Dictionary, topology: Dictionary, queue_active: bool) -> Dictionary:
	var command := {
		"kind": "craft",
		"actor_id": _player_actor_id(),
		"recipe_id": recipe_id,
		"count": max(1, count),
		"recipe_library": recipe_library,
		"crafting_context": crafting_context.duplicate(true),
		"topology": topology.duplicate(true),
	}
	if queue_active:
		command["crafting_queue_active"] = true
	return request_player_craft(command, {"crafting_queue_active": queue_active})


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
	return _dictionary_or_empty(crafting_context_builder.call("build", simulation, world_result, latest_crafting_queue_result, latest_pending_crafting_result))


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
	return _apply_player_action_refresh_operation(operation, current_interaction_prompt(), _dictionary_or_empty(operation.get("result", {})), {})


func _apply_player_action_refresh_operation(operation: Dictionary, selected_prompt: Dictionary = {}, rebuild_command_result: Dictionary = {}, rebuild_selected_prompt: Variant = null) -> Dictionary:
	return _dictionary_or_empty(player_action_refresh_controller.call(
		"apply_operation",
		operation,
		selected_prompt,
		rebuild_command_result,
		rebuild_selected_prompt,
		Callable(self, "rebuild_runtime_world"),
		Callable(self, "refresh_all_panels"),
		Callable(self, "_refresh_operation_panels")
	))


func _rebuild_world_after_runtime_change(selected_prompt: Dictionary = {}, command_result: Dictionary = {}) -> void:
	if not _rebuild_runtime_world_result("runtime_change"):
		return
	_apply_runtime_scene_refresh(true, selected_prompt, {
		"present_world_action": true,
		"command_result": command_result,
		"refresh_kind": "all",
	})


func _rebuild_runtime_world_result(source: String) -> bool:
	var refresh: Dictionary = _dictionary_or_empty(runtime_refresh_controller.call("rebuild_world_result", simulation, interaction_controller, source))
	return _accept_runtime_refresh_result(refresh, "world rebuild failed")


func _apply_existing_runtime_world_result(next_world_result: Dictionary, source: String, fallback_error: String = "world refresh failed") -> bool:
	var refresh: Dictionary = _dictionary_or_empty(runtime_refresh_controller.call("apply_existing_world_result", simulation, interaction_controller, next_world_result, source))
	return _accept_runtime_refresh_result(refresh, fallback_error)


func _accept_runtime_refresh_result(refresh: Dictionary, fallback_error: String) -> bool:
	var accepted: Dictionary = _dictionary_or_empty(runtime_refresh_controller.call("accept_and_report_refresh_result", refresh, fallback_error))
	world_result = _dictionary_or_empty(accepted.get("world_result", {}))
	if not bool(accepted.get("ok", false)):
		return false
	if bool(accepted.get("sync_observed_level", false)):
		runtime_view_state_controller.call("sync_observed_level_to_map", world_result)
	return true


func _world_container_node() -> Node3D:
	if world_root != null and world_root.has_method("world_container_node"):
		var container := world_root.call("world_container_node") as Node3D
		if container != null:
			_world_container_ref = container
	return _world_container_ref


func _player_actor_id() -> int:
	if simulation != null and simulation.has_method("_player_actor_id"):
		return int(simulation.call("_player_actor_id"))
	return 1


func _setup_world_container() -> void:
	if world_root == null or not is_instance_valid(world_root):
		world_root = WorldRootScene.instantiate() as Node3D
		if world_root == null:
			world_root = WorldRoot.new()
		world_root.name = "WorldRoot"
		add_child(world_root)
	if world_root.has_method("ensure_world_container"):
		_world_container_ref = world_root.call("ensure_world_container")


func _setup_runtime_input_controller() -> void:
	if runtime_input_controller == null:
		runtime_input_controller = GameRuntimeInputController.new(self)
	runtime_input_controller.attach_world(_world_container_node(), world_result)
	_configure_turn_action_runner()


func _configure_turn_action_runner() -> void:
	if actor_view_controller != null and actor_view_controller.has_method("attach"):
		actor_view_controller.call("attach", _world_container_node())
	if turn_action_runner != null and turn_action_runner.has_method("configure"):
		turn_action_runner.call("configure", simulation, actor_view_controller, self, world_result)


func _refresh_world_runtime_bindings() -> void:
	_setup_runtime_input_controller()
	_configure_runtime_audio_layers()
	_setup_panels()


func refresh_world_visuals(render_world: bool = true) -> Dictionary:
	var boundary: Dictionary = _prepare_structural_refresh_boundary("refresh_world_visuals", render_world)
	var counts: Dictionary = _apply_world_root_snapshot(render_world)
	if render_world:
		_record_structural_refresh_boundary(boundary, "refresh_world_visuals", counts)
	return counts


func rebuild_runtime_world(selected_prompt: Dictionary = {}, command_result: Dictionary = {}) -> void:
	_rebuild_world_after_runtime_change(selected_prompt, command_result)


func _apply_runtime_scene_refresh(render_world: bool = true, selected_prompt: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	var plan: Dictionary = _dictionary_or_empty(runtime_refresh_controller.call("build_scene_apply_plan", render_world, selected_prompt, options))
	var boundary: Dictionary = _prepare_structural_refresh_boundary(str(options.get("source", "runtime_scene_refresh")), bool(plan.get("render_world", true)))
	var counts: Dictionary = _apply_world_root_snapshot(bool(plan.get("render_world", true)))
	if bool(plan.get("render_world", true)):
		_record_structural_refresh_boundary(boundary, str(options.get("source", "runtime_scene_refresh")), counts)
	if bool(plan.get("present_world_action", false)):
		_present_world_action(_dictionary_or_empty(plan.get("command_result", {})))
	if bool(plan.get("refresh_runtime_bindings", true)):
		_refresh_world_runtime_bindings()
	var refresh_kind := str(plan.get("refresh_kind", "none"))
	var prompt: Dictionary = _dictionary_or_empty(plan.get("prompt", {}))
	if refresh_kind == "all":
		refresh_all_panels(prompt)
	elif refresh_kind == "hud":
		refresh_hud(prompt)
	return counts


func _prepare_structural_refresh_boundary(source: String, render_world: bool = true) -> Dictionary:
	var before_runner: Dictionary = turn_action_runner_snapshot()
	var before_policy: Dictionary = world_render_policy_snapshot()
	var before_phase := str(before_runner.get("phase", ""))
	var runner_busy := bool(before_runner.get("active", false)) or bool(before_runner.get("presentation_active", false))
	var requires_boundary := render_world and runner_busy and before_phase != "finished"
	var boundary_result: Dictionary = {}
	if requires_boundary:
		boundary_result = settle_turn_action_runner_boundary("structural_refresh:%s" % source)
		refresh_hud(current_interaction_prompt())
	return {
		"source": source,
		"render_world": render_world,
		"required": requires_boundary,
		"settled": not requires_boundary or bool(boundary_result.get("settled", false)),
		"boundary_result": boundary_result.duplicate(true),
		"before_runner": before_runner.duplicate(true),
		"after_runner": turn_action_runner_snapshot(),
		"before_policy": before_policy.duplicate(true),
		"after_policy": world_render_policy_snapshot(),
	}


func _record_structural_refresh_boundary(boundary: Dictionary, source: String, counts: Dictionary) -> void:
	var record: Dictionary = boundary.duplicate(true)
	record["source"] = source
	record["rendered"] = true
	record["render_sequence"] = int(runtime_performance_snapshot().get("render_sequence", 0))
	record["counts"] = counts.duplicate(true)
	latest_structural_refresh_boundary = record


func _apply_world_root_snapshot(render_world: bool = true) -> Dictionary:
	_setup_world_container()
	if world_root == null:
		return {}
	var runtime_snapshot: Dictionary = simulation.snapshot() if simulation != null else {}
	var apply_result: Dictionary = _dictionary_or_empty(world_root.call("apply_runtime_snapshot", world_result, runtime_snapshot, current_debug_overlay_mode(), render_world))
	var counts: Dictionary = _dictionary_or_empty(apply_result.get("counts", {}))
	if render_world:
		runtime_performance_tracker.call("record_world_render", counts, world_root)
	elif runtime_input_controller != null:
		runtime_input_controller.world_result = world_result
	_world_container_ref = apply_result.get("world_container", _world_container_ref) as Node3D
	_fog_overlay_ref = apply_result.get("fog_overlay", _fog_overlay_ref) as ColorRect
	return counts


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
		hud_root = HUD_ROOT_SCENE.instantiate()
		hud_root.name = "HudRoot"
		add_child(hud_root)
		if hud_root.has_method("configure"):
			hud_root.call("configure", self)
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
	var modal_name := _panel_modal_blocker_name()
	var result: Dictionary = _dictionary_or_empty(player_command_blocker.call(
		"player_command_rejection",
		action,
		is_observe_mode_enabled(),
		modal_name,
		_world_action_presenter_blocks_input(),
		gameplay_input_blocker_snapshot()
	))
	if not result.is_empty():
		refresh_hud(current_interaction_prompt())
	return result


func _observe_command_rejected(action: String) -> Dictionary:
	var result: Dictionary = _dictionary_or_empty(player_command_blocker.call("observe_command_rejected", action, is_observe_mode_enabled()))
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
