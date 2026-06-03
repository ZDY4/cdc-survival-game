extends Node3D

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")
const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")
const FogOverlayController = preload("res://scripts/world/fog_overlay_controller.gd")
const GamePanelController = preload("res://scripts/app/controllers/game_panel_controller.gd")
const GameRuntimeInputController = preload("res://scripts/app/controllers/game_runtime_input_controller.gd")
const PlayerInteractionController = preload("res://scripts/app/controllers/player_interaction_controller.gd")
const AUTO_TICK_INTERVAL_SEC := 0.45

var registry: ContentRegistry
var simulation: RefCounted
var world_result: Dictionary = {}
var interaction_controller: RefCounted
var runtime_input_controller: RefCounted
var panel_controller: RefCounted
var fog_overlay_controller: RefCounted = FogOverlayController.new()
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
var focused_actor_id: int = 0
var observed_map_level: int = 0


func _ready() -> void:
	registry = ContentRegistry.new()
	var load_result := registry.load_all()
	if load_result.has_errors():
		push_error("failed to load content for Godot game root")
		for error in load_result.errors:
			push_error(error)
		return

	var runtime_result: Dictionary = CoreRuntimeBootstrap.new(registry).build_new_game_runtime()
	simulation = runtime_result.get("simulation")
	var runtime_snapshot: Dictionary = runtime_result.get("snapshot", {})
	world_result = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(runtime_snapshot)
	if not bool(world_result.get("ok", false)):
		push_error(str(world_result.get("error", "world build failed")))
		return
	_sync_observed_level_to_map()

	interaction_controller = PlayerInteractionController.new(registry, simulation, world_result)
	_setup_world_container()
	var counts: Dictionary = WorldSceneRenderer.new().render_world(world_container, world_result)
	_setup_runtime_input_controller()
	_refresh_fog_overlay()
	_setup_panels()
	refresh_all_panels()
	print("Godot game root generated world: %s" % JSON.stringify(counts))


func _process(delta: float) -> void:
	if runtime_input_controller != null:
		runtime_input_controller.process(delta)
	_process_auto_tick(delta)


func _input(event: InputEvent) -> void:
	if runtime_input_controller != null:
		runtime_input_controller.input(event)


func _unhandled_input(event: InputEvent) -> void:
	if runtime_input_controller != null:
		runtime_input_controller.unhandled_input(event)


func refresh_hud(selected_prompt: Dictionary = {}) -> void:
	if panel_controller == null:
		return
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
	panel_controller.refresh_inventory_panel()


func refresh_trade_panel() -> void:
	if panel_controller == null:
		return
	if not _active_trade_target_available():
		active_trade_target = {}
	panel_controller.active_trade_target = active_trade_target
	panel_controller.refresh_trade_panel()


func refresh_container_panel() -> void:
	if panel_controller == null:
		return
	if simulation != null and not _active_container_available():
		simulation.close_container(1, "target_unavailable")
	panel_controller.refresh_container_panel()


func refresh_character_panel() -> void:
	if panel_controller == null:
		return
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
	if panel_controller != null and panel_controller.gameplay_input_blocked():
		return true
	return hud != null and hud.has_method("is_interaction_menu_open") and bool(hud.is_interaction_menu_open())


func gameplay_input_blocker_name() -> String:
	if hud != null and hud.has_method("is_interaction_menu_open") and bool(hud.is_interaction_menu_open()):
		return "interaction_menu"
	if panel_controller != null and panel_controller.has_method("gameplay_input_blocker_name"):
		return str(panel_controller.gameplay_input_blocker_name())
	return ""


func toggle_controls_hint() -> Dictionary:
	if hud == null or not hud.has_method("toggle_controls_hint"):
		return {"success": false, "reason": "hud_missing"}
	return hud.toggle_controls_hint()


func controls_hint_visible() -> bool:
	return hud != null and hud.has_method("is_controls_hint_visible") and bool(hud.is_controls_hint_visible())


func cycle_debug_overlay_mode() -> Dictionary:
	var modes := ["off", "walkable", "vision"]
	var index := modes.find(debug_overlay_mode)
	if index < 0:
		index = 0
	debug_overlay_mode = modes[(index + 1) % modes.size()]
	refresh_hud(current_interaction_prompt())
	return {"success": true, "mode": debug_overlay_mode}


func current_debug_overlay_mode() -> String:
	return debug_overlay_mode


func toggle_auto_tick() -> Dictionary:
	if has_active_dialogue() or gameplay_input_blocked_by_ui():
		return {"success": false, "reason": "ui_blocked", "enabled": auto_tick_enabled}
	auto_tick_enabled = not auto_tick_enabled
	auto_tick_elapsed_sec = 0.0
	refresh_hud(current_interaction_prompt())
	return {"success": true, "enabled": auto_tick_enabled}


