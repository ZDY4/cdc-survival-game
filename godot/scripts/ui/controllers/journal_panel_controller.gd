extends Control

signal tracked_quest_changed(quest_id: String)

var _panel: PanelContainer
var _summary_label: Label
var _quest_box: VBoxContainer
var _completed_box: VBoxContainer
var _detail_title_label: Label
var _detail_body_label: Label
var _track_button: Button
var _feedback_label: Label
var _failure_history_label: Label
var _last_snapshot: Dictionary = {}
var _selected_quest_id := ""
var _tracked_quest_id := ""
var _journal_feedback_text := ""
var _failure_history: Array[String] = []


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()


func apply_snapshot(snapshot: Dictionary) -> void:
	if _panel == null:
		_build_layout()

	_last_snapshot = snapshot.duplicate(true)
	_tracked_quest_id = str(snapshot.get("tracked_quest_id", _tracked_quest_id))
	var quests: Array = snapshot.get("quests", [])
	var completed_quests: Array = snapshot.get("completed_quests", [])
	_summary_label.text = "任务 %d | 已完成 %d" % [
		quests.size(),
		int(snapshot.get("completed_count", 0)),
	]
	_feedback_label.text = _journal_feedback_text
	_failure_history_label.text = _failure_history_text()
	_clear_quests()
	_clear_completed_quests()
	if quests.is_empty():
		var empty := _label("QuestEmpty")
		empty.text = "当前没有进行中的任务"
		_quest_box.add_child(empty)
	else:
		if _selected_quest_id.is_empty() or (_quest_by_id(quests, _selected_quest_id).is_empty() and _quest_by_id(completed_quests, _selected_quest_id).is_empty()):
			_selected_quest_id = str(_dictionary_or_empty(quests[0]).get("quest_id", ""))
		for quest in quests:
			var quest_data: Dictionary = quest
			_quest_box.add_child(_quest_title(quest_data))
			_quest_box.add_child(_quest_objective(quest_data))
			for progress in _array_or_empty(quest_data.get("objective_progress", [])):
				_quest_box.add_child(_objective_progress_line(str(quest_data.get("quest_id", "unknown")), _dictionary_or_empty(progress)))
			_quest_box.add_child(_quest_reward(quest_data))

	if completed_quests.is_empty():
		var completed_empty := _label("CompletedQuestEmpty")
		completed_empty.text = "暂无已完成任务"
		_completed_box.add_child(completed_empty)
	else:
		var completed_title := _label("CompletedQuestHeader")
		completed_title.text = "已完成"
		_completed_box.add_child(completed_title)
		for quest in completed_quests:
			var completed_data: Dictionary = quest
			_completed_box.add_child(_completed_quest_line(completed_data))
	var selected: Dictionary = _quest_by_id(quests, _selected_quest_id)
	if selected.is_empty():
		selected = _quest_by_id(completed_quests, _selected_quest_id)
	if selected.is_empty() and quests.is_empty() and not completed_quests.is_empty():
		_selected_quest_id = str(_dictionary_or_empty(completed_quests[0]).get("quest_id", ""))
		selected = _quest_by_id(completed_quests, _selected_quest_id)
	_apply_detail(selected)


func _build_layout() -> void:
	if _panel != null:
		return

	_panel = PanelContainer.new()
	_panel.name = "JournalPanel"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.offset_left = 16
	_panel.offset_right = 430
	_panel.offset_top = -220
	_panel.offset_bottom = -24
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "JournalLines"
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	_summary_label = _label("SummaryLine")
	_quest_box = VBoxContainer.new()
	_quest_box.name = "QuestLines"
	_quest_box.add_theme_constant_override("separation", 4)
	_completed_box = VBoxContainer.new()
	_completed_box.name = "CompletedQuestLines"
	_completed_box.add_theme_constant_override("separation", 4)
	_detail_title_label = _label("DetailTitleLine")
	_detail_body_label = _label("DetailBodyLine")
	_track_button = Button.new()
	_track_button.name = "TrackQuestButton"
	_track_button.text = "追踪"
	_track_button.tooltip_text = "追踪选中的任务"
	_track_button.custom_minimum_size = Vector2(64, 28)
	_track_button.focus_mode = Control.FOCUS_NONE
	_track_button.pressed.connect(_toggle_tracked_quest, CONNECT_DEFERRED)
	_feedback_label = _label("JournalFeedbackLine")
	_failure_history_label = _label("JournalFailureHistoryLine")
	box.add_child(_summary_label)
	box.add_child(_quest_box)
	box.add_child(_completed_box)
	box.add_child(_detail_title_label)
	box.add_child(_detail_body_label)
	box.add_child(_track_button)
	box.add_child(_feedback_label)
	box.add_child(_failure_history_label)


