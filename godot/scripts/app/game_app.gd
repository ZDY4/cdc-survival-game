extends Node3D

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")
const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")
const WorldActionPresenter = preload("res://scripts/world/world_action_presenter.gd")
const FogOverlayController = preload("res://scripts/world/fog_overlay_controller.gd")
const DebugOverlayController = preload("res://scripts/world/debug_overlay_controller.gd")
const DebugRuntimeController = preload("res://scripts/app/controllers/debug_runtime_controller.gd")
const GamePanelController = preload("res://scripts/app/controllers/game_panel_controller.gd")
const GameRuntimeInputController = preload("res://scripts/app/controllers/game_runtime_input_controller.gd")
const PlayerInteractionController = preload("res://scripts/app/controllers/player_interaction_controller.gd")
const AudioFeedbackController = preload("res://scripts/app/audio_feedback_controller.gd")
const ReasonCatalog = preload("res://scripts/ui/snapshots/reason_catalog.gd")
const AUTO_TICK_INTERVAL_SEC := 0.45
const CRAFTING_QUEUE_ADVANCE_LIMIT := 16
const OBSERVE_SPEEDS: Array[Dictionary] = [
	{"id": "x1", "multiplier": 1.0},
	{"id": "x2", "multiplier": 2.0},
	{"id": "x5", "multiplier": 5.0},
	{"id": "x10", "multiplier": 10.0},
]
const PLAYER_COMMAND_AUTHORITY_AUDIT: Array[Dictionary] = [
	{"app_method": "execute_primary_interaction", "action": "interact", "authority_kind": "submit_player_command", "command_kind": "interact", "owner": "GameApp", "blocker": "_player_command_rejection"},
	{"app_method": "execute_interaction_option", "action": "interact_option", "authority_kind": "submit_player_command", "command_kind": "interact", "owner": "GameApp", "blocker": "_player_command_rejection"},
	{"app_method": "execute_move_to_grid", "action": "move", "authority_kind": "submit_player_command", "command_kind": "move", "owner": "GameApp", "blocker": "_player_command_rejection"},
	{"app_method": "press_space_action", "action": "wait_or_dialogue_advance", "authority_kind": "mixed", "command_kind": "wait", "core_service": "advance_dialogue_without_choice", "owner": "GameApp", "blocker": "dialogue_or_pending_or_command"},
	{"app_method": "_submit_auto_tick_wait", "action": "auto_wait", "authority_kind": "submit_player_command", "command_kind": "wait", "owner": "GameApp", "blocker": "ui_or_pending"},
	{"app_method": "choose_dialogue_option", "action": "dialogue_choice", "authority_kind": "core_service", "core_service": "Simulation.advance_dialogue", "owner": "GameApp", "blocker": "dialogue_session"},
	{"app_method": "advance_dialogue_without_choice", "action": "dialogue_continue", "authority_kind": "core_service", "core_service": "Simulation.advance_dialogue_without_choice", "owner": "GameApp", "blocker": "dialogue_session"},
	{"app_method": "close_active_dialogue", "action": "dialogue_close", "authority_kind": "core_service", "core_service": "Simulation.close_dialogue", "owner": "GameApp", "blocker": "dialogue_session"},
	{"app_method": "close_active_container", "action": "container_close", "authority_kind": "core_service", "core_service": "Simulation.close_container", "owner": "GameApp", "blocker": "container_session"},
	{"app_method": "take_active_container_item", "action": "take_container", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "take_container", "owner": "GameApp", "blocker": "_submit_inventory_action"},
	{"app_method": "take_active_container_money", "action": "take_container_money", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "take_container_money", "owner": "GameApp", "blocker": "_submit_inventory_action"},
	{"app_method": "take_all_active_container_items", "action": "take_all_container", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "take_all_container", "owner": "GameApp", "blocker": "_submit_inventory_action"},
	{"app_method": "store_active_container_item", "action": "store_container", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "store_container", "owner": "GameApp", "blocker": "_submit_inventory_action"},
	{"app_method": "store_all_active_container_items", "action": "store_all_container", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "store_all_container", "owner": "GameApp", "blocker": "_submit_inventory_action"},
	{"app_method": "drop_player_item", "action": "drop_item", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "drop", "owner": "GameApp", "blocker": "_submit_inventory_action"},
	{"app_method": "deconstruct_player_item", "action": "deconstruct_item", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "deconstruct", "owner": "GameApp", "blocker": "_submit_inventory_action"},
	{"app_method": "split_player_inventory_stack", "action": "split_stack", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "split_stack", "owner": "GameApp", "blocker": "_submit_inventory_action"},
	{"app_method": "reorder_player_inventory_item", "action": "reorder_inventory", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "reorder_inventory", "owner": "GameApp", "blocker": "_submit_inventory_action"},
	{"app_method": "use_player_item", "action": "use_item", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "use_item", "owner": "GameApp", "blocker": "_submit_inventory_action"},
	{"app_method": "buy_active_trade_item", "action": "buy_shop", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "buy_shop", "owner": "GameApp", "blocker": "_submit_inventory_action"},
	{"app_method": "sell_active_trade_item", "action": "sell_shop", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "sell_shop", "owner": "GameApp", "blocker": "_submit_inventory_action"},
	{"app_method": "sell_active_trade_equipment", "action": "sell_equipped_shop", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "sell_equipped_shop", "owner": "GameApp", "blocker": "_submit_inventory_action"},
	{"app_method": "confirm_active_trade_cart", "action": "trade_cart", "authority_kind": "core_service", "core_service": "Simulation.confirm_trade_cart", "owner": "GameApp", "blocker": "trade_session"},
	{"app_method": "equip_player_item", "action": "equip", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "equip", "owner": "GameApp", "blocker": "_submit_inventory_action"},
	{"app_method": "unequip_player_slot", "action": "unequip", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "unequip", "owner": "GameApp", "blocker": "_submit_inventory_action"},
	{"app_method": "reload_player_equipped_slot", "action": "reload_equipped", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "reload_equipped", "owner": "GameApp", "blocker": "_submit_inventory_action"},
	{"app_method": "allocate_player_attribute_point", "action": "allocate_attribute", "authority_kind": "core_service", "core_service": "Simulation.allocate_attribute_point", "owner": "GameApp", "blocker": "attribute_points"},
	{"app_method": "learn_player_skill", "action": "learn_skill", "authority_kind": "submit_player_command", "command_kind": "learn_skill", "owner": "GameApp", "blocker": "_player_command_rejection"},
	{"app_method": "bind_player_skill_to_hotbar", "action": "bind_skill_hotbar", "authority_kind": "submit_player_command", "command_kind": "bind_hotbar", "owner": "GameApp", "blocker": "_player_command_rejection"},
	{"app_method": "bind_player_item_to_hotbar", "action": "bind_item_hotbar", "authority_kind": "submit_player_command", "command_kind": "bind_hotbar", "owner": "GameApp", "blocker": "_player_command_rejection"},
	{"app_method": "set_hotbar_group", "action": "set_hotbar_group", "authority_kind": "core_service", "core_service": "Simulation.set_active_hotbar_group", "owner": "GameApp", "blocker": "world_action_presenter"},
	{"app_method": "set_hotbar_group_label", "action": "set_hotbar_group_label", "authority_kind": "core_service", "core_service": "Simulation.set_hotbar_group_label", "owner": "GameApp", "blocker": "hotbar_group"},
	{"app_method": "cycle_hotbar_group", "action": "cycle_hotbar_group", "authority_kind": "core_service", "core_service": "Simulation.cycle_hotbar_group", "owner": "GameApp", "blocker": "world_action_presenter"},
	{"app_method": "use_hotbar_slot", "action": "use_hotbar", "authority_kind": "submit_player_command", "command_kind": "use_skill_or_inventory_action", "owner": "GameApp", "blocker": "_player_command_rejection"},
	{"app_method": "begin_skill_targeting", "action": "begin_skill_targeting", "authority_kind": "submit_player_command_or_ui_state", "command_kind": "use_skill", "owner": "GameApp", "blocker": "_player_command_rejection"},
	{"app_method": "confirm_active_skill_target", "action": "confirm_skill_target", "authority_kind": "submit_player_command", "command_kind": "use_skill", "owner": "GameApp", "blocker": "_player_command_rejection"},
	{"app_method": "craft_player_recipe", "action": "craft", "authority_kind": "submit_player_command", "command_kind": "craft", "owner": "GameApp", "blocker": "_player_command_rejection"},
	{"app_method": "confirm_crafting_queue", "action": "crafting_queue", "authority_kind": "submit_player_command", "command_kind": "craft", "owner": "GameApp", "blocker": "_player_command_rejection", "authority_helper": "_submit_crafting_queue_entry"},
	{"app_method": "cancel_pending_crafting", "action": "cancel_pending_crafting", "authority_kind": "submit_player_command", "command_kind": "cancel_pending", "owner": "GameApp", "blocker": "pending_crafting"},
	{"app_method": "turn_in_player_quest", "action": "quest_turn_in", "authority_kind": "core_service", "core_service": "Simulation.turn_in_quest", "owner": "GameApp", "blocker": "quest_state"},
	{"app_method": "enter_overworld_location_from_panel", "action": "enter_overworld_location", "authority_kind": "core_service", "core_service": "Simulation.enter_location", "owner": "GameApp", "blocker": "map_panel_prompt"},
]

