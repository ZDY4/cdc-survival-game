extends Node
# QuestSystem - 步骤流任务系统

signal quest_started(quest_id: String)
signal quest_updated(quest_id: String, progress: Dictionary)
signal quest_completed(quest_id: String, rewards: Dictionary)
signal quest_failed(quest_id: String, reason: String)

const SAVE_FORMAT_VERSION := 2

var QUESTS: Dictionary = {}

var active_quests: Dictionary = {}
var completed_quests: Array[String] = []
var failed_quests: Array[String] = []


func _ready() -> void:
	_refresh_quest_templates()
	_subscribe_events()
	_connect_build_events()
	print("[QuestSystem] 任务系统已初始化，已加载 %d 个任务" % QUESTS.size())


func _subscribe_events() -> void:
	EventBus.subscribe(EventBus.EventType.GAME_SAVED, _on_game_saved)
	EventBus.subscribe(EventBus.EventType.COMBAT_ENDED, _on_combat_ended)
	EventBus.subscribe(EventBus.EventType.LOCATION_CHANGED, _on_location_changed)
	EventBus.subscribe(EventBus.EventType.ITEM_ACQUIRED, _on_item_acquired)
	EventBus.subscribe(EventBus.EventType.CRAFTING_COMPLETED, _on_crafting_completed)


func _connect_build_events() -> void:
	if BaseBuildingModule and BaseBuildingModule.has_signal("structure_built"):
		var callback := Callable(self, "_on_structure_built")
		if not BaseBuildingModule.structure_built.is_connected(callback):
			BaseBuildingModule.structure_built.connect(callback)


func _refresh_quest_templates() -> void:
	if DataManager and DataManager.has_method("reload_category"):
		DataManager.reload_category("quests")
	if DataManager and DataManager.has_method("get_all_quests"):
		QUESTS = DataManager.get_all_quests().duplicate(true)
	else:
		QUESTS.clear()


func has_quest(quest_id: String) -> bool:
	return QUESTS.has(quest_id)


func get_quest_template(quest_id: String) -> Dictionary:
	return QUESTS.get(quest_id, {})


func is_quest_active(quest_id: String) -> bool:
	return active_quests.has(quest_id)


func is_quest_completed(quest_id: String) -> bool:
	return completed_quests.has(quest_id)


func start_quest(quest_id: String) -> bool:
	if QUESTS.is_empty():
		_refresh_quest_templates()

	if not QUESTS.has(quest_id):
		push_error("[QuestSystem] Quest not found: %s" % quest_id)
		return false

	if active_quests.has(quest_id) or completed_quests.has(quest_id):
		return false

	var quest_template: Dictionary = QUESTS[quest_id]
	for prereq_variant in quest_template.get("prerequisites", []):
		var prereq_id := str(prereq_variant)
		if not completed_quests.has(prereq_id):
			print("[QuestSystem] 前置任务未完成: %s -> %s" % [prereq_id, quest_id])
			return false

	var flow: Dictionary = quest_template.get("flow", {})
	var start_node_id := str(flow.get("start_node_id", "start"))
	if start_node_id.is_empty():
		start_node_id = "start"

	active_quests[quest_id] = {
		"id": quest_id,
		"start_day": int(GameState.world_day) if GameState else 0,
		"start_time": int(Time.get_unix_time_from_system()),
		"current_node_id": start_node_id,
		"visited_nodes": [],
		"completed_objectives": {},
		"granted_reward_nodes": [],
		"awaiting_kind": "",
		"awaiting_node_id": ""
	}

	print("[QuestSystem] 开始任务: %s" % quest_id)
	quest_started.emit(quest_id)

	if DialogModule:
		DialogModule.show_dialog(
			"任务开始：%s\n%s" % [
				str(quest_template.get("title", quest_id)),
				str(quest_template.get("description", ""))
			],
			"任务",
			""
		)

	advance_active_quest(quest_id)
	return true


