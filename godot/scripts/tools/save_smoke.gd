extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const SaveService = preload("res://scripts/app/save_service.gd")
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
	_prepare_runtime_state(simulation, registry)

	var service := SaveService.new("user://save_smoke")
	service.delete_snapshot("roundtrip")
	var snapshot: Dictionary = simulation.snapshot()
	var saved: bool = service.save_snapshot("roundtrip", snapshot)
	var loaded: Dictionary = service.load_snapshot("roundtrip")
	service.delete_snapshot("roundtrip")
	var restored_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	if bool(loaded.get("ok", false)):
		restored_simulation.load_snapshot(loaded.get("runtime_snapshot", {}))

	var errors: Array[String] = _validate_roundtrip(saved, snapshot, loaded, restored_simulation.snapshot())
	errors.append_array(_validate_legacy_snapshot_migration(snapshot, registry))
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("save_smoke passed:")
	print(JSON.stringify(_digest(loaded.get("runtime_snapshot", {})), "\t"))
	quit(0)


func _prepare_runtime_state(simulation: RefCounted, registry: RefCounted) -> void:
	simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_pickup_medkit",
	})
	simulation.execute_interaction(1, {
		"target_type": "actor",
		"actor_id": 2,
	})
	simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_clinic_supply_cabinet",
	})
	simulation.take_item_from_container(1, "survivor_outpost_01_clinic_supply_cabinet", "1031", 1, registry.get_library("items"))
	simulation.store_item_in_container(1, "survivor_outpost_01_clinic_supply_cabinet", "1008", 1, registry.get_library("items"))
	var clinic_container: Dictionary = simulation.container_sessions.get("survivor_outpost_01_clinic_supply_cabinet", {}).duplicate(true)
	clinic_container["allow_take"] = true
	clinic_container["allow_store"] = false
	clinic_container["required_item_ids"] = ["1138"]
	clinic_container["required_tool_ids"] = ["1150"]
	clinic_container["consume_required_items_on_unlock"] = true
	clinic_container["consume_required_tools_on_unlock"] = true
	clinic_container["tool_durability_cost"] = 3.0
	clinic_container["unlock_requirements_consumed"] = true
	clinic_container["unlock_consumed_actor_id"] = 1
	clinic_container["required_world_flags"] = ["outpost_workshop_restored"]
	clinic_container["blocked_world_flags"] = ["clinic_locked_down"]
	clinic_container["max_weight"] = 3.5
	clinic_container["max_items"] = 9
	clinic_container["max_stacks"] = 4
	clinic_container["owned"] = true
	clinic_container["owner_actor_id"] = 2
	clinic_container["owner_actor_definition_id"] = "trader_lao_wang"
	clinic_container["allow_steal"] = false
	clinic_container["steal_relationship_delta"] = -15.0
	clinic_container["owner_relationship_min"] = 40.0
	clinic_container["required_active_quest_ids"] = ["find_medicine"]
	clinic_container["required_completed_quest_ids"] = ["tutorial_survive"]
	clinic_container["blocked_active_quest_ids"] = ["save_smoke_blocked_active"]
	clinic_container["blocked_completed_quest_ids"] = ["save_smoke_blocked_completed"]
	simulation.container_sessions["survivor_outpost_01_clinic_supply_cabinet"] = clinic_container
	var transition_topology: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot()).get("map", {})
	var transition_result: Dictionary = _submit_and_complete(simulation, registry, {
		"kind": "interact",
		"target": {
			"target_type": "map_object",
			"target_id": "survivor_outpost_01_interior_door",
		},
		"topology": transition_topology,
	})
	if not bool(transition_result.get("success", false)):
		push_error("save smoke scene transition failed: %s" % transition_result.get("reason", "unknown"))
	simulation.buy_item_from_shop(1, "trader_lao_wang_shop", "1006", 1, registry.get_library("items"))
	simulation.sell_item_to_shop(1, "trader_lao_wang_shop", "1006", 1, registry.get_library("items"))
	simulation.equip_item(1, "1003", "main_hand", registry.get_library("items"))
	var player_for_reload: RefCounted = simulation.actor_registry.get_actor(1)
	player_for_reload.inventory["1004"] = 1
	player_for_reload.inventory["1009"] = 3
	player_for_reload.tool_durability["1151"] = 42.5
	simulation.equip_item(1, "1004", "main_hand", registry.get_library("items"))
	player_for_reload.ap = 6.0
	simulation.submit_player_command({
		"kind": "inventory_action",
		"actor_id": 1,
		"action": "reload_equipped",
		"slot_id": "main_hand",
		"item_library": registry.get_library("items"),
	})
	simulation.grant_skill_points(1, 1, "save_smoke")
	simulation.learn_skill(1, "survival", registry.get_library("skills"))
	simulation.grant_skill_points(1, 2, "save_smoke")
	simulation.submit_player_command({
		"kind": "learn_skill",
		"actor_id": 1,
		"skill_id": "combat",
		"skill_library": registry.get_library("skills"),
	})
	simulation.submit_player_command({
		"kind": "learn_skill",
		"actor_id": 1,
		"skill_id": "adrenaline_rush",
		"skill_library": registry.get_library("skills"),
	})
	simulation.submit_player_command({
		"kind": "bind_hotbar",
		"actor_id": 1,
		"slot_id": "slot_1",
		"skill_id": "adrenaline_rush",
		"skill_library": registry.get_library("skills"),
	})
	player_for_reload.inventory["1006"] = max(1, int(player_for_reload.inventory.get("1006", 0)))
	player_for_reload.inventory["1006"] = max(4, int(player_for_reload.inventory.get("1006", 0)))
	simulation.submit_player_command({
		"kind": "bind_hotbar",
		"actor_id": 1,
		"slot_id": "slot_2",
		"hotbar_kind": "item",
		"item_id": "1006",
		"item_library": registry.get_library("items"),
		"effect_library": registry.get_library("json"),
	})
	simulation.submit_player_command({
		"kind": "use_skill",
		"actor_id": 1,
		"slot_id": "slot_1",
		"skill_library": registry.get_library("skills"),
		"target": {"target_type": "self"},
	})
	simulation.set_active_hotbar_group("group_2")
	simulation.set_hotbar_group_label("group_2", "Tools")
	simulation.submit_player_command({
		"kind": "bind_hotbar",
		"actor_id": 1,
		"slot_id": "slot_1",
		"hotbar_kind": "item",
		"item_id": "1006",
		"item_library": registry.get_library("items"),
		"effect_library": registry.get_library("json"),
	})
	simulation.set_active_hotbar_group("group_1")
	var topology: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot()).get("map", {})
	simulation.crafted_recipes["recipe_knife_basic"] = true
	simulation.world_flags["outpost_workshop_restored"] = true
	player_for_reload.inventory["1011"] = 2
	player_for_reload.ap = 0.5
	simulation.submit_player_command({
		"kind": "craft",
		"actor_id": 1,
		"recipe_id": "recipe_bandage_basic",
		"count": 1,
		"recipe_library": registry.get_library("recipes"),
		"topology": topology,
	})
	simulation.crafting_queue = [{"recipe_id": "recipe_bandage_basic", "count": 2}]
	var trader_shop: Dictionary = simulation.shop_sessions.get("trader_lao_wang_shop", {}).duplicate(true)
	trader_shop["target_actor_definition_id"] = "trader_lao_wang"
	trader_shop["required_relationship_min"] = 10.0
	trader_shop["required_world_flags"] = ["outpost_workshop_restored"]
	trader_shop["blocked_world_flags"] = ["trader_banned"]
	simulation.shop_sessions["trader_lao_wang_shop"] = trader_shop
	simulation.door_states["save_smoke_door"] = {
		"door_id": "save_smoke_door",
		"object_id": "save_smoke_door",
		"display_name": "存档测试门",
		"is_open": true,
		"locked": false,
		"blocks_movement": false,
		"blocks_sight": false,
		"blocks_sight_when_closed": true,
		"required_item_ids": ["1138"],
		"required_tool_ids": ["1150"],
		"consume_required_items_on_unlock": true,
		"consume_required_tools_on_unlock": true,
		"tool_durability_cost": 3.0,
		"unlock_requirements_consumed": true,
		"unlock_consumed_actor_id": 1,
	}
	simulation.set_actor_vision_radius(1, 4)
	simulation.refresh_actor_vision(1, topology)
	simulation.record_item_collected(1, "1007", 2)
	simulation.set_relationship_score(1, 2, 88.0, "save_smoke")
	var zombie: int = _register_zombie(simulation, registry)
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	var target: RefCounted = simulation.actor_registry.get_actor(zombie)
	simulation.decide_actor_intent(zombie)
	player.attack_power = 10.0
	target.hp = 5.0
	target.defense = 0.0
	simulation.perform_attack(1, zombie)
	simulation.corpse_containers["save_smoke_corpse_container"] = {
		"container_id": "save_smoke_corpse_container",
		"container_type": "corpse",
		"container_origin": "combat_defeat",
		"map_id": simulation.active_map_id,
		"grid_position": {"x": 2, "y": 0, "z": 0},
		"display_name": "存档测试尸体",
		"source_actor_id": zombie,
		"source_actor_definition_id": "zombie_walker",
		"source_actor_kind": "enemy",
		"defeated_by_actor_id": 1,
		"money": 2,
		"inventory": [{"item_id": "1006", "count": 1}],
	}
	simulation.container_sessions["save_smoke_corpse_container"] = {
		"container_id": "save_smoke_corpse_container",
		"container_type": "corpse",
		"container_origin": "combat_defeat",
		"map_id": simulation.active_map_id,
		"grid_position": {"x": 2, "y": 0, "z": 0},
		"source_actor_id": zombie,
		"source_actor_definition_id": "zombie_walker",
		"source_actor_kind": "enemy",
		"defeated_by_actor_id": 1,
		"display_name": "存档测试尸体",
		"money": 2,
		"inventory": [{"item_id": "1006", "count": 1}],
	}
	var active_combat_zombie: int = _register_zombie(simulation, registry)
	var active_target: RefCounted = simulation.actor_registry.get_actor(active_combat_zombie)
	active_target.grid_position = GridCoord.new(3, 0, 0)
	active_target.combat_attributes["speed"] = 3.0
	player.combat_attributes["speed"] = 5.0
	player.turn_open = true
	player.ap = maxf(player.ap, 1.0)
	simulation.combat_state["active"] = true
	simulation.combat_state["round"] = 7
	simulation.combat_state["participants"] = [1, active_combat_zombie]
	simulation.combat_state["turn_order"] = [1, active_combat_zombie]
	simulation.combat_state["initiative"] = [
		{
			"actor_id": 1,
			"display_name": player.display_name,
			"kind": player.kind,
			"side": player.side,
			"speed": 5.0,
			"initiative": 5.0,
			"order_index": 0,
			"turn_open": player.turn_open,
		},
		{
			"actor_id": active_combat_zombie,
			"display_name": active_target.display_name,
			"kind": active_target.kind,
			"side": active_target.side,
			"speed": 3.0,
			"initiative": 3.0,
			"order_index": 1,
			"turn_open": active_target.turn_open,
		},
	]
	simulation.combat_state["current_combat_actor_id"] = 1
	simulation.combat_state["next_combat_actor_id"] = active_combat_zombie
	player.inventory["1006"] = max(4, int(player.inventory.get("1006", 0)))
	player.inventory_stacks.erase("1006")
	var split_result: Dictionary = simulation.submit_player_command({
		"kind": "inventory_action",
		"actor_id": 1,
		"action": "split_stack",
		"item_id": "1006",
		"count": 1,
	})
	if not bool(split_result.get("success", false)):
		push_error("save smoke split_stack fixture failed: %s" % JSON.stringify(split_result))