var registry: ContentRegistry
var simulation: RefCounted
var world_result: Dictionary = {}
var interaction_controller: RefCounted
var runtime_input_controller: RefCounted
var panel_controller: RefCounted
var fog_overlay_controller: RefCounted = FogOverlayController.new()
var debug_overlay_controller: RefCounted = DebugOverlayController.new()
var world_action_presenter: RefCounted = WorldActionPresenter.new()
var world_action_queue_sequence: int = 0
var world_action_queue_state: Dictionary = {
	"active": false,
	"state": "idle",
	"sequence": 0,
	"current_strategy": "present_before_final_refresh",
	"target_strategy": "present_before_final_refresh",
}
var pending_world_action_ui: Dictionary = {}
var pending_world_action_final_refresh: Dictionary = {}
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
var tooltip_layer: Control
var tooltip_panel: PanelContainer
var tooltip_label: Label
var last_tooltip_render_snapshot: Dictionary = {"active": false}
var drag_preview_layer: Control
var drag_preview_panel: PanelContainer
var drag_preview_label: Label
var last_drag_preview_render_snapshot: Dictionary = {"active": false}
var active_trade_target: Dictionary = {}
var active_trade_feedback: Dictionary = {}
var active_container_feedback: Dictionary = {}
var active_character_feedback: Dictionary = {}
var active_inventory_feedback: Dictionary = {}
var latest_crafting_queue_result: Dictionary = {}
var latest_pending_crafting_result: Dictionary = {}
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
var debug_runtime_controller: RefCounted = DebugRuntimeController.new()


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
	_setup_audio_feedback_controller()
	_configure_runtime_audio_layers()
	_setup_panels()
	_setup_tooltip_layer()
	_setup_drag_preview_layer()
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
	_process_world_action_queue_completion()
	_update_tooltip_layer()
	_process_auto_tick(delta)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and _handle_debug_console_key(event as InputEventKey):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and is_debug_console_open():
		return
	if runtime_input_controller != null:
		runtime_input_controller.input(event)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and is_debug_console_open():
		return
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
	_process_audio_feedback()
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
	if world_action_presenter == null:
		return false
	var snapshot: Dictionary = world_action_presenter_snapshot()
	return bool(snapshot.get("active", false))


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
	var viewport := get_viewport()
	var query_source := "explicit" if control != null else "hovered"
	var source := control
	if source == null:
		source = viewport.gui_get_hovered_control() if viewport != null else null
	if source == null:
		return _tooltip_snapshot_base(null, null, query_source, "no_source")
	var tooltip_source := _tooltip_source_for_control(source)
	if tooltip_source == null:
		return _tooltip_snapshot_base(source, null, query_source, "no_text")
	var snapshot := _tooltip_snapshot_base(source, tooltip_source, query_source, "active")
	snapshot["active"] = true
	return snapshot


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
	if drag_data.is_empty():
		return {"active": false, "kind": "", "source": {}, "target": _drag_hover_target_snapshot(hover_target, drag_data), "preview": {}, "payload": {}}
	var kind := str(drag_data.get("kind", ""))
	var payload := _drag_payload_snapshot(drag_data)
	return {
		"active": true,
		"kind": kind,
		"source": _drag_source_snapshot(drag_data, kind),
		"target": _drag_hover_target_snapshot(hover_target, drag_data),
		"preview": _drag_preview_snapshot(drag_data, payload),
		"payload": payload,
	}


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
	if tooltip_layer != null:
		return
	tooltip_layer = Control.new()
	tooltip_layer.name = "TooltipLayer"
	tooltip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	tooltip_layer.visible = false
	add_child(tooltip_layer)
	tooltip_panel = PanelContainer.new()
	tooltip_panel.name = "TooltipPanel"
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_panel.visible = false
	tooltip_layer.add_child(tooltip_panel)
	tooltip_label = Label.new()
	tooltip_label.name = "TooltipLabel"
	tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_panel.add_child(tooltip_label)


func _update_tooltip_layer() -> void:
	_setup_tooltip_layer()
	var snapshot: Dictionary = hover_tooltip_snapshot()
	if not bool(snapshot.get("active", false)):
		_hide_tooltip_layer(str(snapshot.get("lifecycle_state", "inactive")))
		return
	_render_tooltip_snapshot(snapshot)


func _hide_tooltip_layer(reason: String) -> void:
	if tooltip_layer != null:
		tooltip_layer.visible = false
	if tooltip_panel != null:
		tooltip_panel.visible = false
	last_tooltip_render_snapshot = {
		"active": false,
		"reason": reason,
		"layer_exists": tooltip_layer != null,
		"mouse_blocks_world": false,
	}


func _render_tooltip_snapshot(snapshot: Dictionary) -> void:
	if tooltip_layer == null or tooltip_panel == null or tooltip_label == null:
		_hide_tooltip_layer("layer_missing")
		return
	var rect: Dictionary = _dictionary_or_empty(snapshot.get("recommended_rect", {}))
	var visual: Dictionary = _dictionary_or_empty(snapshot.get("visual", {}))
	var position := Vector2(float(rect.get("x", 8.0)), float(rect.get("y", 8.0)))
	var size := Vector2(float(rect.get("w", 160.0)), float(rect.get("h", 28.0)))
	tooltip_layer.visible = true
	tooltip_panel.visible = true
	tooltip_panel.position = position
	tooltip_panel.custom_minimum_size = size
	tooltip_panel.size = size
	tooltip_panel.add_theme_stylebox_override("panel", _tooltip_panel_style(visual))
	tooltip_label.text = str(snapshot.get("text", ""))
	tooltip_label.custom_minimum_size = Vector2(max(1.0, size.x - 20.0), 0.0)
	tooltip_label.add_theme_font_size_override("font_size", 12)
	tooltip_label.set_meta("tooltip_text_length", int(snapshot.get("text_length", 0)))
	tooltip_label.set_meta("tooltip_owner_panel", str(snapshot.get("owner_panel", "")))
	tooltip_label.set_meta("tooltip_source_name", str(snapshot.get("source_name", "")))
	tooltip_panel.set_meta("tooltip_visual_style", str(visual.get("style", "")))
	tooltip_panel.set_meta("tooltip_theme_type", str(visual.get("theme_type", "")))
	tooltip_panel.set_meta("tooltip_recommended_rect", rect.duplicate(true))
	tooltip_panel.set_meta("tooltip_non_blocking", bool(visual.get("non_blocking", false)))
	last_tooltip_render_snapshot = {
		"active": true,
		"layer_path": str(tooltip_layer.get_path()),
		"panel_path": str(tooltip_panel.get_path()),
		"label_path": str(tooltip_label.get_path()),
		"owner_panel": str(snapshot.get("owner_panel", "")),
		"source_name": str(snapshot.get("source_name", "")),
		"text": str(snapshot.get("text", "")),
		"text_length": int(snapshot.get("text_length", 0)),
		"mouse_blocks_world": tooltip_layer.mouse_filter == Control.MOUSE_FILTER_STOP or tooltip_panel.mouse_filter == Control.MOUSE_FILTER_STOP,
		"layer_mouse_filter": _mouse_filter_name(tooltip_layer.mouse_filter),
		"panel_mouse_filter": _mouse_filter_name(tooltip_panel.mouse_filter),
		"visual": visual.duplicate(true),
		"recommended_rect": rect.duplicate(true),
		"actual_rect": {"x": tooltip_panel.position.x, "y": tooltip_panel.position.y, "w": tooltip_panel.size.x, "h": tooltip_panel.size.y},
		"label_text_matches": tooltip_label.text == str(snapshot.get("text", "")),
	}