func advance_active_quest(quest_id: String) -> void:
	while active_quests.has(quest_id):
		var quest_state: Dictionary = active_quests[quest_id]
		var node_id := str(quest_state.get("current_node_id", ""))
		if node_id.is_empty():
			_fail_quest(quest_id, "current_node_id 为空")
			return

		var node := _get_quest_node(quest_id, node_id)
		if node.is_empty():
			_fail_quest(quest_id, "节点不存在: %s" % node_id)
			return

		_mark_node_visited(quest_id, node_id)

		match str(node.get("type", "")):
			"start":
				if not _advance_to_connection_port(quest_id, node_id, 0):
					_fail_quest(quest_id, "Start 节点缺少后继: %s" % node_id)
					return
			"objective":
				_prepare_objective_state(quest_id, node)
				quest_updated.emit(quest_id, _get_quest_progress(quest_id))
				return
			"dialog":
				if _is_waiting_on_node(quest_id, "dialog", node_id):
					return
				_set_waiting_state(quest_id, "dialog", node_id)
				quest_updated.emit(quest_id, _get_quest_progress(quest_id))
				call_deferred("_run_dialog_flow_node", quest_id, node_id)
				return
			"choice":
				if _is_waiting_on_node(quest_id, "choice", node_id):
					return
				_set_waiting_state(quest_id, "choice", node_id)
				quest_updated.emit(quest_id, _get_quest_progress(quest_id))
				call_deferred("_run_choice_flow_node", quest_id, node_id)
				return
			"reward":
				_grant_reward_node_once(quest_id, node)
				if not _advance_to_connection_port(quest_id, node_id, 0):
					_fail_quest(quest_id, "Reward 节点缺少后继: %s" % node_id)
					return
			"end":
				complete_quest(quest_id)
				return
			_:
				push_warning("[QuestSystem] 未知节点类型，按默认出口推进: %s" % str(node.get("type", "")))
				if not _advance_to_connection_port(quest_id, node_id, 0):
					_fail_quest(quest_id, "未知节点缺少后继: %s" % node_id)
					return


func update_quest_progress(quest_id: String, objective_type: String, amount: int = 1, params: Dictionary = {}) -> void:
	if not active_quests.has(quest_id):
		return

	var quest_state: Dictionary = active_quests[quest_id]
	var node_id := str(quest_state.get("current_node_id", ""))
	var node := _get_quest_node(quest_id, node_id)
	if node.is_empty() or str(node.get("type", "")) != "objective":
		return
	if str(node.get("objective_type", "")) != objective_type:
		return
	if not _objective_matches(node, params):
		return

	var objective_state: Dictionary = quest_state.get("completed_objectives", {})
	var current_value := int(objective_state.get(node_id, 0))
	var target_value := _get_objective_target(node)
	var new_value: int = min(current_value + max(amount, 1), target_value)
	if _is_boolean_objective(node):
		new_value = 1
	if new_value == current_value:
		return

	objective_state[node_id] = new_value
	quest_state["completed_objectives"] = objective_state
	active_quests[quest_id] = quest_state

	print("[QuestSystem] 任务进度更新: %s - %s (%d/%d)" % [
		quest_id,
		str(node.get("description", node_id)),
		new_value,
		target_value
	])

	quest_updated.emit(quest_id, _get_quest_progress(quest_id))
	if new_value >= target_value:
		if not _advance_to_connection_port(quest_id, node_id, 0):
			_fail_quest(quest_id, "Objective 节点缺少后继: %s" % node_id)
			return
		advance_active_quest(quest_id)


func on_dialog_node_completed(quest_id: String, dialog_node_id: String, branch_key: Variant) -> void:
	if not active_quests.has(quest_id):
		return

	var quest_state: Dictionary = active_quests[quest_id]
	if str(quest_state.get("current_node_id", "")) != dialog_node_id:
		return

	var node := _get_quest_node(quest_id, dialog_node_id)
	var output_port := _resolve_branch_port(node, branch_key)
	_clear_waiting_state(quest_id)
	if not _advance_to_connection_port(quest_id, dialog_node_id, output_port):
		if output_port != 0 and _advance_to_connection_port(quest_id, dialog_node_id, 0):
			advance_active_quest(quest_id)
			return
		_fail_quest(quest_id, "Dialog 节点缺少分支出口: %s" % dialog_node_id)
		return
	advance_active_quest(quest_id)


