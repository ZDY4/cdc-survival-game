extends Node3D

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")
const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")
const HudSnapshot = preload("res://scripts/ui/snapshots/hud_snapshot.gd")
const DialogueSnapshot = preload("res://scripts/ui/snapshots/dialogue_snapshot.gd")
const InventorySnapshot = preload("res://scripts/ui/snapshots/inventory_snapshot.gd")
const PlayerInteractionController = preload("res://scripts/app/controllers/player_interaction_controller.gd")
const HUD_SCENE = preload("res://scenes/ui/hud.tscn")
const DIALOGUE_PANEL_SCENE = preload("res://scenes/ui/dialogue_panel.tscn")
const INVENTORY_PANEL_SCENE = preload("res://scenes/ui/inventory_panel.tscn")

var registry: ContentRegistry
var simulation: RefCounted
var world_result: Dictionary = {}
var interaction_controller: RefCounted
var world_container: Node3D
var hud: Control
var dialogue_panel: Control
var inventory_panel: Control


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
	refresh_hud()
	refresh_dialogue_panel()
	refresh_inventory_panel()
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
	var result: Dictionary = interaction_controller.execute_primary_interaction()
	world_result = interaction_controller.world_result
	# 地图切换或对象消费后需要重绘占位世界，保证 scene tree 与运行时快照一致。
	_setup_world_container()
	WorldSceneRenderer.new().render_world(world_container, world_result)
	_setup_hud()
	_setup_dialogue_panel()
	_setup_inventory_panel()
	refresh_hud(_dictionary_or_empty(result.get("prompt", {})))
	refresh_dialogue_panel()
	refresh_inventory_panel()
	return result


func current_interaction_prompt() -> Dictionary:
	if interaction_controller == null:
		return {}
	return interaction_controller.current_prompt()


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


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
