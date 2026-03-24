@tool
extends "res://addons/cdc_game_editor/editors/flow_graph/flow_graph_editor_base.gd"

signal quest_saved(quest_id: String)
signal quest_loaded(quest_id: String)
signal validation_errors_found(errors: Array[String])

const QUEST_DATA_DIR := "res://data/quests"

const MODE_RELATIONSHIP := "relationship"
const MODE_FLOW := "flow"

const QUEST_NODE_COLOR := Color(0.28, 0.52, 0.82)
const FLOW_NODE_COLORS := {
	"start": Color(0.22, 0.66, 0.38),
	"objective": Color(0.24, 0.56, 0.92),
	"dialog": Color(0.87, 0.54, 0.22),
	"choice": Color(0.88, 0.72, 0.26),
	"reward": Color(0.45, 0.7, 0.34),
	"end": Color(0.78, 0.28, 0.26)
}

const NODE_TYPE_NAMES := {
	"quest": "任务",
	"start": "开始",
	"objective": "目标",
	"dialog": "对话",
	"choice": "选择",
	"reward": "奖励",
	"end": "结束"
}

const OBJECTIVE_TYPES := {
	"travel": "前往地点",
	"search": "搜索",
	"collect": "收集",
	"kill": "击杀",
	"sleep": "休息",
	"survive": "生存",
	"craft": "制造",
	"build": "建造"
}

@onready var _validation_panel: VBoxContainer
@onready var _mode_button: Button
@onready var _new_button: Button
@onready var _delete_quest_button: Button

var _quests: Dictionary = {}
var _editor_mode: String = MODE_RELATIONSHIP
var _current_quest_id: String = ""
var _focused_relationship_quest_id: String = ""
var _validation_errors: Dictionary = {}
var _dirty_quest_ids: Dictionary = {}
var _persisted_quest_ids: Dictionary = {}
var _deleted_persisted_quest_ids: Dictionary = {}


func _get_editor_name() -> String:
	return "任务编辑器"


func _get_search_placeholder() -> String:
	return "搜索任务或节点..."


func _get_property_panel_title() -> String:
	return "Quest Editor"


func _get_initial_status_text() -> String:
	return "关系图模式 - 0 个任务"

func _has_record_list() -> bool:
	return true

func _get_record_list_title() -> String:
	return "Quest 列表"

func _get_record_list_empty_text() -> String:
	return "data/quests 为空"

func _get_record_list_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var quest_ids: Array = _quests.keys()
	quest_ids.sort()
	for quest_id_variant in quest_ids:
		var quest_id := str(quest_id_variant)
		var quest: Dictionary = _quests.get(quest_id, {})
		var title := str(quest.get("title", quest_id)).strip_edges()
		var label := quest_id
		if not title.is_empty() and title != quest_id:
			label = "%s | %s" % [quest_id, title]
		entries.append({
			"id": quest_id,
			"label": label
		})
	return entries

func _get_record_list_selected_id() -> String:
	if _editor_mode == MODE_FLOW and not _current_quest_id.is_empty():
		return _current_quest_id
	if not selected_node_id.is_empty() and _quests.has(selected_node_id):
		return selected_node_id
	return _focused_relationship_quest_id

func _is_record_list_entry_dirty(record_id: String) -> bool:
	return _dirty_quest_ids.has(record_id)

func _on_record_list_item_selected(record_id: String) -> void:
	var quest_id := record_id.strip_edges()
	if quest_id.is_empty() or not _quests.has(quest_id):
		return
	if quest_id != _current_quest_id:
		_show_flow_mode(quest_id)

func _on_record_list_item_activated(record_id: String) -> void:
	var quest_id := record_id.strip_edges()
	if quest_id.is_empty() or not _quests.has(quest_id):
		return
	_show_flow_mode(quest_id)


func _get_node_type_definitions() -> Array[Dictionary]:
	return _get_relationship_node_definitions()


func _create_toolbar() -> void:
	_mode_button = _add_toolbar_button("关系图模式", _on_mode_button_pressed, "切换关系图 / 返回关系图")
	_add_toolbar_separator()
	_new_button = _add_toolbar_button("新建 Quest", _on_new_quest, "创建任务并进入单任务模式")
	_delete_quest_button = _add_toolbar_button("删除 Quest", _on_delete_current_quest, "仅在单任务模式删除当前任务")
	_add_toolbar_separator()
	_add_toolbar_button("保存", _on_save_quests, "保存所有任务到 data/quests")
	_add_toolbar_button("加载", _on_load_quests, "重新加载任务文件")
	_add_toolbar_button("验证", _on_validate_all, "验证所有任务")
	_add_toolbar_separator()
	_add_toolbar_button("居中", _on_center_view, "居中当前图")


func _after_base_ready() -> void:
	_setup_validation_panel()
	if _graph_edit and _graph_edit.has_signal("node_double_clicked"):
		_graph_edit.node_double_clicked.connect(_on_graph_node_double_clicked)
	_load_quests_from_directory()


func _setup_validation_panel() -> void:
	_validation_panel = VBoxContainer.new()
	_validation_panel.visible = false
	_right_container.add_child(_validation_panel)

	var title := Label.new()
	title.text = "验证问题"
	title.add_theme_color_override("font_color", Color(0.92, 0.58, 0.2))
	_validation_panel.add_child(title)
	_validation_panel.add_child(HSeparator.new())


func _get_relationship_node_definitions() -> Array[Dictionary]:
	return [
		{"type": "quest", "name": "任务", "color": QUEST_NODE_COLOR}
	]


func _get_flow_node_definitions() -> Array[Dictionary]:
	return [
		{"type": "start", "name": NODE_TYPE_NAMES.start, "color": FLOW_NODE_COLORS.start},
		{"type": "objective", "name": NODE_TYPE_NAMES.objective, "color": FLOW_NODE_COLORS.objective},
		{"type": "dialog", "name": NODE_TYPE_NAMES.dialog, "color": FLOW_NODE_COLORS.dialog},
		{"type": "choice", "name": NODE_TYPE_NAMES.choice, "color": FLOW_NODE_COLORS.choice},
		{"type": "reward", "name": NODE_TYPE_NAMES.reward, "color": FLOW_NODE_COLORS.reward},
		{"type": "end", "name": NODE_TYPE_NAMES.end, "color": FLOW_NODE_COLORS.end}
	]


func _recalculate_dirty_state() -> void:
	_set_dirty_state(not _dirty_quest_ids.is_empty() or not _deleted_persisted_quest_ids.is_empty())


func _mark_quest_dirty(quest_id: String) -> void:
	var normalized_id := quest_id.strip_edges()
	if normalized_id.is_empty():
		return
	_dirty_quest_ids[normalized_id] = true
	_recalculate_dirty_state()
	_refresh_record_list()


func _move_dirty_quest_id(old_id: String, new_id: String) -> void:
	var old_key := old_id.strip_edges()
	var new_key := new_id.strip_edges()
	if old_key.is_empty() or new_key.is_empty():
		return
	_dirty_quest_ids.erase(old_key)
	_dirty_quest_ids[new_key] = true
	if _persisted_quest_ids.has(old_key):
		_deleted_persisted_quest_ids[old_key] = true
	_recalculate_dirty_state()
	_refresh_record_list()


func _handle_deleted_quest(quest_id: String) -> void:
	var normalized_id := quest_id.strip_edges()
	if normalized_id.is_empty():
		return
	_dirty_quest_ids.erase(normalized_id)
	if _persisted_quest_ids.has(normalized_id):
		_deleted_persisted_quest_ids[normalized_id] = true
	else:
		_deleted_persisted_quest_ids.erase(normalized_id)
	_recalculate_dirty_state()
	_refresh_record_list()