func on_choice_selected(quest_id: String, choice_node_id: String, option_id: Variant) -> void:
	if not active_quests.has(quest_id):
		return

	var quest_state: Dictionary = active_quests[quest_id]
	if str(quest_state.get("current_node_id", "")) != choice_node_id:
		return

	var node := _get_quest_node(quest_id, choice_node_id)
	var output_port := _resolve_choice_option_port(node, option_id)
	_clear_waiting_state(quest_id)
	if not _advance_to_connection_port(quest_id, choice_node_id, output_port):
		_fail_quest(quest_id, "Choice 节点缺少出口: %s" % choice_node_id)
		return
	advance_active_quest(quest_id)


func on_craft_completed(item_id: Variant, count: int = 1) -> void:
	for quest_id_variant in active_quests.keys():
		var quest_id := str(quest_id_variant)
		update_quest_progress(quest_id, "craft", count, {"item_id": str(item_id)})


func on_build_completed(structure_id: Variant) -> void:
	for quest_id_variant in active_quests.keys():
		var quest_id := str(quest_id_variant)
		update_quest_progress(quest_id, "build", 1, {"structure_id": str(structure_id)})


func complete_quest(quest_id: String) -> void:
	if not active_quests.has(quest_id):
		return

	var quest_template := get_quest_template(quest_id)
	var final_rewards := _collect_granted_rewards_for_quest(quest_id)

	active_quests.erase(quest_id)
	if not completed_quests.has(quest_id):
		completed_quests.append(quest_id)

	print("[QuestSystem] 完成任务: %s" % quest_id)
	quest_completed.emit(quest_id, final_rewards)

	if DialogModule:
		DialogModule.show_dialog(
			"任务完成：%s\n%s" % [
				str(quest_template.get("title", quest_id)),
				_format_rewards(final_rewards)
			],
			"任务",
			""
		)


func complete_stage(quest_id: String, stage: String) -> void:
	if not active_quests.has(quest_id):
		return
	var quest_state: Dictionary = active_quests[quest_id]
	if str(quest_state.get("current_node_id", "")) == stage:
		var node := _get_quest_node(quest_id, stage)
		if str(node.get("type", "")) == "objective":
			update_quest_progress(quest_id, str(node.get("objective_type", "")), _get_objective_target(node))
		elif _advance_to_connection_port(quest_id, stage, 0):
			advance_active_quest(quest_id)


func get_available_quests() -> Array:
	var available: Array = []
	for quest_id_variant in QUESTS.keys():
		var quest_id := str(quest_id_variant)
		if active_quests.has(quest_id) or completed_quests.has(quest_id):
			continue

		var quest: Dictionary = QUESTS[quest_id]
		var can_start := true
		for prereq_variant in quest.get("prerequisites", []):
			if not completed_quests.has(str(prereq_variant)):
				can_start = false
				break
		if not can_start:
			continue

		available.append({
			"id": quest_id,
			"title": str(quest.get("title", quest_id)),
			"description": str(quest.get("description", ""))
		})
	return available


func get_active_quests() -> Array:
	var quests: Array = []
	for quest_id_variant in active_quests.keys():
		var quest_id := str(quest_id_variant)
		var quest_template := get_quest_template(quest_id)
		quests.append({
			"id": quest_id,
			"title": str(quest_template.get("title", quest_id)),
			"description": str(quest_template.get("description", "")),
			"current_node_id": str(active_quests[quest_id].get("current_node_id", "")),
			"progress": _get_quest_progress(quest_id)
		})
	return quests


func get_save_data() -> Dictionary:
	return {
		"save_format_version": SAVE_FORMAT_VERSION,
		"active_quests": active_quests.duplicate(true),
		"completed_quests": completed_quests.duplicate(),
		"failed_quests": failed_quests.duplicate()
	}


