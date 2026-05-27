extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
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
	var errors: Array[String] = _run_checks(simulation, registry)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("combat_smoke passed:")
	print(JSON.stringify(_digest(simulation.snapshot()), "\t"))
	quit(0)


func _run_checks(simulation: RefCounted, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	simulation.record_item_collected(1, "1007", 2)
	if not _active_quest_ids(simulation.snapshot()).has("zombie_hunter"):
		return ["zombie_hunter did not start after tutorial completion"]

	var zombie_a: int = _register_character(simulation, registry, "zombie_walker", {"x": 2, "y": 0, "z": 0})
	var zombie_b: int = _register_character(simulation, registry, "zombie_walker", {"x": 3, "y": 0, "z": 0})
	_force_combat_values(simulation, zombie_a)
	_force_combat_values(simulation, zombie_b)

	var first: Dictionary = simulation.perform_attack(1, zombie_a)
	if not bool(first.get("success", false)) or not bool(first.get("defeated", false)):
		errors.append("first zombie attack should defeat target")
	if _quest_progress(simulation.snapshot(), "zombie_hunter") != 1:
		errors.append("zombie_hunter progress should be 1 after first kill")

	var second: Dictionary = simulation.perform_attack(1, zombie_b)
	if not bool(second.get("success", false)) or not bool(second.get("defeated", false)):
		errors.append("second zombie attack should defeat target")
	var snapshot: Dictionary = simulation.snapshot()
	if _active_quest_ids(snapshot).has("zombie_hunter"):
		errors.append("zombie_hunter should complete after two kills")
	if not snapshot.get("completed_quests", []).has("zombie_hunter"):
		errors.append("zombie_hunter missing from completed quests")
	return errors


func _register_character(simulation: RefCounted, registry: RefCounted, definition_id: String, grid: Dictionary) -> int:
	var record: Dictionary = registry.get_library("characters").get(definition_id, {})
	var data: Dictionary = record.get("data", {})
	var identity: Dictionary = data.get("identity", {})
	var faction: Dictionary = data.get("faction", {})
	var combat: Dictionary = data.get("combat", {})
	var attributes: Dictionary = data.get("attributes", {})
	var sets: Dictionary = attributes.get("sets", {})
	var combat_attributes: Dictionary = sets.get("combat", {})
	var resources: Dictionary = attributes.get("resources", {})
	var hp: Dictionary = resources.get("hp", {})
	return simulation.register_actor({
		"definition_id": definition_id,
		"display_name": str(identity.get("display_name", definition_id)),
		"kind": "enemy",
		"side": str(faction.get("disposition", "hostile")),
		"group_id": str(faction.get("camp_id", "infected")),
		"grid_position": GridCoord.from_dictionary(grid),
		"max_hp": float(combat_attributes.get("max_hp", 1.0)),
		"hp": float(hp.get("current", combat_attributes.get("max_hp", 1.0))),
		"attack_power": float(combat_attributes.get("attack_power", 1.0)),
		"defense": float(combat_attributes.get("defense", 0.0)),
		"xp_reward": int(combat.get("xp_reward", 0)),
	})


func _force_combat_values(simulation: RefCounted, actor_id: int) -> void:
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	var target: RefCounted = simulation.actor_registry.get_actor(actor_id)
	player.attack_power = 10.0
	target.hp = 5.0
	target.max_hp = 5.0
	target.defense = 0.0


func _active_quest_ids(snapshot: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for quest in snapshot.get("active_quests", []):
		var quest_data: Dictionary = quest
		output.append(str(quest_data.get("quest_id", "")))
	return output


func _quest_progress(snapshot: Dictionary, quest_id: String) -> int:
	for quest in snapshot.get("active_quests", []):
		var quest_data: Dictionary = quest
		if quest_data.get("quest_id", "") == quest_id:
			var completed: Dictionary = quest_data.get("completed_objectives", {})
			return int(completed.get("step_1", 0))
	return 0


func _digest(snapshot: Dictionary) -> Dictionary:
	return {
		"active_quests": snapshot.get("active_quests", []),
		"completed_quests": snapshot.get("completed_quests", []),
		"actors": snapshot.get("actors", []).size(),
		"event_count": snapshot.get("events", []).size(),
	}
