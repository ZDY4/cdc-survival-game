extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")


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
	var errors: Array[String] = _run_checks(simulation, registry)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("crafting_smoke passed:")
	print(JSON.stringify(_digest(simulation.snapshot()), "\t"))
	quit(0)


func _run_checks(simulation: RefCounted, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var recipes: Dictionary = registry.get_library("recipes")
	var player: RefCounted = simulation.actor_registry.get_actor(1)

	var missing_materials: Dictionary = simulation.craft_recipe(1, "recipe_bandage_basic", recipes)
	if bool(missing_materials.get("success", false)):
		errors.append("crafting should fail before materials are available")
	if missing_materials.get("reason", "") != "materials_insufficient":
		errors.append("crafting failure should report materials_insufficient")

	player.inventory["1011"] = 2
	var crafted: Dictionary = simulation.craft_recipe(1, "recipe_bandage_basic", recipes)
	if not bool(crafted.get("success", false)):
		errors.append("bandage crafting failed: %s" % crafted.get("reason", "unknown"))
	if int(player.inventory.get("1011", 0)) != 0:
		errors.append("crafting did not consume cloth material")
	if int(player.inventory.get("1006", 0)) != 2:
		errors.append("crafting did not add crafted bandage")
	if _event_count(simulation.snapshot(), "recipe_crafted") != 1:
		errors.append("crafting did not emit recipe_crafted event")
	if int(player.progression.get("total_xp_earned", 0)) != 5:
		errors.append("crafting experience reward should be added to progression")
	if _event_count(simulation.snapshot(), "experience_granted") != 1:
		errors.append("crafting experience reward should emit experience_granted")

	player.inventory["1011"] = 4
	var batch_events_before := _event_count(simulation.snapshot(), "recipe_crafted")
	var batch_xp_events_before := _event_count(simulation.snapshot(), "experience_granted")
	var batch: Dictionary = simulation.submit_player_command({
		"kind": "craft",
		"actor_id": 1,
		"recipe_id": "recipe_bandage_basic",
		"count": 2,
		"recipe_library": recipes,
	})
	if not bool(batch.get("success", false)):
		errors.append("batch bandage crafting failed: %s" % batch.get("reason", "unknown"))
	if int(batch.get("count", 0)) != 2:
		errors.append("batch crafting should report completed count")
	if int(batch.get("output_count", 0)) != 2:
		errors.append("batch crafting should aggregate output count")
	if int(player.inventory.get("1011", 0)) != 0:
		errors.append("batch crafting did not consume all selected cloth")
	if int(player.inventory.get("1006", 0)) != 4:
		errors.append("batch crafting did not add crafted bandages")
	if _event_count(simulation.snapshot(), "recipe_crafted") != batch_events_before + 2:
		errors.append("batch crafting should emit recipe_crafted for each craft")
	if int(player.progression.get("total_xp_earned", 0)) != 15:
		errors.append("batch crafting should apply experience for each craft")
	if _event_count(simulation.snapshot(), "experience_granted") != batch_xp_events_before + 2:
		errors.append("batch crafting experience should emit per craft")

	var tool_missing: Dictionary = simulation.craft_recipe(1, "recipe_knife_basic", recipes)
	if tool_missing.get("reason", "") != "missing_tools":
		errors.append("tool-gated recipe should report missing_tools before station check")
	var missing_tools: Array = tool_missing.get("missing_tools", [])
	if missing_tools.is_empty() or str(_dictionary_or_empty(missing_tools[0]).get("item_id", "")) != "1151":
		errors.append("tool-gated recipe should identify missing screwdriver")
	player.inventory["1151"] = 1
	var tool_available: Dictionary = simulation.craft_recipe(1, "recipe_knife_basic", recipes)
	if tool_available.get("reason", "") != "required_station_unsupported":
		errors.append("tool-gated recipe should advance to station check when tool is available")

	var station_result: Dictionary = simulation.craft_recipe(1, "recipe_first_aid_kit", recipes)
	if station_result.get("reason", "") != "required_station_unsupported":
		errors.append("station-gated recipe should report required_station_unsupported")
	return errors


func _event_count(snapshot: Dictionary, kind: String) -> int:
	var count := 0
	for event in snapshot.get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			count += 1
	return count


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _digest(snapshot: Dictionary) -> Dictionary:
	var player: Dictionary = _player_actor(snapshot)
	return {
		"event_count": snapshot.get("events", []).size(),
		"player_inventory": player.get("inventory", {}),
	}


func _player_actor(snapshot: Dictionary) -> Dictionary:
	for actor in snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return actor_data
	return {}