func _submit_and_complete(simulation: RefCounted, registry: RefCounted, command: Dictionary, max_waits: int = 8) -> Dictionary:
	var result: Dictionary = simulation.submit_player_command(command)
	var waits := 0
	while waits < max_waits and _has_pending(simulation) and not _final_interaction_result(result):
		waits += 1
		var topology: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot()).get("map", {})
		var wait_result: Dictionary = simulation.submit_player_command({
			"kind": "wait",
			"topology": topology,
		})
		var pending_result: Dictionary = _dictionary_or_empty(wait_result.get("pending_result", {}))
		result = pending_result if not pending_result.is_empty() else wait_result
	return result


func _has_pending(simulation: RefCounted) -> bool:
	var snapshot: Dictionary = simulation.snapshot()
	return not _dictionary_or_empty(snapshot.get("pending_movement", {})).is_empty() or not _dictionary_or_empty(snapshot.get("pending_interaction", {})).is_empty() or not _dictionary_or_empty(snapshot.get("pending_crafting", {})).is_empty()


func _final_interaction_result(result: Dictionary) -> bool:
	if not bool(result.get("success", false)):
		return true
	if str(result.get("kind", "")) in ["approach_queued", "move", "wait"]:
		return false
	if result.has("target_map_id") or result.has("dialogue_id") or result.has("container") or result.has("item_id") or result.has("defeated"):
		return true
	return str(result.get("reason", "")) == "ok"


