extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const SaveService = preload("res://scripts/app/save_service.gd")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")


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
		"target_id": "survivor_outpost_01_interior_door",
	})
	simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_clinic_supply_cabinet",
	})
	simulation.take_item_from_container(1, "survivor_outpost_01_clinic_supply_cabinet", "1031", 1, registry.get_library("items"))
	simulation.store_item_in_container(1, "survivor_outpost_01_clinic_supply_cabinet", "1008", 1, registry.get_library("items"))
	simulation.buy_item_from_shop(1, "trader_lao_wang_shop", "1006", 1, registry.get_library("items"))
	simulation.sell_item_to_shop(1, "trader_lao_wang_shop", "1006", 1, registry.get_library("items"))
	simulation.equip_item(1, "1003", "main_hand", registry.get_library("items"))
	simulation.record_item_collected(1, "1007", 2)
	var zombie: int = _register_zombie(simulation, registry)
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	var target: RefCounted = simulation.actor_registry.get_actor(zombie)
	player.attack_power = 10.0
	target.hp = 5.0
	target.defense = 0.0
	simulation.perform_attack(1, zombie)


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

	for key in ["active_map_id", "active_location_id", "active_entry_point_id", "consumed_interaction_targets", "completed_quests"]:
		if JSON.stringify(restored.get(key)) != JSON.stringify(original.get(key)):
			errors.append("snapshot field mismatch: %s" % key)
	if JSON.stringify(_normalized_container_sessions(restored)) != JSON.stringify(_normalized_container_sessions(original)):
		errors.append("container sessions did not roundtrip")
	if JSON.stringify(restored.get("shop_sessions")) != JSON.stringify(original.get("shop_sessions")):
		errors.append("shop sessions did not roundtrip")
	if int(restored.get("schema_version", 0)) != int(original.get("schema_version", 0)):
		errors.append("snapshot schema_version did not restore")
	var player_original: Dictionary = _player_actor(original)
	var player_restored: Dictionary = _player_actor(restored)
	if _inventory_count(player_restored, "1006") != _inventory_count(player_original, "1006"):
		errors.append("player inventory did not roundtrip")
	if _inventory_count(player_restored, "1031") != 1:
		errors.append("taken container item did not roundtrip in player inventory")
	if JSON.stringify(player_restored.get("equipment", {})) != JSON.stringify(player_original.get("equipment", {})):
		errors.append("player equipment did not roundtrip")
	if player_restored.get("active_dialogue_id", "") != "trader_lao_wang":
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
	if restored.get("events", []).size() != original.get("events", []).size():
		errors.append("event count did not roundtrip")
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


func _inventory_count(actor: Dictionary, item_id: String) -> int:
	var inventory: Dictionary = actor.get("inventory", {})
	return int(inventory.get(item_id, 0))


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


func _normalized_container_sessions(snapshot: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for container in snapshot.get("container_sessions", []):
		var container_data: Dictionary = container
		output.append({
			"container_id": str(container_data.get("container_id", "")),
			"display_name": str(container_data.get("display_name", "")),
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
		"container_sessions": snapshot.get("container_sessions", []),
		"shop_sessions": snapshot.get("shop_sessions", []),
		"event_count": snapshot.get("events", []).size(),
		"player_inventory": _player_actor(snapshot).get("inventory", {}),
		"player_equipment": _player_actor(snapshot).get("equipment", {}),
		"player_money": int(_player_actor(snapshot).get("money", 0)),
	}
