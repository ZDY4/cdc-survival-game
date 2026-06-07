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
	var batch_ap_before: float = player.ap
	var batch: Dictionary = simulation.submit_player_command({
		"kind": "craft",
		"actor_id": 1,
		"recipe_id": "recipe_bandage_basic",
		"count": 2,
		"recipe_library": recipes,
	})
	if not bool(batch.get("success", false)):
		errors.append("batch bandage crafting failed: %s" % batch.get("reason", "unknown"))
	_expect_turn_policy(errors, batch, "craft", false, "batch bandage crafting")
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
	if float(batch.get("ap_cost", 0.0)) != 2.0 or not is_equal_approx(player.ap, batch_ap_before - 2.0):
		errors.append("batch crafting should spend AP based on craft_time")
	player.inventory["1011"] = 2
	player.ap = 0.5
	var queued_events_before := _event_count(simulation.snapshot(), "crafting_queued")
	var crafted_events_before := _event_count(simulation.snapshot(), "recipe_crafted")
	var queued_craft: Dictionary = simulation.submit_player_command({
		"kind": "craft",
		"actor_id": 1,
		"recipe_id": "recipe_bandage_basic",
		"count": 1,
		"recipe_library": recipes,
		"topology": {},
	})
	if not bool(queued_craft.get("success", false)) or str(queued_craft.get("kind", "")) != "pending_crafting":
		errors.append("AP-short crafting should queue pending crafting: %s" % queued_craft)
	_expect_turn_policy(errors, queued_craft, "craft", false, "queued pending crafting")
	if str(queued_craft.get("reason", "")) != "ap_insufficient_craft_queued":
		errors.append("AP-short crafting should report queued reason")
	if int(player.inventory.get("1011", 0)) != 2:
		errors.append("queued crafting should not consume materials before completion")
	if int(player.inventory.get("1006", 0)) != 4:
		errors.append("queued crafting should not add output before completion")
	var pending_crafting: Dictionary = _dictionary_or_empty(simulation.snapshot().get("pending_crafting", {}))
	if pending_crafting.is_empty():
		errors.append("queued crafting should persist pending_crafting")
	if float(pending_crafting.get("progress_ap", 0.0)) <= 0.0 or float(pending_crafting.get("remaining_ap", 0.0)) <= 0.0:
		errors.append("pending crafting should expose progress and remaining AP: %s" % pending_crafting)
	if _event_count(simulation.snapshot(), "crafting_queued") <= queued_events_before:
		errors.append("queued crafting should emit crafting_queued")
	var resume_result: Dictionary = simulation.submit_player_command({
		"kind": "wait",
		"actor_id": 1,
		"topology": {},
	})
	if not bool(resume_result.get("success", false)):
		errors.append("wait should resume pending crafting: %s" % resume_result)
	if not simulation.snapshot().get("pending_crafting", {}).is_empty():
		errors.append("pending crafting should clear after enough AP is restored")
	if int(player.inventory.get("1011", 0)) != 0:
		errors.append("resumed crafting should consume queued materials")
	if int(player.inventory.get("1006", 0)) != 5:
		errors.append("resumed crafting should add queued output")
	if _event_count(simulation.snapshot(), "recipe_crafted") != crafted_events_before + 1:
		errors.append("resumed crafting should emit recipe_crafted once")
	if _event_count(simulation.snapshot(), "crafting_resumed") <= 0:
		errors.append("resumed crafting should emit crafting_resumed")
	player.ap = 6.0

	var recipe_locked: Dictionary = simulation.craft_recipe(1, "recipe_advanced_knife", recipes)
	if recipe_locked.get("reason", "") != "recipe_locked":
		errors.append("recipe-chain gated recipe should report recipe_locked before source recipe is crafted")
	var missing_unlocks: Array = recipe_locked.get("missing_unlock_conditions", [])
	if missing_unlocks.is_empty() or str(_dictionary_or_empty(missing_unlocks[0]).get("id", "")) != "recipe_knife_basic":
		errors.append("recipe-chain gated recipe should identify missing source recipe")
	var unlock_recipes: Dictionary = _unlock_smoke_recipes()
	var skill_locked: Dictionary = simulation.craft_recipe(1, "smoke_skill_unlock_recipe", unlock_recipes)
	if skill_locked.get("reason", "") != "recipe_locked":
		errors.append("skill unlock recipe should report recipe_locked before required skill")
	var skill_unlocks: Array = skill_locked.get("missing_unlock_conditions", [])
	if skill_unlocks.is_empty() or str(_dictionary_or_empty(skill_unlocks[0]).get("type", "")) != "skill":
		errors.append("skill unlock recipe should identify missing skill condition")
	player.progression["learned_skills"]["survival"] = 2
	var skill_unlocked: Dictionary = simulation.craft_recipe(1, "smoke_skill_unlock_recipe", unlock_recipes)
	if not bool(skill_unlocked.get("success", false)):
		errors.append("skill unlock recipe should craft after required skill: %s" % skill_unlocked.get("reason", "unknown"))
	var quest_locked: Dictionary = simulation.craft_recipe(1, "smoke_quest_unlock_recipe", unlock_recipes)
	if quest_locked.get("reason", "") != "recipe_locked":
		errors.append("quest unlock recipe should report recipe_locked before required quest")
	var quest_unlocks: Array = quest_locked.get("missing_unlock_conditions", [])
	if quest_unlocks.is_empty() or str(_dictionary_or_empty(quest_unlocks[0]).get("type", "")) != "quest":
		errors.append("quest unlock recipe should identify missing quest condition")
	simulation.completed_quests["tutorial_survive"] = true
	var quest_unlocked: Dictionary = simulation.craft_recipe(1, "smoke_quest_unlock_recipe", unlock_recipes)
	if not bool(quest_unlocked.get("success", false)):
		errors.append("quest unlock recipe should craft after required quest: %s" % quest_unlocked.get("reason", "unknown"))
	var item_locked: Dictionary = simulation.craft_recipe(1, "smoke_item_unlock_recipe", unlock_recipes)
	if item_locked.get("reason", "") != "recipe_locked":
		errors.append("item unlock recipe should report recipe_locked before required item")
	var item_unlocks: Array = item_locked.get("missing_unlock_conditions", [])
	if item_unlocks.is_empty() or str(_dictionary_or_empty(item_unlocks[0]).get("type", "")) != "item":
		errors.append("item unlock recipe should identify missing item condition")
	player.inventory["1104"] = 1
	var item_unlocked: Dictionary = simulation.craft_recipe(1, "smoke_item_unlock_recipe", unlock_recipes)
	if not bool(item_unlocked.get("success", false)):
		errors.append("item unlock recipe should craft after required item: %s" % item_unlocked.get("reason", "unknown"))
	player.inventory.erase("1104")
	var book_locked: Dictionary = simulation.craft_recipe(1, "smoke_book_unlock_recipe", unlock_recipes)
	if book_locked.get("reason", "") != "recipe_locked":
		errors.append("book unlock recipe should report recipe_locked before required book item")
	var book_unlocks: Array = book_locked.get("missing_unlock_conditions", [])
	if book_unlocks.is_empty() or str(_dictionary_or_empty(book_unlocks[0]).get("type", "")) != "book":
		errors.append("book unlock recipe should identify missing book condition")
	player.inventory["1031"] = 1
	var book_unlocked: Dictionary = simulation.craft_recipe(1, "smoke_book_unlock_recipe", unlock_recipes)
	if not bool(book_unlocked.get("success", false)):
		errors.append("book unlock recipe should craft after required book item: %s" % book_unlocked.get("reason", "unknown"))
	player.inventory.erase("1031")
	var flag_locked: Dictionary = simulation.craft_recipe(1, "smoke_world_flag_unlock_recipe", unlock_recipes)
	if flag_locked.get("reason", "") != "recipe_locked":
		errors.append("world flag unlock recipe should report recipe_locked before flag")
	var flag_unlocks: Array = flag_locked.get("missing_unlock_conditions", [])
	if flag_unlocks.is_empty() or str(_dictionary_or_empty(flag_unlocks[0]).get("type", "")) != "world_flag":
		errors.append("world flag unlock recipe should identify missing world_flag condition")
	simulation.world_flags["outpost_workshop_restored"] = true
	var flag_unlocked: Dictionary = simulation.craft_recipe(1, "smoke_world_flag_unlock_recipe", unlock_recipes)
	if not bool(flag_unlocked.get("success", false)):
		errors.append("world flag unlock recipe should craft after flag: %s" % flag_unlocked.get("reason", "unknown"))
	simulation.world_flags.erase("outpost_workshop_restored")

	var tool_missing: Dictionary = simulation.craft_recipe(1, "recipe_knife_basic", recipes)
	if tool_missing.get("reason", "") != "missing_tools":
		errors.append("tool-gated recipe should report missing_tools before station check")
	var missing_tools: Array = tool_missing.get("missing_tools", [])
	if missing_tools.is_empty() or str(_dictionary_or_empty(missing_tools[0]).get("item_id", "")) != "1151":
		errors.append("tool-gated recipe should identify missing screwdriver")
	var nearby_tool_available: Dictionary = simulation.craft_recipe(1, "recipe_knife_basic", recipes, {
		"nearby_tool_containers": [{
			"container_id": "smoke_tool_crate",
			"display_name": "工具箱",
			"inventory": [{"item_id": "1151", "count": 1}],
		}],
	})
	if nearby_tool_available.get("reason", "") != "missing_station":
		errors.append("tool-gated recipe should use nearby container tool before station check")
	if int(player.inventory.get("1151", 0)) > 0:
		errors.append("nearby container tool check should not move tool into player inventory")
	player.inventory["1151"] = 1
	var tool_available: Dictionary = simulation.craft_recipe(1, "recipe_knife_basic", recipes)
	if tool_available.get("reason", "") != "missing_station":
		errors.append("tool-gated recipe should advance to station check when tool is available")
	var consumable_tool_recipes: Dictionary = _consumable_tool_smoke_recipes()
	player.inventory.clear()
	player.inventory_order.clear()
	player.equipment.clear()
	player.inventory["1011"] = 2
	var missing_consumable_tool: Dictionary = simulation.craft_recipe(1, "smoke_consumes_tool_recipe", consumable_tool_recipes)
	if str(missing_consumable_tool.get("reason", "")) != "missing_tools":
		errors.append("consumable tool recipe should require tool before materials are consumed")
	if int(player.inventory.get("1011", 0)) != 2:
		errors.append("missing consumable tool craft should not consume materials")
	player.inventory["1151"] = 1
	player.inventory["1011"] = 0
	var failed_material_consumable_tool: Dictionary = simulation.craft_recipe(1, "smoke_consumes_tool_recipe", consumable_tool_recipes)
	if str(failed_material_consumable_tool.get("reason", "")) != "materials_insufficient":
		errors.append("failed consumable tool craft should report material shortage after tool availability")
	if int(player.inventory.get("1151", 0)) != 1:
		errors.append("failed consumable tool craft should not consume the tool")
	player.inventory["1011"] = 2
	var consumable_tool_event_before := _event_count(simulation.snapshot(), "recipe_crafted")
	var consumable_tool_craft: Dictionary = simulation.craft_recipe(1, "smoke_consumes_tool_recipe", consumable_tool_recipes)
	if not bool(consumable_tool_craft.get("success", false)):
		errors.append("consumable tool craft should succeed: %s" % consumable_tool_craft.get("reason", "unknown"))
	if int(player.inventory.get("1151", 0)) != 0:
		errors.append("successful consumable tool craft should consume the tool")
	if int(player.inventory.get("1011", 0)) != 0:
		errors.append("successful consumable tool craft should consume materials")
	if int(player.inventory.get("1006", 0)) != 1:
		errors.append("successful consumable tool craft should add output")
	var consumed_tools: Array = _array_or_empty(consumable_tool_craft.get("consumed_tools", []))
	if consumed_tools.is_empty() or str(_dictionary_or_empty(consumed_tools[0]).get("item_id", "")) != "1151":
		errors.append("successful consumable tool craft should return consumed tool payload")
	if _event_count(simulation.snapshot(), "recipe_crafted") != consumable_tool_event_before + 1:
		errors.append("successful consumable tool craft should emit recipe_crafted")
	var last_event: Dictionary = _last_event(simulation.snapshot(), "recipe_crafted")
	if _array_or_empty(_dictionary_or_empty(last_event.get("payload", {})).get("consumed_tools", [])).is_empty():
		errors.append("recipe_crafted event should expose consumed_tools")
	player.inventory.clear()
	player.inventory_order.clear()
	player.equipment.clear()
	player.inventory["1011"] = 2
	player.equipment["utility"] = "1151"
	var equipped_tool_craft: Dictionary = simulation.craft_recipe(1, "smoke_consumes_tool_recipe", consumable_tool_recipes)
	if not bool(equipped_tool_craft.get("success", false)):
		errors.append("equipped consumable tool craft should succeed: %s" % equipped_tool_craft.get("reason", "unknown"))
	if player.equipment.has("utility"):
		errors.append("equipped consumable tool craft should remove consumed equipment slot")
	var equipped_consumed_tools: Array = _array_or_empty(equipped_tool_craft.get("consumed_tools", []))
	if equipped_consumed_tools.is_empty() or str(_dictionary_or_empty(equipped_consumed_tools[0]).get("source", "")) != "equipment":
		errors.append("equipped consumable tool craft should report equipment source: %s" % equipped_consumed_tools)
	player.inventory.clear()
	player.inventory_order.clear()
	player.equipment.clear()
	player.inventory["1011"] = 2
	simulation.container_sessions["smoke_consumable_tool_crate"] = {
		"container_id": "smoke_consumable_tool_crate",
		"display_name": "消耗工具箱",
		"inventory": [{"item_id": "1151", "count": 1}],
	}
	var nearby_consumable_tool_craft: Dictionary = simulation.craft_recipe(1, "smoke_consumes_tool_recipe", consumable_tool_recipes, {
		"nearby_tool_containers": [{
			"container_id": "smoke_consumable_tool_crate",
			"display_name": "消耗工具箱",
			"inventory": [{"item_id": "1151", "count": 1}],
		}],
	})
	if not bool(nearby_consumable_tool_craft.get("success", false)):
		errors.append("nearby container consumable tool craft should succeed: %s" % nearby_consumable_tool_craft.get("reason", "unknown"))
	var tool_crate: Dictionary = _dictionary_or_empty(simulation.container_sessions.get("smoke_consumable_tool_crate", {}))
	if _inventory_entry_count(_array_or_empty(tool_crate.get("inventory", [])), "1151") != 0:
		errors.append("nearby container consumable tool craft should consume container tool")
	if int(player.inventory.get("1151", 0)) != 0:
		errors.append("nearby container consumable tool craft should not add tool to player inventory")
	var nearby_consumed_tools: Array = _array_or_empty(nearby_consumable_tool_craft.get("consumed_tools", []))
	var nearby_source_seen := false
	for consumed_tool in nearby_consumed_tools:
		var consumed_tool_data: Dictionary = _dictionary_or_empty(consumed_tool)
		if str(consumed_tool_data.get("source", "")) == "nearby_container" and str(consumed_tool_data.get("container_id", "")) == "smoke_consumable_tool_crate":
			nearby_source_seen = true
	if not nearby_source_seen:
		errors.append("nearby container consumable tool craft should report container source: %s" % nearby_consumed_tools)
	simulation.container_sessions.erase("smoke_consumable_tool_crate")
	var durable_tool_recipes: Dictionary = _durable_tool_smoke_recipes()
	player.inventory.clear()
	player.inventory_order.clear()
	player.equipment.clear()
	player.tool_durability.clear()
	player.inventory["1151"] = 1
	player.inventory["1011"] = 4
	player.tool_durability["1151"] = 5.0
	var durable_tool_craft: Dictionary = simulation.craft_recipe(1, "smoke_durable_tool_recipe", durable_tool_recipes)
	if not bool(durable_tool_craft.get("success", false)):
		errors.append("durable tool craft should succeed: %s" % durable_tool_craft.get("reason", "unknown"))
	if int(player.inventory.get("1151", 0)) != 1:
		errors.append("durable tool craft should not consume whole tool item")
	if not is_equal_approx(float(player.tool_durability.get("1151", 0.0)), 2.0):
		errors.append("durable tool craft should reduce tool durability to 2.0")
	var durable_consumed: Array = _array_or_empty(durable_tool_craft.get("consumed_tools", []))
	if durable_consumed.is_empty() or not is_equal_approx(float(_dictionary_or_empty(durable_consumed[0]).get("durability_cost", 0.0)), 3.0):
		errors.append("durable tool craft should expose durability consumption payload")
	var durable_event: Dictionary = _last_event(simulation.snapshot(), "recipe_crafted")
	var durable_event_tools: Array = _array_or_empty(_dictionary_or_empty(durable_event.get("payload", {})).get("consumed_tools", []))
	if durable_event_tools.is_empty() or not _dictionary_or_empty(durable_event_tools[0]).has("durability_after"):
		errors.append("durable tool recipe_crafted event should expose durability_after")
	player.inventory["1011"] = 2
	var low_durability_craft: Dictionary = simulation.craft_recipe(1, "smoke_durable_tool_recipe", durable_tool_recipes)
	if str(low_durability_craft.get("reason", "")) != "tool_durability_insufficient":
		errors.append("durable tool craft should reject when durability is insufficient")
	if int(player.inventory.get("1151", 0)) != 1 or int(player.inventory.get("1011", 0)) != 2:
		errors.append("durability rejected craft should not consume tool or material")
	player.inventory.clear()
	player.inventory_order.clear()
	player.equipment.clear()
	player.inventory["1151"] = 1
	player.inventory["1009"] = 10

	var station_result: Dictionary = simulation.craft_recipe(1, "recipe_first_aid_kit", recipes)
	if station_result.get("reason", "") != "missing_station":
		errors.append("station-gated recipe should report missing_station without station context")
	var world_result: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
	var crafting_context := {
		"crafting_stations": _array_or_empty(_dictionary_or_empty(world_result.get("map", {})).get("crafting_stations", [])),
	}
	if _array_or_empty(crafting_context.get("crafting_stations", [])).is_empty():
		errors.append("map topology should expose crafting station definitions")
	for station_id in ["workbench", "medical_station", "forge"]:
		if not _has_station(crafting_context, station_id):
			errors.append("map topology should expose %s crafting station" % station_id)
	player.grid_position = GridCoord.new(33, 0, 31)
	player.inventory["1105"] = 1
	player.inventory["1010"] = 1
	var gated_context: Dictionary = crafting_context.duplicate(true)
	gated_context["crafting_stations"] = _station_context_with_requirement(_array_or_empty(crafting_context.get("crafting_stations", [])), "workbench", {
		"required_world_flags": ["crafting_station_permission_smoke"],
	})
	gated_context["world_flags"] = simulation.world_flags.duplicate(true)
	var station_permission_result: Dictionary = simulation.submit_player_command({
		"kind": "craft",
		"actor_id": 1,
		"recipe_id": "recipe_ammo_pistol",
		"recipe_library": recipes,
		"crafting_context": gated_context,
	})
	if str(station_permission_result.get("reason", "")) != "station_world_flag_missing":
		errors.append("station-gated recipe should report station permission missing world flag")
	if int(player.inventory.get("1105", 0)) != 1 or int(player.inventory.get("1010", 0)) != 1:
		errors.append("station permission failure should not consume craft materials")
	simulation.world_flags["crafting_station_permission_smoke"] = true
	gated_context["world_flags"] = simulation.world_flags.duplicate(true)
	var station_craft: Dictionary = simulation.submit_player_command({
		"kind": "craft",
		"actor_id": 1,
		"recipe_id": "recipe_ammo_pistol",
		"recipe_library": recipes,
		"crafting_context": gated_context,
	})
	if not bool(station_craft.get("success", false)):
		errors.append("station-gated recipe should craft near workbench: %s" % station_craft.get("reason", "unknown"))
	simulation.world_flags.erase("crafting_station_permission_smoke")
	if int(player.inventory.get("1105", 0)) != 0 or int(player.inventory.get("1010", 0)) != 0:
		errors.append("station-gated craft should consume materials")
	if int(player.inventory.get("1009", 0)) != 20:
		errors.append("station-gated craft should add pistol ammo output")
	player.grid_position = GridCoord.new(32, 0, 10)
	player.inventory["1006"] = 2
	player.inventory["1031"] = 1
	player.progression["learned_skills"]["medical"] = 1
	var medical_station_result: Dictionary = simulation.craft_recipe(1, "recipe_antibody_serum", recipes, crafting_context)
	if medical_station_result.get("reason", "") == "missing_station":
		errors.append("medical station recipe should find nearby medical_station")
	player.grid_position = GridCoord.new(34, 0, 31)
	player.inventory["1106"] = 2
	player.inventory["1012"] = 2
	player.inventory["1144"] = 1
	player.inventory["1166"] = 1
	player.progression["learned_skills"]["crafting"] = 3
	player.progression["learned_skills"]["engineering"] = 2
	var had_basic_knife_unlock: bool = simulation.crafted_recipes.has("recipe_knife_basic")
	simulation.crafted_recipes["recipe_knife_basic"] = true
	var forge_station_result: Dictionary = simulation.craft_recipe(1, "recipe_advanced_knife", recipes, crafting_context)
	if not had_basic_knife_unlock:
		simulation.crafted_recipes.erase("recipe_knife_basic")
	if forge_station_result.get("reason", "") == "missing_station":
		errors.append("forge recipe should find nearby forge station")
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
	player.inventory["1008"] = 2
	player.inventory["1104"] = 0
	var deconstruct_events_before := _event_count(simulation.snapshot(), "item_deconstructed")
	player.ap = 0.0
	var insufficient_ap_deconstruct: Dictionary = simulation.submit_player_command({
		"kind": "inventory_action",
		"actor_id": 1,
		"action": "deconstruct",
		"item_id": "1008",
		"count": 2,
		"item_library": registry.get_library("items"),
	})
	if str(insufficient_ap_deconstruct.get("reason", "")) != "ap_insufficient_deconstruct":
		errors.append("deconstruct command should reject when AP is insufficient")
	if int(player.inventory.get("1008", 0)) != 2 or int(player.inventory.get("1104", 0)) != 0:
		errors.append("AP rejected deconstruct should not mutate inventory")
	if _event_count(simulation.snapshot(), "item_deconstructed") != deconstruct_events_before:
		errors.append("AP rejected deconstruct should not emit item_deconstructed")
	player.ap = 6.0
	var deconstruct_ap_before: float = player.ap
	var deconstructed: Dictionary = simulation.submit_player_command({
		"kind": "inventory_action",
		"actor_id": 1,
		"action": "deconstruct",
		"item_id": "1008",
		"count": 2,
		"item_library": registry.get_library("items"),
	})
	if not bool(deconstructed.get("success", false)):
		errors.append("deconstructing water bottles should succeed: %s" % deconstructed.get("reason", "unknown"))
	if int(player.inventory.get("1008", 0)) != 0:
		errors.append("deconstructing should consume selected source items")
	if int(player.inventory.get("1104", 0)) != 2:
		errors.append("deconstructing should add scaled yield items")
	if _event_count(simulation.snapshot(), "item_deconstructed") != deconstruct_events_before + 1:
		errors.append("deconstructing should emit item_deconstructed")
	if float(deconstructed.get("ap_cost", 0.0)) != 2.0 or not is_equal_approx(player.ap, deconstruct_ap_before - 2.0):
		errors.append("deconstructing should spend AP")
	var not_deconstructable: Dictionary = simulation.submit_player_command({
		"kind": "inventory_action",
		"actor_id": 1,
		"action": "deconstruct",
		"item_id": "1002",
		"count": 1,
		"item_library": registry.get_library("items"),
	})
	if str(not_deconstructable.get("reason", "")) != "item_not_deconstructable":
		errors.append("item without deconstruct yield should report item_not_deconstructable")
	var deconstruct_requirements_items: Dictionary = _deconstruct_requirement_smoke_items(registry.get_library("items"))
	player.inventory.clear()
	player.inventory_order.clear()
	player.equipment.clear()
	player.inventory["smoke_deconstruct_tool_item"] = 1
	var missing_deconstruct_tool: Dictionary = simulation.submit_player_command({
		"kind": "inventory_action",
		"actor_id": 1,
		"action": "deconstruct",
		"item_id": "smoke_deconstruct_tool_item",
		"count": 1,
		"item_library": deconstruct_requirements_items,
	})
	if str(missing_deconstruct_tool.get("reason", "")) != "missing_tools":
		errors.append("deconstruct should report missing_tools when required tool is absent")
	if int(player.inventory.get("smoke_deconstruct_tool_item", 0)) != 1:
		errors.append("missing deconstruct tool should not consume source item")
	player.inventory["1151"] = 1
	var missing_deconstruct_station: Dictionary = simulation.submit_player_command({
		"kind": "inventory_action",
		"actor_id": 1,
		"action": "deconstruct",
		"item_id": "smoke_deconstruct_tool_item",
		"count": 1,
		"item_library": deconstruct_requirements_items,
	})
	if str(missing_deconstruct_station.get("reason", "")) != "missing_station":
		errors.append("deconstruct should report missing_station after tool requirement passes")
	if int(player.inventory.get("smoke_deconstruct_tool_item", 0)) != 1:
		errors.append("missing deconstruct station should not consume source item")
	var deconstruct_with_context: Dictionary = simulation.submit_player_command({
		"kind": "inventory_action",
		"actor_id": 1,
		"action": "deconstruct",
		"item_id": "smoke_deconstruct_tool_item",
		"count": 1,
		"item_library": deconstruct_requirements_items,
		"crafting_context": {
			"crafting_stations": [{
				"station_id": "workbench",
				"display_name": "测试工作台",
				"range": 1,
				"anchor": player.grid_position.to_dictionary(),
				"cells": [player.grid_position.to_dictionary()],
			}],
		},
	})
	if not bool(deconstruct_with_context.get("success", false)):
		errors.append("deconstruct should succeed when tool and station requirements pass: %s" % deconstruct_with_context.get("reason", "unknown"))
	if int(player.inventory.get("smoke_deconstruct_tool_item", 0)) != 0:
		errors.append("successful requirement-gated deconstruct should consume source item")
	if int(player.inventory.get("1104", 0)) != 1:
		errors.append("successful requirement-gated deconstruct should add yield")
	var consumable_deconstruct_items: Dictionary = _consumable_deconstruct_tool_smoke_items(registry.get_library("items"))
	player.inventory.clear()
	player.inventory_order.clear()
	player.equipment.clear()
	player.inventory["smoke_deconstruct_consumable_tool_item"] = 1
	player.equipment["tool"] = "1151"
	var missing_consumable_deconstruct_tool: Dictionary = simulation.submit_player_command({
		"kind": "inventory_action",
		"actor_id": 1,
		"action": "deconstruct",
		"item_id": "smoke_deconstruct_consumable_tool_item",
		"count": 1,
		"item_library": consumable_deconstruct_items,
	})
	if str(missing_consumable_deconstruct_tool.get("reason", "")) != "missing_consumable_tools":
		errors.append("deconstruct should require consumable tool from inventory before consuming source")
	if int(player.inventory.get("smoke_deconstruct_consumable_tool_item", 0)) != 1:
		errors.append("missing consumable deconstruct tool should not consume source item")
	player.equipment.clear()
	player.inventory["1151"] = 1
	var event_count_before_deconstruct: int = _event_count(simulation.snapshot(), "item_deconstructed")
	var consumable_deconstruct_result: Dictionary = simulation.submit_player_command({
		"kind": "inventory_action",
		"actor_id": 1,
		"action": "deconstruct",
		"item_id": "smoke_deconstruct_consumable_tool_item",
		"count": 1,
		"item_library": consumable_deconstruct_items,
	})
	if not bool(consumable_deconstruct_result.get("success", false)):
		errors.append("deconstruct with consumable tool in inventory should succeed: %s" % consumable_deconstruct_result.get("reason", "unknown"))
	if int(player.inventory.get("1151", 0)) != 0:
		errors.append("successful consumable-tool deconstruct should consume tool from inventory")
	if _array_or_empty(consumable_deconstruct_result.get("consumed_tools", [])).is_empty():
		errors.append("deconstruct result should expose consumed_tools")
	var deconstruct_events: Array = _events_of_kind(simulation.snapshot(), "item_deconstructed")
	if deconstruct_events.size() <= event_count_before_deconstruct:
		errors.append("consumable-tool deconstruct should emit item_deconstructed event")
	elif _array_or_empty(_dictionary_or_empty(_dictionary_or_empty(deconstruct_events[deconstruct_events.size() - 1]).get("payload", {})).get("consumed_tools", [])).is_empty():
		errors.append("item_deconstructed event should expose consumed_tools")
	var durable_deconstruct_items: Dictionary = _durable_deconstruct_tool_smoke_items(registry.get_library("items"))
	player.inventory.clear()
	player.inventory_order.clear()
	player.equipment.clear()
	player.tool_durability.clear()
	player.inventory["smoke_deconstruct_durable_tool_item"] = 2
	player.inventory["1151"] = 1
	player.tool_durability["1151"] = 5.0
	var durable_deconstruct_result: Dictionary = simulation.submit_player_command({
		"kind": "inventory_action",
		"actor_id": 1,
		"action": "deconstruct",
		"item_id": "smoke_deconstruct_durable_tool_item",
		"count": 1,
		"item_library": durable_deconstruct_items,
	})
	if not bool(durable_deconstruct_result.get("success", false)):
		errors.append("deconstruct with durable tool should succeed: %s" % durable_deconstruct_result.get("reason", "unknown"))
	if int(player.inventory.get("1151", 0)) != 1:
		errors.append("durable deconstruct should not consume whole tool item")
	if not is_equal_approx(float(player.tool_durability.get("1151", 0.0)), 2.0):
		errors.append("durable deconstruct should reduce tool durability to 2.0")
	var durable_deconstruct_tools: Array = _array_or_empty(durable_deconstruct_result.get("consumed_tools", []))
	if durable_deconstruct_tools.is_empty() or not _dictionary_or_empty(durable_deconstruct_tools[0]).has("durability_after"):
		errors.append("durable deconstruct should expose durability consumption payload")
	var durable_deconstruct_event: Dictionary = _last_event(simulation.snapshot(), "item_deconstructed")
	var durable_deconstruct_event_tools: Array = _array_or_empty(_dictionary_or_empty(durable_deconstruct_event.get("payload", {})).get("consumed_tools", []))
	if durable_deconstruct_event_tools.is_empty() or not is_equal_approx(float(_dictionary_or_empty(durable_deconstruct_event_tools[0]).get("durability_cost", 0.0)), 3.0):
		errors.append("durable deconstruct event should expose durability_cost")
	var low_durability_deconstruct: Dictionary = simulation.submit_player_command({
		"kind": "inventory_action",
		"actor_id": 1,
		"action": "deconstruct",
		"item_id": "smoke_deconstruct_durable_tool_item",
		"count": 1,
		"item_library": durable_deconstruct_items,
	})
	if str(low_durability_deconstruct.get("reason", "")) != "tool_durability_insufficient":
		errors.append("durable deconstruct should reject when durability is insufficient")
	if int(player.inventory.get("smoke_deconstruct_durable_tool_item", 0)) != 1 or int(player.inventory.get("1151", 0)) != 1:
		errors.append("durability rejected deconstruct should not consume source or tool")
	player.inventory.clear()
	player.inventory_order.clear()
	player.equipment.clear()
	player.tool_durability.clear()
	player.ap = 6.0
	player.inventory["1003"] = 50
	player.inventory["1011"] = 10
	var overweight_craft: Dictionary = simulation.craft_recipe(1, "recipe_bandage_basic", recipes)
	if str(overweight_craft.get("reason", "")) != "inventory_over_capacity":
		errors.append("overweight crafting should report inventory_over_capacity")
	if int(player.inventory.get("1011", 0)) != 10:
		errors.append("failed overweight craft should not consume materials")
	if int(player.inventory.get("1006", 0)) != 0:
		errors.append("failed overweight craft should not add output")
	player.inventory.clear()
	player.inventory_order.clear()
	player.equipment.clear()
	player.ap = 6.0
	player.inventory["1003"] = 49
	player.inventory["1004"] = 2
	player.inventory["1010"] = 0
	var overweight_deconstruct: Dictionary = simulation.submit_player_command({
		"kind": "inventory_action",
		"actor_id": 1,
		"action": "deconstruct",
		"item_id": "1004",
		"count": 2,
		"item_library": registry.get_library("items"),
	})
	if str(overweight_deconstruct.get("reason", "")) != "inventory_over_capacity":
		errors.append("overweight deconstruct should report inventory_over_capacity")
	if int(player.inventory.get("1004", 0)) != 2:
		errors.append("failed overweight deconstruct should keep source items")
	if int(player.inventory.get("1010", 0)) != 0:
		errors.append("failed overweight deconstruct should not add yield")
	return errors


