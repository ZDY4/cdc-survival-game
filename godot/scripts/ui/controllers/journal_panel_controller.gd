extends Control

var _panel: PanelContainer
var _summary_label: Label
var _quest_box: VBoxContainer


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()


func apply_snapshot(snapshot: Dictionary) -> void:
	if _panel == null:
		_build_layout()

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
		return

	for quest in quests:
		var quest_data: Dictionary = quest
		_quest_box.add_child(_quest_title(quest_data))
		_quest_box.add_child(_quest_objective(quest_data))
		_quest_box.add_child(_quest_reward(quest_data))


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
	box.add_child(_summary_label)
	box.add_child(_quest_box)


func _quest_title(quest: Dictionary) -> Label:
	var label := _label("Quest_%s" % quest.get("quest_id", "unknown"))
	label.text = str(quest.get("title", ""))
	return label


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
