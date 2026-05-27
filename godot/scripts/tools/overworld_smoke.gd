extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const SaveService = preload("res://scripts/app/save_service.gd")


func _init() -> void:
	var registry := ContentRegistry.new()
	var load_result := registry.load_all()
	if load_result.has_errors():
		for error in load_result.errors:
			printerr(error)
		quit(1)
		return

	var simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var errors: Array[String] = _run_checks(simulation, registry)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("overworld_smoke passed:")
	print(JSON.stringify(_digest(simulation.snapshot()), "\t"))
	quit(0)


func _run_checks(simulation: RefCounted, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var overworld: Dictionary = registry.get_library("overworld")
	var initial: Dictionary = simulation.snapshot()
	if initial.get("active_location_id", "") != "survivor_outpost_01":
		errors.append("initial active location should be survivor_outpost_01")
	if initial.get("active_entry_point_id", "") != "default_entry":
		errors.append("initial active entry point should be default_entry")

	var locked_result: Dictionary = simulation.enter_location(1, "forest", overworld)
	if locked_result.get("reason", "") != "location_locked":
		errors.append("locked forest should reject enter_location")
	if simulation.active_map_id != "survivor_outpost_01":
		errors.append("locked enter_location should not change active map")

	var unlocked: bool = simulation.unlock_location("forest")
	if not unlocked:
		errors.append("forest unlock should report changed state")
	var entered: Dictionary = simulation.enter_location(1, "forest", overworld)
	if not bool(entered.get("success", false)):
		errors.append("unlocked forest enter failed: %s" % entered.get("reason", "unknown"))
	if simulation.active_map_id != "forest":
		errors.append("forest enter should update active map")
	if simulation.active_location_id != "forest":
		errors.append("forest enter should update active location")
	if simulation.active_entry_point_id != "default_entry":
		errors.append("forest enter should use default entry point")
	if _event_count(simulation.snapshot(), "location_entered") != 1:
		errors.append("forest enter should emit location_entered")

	var restored: Dictionary = _roundtrip_snapshot(simulation.snapshot())
	if restored.get("active_map_id", "") != "forest":
		errors.append("active map did not roundtrip")
	if restored.get("active_location_id", "") != "forest":
		errors.append("active location did not roundtrip")
	if restored.get("active_entry_point_id", "") != "default_entry":
		errors.append("active entry point did not roundtrip")
	return errors


func _roundtrip_snapshot(snapshot: Dictionary) -> Dictionary:
	var service := SaveService.new("user://overworld_smoke")
	service.delete_snapshot("roundtrip")
	service.save_snapshot("roundtrip", snapshot)
	var loaded: Dictionary = service.load_snapshot("roundtrip")
	service.delete_snapshot("roundtrip")
	return loaded.get("runtime_snapshot", {})


func _event_count(snapshot: Dictionary, kind: String) -> int:
	var count := 0
	for event in snapshot.get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			count += 1
	return count


func _digest(snapshot: Dictionary) -> Dictionary:
	return {
		"active_map_id": snapshot.get("active_map_id", ""),
		"active_location_id": snapshot.get("active_location_id", ""),
		"active_entry_point_id": snapshot.get("active_entry_point_id", ""),
		"unlocked_locations": snapshot.get("unlocked_locations", []),
		"event_count": snapshot.get("events", []).size(),
	}