func _unlock_smoke_recipes() -> Dictionary:
	return {
		"smoke_skill_unlock_recipe": {
			"data": {
				"id": "smoke_skill_unlock_recipe",
				"name": "技能解锁测试配方",
				"is_default_unlocked": false,
				"unlock_conditions": [{"type": "skill", "id": "survival", "level": 2}],
				"required_tools": [],
				"required_station": "none",
				"skill_requirements": {},
				"materials": [],
				"output": {"item_id": "1006", "count": 1},
				"craft_time": 0.0,
				"experience_reward": 0,
			},
		},
		"smoke_quest_unlock_recipe": {
			"data": {
				"id": "smoke_quest_unlock_recipe",
				"name": "任务解锁测试配方",
				"is_default_unlocked": false,
				"unlock_conditions": [{"type": "quest", "id": "tutorial_survive"}],
				"required_tools": [],
				"required_station": "none",
				"skill_requirements": {},
				"materials": [],
				"output": {"item_id": "1006", "count": 1},
				"craft_time": 0.0,
				"experience_reward": 0,
			},
		},
		"smoke_item_unlock_recipe": {
			"data": {
				"id": "smoke_item_unlock_recipe",
				"name": "物品解锁测试配方",
				"is_default_unlocked": false,
				"unlock_conditions": [{"type": "item", "id": "1104", "count": 1}],
				"required_tools": [],
				"required_station": "none",
				"skill_requirements": {},
				"materials": [],
				"output": {"item_id": "1006", "count": 1},
				"craft_time": 0.0,
				"experience_reward": 0,
			},
		},
		"smoke_book_unlock_recipe": {
			"data": {
				"id": "smoke_book_unlock_recipe",
				"name": "书籍解锁测试配方",
				"is_default_unlocked": false,
				"unlock_conditions": [{"type": "book", "id": "1031"}],
				"required_tools": [],
				"required_station": "none",
				"skill_requirements": {},
				"materials": [],
				"output": {"item_id": "1006", "count": 1},
				"craft_time": 0.0,
				"experience_reward": 0,
			},
		},
		"smoke_world_flag_unlock_recipe": {
			"data": {
				"id": "smoke_world_flag_unlock_recipe",
				"name": "世界状态解锁测试配方",
				"is_default_unlocked": false,
				"unlock_conditions": [{"type": "world_flag", "id": "outpost_workshop_restored"}],
				"required_tools": [],
				"required_station": "none",
				"skill_requirements": {},
				"materials": [],
				"output": {"item_id": "1006", "count": 1},
				"craft_time": 0.0,
				"experience_reward": 0,
			},
		},
	}


