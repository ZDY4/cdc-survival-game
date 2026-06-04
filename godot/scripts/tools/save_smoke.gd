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
	simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_interior_door",
	})
	simulation.buy_item_from_shop(1, "trader_lao_wang_shop", "1006", 1, registry.get_library("items"))
	simulation.sell_item_to_shop(1, "trader_lao_wang_shop", "1006", 1, registry.get_library("items"))
	simulation.equip_item(1, "1003", "main_hand", registry.get_library("items"))
	var player_for_reload: RefCounted = simulation.actor_registry.get_actor(1)
	player_for_reload.inventory["1004"] = 1
	player_for_reload.inventory["1009"] = 3
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
	var topology: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot()).get("map", {})
	simulation.set_actor_vision_radius(1, 4)
	simulation.refresh_actor_vision(1, topology)
	simulation.record_item_collected(1, "1007", 2)
	var zombie: int = _register_zombie(simulation, registry)
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	var target: RefCounted = simulation.actor_registry.get_actor(zombie)
	simulation.decide_actor_intent(zombie)
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
	if JSON.stringify(player_restored.get("inventory_order", [])) != JSON.stringify(player_original.get("inventory_order", [])):
		errors.append("player inventory_order did not roundtrip")
	if _inventory_count(player_restored, "1031") != 1:
		errors.append("taken container item did not roundtrip in player inventory")
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
	if JSON.stringify(_actor_vision_snapshot(restored, 1)) != JSON.stringify(_actor_vision_snapshot(original, 1)):
		errors.append("player vision did not roundtrip")
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
	legacy.erase("corpse_containers")
	legacy.erase("interaction_menu")
	legacy.erase("hotbar")
	var restored_simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	restored_simulation.load_snapshot(legacy)
	var restored: Dictionary = restored_simulation.snapshot()
	if int(restored.get("schema_version", 0)) != 1:
		errors.append("legacy snapshot migration should restore current schema_version")
	if str(restored.get("active_location_id", "")) != str(snapshot.get("start_location_id", "")):
		errors.append("legacy snapshot migration should default active_location_id from start_location_id")
	if str(restored.get("active_entry_point_id", "")) != str(snapshot.get("start_entry_point_id", "")):
		errors.append("legacy snapshot migration should default active_entry_point_id from start_entry_point_id")
	for key in ["turn_state", "combat_state", "pending_movement", "pending_interaction", "corpse_containers", "interaction_menu", "hotbar"]:
		if not restored.has(key):
			errors.append("legacy snapshot migration missing %s" % key)
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
		"hotbar": snapshot.get("hotbar", {}),
		"event_count": snapshot.get("events", []).size(),
		"player_inventory": _player_actor(snapshot).get("inventory", {}),
		"player_inventory_order": _player_actor(snapshot).get("inventory_order", []),
		"player_equipment": _player_actor(snapshot).get("equipment", {}),
		"player_weapon_ammo": _normalized_weapon_ammo(_player_actor(snapshot)),
		"player_active_effects": _normalized_active_effects(_player_actor(snapshot)),
		"player_money": int(_player_actor(snapshot).get("money", 0)),
	}