func load_save_data(data: Dictionary) -> void:
	if int(data.get("save_format_version", 0)) != SAVE_FORMAT_VERSION:
		active_quests.clear()
		completed_quests.clear()
		failed_quests.clear()
		print("[QuestSystem] 旧任务存档不兼容，已重置任务状态")
		return

	active_quests = data.get("active_quests", {}).duplicate(true)
	completed_quests = data.get("completed_quests", []).duplicate()
	failed_quests = data.get("failed_quests", []).duplicate()

	for quest_id_variant in active_quests.keys():
		var quest_id := str(quest_id_variant)
		var quest_state: Dictionary = active_quests[quest_id]
		if not quest_state.has("awaiting_kind"):
			quest_state["awaiting_kind"] = ""
		if not quest_state.has("awaiting_node_id"):
			quest_state["awaiting_node_id"] = ""
		active_quests[quest_id] = quest_state
		advance_active_quest(quest_id)

	print("[QuestSystem] 已加载新任务存档")


func on_search_completed() -> void:
	var current_location := ""
	if GameState and GameState.has_method("get"):
		current_location = str(GameState.get("player_position"))

	for quest_id_variant in active_quests.keys():
		var quest_id := str(quest_id_variant)
		update_quest_progress(quest_id, "search", 1, {"location": current_location})


func _on_game_saved(_data: Dictionary = {}) -> void:
	for quest_id_variant in active_quests.keys():
		var quest_id := str(quest_id_variant)
		update_quest_progress(quest_id, "sleep", 1)
		update_quest_progress(quest_id, "survive", 1)


func _on_combat_ended(data: Dictionary) -> void:
	if not bool(data.get("victory", false)):
		return

	var enemy_data: Dictionary = data.get("enemy_data", {})
	var enemy_type := str(enemy_data.get("type", ""))
	for quest_id_variant in active_quests.keys():
		var quest_id := str(quest_id_variant)
		update_quest_progress(quest_id, "kill", 1, {"enemy_type": enemy_type})


func _on_location_changed(data: Dictionary) -> void:
	var location := str(data.get("location", ""))
	for quest_id_variant in active_quests.keys():
		var quest_id := str(quest_id_variant)
		update_quest_progress(quest_id, "travel", 1, {"location": location})


func _on_item_acquired(data: Dictionary) -> void:
	var items: Array = data.get("items", [])
	for item_variant in items:
		if not (item_variant is Dictionary):
			continue
		var item_data: Dictionary = item_variant
		var item_id := str(item_data.get("id", ""))
		var count := int(item_data.get("count", 1))
		for quest_id_variant in active_quests.keys():
			var quest_id := str(quest_id_variant)
			update_quest_progress(quest_id, "collect", count, {"item_id": item_id})


func _on_crafting_completed(data: Dictionary) -> void:
	var result: Dictionary = data.get("result", {})
	on_craft_completed(result.get("item", ""), int(result.get("count", 1)))


func _on_structure_built(structure_id: String, _position: Vector2) -> void:
	on_build_completed(structure_id)


func _get_quest_node(quest_id: String, node_id: String) -> Dictionary:
	var quest_template := get_quest_template(quest_id)
	var flow: Dictionary = quest_template.get("flow", {})
	var flow_nodes: Dictionary = flow.get("nodes", {})
	var node: Dictionary = flow_nodes.get(node_id, {}).duplicate(true)
	node["id"] = str(node.get("id", node_id))
	return node


func _get_flow_connections(quest_id: String) -> Array:
	var quest_template := get_quest_template(quest_id)
	return quest_template.get("flow", {}).get("connections", [])


func _get_next_node_id(quest_id: String, from_node_id: String, from_port: int = 0) -> String:
	for conn_variant in _get_flow_connections(quest_id):
		if not (conn_variant is Dictionary):
			continue
		var conn: Dictionary = conn_variant
		if str(conn.get("from", "")) != from_node_id:
			continue
		if int(conn.get("from_port", 0)) != from_port:
			continue
		return str(conn.get("to", ""))
	return ""


func _advance_to_connection_port(quest_id: String, from_node_id: String, from_port: int) -> bool:
	var next_node_id := _get_next_node_id(quest_id, from_node_id, from_port)
	if next_node_id.is_empty():
		return false
	var quest_state: Dictionary = active_quests.get(quest_id, {})
	if quest_state.is_empty():
		return false
	quest_state["current_node_id"] = next_node_id
	active_quests[quest_id] = quest_state
	return true