func _tooltip_panel_style(visual: Dictionary) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.078, 0.105, 0.88)
	style.border_color = Color(0.39, 0.50, 0.61, 0.96)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	var radius := int(visual.get("corner_radius", 4))
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	var padding: Dictionary = _dictionary_or_empty(visual.get("padding", {}))
	var padding_x := float(padding.get("x", 10.0))
	var padding_y := float(padding.get("y", 7.0))
	style.content_margin_left = padding_x
	style.content_margin_right = padding_x
	style.content_margin_top = padding_y
	style.content_margin_bottom = padding_y
	return style


func _setup_drag_preview_layer() -> void:
	if drag_preview_layer != null:
		return
	drag_preview_layer = Control.new()
	drag_preview_layer.name = "DragPreviewLayer"
	drag_preview_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	drag_preview_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	drag_preview_layer.visible = false
	add_child(drag_preview_layer)
	drag_preview_panel = PanelContainer.new()
	drag_preview_panel.name = "DragPreviewPanel"
	drag_preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_preview_panel.visible = false
	drag_preview_layer.add_child(drag_preview_panel)
	drag_preview_label = Label.new()
	drag_preview_label.name = "DragPreviewLabel"
	drag_preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_preview_label.clip_text = true
	drag_preview_panel.add_child(drag_preview_label)


func render_drag_preview_for_snapshot(drag_data: Variant = {}, hover_target: Control = null) -> Dictionary:
	var drag: Dictionary = drag_state_snapshot(drag_data, hover_target)
	if not bool(drag.get("active", false)):
		_hide_drag_preview_layer("inactive")
		return drag_preview_render_snapshot()
	_render_drag_preview_snapshot(drag)
	return drag_preview_render_snapshot()


func _hide_drag_preview_layer(reason: String) -> void:
	if drag_preview_layer != null:
		drag_preview_layer.visible = false
	if drag_preview_panel != null:
		drag_preview_panel.visible = false
	last_drag_preview_render_snapshot = {
		"active": false,
		"reason": reason,
		"layer_exists": drag_preview_layer != null,
		"mouse_blocks_world": false,
	}


func _render_drag_preview_snapshot(drag: Dictionary) -> void:
	_setup_drag_preview_layer()
	if drag_preview_layer == null or drag_preview_panel == null or drag_preview_label == null:
		_hide_drag_preview_layer("layer_missing")
		return
	var preview: Dictionary = _dictionary_or_empty(drag.get("preview", {}))
	var position_data: Dictionary = _dictionary_or_empty(preview.get("screen_position", {}))
	var anchor_data: Dictionary = _dictionary_or_empty(preview.get("anchor", {}))
	var size_data: Dictionary = _dictionary_or_empty(preview.get("estimated_size", {}))
	var position := Vector2(float(position_data.get("x", 0.0)) + float(anchor_data.get("x", 8.0)), float(position_data.get("y", 0.0)) + float(anchor_data.get("y", 8.0)))
	var size := Vector2(maxf(48.0, float(size_data.get("x", 80.0))), maxf(24.0, float(size_data.get("y", 24.0))))
	drag_preview_layer.visible = true
	drag_preview_panel.visible = true
	drag_preview_panel.position = position
	drag_preview_panel.custom_minimum_size = size
	drag_preview_panel.size = size
	drag_preview_panel.add_theme_stylebox_override("panel", _drag_preview_panel_style(str(drag.get("kind", ""))))
	drag_preview_label.text = str(preview.get("text", ""))
	drag_preview_label.custom_minimum_size = Vector2(max(1.0, size.x - 18.0), max(1.0, size.y - 8.0))
	drag_preview_label.add_theme_font_size_override("font_size", 12)
	drag_preview_panel.set_meta("drag_preview_kind", str(drag.get("kind", "")))
	drag_preview_panel.set_meta("drag_preview_text", drag_preview_label.text)
	drag_preview_panel.set_meta("drag_preview_lifecycle", str(preview.get("lifecycle_state", "")))
	drag_preview_panel.set_meta("drag_preview_threshold_policy", str(preview.get("threshold_policy", "")))
	last_drag_preview_render_snapshot = {
		"active": true,
		"layer_path": str(drag_preview_layer.get_path()),
		"panel_path": str(drag_preview_panel.get_path()),
		"label_path": str(drag_preview_label.get_path()),
		"kind": str(drag.get("kind", "")),
		"owner_panel": str(_dictionary_or_empty(drag.get("source", {})).get("owner_panel", "")),
		"text": drag_preview_label.text,
		"mouse_blocks_world": drag_preview_layer.mouse_filter == Control.MOUSE_FILTER_STOP,
		"layer_mouse_filter": _mouse_filter_name(drag_preview_layer.mouse_filter),
		"panel_mouse_filter": _mouse_filter_name(drag_preview_panel.mouse_filter),
		"preview": preview.duplicate(true),
		"actual_rect": {"x": drag_preview_panel.position.x, "y": drag_preview_panel.position.y, "w": drag_preview_panel.size.x, "h": drag_preview_panel.size.y},
		"label_text_matches": drag_preview_label.text == str(preview.get("text", "")),
		"threshold_policy": str(preview.get("threshold_policy", "")),
		"lifecycle_state": str(preview.get("lifecycle_state", "")),
	}


func _drag_preview_panel_style(kind: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.13, 0.16, 0.86)
	style.border_color = Color(0.58, 0.68, 0.74, 0.96)
	if kind == "skill_hotbar":
		style.border_color = Color(0.45, 0.66, 0.90, 0.96)
	elif kind in ["trade_item", "trade_cart_entry"]:
		style.border_color = Color(0.74, 0.62, 0.36, 0.96)
	elif kind == "container_item":
		style.border_color = Color(0.42, 0.70, 0.55, 0.96)
	style.border_width_left = 2
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


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
	var modes := ["off", "walkable", "vision", "blocked_sight", "level"]
	var index := modes.find(debug_overlay_mode)
	if index < 0:
		index = 0
	debug_overlay_mode = modes[(index + 1) % modes.size()]
	_refresh_debug_overlay()
	refresh_hud(current_interaction_prompt())
	_play_hud_shortcut_audio("ui_option_selected", "DebugOverlayShortcut", "keyboard_shortcut", "cycle_debug_overlay", {
		"value": debug_overlay_mode,
	})
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
	return not observe_mode_enabled and not _world_action_presenter_blocks_input() and _panel_modal_blocker_name().is_empty()


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
	_play_hud_shortcut_audio("ui_option_selected", "InfoPanelShortcut", "keyboard_shortcut", "cycle_info_panel", {
		"value": str(page.get("id", "")),
		"count": info_panel_pages.size(),
		"option_index": active_info_panel_index,
	})
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
		"world_time": runtime_world_time_snapshot(),
		"map_level": map_level_snapshot(),
		"focused_actor": focused_actor_snapshot(),
		"ui_blocker": gameplay_input_blocker_name(),
		"ui_blocker_snapshot": gameplay_input_blocker_snapshot(),
		"modal_stack": modal_stack_snapshot(),
		"menu_state": menu_state_snapshot(),
		"ui_theme": ui_theme_snapshot(),
		"ui_layer_stack": ui_layer_stack_snapshot(),
		"context_menu": context_menu_snapshot(),
		"controls_hint": controls_hint_snapshot(),
		"debug_console": debug_console_snapshot(),
		"debug_panel": debug_panel_snapshot(),
		"hover": runtime_hover_snapshot(),
		"tooltip": hover_tooltip_snapshot(),
		"tooltip_render": tooltip_render_snapshot(),
		"hotbar_hit_test": hotbar_hit_test_snapshot(),
		"drag": drag_state_snapshot(),
		"drag_preview_render": drag_preview_render_snapshot(),
		"selection_debug": runtime_selection_debug_snapshot(),
		"action_presenter": world_action_presenter_snapshot(),
		"world_action_queue": world_action_queue_snapshot(),
		"ai_debug": ai_debug_snapshot(),
		"debug_overlay": debug_overlay_snapshot(),
		"audio_feedback": audio_feedback_snapshot(),
		"performance": runtime_performance_snapshot(),
		"skill_targeting": _skill_targeting_snapshot(),
		"player_command_authority_audit": player_command_authority_audit_snapshot(),
	}


