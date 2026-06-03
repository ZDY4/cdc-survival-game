extends Node3D

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")
const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")
const FogOverlayController = preload("res://scripts/world/fog_overlay_controller.gd")
const GamePanelController = preload("res://scripts/app/controllers/game_panel_controller.gd")
const GameRuntimeInputController = preload("res://scripts/app/controllers/game_runtime_input_controller.gd")
const PlayerInteractionController = preload("res://scripts/app/controllers/player_interaction_controller.gd")

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
	panel_controller.active_trade_target = active_trade_target
	panel_controller.refresh_trade_panel()


func refresh_container_panel() -> void:
	if panel_controller == null:
		return
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
	return panel_controller != null and panel_controller.gameplay_input_blocked()


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
		"target_type": "actor",
		"actor_id": 0,
	}


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


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
