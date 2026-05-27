extends Node3D

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")
const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")
const HudSnapshot = preload("res://scripts/ui/snapshots/hud_snapshot.gd")
const HUD_SCENE = preload("res://scenes/ui/hud.tscn")

var registry: ContentRegistry
var simulation: RefCounted
var world_result: Dictionary = {}
var hud: Control


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

	var counts: Dictionary = WorldSceneRenderer.new().render_world(self, world_result)
	_setup_hud()
	refresh_hud()
	print("Godot game root generated world: %s" % JSON.stringify(counts))


func refresh_hud(selected_prompt: Dictionary = {}) -> void:
	if hud == null or simulation == null:
		return
	var snapshot: Dictionary = HudSnapshot.new().build(simulation.snapshot(), world_result, selected_prompt)
	hud.apply_snapshot(snapshot)


func _setup_hud() -> void:
	if hud != null:
		return
	hud = HUD_SCENE.instantiate()
	hud.name = "Hud"
	add_child(hud)