func _register_zombie(simulation: RefCounted, registry: RefCounted) -> int:
	var record: Dictionary = registry.get_library("characters").get("zombie_walker", {})
	var data: Dictionary = record.get("data", {})
	var identity: Dictionary = data.get("identity", {})
	return simulation.register_actor({
		"definition_id": "zombie_walker",
		"display_name": str(identity.get("display_name", "zombie_walker")),
		"kind": "enemy",
		"side": "hostile",
		"group_id": "infected",
		"grid_position": GridCoord.new(2, 0, 0),
		"max_hp": 5.0,
		"hp": 5.0,
		"attack_power": 4.0,
		"defense": 0.0,
		"xp_reward": 10,
	})


func _validate_roundtrip(saved: bool, original: Dictionary, loaded: Dictionary, restored: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not saved:
		return ["save_snapshot returned false"]
	if not bool(loaded.get("ok", false)):
		return ["load_snapshot failed: %s" % loaded.get("reason", "unknown")]
	var metadata: Dictionary = _dictionary_or_empty(loaded.get("metadata", {}))
	var metadata_player: Dictionary = _dictionary_or_empty(metadata.get("player", {}))
	if str(metadata.get("active_map_id", "")) != str(original.get("active_map_id", "")):
		errors.append("save metadata active_map_id should match snapshot")
	if str(metadata.get("turn_phase", "")) != str(_dictionary_or_empty(original.get("turn_state", {})).get("phase", "")):
		errors.append("save metadata turn_phase should match snapshot")
	if bool(metadata.get("combat_active", true)) != bool(_dictionary_or_empty(original.get("combat_state", {})).get("active", false)):
		errors.append("save metadata combat_active should match snapshot")
	if int(metadata.get("active_quest_count", -1)) != _array_or_empty(original.get("active_quests", [])).size():
		errors.append("save metadata active_quest_count should match snapshot")
	if int(metadata.get("completed_quest_count", -1)) != _array_or_empty(original.get("completed_quests", [])).size():
		errors.append("save metadata completed_quest_count should match snapshot")
	if int(metadata.get("container_session_count", -1)) != _array_or_empty(original.get("container_sessions", [])).size():
		errors.append("save metadata container_session_count should match snapshot")
	if int(metadata.get("shop_session_count", -1)) != _array_or_empty(original.get("shop_sessions", [])).size():
		errors.append("save metadata shop_session_count should match snapshot")
	if int(metadata.get("corpse_container_count", -1)) != _array_or_empty(original.get("corpse_containers", [])).size():
		errors.append("save metadata corpse_container_count should match snapshot")
	if str(metadata_player.get("display_name", "")).is_empty():
		errors.append("save metadata player display_name should be present")
	if _dictionary_or_empty(metadata_player.get("grid_position", {})).is_empty():
		errors.append("save metadata player grid_position should be present")
	if float(metadata_player.get("max_hp", 0.0)) <= 0.0:
		errors.append("save metadata player hp/max_hp should be present")
	if int(metadata_player.get("inventory_stack_count", 0)) <= 0 or int(metadata_player.get("inventory_item_count", 0)) <= 0:
		errors.append("save metadata player inventory counts should be present")

	for key in ["active_map_id", "active_location_id", "active_entry_point_id", "consumed_interaction_targets", "completed_quests", "crafted_recipes", "world_flags", "door_states", "relationships"]:
		if JSON.stringify(restored.get(key)) != JSON.stringify(original.get(key)):
			errors.append("snapshot field mismatch: %s" % key)
	if JSON.stringify(_normalized_container_sessions(restored)) != JSON.stringify(_normalized_container_sessions(original)):
		errors.append("container sessions did not roundtrip")
	if str(original.get("active_map_id", "")) != "survivor_outpost_01_interior":
		errors.append("save fixture should snapshot after scene transition to interior")
	if str(restored.get("active_map_id", "")) != "survivor_outpost_01_interior":
		errors.append("scene-transition active_map_id did not roundtrip")
	if str(restored.get("active_entry_point_id", "")) != str(original.get("active_entry_point_id", "")):
		errors.append("scene-transition active_entry_point_id did not roundtrip")
	if not _array_or_empty(restored.get("unlocked_locations", [])).has(str(original.get("active_location_id", ""))):
		errors.append("unlocked_locations should survive scene-transition save roundtrip")
	if str(_player_actor(restored).get("map_id", "")) != "survivor_outpost_01_interior":
		errors.append("player actor map_id should roundtrip after scene transition")
	if JSON.stringify(_dictionary_or_empty(_player_actor(restored).get("grid_position", {}))) != JSON.stringify(_dictionary_or_empty(_player_actor(original).get("grid_position", {}))):
		errors.append("player scene-transition grid_position did not roundtrip")
	var transition_payload: Dictionary = _last_event_payload(restored, "scene_transition")
	if str(transition_payload.get("to_map_id", "")) != "survivor_outpost_01_interior":
		errors.append("scene_transition event payload should roundtrip target map")
	if _dictionary_or_empty(transition_payload.get("grid_position", {})).is_empty():
		errors.append("scene_transition event payload should roundtrip entry grid")
	var original_combat_state: Dictionary = _dictionary_or_empty(original.get("combat_state", {}))
	var restored_combat_state: Dictionary = _dictionary_or_empty(restored.get("combat_state", {}))
	if JSON.stringify(_normalized_combat_state(restored_combat_state)) != JSON.stringify(_normalized_combat_state(original_combat_state)):
		errors.append("combat_state initiative summary did not roundtrip")
	if not bool(restored_combat_state.get("active", false)):
		errors.append("combat_state active test fixture should roundtrip as active")
	if _array_or_empty(restored_combat_state.get("turn_order", [])).size() < 2:
		errors.append("combat_state turn_order should roundtrip non-empty order")
	if _array_or_empty(restored_combat_state.get("initiative", [])).size() < 2:
		errors.append("combat_state initiative should roundtrip non-empty entries")
	var original_pending_crafting: Dictionary = _dictionary_or_empty(original.get("pending_crafting", {}))
	var restored_pending_crafting: Dictionary = _dictionary_or_empty(restored.get("pending_crafting", {}))
	if original_pending_crafting.is_empty():
		errors.append("save fixture should include pending_crafting")
	if JSON.stringify(_normalized_pending_crafting(restored_pending_crafting)) != JSON.stringify(_normalized_pending_crafting(original_pending_crafting)):
		errors.append("pending_crafting did not roundtrip")
	if not _runtime_queue_has_kind(restored, "pending_crafting"):
		errors.append("runtime_command_queue should expose restored pending_crafting")
	if JSON.stringify(restored.get("crafting_queue", [])) != JSON.stringify(original.get("crafting_queue", [])):
		errors.append("crafting_queue did not roundtrip")
	var restored_clinic_container: Dictionary = _container_session(restored, "survivor_outpost_01_clinic_supply_cabinet")
	if str(restored_clinic_container.get("container_type", "")) != "map":
		errors.append("map container type metadata did not roundtrip")
	if str(restored_clinic_container.get("container_origin", "")) != "map_scene":
		errors.append("map container origin metadata did not roundtrip")
	if not bool(restored_clinic_container.get("allow_take", false)):
		errors.append("container allow_take permission did not roundtrip")
	if bool(restored_clinic_container.get("allow_store", true)):
		errors.append("container allow_store permission did not roundtrip")
	if not _array_or_empty(restored_clinic_container.get("required_item_ids", [])).has("1138"):
		errors.append("container required item ids did not roundtrip")
	if not _array_or_empty(restored_clinic_container.get("required_tool_ids", [])).has("1150"):
		errors.append("container required tool ids did not roundtrip")
	if not bool(restored_clinic_container.get("consume_required_items_on_unlock", false)):
		errors.append("container consume_required_items_on_unlock did not roundtrip")
	if not bool(restored_clinic_container.get("consume_required_tools_on_unlock", false)):
		errors.append("container consume_required_tools_on_unlock did not roundtrip")
	if not is_equal_approx(float(restored_clinic_container.get("tool_durability_cost", 0.0)), 3.0):
		errors.append("container tool_durability_cost did not roundtrip")
	if not bool(restored_clinic_container.get("unlock_requirements_consumed", false)):
		errors.append("container unlock_requirements_consumed did not roundtrip")
	if int(restored_clinic_container.get("unlock_consumed_actor_id", 0)) != 1:
		errors.append("container unlock_consumed_actor_id did not roundtrip")
	if not _array_or_empty(restored_clinic_container.get("required_world_flags", [])).has("outpost_workshop_restored"):
		errors.append("container required world flags did not roundtrip")
	if not _array_or_empty(restored_clinic_container.get("blocked_world_flags", [])).has("clinic_locked_down"):
		errors.append("container blocked world flags did not roundtrip")
	if not is_equal_approx(float(restored_clinic_container.get("max_weight", 0.0)), 3.5):
		errors.append("container max_weight did not roundtrip")
	if int(restored_clinic_container.get("max_items", 0)) != 9:
		errors.append("container max_items did not roundtrip")
	if int(restored_clinic_container.get("max_stacks", 0)) != 4:
		errors.append("container max_stacks did not roundtrip")
	if not bool(restored_clinic_container.get("owned", false)):
		errors.append("container owned flag did not roundtrip")
	if int(restored_clinic_container.get("owner_actor_id", 0)) != 2:
		errors.append("container owner_actor_id did not roundtrip")
	if str(restored_clinic_container.get("owner_actor_definition_id", "")) != "trader_lao_wang":
		errors.append("container owner_actor_definition_id did not roundtrip")
	if bool(restored_clinic_container.get("allow_steal", true)):
		errors.append("container allow_steal did not roundtrip")
	if absf(float(restored_clinic_container.get("steal_relationship_delta", 0.0)) + 15.0) > 0.001:
		errors.append("container steal_relationship_delta did not roundtrip")
	if absf(float(restored_clinic_container.get("owner_relationship_min", 0.0)) - 40.0) > 0.001:
		errors.append("container owner_relationship_min did not roundtrip")
	if not _array_or_empty(restored_clinic_container.get("required_active_quest_ids", [])).has("find_medicine"):
		errors.append("container required active quest ids did not roundtrip")
	if not _array_or_empty(restored_clinic_container.get("required_completed_quest_ids", [])).has("tutorial_survive"):
		errors.append("container required completed quest ids did not roundtrip")
	if not _array_or_empty(restored_clinic_container.get("blocked_active_quest_ids", [])).has("save_smoke_blocked_active"):
		errors.append("container blocked active quest ids did not roundtrip")
	if not _array_or_empty(restored_clinic_container.get("blocked_completed_quest_ids", [])).has("save_smoke_blocked_completed"):
		errors.append("container blocked completed quest ids did not roundtrip")
	var restored_corpse_container: Dictionary = _first_container_with_type(restored, "corpse")
	if restored_corpse_container.is_empty():
		errors.append("corpse container type metadata did not roundtrip")
	elif str(restored_corpse_container.get("container_origin", "")) != "combat_defeat":
		errors.append("corpse container origin metadata did not roundtrip")
	if JSON.stringify(restored.get("shop_sessions")) != JSON.stringify(original.get("shop_sessions")):
		errors.append("shop sessions did not roundtrip")
	var restored_trader_shop: Dictionary = _shop_session(restored, "trader_lao_wang_shop")
	if str(restored_trader_shop.get("target_actor_definition_id", "")) != "trader_lao_wang":
		errors.append("shop permission target definition did not roundtrip")
	if absf(float(restored_trader_shop.get("required_relationship_min", 0.0)) - 10.0) > 0.001:
		errors.append("shop relationship permission did not roundtrip")
	if not _array_or_empty(restored_trader_shop.get("required_world_flags", [])).has("outpost_workshop_restored"):
		errors.append("shop required world flags did not roundtrip")
	if not _array_or_empty(restored_trader_shop.get("blocked_world_flags", [])).has("trader_banned"):
		errors.append("shop blocked world flags did not roundtrip")
	if int(restored.get("schema_version", 0)) != int(original.get("schema_version", 0)):
		errors.append("snapshot schema_version did not restore")
	var restored_door: Dictionary = _door_state(restored, "save_smoke_door")
	if not _array_or_empty(restored_door.get("required_item_ids", [])).has("1138"):
		errors.append("door required item ids did not roundtrip")
	if not _array_or_empty(restored_door.get("required_tool_ids", [])).has("1150"):
		errors.append("door required tool ids did not roundtrip")
	if not bool(restored_door.get("consume_required_items_on_unlock", false)):
		errors.append("door consume_required_items_on_unlock did not roundtrip")
	if not bool(restored_door.get("consume_required_tools_on_unlock", false)):
		errors.append("door consume_required_tools_on_unlock did not roundtrip")
	if not is_equal_approx(float(restored_door.get("tool_durability_cost", 0.0)), 3.0):
		errors.append("door tool_durability_cost did not roundtrip")
	if not bool(restored_door.get("unlock_requirements_consumed", false)):
		errors.append("door unlock_requirements_consumed did not roundtrip")
	if int(restored_door.get("unlock_consumed_actor_id", 0)) != 1:
		errors.append("door unlock_consumed_actor_id did not roundtrip")
	var player_original: Dictionary = _player_actor(original)
	var player_restored: Dictionary = _player_actor(restored)
	if _inventory_count(player_restored, "1006") != _inventory_count(player_original, "1006"):
		errors.append("player inventory did not roundtrip")
	if JSON.stringify(player_restored.get("inventory_order", [])) != JSON.stringify(player_original.get("inventory_order", [])):
		errors.append("player inventory_order did not roundtrip")
	if JSON.stringify(_dictionary_or_empty(player_restored.get("inventory_stacks", {}))) != JSON.stringify(_dictionary_or_empty(player_original.get("inventory_stacks", {}))):
		errors.append("player inventory_stacks did not roundtrip")
	var bandage_stacks: Array = _array_or_empty(_dictionary_or_empty(player_restored.get("inventory_stacks", {})).get("1006", []))
	if bandage_stacks.size() < 2:
		errors.append("player split bandage stacks should roundtrip")
	if _inventory_count(player_restored, "1031") != 1:
		errors.append("taken container item did not roundtrip in player inventory")
	if JSON.stringify(_dictionary_or_empty(player_restored.get("tool_durability", {}))) != JSON.stringify(_dictionary_or_empty(player_original.get("tool_durability", {}))):
		errors.append("player tool_durability did not roundtrip")
	if JSON.stringify(player_restored.get("equipment", {})) != JSON.stringify(player_original.get("equipment", {})):
		errors.append("player equipment did not roundtrip")
	if JSON.stringify(_normalized_resources(player_restored)) != JSON.stringify(_normalized_resources(player_original)):
		errors.append("player resources did not roundtrip")
	if JSON.stringify(_normalized_weapon_ammo(player_restored)) != JSON.stringify(_normalized_weapon_ammo(player_original)):
		errors.append("player weapon ammo did not roundtrip")
	if JSON.stringify(_normalized_progression(player_restored)) != JSON.stringify(_normalized_progression(player_original)):
		errors.append("player progression did not roundtrip")
	if JSON.stringify(_normalized_active_effects(player_restored)) != JSON.stringify(_normalized_active_effects(player_original)):
		errors.append("player active skill effects did not roundtrip")
	if JSON.stringify(restored.get("hotbar", {})) != JSON.stringify(original.get("hotbar", {})):
		errors.append("hotbar did not roundtrip")
	if str(restored.get("active_hotbar_group", "")) != str(original.get("active_hotbar_group", "")):
		errors.append("active_hotbar_group did not roundtrip")
	if JSON.stringify(restored.get("hotbar_groups", {})) != JSON.stringify(original.get("hotbar_groups", {})):
		errors.append("hotbar_groups did not roundtrip")
	if JSON.stringify(restored.get("hotbar_group_labels", {})) != JSON.stringify(original.get("hotbar_group_labels", {})):
		errors.append("hotbar_group_labels did not roundtrip")
	for derived_key in ["runtime_command_queue", "runtime_command_history", "pending_progression_step", "current_control_actor", "recent_interaction_target", "recent_failure", "recent_event_feedback", "target_preview", "target_selection_state", "ui_menu_state_refs", "debug_runtime_diagnostics"]:
		if not restored.has(derived_key):
			errors.append("restored snapshot missing derived runtime field %s" % derived_key)
	if int(_dictionary_or_empty(restored.get("current_control_actor", {})).get("actor_id", 0)) != 1:
		errors.append("restored snapshot should rebuild current_control_actor")
	if typeof(restored.get("recent_event_feedback", [])) != TYPE_ARRAY:
		errors.append("restored snapshot should rebuild recent_event_feedback")
	if typeof(restored.get("runtime_command_history", [])) != TYPE_ARRAY:
		errors.append("restored snapshot should rebuild runtime_command_history")
	var restored_diagnostics: Dictionary = _dictionary_or_empty(restored.get("debug_runtime_diagnostics", {}))
	if int(restored_diagnostics.get("command_history_count", -1)) != _array_or_empty(restored.get("runtime_command_history", [])).size():
		errors.append("restored debug diagnostics should mirror runtime_command_history count")
	if not _array_or_empty(restored.get("crafted_recipes", [])).has("recipe_knife_basic"):
		errors.append("crafted_recipes should roundtrip non-empty recipe unlock state")
	if not _array_or_empty(restored.get("world_flags", [])).has("outpost_workshop_restored"):
		errors.append("world_flags should roundtrip non-empty unlock state")
	if player_restored.get("active_dialogue_id", "") != "trader_lao_wang_tutorial_active":
		errors.append("player active dialogue did not roundtrip")
	if player_restored.get("active_container_id", "") != "survivor_outpost_01_clinic_supply_cabinet":
		errors.append("player active container did not roundtrip")
	if int(player_restored.get("money", 0)) != int(player_original.get("money", 0)):
		errors.append("player money did not roundtrip")
	if _container_count(restored, "survivor_outpost_01_clinic_supply_cabinet", "1008") != 1:
		errors.append("stored player item did not roundtrip in container")
	if _container_count(restored, "survivor_outpost_01_clinic_supply_cabinet", "1031") != 0:
		errors.append("taken container item still appeared in restored container")
	if _active_quest_ids(restored) != _active_quest_ids(original):
		errors.append("active quests did not roundtrip")
	if JSON.stringify(_actor_vision_snapshot(restored, 1)) != JSON.stringify(_actor_vision_snapshot(original, 1)):
		errors.append("player vision did not roundtrip")
	if absf(_relationship_score(restored, 1, 2) - 88.0) > 0.001:
		errors.append("player/trader relationship score did not roundtrip")
	if JSON.stringify(_normalized_ai_intents(restored)) != JSON.stringify(_normalized_ai_intents(original)):
		errors.append("ai intents did not roundtrip")
	if restored.get("events", []).size() != original.get("events", []).size():
		errors.append("event count did not roundtrip")
	return errors


func _validate_legacy_snapshot_migration(snapshot: Dictionary, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy.erase("schema_version")
	legacy.erase("active_location_id")
	legacy.erase("active_entry_point_id")
	legacy.erase("combat_state")
	legacy.erase("pending_movement")
	legacy.erase("pending_interaction")
	legacy.erase("pending_crafting")
	legacy.erase("crafting_queue")
	legacy.erase("door_states")
	legacy.erase("corpse_containers")
	legacy.erase("interaction_menu")
	legacy.erase("hotbar")
	legacy.erase("active_hotbar_group")
	legacy.erase("hotbar_groups")
	legacy.erase("hotbar_group_labels")
	legacy.erase("relationships")
	var restored_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	restored_simulation.load_snapshot(legacy)
	var restored: Dictionary = restored_simulation.snapshot()
	if int(restored.get("schema_version", 0)) != 1:
		errors.append("legacy snapshot migration should restore current schema_version")
	if str(restored.get("active_location_id", "")) != str(snapshot.get("start_location_id", "")):
		errors.append("legacy snapshot migration should default active_location_id from start_location_id")
	if str(restored.get("active_entry_point_id", "")) != str(snapshot.get("start_entry_point_id", "")):
		errors.append("legacy snapshot migration should default active_entry_point_id from start_entry_point_id")
	for key in ["turn_state", "combat_state", "pending_movement", "pending_interaction", "pending_crafting", "crafting_queue", "runtime_command_queue", "runtime_command_history", "pending_progression_step", "current_control_actor", "recent_interaction_target", "recent_failure", "recent_event_feedback", "target_preview", "target_selection_state", "ui_menu_state_refs", "debug_runtime_diagnostics", "door_states", "corpse_containers", "interaction_menu", "hotbar", "active_hotbar_group", "hotbar_groups", "hotbar_group_labels", "relationships"]:
		if not restored.has(key):
			errors.append("legacy snapshot migration missing %s" % key)
	if not _dictionary_or_empty(restored.get("pending_crafting", {})).is_empty():
		errors.append("legacy snapshot migration should default pending_crafting to empty")
	if not _array_or_empty(restored.get("crafting_queue", [])).is_empty():
		errors.append("legacy snapshot migration should default crafting_queue to empty")
	if _relationship_score(restored, 1, 2) < 49.9:
		errors.append("legacy snapshot migration should initialize player/trader relationship from sides")
	if not _has_event(restored, "snapshot_migrated"):
		errors.append("legacy snapshot migration should emit snapshot_migrated")
	return errors


func _player_actor(snapshot: Dictionary) -> Dictionary:
	for actor in snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return actor_data
	return {}


func _active_quest_ids(snapshot: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for quest in snapshot.get("active_quests", []):
		var quest_data: Dictionary = quest
		output.append(str(quest_data.get("quest_id", "")))
	return output


func _actor_vision_snapshot(snapshot: Dictionary, actor_id: int) -> Dictionary:
	var vision: Dictionary = snapshot.get("vision", {})
	for actor in vision.get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == actor_id:
			return actor_data
	return {}


func _relationship_score(snapshot: Dictionary, actor_id: int, target_actor_id: int) -> float:
	var left: int = min(actor_id, target_actor_id)
	var right: int = max(actor_id, target_actor_id)
	for entry in snapshot.get("relationships", []):
		var relationship: Dictionary = _dictionary_or_empty(entry)
		if int(relationship.get("actor_id", 0)) == left and int(relationship.get("target_actor_id", 0)) == right:
			return float(relationship.get("score", 0.0))
	return 0.0


func _shop_session(snapshot: Dictionary, shop_id: String) -> Dictionary:
	for entry in snapshot.get("shop_sessions", []):
		var session: Dictionary = _dictionary_or_empty(entry)
		if str(session.get("shop_id", "")) == shop_id:
			return session
	return {}


func _container_session(snapshot: Dictionary, container_id: String) -> Dictionary:
	for entry in snapshot.get("container_sessions", []):
		var session: Dictionary = _dictionary_or_empty(entry)
		if str(session.get("container_id", "")) == container_id:
			return session
	return {}


func _first_container_with_type(snapshot: Dictionary, container_type: String) -> Dictionary:
	for entry in snapshot.get("container_sessions", []):
		var session: Dictionary = _dictionary_or_empty(entry)
		if str(session.get("container_type", "")) == container_type:
			return session
	return {}


func _door_state(snapshot: Dictionary, door_id: String) -> Dictionary:
	for entry in snapshot.get("door_states", []):
		var state: Dictionary = _dictionary_or_empty(entry)
		if str(state.get("door_id", state.get("object_id", ""))) == door_id:
			return state
	return {}


func _normalized_ai_intents(snapshot: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for intent in snapshot.get("ai_intents", []):
		var intent_data: Dictionary = intent
		output.append({
			"actor_id": int(intent_data.get("actor_id", 0)),
			"intent": str(intent_data.get("intent", "")),
			"target_actor_id": int(intent_data.get("target_actor_id", 0)),
			"reason": str(intent_data.get("reason", "")),
		})
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("actor_id", 0)) < int(b.get("actor_id", 0))
	)
	return output


func _normalized_combat_state(combat_state: Dictionary) -> Dictionary:
	var initiative: Array[Dictionary] = []
	for entry in _array_or_empty(combat_state.get("initiative", [])):
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		initiative.append({
			"actor_id": int(entry_data.get("actor_id", 0)),
			"display_name": str(entry_data.get("display_name", "")),
			"kind": str(entry_data.get("kind", "")),
			"side": str(entry_data.get("side", "")),
			"speed": float(entry_data.get("speed", 0.0)),
			"initiative": float(entry_data.get("initiative", 0.0)),
			"order_index": int(entry_data.get("order_index", 0)),
			"turn_open": bool(entry_data.get("turn_open", false)),
		})
	return {
		"active": bool(combat_state.get("active", false)),
		"round": int(combat_state.get("round", 0)),
		"participants": _int_array(combat_state.get("participants", [])),
		"turn_order": _int_array(combat_state.get("turn_order", [])),
		"initiative": initiative,
		"current_combat_actor_id": int(combat_state.get("current_combat_actor_id", 0)),
		"next_combat_actor_id": int(combat_state.get("next_combat_actor_id", 0)),
	}


func _normalized_pending_crafting(pending: Dictionary) -> Dictionary:
	if pending.is_empty():
		return {}
	return {
		"kind": str(pending.get("kind", "")),
		"actor_id": int(pending.get("actor_id", 0)),
		"recipe_id": str(pending.get("recipe_id", "")),
		"count": int(pending.get("count", 0)),
		"required_ap": float(pending.get("required_ap", 0.0)),
		"progress_ap": float(pending.get("progress_ap", 0.0)),
		"remaining_ap": float(pending.get("remaining_ap", 0.0)),
		"available_ap": float(pending.get("available_ap", 0.0)),
	}


func _runtime_queue_has_kind(snapshot: Dictionary, kind: String) -> bool:
	for entry in _array_or_empty(snapshot.get("runtime_command_queue", [])):
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if str(entry_data.get("kind", "")) == kind:
			return true
	return false


func _inventory_count(actor: Dictionary, item_id: String) -> int:
	var inventory: Dictionary = actor.get("inventory", {})
	return int(inventory.get(item_id, 0))


func _normalized_weapon_ammo(actor: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	var weapon_ammo: Dictionary = actor.get("weapon_ammo", {})
	for slot_id in weapon_ammo.keys():
		output[str(slot_id)] = int(weapon_ammo.get(slot_id, 0))
	return output


func _normalized_resources(actor: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	var combat: Dictionary = actor.get("combat", {})
	var resources: Dictionary = combat.get("resources", {})
	for resource_id in resources.keys():
		var resource: Dictionary = resources.get(resource_id, {})
		output[str(resource_id)] = {
			"current": float(resource.get("current", 0.0)),
			"max": float(resource.get("max", 0.0)),
		}
	return output


func _normalized_progression(actor: Dictionary) -> Dictionary:
	var progression: Dictionary = actor.get("progression", {})
	return {
		"level": int(progression.get("level", 0)),
		"current_xp": int(progression.get("current_xp", 0)),
		"total_xp_earned": int(progression.get("total_xp_earned", 0)),
		"available_stat_points": int(progression.get("available_stat_points", 0)),
		"available_skill_points": int(progression.get("available_skill_points", 0)),
		"total_stat_points_earned": int(progression.get("total_stat_points_earned", 0)),
		"total_skill_points_earned": int(progression.get("total_skill_points_earned", 0)),
		"attributes": _sorted_key_values(progression.get("attributes", {})),
		"learned_skills": _sorted_key_values(progression.get("learned_skills", {})),
	}


func _normalized_active_effects(actor: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var combat: Dictionary = actor.get("combat", {})
	for effect in combat.get("active_effects", []):
		var effect_data: Dictionary = effect
		output.append({
			"effect_id": str(effect_data.get("effect_id", "")),
			"source": str(effect_data.get("source", "")),
			"skill_id": str(effect_data.get("skill_id", "")),
			"level": int(effect_data.get("level", 0)),
			"category": str(effect_data.get("category", "")),
			"duration_remaining": float(effect_data.get("duration_remaining", 0.0)),
			"is_infinite": bool(effect_data.get("is_infinite", false)),
			"modifiers": _sorted_float_key_values(effect_data.get("modifiers", {})),
		})
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("effect_id", "")) < str(b.get("effect_id", ""))
	)
	return output


func _sorted_key_values(value: Variant) -> Array[Dictionary]:
	var data: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {}
	var keys: Array = data.keys()
	keys.sort()
	var output: Array[Dictionary] = []
	for key in keys:
		output.append({
			"id": str(key),
			"value": int(data.get(key, 0)),
		})
	return output


func _sorted_float_key_values(value: Variant) -> Array[Dictionary]:
	var data: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {}
	var keys: Array = data.keys()
	keys.sort()
	var output: Array[Dictionary] = []
	for key in keys:
		output.append({
			"id": str(key),
			"value": float(data.get(key, 0.0)),
		})
	return output


func _container_count(snapshot: Dictionary, container_id: String, item_id: String) -> int:
	for container in snapshot.get("container_sessions", []):
		var container_data: Dictionary = container
		if str(container_data.get("container_id", "")) != container_id:
			continue
		for entry in container_data.get("inventory", []):
			var entry_data: Dictionary = entry
			if str(entry_data.get("item_id", "")) == item_id:
				return int(entry_data.get("count", 0))
	return 0


func _has_event(snapshot: Dictionary, kind: String) -> bool:
	for event in snapshot.get("events", []):
		var event_data: Dictionary = event
		if str(event_data.get("kind", "")) == kind:
			return true
	return false


func _last_event_payload(snapshot: Dictionary, kind: String) -> Dictionary:
	var events: Array = _array_or_empty(snapshot.get("events", []))
	for index in range(events.size() - 1, -1, -1):
		var event_data: Dictionary = _dictionary_or_empty(events[index])
		if str(event_data.get("kind", "")) == kind:
			return _dictionary_or_empty(event_data.get("payload", {}))
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _int_array(value: Variant) -> Array[int]:
	var output: Array[int] = []
	for item in _array_or_empty(value):
		output.append(int(item))
	return output


func _normalized_container_sessions(snapshot: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for container in snapshot.get("container_sessions", []):
		var container_data: Dictionary = container
		output.append({
			"container_id": str(container_data.get("container_id", "")),
			"display_name": str(container_data.get("display_name", "")),
			"money": max(0, int(container_data.get("money", 0))),
			"inventory": _normalized_inventory_entries(container_data.get("inventory", [])),
		})
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("container_id", "")) < str(b.get("container_id", ""))
	)
	return output


func _normalized_inventory_entries(entries: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for entry in entries:
		var entry_data: Dictionary = entry
		var item_id: String = str(entry_data.get("item_id", ""))
		var count: int = int(entry_data.get("count", 0))
		if item_id.is_empty() or count <= 0:
			continue
		output.append({
			"item_id": item_id,
			"count": count,
		})
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("item_id", "")) < str(b.get("item_id", ""))
	)
	return output


func _digest(snapshot: Dictionary) -> Dictionary:
	return {
		"active_map_id": snapshot.get("active_map_id", ""),
		"active_location_id": snapshot.get("active_location_id", ""),
		"active_entry_point_id": snapshot.get("active_entry_point_id", ""),
		"actor_count": snapshot.get("actors", []).size(),
		"active_quests": _active_quest_ids(snapshot),
		"completed_quests": snapshot.get("completed_quests", []),
		"crafted_recipes": snapshot.get("crafted_recipes", []),
		"container_sessions": snapshot.get("container_sessions", []),
		"shop_sessions": snapshot.get("shop_sessions", []),
		"hotbar": snapshot.get("hotbar", {}),
		"active_hotbar_group": snapshot.get("active_hotbar_group", ""),
		"hotbar_groups": snapshot.get("hotbar_groups", {}),
		"relationships": snapshot.get("relationships", []),
		"event_count": snapshot.get("events", []).size(),
		"player_inventory": _player_actor(snapshot).get("inventory", {}),
		"player_inventory_order": _player_actor(snapshot).get("inventory_order", []),
		"player_equipment": _player_actor(snapshot).get("equipment", {}),
		"player_weapon_ammo": _normalized_weapon_ammo(_player_actor(snapshot)),
		"player_active_effects": _normalized_active_effects(_player_actor(snapshot)),
		"player_money": int(_player_actor(snapshot).get("money", 0)),
	}
