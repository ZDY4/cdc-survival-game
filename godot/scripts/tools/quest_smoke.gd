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
	errors.append_array(_expect_structured_prerequisites(registry))
	errors.append_array(_expect_state_reward_quest(simulation, registry))
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
	var hud_snapshot: Dictionary = _hud_snapshot(simulation, registry)
	var parts: Array[String] = []
	for entry in hud_snapshot.get("event_feedback", []):
		var data: Dictionary = _dictionary_or_empty(entry)
		var text := str(data.get("text", ""))
		if not text.is_empty():
			parts.append(text)
	return " | ".join(parts)


func _hud_snapshot(simulation: RefCounted, registry: RefCounted) -> Dictionary:
	var runtime_snapshot: Dictionary = simulation.snapshot()
	var world_snapshot: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(runtime_snapshot)
	return HudSnapshot.new(registry).build(runtime_snapshot, world_snapshot, {})


func _expect_state_reward_quest(simulation: RefCounted, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	if player == null:
		return ["state reward quest setup missing player"]
	simulation.quest_library["quest_reward_state_smoke"] = {
		"data": {
			"quest_id": "quest_reward_state_smoke",
			"title": "状态奖励测试",
			"description": "smoke-only state reward quest",
			"flow": {
				"nodes": {
					"step_1": {
						"id": "step_1",
						"type": "objective",
						"objective_type": "collect",
						"item_id": 1007,
						"count": 1,
					},
					"reward_1": {
						"id": "reward_1",
						"type": "reward",
						"rewards": {
							"money": 13,
							"unlock_locations": ["quest_reward_smoke_location"],
							"world_flags": ["quest_reward_smoke_flag"],
							"relationships": [
								{
									"target_definition_id": "trader_lao_wang",
									"delta": 9,
								},
							],
						},
					},
				},
			},
		},
	}
	var money_before: int = player.money
	var relationship_before := float(simulation.relationship_score(1, 2))
	if not simulation.start_quest(1, "quest_reward_state_smoke"):
		errors.append("state reward quest should start")
	player.inventory["1007"] = int(player.inventory.get("1007", 0)) + 1
	simulation.record_item_collected(1, "1007", 1)
	var snapshot: Dictionary = simulation.snapshot()
	if _active_quest_ids(snapshot).has("quest_reward_state_smoke"):
		errors.append("state reward quest should complete after collect")
	if not snapshot.get("completed_quests", []).has("quest_reward_state_smoke"):
		errors.append("state reward quest should enter completed quests")
	if player.money != money_before + 13:
		errors.append("state reward quest should grant money")
	if not simulation.unlocked_locations.has("quest_reward_smoke_location"):
		errors.append("state reward quest should unlock location")
	if not simulation.world_flags.has("quest_reward_smoke_flag"):
		errors.append("state reward quest should set world flag")
	if absf(float(simulation.relationship_score(1, 2)) - (relationship_before + 9.0)) > 0.001:
		errors.append("state reward quest should adjust trader relationship")
	var reward_payload: Dictionary = _last_event_payload(snapshot, "quest_reward_granted")
	if int(reward_payload.get("money", 0)) != 13:
		errors.append("quest_reward_granted should include money")
	if not _array_or_empty(reward_payload.get("unlocked_locations", [])).has("quest_reward_smoke_location"):
		errors.append("quest_reward_granted should include unlocked location")
	if not _array_or_empty(reward_payload.get("world_flags", [])).has("quest_reward_smoke_flag"):
		errors.append("quest_reward_granted should include world flag")
	var relationship_changes: Array = _array_or_empty(reward_payload.get("relationship_changes", []))
	if relationship_changes.is_empty():
		errors.append("quest_reward_granted should include relationship changes")
	else:
		var relationship_change: Dictionary = _dictionary_or_empty(relationship_changes[0])
		if absf(float(relationship_change.get("score_delta", 0.0)) - 9.0) > 0.001:
			errors.append("quest relationship reward should expose score_delta")
		if str(relationship_change.get("actor_name", "")).is_empty() or str(relationship_change.get("target_actor_name", "")).is_empty():
			errors.append("quest relationship reward should expose actor display names")
	var feedback_text := _hud_feedback_text(simulation, registry)
	if not feedback_text.contains("金钱 13"):
		errors.append("HUD reward feedback should include money, got %s" % feedback_text)
	if not feedback_text.contains("解锁地点 1"):
		errors.append("HUD reward feedback should include unlocked location count, got %s" % feedback_text)
	if not feedback_text.contains("世界状态 1"):
		errors.append("HUD reward feedback should include world flag count, got %s" % feedback_text)
	if not feedback_text.contains("关系") or not feedback_text.contains("+9"):
		errors.append("HUD reward feedback should include relationship delta details, got %s" % feedback_text)
	var hud_snapshot: Dictionary = _hud_snapshot(simulation, registry)
	var reward_detail: Dictionary = _feedback_detail_by_kind(hud_snapshot, "quest_reward_granted")
	if reward_detail.is_empty():
		errors.append("HUD should expose structured quest reward feedback details")
	else:
		if int(reward_detail.get("entry_count", 0)) < 4:
			errors.append("quest reward feedback details should expose reward entries: %s" % reward_detail)
		if not _feedback_detail_has_entry(reward_detail, "money", 13):
			errors.append("quest reward feedback details should include money 13: %s" % reward_detail)
		if not _feedback_detail_has_entry(reward_detail, "location", 1, "quest_reward_smoke_location"):
			errors.append("quest reward feedback details should include unlocked location id: %s" % reward_detail)
		if not _feedback_detail_has_entry(reward_detail, "world_flag", 1, "quest_reward_smoke_flag"):
			errors.append("quest reward feedback details should include world flag id: %s" % reward_detail)
		if not _feedback_detail_has_kind(reward_detail, "relationship"):
			errors.append("quest reward feedback details should include relationship delta: %s" % reward_detail)
	var reward_toast: Dictionary = _feedback_toast_by_kind(hud_snapshot, "quest_reward_granted")
	if reward_toast.is_empty() or not bool(reward_toast.get("has_details", false)):
		errors.append("quest reward toast should carry structured details: %s" % reward_toast)
	return errors


func _expect_structured_prerequisites(registry: RefCounted) -> Array[String]:
	var simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var errors: Array[String] = []
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	if player == null:
		return ["structured prerequisite smoke missing player"]
	simulation.quest_library["quest_structured_prerequisite_smoke"] = {
		"data": {
			"quest_id": "quest_structured_prerequisite_smoke",
			"title": "结构化前置测试",
			"description": "smoke-only structured prerequisite quest",
			"prerequisites": [
				"tutorial_survive",
				{"world_flags_all": ["quest_prereq_flag", "quest_prereq_flag_all"]},
				{"type": "world_flags_any", "ids": ["quest_prereq_flag_any_a", "quest_prereq_flag_any_b"]},
				{"type": "world_flags_none", "ids": ["quest_prereq_flag_blocked"]},
				{"type": "item", "item_id": "1007", "count": 2},
				{"type": "relationship", "target_definition_id": "trader_lao_wang", "min": 80},
			],
			"flow": {
				"nodes": {
					"step_1": {
						"id": "step_1",
						"type": "objective",
						"objective_type": "collect",
						"item_id": 1008,
						"count": 1,
					},
				},
			},
		},
	}
	if simulation.start_quest(1, "quest_structured_prerequisite_smoke"):
		errors.append("structured prerequisite quest should not start before prerequisites")
	simulation.completed_quests["tutorial_survive"] = true
	if simulation.start_quest(1, "quest_structured_prerequisite_smoke"):
		errors.append("structured prerequisite quest should wait for all world flags")
	simulation.world_flags["quest_prereq_flag"] = true
	if simulation.start_quest(1, "quest_structured_prerequisite_smoke"):
		errors.append("structured prerequisite quest should wait for second all-world flag")
	simulation.world_flags["quest_prereq_flag_all"] = true
	if simulation.start_quest(1, "quest_structured_prerequisite_smoke"):
		errors.append("structured prerequisite quest should wait for any-world flag")
	simulation.world_flags["quest_prereq_flag_any_b"] = true
	simulation.world_flags["quest_prereq_flag_blocked"] = true
	if simulation.start_quest(1, "quest_structured_prerequisite_smoke"):
		errors.append("structured prerequisite quest should reject blocked none-world flag")
	simulation.world_flags.erase("quest_prereq_flag_blocked")
	if simulation.start_quest(1, "quest_structured_prerequisite_smoke"):
		errors.append("structured prerequisite quest should wait for required item")
	player.inventory["1007"] = 2
	if simulation.start_quest(1, "quest_structured_prerequisite_smoke"):
		errors.append("structured prerequisite quest should wait for relationship score")
	simulation.set_relationship_score(1, 2, 85.0, "quest_prerequisite_smoke")
	if not simulation.start_quest(1, "quest_structured_prerequisite_smoke"):
		errors.append("structured prerequisite quest should start after all prerequisites")
	var snapshot: Dictionary = simulation.snapshot()
	if not _active_quest_ids(snapshot).has("quest_structured_prerequisite_smoke"):
		errors.append("structured prerequisite quest should be active after successful start")
	return errors


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _last_event_payload(snapshot: Dictionary, kind: String) -> Dictionary:
	var events: Array = snapshot.get("events", [])
	for index in range(events.size() - 1, -1, -1):
		var event_data: Dictionary = _dictionary_or_empty(events[index])
		if str(event_data.get("kind", "")) == kind:
			return _dictionary_or_empty(event_data.get("payload", {}))
	return {}


func _feedback_detail_by_kind(hud_snapshot: Dictionary, kind: String) -> Dictionary:
	var details: Array = _array_or_empty(hud_snapshot.get("feedback_details", []))
	for index in range(details.size() - 1, -1, -1):
		var detail: Dictionary = _dictionary_or_empty(details[index])
		if str(detail.get("kind", "")) == kind:
			return detail
	return {}


func _feedback_toast_by_kind(hud_snapshot: Dictionary, kind: String) -> Dictionary:
	var toasts: Array = _array_or_empty(hud_snapshot.get("feedback_toasts", []))
	for index in range(toasts.size() - 1, -1, -1):
		var toast: Dictionary = _dictionary_or_empty(toasts[index])
		if str(toast.get("kind", "")) == kind:
			return toast
	return {}


func _feedback_detail_has_kind(detail: Dictionary, kind: String) -> bool:
	for value in _array_or_empty(detail.get("entries", [])):
		var entry: Dictionary = _dictionary_or_empty(value)
		if str(entry.get("kind", "")) == kind:
			return true
	return false


func _feedback_detail_has_entry(detail: Dictionary, kind: String, amount: Variant, detail_text: String = "") -> bool:
	for value in _array_or_empty(detail.get("entries", [])):
		var entry: Dictionary = _dictionary_or_empty(value)
		if str(entry.get("kind", "")) != kind:
			continue
		if str(entry.get("amount", "")) != str(amount):
			continue
		if not detail_text.is_empty() and str(entry.get("detail", "")) != detail_text:
			continue
		return true
	return false


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _digest(snapshot: Dictionary) -> Dictionary:
	return {
		"active_quests": snapshot.get("active_quests", []),
		"completed_quests": snapshot.get("completed_quests", []),
		"event_count": snapshot.get("events", []).size(),
	}