func _mark_node_visited(quest_id: String, node_id: String) -> void:
	var quest_state: Dictionary = active_quests.get(quest_id, {})
	if quest_state.is_empty():
		return
	var visited_nodes: Array = quest_state.get("visited_nodes", [])
	if not visited_nodes.has(node_id):
		visited_nodes.append(node_id)
		quest_state["visited_nodes"] = visited_nodes
		active_quests[quest_id] = quest_state


func _prepare_objective_state(quest_id: String, node: Dictionary) -> void:
	var quest_state: Dictionary = active_quests.get(quest_id, {})
	if quest_state.is_empty():
		return
	var objective_state: Dictionary = quest_state.get("completed_objectives", {})
	var node_id := str(node.get("id", ""))
	if not objective_state.has(node_id):
		objective_state[node_id] = 0
		quest_state["completed_objectives"] = objective_state
		active_quests[quest_id] = quest_state


func _is_boolean_objective(node: Dictionary) -> bool:
	return str(node.get("objective_type", "")) == "travel" and _get_objective_target(node) <= 1


func _get_objective_target(node: Dictionary) -> int:
	if node.has("count"):
		return max(int(node.get("count", 1)), 1)
	var target_value: Variant = node.get("target", 1)
	if target_value is int or target_value is float:
		return max(int(target_value), 1)
	return 1


func _objective_matches(node: Dictionary, params: Dictionary) -> bool:
	var objective_type := str(node.get("objective_type", ""))
	match objective_type:
		"travel", "search":
			if params.has("location") and node.has("target"):
				var target := str(node.get("target", ""))
				if not target.is_empty() and target != str(params.get("location", "")):
					return false
		"collect", "craft":
			if node.has("item_id") and params.has("item_id"):
				var expected_item := str(node.get("item_id", ""))
				var provided_item := str(params.get("item_id", ""))
				if ItemDatabase and ItemDatabase.has_method("resolve_item_id"):
					expected_item = str(ItemDatabase.resolve_item_id(expected_item))
					provided_item = str(ItemDatabase.resolve_item_id(provided_item))
				if expected_item != provided_item:
					return false
		"kill":
			if node.has("enemy_type") and params.has("enemy_type"):
				var enemy_type := str(node.get("enemy_type", ""))
				if not enemy_type.is_empty() and enemy_type != str(params.get("enemy_type", "")):
					return false
		"build":
			if node.has("structure_id") and params.has("structure_id"):
				var structure_id := str(node.get("structure_id", ""))
				if not structure_id.is_empty() and structure_id != str(params.get("structure_id", "")):
					return false
	return true


func _set_waiting_state(quest_id: String, waiting_kind: String, node_id: String) -> void:
	var quest_state: Dictionary = active_quests.get(quest_id, {})
	if quest_state.is_empty():
		return
	quest_state["awaiting_kind"] = waiting_kind
	quest_state["awaiting_node_id"] = node_id
	active_quests[quest_id] = quest_state


func _clear_waiting_state(quest_id: String) -> void:
	var quest_state: Dictionary = active_quests.get(quest_id, {})
	if quest_state.is_empty():
		return
	quest_state["awaiting_kind"] = ""
	quest_state["awaiting_node_id"] = ""
	active_quests[quest_id] = quest_state


func _is_waiting_on_node(quest_id: String, waiting_kind: String, node_id: String) -> bool:
	var quest_state: Dictionary = active_quests.get(quest_id, {})
	return str(quest_state.get("awaiting_kind", "")) == waiting_kind \
		and str(quest_state.get("awaiting_node_id", "")) == node_id


func _grant_reward_node_once(quest_id: String, node: Dictionary) -> void:
	var quest_state: Dictionary = active_quests.get(quest_id, {})
	if quest_state.is_empty():
		return
	var node_id := str(node.get("id", ""))
	var granted_nodes: Array = quest_state.get("granted_reward_nodes", [])
	if granted_nodes.has(node_id):
		return
	granted_nodes.append(node_id)
	quest_state["granted_reward_nodes"] = granted_nodes
	active_quests[quest_id] = quest_state
	_give_rewards(node.get("rewards", {}))