func _quest_title(quest: Dictionary) -> Button:
	var button := Button.new()
	var quest_id := str(quest.get("quest_id", "unknown"))
	button.name = "Quest_%s" % quest_id
	button.text = "%s%s" % [
		"* " if _tracked_quest_id == quest_id else "",
		str(quest.get("title", "")),
	]
	button.tooltip_text = "查看 %s" % quest.get("title", quest_id)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.toggle_mode = true
	button.button_pressed = _selected_quest_id == quest_id
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		_selected_quest_id = quest_id
		apply_snapshot(_last_snapshot)
	, CONNECT_DEFERRED)
	return button


func _completed_quest_line(quest: Dictionary) -> Button:
	var button := Button.new()
	var quest_id := str(quest.get("quest_id", "unknown"))
	button.name = "CompletedQuest_%s" % quest_id
	button.text = "%s | 已完成" % str(quest.get("title", quest_id))
	button.tooltip_text = "查看已完成任务 %s" % quest.get("title", quest_id)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.toggle_mode = true
	button.button_pressed = _selected_quest_id == quest_id
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		_selected_quest_id = quest_id
		apply_snapshot(_last_snapshot)
	, CONNECT_DEFERRED)
	return button


func _quest_objective(quest: Dictionary) -> Label:
	var label := _label("Objective_%s" % quest.get("quest_id", "unknown"))
	label.text = "目标: %s | 进度: %d/%d | %s" % [
		quest.get("objective_text", ""),
		int(quest.get("progress_current", 0)),
		int(quest.get("progress_target", 0)),
		quest.get("status_text", ""),
	]
	return label


func _objective_progress_line(quest_id: String, progress: Dictionary) -> Label:
	var objective_id := str(progress.get("id", "unknown"))
	var label := _label("ObjectiveProgress_%s_%s" % [quest_id, objective_id])
	label.text = "- %s: %d/%d | %s | %s" % [
		str(progress.get("description", progress.get("requirement_text", objective_id))),
		int(progress.get("current", 0)),
		int(progress.get("target", 0)),
		str(progress.get("requirement_text", "")),
		"完成" if str(progress.get("state", "")) == "completed" else "进行中",
	]
	return label