func _reset_dirty_tracking_to_persisted_state() -> void:
	_dirty_quest_ids.clear()
	_deleted_persisted_quest_ids.clear()
	_persisted_quest_ids.clear()
	for quest_id_variant in _quests.keys():
		_persisted_quest_ids[str(quest_id_variant)] = true
	_clear_dirty_state()
	_refresh_record_list()


func _on_mode_button_pressed() -> void:
	if _editor_mode == MODE_FLOW:
		_show_relationship_mode(_current_quest_id)


func _on_graph_node_double_clicked(node_id: String) -> void:
	if _editor_mode != MODE_RELATIONSHIP:
		return
	if not _quests.has(node_id):
		return
	_show_flow_mode(node_id)


func _load_quests_from_directory() -> void:
	_begin_dirty_tracking_suspension()
	_quests.clear()
	_validation_errors.clear()

	var absolute_dir_path := ProjectSettings.globalize_path(QUEST_DATA_DIR)
	if not DirAccess.dir_exists_absolute(absolute_dir_path):
		_end_dirty_tracking_suspension()
		_reset_dirty_tracking_to_persisted_state()
		_update_status("未找到任务目录: %s" % QUEST_DATA_DIR)
		_show_relationship_mode("")
		return

	var dir := DirAccess.open(QUEST_DATA_DIR)
	if dir == null:
		_end_dirty_tracking_suspension()
		_reset_dirty_tracking_to_persisted_state()
		_update_status("无法读取任务目录: %s" % QUEST_DATA_DIR)
		return

	var file_names: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			file_names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	file_names.sort()
	for i in range(file_names.size()):
		var quest_file_path := "%s/%s" % [QUEST_DATA_DIR, file_names[i]]
		var raw_data := _load_json_file(quest_file_path)
		if not (raw_data is Dictionary):
			push_warning("[QuestEditor] 跳过无效任务文件: %s" % quest_file_path)
			continue
		var quest_id := str(raw_data.get("quest_id", file_names[i].get_basename())).strip_edges()
		if quest_id.is_empty():
			continue
		_quests[quest_id] = _normalize_loaded_quest(raw_data, quest_id, i)

	_validate_all()
	_show_relationship_mode("")
	_end_dirty_tracking_suspension()
	_reset_dirty_tracking_to_persisted_state()
	_refresh_record_list()
	quest_loaded.emit(_current_quest_id)


func _normalize_loaded_quest(raw_quest: Dictionary, quest_id: String, index: int) -> Dictionary:
	var quest: Dictionary = raw_quest.duplicate(true)
	quest["quest_id"] = quest_id
	if not quest.has("flow"):
		quest = _migrate_legacy_quest(quest, quest_id)

	if not quest.has("title"):
		quest["title"] = quest_id
	if not quest.has("description"):
		quest["description"] = ""
	if not quest.has("prerequisites"):
		quest["prerequisites"] = []
	if not quest.has("time_limit"):
		quest["time_limit"] = -1
	if not quest.has("_editor"):
		quest["_editor"] = {}

	var editor_meta: Dictionary = quest.get("_editor", {})
	var default_relationship_position := Vector2(320.0 + float(index % 4) * 260.0, 200.0 + float(index / 4) * 180.0)
	editor_meta["relationship_position"] = _parse_position(
		editor_meta.get("relationship_position", editor_meta.get("position", {})),
		default_relationship_position
	)
	quest["_editor"] = editor_meta

	var flow: Dictionary = quest.get("flow", {})
	var flow_nodes: Dictionary = flow.get("nodes", {})
	var normalized_nodes: Dictionary = {}
	for node_id_variant in flow_nodes.keys():
		var node_id := str(node_id_variant)
		var node: Dictionary = flow_nodes[node_id].duplicate(true)
		node["id"] = str(node.get("id", node_id))
		node["position"] = _parse_position(node.get("position", {}), Vector2(120.0, 160.0))
		normalized_nodes[node_id] = node
	flow["nodes"] = normalized_nodes
	if not flow.has("connections"):
		flow["connections"] = []
	if not flow.has("start_node_id"):
		flow["start_node_id"] = "start"
	quest["flow"] = flow
	return quest


func _migrate_legacy_quest(raw_quest: Dictionary, quest_id: String) -> Dictionary:
	var quest: Dictionary = raw_quest.duplicate(true)
	var relationship_position := _parse_position(
		quest.get("_editor", {}).get("relationship_position", quest.get("_editor", {}).get("position", {})),
		Vector2(320, 200)
	)

	var flow_nodes: Dictionary = {}
	var flow_connections: Array[Dictionary] = []
	var current_x := 120.0
	var y := 160.0
	flow_nodes["start"] = {
		"id": "start",
		"type": "start",
		"position": Vector2(current_x, y)
	}

	var previous_node_id := "start"
	var step_index := 1
	for objective_variant in quest.get("objectives", []):
		if not (objective_variant is Dictionary):
			continue
		current_x += 300.0
		var objective_data: Dictionary = objective_variant
		var node_id := "step_%d" % step_index
		var node_data: Dictionary = {
			"id": node_id,
			"type": "objective",
			"position": Vector2(current_x, y),
			"objective_type": str(objective_data.get("type", "collect")),
			"description": str(objective_data.get("description", ""))
		}
		_apply_legacy_objective_fields(node_data, objective_data)
		flow_nodes[node_id] = node_data
		flow_connections.append({"from": previous_node_id, "to": node_id, "from_port": 0, "to_port": 0})
		previous_node_id = node_id
		step_index += 1

	var rewards: Dictionary = quest.get("rewards", {})
	if not _is_reward_empty(rewards):
		current_x += 300.0
		var reward_node_id := "reward_1"
		flow_nodes[reward_node_id] = {
			"id": reward_node_id,
			"type": "reward",
			"position": Vector2(current_x, y),
			"rewards": rewards.duplicate(true)
		}
		flow_connections.append({"from": previous_node_id, "to": reward_node_id, "from_port": 0, "to_port": 0})
		previous_node_id = reward_node_id

	current_x += 300.0
	flow_nodes["end"] = {
		"id": "end",
		"type": "end",
		"position": Vector2(current_x, y)
	}
	flow_connections.append({"from": previous_node_id, "to": "end", "from_port": 0, "to_port": 0})

	quest.erase("objectives")
	quest.erase("rewards")
	quest["flow"] = {
		"start_node_id": "start",
		"nodes": flow_nodes,
		"connections": flow_connections
	}
	quest["_editor"] = {"relationship_position": relationship_position}
	quest["quest_id"] = quest_id
	return quest


func _apply_legacy_objective_fields(node_data: Dictionary, objective_data: Dictionary) -> void:
	var objective_type := str(node_data.get("objective_type", ""))
	var target_value: Variant = objective_data.get("target", null)
	match objective_type:
		"travel":
			node_data["target"] = str(target_value)
			node_data["count"] = 1
		"search", "sleep", "survive", "build":
			node_data["count"] = max(int(target_value), 1) if target_value != null else 1
			if objective_data.has("structure_id"):
				node_data["structure_id"] = str(objective_data.get("structure_id", ""))
		"collect", "craft":
			node_data["count"] = max(int(target_value), 1) if target_value != null else 1
			if objective_data.has("item_id"):
				node_data["item_id"] = str(objective_data.get("item_id", ""))
		"kill":
			node_data["count"] = max(int(target_value), 1) if target_value != null else 1
			if objective_data.has("enemy_type"):
				node_data["enemy_type"] = str(objective_data.get("enemy_type", ""))
		_:
			if target_value is String:
				node_data["target"] = str(target_value)
			elif target_value != null:
				node_data["count"] = max(int(target_value), 1)