func _collect_granted_rewards_for_quest(quest_id: String) -> Dictionary:
	var aggregated := {
		"items": [],
		"experience": 0,
		"skill_points": 0,
		"unlock_recipes": []
	}
	var quest_state: Dictionary = active_quests.get(quest_id, {})
	var granted_nodes: Array = quest_state.get("granted_reward_nodes", [])
	for node_id_variant in granted_nodes:
		var node := _get_quest_node(quest_id, str(node_id_variant))
		_merge_rewards(aggregated, node.get("rewards", {}))
	return aggregated


func _merge_rewards(target: Dictionary, rewards: Dictionary) -> void:
	if rewards.is_empty():
		return

	if rewards.has("items"):
		var items: Array = target.get("items", [])
		for item_variant in rewards.get("items", []):
			items.append(item_variant)
		target["items"] = items

	target["experience"] = int(target.get("experience", 0)) + int(rewards.get("experience", 0))
	target["skill_points"] = int(target.get("skill_points", 0)) + int(rewards.get("skill_points", 0))

	if rewards.has("unlock_location"):
		target["unlock_location"] = rewards.get("unlock_location")
	if rewards.has("title"):
		target["title"] = rewards.get("title")
	if rewards.has("unlock_recipes"):
		var unlock_recipes: Array = target.get("unlock_recipes", [])
		for recipe_variant in rewards.get("unlock_recipes", []):
			if not unlock_recipes.has(recipe_variant):
				unlock_recipes.append(recipe_variant)
		target["unlock_recipes"] = unlock_recipes


func _give_rewards(rewards: Dictionary) -> void:
	if rewards.has("items"):
		for item_variant in rewards.get("items", []):
			if not (item_variant is Dictionary):
				continue
			var item_data: Dictionary = item_variant
			if InventoryModule:
				InventoryModule.add_item(str(item_data.get("id", "")), int(item_data.get("count", 1)))

	if rewards.has("experience"):
		print("[QuestSystem] 获得经验: %d" % int(rewards.get("experience", 0)))

	if rewards.has("skill_points"):
		if SkillModule and SkillModule.has_method("add_skill_points"):
			SkillModule.add_skill_points(int(rewards.get("skill_points", 0)))

	if rewards.has("unlock_location") and MapModule and MapModule.has_method("unlock_location"):
		MapModule.unlock_location(str(rewards.get("unlock_location", "")))

	if rewards.has("unlock_recipes") and CraftingSystem and CraftingSystem.has_method("unlock_recipe"):
		for recipe_variant in rewards.get("unlock_recipes", []):
			CraftingSystem.unlock_recipe(str(recipe_variant))

	if rewards.has("title"):
		print("[QuestSystem] 获得称号: %s" % str(rewards.get("title", "")))


func _format_rewards(rewards: Dictionary) -> String:
	var lines: Array[String] = ["奖励："]
	for item_variant in rewards.get("items", []):
		if not (item_variant is Dictionary):
			continue
		var item_data: Dictionary = item_variant
		lines.append("- %s x%d" % [str(item_data.get("id", "")), int(item_data.get("count", 1))])

	if int(rewards.get("experience", 0)) > 0:
		lines.append("- %d 经验" % int(rewards.get("experience", 0)))
	if int(rewards.get("skill_points", 0)) > 0:
		lines.append("- %d 技能点" % int(rewards.get("skill_points", 0)))
	if rewards.has("unlock_location"):
		lines.append("- 解锁地点: %s" % str(rewards.get("unlock_location", "")))
	if rewards.has("unlock_recipes"):
		lines.append("- 解锁配方: %s" % ", ".join(PackedStringArray(rewards.get("unlock_recipes", []))))
	if rewards.has("title"):
		lines.append("- 称号: %s" % str(rewards.get("title", "")))
	return "\n".join(lines)