func _consumable_tool_smoke_recipes() -> Dictionary:
	return {
		"smoke_consumes_tool_recipe": {
			"data": {
				"id": "smoke_consumes_tool_recipe",
				"name": "消耗工具测试配方",
				"is_default_unlocked": true,
				"unlock_conditions": [],
				"required_tools": [{"item_id": "1151", "consume_on_craft": true, "consume_count": 1}],
				"required_station": "none",
				"skill_requirements": {},
				"materials": [{"item_id": "1011", "count": 2}],
				"output": {"item_id": "1006", "count": 1},
				"craft_time": 0.0,
				"experience_reward": 0,
			},
		},
	}


func _durable_tool_smoke_recipes() -> Dictionary:
	return {
		"smoke_durable_tool_recipe": {
			"data": {
				"id": "smoke_durable_tool_recipe",
				"name": "工具耐久测试配方",
				"is_default_unlocked": true,
				"unlock_conditions": [],
				"required_tools": [{"item_id": "1151", "durability_cost": 3.0}],
				"required_station": "none",
				"skill_requirements": {},
				"materials": [{"item_id": "1011", "count": 2}],
				"output": {"item_id": "1006", "count": 1},
				"craft_time": 0.0,
				"experience_reward": 0,
			},
		},
	}


func _deconstruct_requirement_smoke_items(base_items: Dictionary) -> Dictionary:
	var output := base_items.duplicate(true)
	output["smoke_deconstruct_tool_item"] = {
		"data": {
			"id": "smoke_deconstruct_tool_item",
			"name": "拆解要求测试物品",
			"weight": 0.1,
			"fragments": [{
				"kind": "crafting",
				"deconstruct_required_tools": ["1151"],
				"deconstruct_required_station": "workbench",
				"deconstruct_yield": [{"item_id": "1104", "count": 1}],
			}],
		},
	}
	return output


