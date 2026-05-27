extends Node3D

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")
const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")
const HudSnapshot = preload("res://scripts/ui/snapshots/hud_snapshot.gd")
const DialogueSnapshot = preload("res://scripts/ui/snapshots/dialogue_snapshot.gd")
const InventorySnapshot = preload("res://scripts/ui/snapshots/inventory_snapshot.gd")
const TradeSnapshot = preload("res://scripts/ui/snapshots/trade_snapshot.gd")
const ContainerSnapshot = preload("res://scripts/ui/snapshots/container_snapshot.gd")
const JournalSnapshot = preload("res://scripts/ui/snapshots/journal_snapshot.gd")
const PlayerInteractionController = preload("res://scripts/app/controllers/player_interaction_controller.gd")
const HUD_SCENE = preload("res://scenes/ui/hud.tscn")
const DIALOGUE_PANEL_SCENE = preload("res://scenes/ui/dialogue_panel.tscn")
const INVENTORY_PANEL_SCENE = preload("res://scenes/ui/inventory_panel.tscn")
const TRADE_PANEL_SCENE = preload("res://scenes/ui/trade_panel.tscn")
const CONTAINER_PANEL_SCENE = preload("res://scenes/ui/container_panel.tscn")
const JOURNAL_PANEL_SCENE = preload("res://scenes/ui/journal_panel.tscn")

var registry: ContentRegistry
var simulation: RefCounted
var world_result: Dictionary = {}
var interaction_controller: RefCounted
var world_container: Node3D
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
	_setup_hud()
	_setup_dialogue_panel()
	_setup_inventory_panel()
	_setup_trade_panel()
	_setup_container_panel()
	_setup_journal_panel()
	refresh_hud()
	refresh_dialogue_panel()
	refresh_inventory_panel()
	refresh_trade_panel()
	refresh_container_panel()
	refresh_journal_panel()
	print("Godot game root generated world: %s" % JSON.stringify(counts))


func refresh_hud(selected_prompt: Dictionary = {}) -> void:
	if hud == null or simulation == null:
		return
	if selected_prompt.is_empty():
		selected_prompt = current_interaction_prompt()
	var snapshot: Dictionary = HudSnapshot.new().build(simulation.snapshot(), world_result, selected_prompt)
	hud.apply_snapshot(snapshot)


func refresh_dialogue_panel() -> void:
	if dialogue_panel == null or simulation == null:
		return
	var snapshot: Dictionary = DialogueSnapshot.new(registry).build(simulation.snapshot())
	dialogue_panel.apply_snapshot(snapshot)


func refresh_inventory_panel() -> void:
	if inventory_panel == null or simulation == null:
		return
	var snapshot: Dictionary = InventorySnapshot.new(registry).build(simulation.snapshot())
	inventory_panel.apply_snapshot(snapshot)


func refresh_trade_panel() -> void:
	if trade_panel == null or simulation == null:
		return
	var snapshot: Dictionary = TradeSnapshot.new(registry).build(simulation.snapshot(), active_trade_target)
	trade_panel.apply_snapshot(snapshot)


func refresh_container_panel() -> void:
	if container_panel == null or simulation == null:
		return
	var snapshot: Dictionary = ContainerSnapshot.new(registry).build(simulation.snapshot())
	container_panel.apply_snapshot(snapshot)


func refresh_journal_panel() -> void:
	if journal_panel == null or simulation == null:
		return
	var snapshot: Dictionary = JournalSnapshot.new(registry).build(simulation.snapshot())
	journal_panel.apply_snapshot(snapshot)


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
	_update_trade_target_after_interaction(result, executed_target)
	world_result = interaction_controller.world_result
	# 地图切换或对象消费后需要重绘占位世界，保证 scene tree 与运行时快照一致。
	_setup_world_container()
	WorldSceneRenderer.new().render_world(world_container, world_result)
	_setup_hud()
	_setup_dialogue_panel()
	_setup_inventory_panel()
	_setup_trade_panel()
	_setup_container_panel()
	_setup_journal_panel()
	refresh_hud(_dictionary_or_empty(result.get("prompt", {})))
	refresh_dialogue_panel()
	refresh_inventory_panel()
	refresh_trade_panel()
	refresh_container_panel()
	refresh_journal_panel()
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


func _setup_world_container() -> void:
	if world_container != null:
		return
	world_container = Node3D.new()
	world_container.name = "WorldContainer"
	add_child(world_container)


func _setup_hud() -> void:
	if hud != null:
		return
	hud = HUD_SCENE.instantiate()
	hud.name = "Hud"
	add_child(hud)


func _setup_dialogue_panel() -> void:
	if dialogue_panel != null:
		return
	dialogue_panel = DIALOGUE_PANEL_SCENE.instantiate()
	dialogue_panel.name = "DialoguePanelRoot"
	add_child(dialogue_panel)


func _setup_inventory_panel() -> void:
	if inventory_panel != null:
		return
	inventory_panel = INVENTORY_PANEL_SCENE.instantiate()
	inventory_panel.name = "InventoryPanelRoot"
	add_child(inventory_panel)


func _setup_trade_panel() -> void:
	if trade_panel != null:
		return
	trade_panel = TRADE_PANEL_SCENE.instantiate()
	trade_panel.name = "TradePanelRoot"
	add_child(trade_panel)


func _setup_container_panel() -> void:
	if container_panel != null:
		return
	container_panel = CONTAINER_PANEL_SCENE.instantiate()
	container_panel.name = "ContainerPanelRoot"
	add_child(container_panel)


func _setup_journal_panel() -> void:
	if journal_panel != null:
		return
	journal_panel = JOURNAL_PANEL_SCENE.instantiate()
	journal_panel.name = "JournalPanelRoot"
	add_child(journal_panel)


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
