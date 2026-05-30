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
	var snapshot: Dictionary = runtime_result.get("snapshot", {})
	var errors := _validate_new_game_snapshot(snapshot)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("runtime_smoke passed:")
	print(JSON.stringify(_snapshot_digest(snapshot), "\t"))
	quit(0)


func _validate_new_game_snapshot(snapshot: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if snapshot.get("active_map_id", "") != "survivor_outpost_01":
		errors.append("expected active_map_id survivor_outpost_01")

	var actors: Array = snapshot.get("actors", [])
	if actors.size() != 3:
		errors.append("expected 3 startup actors, got %d" % actors.size())

	var expected_positions := {
		"player": {"x": 24, "y": 0, "z": 39},
		"trader_lao_wang": {"x": 1, "y": 0, "z": 0},
		"doctor_chen": {"x": 33, "y": 0, "z": 10},
	}
	for actor in actors:
		var definition_id := str(actor.get("definition_id", ""))
		if not expected_positions.has(definition_id):
			errors.append("unexpected startup actor %s" % definition_id)
			continue
		if str(actor.get("map_id", "")) != "survivor_outpost_01":
			errors.append("%s should start on survivor_outpost_01" % definition_id)
		var expected: Dictionary = expected_positions[definition_id]
		var actual: Dictionary = actor.get("grid_position", {})
		for axis in ["x", "y", "z"]:
			if int(actual.get(axis, -9999)) != int(expected[axis]):
				errors.append("%s expected %s=%d, got %s" % [definition_id, axis, expected[axis], actual.get(axis)])

	if _event_count(snapshot, "actor_registered") != 3:
		errors.append("expected 3 actor_registered events")
	if not _active_quest_ids(snapshot).has("tutorial_survive"):
		errors.append("expected tutorial_survive to auto start")
	var player: Dictionary = _actor_by_definition(snapshot, "player")
	var inventory: Dictionary = player.get("inventory", {})
	var equipment: Dictionary = player.get("equipment", {})
	if int(player.get("money", 0)) != 100:
		errors.append("expected default player money 100")
	if int(inventory.get("1009", 0)) != 10:
		errors.append("expected bootstrap ammo 1009 x10")
	if int(inventory.get("1006", 0)) != 1:
		errors.append("expected bootstrap item 1006 x1")
	if equipment.get("main_hand", "") != "1002":
		errors.append("expected bootstrap main_hand equipment 1002")
	if equipment.get("body", "") != "2004":
		errors.append("expected bootstrap body equipment 2004")
	if snapshot.get("shop_sessions", []).size() <= 0:
		errors.append("expected runtime shop session")
	return errors


func _snapshot_digest(snapshot: Dictionary) -> Dictionary:
	var actors: Array[String] = []
	for actor in snapshot.get("actors", []):
		actors.append("%s#%d" % [actor.get("definition_id", ""), int(actor.get("actor_id", 0))])
	return {
		"active_map_id": snapshot.get("active_map_id", ""),
		"actors": actors,
		"active_quests": _active_quest_ids(snapshot),
		"player_inventory": _actor_by_definition(snapshot, "player").get("inventory", {}),
		"player_equipment": _actor_by_definition(snapshot, "player").get("equipment", {}),
		"shop_sessions": snapshot.get("shop_sessions", []).size(),
		"event_count": snapshot.get("events", []).size(),
	}


func _event_count(snapshot: Dictionary, kind: String) -> int:
	var count := 0
	for event in snapshot.get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			count += 1
	return count


func _active_quest_ids(snapshot: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for quest in snapshot.get("active_quests", []):
		var quest_data: Dictionary = quest
		output.append(str(quest_data.get("quest_id", "")))
	return output


func _actor_by_definition(snapshot: Dictionary, definition_id: String) -> Dictionary:
	for actor in snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if str(actor_data.get("definition_id", "")) == definition_id:
			return actor_data
	return {}