func is_auto_tick_enabled() -> bool:
	return auto_tick_enabled


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
		"observe_mode": false,
		"observe_playback": false,
		"observe_speed": "x1",
		"map_level": map_level_snapshot(),
		"focused_actor": focused_actor_snapshot(),
		"ui_blocker": gameplay_input_blocker_name(),
	}


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
	if not busy_state.is_empty():
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
		active_trade_target = {}
		refresh_dialogue_panel()
		refresh_trade_panel()
		refresh_hud()
	return result


func close_active_container(reason: String = "closed") -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = simulation.close_container(1, reason)
	if bool(result.get("success", false)):
		refresh_container_panel()
		refresh_hud()
	return result


func close_active_ui(reason: String = "closed") -> Dictionary:
	if runtime_input_controller != null and runtime_input_controller.has_method("has_selection_state") and bool(runtime_input_controller.has_selection_state()):
		runtime_input_controller.clear_selection_state()
		return {"success": true, "closed": "selection"}
	if hud != null and hud.has_method("is_interaction_menu_open") and bool(hud.is_interaction_menu_open()):
		hud.hide_interaction_menu()
		return {"success": true, "closed": "interaction_menu"}
	if runtime_input_controller != null:
		runtime_input_controller.clear_selection_state()
	var dialogue_result := close_active_dialogue(reason)
	if bool(dialogue_result.get("success", false)):
		return {"success": true, "closed": "dialogue", "result": dialogue_result}
	if not active_trade_target.is_empty():
		close_trade_panel()
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
	var executed_target: Dictionary = interaction_controller.selected_target.duplicate(true)
	var result: Dictionary = interaction_controller.execute_primary_interaction()
	_apply_interaction_execution_result(result, executed_target)
	return result


func execute_interaction_option(option_id: String) -> Dictionary:
	if interaction_controller == null:
		return {"success": false, "reason": "interaction_controller_missing"}
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


func close_trade_panel() -> void:
	active_trade_target = {}
	refresh_trade_panel()


func choose_dialogue_option(option_ref: Variant) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = simulation.advance_dialogue(1, option_ref, registry.get_library("dialogues"))
	if bool(result.get("success", false)) and result.get("end_type", "") == "trade":
		active_trade_target = _dialogue_trade_target()
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
	if bool(result.get("success", false)) and result.get("end_type", "") == "trade":
		active_trade_target = _dialogue_trade_target()
	refresh_dialogue_panel()
	refresh_inventory_panel()
	refresh_trade_panel()
	refresh_journal_panel()
	refresh_skills_panel()
	refresh_crafting_panel()
	refresh_hud()
	return result


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
		WorldSceneRenderer.new().render_world(world_container, world_result)
		_setup_runtime_input_controller()
		_refresh_fog_overlay()
	refresh_all_panels(current_interaction_prompt())
	return result


func _process_auto_tick(delta: float) -> void:
	if not auto_tick_enabled:
		auto_tick_elapsed_sec = 0.0
		return
	auto_tick_elapsed_sec += delta
	if auto_tick_elapsed_sec < AUTO_TICK_INTERVAL_SEC:
		return
	auto_tick_elapsed_sec = 0.0
	_submit_auto_tick_wait()


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
		WorldSceneRenderer.new().render_world(world_container, world_result)
		_setup_runtime_input_controller()
		_refresh_fog_overlay()
		refresh_all_panels(current_interaction_prompt())
	return result


func press_enter_action() -> Dictionary:
	if has_active_dialogue():
		return advance_dialogue_without_choice()
	return {"success": false, "reason": "no_enter_action"}


func take_active_container_item(item_id: String, count: int = 1) -> Dictionary:
	var container_id: String = _active_container_id()
	if container_id.is_empty():
		return {"success": false, "reason": "active_container_missing"}
	var result: Dictionary = _submit_inventory_action({
		"action": "take_container",
		"container_id": container_id,
		"item_id": item_id,
		"count": count,
	})
	refresh_inventory_panel()
	refresh_container_panel()
	refresh_journal_panel()
	return result


func store_active_container_item(item_id: String, count: int = 1) -> Dictionary:
	var container_id: String = _active_container_id()
	if container_id.is_empty():
		return {"success": false, "reason": "active_container_missing"}
	var result: Dictionary = _submit_inventory_action({
		"action": "store_container",
		"container_id": container_id,
		"item_id": item_id,
		"count": count,
	})
	refresh_inventory_panel()
	refresh_container_panel()
	return result


func drop_player_item(item_id: String, count: int = 1) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = _submit_inventory_action({
		"action": "drop",
		"item_id": item_id,
		"count": count,
	})
	if bool(result.get("success", false)):
		_rebuild_world_after_runtime_change()
	else:
		refresh_inventory_panel()
	return result


