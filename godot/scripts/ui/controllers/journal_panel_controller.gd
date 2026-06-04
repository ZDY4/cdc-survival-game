extends Control

var _panel: PanelContainer
var _summary_label: Label
var _quest_box: VBoxContainer
var _detail_title_label: Label
var _detail_body_label: Label
var _track_button: Button
var _last_snapshot: Dictionary = {}
var _selected_quest_id := ""
var _tracked_quest_id := ""


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()


func apply_snapshot(snapshot: Dictionary) -> void:
	if _panel == null:
		_build_layout()

	_last_snapshot = snapshot.duplicate(true)
	var quests: Array = snapshot.get("quests", [])
	_summary_label.text = "任务 %d | 已完成 %d" % [
		quests.size(),
		int(snapshot.get("completed_count", 0)),
	]
	_clear_quests()
	if quests.is_empty():
		var empty := _label("QuestEmpty")
		empty.text = "当前没有进行中的任务"
		_quest_box.add_child(empty)
		_selected_quest_id = ""
		_apply_detail({})
		return

	if _selected_quest_id.is_empty() or _quest_by_id(quests, _selected_quest_id).is_empty():
		_selected_quest_id = str(_dictionary_or_empty(quests[0]).get("quest_id", ""))
	for quest in quests:
		var quest_data: Dictionary = quest
		_quest_box.add_child(_quest_title(quest_data))
		_quest_box.add_child(_quest_objective(quest_data))
		_quest_box.add_child(_quest_reward(quest_data))
	_apply_detail(_quest_by_id(quests, _selected_quest_id))


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
	_detail_title_label = _label("DetailTitleLine")
	_detail_body_label = _label("DetailBodyLine")
	_track_button = Button.new()
	_track_button.name = "TrackQuestButton"
	_track_button.text = "追踪"
	_track_button.tooltip_text = "追踪选中的任务"
	_track_button.custom_minimum_size = Vector2(64, 28)
	_track_button.focus_mode = Control.FOCUS_NONE
	_track_button.pressed.connect(_toggle_tracked_quest, CONNECT_DEFERRED)
	box.add_child(_summary_label)
	box.add_child(_quest_box)
	box.add_child(_detail_title_label)
	box.add_child(_detail_body_label)
	box.add_child(_track_button)


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


func _quest_objective(quest: Dictionary) -> Label:
	var label := _label("Objective_%s" % quest.get("quest_id", "unknown"))
	label.text = "目标: %s | 进度: %d/%d | %s" % [
		quest.get("objective_text", ""),
		int(quest.get("progress_current", 0)),
		int(quest.get("progress_target", 0)),
		quest.get("status_text", ""),
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
	button.pressed.connect(func() -> void:
		var root := get_parent()
		if root != null and root.has_method("turn_in_player_quest"):
			root.turn_in_player_quest(quest_id)
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
	_detail_title_label.text = "详情: %s" % quest.get("title", quest_id)
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
	if bool(quest.get("manual_turn_in", false)):
		lines.append("交付: %s" % ("可交付" if bool(quest.get("turn_in_ready", false)) else "需要完成目标后手动交付"))
	lines.append("奖励: %s" % _reward_text(quest.get("rewards", {})))
	_detail_body_label.text = "\n".join(lines)
	_track_button.disabled = false
	_track_button.text = "取消追踪" if _tracked_quest_id == quest_id else "追踪"
	_track_button.tooltip_text = "%s %s" % [_track_button.text, quest.get("title", quest_id)]


func _toggle_tracked_quest() -> void:
	if _selected_quest_id.is_empty():
		return
	_tracked_quest_id = "" if _tracked_quest_id == _selected_quest_id else _selected_quest_id
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
