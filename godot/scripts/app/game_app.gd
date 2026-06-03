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
var journal_panel: Control
var active_trade_target: Dictionary = {}


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


func refresh_journal_panel() -> void:
	if panel_controller == null:
		return
	panel_controller.refresh_journal_panel()


func refresh_all_panels(selected_prompt: Dictionary = {}) -> void:
	refresh_hud(selected_prompt)
	refresh_dialogue_panel()
	refresh_inventory_panel()
	refresh_trade_panel()
	refresh_container_panel()
	refresh_journal_panel()


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
	return result


func take_active_container_item(item_id: String, count: int = 1) -> Dictionary:
	var container_id: String = _active_container_id()
	if container_id.is_empty():
		return {"success": false, "reason": "active_container_missing"}
	var result: Dictionary = simulation.take_item_from_container(1, container_id, item_id, count, registry.get_library("items"))
	refresh_inventory_panel()
	refresh_container_panel()
	refresh_journal_panel()
	return result


func store_active_container_item(item_id: String, count: int = 1) -> Dictionary:
	var container_id: String = _active_container_id()
	if container_id.is_empty():
		return {"success": false, "reason": "active_container_missing"}
	var result: Dictionary = simulation.store_item_in_container(1, container_id, item_id, count, registry.get_library("items"))
	refresh_inventory_panel()
	refresh_container_panel()
	return result


func equip_player_item(item_id: String, slot_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = simulation.equip_item(1, item_id, slot_id, registry.get_library("items"))
	if bool(result.get("success", false)):
		_rebuild_world_after_runtime_change()
	else:
		refresh_inventory_panel()
	return result


func unequip_player_slot(slot_id: String) -> Dictionary:
	if simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var result: Dictionary = simulation.unequip_item(1, slot_id)
	if bool(result.get("success", false)):
		_rebuild_world_after_runtime_change()
	else:
		refresh_inventory_panel()
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
	journal_panel = panel_controller.journal_panel


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


func _dialogue_trade_target() -> Dictionary:
	if active_trade_target.get("target_type", "") == "actor":
		return active_trade_target.duplicate(true)
	return {
		"target_type": "actor",
		"actor_id": 0,
	}


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
