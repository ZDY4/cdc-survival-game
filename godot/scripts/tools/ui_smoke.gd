extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")
const HudSnapshot = preload("res://scripts/ui/snapshots/hud_snapshot.gd")
const HUD_SCENE = preload("res://scenes/ui/hud.tscn")


func _init() -> void:
	var registry := ContentRegistry.new()
	var load_result := registry.load_all()
	if load_result.has_errors():
		for error in load_result.errors:
			printerr(error)
		quit(1)
		return

	var runtime_result: Dictionary = CoreRuntimeBootstrap.new(registry).build_new_game_runtime()
	var simulation: RefCounted = runtime_result.get("simulation")
	var world_result: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
	var pickup_prompt: Dictionary = simulation.query_interaction_options(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_pickup_medkit",
	})
	var pickup_result: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_pickup_medkit",
	})
	if not bool(pickup_result.get("success", false)):
		printerr("ui smoke setup pickup failed")
		quit(1)
		return

	var snapshot: Dictionary = HudSnapshot.new().build(simulation.snapshot(), world_result, pickup_prompt)
	var hud: Control = HUD_SCENE.instantiate()
	get_root().add_child(hud)
	hud.apply_snapshot(snapshot)

	var errors := _validate_hud(hud, snapshot)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("ui_smoke passed:")
	print(JSON.stringify({
		"world_line": hud.get_node("HudPanel/HudLines/WorldLine").text,
		"inventory_line": hud.get_node("HudPanel/HudLines/InventoryLine").text,
		"interaction_line": hud.get_node("HudPanel/HudLines/InteractionLine").text,
	}, "\t"))
	quit(0)


func _validate_hud(hud: Control, snapshot: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if hud.get_node_or_null("HudPanel/HudLines/WorldLine") == null:
		errors.append("missing world line")
	if not hud.get_node("HudPanel/HudLines/WorldLine").text.contains(str(snapshot.get("world", {}).get("map_id", ""))):
		errors.append("world line missing map id")
	if not hud.get_node("HudPanel/HudLines/InventoryLine").text.contains("1006"):
		errors.append("inventory line missing picked item")
	if not hud.get_node("HudPanel/HudLines/InteractionLine").text.contains("拾取"):
		errors.append("interaction line missing pickup option")
	return errors