func buy_active_trade_item(item_id: String, count: int = 1) -> Dictionary:
	var shop_id: String = _active_shop_id()
	if shop_id.is_empty():
		return {"success": false, "reason": "active_trade_missing"}
	var result: Dictionary = _submit_inventory_action({
		"action": "buy_shop",
		"shop_id": shop_id,
		"item_id": item_id,
		"count": count,
	})
	refresh_inventory_panel()
	refresh_trade_panel()
	return result


func sell_active_trade_item(item_id: String, count: int = 1) -> Dictionary:
	var shop_id: String = _active_shop_id()
	if shop_id.is_empty():
		return {"success": false, "reason": "active_trade_missing"}
	var result: Dictionary = _submit_inventory_action({
		"action": "sell_shop",
		"shop_id": shop_id,
		"item_id": item_id,
		"count": count,
	})
	refresh_inventory_panel()
	refresh_trade_panel()
	return result


func equip_player_item(item_id: String, slot_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = _submit_inventory_action({
		"action": "equip",
		"item_id": item_id,
		"slot_id": slot_id,
	})
	if bool(result.get("success", false)):
		_rebuild_world_after_runtime_change()
	else:
		refresh_inventory_panel()
	return result


func unequip_player_slot(slot_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = _submit_inventory_action({
		"action": "unequip",
		"slot_id": slot_id,
	})
	if bool(result.get("success", false)):
		_rebuild_world_after_runtime_change()
	else:
		refresh_inventory_panel()
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


func use_hotbar_slot(slot_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = simulation.submit_player_command({
		"kind": "use_skill",
		"actor_id": 1,
		"slot_id": slot_id,
		"skill_library": registry.get_library("skills"),
		"target": {"target_type": "self"},
	})
	refresh_hud()
	refresh_skills_panel()
	return result


func craft_player_recipe(recipe_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = simulation.submit_player_command({
		"kind": "craft",
		"actor_id": 1,
		"recipe_id": recipe_id,
		"recipe_library": registry.get_library("recipes"),
	})
	refresh_inventory_panel()
	refresh_crafting_panel()
	refresh_skills_panel()
	return result


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
	if interaction_controller != null:
		interaction_controller.world_result = world_result
	_setup_world_container()
	WorldSceneRenderer.new().render_world(world_container, world_result)
	_setup_runtime_input_controller()
	_refresh_fog_overlay()
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


func _refresh_fog_overlay() -> void:
	if simulation == null or world_result.is_empty():
		return
	fog_overlay = fog_overlay_controller.ensure_overlay(self, _dictionary_or_empty(world_result.get("map", {})), simulation.snapshot())


func _setup_panels() -> void:
	if panel_controller == null:
		panel_controller = GamePanelController.new(self, registry, simulation, world_result)
	panel_controller.update_world_result(world_result)
	panel_controller.active_trade_target = active_trade_target
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


func _apply_interaction_execution_result(result: Dictionary, executed_target: Dictionary) -> void:
	_update_trade_target_after_interaction(result, executed_target)
	world_result = interaction_controller.world_result
	_sync_observed_level_to_map()
	# 地图切换、对象消费、移动和击杀后需要重绘世界，保证 scene tree 与运行时快照一致。
	_setup_world_container()
	WorldSceneRenderer.new().render_world(world_container, world_result)
	_setup_runtime_input_controller()
	_refresh_fog_overlay()
	_setup_panels()
	refresh_all_panels(_dictionary_or_empty(result.get("prompt", {})))


func _submit_inventory_action(action: Dictionary) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var command: Dictionary = action.duplicate(true)
	command["kind"] = "inventory_action"
	command["actor_id"] = 1
	command["item_library"] = registry.get_library("items")
	return simulation.submit_player_command(command)


func _dialogue_trade_target() -> Dictionary:
	if active_trade_target.get("target_type", "") == "actor":
		return active_trade_target.duplicate(true)
	return {
		"target_type": "shop",
	}


func _active_trade_target_available() -> bool:
	if active_trade_target.is_empty() or simulation == null:
		return true
	if str(active_trade_target.get("target_type", "")) != "actor":
		return true
	var actor_id := int(active_trade_target.get("actor_id", 0))
	if actor_id <= 0:
		return false
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return false
	var shop_id := "%s_shop" % actor.definition_id
	return registry != null and registry.get_library("shops").has(shop_id)


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


func _active_container_id() -> String:
	if simulation == null:
		return ""
	var snapshot: Dictionary = simulation.snapshot()
	for actor in snapshot.get("actors", []):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if actor_data.get("kind", "") == "player":
			return str(actor_data.get("active_container_id", ""))
	return ""


func _active_container_available() -> bool:
	var container_id := _active_container_id()
	if container_id.is_empty() or simulation == null:
		return true
	return simulation.container_sessions.has(container_id)


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
		if not _is_player_side_actor(actor_data):
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


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
