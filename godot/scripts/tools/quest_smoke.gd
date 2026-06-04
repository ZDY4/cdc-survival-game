extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")
const HudSnapshot = preload("res://scripts/ui/snapshots/hud_snapshot.gd")


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

	print("quest_smoke passed:")
	print(JSON.stringify(_digest(simulation.snapshot()), "\t"))
	quit(0)


func _run_checks(simulation: RefCounted, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var initial_snapshot: Dictionary = simulation.snapshot()
	if not _active_quest_ids(initial_snapshot).has("tutorial_survive"):
		errors.append("tutorial_survive should auto start")
	if _active_quest_ids(initial_snapshot).has("zombie_hunter"):
		errors.append("zombie_hunter should wait for prerequisite")
	if _event_count(initial_snapshot, "quest_advanced") <= 0:
		errors.append("auto started tutorial quest should emit quest_advanced")
	if not _hud_feedback_text(simulation, registry).contains("任务开始: 补给试跑"):
		errors.append("HUD feedback should show auto-started quest")

	var player: RefCounted = simulation.actor_registry.get_actor(1)
	player.inventory["1007"] = 1
	var quest_advanced_before_collect: int = _event_count(simulation.snapshot(), "quest_advanced")
	simulation.record_item_collected(1, "1007", 1)
	var halfway: Dictionary = simulation.snapshot()
	if _quest_progress(halfway, "tutorial_survive") != 1:
		errors.append("tutorial_survive progress should be 1 after first can")
	if _event_count(halfway, "quest_advanced") <= quest_advanced_before_collect:
		errors.append("collect quest progress should emit quest_advanced")
	if not _hud_feedback_text(simulation, registry).contains("任务进度: 补给试跑 1/2"):
		errors.append("HUD feedback should show collect quest progress")

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
	var completed_feedback := _hud_feedback_text(simulation, registry)
	if not completed_feedback.contains("任务完成: 补给试跑"):
		errors.append("HUD feedback should show quest completion, got %s" % completed_feedback)
	if not completed_feedback.contains("任务奖励: 补给试跑"):
		errors.append("HUD feedback should show quest reward, got %s" % completed_feedback)
	if not completed_feedback.contains("任务开始: 警戒区清剿"):
		errors.append("HUD feedback should show follow-up quest start, got %s" % completed_feedback)
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


func _hud_feedback_text(simulation: RefCounted, registry: RefCounted) -> String:
	var runtime_snapshot: Dictionary = simulation.snapshot()
	var world_snapshot: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(runtime_snapshot)
	var hud_snapshot: Dictionary = HudSnapshot.new(registry).build(runtime_snapshot, world_snapshot, {})
	var parts: Array[String] = []
	for entry in hud_snapshot.get("event_feedback", []):
		var data: Dictionary = _dictionary_or_empty(entry)
		var text := str(data.get("text", ""))
		if not text.is_empty():
			parts.append(text)
	return " | ".join(parts)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _digest(snapshot: Dictionary) -> Dictionary:
	return {
		"active_quests": snapshot.get("active_quests", []),
		"completed_quests": snapshot.get("completed_quests", []),
		"event_count": snapshot.get("events", []).size(),
	}