func _parse_position(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return fallback


func _show_relationship_mode(focus_quest_id: String) -> void:
	_sync_displayed_graph_to_store()
	_editor_mode = MODE_RELATIONSHIP
	_current_quest_id = ""
	_focused_relationship_quest_id = focus_quest_id
	_set_node_type_menu(_get_relationship_node_definitions())
	_rebuild_display_graph()
	_update_toolbar_state()
	if not focus_quest_id.is_empty():
		_select_display_node(focus_quest_id)
	_refresh_record_list()
	_update_status("关系图模式 - %d 个任务" % _quests.size())


func _show_flow_mode(quest_id: String, selected_flow_node_id: String = "") -> void:
	if not _quests.has(quest_id):
		return
	_sync_displayed_graph_to_store()
	_editor_mode = MODE_FLOW
	_current_quest_id = quest_id
	_set_node_type_menu(_get_flow_node_definitions())
	_rebuild_display_graph()
	_update_toolbar_state()

	var flow: Dictionary = _quests[quest_id].get("flow", {})
	var start_node_id := selected_flow_node_id
	if start_node_id.is_empty():
		start_node_id = str(flow.get("start_node_id", "start"))
	if nodes.has(start_node_id):
		_select_display_node(start_node_id)
	else:
		_refresh_property_panel_for_current_mode()

	_refresh_record_list()
	_update_status("单任务模式 - %s" % quest_id)


func _rebuild_display_graph() -> void:
	nodes.clear()
	connections.clear()
	_graph_edit.clear_graph()
	_clear_selection_state()

	if _editor_mode == MODE_RELATIONSHIP:
		var quest_ids: Array = _quests.keys()
		quest_ids.sort()
		for quest_id_variant in quest_ids:
			var quest_id := str(quest_id_variant)
			_create_node_internal(_build_relationship_node_data(quest_id))

		for quest_id_variant in quest_ids:
			var quest_id := str(quest_id_variant)
			var quest: Dictionary = _quests[quest_id]
			for prereq_variant in quest.get("prerequisites", []):
				var prereq_id := str(prereq_variant)
				if not _quests.has(prereq_id):
					continue
				var conn := {"from": prereq_id, "to": quest_id, "from_port": 0, "to_port": 0}
				connections.append(conn)
				_graph_edit.connect_node(StringName(prereq_id), 0, StringName(quest_id), 0)
	else:
		var quest: Dictionary = _quests.get(_current_quest_id, {})
		var flow: Dictionary = quest.get("flow", {})
		var flow_nodes: Dictionary = flow.get("nodes", {})
		var flow_node_ids: Array = flow_nodes.keys()
		flow_node_ids.sort()
		for node_id_variant in flow_node_ids:
			var node_id := str(node_id_variant)
			_create_node_internal(flow_nodes[node_id].duplicate(true))

		for conn_variant in flow.get("connections", []):
			if not (conn_variant is Dictionary):
				continue
			var conn: Dictionary = conn_variant
			connections.append(conn.duplicate(true))
			_graph_edit.connect_node(
				StringName(str(conn.get("from", ""))),
				int(conn.get("from_port", 0)),
				StringName(str(conn.get("to", ""))),
				int(conn.get("to_port", 0))
			)

	for graph_node in _graph_edit.get_all_nodes():
		_disable_graph_node_close(graph_node)

	_refresh_property_panel_for_current_mode()
	_update_validation_panel()


func _build_relationship_node_data(quest_id: String) -> Dictionary:
	var quest: Dictionary = _quests[quest_id]
	var relationship_position: Vector2 = quest.get("_editor", {}).get("relationship_position", Vector2.ZERO)
	return {
		"id": quest_id,
		"type": "quest",
		"title": str(quest.get("title", quest_id)),
		"quest_id": quest_id,
		"description": str(quest.get("description", "")),
		"position": relationship_position,
		"step_count": _get_step_count(quest),
		"prerequisite_count": quest.get("prerequisites", []).size()
	}


func _refresh_graph_node(node, data: Dictionary) -> void:
	super._refresh_graph_node(node, data)
	_disable_graph_node_close(node)


func _disable_graph_node_close(graph_node: GraphNode) -> void:
	if graph_node == null:
		return
	if graph_node.has_method("_has_property") and graph_node.call("_has_property", "show_close_button"):
		graph_node.set("show_close_button", false)
	elif graph_node.has_method("_has_property") and graph_node.call("_has_property", "show_close"):
		graph_node.set("show_close", false)
	elif graph_node.has_method("_has_property") and graph_node.call("_has_property", "close_button_enabled"):
		graph_node.set("close_button_enabled", false)


func _populate_node_preview(node, data: Dictionary) -> void:
	if _editor_mode == MODE_RELATIONSHIP:
		node.add_text_row(str(data.get("quest_id", data.get("id", ""))), Color.GRAY)
		node.add_separator()
		node.add_text_row(str(data.get("title", "Untitled Quest")))
		node.add_text_row(_truncate_text(str(data.get("description", "")), 60), Color.WHITE, Vector2(180, 40), true, HORIZONTAL_ALIGNMENT_LEFT)
		node.add_text_row("步骤: %d" % int(data.get("step_count", 0)), Color.LIGHT_BLUE)
		node.add_text_row("前置任务: %d" % int(data.get("prerequisite_count", 0)), Color.GREEN)
		return

	var node_type := str(data.get("type", ""))
	match node_type:
		"start":
			node.add_text_row("任务开始", Color.WHITE)
		"objective":
			node.add_text_row(OBJECTIVE_TYPES.get(str(data.get("objective_type", "")), str(data.get("objective_type", ""))), Color.WHITE)
			node.add_text_row(_truncate_text(str(data.get("description", "")), 50), Color.LIGHT_GRAY, Vector2(180, 36), true, HORIZONTAL_ALIGNMENT_LEFT)
			node.add_text_row(_describe_objective_target(data), Color.LIGHT_BLUE)
		"dialog":
			node.add_text_row("dialog_id", Color.GRAY)
			node.add_text_row(str(data.get("dialog_id", "")), Color.WHITE)
			node.add_text_row("分支: %d" % max(_get_dialog_output_count(data), 1), Color.LIGHT_BLUE)
		"choice":
			node.add_text_row("Quest Choice", Color.WHITE)
			node.add_text_row("选项数: %d" % data.get("options", []).size(), Color.LIGHT_BLUE)
		"reward":
			node.add_text_row("奖励节点", Color.WHITE)
			node.add_text_row(_summarize_rewards(data.get("rewards", {})), Color.GREEN, Vector2(180, 36), true, HORIZONTAL_ALIGNMENT_LEFT)
		"end":
			node.add_text_row("任务结束", Color.WHITE)


func _configure_node_ports(node, data: Dictionary) -> void:
	var node_type := str(data.get("type", ""))
	if _editor_mode == MODE_RELATIONSHIP:
		node.add_input_port()
		node.add_output_port()
		return

	match node_type:
		"start":
			node.add_output_port()
		"objective":
			node.add_input_port()
			node.add_output_port()
		"dialog":
			node.add_input_port()
			for _i in range(max(_get_dialog_output_count(data), 1)):
				node.add_output_port()
		"choice":
			node.add_input_port()
			for _i in range(max(data.get("options", []).size(), 1)):
				node.add_output_port()
		"reward":
			node.add_input_port()
			node.add_output_port()
		"end":
			node.add_input_port()


func _describe_objective_target(node_data: Dictionary) -> String:
	var objective_type := str(node_data.get("objective_type", ""))
	match objective_type:
		"travel", "search":
			if node_data.has("target") and not str(node_data.get("target", "")).is_empty():
				return "目标: %s" % str(node_data.get("target", ""))
			return "次数: %d" % int(node_data.get("count", 1))
		"collect", "craft":
			return "物品 %s x%d" % [str(node_data.get("item_id", "")), int(node_data.get("count", 1))]
		"kill":
			return "敌人 %s x%d" % [str(node_data.get("enemy_type", "")), int(node_data.get("count", 1))]
		"build":
			if node_data.has("structure_id") and not str(node_data.get("structure_id", "")).is_empty():
				return "建筑 %s x%d" % [str(node_data.get("structure_id", "")), int(node_data.get("count", 1))]
			return "建造 x%d" % int(node_data.get("count", 1))
		_:
			return "次数: %d" % int(node_data.get("count", 1))


func _get_dialog_output_count(node_data: Dictionary) -> int:
	return max(node_data.get("branch_labels", []).size(), 1)


func _summarize_rewards(rewards: Dictionary) -> String:
	var parts: Array[String] = []
	if rewards.get("items", []).size() > 0:
		parts.append("%d 件物品" % rewards.get("items", []).size())
	if int(rewards.get("experience", 0)) > 0:
		parts.append("%d 经验" % int(rewards.get("experience", 0)))
	if int(rewards.get("skill_points", 0)) > 0:
		parts.append("%d 技能点" % int(rewards.get("skill_points", 0)))
	if rewards.has("unlock_location") and not str(rewards.get("unlock_location", "")).is_empty():
		parts.append("解锁地点")
	if parts.is_empty():
		return "无奖励"
	return ", ".join(parts)


func _truncate_text(text: String, max_length: int) -> String:
	if text.length() <= max_length:
		return text
	return text.substr(0, max_length - 3) + "..."


func _update_property_panel(_data: Dictionary) -> void:
	_property_panel.clear()
	if _editor_mode == MODE_RELATIONSHIP:
		_update_relationship_property_panel()
	else:
		_update_flow_property_panel()


func _update_relationship_property_panel() -> void:
	_property_panel.add_readonly_label("mode", "模式:", "关系图模式（只读）")
	_property_panel.add_separator()
	if selected_node_id.is_empty() or not _quests.has(selected_node_id):
		_property_panel.add_readonly_label("hint", "说明:", "双击任务节点进入单任务编辑")
		return

	var quest: Dictionary = _quests[selected_node_id]
	_property_panel.add_readonly_label("quest_id", "任务ID:", selected_node_id)
	_property_panel.add_readonly_label("title", "标题:", str(quest.get("title", "")))
	_property_panel.add_readonly_label("description", "描述:", str(quest.get("description", "")))
	_property_panel.add_readonly_label("steps", "步骤数:", str(_get_step_count(quest)))
	_property_panel.add_readonly_label("prerequisites", "前置任务:", _format_prerequisites(quest.get("prerequisites", [])))


func _update_flow_property_panel() -> void:
	var quest: Dictionary = _quests.get(_current_quest_id, {})
	if quest.is_empty():
		_property_panel.add_readonly_label("empty", "任务:", "未选择")
		return

	_property_panel.add_readonly_label("mode", "模式:", "单任务模式")
	_property_panel.add_string_property("quest_quest_id", "任务ID:", str(quest.get("quest_id", "")), false, "唯一任务ID")
	_property_panel.add_string_property("quest_title", "任务标题:", str(quest.get("title", "")))
	_property_panel.add_string_property("quest_description", "任务描述:", str(quest.get("description", "")), true, "任务说明")
	_property_panel.add_number_property("quest_time_limit", "时间限制:", int(quest.get("time_limit", -1)), -1, 999999, 1, false)
	_property_panel.add_readonly_label("quest_prerequisites", "前置任务:", _format_prerequisites(quest.get("prerequisites", [])))
	_property_panel.add_separator()

	var selected_node: Dictionary = nodes.get(selected_node_id, {})
	if selected_node.is_empty():
		_property_panel.add_readonly_label("select_hint", "节点:", "请选择一个步骤节点")
		return

	_property_panel.add_readonly_label("node_id", "节点ID:", str(selected_node.get("id", "")))
	_property_panel.add_readonly_label("node_type", "节点类型:", NODE_TYPE_NAMES.get(str(selected_node.get("type", "")), str(selected_node.get("type", ""))))

	match str(selected_node.get("type", "")):
		"objective":
			_property_panel.add_enum_property("node_objective_type", "目标类型:", OBJECTIVE_TYPES, str(selected_node.get("objective_type", "travel")))
			_property_panel.add_string_property("node_description", "目标描述:", str(selected_node.get("description", "")), true, "例如：前往超市")
			_property_panel.add_string_property("node_target", "目标参数:", str(selected_node.get("target", "")), false, "地点/通用目标")
			_property_panel.add_number_property("node_count", "数量:", int(selected_node.get("count", 1)), 1, 9999, 1, false)
			_property_panel.add_string_property("node_item_id", "物品ID:", str(selected_node.get("item_id", "")))
			_property_panel.add_string_property("node_enemy_type", "敌人类型:", str(selected_node.get("enemy_type", "")))
			_property_panel.add_string_property("node_structure_id", "建筑ID:", str(selected_node.get("structure_id", "")))
		"dialog":
			_property_panel.add_string_property("node_dialog_id", "dialog_id:", str(selected_node.get("dialog_id", "")))
			_property_panel.add_separator()
			_property_panel.add_custom_control(_create_string_array_editor("分支标签", selected_node.get("branch_labels", []), _on_dialog_branch_labels_changed))
		"choice":
			_property_panel.add_custom_control(_create_choice_options_editor(selected_node))
		"reward":
			var rewards: Dictionary = selected_node.get("rewards", {})
			_property_panel.add_number_property("node_reward_experience", "经验:", int(rewards.get("experience", 0)), 0, 999999, 10, false)
			_property_panel.add_number_property("node_reward_skill_points", "技能点:", int(rewards.get("skill_points", 0)), 0, 9999, 1, false)
			_property_panel.add_string_property("node_reward_unlock_location", "解锁地点:", str(rewards.get("unlock_location", "")))
			_property_panel.add_string_property("node_reward_title", "称号:", str(rewards.get("title", "")))
			_property_panel.add_string_property("node_reward_unlock_recipes", "解锁配方:", ", ".join(Array(rewards.get("unlock_recipes", []))), false, "逗号分隔")
			_property_panel.add_separator()
			_property_panel.add_custom_control(_create_reward_items_editor(selected_node))
		"start", "end":
			_property_panel.add_readonly_label("node_hint", "说明:", "该节点没有额外可编辑属性")


func _create_string_array_editor(title: String, values: Array, callback: Callable) -> Control:
	var container := VBoxContainer.new()
	var label := Label.new()
	label.text = title
	container.add_child(label)

	for i in range(values.size()):
		var row := HBoxContainer.new()
		var edit := LineEdit.new()
		edit.text = str(values[i])
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.text_changed.connect(func(v: String):
			var updated := values.duplicate()
			updated[i] = v
			callback.call(updated)
		)
		row.add_child(edit)

		var del_btn := Button.new()
		del_btn.text = "×"
		del_btn.pressed.connect(func():
			var updated := values.duplicate()
			updated.remove_at(i)
			callback.call(updated)
		)
		row.add_child(del_btn)
		container.add_child(row)

	var add_btn := Button.new()
	add_btn.text = "+ 添加"
	add_btn.pressed.connect(func():
		var updated := values.duplicate()
		updated.append("")
		callback.call(updated)
	)
	container.add_child(add_btn)
	return container


func _create_choice_options_editor(node_data: Dictionary) -> Control:
	var container := VBoxContainer.new()
	var label := Label.new()
	label.text = "选项"
	container.add_child(label)

	var options: Array = node_data.get("options", [])
	for i in range(options.size()):
		var option_data: Dictionary = options[i]
		var row := HBoxContainer.new()

		var id_edit := LineEdit.new()
		id_edit.text = str(option_data.get("id", ""))
		id_edit.placeholder_text = "option_id"
		id_edit.custom_minimum_size = Vector2(120, 0)
		id_edit.text_changed.connect(func(v: String):
			var updated := options.duplicate(true)
			updated[i]["id"] = v
			_update_choice_options(updated)
		)
		row.add_child(id_edit)

		var text_edit := LineEdit.new()
		text_edit.text = str(option_data.get("text", ""))
		text_edit.placeholder_text = "显示文本"
		text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_edit.text_changed.connect(func(v: String):
			var updated := options.duplicate(true)
			updated[i]["text"] = v
			_update_choice_options(updated)
		)
		row.add_child(text_edit)

		var del_btn := Button.new()
		del_btn.text = "×"
		del_btn.pressed.connect(func():
			var updated := options.duplicate(true)
			updated.remove_at(i)
			_update_choice_options(updated)
		)
		row.add_child(del_btn)
		container.add_child(row)

	var add_btn := Button.new()
	add_btn.text = "+ 添加选项"
	add_btn.pressed.connect(func():
		var updated := options.duplicate(true)
		updated.append({
			"id": "option_%d" % updated.size(),
			"text": "新选项"
		})
		_update_choice_options(updated)
	)
	container.add_child(add_btn)
	return container


func _create_reward_items_editor(node_data: Dictionary) -> Control:
	var container := VBoxContainer.new()
	var label := Label.new()
	label.text = "物品奖励"
	container.add_child(label)

	var rewards: Dictionary = node_data.get("rewards", {})
	var items: Array = rewards.get("items", [])
	for i in range(items.size()):
		var item_data: Dictionary = items[i]
		var row := HBoxContainer.new()

		var id_edit := LineEdit.new()
		id_edit.text = str(item_data.get("id", ""))
		id_edit.placeholder_text = "item_id"
		id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		id_edit.text_changed.connect(func(v: String):
			var updated := items.duplicate(true)
			updated[i]["id"] = v
			_update_reward_items(updated)
		)
		row.add_child(id_edit)

		var count_spin := SpinBox.new()
		count_spin.min_value = 1
		count_spin.max_value = 9999
		count_spin.value = float(item_data.get("count", 1))
		count_spin.value_changed.connect(func(v: float):
			var updated := items.duplicate(true)
			updated[i]["count"] = int(v)
			_update_reward_items(updated)
		)
		row.add_child(count_spin)

		var del_btn := Button.new()
		del_btn.text = "×"
		del_btn.pressed.connect(func():
			var updated := items.duplicate(true)
			updated.remove_at(i)
			_update_reward_items(updated)
		)
		row.add_child(del_btn)
		container.add_child(row)

	var add_btn := Button.new()
	add_btn.text = "+ 添加物品"
	add_btn.pressed.connect(func():
		var updated := items.duplicate(true)
		updated.append({"id": "", "count": 1})
		_update_reward_items(updated)
	)
	container.add_child(add_btn)
	return container


func _on_property_changed(property_name: String, new_value: Variant, _old_value: Variant) -> void:
	if _editor_mode != MODE_FLOW or _current_quest_id.is_empty():
		return

	var quest: Dictionary = _quests.get(_current_quest_id, {})
	if quest.is_empty():
		return

	match property_name:
		"quest_quest_id":
			_change_quest_id(_current_quest_id, str(new_value).strip_edges())
			return
		"quest_title":
			quest["title"] = str(new_value)
			_quests[_current_quest_id] = quest
		"quest_description":
			quest["description"] = str(new_value)
			_quests[_current_quest_id] = quest
		"quest_time_limit":
			quest["time_limit"] = int(new_value)
			_quests[_current_quest_id] = quest
		_:
			_update_selected_flow_node_property(property_name, new_value)
			return

	_validate_quest(_current_quest_id)
	_refresh_property_panel_for_current_mode()
	_update_validation_panel()
	_mark_quest_dirty(_current_quest_id)


func _update_selected_flow_node_property(property_name: String, new_value: Variant) -> void:
	if selected_node_id.is_empty():
		return
	var node_data: Dictionary = _get_current_flow_node(selected_node_id)
	if node_data.is_empty():
		return

	match property_name:
		"node_objective_type":
			node_data["objective_type"] = str(new_value)
		"node_description":
			node_data["description"] = str(new_value)
		"node_target":
			node_data["target"] = str(new_value)
		"node_count":
			node_data["count"] = int(new_value)
		"node_item_id":
			if str(new_value).is_empty():
				node_data.erase("item_id")
			else:
				node_data["item_id"] = str(new_value)
		"node_enemy_type":
			if str(new_value).is_empty():
				node_data.erase("enemy_type")
			else:
				node_data["enemy_type"] = str(new_value)
		"node_structure_id":
			if str(new_value).is_empty():
				node_data.erase("structure_id")
			else:
				node_data["structure_id"] = str(new_value)
		"node_dialog_id":
			node_data["dialog_id"] = str(new_value)
		"node_reward_experience", "node_reward_skill_points", "node_reward_unlock_location", "node_reward_title", "node_reward_unlock_recipes":
			var rewards: Dictionary = node_data.get("rewards", {})
			match property_name:
				"node_reward_experience":
					rewards["experience"] = int(new_value)
				"node_reward_skill_points":
					rewards["skill_points"] = int(new_value)
				"node_reward_unlock_location":
					if str(new_value).is_empty():
						rewards.erase("unlock_location")
					else:
						rewards["unlock_location"] = str(new_value)
				"node_reward_title":
					if str(new_value).is_empty():
						rewards.erase("title")
					else:
						rewards["title"] = str(new_value)
				"node_reward_unlock_recipes":
					var recipes: Array[String] = []
					for part in str(new_value).split(","):
						var recipe_id := part.strip_edges()
						if not recipe_id.is_empty():
							recipes.append(recipe_id)
					if recipes.is_empty():
						rewards.erase("unlock_recipes")
					else:
						rewards["unlock_recipes"] = recipes
			node_data["rewards"] = rewards
		_:
			return

	_update_current_flow_node(selected_node_id, node_data)


func _on_dialog_branch_labels_changed(updated_values: Array) -> void:
	if selected_node_id.is_empty():
		return
	var node_data := _get_current_flow_node(selected_node_id)
	node_data["branch_labels"] = updated_values
	_update_current_flow_node(selected_node_id, node_data, true)


func _update_choice_options(updated_options: Array) -> void:
	if selected_node_id.is_empty():
		return
	var node_data := _get_current_flow_node(selected_node_id)
	node_data["options"] = updated_options
	_update_current_flow_node(selected_node_id, node_data, true)


func _update_reward_items(updated_items: Array) -> void:
	if selected_node_id.is_empty():
		return
	var node_data := _get_current_flow_node(selected_node_id)
	var rewards: Dictionary = node_data.get("rewards", {})
	rewards["items"] = updated_items
	node_data["rewards"] = rewards
	_update_current_flow_node(selected_node_id, node_data)


func _update_current_flow_node(node_id: String, node_data: Dictionary, rebuild_graph: bool = false) -> void:
	if _editor_mode != MODE_FLOW or _current_quest_id.is_empty():
		return
	var quest: Dictionary = _quests.get(_current_quest_id, {})
	var flow: Dictionary = quest.get("flow", {})
	var flow_nodes: Dictionary = flow.get("nodes", {})
	flow_nodes[node_id] = node_data
	flow["nodes"] = flow_nodes
	quest["flow"] = flow
	_quests[_current_quest_id] = quest
	_validate_quest(_current_quest_id)
	_mark_quest_dirty(_current_quest_id)

	if rebuild_graph:
		_prune_invalid_flow_connections()
		_show_flow_mode(_current_quest_id, node_id)
	else:
		nodes[node_id] = node_data
		_on_node_data_changed(node_id, node_data)
		_update_validation_panel()


func _get_current_flow_node(node_id: String) -> Dictionary:
	if _current_quest_id.is_empty():
		return {}
	var quest: Dictionary = _quests.get(_current_quest_id, {})
	return quest.get("flow", {}).get("nodes", {}).get(node_id, {}).duplicate(true)


func _change_quest_id(old_id: String, new_id: String) -> void:
	if new_id.is_empty() or new_id == old_id:
		return
	if _quests.has(new_id):
		_update_status("任务ID已存在: %s" % new_id)
		return

	var quest: Dictionary = _quests[old_id]
	quest["quest_id"] = new_id
	_quests.erase(old_id)
	_quests[new_id] = quest

	for quest_id_variant in _quests.keys():
		var quest_id := str(quest_id_variant)
		var other: Dictionary = _quests[quest_id]
		var prerequisites: Array = other.get("prerequisites", [])
		for i in range(prerequisites.size()):
			if str(prerequisites[i]) == old_id:
				prerequisites[i] = new_id
		other["prerequisites"] = prerequisites
		_quests[quest_id] = other

	_move_dirty_quest_id(old_id, new_id)
	_current_quest_id = new_id
	_validate_all()
	_refresh_property_panel_for_current_mode()
	_update_validation_panel()
	_refresh_record_list()
	_update_status("已修改任务ID: %s" % new_id)


func _refresh_property_panel_for_current_mode() -> void:
	_queue_property_panel_update({})


func _after_node_data_changed(node_id: String, previous_data: Dictionary, new_data: Dictionary, is_position_only_update: bool) -> void:
	super._after_node_data_changed(node_id, previous_data, new_data, is_position_only_update)
	if previous_data == new_data:
		return
	if _editor_mode == MODE_RELATIONSHIP and _quests.has(node_id):
		_mark_quest_dirty(node_id)
	elif _editor_mode == MODE_FLOW and not _current_quest_id.is_empty():
		_mark_quest_dirty(_current_quest_id)


func _select_display_node(node_id: String) -> void:
	selected_node_id = node_id
	_inspected_node_id = node_id
	var graph_node: Node = _graph_edit.get_node_or_null(node_id)
	if graph_node and graph_node is GraphNode:
		graph_node.selected = true
	_queue_property_panel_update(nodes.get(node_id, {}))
	_update_validation_panel()


func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if _editor_mode == MODE_RELATIONSHIP:
		_update_status("关系图模式只读，不能修改依赖关系")
		return
	super._on_connection_request(from_node, from_port, to_node, to_port)
	_sync_flow_connections_to_store()
	_mark_quest_dirty(_current_quest_id)


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if _editor_mode == MODE_RELATIONSHIP:
		_update_status("关系图模式只读，不能修改依赖关系")
		return
	super._on_disconnection_request(from_node, from_port, to_node, to_port)
	_sync_flow_connections_to_store()
	_mark_quest_dirty(_current_quest_id)


func _on_add_node_requested(node_type: String, graph_position: Vector2, pending_connection: Dictionary = {}) -> void:
	if _editor_mode != MODE_FLOW:
		_update_status("关系图模式只读，不能新增流程节点")
		return
	super._on_add_node_requested(node_type, graph_position, pending_connection)
	_sync_flow_nodes_to_store()
	_mark_quest_dirty(_current_quest_id)


func _on_delete_selected() -> void:
	if _editor_mode != MODE_FLOW:
		_update_status("关系图模式只读，不能删除任务或节点")
		return
	super._on_delete_selected()
	_sync_displayed_graph_to_store()
	_validate_quest(_current_quest_id)
	_update_validation_panel()
	_mark_quest_dirty(_current_quest_id)


func _on_paste_nodes() -> void:
	if _editor_mode != MODE_FLOW:
		_update_status("关系图模式只读，不能粘贴节点")
		return
	super._on_paste_nodes()
	_sync_flow_nodes_to_store()
	_mark_quest_dirty(_current_quest_id)


func _normalize_pasted_node_data(data: Dictionary) -> Dictionary:
	if _editor_mode != MODE_FLOW:
		return {}
	var normalized := data.duplicate(true)
	normalized["id"] = _generate_node_id(str(normalized.get("type", "node")))
	normalized["position"] = normalized.get("position", Vector2.ZERO) + Vector2(40, 40)
	return normalized


func _generate_node_id(node_type: String = "node") -> String:
	return "%s_%d" % [node_type, Time.get_ticks_msec()]


func _apply_type_defaults(data: Dictionary, node_type: String) -> void:
	if _editor_mode == MODE_RELATIONSHIP:
		return

	data["type"] = node_type
	if not data.has("id"):
		data["id"] = _generate_node_id(node_type)
	if not data.has("position"):
		data["position"] = Vector2.ZERO
	match node_type:
		"start":
			data["id"] = "start" if str(data.get("id", "")).is_empty() else data["id"]
		"objective":
			if not data.has("objective_type"):
				data["objective_type"] = "travel"
			if not data.has("description"):
				data["description"] = "新的任务步骤"
			if not data.has("count"):
				data["count"] = 1
		"dialog":
			if not data.has("dialog_id"):
				data["dialog_id"] = ""
			if not data.has("branch_labels"):
				data["branch_labels"] = []
		"choice":
			if not data.has("options"):
				data["options"] = [{"id": "option_0", "text": "新选项"}]
		"reward":
			if not data.has("rewards"):
				data["rewards"] = {"items": [], "experience": 0, "skill_points": 0}


func _on_new_quest() -> void:
	if _editor_mode != MODE_RELATIONSHIP:
		_update_status("请先返回关系图模式再创建新 Quest")
		return

	var quest_id := "quest_%d" % Time.get_ticks_msec()
	_quests[quest_id] = _build_new_quest(quest_id)
	_validate_quest(quest_id)
	_mark_quest_dirty(quest_id)
	_show_flow_mode(quest_id)


func _build_new_quest(quest_id: String) -> Dictionary:
	return {
		"quest_id": quest_id,
		"title": "New Quest",
		"description": "任务描述",
		"prerequisites": [],
		"time_limit": -1,
		"flow": {
			"start_node_id": "start",
			"nodes": {
				"start": {
					"id": "start",
					"type": "start",
					"position": Vector2(120, 180)
				},
				"end": {
					"id": "end",
					"type": "end",
					"position": Vector2(420, 180)
				}
			},
			"connections": [
				{"from": "start", "to": "end", "from_port": 0, "to_port": 0}
			]
		},
		"_editor": {
			"relationship_position": Vector2(320, 200)
		}
	}


func _on_delete_current_quest() -> void:
	if _editor_mode != MODE_FLOW or _current_quest_id.is_empty():
		_update_status("只有单任务模式可以删除 Quest")
		return

	var deleted_quest_id := _current_quest_id
	_quests.erase(deleted_quest_id)
	_validation_errors.erase(deleted_quest_id)
	_handle_deleted_quest(deleted_quest_id)
	_current_quest_id = ""
	_show_relationship_mode("")
	_update_status("已删除任务: %s" % deleted_quest_id)


func _get_search_strings(data: Dictionary) -> Array[String]:
	var values: Array[String] = [
		str(data.get("id", "")),
		str(data.get("quest_id", "")),
		str(data.get("title", "")),
		str(data.get("description", "")),
		str(data.get("dialog_id", "")),
		str(data.get("objective_type", ""))
	]
	for option_variant in data.get("options", []):
		if option_variant is Dictionary:
			values.append(str(option_variant.get("id", "")))
			values.append(str(option_variant.get("text", "")))
	return values


func _sync_displayed_graph_to_store() -> void:
	_sync_node_positions_from_graph()
	if _editor_mode == MODE_RELATIONSHIP:
		_sync_relationship_positions_to_store()
	else:
		_sync_flow_nodes_to_store()
		_sync_flow_connections_to_store()


func _sync_relationship_positions_to_store() -> void:
	for quest_id_variant in nodes.keys():
		var quest_id := str(quest_id_variant)
		if not _quests.has(quest_id):
			continue
		var relationship_node: Dictionary = nodes[quest_id]
		var quest: Dictionary = _quests[quest_id]
		var editor_meta: Dictionary = quest.get("_editor", {})
		editor_meta["relationship_position"] = relationship_node.get("position", Vector2.ZERO)
		quest["_editor"] = editor_meta
		_quests[quest_id] = quest


func _sync_flow_nodes_to_store() -> void:
	if _editor_mode != MODE_FLOW or _current_quest_id.is_empty() or not _quests.has(_current_quest_id):
		return
	var quest: Dictionary = _quests[_current_quest_id]
	var flow: Dictionary = quest.get("flow", {})
	var flow_nodes: Dictionary = {}
	for node_id_variant in nodes.keys():
		var node_id := str(node_id_variant)
		flow_nodes[node_id] = nodes[node_id].duplicate(true)
	flow["nodes"] = flow_nodes
	quest["flow"] = flow
	_quests[_current_quest_id] = quest


func _sync_flow_connections_to_store() -> void:
	if _editor_mode != MODE_FLOW or _current_quest_id.is_empty() or not _quests.has(_current_quest_id):
		return
	var quest: Dictionary = _quests[_current_quest_id]
	var flow: Dictionary = quest.get("flow", {})
	var stored_connections: Array[Dictionary] = []
	for conn_variant in connections:
		if conn_variant is Dictionary:
			stored_connections.append(conn_variant.duplicate(true))
	flow["connections"] = stored_connections
	quest["flow"] = flow
	_quests[_current_quest_id] = quest


func _prune_invalid_flow_connections() -> void:
	if _editor_mode != MODE_FLOW or _current_quest_id.is_empty():
		return
	var flow: Dictionary = _quests[_current_quest_id].get("flow", {})
	var flow_nodes: Dictionary = flow.get("nodes", {})
	var valid_connections: Array[Dictionary] = []
	for conn_variant in flow.get("connections", []):
		if not (conn_variant is Dictionary):
			continue
		var conn: Dictionary = conn_variant
		var from_id := str(conn.get("from", ""))
		var to_id := str(conn.get("to", ""))
		if not flow_nodes.has(from_id) or not flow_nodes.has(to_id):
			continue
		var from_node: Dictionary = flow_nodes[from_id]
		if int(conn.get("from_port", 0)) >= _get_output_port_count(from_node):
			continue
		valid_connections.append(conn)
	flow["connections"] = valid_connections
	var quest: Dictionary = _quests[_current_quest_id]
	quest["flow"] = flow
	_quests[_current_quest_id] = quest


func _get_output_port_count(node_data: Dictionary) -> int:
	match str(node_data.get("type", "")):
		"dialog":
			return max(_get_dialog_output_count(node_data), 1)
		"choice":
			return max(node_data.get("options", []).size(), 1)
		"end":
			return 0
		_:
			return 1


func _on_save_quests() -> void:
	_save_all_quests()


func _save_all_quests() -> bool:
	_sync_displayed_graph_to_store()
	if not _ensure_quest_dir():
		return false

	var quest_ids: Array = _quests.keys()
	quest_ids.sort()
	for quest_id_variant in quest_ids:
		var quest_id := str(quest_id_variant)
		var quest: Dictionary = _quests[quest_id]
		var quest_file_path := "%s/%s.json" % [QUEST_DATA_DIR, quest_id]
		var file := FileAccess.open(quest_file_path, FileAccess.WRITE)
		if file == null:
			push_warning("[QuestEditor] 无法保存任务文件: %s" % quest_file_path)
			continue
		file.store_string(JSON.stringify(_serialize_quest_for_storage(quest_id, quest), "\t"))
		file.close()

	var dir := DirAccess.open(QUEST_DATA_DIR)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				var existing_id := file_name.trim_suffix(".json")
				if not _quests.has(existing_id):
					dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

	var emitted_quest_id := _current_quest_id if not _current_quest_id.is_empty() else _focused_relationship_quest_id
	quest_saved.emit(emitted_quest_id)
	_reset_dirty_tracking_to_persisted_state()
	_refresh_record_list()
	_update_status("已保存 %d 个任务" % _quests.size())
	return true


func _ensure_quest_dir() -> bool:
	var absolute_dir_path := ProjectSettings.globalize_path(QUEST_DATA_DIR)
	if DirAccess.dir_exists_absolute(absolute_dir_path):
		return true
	return DirAccess.make_dir_recursive_absolute(absolute_dir_path) == OK


func _serialize_quest_for_storage(quest_id: String, quest: Dictionary) -> Dictionary:
	var serialized: Dictionary = {
		"quest_id": quest_id,
		"title": str(quest.get("title", "")),
		"description": str(quest.get("description", "")),
		"prerequisites": quest.get("prerequisites", []).duplicate(),
		"time_limit": int(quest.get("time_limit", -1)),
		"flow": {
			"start_node_id": str(quest.get("flow", {}).get("start_node_id", "start")),
			"nodes": {},
			"connections": quest.get("flow", {}).get("connections", []).duplicate(true)
		},
		"_editor": {
			"relationship_position": _serialize_position(quest.get("_editor", {}).get("relationship_position", Vector2.ZERO))
		}
	}

	var serialized_nodes: Dictionary = {}
	for node_id_variant in quest.get("flow", {}).get("nodes", {}).keys():
		var node_id := str(node_id_variant)
		var node_data: Dictionary = quest.get("flow", {}).get("nodes", {})[node_id].duplicate(true)
		node_data["position"] = _serialize_position(node_data.get("position", Vector2.ZERO))
		node_data.erase("title")
		serialized_nodes[node_id] = node_data
	serialized["flow"]["nodes"] = serialized_nodes
	return serialized


func _serialize_position(position_value: Variant) -> Dictionary:
	var position := position_value if position_value is Vector2 else Vector2.ZERO
	return {"x": position.x, "y": position.y}


func _on_load_quests() -> void:
	_load_quests_from_directory()


func _save_before_close() -> bool:
	return _save_all_quests()


func _validate_quest(quest_id: String) -> bool:
	if not _quests.has(quest_id):
		return false
	var quest: Dictionary = _quests[quest_id]
	var errors: Array[String] = _validate_quest_record(quest_id, quest)
	_validation_errors[quest_id] = errors
	return errors.is_empty()


func _validate_all() -> Array[String]:
	var all_errors: Array[String] = []
	var quest_ids: Array = _quests.keys()
	quest_ids.sort()
	for quest_id_variant in quest_ids:
		var quest_id := str(quest_id_variant)
		_validate_quest(quest_id)
		for error in _validation_errors.get(quest_id, []):
			all_errors.append("%s: %s" % [quest_id, error])
	validation_errors_found.emit(all_errors)
	return all_errors


func _on_validate_all() -> void:
	var errors := _validate_all()
	_update_validation_panel()
	if errors.is_empty():
		_update_status("所有任务验证通过")
	else:
		_update_status("发现 %d 个验证问题" % errors.size())


func _update_validation_panel() -> void:
	if _validation_panel == null:
		return
	while _validation_panel.get_child_count() > 2:
		var child := _validation_panel.get_child(2)
		_validation_panel.remove_child(child)
		child.queue_free()

	var quest_id := _current_quest_id if _editor_mode == MODE_FLOW else selected_node_id
	var errors: Array = _validation_errors.get(quest_id, [])
	_validation_panel.visible = not errors.is_empty()
	for error_variant in errors:
		var label := Label.new()
		label.text = str(error_variant)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		_validation_panel.add_child(label)


func _format_prerequisites(prerequisites: Array) -> String:
	if prerequisites.is_empty():
		return "无"
	var parts: Array[String] = []
	for prereq_variant in prerequisites:
		parts.append(str(prereq_variant))
	return ", ".join(parts)


func _get_step_count(quest: Dictionary) -> int:
	return quest.get("flow", {}).get("nodes", {}).size()


func _load_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var json_text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_text) != OK:
		push_warning("[QuestEditor] JSON 解析失败: %s" % path)
		return null
	return json.data