func _consumable_deconstruct_tool_smoke_items(base_items: Dictionary) -> Dictionary:
	var output := base_items.duplicate(true)
	output["smoke_deconstruct_consumable_tool_item"] = {
		"data": {
			"id": "smoke_deconstruct_consumable_tool_item",
			"name": "消耗拆解工具测试物品",
			"weight": 0.1,
			"fragments": [{
				"kind": "crafting",
				"deconstruct_required_tools": [{"item_id": "1151", "consume_on_deconstruct": true, "consume_count": 1}],
				"deconstruct_yield": [{"item_id": "1104", "count": 1}],
			}],
		},
	}
	return output


func _durable_deconstruct_tool_smoke_items(base_items: Dictionary) -> Dictionary:
	var output := base_items.duplicate(true)
	output["smoke_deconstruct_durable_tool_item"] = {
		"path": "<smoke>",
		"data": {
			"id": "smoke_deconstruct_durable_tool_item",
			"name": "耐久拆解测试物品",
			"description": "用于验证拆解工具耐久消耗",
			"value": 1,
			"weight": 0.1,
			"fragments": [{
				"kind": "crafting",
				"deconstruct_required_tools": [{"item_id": "1151", "durability_cost": 3.0}],
				"deconstruct_yield": [{"item_id": "1104", "count": 1}],
			}],
		},
	}
	return output