func _get_quest_progress(quest_id: String) -> Dictionary:
	if not active_quests.has(quest_id):
		return {}

	var quest_state: Dictionary = active_quests[quest_id]
	var node_id := str(quest_state.get("current_node_id", ""))
	var node := _get_quest_node(quest_id, node_id)
	if node.is_empty():
		return {}

	var progress: Dictionary = {}
	match str(node.get("type", "")):
		"objective":
			var current_value := int(quest_state.get("completed_objectives", {}).get(node_id, 0))
			progress[0] = {
				"description": str(node.get("description", node_id)),
				"current": current_value,
				"target": _get_objective_target(node)
			}
		"dialog":
			progress[0] = {
				"description": "对话：%s" % str(node.get("dialog_id", node_id)),
				"current": 0,
				"target": 1
			}
		"choice":
			progress[0] = {
				"description": "选择分支",
				"current": 0,
				"target": 1
			}
		"reward":
			progress[0] = {
				"description": "发放奖励",
				"current": 1,
				"target": 1
			}
		"end":
			progress[0] = {
				"description": "任务完成",
				"current": 1,
				"target": 1
			}
		_:
			progress[0] = {
				"description": str(node.get("type", node_id)),
				"current": 0,
				"target": 1
			}
	return progress


func _resolve_branch_port(node: Dictionary, branch_key: Variant) -> int:
	if branch_key is int or branch_key is float:
		return max(int(branch_key), 0)

	var branch_text := str(branch_key)
	if branch_text.is_valid_int():
		return max(branch_text.to_int(), 0)

	var branch_labels: Array = node.get("branch_labels", [])
	for i in range(branch_labels.size()):
		if str(branch_labels[i]) == branch_text:
			return i
	return 0


func _resolve_choice_option_port(node: Dictionary, option_id: Variant) -> int:
	if option_id is int or option_id is float:
		return max(int(option_id), 0)

	var option_text := str(option_id)
	if option_text.is_valid_int():
		return max(option_text.to_int(), 0)

	var options: Array = node.get("options", [])
	for i in range(options.size()):
		var option_data: Dictionary = options[i]
		if str(option_data.get("id", "")) == option_text:
			return i
	return 0


func _run_dialog_flow_node(quest_id: String, dialog_node_id: String) -> void:
	if not active_quests.has(quest_id):
		return

	var flow_node := _get_quest_node(quest_id, dialog_node_id)
	if flow_node.is_empty():
		on_dialog_node_completed(quest_id, dialog_node_id, 0)
		return

	var dialog_id := str(flow_node.get("dialog_id", "")).strip_edges()
	if dialog_id.is_empty():
		on_dialog_node_completed(quest_id, dialog_node_id, 0)
		return

	var dialog_result := {"selected_port": 0, "branch_key": 0}
	if DialogModule and DialogModule.has_method("play_dialog_resource"):
		dialog_result = await DialogModule.play_dialog_resource(dialog_id)
	if dialog_result.is_empty():
		on_dialog_node_completed(quest_id, dialog_node_id, 0)
		return

	on_dialog_node_completed(
		quest_id,
		dialog_node_id,
		dialog_result.get("branch_key", dialog_result.get("selected_port", 0))
	)


func _run_choice_flow_node(quest_id: String, choice_node_id: String) -> void:
	if not active_quests.has(quest_id):
		return

	var flow_node := _get_quest_node(quest_id, choice_node_id)
	var options: Array = flow_node.get("options", [])
	if options.is_empty() or not DialogModule:
		on_choice_selected(quest_id, choice_node_id, 0)
		return

	var texts: Array[String] = []
	for option_variant in options:
		var option_data: Dictionary = option_variant
		texts.append(str(option_data.get("text", option_data.get("id", "选项"))))

	var selected_index: int = await DialogModule.show_choices(texts)
	if selected_index < 0 or selected_index >= options.size():
		selected_index = 0
	var selected_option: Dictionary = options[selected_index]
	on_choice_selected(quest_id, choice_node_id, selected_option.get("id", selected_index))

func _fail_quest(quest_id: String, reason: String) -> void:
	if active_quests.has(quest_id):
		active_quests.erase(quest_id)
	if not failed_quests.has(quest_id):
		failed_quests.append(quest_id)
	quest_failed.emit(quest_id, reason)
	push_warning("[QuestSystem] 任务失败: %s | %s" % [quest_id, reason])
