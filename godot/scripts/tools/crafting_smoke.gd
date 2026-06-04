extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")


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

	var recipe_locked: Dictionary = simulation.craft_recipe(1, "recipe_advanced_knife", recipes)
	if recipe_locked.get("reason", "") != "recipe_locked":
		errors.append("recipe-chain gated recipe should report recipe_locked before source recipe is crafted")
	var missing_unlocks: Array = recipe_locked.get("missing_unlock_conditions", [])
	if missing_unlocks.is_empty() or str(_dictionary_or_empty(missing_unlocks[0]).get("id", "")) != "recipe_knife_basic":
		errors.append("recipe-chain gated recipe should identify missing source recipe")

	var tool_missing: Dictionary = simulation.craft_recipe(1, "recipe_knife_basic", recipes)
	if tool_missing.get("reason", "") != "missing_tools":
		errors.append("tool-gated recipe should report missing_tools before station check")
	var missing_tools: Array = tool_missing.get("missing_tools", [])
	if missing_tools.is_empty() or str(_dictionary_or_empty(missing_tools[0]).get("item_id", "")) != "1151":
		errors.append("tool-gated recipe should identify missing screwdriver")
	player.inventory["1151"] = 1
	var tool_available: Dictionary = simulation.craft_recipe(1, "recipe_knife_basic", recipes)
	if tool_available.get("reason", "") != "missing_station":
		errors.append("tool-gated recipe should advance to station check when tool is available")

	var station_result: Dictionary = simulation.craft_recipe(1, "recipe_first_aid_kit", recipes)
	if station_result.get("reason", "") != "missing_station":
		errors.append("station-gated recipe should report missing_station without station context")
	var world_result: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
	var crafting_context := {
		"crafting_stations": _array_or_empty(_dictionary_or_empty(world_result.get("map", {})).get("crafting_stations", [])),
	}
	if _array_or_empty(crafting_context.get("crafting_stations", [])).is_empty():
		errors.append("map topology should expose crafting station definitions")
	player.grid_position = GridCoord.new(33, 0, 31)
	player.inventory["1105"] = 1
	player.inventory["1010"] = 1
	var station_craft: Dictionary = simulation.submit_player_command({
		"kind": "craft",
		"actor_id": 1,
		"recipe_id": "recipe_ammo_pistol",
		"recipe_library": recipes,
		"crafting_context": crafting_context,
	})
	if not bool(station_craft.get("success", false)):
		errors.append("station-gated recipe should craft near workbench: %s" % station_craft.get("reason", "unknown"))
	if int(player.inventory.get("1105", 0)) != 0 or int(player.inventory.get("1010", 0)) != 0:
		errors.append("station-gated craft should consume materials")
	if int(player.inventory.get("1009", 0)) != 20:
		errors.append("station-gated craft should add pistol ammo output")
	player.inventory["1010"] = 3
	player.inventory["1012"] = 1
	player.progression["learned_skills"]["crafting"] = 1
	var recipe_unlocked_events_before := _event_count(simulation.snapshot(), "recipe_unlocked")
	var basic_knife_craft: Dictionary = simulation.craft_recipe(1, "recipe_knife_basic", recipes, crafting_context)
	if not bool(basic_knife_craft.get("success", false)):
		errors.append("basic knife craft should unlock recipe-chain source: %s" % basic_knife_craft.get("reason", "unknown"))
	var crafted_recipes: Array = simulation.snapshot().get("crafted_recipes", [])
	if not crafted_recipes.has("recipe_knife_basic"):
		errors.append("crafted_recipes should include crafted source recipe")
	if _event_count(simulation.snapshot(), "recipe_unlocked") != recipe_unlocked_events_before + 1:
		errors.append("crafting a recipe for the first time should emit recipe_unlocked")
	var advanced_after_unlock: Dictionary = simulation.craft_recipe(1, "recipe_advanced_knife", recipes, crafting_context)
	if advanced_after_unlock.get("reason", "") == "recipe_locked":
		errors.append("advanced knife should pass recipe-chain unlock after basic knife is crafted")
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


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


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