func _is_reward_empty(rewards: Dictionary) -> bool:
	if rewards.is_empty():
		return true
	if rewards.get("items", []).size() > 0:
		return false
	if int(rewards.get("experience", 0)) > 0:
		return false
	if int(rewards.get("skill_points", 0)) > 0:
		return false
	if rewards.has("unlock_location") and not str(rewards.get("unlock_location", "")).is_empty():
		return false
	if rewards.has("unlock_recipes") and rewards.get("unlock_recipes", []).size() > 0:
		return false
	if rewards.has("title") and not str(rewards.get("title", "")).is_empty():
		return false
	return true


func _update_toolbar_state() -> void:
	if _mode_button:
		_mode_button.text = "返回关系图" if _editor_mode == MODE_FLOW else "关系图模式"
		_mode_button.disabled = _editor_mode == MODE_RELATIONSHIP
	if _new_button:
		_new_button.disabled = _editor_mode != MODE_RELATIONSHIP
	if _delete_quest_button:
		_delete_quest_button.disabled = _editor_mode != MODE_FLOW


func _input(event: InputEvent) -> void:
	super._input(event)
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_N when event.ctrl_pressed:
				_on_new_quest()
			KEY_S when event.ctrl_pressed:
				_on_save_quests()
			KEY_ESCAPE:
				if _editor_mode == MODE_FLOW:
					_show_relationship_mode(_current_quest_id)