func tooltip_render_snapshot() -> Dictionary:
	return last_tooltip_render_snapshot.duplicate(true)


func drag_preview_render_snapshot() -> Dictionary:
	return last_drag_preview_render_snapshot.duplicate(true)


func player_command_authority_audit_snapshot() -> Dictionary:
	var allowed_authority_kinds := [
		"submit_player_command",
		"core_service",
		"mixed",
		"submit_player_command_or_ui_state",
	]
	var entries: Array[Dictionary] = []
	var unknown_authority: Array[Dictionary] = []
	var missing_command_kind: Array[Dictionary] = []
	var missing_core_service: Array[Dictionary] = []
	var command_count := 0
	var core_service_count := 0
	var mixed_count := 0
	for entry in PLAYER_COMMAND_AUTHORITY_AUDIT:
		var item := entry.duplicate(true)
		var authority_kind := str(item.get("authority_kind", ""))
		var command_kind := str(item.get("command_kind", ""))
		var core_service := str(item.get("core_service", ""))
		item["authority_helper"] = str(item.get("authority_helper", ""))
		if not allowed_authority_kinds.has(authority_kind):
			unknown_authority.append(item.duplicate(true))
		if authority_kind == "submit_player_command" or authority_kind == "submit_player_command_or_ui_state":
			command_count += 1
			if command_kind.is_empty():
				missing_command_kind.append(item.duplicate(true))
		elif authority_kind == "core_service":
			core_service_count += 1
			if core_service.is_empty():
				missing_core_service.append(item.duplicate(true))
		elif authority_kind == "mixed":
			mixed_count += 1
			if command_kind.is_empty():
				missing_command_kind.append(item.duplicate(true))
			if core_service.is_empty():
				missing_core_service.append(item.duplicate(true))
		entries.append(item)
	var debug_console_audit: Dictionary = _debug_console_mutation_authority_audit()
	return {
		"audit_version": 2,
		"requires_simulation_authority": true,
		"business_entry_count": entries.size(),
		"submit_player_command_entry_count": command_count,
		"core_service_entry_count": core_service_count,
		"mixed_entry_count": mixed_count,
		"allowed_authority_kinds": allowed_authority_kinds,
		"unknown_authority_count": unknown_authority.size(),
		"missing_command_kind_count": missing_command_kind.size(),
		"missing_core_service_count": missing_core_service.size(),
		"unknown_authority": unknown_authority,
		"missing_command_kind": missing_command_kind,
		"missing_core_service": missing_core_service,
		"entries": entries,
		"debug_console_mutation_audit": debug_console_audit,
	}


