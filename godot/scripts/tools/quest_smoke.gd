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
	var errors: Array[String] = _run_checks(simulation)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("quest_smoke passed:")
	print(JSON.stringify(_digest(simulation.snapshot()), "\t"))
	quit(0)


func _run_checks(simulation: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var initial_snapshot: Dictionary = simulation.snapshot()
	if not _active_quest_ids(initial_snapshot).has("tutorial_survive"):
		errors.append("tutorial_survive should auto start")
	if _active_quest_ids(initial_snapshot).has("zombie_hunter"):
		errors.append("zombie_hunter should wait for prerequisite")
	if _event_count(initial_snapshot, "quest_advanced") <= 0:
		errors.append("auto started tutorial quest should emit quest_advanced")

	var player: RefCounted = simulation.actor_registry.get_actor(1)
	player.inventory["1007"] = 1
	var quest_advanced_before_collect: int = _event_count(simulation.snapshot(), "quest_advanced")
	simulation.record_item_collected(1, "1007", 1)
	var halfway: Dictionary = simulation.snapshot()
	if _quest_progress(halfway, "tutorial_survive") != 1:
		errors.append("tutorial_survive progress should be 1 after first can")
	if _event_count(halfway, "quest_advanced") <= quest_advanced_before_collect:
		errors.append("collect quest progress should emit quest_advanced")

	player.inventory["1007"] = 2
	var quest_advanced_before_complete: int = _event_count(simulation.snapshot(), "quest_advanced")
	simulation.record_item_collected(1, "1007", 1)
	var completed: Dictionary = simulation.snapshot()
	if _active_quest_ids(completed).has("tutorial_survive"):
		errors.append("tutorial_survive should complete after second can")
	if not completed.get("completed_quests", []).has("tutorial_survive"):
		errors.append("tutorial_survive missing from completed quests")
	if not _active_quest_ids(completed).has("zombie_hunter"):
		errors.append("zombie_hunter should start after tutorial completion")
	if _event_count(completed, "quest_advanced") <= quest_advanced_before_complete:
		errors.append("quest completion and follow-up start should emit quest_advanced")
	return errors


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


func _event_count(snapshot: Dictionary, kind: String) -> int:
	var count := 0
	for event in snapshot.get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			count += 1
	return count


func _digest(snapshot: Dictionary) -> Dictionary:
	return {
		"active_quests": snapshot.get("active_quests", []),
		"completed_quests": snapshot.get("completed_quests", []),
		"event_count": snapshot.get("events", []).size(),
	}
