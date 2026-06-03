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

	print("equipment_smoke passed:")
	print(JSON.stringify(_digest(simulation.snapshot()), "\t"))
	quit(0)


func _run_checks(simulation: RefCounted, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var items: Dictionary = registry.get_library("items")
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	if player == null:
		return ["player actor missing"]

	var equipment: Dictionary = player.equipment
	if equipment.get("main_hand", "") != "1002":
		errors.append("bootstrap main_hand equipment missing")
	if equipment.get("body", "") != "2004":
		errors.append("bootstrap body equipment missing")
	if int(player.inventory.get("1002", 0)) != 0:
		errors.append("bootstrap equipped knife should leave inventory")

	var equipped_event_count: int = _event_count(simulation.snapshot(), "item_equipped")
	var replace_result: Dictionary = simulation.equip_item(1, "1003", "main_hand", items)
	if not bool(replace_result.get("success", false)):
		errors.append("baseball bat equip failed: %s" % replace_result.get("reason", "unknown"))
	if replace_result.get("previous_item_id", "") != "1002":
		errors.append("equip should return previous main_hand item")
	if player.equipment.get("main_hand", "") != "1003":
		errors.append("main_hand did not switch to baseball bat")
	if int(player.inventory.get("1003", 0)) != 0:
		errors.append("equipped baseball bat should leave inventory")
	if int(player.inventory.get("1002", 0)) != 1:
		errors.append("replaced knife should return to inventory")
	if _event_count(simulation.snapshot(), "item_equipped") != equipped_event_count + 1:
		errors.append("manual equip did not emit item_equipped")

	var invalid_slot: Dictionary = simulation.equip_item(1, "1003", "body", items)
	if invalid_slot.get("reason", "") != "invalid_equipment_slot":
		errors.append("weapon equip to body should report invalid_equipment_slot")

	var unequipped_event_count: int = _event_count(simulation.snapshot(), "item_unequipped")
	var unequip_result: Dictionary = simulation.unequip_item(1, "main_hand")
	if not bool(unequip_result.get("success", false)):
		errors.append("main_hand unequip failed: %s" % unequip_result.get("reason", "unknown"))
	if player.equipment.has("main_hand"):
		errors.append("main_hand should be empty after unequip")
	if int(player.inventory.get("1003", 0)) != 1:
		errors.append("unequipped baseball bat should return to inventory")
	if _event_count(simulation.snapshot(), "item_unequipped") != unequipped_event_count + 1:
		errors.append("unequip did not emit item_unequipped")

	var empty_slot: Dictionary = simulation.unequip_item(1, "main_hand")
	if empty_slot.get("reason", "") != "empty_equipment_slot":
		errors.append("empty slot unequip should report empty_equipment_slot")
	var not_equippable: Dictionary = simulation.equip_item(1, "1006", "main_hand", items)
	if not_equippable.get("reason", "") != "item_not_equippable":
		errors.append("consumable equip should report item_not_equippable")
	player.inventory["1004"] = 1
	player.inventory["1009"] = 5
	var equip_pistol: Dictionary = simulation.equip_item(1, "1004", "main_hand", items)
	if not bool(equip_pistol.get("success", false)):
		errors.append("pistol equip for reload failed: %s" % equip_pistol.get("reason", "unknown"))
	player.ap = 6.0
	var reloaded_event_count: int = _event_count(simulation.snapshot(), "weapon_reloaded")
	var reload_result: Dictionary = simulation.submit_player_command({
		"kind": "inventory_action",
		"actor_id": 1,
		"action": "reload_equipped",
		"slot_id": "main_hand",
		"item_library": items,
	})
	if not bool(reload_result.get("success", false)):
		errors.append("reload equipped pistol failed: %s" % reload_result.get("reason", "unknown"))
	if int(player.weapon_ammo.get("main_hand", 0)) != 5:
		errors.append("reload should move available pistol ammo into main hand magazine")
	if int(player.inventory.get("1009", 0)) != 0:
		errors.append("reload should consume pistol ammo from inventory")
	if absf(player.ap - 4.0) > 0.01:
		errors.append("reload should consume reload_time AP")
	if _event_count(simulation.snapshot(), "weapon_reloaded") != reloaded_event_count + 1:
		errors.append("reload should emit weapon_reloaded")
	var reload_without_ammo: Dictionary = simulation.submit_player_command({
		"kind": "inventory_action",
		"actor_id": 1,
		"action": "reload_equipped",
		"slot_id": "main_hand",
		"item_library": items,
	})
	if str(reload_without_ammo.get("reason", "")) != "ammo_insufficient":
		errors.append("reload without spare ammo should report ammo_insufficient")
	player.inventory["1003"] = 1
	var equip_bat_after_reload: Dictionary = simulation.equip_item(1, "1003", "main_hand", items)
	if not bool(equip_bat_after_reload.get("success", false)):
		errors.append("re-equipping bat after reload failed: %s" % equip_bat_after_reload.get("reason", "unknown"))
	if player.weapon_ammo.has("main_hand"):
		errors.append("replacing weapon should clear main hand magazine state")
	return errors


func _event_count(snapshot: Dictionary, kind: String) -> int:
	var count := 0
	for event in snapshot.get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			count += 1
	return count


func _digest(snapshot: Dictionary) -> Dictionary:
	var player: Dictionary = _player_actor(snapshot)
	return {
		"event_count": snapshot.get("events", []).size(),
		"player_inventory": player.get("inventory", {}),
		"player_equipment": player.get("equipment", {}),
		"player_weapon_ammo": player.get("weapon_ammo", {}),
	}


func _player_actor(snapshot: Dictionary) -> Dictionary:
	for actor in snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return actor_data
	return {}