func _debug_console_mutation_authority_audit() -> Dictionary:
	var mutating_commands: Array[Dictionary] = []
	var missing_permission: Array[Dictionary] = []
	var missing_runtime_flag: Array[Dictionary] = []
	var missing_usage: Array[Dictionary] = []
	var permission_snapshot: Dictionary = debug_runtime_controller.permission_snapshot(self)
	for command in debug_runtime_controller.command_schema():
		var command_data: Dictionary = _dictionary_or_empty(command).duplicate(true)
		if not bool(command_data.get("mutates_runtime", false)):
			continue
		var permission := str(command_data.get("permission", "")).strip_edges()
		var usage := str(command_data.get("usage", "")).strip_edges()
		var item := {
			"id": str(command_data.get("id", usage)),
			"usage": usage,
			"permission": permission,
			"mutates_runtime": true,
			"authority_kind": "debug_console_runtime_mutation",
			"runner": "DebugConsoleCommandRunner",
		}
		if permission != "debug_runtime_mutation":
			missing_permission.append(item.duplicate(true))
		if not bool(command_data.get("mutates_runtime", false)):
			missing_runtime_flag.append(item.duplicate(true))
		if usage.is_empty():
			missing_usage.append(item.duplicate(true))
		mutating_commands.append(item)
	return {
		"authority_kind": "debug_console_runtime_mutation",
		"runner": "DebugConsoleCommandRunner",
		"permission": "debug_runtime_mutation",
		"runtime_mutation_setting": str(permission_snapshot.get("runtime_mutation_setting", "")),
		"allow_runtime_mutation": bool(permission_snapshot.get("allow_runtime_mutation", false)),
		"mutating_command_count": mutating_commands.size(),
		"schema_mutating_command_count": int(permission_snapshot.get("mutating_command_count", 0)),
		"missing_permission_count": missing_permission.size(),
		"missing_runtime_flag_count": missing_runtime_flag.size(),
		"missing_usage_count": missing_usage.size(),
		"commands": mutating_commands,
		"missing_permission": missing_permission,
		"missing_runtime_flag": missing_runtime_flag,
		"missing_usage": missing_usage,
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


func runtime_world_time_snapshot() -> Dictionary:
	if simulation == null:
		return {
			"day": "monday",
			"minute_of_day": 540,
			"hour": 9,
			"minute": 0,
			"display_time": "09:00",
			"display_label": "monday 09:00",
		}
	var runtime_snapshot: Dictionary = simulation.snapshot()
	var world_time: Dictionary = _dictionary_or_empty(runtime_snapshot.get("world_time", {}))
	var minute_of_day: int = posmod(int(world_time.get("minute_of_day", 540)), 1440)
	var hour := int(minute_of_day / 60)
	var minute := minute_of_day % 60
	var display_time := "%02d:%02d" % [hour, minute]
	var day := str(world_time.get("day", "monday"))
	return {
		"day": day,
		"minute_of_day": minute_of_day,
		"hour": hour,
		"minute": minute,
		"display_time": display_time,
		"display_label": "%s %s" % [day, display_time],
	}


func world_action_presenter_snapshot() -> Dictionary:
	if world_action_presenter == null:
		return {"active": false, "kind": "missing"}
	return _dictionary_or_empty(world_action_presenter.call("snapshot"))


func world_action_queue_snapshot() -> Dictionary:
	var output: Dictionary = world_action_queue_state.duplicate(true)
	var presenter: Dictionary = world_action_presenter_snapshot()
	var presenter_active := bool(presenter.get("active", false))
	output["presenter_active"] = presenter_active
	output["presenter_kind"] = str(presenter.get("kind", ""))
	output["presenter_sequence"] = int(presenter.get("sequence", 0))
	output["input_blocked"] = _world_action_presenter_blocks_input()
	output["pending_ui"] = pending_world_action_ui.duplicate(true)
	output["pending_ui_active"] = not pending_world_action_ui.is_empty()
	output["pending_final_refresh"] = pending_world_action_final_refresh.duplicate(true)
	output["pending_final_refresh_active"] = not pending_world_action_final_refresh.is_empty()
	if str(output.get("state", "")) == "presenting" and not presenter_active and pending_world_action_ui.is_empty() and pending_world_action_final_refresh.is_empty():
		output["active"] = false
		output["state"] = "completed"
		world_action_queue_state = output.duplicate(true)
	return output


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
	if world_action_presenter == null or not world_action_presenter.has_method("finish_active_presentations"):
		return world_action_presenter_snapshot()
	var result: Dictionary = _dictionary_or_empty(world_action_presenter.call("finish_active_presentations"))
	_record_world_action_queue_finished(result)
	var applied_refresh := _apply_pending_world_action_final_refresh("presenter_finished")
	if not _apply_pending_world_action_ui("presenter_finished") and not applied_refresh:
		refresh_hud(current_interaction_prompt())
	return result


func _ai_debug_intent_summary(intent: Dictionary) -> Dictionary:
	var actor_id := int(intent.get("actor_id", 0))
	if actor_id <= 0:
		return {}
	var path: Array = _array_or_empty(intent.get("path", []))
	var target_actor_id := int(intent.get("target_actor_id", 0))
	var reason := str(intent.get("reason", ""))
	var intent_kind := str(intent.get("intent", ""))
	var target_tracking_state := str(intent.get("target_tracking_state", ""))
	var settlement_id := str(intent.get("settlement_id", ""))
	var route_id := str(intent.get("route_id", ""))
	var anchor_id := str(intent.get("anchor_id", ""))
	var smart_object_id := str(intent.get("smart_object_id", ""))
	var schedule_label := str(intent.get("schedule_label", ""))
	var planner: Dictionary = _dictionary_or_empty(intent.get("planner", {}))
	var planner_goal_id := str(planner.get("goal_id", intent.get("goal_id", "")))
	var planner_action_id := str(planner.get("action_id", intent.get("planner_action_id", "")))
	var life_status_id := _ai_life_status_id(intent_kind, planner_action_id, reason)
	var life_status_group := _ai_life_status_group(life_status_id, planner_action_id)
	var life_goal_kind := "settlement_life" if not settlement_id.is_empty() else ("combat" if target_actor_id > 0 else "idle")
	var goal_id := "none"
	if target_actor_id > 0:
		goal_id = "hostile_target"
	elif not planner_goal_id.is_empty():
		goal_id = planner_goal_id
	elif not route_id.is_empty():
		goal_id = route_id
	elif not smart_object_id.is_empty():
		goal_id = smart_object_id
	elif not anchor_id.is_empty():
		goal_id = anchor_id
	var goal := {
		"id": goal_id,
		"kind": life_goal_kind,
		"target_actor_id": target_actor_id,
		"target_grid": _dictionary_or_empty(intent.get("target_grid", {})).duplicate(true),
		"settlement_id": settlement_id,
		"route_id": route_id,
		"anchor_id": anchor_id,
		"smart_object_id": smart_object_id,
		"planner_score": float(planner.get("goal_score", intent.get("planner_goal_score", 0.0))),
		"planner_action_id": planner_action_id,
		"life_status_id": life_status_id,
		"life_status_group": life_status_group,
		"tracking_state": target_tracking_state,
		"lost": bool(intent.get("target_lost", false)),
		"lost_reason": str(intent.get("target_lost_reason", "")),
	}
	var action := {
		"id": planner_action_id if not planner_action_id.is_empty() else intent_kind,
		"kind": intent_kind,
		"reason": reason,
		"planned_intent": str(intent.get("planned_intent", "")),
		"planner_reason": str(planner.get("action_reason", intent.get("planner_action_reason", ""))),
		"planner_cost": float(planner.get("action_cost", 0.0)),
		"path_length": path.size(),
		"remaining_steps": int(intent.get("remaining_steps", 0)),
		"required_ap": float(intent.get("required_ap", 0.0)),
		"available_ap": float(intent.get("available_ap", intent.get("ap", 0.0))),
		"settlement_id": settlement_id,
		"route_id": route_id,
		"anchor_id": anchor_id,
		"smart_object_id": smart_object_id,
		"schedule_label": schedule_label,
		"life_status_id": life_status_id,
		"life_status_group": life_status_group,
	}
	var blackboard := {
		"target_actor_id": target_actor_id,
		"previous_target_actor_id": int(intent.get("previous_target_actor_id", 0)),
		"last_seen_target_actor_id": int(intent.get("last_seen_target_actor_id", 0)),
		"target_tracking_state": target_tracking_state,
		"target_lost": bool(intent.get("target_lost", false)),
		"target_lost_reason": str(intent.get("target_lost_reason", "")),
		"candidate_count": int(intent.get("candidate_count", 0)),
		"blocked_by_los_count": int(intent.get("blocked_by_los_count", 0)),
		"ammo_ready": bool(intent.get("ammo_ready", true)),
		"can_reload": bool(intent.get("can_reload", false)),
		"ap": float(intent.get("ap", 0.0)),
		"settlement_id": settlement_id,
		"route_id": route_id,
		"route_grid_count": _array_or_empty(intent.get("route_grids", [])).size(),
		"anchor_id": anchor_id,
		"smart_object_id": smart_object_id,
		"schedule_label": schedule_label,
		"planner_goal_id": planner_goal_id,
		"planner_action_id": planner_action_id,
		"life_status_id": life_status_id,
		"life_status_group": life_status_group,
		"planner_score_rule_ids": _array_or_empty(planner.get("score_rule_ids", [])).duplicate(true),
		"planner_facts": _dictionary_or_empty(planner.get("facts", {})).duplicate(true),
	}
	return {
		"actor_id": actor_id,
		"intent": intent_kind,
		"reason": reason,
		"settlement_id": settlement_id,
		"route_id": route_id,
		"route_grid_count": _array_or_empty(intent.get("route_grids", [])).size(),
		"anchor_id": anchor_id,
		"smart_object_id": smart_object_id,
		"schedule_label": schedule_label,
		"life_status_id": life_status_id,
		"life_status_group": life_status_group,
		"target_actor_id": target_actor_id,
		"target_grid": _dictionary_or_empty(intent.get("target_grid", {})).duplicate(true),
		"path_length": path.size(),
		"ap": float(intent.get("ap", 0.0)),
		"distance": float(intent.get("distance", -1.0)),
		"aggro_range": float(intent.get("aggro_range", 0.0)),
		"attack_range": float(intent.get("attack_range", 0.0)),
		"weapon_item_id": str(intent.get("weapon_item_id", "")),
		"ammo_type": str(intent.get("ammo_type", "")),
		"ammo_ready": bool(intent.get("ammo_ready", true)),
		"can_reload": bool(intent.get("can_reload", false)),
		"failure_reason": str(intent.get("failure_reason", intent.get("reason", ""))),
		"planner": planner.duplicate(true),
		"goal": goal,
		"action": action,
		"blackboard": blackboard,
		"target_tracking_state": target_tracking_state,
		"target_lost": bool(intent.get("target_lost", false)),
		"target_lost_reason": str(intent.get("target_lost_reason", "")),
	}


func _ai_life_status_id(intent_kind: String, planner_action_id: String, reason: String) -> String:
	if reason.begins_with("life_") and reason.ends_with("_unreachable"):
		return "blocked"
	match planner_action_id:
		"travel_to_duty_area", "travel_home", "travel_to_canteen", "travel_to_leisure":
			return "traveling"
		"patrol_route":
			return "patrolling"
		"stand_guard", "respond_alarm", "raise_alarm":
			return "guarding"
		"restock_meal_service":
			return "servicing"
		"treat_patients":
			return "treating"
		"eat_meal":
			return "eating"
		"sleep":
			return "resting"
		"relax":
			return "relaxing"
		"idle_safely":
			return "idle"
	match intent_kind:
		"follow_route":
			return "patrolling"
		"return_home":
			return "traveling"
		"use_smart_object":
			return "servicing"
	return ""


func _ai_life_status_group(state_id: String, planner_action_id: String) -> String:
	match state_id:
		"traveling", "patrolling":
			return "work"
		"guarding", "servicing", "treating":
			return "service"
		"eating", "resting", "relaxing":
			return "rest"
		"blocked":
			return "blocked"
	if state_id.is_empty() and planner_action_id.is_empty():
		return ""
	return "idle" if state_id == "idle" else "work"


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


func _tooltip_snapshot_base(source: Control, tooltip_source: Control, query_source: String, lifecycle_state: String) -> Dictionary:
	var viewport := get_viewport()
	var mouse_position := viewport.get_mouse_position() if viewport != null else Vector2.ZERO
	var viewport_size := viewport.get_visible_rect().size if viewport != null else Vector2.ZERO
	var resolved_source := tooltip_source if tooltip_source != null else source
	var button := resolved_source as BaseButton
	var source_rect := _control_rect_snapshot(resolved_source)
	var text := str(resolved_source.tooltip_text) if resolved_source != null else ""
	var visual := _tooltip_visual_snapshot(text, source_rect, mouse_position, viewport_size, lifecycle_state)
	return {
		"active": lifecycle_state == "active",
		"lifecycle_state": lifecycle_state,
		"query_source": query_source,
		"requested_source_path": str(source.get_path()) if source != null else "",
		"requested_source_name": str(source.name) if source != null else "",
		"requested_source_class": source.get_class() if source != null else "",
		"source_path": str(resolved_source.get_path()) if resolved_source != null else "",
		"source_name": str(resolved_source.name) if resolved_source != null else "",
		"source_class": resolved_source.get_class() if resolved_source != null else "",
		"owner_panel": _owner_panel_for_control(resolved_source) if resolved_source != null else "",
		"text": text,
		"text_length": text.length(),
		"screen_position": _vector2_snapshot(mouse_position),
		"viewport_size": _vector2_snapshot(viewport_size),
		"source_rect": source_rect,
		"requested_source_rect": _control_rect_snapshot(source),
		"visible": resolved_source != null and resolved_source.is_visible_in_tree(),
		"disabled": button != null and button.disabled,
		"mouse_filter": _mouse_filter_name(resolved_source.mouse_filter) if resolved_source != null else "",
		"mouse_filter_id": int(resolved_source.mouse_filter) if resolved_source != null else -1,
		"mouse_blocks_world": resolved_source != null and resolved_source.mouse_filter == Control.MOUSE_FILTER_STOP,
		"delay_policy": "godot_default",
		"delay_ms": -1,
		"visual": visual,
		"recommended_rect": _dictionary_or_empty(visual.get("recommended_rect", {})).duplicate(true),
	}


func _tooltip_visual_snapshot(text: String, source_rect: Dictionary, mouse_position: Vector2, viewport_size: Vector2, lifecycle_state: String) -> Dictionary:
	var max_width := 320.0
	var min_width := 160.0
	var padding_x := 10.0
	var padding_y := 7.0
	var line_height := 18.0
	var text_length: int = max(1, text.length())
	var estimated_text_width: float = min(max_width - padding_x * 2.0, max(80.0, float(min(text_length, 42)) * 7.2))
	var line_count := int(ceil(float(text_length) / 42.0))
	var estimated_width := clampf(estimated_text_width + padding_x * 2.0, min_width, max_width)
	var estimated_height: float = max(28.0, float(line_count) * line_height + padding_y * 2.0)
	var anchor := Vector2(mouse_position.x + 14.0, mouse_position.y + 18.0)
	if not source_rect.is_empty():
		anchor = Vector2(float(source_rect.get("x", mouse_position.x)), float(source_rect.get("y", mouse_position.y)) + float(source_rect.get("h", 0.0)) + 8.0)
	if viewport_size.x > 0.0 and anchor.x + estimated_width > viewport_size.x - 8.0:
		anchor.x = max(8.0, viewport_size.x - estimated_width - 8.0)
	if viewport_size.y > 0.0 and anchor.y + estimated_height > viewport_size.y - 8.0:
		if not source_rect.is_empty():
			anchor.y = max(8.0, float(source_rect.get("y", mouse_position.y)) - estimated_height - 8.0)
		else:
			anchor.y = max(8.0, viewport_size.y - estimated_height - 8.0)
	return {
		"style": "panel_container",
		"theme_type": "TooltipPanel",
		"label_theme_type": "TooltipLabel",
		"placement": "below_source",
		"viewport_avoidance": true,
		"non_blocking": true,
		"max_width": max_width,
		"min_width": min_width,
		"padding": {"x": padding_x, "y": padding_y},
		"line_height": line_height,
		"estimated_line_count": line_count,
		"background_color": "0e141bcc",
		"border_color": "63809cff",
		"corner_radius": 4,
		"lifecycle_state": lifecycle_state,
		"recommended_rect": {"x": anchor.x, "y": anchor.y, "w": estimated_width, "h": estimated_height},
	}


func _vector2_snapshot(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


func _control_rect_snapshot(control: Control) -> Dictionary:
	if control == null or not control.is_inside_tree():
		return {}
	var rect := control.get_global_rect()
	return {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y}


func _mouse_filter_name(mouse_filter: int) -> String:
	match mouse_filter:
		Control.MOUSE_FILTER_STOP:
			return "stop"
		Control.MOUSE_FILTER_PASS:
			return "pass"
		Control.MOUSE_FILTER_IGNORE:
			return "ignore"
	return "unknown"


func _tooltip_source_for_control(control: Control) -> Control:
	var current: Node = control
	while current != null:
		if current is Control:
			var control_node := current as Control
			if not str(control_node.tooltip_text).is_empty():
				return control_node
		current = current.get_parent()
	return null


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


func _drag_source_snapshot(drag_data: Dictionary, kind: String) -> Dictionary:
	var output := {
		"kind": kind,
		"owner_panel": _drag_source_owner(kind, drag_data),
		"source": str(drag_data.get("source", "")),
		"from_index": int(drag_data.get("from_index", drag_data.get("index", -1))),
	}
	if kind == "skill_hotbar":
		output["source"] = "skills"
	elif kind == "inventory_item" and str(output.get("source", "")).is_empty():
		output["source"] = "inventory"
	return output


func _drag_source_owner(kind: String, drag_data: Dictionary) -> String:
	match kind:
		"inventory_item":
			return "inventory"
		"skill_hotbar":
			return "skills"
		"trade_item", "trade_cart_entry":
			return "trade"
		"container_item":
			return "container"
	var source := str(drag_data.get("source", ""))
	return source if source in ["inventory", "skills", "trade", "container", "hud", "character"] else ""


func _drag_payload_snapshot(drag_data: Dictionary) -> Dictionary:
	var kind := str(drag_data.get("kind", ""))
	var item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
	var skill: Dictionary = _dictionary_or_empty(drag_data.get("skill", {}))
	match kind:
		"inventory_item", "trade_item", "container_item":
			return {
				"item_id": str(drag_data.get("item_id", item.get("item_id", ""))),
				"name": str(item.get("name", drag_data.get("item_id", ""))),
				"count": int(drag_data.get("count", item.get("count", 1))),
				"item_count": int(item.get("count", drag_data.get("count", 1))),
			}
		"skill_hotbar":
			return {
				"skill_id": str(drag_data.get("skill_id", skill.get("skill_id", ""))),
				"name": str(skill.get("name", drag_data.get("skill_id", ""))),
				"count": 1,
			}
		"trade_cart_entry":
			return {
				"index": int(drag_data.get("index", -1)),
				"name": str(drag_data.get("name", "")),
				"count": int(drag_data.get("count", 1)),
			}
	return {"count": int(drag_data.get("count", 0))}


func _drag_preview_snapshot(drag_data: Dictionary, payload: Dictionary) -> Dictionary:
	var text := str(drag_data.get("drag_preview_text", ""))
	if text.is_empty():
		match str(drag_data.get("kind", "")):
			"skill_hotbar":
				text = "%s -> 热栏" % str(payload.get("name", payload.get("skill_id", "")))
			_:
				var name := str(payload.get("name", payload.get("item_id", "")))
				var count := int(payload.get("count", 0))
				text = "%s x%d" % [name, count] if not name.is_empty() and count > 0 else name
	var viewport := get_viewport()
	var mouse_position := viewport.get_mouse_position() if viewport != null else Vector2.ZERO
	var viewport_size := viewport.get_visible_rect().size if viewport != null else Vector2.ZERO
	var estimated_size := _drag_preview_estimated_size(text)
	return {
		"text": text,
		"has_preview": not text.is_empty(),
		"screen_position": _vector2_snapshot(mouse_position),
		"viewport_size": _vector2_snapshot(viewport_size),
		"estimated_size": _vector2_snapshot(estimated_size),
		"anchor": _vector2_snapshot(Vector2(8.0, 8.0)),
		"lifecycle_state": "dragging",
		"threshold_policy": "godot_default",
		"threshold_px": -1,
	}


func _drag_preview_estimated_size(text: String) -> Vector2:
	if text.is_empty():
		return Vector2.ZERO
	return Vector2(maxf(48.0, float(text.length() * 8 + 16)), 24.0)


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
		_continue_crafting_queue_after_wait(result)
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
	var blocked: Dictionary = _player_command_rejection("use_skill")
	if not blocked.is_empty():
		return blocked
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
	latest_pending_crafting_result = {}
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
	latest_pending_crafting_result = {}
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
		latest_crafting_queue_result = {
			"active": false,
			"reason": "queue_cleared",
			"entry_count": 0,
			"total_count": 0,
		}
	return {
		"success": true,
		"entry_count": simulation.crafting_queue.size(),
		"crafting_queue": simulation.crafting_queue.duplicate(true),
	}


func crafting_queue_snapshot() -> Dictionary:
	if simulation == null:
		return {"entries": [], "entry_count": 0, "total_count": 0}
	return {
		"entries": simulation.crafting_queue.duplicate(true),
		"entry_count": simulation.crafting_queue.size(),
		"total_count": _crafting_queue_total_count(simulation.crafting_queue),
		"latest_result": latest_crafting_queue_result.duplicate(true),
	}


func _normalized_crafting_queue(entries: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for entry in _array_or_empty(entries):
		var data: Dictionary = _dictionary_or_empty(entry)
		var recipe_id := str(data.get("recipe_id", "")).strip_edges()
		if recipe_id.is_empty():
			continue
		output.append({
			"recipe_id": recipe_id,
			"count": max(1, int(data.get("count", 1))),
		})
	return output


func _crafting_queue_total_count(entries: Array) -> int:
	var total := 0
	for entry in entries:
		total += max(1, int(_dictionary_or_empty(entry).get("count", 1)))
	return total


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
		latest_pending_crafting_result = _pending_crafting_cancel_feedback_snapshot(result, reason)
		latest_crafting_queue_result = {
			"active": true,
			"reason": "pending_cancelled",
			"cancel_reason": reason,
			"remaining_queue_count": simulation.crafting_queue.size(),
			"remaining_total_count": _crafting_queue_total_count(simulation.crafting_queue),
		}
	elif bool(result.get("success", false)):
		latest_pending_crafting_result = {}
	refresh_inventory_panel()
	refresh_crafting_panel()
	refresh_skills_panel()
	return result


func _set_latest_crafting_queue_result(result: Dictionary, trigger: String) -> void:
	if result.is_empty():
		latest_crafting_queue_result = {}
		return
	latest_crafting_queue_result = _crafting_queue_feedback_snapshot(result, trigger)


func _crafting_queue_feedback_snapshot(result: Dictionary, trigger: String) -> Dictionary:
	var remaining_queue: Array = _array_or_empty(result.get("remaining_queue", []))
	var pending: Dictionary = _dictionary_or_empty(simulation.pending_crafting) if simulation != null else {}
	var summary := ""
	if bool(result.get("pending", false)):
		summary = "队列进行中: 已完成 %d 次，正在制作 %s x%d，剩余 %d 项" % [
			int(result.get("completed_count", 0)),
			str(pending.get("recipe_id", "")),
			max(1, int(pending.get("count", 1))) if not pending.is_empty() else 1,
			int(result.get("remaining_queue_count", remaining_queue.size())),
		]
	elif bool(result.get("success", false)):
		summary = "队列完成: 已制作 %d 次" % int(result.get("completed_count", 0))
	elif bool(result.get("partial_success", false)):
		summary = "队列部分完成: 已制作 %d 次，失败 %d 项" % [
			int(result.get("completed_count", 0)),
			int(result.get("failed_count", 0)),
		]
	else:
		summary = "队列失败: %s" % str(result.get("reason", "unknown"))
	return {
		"active": true,
		"trigger": trigger,
		"success": bool(result.get("success", false)),
		"partial_success": bool(result.get("partial_success", false)),
		"pending": bool(result.get("pending", false)),
		"started_pending": bool(result.get("started_pending", false)),
		"completed_count": int(result.get("completed_count", 0)),
		"failed_count": int(result.get("failed_count", 0)),
		"remaining_queue_count": int(result.get("remaining_queue_count", remaining_queue.size())),
		"remaining_total_count": _crafting_queue_total_count(remaining_queue),
		"queue_empty": bool(result.get("queue_empty", remaining_queue.is_empty())),
		"pending_recipe_id": str(pending.get("recipe_id", "")),
		"pending_count": max(1, int(pending.get("count", 1))) if not pending.is_empty() else 0,
		"summary": summary,
		"reason": str(result.get("reason", "")),
	}


func _pending_crafting_cancel_feedback_snapshot(result: Dictionary, reason: String) -> Dictionary:
	var cancelled: Dictionary = _dictionary_or_empty(result.get("pending_crafting", {}))
	if cancelled.is_empty():
		cancelled = _dictionary_or_empty(result.get("cancelled_crafting", {}))
	if cancelled.is_empty():
		return {}
	var required_ap: float = max(0.0, float(cancelled.get("required_ap", 0.0)))
	var progress_ap: float = clampf(float(cancelled.get("progress_ap", 0.0)), 0.0, required_ap)
	var remaining_ap: float = max(0.0, float(cancelled.get("remaining_ap", required_ap - progress_ap)))
	var recipe_id := str(cancelled.get("recipe_id", ""))
	return {
		"active": true,
		"reason": "pending_cancelled",
		"cancel_reason": reason,
		"recipe_id": recipe_id,
		"count": max(1, int(cancelled.get("count", 1))),
		"required_ap": required_ap,
		"progress_ap": progress_ap,
		"remaining_ap": remaining_ap,
		"progress_ratio": 0.0 if required_ap <= 0.0 else progress_ap / required_ap,
		"turn_policy": _dictionary_or_empty(result.get("turn_policy", {})).duplicate(true),
		"remaining_queue_count": simulation.crafting_queue.size() if simulation != null else 0,
		"remaining_total_count": _crafting_queue_total_count(simulation.crafting_queue) if simulation != null else 0,
		"pending_crafting": cancelled.duplicate(true),
		"summary": "已取消正在制作: %s x%d | 进度 %.1f/%.1f AP | 剩余 %.1f AP" % [
			recipe_id,
			max(1, int(cancelled.get("count", 1))),
			progress_ap,
			required_ap,
			remaining_ap,
		],
	}


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
	_present_world_action(command_result)
	_setup_runtime_input_controller()
	_refresh_fog_overlay()
	_refresh_debug_overlay()
	_configure_runtime_audio_layers()
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
	_setup_world_container()
	_render_world()
	_present_world_action(result)
	_setup_runtime_input_controller()
	_refresh_fog_overlay()
	_refresh_debug_overlay()
	_setup_panels()
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
		pending_world_action_ui = {
			"kind": "open_stage_panel",
			"panel_id": panel_id,
			"source": "interaction_result",
			"command_kind": _world_action_command_kind(result),
			"presenter_kind": str(world_action_presenter_snapshot().get("kind", "")),
			"queued_sequence": int(world_action_queue_state.get("sequence", 0)),
			"open_after": "presenter_finished",
			"refresh_all_panels": true,
			"prompt": _dictionary_or_empty(result.get("prompt", {})).duplicate(true),
		}
		world_action_queue_state["pending_ui"] = pending_world_action_ui.duplicate(true)
		world_action_queue_state["pending_ui_active"] = true
		return true
	_open_stage_panel_from_interaction(panel_id)
	return false


func _queue_or_refresh_all_panels_after_world_action(result: Dictionary) -> bool:
	if not _world_action_presenter_blocks_input():
		return false
	pending_world_action_ui = {
		"kind": "refresh_all_panels",
		"source": "interaction_result",
		"command_kind": _world_action_command_kind(result),
		"presenter_kind": str(world_action_presenter_snapshot().get("kind", "")),
		"queued_sequence": int(world_action_queue_state.get("sequence", 0)),
		"open_after": "presenter_finished",
		"refresh_all_panels": true,
		"prompt": _dictionary_or_empty(result.get("prompt", {})).duplicate(true),
	}
	world_action_queue_state["pending_ui"] = pending_world_action_ui.duplicate(true)
	world_action_queue_state["pending_ui_active"] = true
	return true


func _process_world_action_queue_completion() -> void:
	var queue_state := str(world_action_queue_state.get("state", ""))
	if pending_world_action_ui.is_empty() and pending_world_action_final_refresh.is_empty() and queue_state != "presenting":
		return
	if _world_action_presenter_blocks_input():
		return
	if queue_state == "presenting":
		_record_world_action_queue_finished(world_action_presenter_snapshot())
	_apply_pending_world_action_final_refresh("presenter_finished")
	_apply_pending_world_action_ui("presenter_finished")


func _queue_deferred_world_refresh(final_world_result: Dictionary, selected_prompt: Dictionary, command_result: Dictionary, source: String, render_world: bool = true) -> void:
	pending_world_action_final_refresh = {
		"kind": "final_world_refresh",
		"source": source,
		"command_kind": _world_action_command_kind(command_result),
		"presenter_kind": str(world_action_presenter_snapshot().get("kind", "")),
		"queued_sequence": int(world_action_queue_state.get("sequence", 0)),
		"refresh_after": "presenter_finished",
		"render_world": render_world,
		"refresh_all_panels": true,
		"prompt": selected_prompt.duplicate(true),
		"world_result": final_world_result.duplicate(true),
	}
	world_action_queue_state["current_strategy"] = "present_before_final_refresh"
	world_action_queue_state["refresh_timing"] = "presenter_before_final_world_render"
	world_action_queue_state["final_refresh_deferred"] = true
	world_action_queue_state["final_refresh_deferred_supported"] = true
	world_action_queue_state["pending_final_refresh"] = _deferred_world_refresh_public_snapshot(pending_world_action_final_refresh)
	world_action_queue_state["pending_final_refresh_active"] = true


func _apply_pending_world_action_final_refresh(trigger: String) -> bool:
	if pending_world_action_final_refresh.is_empty():
		return false
	var pending_refresh: Dictionary = pending_world_action_final_refresh.duplicate(true)
	pending_world_action_final_refresh.clear()
	var final_world_result: Dictionary = _dictionary_or_empty(pending_refresh.get("world_result", {}))
	if final_world_result.is_empty() or not bool(final_world_result.get("ok", false)):
		final_world_result = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
	_apply_world_result_without_present(final_world_result, bool(pending_refresh.get("render_world", true)))
	var applied: Dictionary = _deferred_world_refresh_public_snapshot(pending_refresh)
	applied["trigger"] = trigger
	applied["applied"] = true
	world_action_queue_state["pending_final_refresh"] = {}
	world_action_queue_state["pending_final_refresh_active"] = false
	world_action_queue_state["final_refresh_deferred"] = false
	world_action_queue_state["final_refresh_applied"] = true
	world_action_queue_state["applied_final_refresh"] = applied
	if bool(pending_refresh.get("refresh_all_panels", false)):
		refresh_all_panels(_dictionary_or_empty(pending_refresh.get("prompt", {})))
	return true


func _deferred_world_refresh_public_snapshot(source: Dictionary) -> Dictionary:
	return {
		"kind": str(source.get("kind", "final_world_refresh")),
		"source": str(source.get("source", "")),
		"command_kind": str(source.get("command_kind", "")),
		"presenter_kind": str(source.get("presenter_kind", "")),
		"queued_sequence": int(source.get("queued_sequence", 0)),
		"refresh_after": str(source.get("refresh_after", "")),
		"render_world": bool(source.get("render_world", true)),
		"refresh_all_panels": bool(source.get("refresh_all_panels", false)),
		"prompt": _dictionary_or_empty(source.get("prompt", {})).duplicate(true),
	}


func _apply_world_result_without_present(next_world_result: Dictionary, render_world: bool = true) -> void:
	world_result = next_world_result
	if not bool(world_result.get("ok", false)):
		push_error(str(world_result.get("error", "world refresh failed")))
		return
	_sync_observed_level_to_map()
	if simulation != null:
		var map: Dictionary = _dictionary_or_empty(world_result.get("map", {}))
		simulation.configure_map_interactions(_dictionary_or_empty(map.get("interaction_targets", {})))
	if interaction_controller != null:
		interaction_controller.world_result = world_result
	_setup_world_container()
	if render_world:
		_render_world()
		_setup_runtime_input_controller()
	elif runtime_input_controller != null:
		runtime_input_controller.world_result = world_result
	_refresh_fog_overlay()
	_refresh_debug_overlay()
	_configure_runtime_audio_layers()
	_setup_panels()


func _apply_pending_world_action_ui(trigger: String) -> bool:
	if pending_world_action_ui.is_empty():
		return false
	var pending_ui: Dictionary = pending_world_action_ui.duplicate(true)
	pending_world_action_ui.clear()
	if str(pending_ui.get("kind", "")) == "open_stage_panel":
		_open_stage_panel_from_interaction(str(pending_ui.get("panel_id", "")))
	if bool(pending_ui.get("refresh_all_panels", false)) or str(pending_ui.get("kind", "")) == "refresh_all_panels":
		refresh_all_panels(_dictionary_or_empty(pending_ui.get("prompt", {})))
	var applied: Dictionary = pending_ui.duplicate(true)
	applied["trigger"] = trigger
	applied["applied"] = true
	world_action_queue_state["pending_ui"] = {}
	world_action_queue_state["pending_ui_active"] = false
	world_action_queue_state["applied_deferred_ui"] = applied
	world_action_queue_state["deferred_ui_applied"] = true
	return true


func _present_world_action(command_result: Dictionary) -> void:
	if world_action_presenter == null or command_result.is_empty() or world_container == null:
		return
	var presenter_result: Dictionary = _dictionary_or_empty(world_action_presenter.call("present_result", self, world_container, command_result, world_result))
	_record_world_action_queue_presented(command_result, presenter_result)


func _record_world_action_queue_presented(command_result: Dictionary, presenter_result: Dictionary) -> void:
	world_action_queue_sequence += 1
	var presenter_active := bool(presenter_result.get("active", false))
	var presenter_kind := str(presenter_result.get("kind", "none"))
	var phase_order := [
		"command_result_received",
		"runtime_snapshot_applied",
		"presenter_started",
		"final_world_refresh_deferred",
	]
	world_action_queue_state = {
		"active": presenter_active,
		"state": "presenting" if presenter_active else "completed",
		"sequence": world_action_queue_sequence,
		"current_strategy": "present_before_final_refresh",
		"target_strategy": "present_before_final_refresh",
		"refresh_timing": "presenter_before_final_world_render",
		"next_strategy_step": "apply_final_world_refresh_after_presenter_finished",
		"phase_order": phase_order,
		"command_kind": _world_action_command_kind(command_result),
		"success": bool(command_result.get("success", false)),
		"reason": str(command_result.get("reason", "")),
		"event_count": _world_action_event_count(command_result),
		"presenter_kind": presenter_kind,
		"presenter_active": presenter_active,
		"presenter_sequence": int(presenter_result.get("sequence", 0)),
		"presenter_snapshot": presenter_result.duplicate(true),
		"final_refresh_deferred": false,
		"final_refresh_deferred_supported": true,
	}


func _record_world_action_queue_finished(finish_result: Dictionary) -> void:
	var output: Dictionary = world_action_queue_state.duplicate(true)
	output["active"] = false
	output["state"] = "completed"
	output["finished"] = true
	output["finish_reason"] = "fast_forwarded" if bool(finish_result.get("fast_forwarded", false)) else "presenter_idle"
	output["finish_result"] = finish_result.duplicate(true)
	output["presenter_active"] = bool(finish_result.get("active", false))
	output["presenter_kind"] = str(finish_result.get("kind", output.get("presenter_kind", "")))
	output["presenter_sequence"] = int(finish_result.get("sequence", output.get("presenter_sequence", 0)))
	world_action_queue_state = output


func _world_action_command_kind(command_result: Dictionary) -> String:
	var result: Dictionary = _dictionary_or_empty(command_result.get("result", {}))
	var kind := str(result.get("kind", ""))
	if not kind.is_empty():
		return kind
	kind = str(command_result.get("kind", ""))
	if not kind.is_empty():
		return kind
	var events: Array = _world_action_events_from_result(command_result)
	for event_value in events:
		var event: Dictionary = _dictionary_or_empty(event_value)
		match str(event.get("kind", "")):
			"movement_step", "actor_moved", "movement_queued", "movement_cancelled":
				return "move"
			"attack_resolved":
				return "attack"
			"interaction_succeeded", "interaction_queued", "interaction_cancelled":
				return "interact"
			"weapon_reloaded":
				return "reload"
	return ""


func _world_action_event_count(command_result: Dictionary) -> int:
	return _world_action_events_from_result(command_result).size()


func _world_action_events_from_result(command_result: Dictionary) -> Array:
	var direct_events := _array_or_empty(command_result.get("events", []))
	if not direct_events.is_empty():
		return direct_events
	var result: Dictionary = _dictionary_or_empty(command_result.get("result", {}))
	var nested_events := _array_or_empty(result.get("events", []))
	if not nested_events.is_empty():
		return nested_events
	var runtime_delta: Dictionary = _dictionary_or_empty(result.get("runtime_snapshot_delta", {}))
	return _array_or_empty(runtime_delta.get("events", []))


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
	var pending_crafting: Dictionary = _dictionary_or_empty(snapshot.get("pending_crafting", {}))
	if not pending_crafting.is_empty() and int(pending_crafting.get("actor_id", 0)) == actor_id:
		return {"kind": "pending_crafting", "state": pending_crafting.duplicate(true)}
	return {}


func _clear_focus_switch_ui_state() -> void:
	if runtime_input_controller != null and runtime_input_controller.has_method("clear_selection_state"):
		runtime_input_controller.clear_selection_state("focus_switch")
	if interaction_controller != null:
		interaction_controller.clear_selection("focus_switch")
	_close_hud_interaction_menu()


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