func focus_record(record_id: String) -> bool:
	var target_id := record_id.strip_edges()
	if target_id.is_empty() or not _quests.has(target_id):
		_update_status("未找到任务: %s" % record_id)
		return false
	_show_relationship_mode(target_id)
	_graph_edit.center_view()
	return true


func get_current_quest_id() -> String:
	return _current_quest_id if not _current_quest_id.is_empty() else selected_node_id


func get_quests_count() -> int:
	return _quests.size()


func get_validation_errors() -> Dictionary:
	return _validation_errors


func _validate_quest_record(quest_id: String, quest: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if quest_id.is_empty():
		errors.append("任务ID不能为空")
	if str(quest.get("title", "")).strip_edges().is_empty():
		errors.append("任务标题不能为空")

	for prereq_variant in quest.get("prerequisites", []):
		var prereq_id := str(prereq_variant)
		if not _quests.has(prereq_id) and prereq_id != quest_id:
			errors.append("前置任务不存在: %s" % prereq_id)

	var flow: Dictionary = quest.get("flow", {})
	var flow_nodes: Dictionary = flow.get("nodes", {})
	var start_count := 0
	var end_count := 0
	for node_id_variant in flow_nodes.keys():
		var node_id := str(node_id_variant)
		var node: Dictionary = flow_nodes[node_id]
		match str(node.get("type", "")):
			"start":
				start_count += 1
			"end":
				end_count += 1
			"objective":
				if str(node.get("objective_type", "")).is_empty():
					errors.append("%s: objective_type 不能为空" % node_id)
				if str(node.get("objective_type", "")) == "collect":
					var item_id_text := str(node.get("item_id", "")).strip_edges()
					if item_id_text.is_empty() or not FileAccess.file_exists("res://data/items/%s.json" % item_id_text):
						errors.append("%s: collect 节点引用了不存在的 item_id" % node_id)
			"dialog":
				var dialog_id := str(node.get("dialog_id", "")).strip_edges()
				if dialog_id.is_empty():
					errors.append("%s: dialog_id 不能为空" % node_id)
				elif not FileAccess.file_exists("res://data/dialogues/%s.json" % dialog_id):
					errors.append("%s: dialog_id 不存在 -> %s" % [node_id, dialog_id])
			"choice":
				if node.get("options", []).is_empty():
					errors.append("%s: choice 至少要有一个选项" % node_id)
			"reward":
				for reward_item_variant in node.get("rewards", {}).get("items", []):
					if reward_item_variant is Dictionary:
						var reward_item_id := str((reward_item_variant as Dictionary).get("id", "")).strip_edges()
						if reward_item_id.is_empty() or not FileAccess.file_exists("res://data/items/%s.json" % reward_item_id):
							errors.append("%s: reward 节点引用了不存在的物品" % node_id)

	if start_count != 1:
		errors.append("每个 Quest 必须且只能有一个 start 节点")
	if end_count < 1:
		errors.append("每个 Quest 至少需要一个 end 节点")

	var start_node_id := str(flow.get("start_node_id", "start"))
	if not flow_nodes.has(start_node_id):
		errors.append("flow.start_node_id 指向不存在的节点")
	elif str(flow_nodes[start_node_id].get("type", "")) != "start":
		errors.append("flow.start_node_id 必须指向 start 节点")

	for conn_variant in flow.get("connections", []):
		if not (conn_variant is Dictionary):
			errors.append("存在无效连接数据")
			continue
		var conn: Dictionary = conn_variant
		if not flow_nodes.has(str(conn.get("from", ""))) or not flow_nodes.has(str(conn.get("to", ""))):
			errors.append("连接引用了不存在的节点")

	return errors