func _quest_reward(quest: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Reward_%s" % quest.get("quest_id", "unknown")
	row.custom_minimum_size = Vector2(380, 28)
	row.add_theme_constant_override("separation", 6)
	var label := _label("Line")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = "奖励: %s" % _reward_text(quest.get("rewards", {}))
	var button := Button.new()
	button.name = "TurnInButton"
	button.text = "交"
	button.tooltip_text = "交付 %s" % quest.get("title", quest.get("quest_id", ""))
	button.custom_minimum_size = Vector2(36, 28)
	button.disabled = not bool(quest.get("turn_in_ready", false))
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	var quest_id := str(quest.get("quest_id", ""))
	var quest_title := str(quest.get("title", quest_id))
	var reward_text := _reward_text(quest.get("rewards", {}))
	button.pressed.connect(func() -> void:
		var root := get_parent()
		if root != null and root.has_method("turn_in_player_quest"):
			var result: Dictionary = root.turn_in_player_quest(quest_id)
			if bool(result.get("success", false)):
				_journal_feedback_text = "已完成 %s，获得奖励: %s" % [quest_title, reward_text]
			else:
				_journal_feedback_text = "交付 %s 失败: %s" % [quest_title, _turn_in_failure_text(str(result.get("reason", "unknown")))]
				_record_failure(quest_title, str(result.get("reason", "unknown")))
			_feedback_label.text = _journal_feedback_text
			_failure_history_label.text = _failure_history_text()
	, CONNECT_DEFERRED)
	row.add_child(label)
	row.add_child(button)
	return row


func _apply_detail(quest: Dictionary) -> void:
	if _detail_title_label == null or _detail_body_label == null or _track_button == null:
		return
	if quest.is_empty():
		_detail_title_label.text = "任务详情"
		_detail_body_label.text = "选择任务查看详情"
		_track_button.disabled = true
		_track_button.text = "追踪"
		return
	var quest_id := str(quest.get("quest_id", ""))
	var objective: Dictionary = _dictionary_or_empty(quest.get("objective", {}))
	var is_completed := str(quest.get("state", "active")) == "completed"
	_detail_title_label.text = "详情: %s%s" % [
		quest.get("title", quest_id),
		"（已完成）" if is_completed else "",
	]
	var lines: Array[String] = []
	var description := str(quest.get("description", ""))
	if not description.is_empty():
		lines.append(description)
	lines.append("当前节点: %s" % quest.get("current_node_id", ""))
	lines.append("目标: %s" % quest.get("objective_text", ""))
	lines.append("类型: %s | 需求: %s" % [
		objective.get("type", quest.get("objective_type", "")),
		objective.get("requirement_text", ""),
	])
	lines.append("进度: %d/%d | %s" % [
		int(quest.get("progress_current", 0)),
		int(quest.get("progress_target", 0)),
		quest.get("status_text", ""),
	])
	var progress_lines := _objective_progress_texts(quest.get("objective_progress", []))
	if not progress_lines.is_empty():
		lines.append("目标进度:")
		lines.append_array(progress_lines)
	if bool(quest.get("manual_turn_in", false)):
		lines.append("交付: %s" % ("可交付" if bool(quest.get("turn_in_ready", false)) else "需要完成目标后手动交付"))
	lines.append("奖励: %s" % _reward_text(quest.get("rewards", {})))
	_detail_body_label.text = "\n".join(lines)
	_track_button.disabled = is_completed
	_track_button.text = "已完成" if is_completed else ("取消追踪" if _tracked_quest_id == quest_id else "追踪")
	_track_button.tooltip_text = "%s %s" % [_track_button.text, quest.get("title", quest_id)]


func _toggle_tracked_quest() -> void:
	if _selected_quest_id.is_empty():
		return
	_tracked_quest_id = "" if _tracked_quest_id == _selected_quest_id else _selected_quest_id
	_last_snapshot["tracked_quest_id"] = _tracked_quest_id
	tracked_quest_changed.emit(_tracked_quest_id)
	if not _last_snapshot.is_empty():
		apply_snapshot(_last_snapshot)


func _reward_text(rewards: Dictionary) -> String:
	var parts: Array[String] = []
	for item in rewards.get("items", []):
		var item_data: Dictionary = item
		parts.append("%s x%d" % [
			item_data.get("name", item_data.get("item_id", "")),
			int(item_data.get("count", 1)),
		])
	if int(rewards.get("experience", 0)) > 0:
		parts.append("XP %d" % int(rewards.get("experience", 0)))
	if int(rewards.get("skill_points", 0)) > 0:
		parts.append("技能点 %d" % int(rewards.get("skill_points", 0)))
	return "无" if parts.is_empty() else " / ".join(parts)


func _objective_progress_texts(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for progress in _array_or_empty(value):
		var progress_data: Dictionary = _dictionary_or_empty(progress)
		result.append("- %s: %d/%d | %s" % [
			str(progress_data.get("description", progress_data.get("requirement_text", progress_data.get("id", "")))),
			int(progress_data.get("current", 0)),
			int(progress_data.get("target", 0)),
			"完成" if str(progress_data.get("state", "")) == "completed" else "进行中",
		])
	return result


func _turn_in_failure_text(reason: String) -> String:
	match reason:
		"simulation_missing":
			return "运行时未就绪"
		"quest_not_active":
			return "任务未激活"
		"quest_not_waiting_for_turn_in":
			return "任务不需要手动交付"
		"quest_objective_incomplete":
			return "目标尚未完成"
		"not_enough_items":
			return "物品不足"
		_:
			return reason


func _record_failure(quest_title: String, reason: String) -> void:
	var text := "%s: %s" % [quest_title, _turn_in_failure_text(reason)]
	_failure_history.append(text)
	while _failure_history.size() > 5:
		_failure_history.pop_front()


func _failure_history_text() -> String:
	if _failure_history.is_empty():
		return "失败历史: 无"
	return "失败历史: %s" % "；".join(_failure_history)


func _label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _clear_quests() -> void:
	for child in _quest_box.get_children():
		_quest_box.remove_child(child)
		child.free()


func _clear_completed_quests() -> void:
	for child in _completed_box.get_children():
		_completed_box.remove_child(child)
		child.free()


func _quest_by_id(quests: Array, quest_id: String) -> Dictionary:
	for quest in quests:
		var quest_data: Dictionary = _dictionary_or_empty(quest)
		if str(quest_data.get("quest_id", "")) == quest_id:
			return quest_data
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