func _event_count(snapshot: Dictionary, kind: String) -> int:
	var count := 0
	for event in snapshot.get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			count += 1
	return count


func _events_of_kind(snapshot: Dictionary, kind: String) -> Array:
	var output: Array = []
	for event in snapshot.get("events", []):
		var event_data: Dictionary = _dictionary_or_empty(event)
		if str(event_data.get("kind", "")) == kind:
			output.append(event_data)
	return output


func _last_event(snapshot: Dictionary, kind: String) -> Dictionary:
	var events: Array = _array_or_empty(snapshot.get("events", []))
	for index in range(events.size() - 1, -1, -1):
		var event_data: Dictionary = _dictionary_or_empty(events[index])
		if str(event_data.get("kind", "")) == kind:
			return event_data
	return {}


func _inventory_entry_count(entries: Array, item_id: String) -> int:
	var total := 0
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if str(entry_data.get("item_id", "")) == item_id:
			total += max(0, int(entry_data.get("count", 0)))
	return total


func _expect_turn_policy(errors: Array[String], result: Dictionary, expected_action: String, expected_auto_advanced: bool, context: String) -> void:
	var policy: Dictionary = _dictionary_or_empty(result.get("turn_policy", {}))
	if policy.is_empty():
		errors.append("%s should expose turn_policy" % context)
		return
	if str(policy.get("action_kind", "")) != expected_action:
		errors.append("%s turn_policy should expose action kind %s" % [context, expected_action])
	if bool(policy.get("success", false)) != bool(result.get("success", false)):
		errors.append("%s turn_policy success should mirror command result" % context)
	if not policy.has("ap_after_action") or not policy.has("affordable_ap_threshold"):
		errors.append("%s turn_policy should expose AP after action and affordable threshold" % context)
	if bool(policy.get("auto_advanced", false)) != expected_auto_advanced:
		errors.append("%s turn_policy auto_advanced should be %s" % [context, str(expected_auto_advanced)])
	var runtime_delta: Dictionary = _dictionary_or_empty(result.get("runtime_snapshot_delta", {}))
	var delta_policy: Dictionary = _dictionary_or_empty(runtime_delta.get("turn_policy", {}))
	if delta_policy.is_empty():
		errors.append("%s runtime delta should expose turn_policy" % context)
	elif str(delta_policy.get("action_kind", "")) != expected_action:
		errors.append("%s runtime delta turn_policy should mirror action kind" % context)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _station_context_with_requirement(stations: Array, station_id: String, requirement: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for station in stations:
		var station_data: Dictionary = _dictionary_or_empty(station).duplicate(true)
		if str(station_data.get("station_id", "")) == station_id:
			for key in requirement.keys():
				station_data[key] = requirement.get(key)
		output.append(station_data)
	return output


func _has_station(crafting_context: Dictionary, station_id: String) -> bool:
	for station in _array_or_empty(crafting_context.get("crafting_stations", [])):
		var data: Dictionary = _dictionary_or_empty(station)
		if str(data.get("station_id", "")) == station_id:
			return true
	return false


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
