extends Control

var _panel: PanelContainer
var _summary_label: Label
var _hotbar_label: Label
var _feedback_label: Label
var _filter_box: HBoxContainer
var _tree_filter_box: HBoxContainer
var _tree_box: VBoxContainer
var _detail_title_label: Label
var _detail_body_label: Label
var _learn_confirm_dialog: ConfirmationDialog
var _filter_mode: String = "all"
var _tree_filter_mode: String = "all"
var _selected_skill_id := ""
var _pending_learn_skill: Dictionary = {}
var _learn_feedback_text := ""
var _last_snapshot: Dictionary = {}


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()


func apply_snapshot(snapshot: Dictionary) -> void:
	if _panel == null:
		_build_layout()
	_last_snapshot = snapshot.duplicate(true)

	_summary_label.text = "%s Lv%d | 技能点 %d" % [
		snapshot.get("owner_name", ""),
		int(snapshot.get("level", 1)),
		int(snapshot.get("available_skill_points", 0)),
	]
	_hotbar_label.text = _hotbar_text(snapshot.get("hotbar", {}))
	_feedback_label.visible = not _learn_feedback_text.is_empty()
	_feedback_label.text = _learn_feedback_text
	_rebuild_tree_filter_buttons(snapshot)
	_clear_trees()
	var visible_skills: Array[Dictionary] = []
	for tree in snapshot.get("trees", []):
		var tree_data: Dictionary = tree
		if not _tree_matches_filter(tree_data):
			continue
		var tree_visible_skills: Array[Dictionary] = _visible_skills(tree_data)
		if tree_visible_skills.is_empty():
			continue
		_tree_box.add_child(_tree_title(tree_data, tree_visible_skills.size()))
		for skill in tree_visible_skills:
			var skill_data: Dictionary = skill
			visible_skills.append(skill_data)
			_tree_box.add_child(_skill_row(skill_data))
	if visible_skills.is_empty():
		var empty := _label("SkillEmptyLine")
		empty.text = "没有符合筛选的技能"
		_tree_box.add_child(empty)
		_apply_detail({})
		return
	if _selected_skill_id.is_empty() or _skill_by_id(visible_skills, _selected_skill_id).is_empty():
		_selected_skill_id = str(visible_skills[0].get("skill_id", ""))
	_apply_detail(_skill_by_id(visible_skills, _selected_skill_id))


func _build_layout() -> void:
	if _panel != null:
		return

	_panel = PanelContainer.new()
	_panel.name = "SkillsPanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_panel.offset_left = 16
	_panel.offset_right = 455
	_panel.offset_top = -155
	_panel.offset_bottom = 165
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "SkillsLines"
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	_summary_label = _label("SummaryLine")
	_hotbar_label = _label("HotbarLine")
	_feedback_label = _label("FeedbackLine")
	_filter_box = HBoxContainer.new()
	_filter_box.name = "FilterBar"
	_filter_box.add_theme_constant_override("separation", 4)
	_tree_filter_box = HBoxContainer.new()
	_tree_filter_box.name = "TreeFilterBar"
	_tree_filter_box.add_theme_constant_override("separation", 4)
	_tree_box = VBoxContainer.new()
	_tree_box.name = "TreeLines"
	_tree_box.add_theme_constant_override("separation", 4)
	_detail_title_label = _label("DetailTitleLine")
	_detail_body_label = _label("DetailBodyLine")
	_learn_confirm_dialog = ConfirmationDialog.new()
	_learn_confirm_dialog.name = "LearnSkillConfirmDialog"
	_learn_confirm_dialog.title = "确认学习技能"
	_learn_confirm_dialog.dialog_text = "确定学习选中的技能吗？"
	_learn_confirm_dialog.confirmed.connect(_confirm_pending_learn)
	_learn_confirm_dialog.get_ok_button().text = "学习"
	_learn_confirm_dialog.get_cancel_button().text = "取消"
	add_child(_learn_confirm_dialog)
	box.add_child(_summary_label)
	box.add_child(_hotbar_label)
	box.add_child(_feedback_label)
	box.add_child(_filter_box)
	_add_filter_button("FilterAllButton", "全部", "all")
	_add_filter_button("FilterLearnedButton", "已学", "learned")
	_add_filter_button("FilterAvailableButton", "可学", "available")
	_add_filter_button("FilterLockedButton", "锁定", "locked")
	_add_filter_button("FilterActiveButton", "主动", "active")
	box.add_child(_tree_filter_box)
	box.add_child(_tree_box)
	box.add_child(_detail_title_label)
	box.add_child(_detail_body_label)


func _tree_title(tree: Dictionary, visible_count: int) -> Label:
	var label := _label("Tree_%s" % tree.get("tree_id", "unknown"))
	label.text = "%s | %d 技能" % [
		tree.get("name", tree.get("tree_id", "")),
		visible_count,
	]
	return label


func _tree_matches_filter(tree: Dictionary) -> bool:
	return _tree_filter_mode == "all" or str(tree.get("tree_id", "")) == _tree_filter_mode


func _visible_skills(tree: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for skill in tree.get("skills", []):
		var skill_data: Dictionary = skill
		if _skill_matches_filter(skill_data):
			rows.append(skill_data)
	return rows


func _skill_matches_filter(skill: Dictionary) -> bool:
	match _filter_mode:
		"learned":
			return int(skill.get("level", 0)) > 0
		"available":
			return bool(skill.get("can_learn", false))
		"locked":
			return int(skill.get("level", 0)) <= 0 and not bool(skill.get("can_learn", false))
		"active":
			return str(skill.get("activation_mode", "passive")) != "passive"
	return true


func _skill_row(skill: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Skill_%s" % skill.get("skill_id", "unknown")
	row.custom_minimum_size = Vector2(430, 28)
	row.add_theme_constant_override("separation", 6)
	var line := Button.new()
	line.name = "Line"
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.text = "%s %d/%d | %s | %s" % [
		skill.get("name", skill.get("skill_id", "")),
		int(skill.get("level", 0)),
		int(skill.get("max_level", 1)),
		skill.get("activation_mode", "passive"),
		"%s%s%s%s" % [_reason_text(skill), _binding_text(skill), _activation_cost_text(skill), _use_reason_text(skill)],
	]
	line.tooltip_text = "查看 %s" % skill.get("name", skill.get("skill_id", ""))
	line.alignment = HORIZONTAL_ALIGNMENT_LEFT
	line.toggle_mode = true
	line.button_pressed = _selected_skill_id == str(skill.get("skill_id", ""))
	line.focus_mode = Control.FOCUS_NONE
	var skill_id := str(skill.get("skill_id", ""))
	line.set_meta("skill_drag_data", skill.duplicate(true))
	line.set_drag_forwarding(
		Callable(self, "_get_skill_drag_data"),
		Callable(self, "_empty_skill_drop_check"),
		Callable(self, "_empty_skill_drop")
	)
	line.pressed.connect(func() -> void:
		_selected_skill_id = skill_id
		_learn_feedback_text = ""
		apply_snapshot(_last_snapshot)
	, CONNECT_DEFERRED)
	var learn_button := _button("LearnButton", "+", "学习 %s" % skill.get("name", skill_id), not bool(skill.get("can_learn", false)))
	learn_button.pressed.connect(func() -> void:
		_open_learn_confirm(skill.duplicate(true))
	, CONNECT_DEFERRED)
	var bind_button := _button("BindButton", "B", "绑定 %s 到第一个空快捷栏" % skill.get("name", skill_id), not bool(skill.get("can_bind", false)))
	bind_button.pressed.connect(func() -> void:
		var root := get_parent()
		if root != null and root.has_method("bind_player_skill_to_hotbar"):
			root.bind_player_skill_to_hotbar("", skill_id)
	, CONNECT_DEFERRED)
	var use_button := _button("UseButton", "U", "使用 %s" % skill.get("name", skill_id), not bool(skill.get("can_use", false)))
	use_button.pressed.connect(func() -> void:
		var root := get_parent()
		if root != null and root.has_method("use_hotbar_slot"):
			root.use_hotbar_slot(str(skill.get("bound_slot", "")))
	, CONNECT_DEFERRED)
	var bound_slot_id: String = str(skill.get("bound_slot", ""))
	var clear_button := _button("ClearButton", "X", "清空 %s" % bound_slot_id, bound_slot_id.is_empty())
	clear_button.pressed.connect(func() -> void:
		var root := get_parent()
		if root != null and root.has_method("bind_player_skill_to_hotbar"):
			root.bind_player_skill_to_hotbar(bound_slot_id, "")
	, CONNECT_DEFERRED)
	row.add_child(line)
	row.add_child(learn_button)
	row.add_child(bind_button)
	row.add_child(use_button)
	row.add_child(clear_button)
	return row


func _get_skill_drag_data(_position: Vector2, from_control: Control) -> Variant:
	if from_control == null or not from_control.has_meta("skill_drag_data"):
		return null
	var skill: Dictionary = _dictionary_or_empty(from_control.get_meta("skill_drag_data"))
	var skill_id := str(skill.get("skill_id", ""))
	if skill_id.is_empty() or not bool(skill.get("can_bind", false)):
		return null
	_selected_skill_id = skill_id
	_apply_detail(skill)
	if get_viewport() != null and get_viewport().gui_is_dragging():
		var preview := Label.new()
		preview.text = "%s -> 热栏" % skill.get("name", skill_id)
		set_drag_preview(preview)
	return {
		"kind": "skill_hotbar",
		"skill_id": skill_id,
		"skill": skill.duplicate(true),
	}


func _empty_skill_drop_check(_position: Vector2, _data: Variant, _from_control: Control) -> bool:
	return false


func _empty_skill_drop(_position: Vector2, _data: Variant, _from_control: Control) -> void:
	pass


func has_blocking_modal() -> bool:
	return _learn_confirm_dialog != null and _learn_confirm_dialog.visible


func blocking_modal_name() -> String:
	if has_blocking_modal():
		return "skill_learn_confirm"
	return ""


func close_blocking_modal() -> Dictionary:
	if not has_blocking_modal():
		return {"success": false, "reason": "modal_inactive"}
	_learn_confirm_dialog.hide()
	_pending_learn_skill = {}
	return {
		"success": true,
		"closed": "modal:skill_learn_confirm",
	}


func _open_learn_confirm(skill: Dictionary) -> void:
	if _learn_confirm_dialog == null or skill.is_empty() or not bool(skill.get("can_learn", false)):
		return
	_pending_learn_skill = skill.duplicate(true)
	var skill_id := str(skill.get("skill_id", ""))
	var skill_name := str(skill.get("name", skill_id))
	var next_level := int(skill.get("level", 0)) + 1
	_learn_confirm_dialog.dialog_text = "学习 %s 到 %d 级会消耗 1 个技能点。确定学习吗？" % [
		skill_name,
		next_level,
	]
	_learn_confirm_dialog.popup_centered()


func _confirm_pending_learn() -> void:
	var skill_id := str(_pending_learn_skill.get("skill_id", ""))
	var skill_name := str(_pending_learn_skill.get("name", skill_id))
	var activation_mode := str(_pending_learn_skill.get("activation_mode", "passive"))
	_pending_learn_skill = {}
	if _learn_confirm_dialog != null:
		_learn_confirm_dialog.hide()
	if skill_id.is_empty():
		return
	var root := get_parent()
	if root != null and root.has_method("learn_player_skill"):
		var result: Dictionary = root.learn_player_skill(skill_id)
		if bool(result.get("success", false)):
			_selected_skill_id = skill_id
			_learn_feedback_text = _learn_feedback(skill_name, activation_mode)
			if not _last_snapshot.is_empty():
				apply_snapshot(_last_snapshot)


func _learn_feedback(skill_name: String, activation_mode: String) -> String:
	if activation_mode == "passive":
		return "已学习 %s。" % skill_name
	return "已学习 %s，可绑定到快捷栏。" % skill_name


func _apply_detail(skill: Dictionary) -> void:
	if _detail_title_label == null or _detail_body_label == null:
		return
	if skill.is_empty():
		_detail_title_label.text = "技能详情"
		_detail_body_label.text = "选择技能查看详情"
		return
	var skill_id := str(skill.get("skill_id", ""))
	_detail_title_label.text = "详情: %s %d/%d" % [
		skill.get("name", skill_id),
		int(skill.get("level", 0)),
		int(skill.get("max_level", 1)),
	]
	var lines: Array[String] = []
	var description := str(skill.get("description", ""))
	if not description.is_empty():
		lines.append(description)
	lines.append("技能树: %s | 类型: %s" % [
		_tree_name_for_id(str(skill.get("tree_id", ""))),
		_activation_label(str(skill.get("activation_mode", "passive"))),
	])
	lines.append("学习: %s" % _reason_text(skill))
	lines.append("前置: %s" % _prerequisites_text(skill.get("prerequisites", [])))
	lines.append("属性: %s" % _attribute_requirements_text(skill.get("attribute_requirements", {})))
	if str(skill.get("activation_mode", "passive")) != "passive":
		lines.append("激活: AP %.0f | 冷却 %.0fs | 绑定 %s | 使用 %s" % [
			float(skill.get("ap_cost", 1.0)),
			float(skill.get("cooldown", 0.0)),
			"无" if str(skill.get("bound_slot", "")).is_empty() else str(skill.get("bound_slot", "")),
			_use_state_text(skill),
		])
	_detail_body_label.text = "\n".join(lines)


func _reason_text(skill: Dictionary) -> String:
	match str(skill.get("learn_reason", "")):
		"available":
			return "可学习"
		"maxed":
			return "已满级"
		"missing_skill_points":
			return "缺技能点"
		"missing_prerequisites":
			var ids: Array[String] = []
			for item in skill.get("missing_prerequisites", []):
				var data: Dictionary = item
				ids.append(str(data.get("skill_id", "")))
			return "需前置 %s" % ", ".join(ids)
		"missing_attributes":
			var parts: Array[String] = []
			for item in skill.get("missing_attributes", []):
				var data: Dictionary = item
				parts.append("%s %d/%d" % [
					data.get("attribute", ""),
					int(data.get("current", 0)),
					int(data.get("required", 0)),
				])
			return "属性不足 %s" % ", ".join(parts)
	return str(skill.get("learn_reason", ""))


func _hotbar_text(hotbar: Dictionary) -> String:
	if hotbar.is_empty():
		return "快捷栏 空"
	var parts: Array[String] = []
	var slots: Array = hotbar.keys()
	slots.sort()
	for slot in slots:
		var slot_data: Dictionary = hotbar[slot]
		parts.append("%s:%s cd%.0f" % [
			slot,
			slot_data.get("skill_id", slot_data),
			float(slot_data.get("cooldown_remaining", 0.0)),
		])
	return "快捷栏 %s" % " | ".join(parts)


func _binding_text(skill: Dictionary) -> String:
	var slot_id: String = str(skill.get("bound_slot", ""))
	if slot_id.is_empty():
		return ""
	return " | %s" % slot_id


func _activation_cost_text(skill: Dictionary) -> String:
	if str(skill.get("activation_mode", "passive")) == "passive":
		return ""
	return " | AP %.0f" % float(skill.get("ap_cost", 1.0))


func _use_reason_text(skill: Dictionary) -> String:
	match str(skill.get("use_reason", "")):
		"available":
			return " | 可用"
		"cooldown":
			return " | 冷却 %.0fs" % float(skill.get("cooldown_remaining", 0.0))
		"unbound":
			return " | 未绑定"
		"passive", "not_learned", "":
			return ""
	return " | %s" % skill.get("use_reason", "")


func _use_state_text(skill: Dictionary) -> String:
	match str(skill.get("use_reason", "")):
		"available":
			return "可用"
		"cooldown":
			return "冷却 %.0fs" % float(skill.get("cooldown_remaining", 0.0))
		"unbound":
			return "未绑定"
		"not_learned":
			return "未学习"
		"passive":
			return "被动"
		"":
			return "无"
	return str(skill.get("use_reason", ""))


func _activation_label(mode: String) -> String:
	match mode:
		"active":
			return "主动"
		"toggle":
			return "切换"
	return "被动"


func _prerequisites_text(prerequisites: Array) -> String:
	var parts: Array[String] = []
	for prerequisite in prerequisites:
		var prerequisite_id := str(prerequisite)
		parts.append(_skill_name_for_id(prerequisite_id))
	return "无" if parts.is_empty() else ", ".join(parts)


func _attribute_requirements_text(requirements: Dictionary) -> String:
	var parts: Array[String] = []
	var keys: Array = requirements.keys()
	keys.sort()
	for key in keys:
		parts.append("%s %d" % [_attribute_label(str(key)), int(requirements.get(key, 0))])
	return "无" if parts.is_empty() else " / ".join(parts)


func _attribute_label(attribute: String) -> String:
	match attribute:
		"strength":
			return "力量"
		"agility":
			return "敏捷"
		"constitution":
			return "体质"
	return attribute


func _skill_name_for_id(skill_id: String) -> String:
	for tree in _last_snapshot.get("trees", []):
		var tree_data: Dictionary = tree
		for skill in tree_data.get("skills", []):
			var skill_data: Dictionary = skill
			if str(skill_data.get("skill_id", "")) == skill_id:
				return str(skill_data.get("name", skill_id))
	return skill_id


func _tree_name_for_id(tree_id: String) -> String:
	for tree in _last_snapshot.get("trees", []):
		var tree_data: Dictionary = tree
		if str(tree_data.get("tree_id", "")) == tree_id:
			return str(tree_data.get("name", tree_id))
	return tree_id


func _button(node_name: String, text: String, tooltip: String, disabled: bool) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(34, 28)
	button.disabled = disabled
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	return button


func _add_filter_button(node_name: String, text: String, mode: String) -> void:
	var button := _button(node_name, text, "筛选%s技能" % text, false)
	button.custom_minimum_size = Vector2(58, 28)
	button.toggle_mode = true
	button.button_pressed = _filter_mode == mode
	button.pressed.connect(func() -> void:
		_filter_mode = mode
		_refresh_filter_buttons()
		if not _last_snapshot.is_empty():
			apply_snapshot(_last_snapshot)
	, CONNECT_DEFERRED)
	_filter_box.add_child(button)


func _rebuild_tree_filter_buttons(snapshot: Dictionary) -> void:
	if _tree_filter_box == null:
		return
	var tree_ids: Array[String] = []
	for tree in snapshot.get("trees", []):
		var tree_data: Dictionary = tree
		var tree_id: String = str(tree_data.get("tree_id", ""))
		if not tree_id.is_empty():
			tree_ids.append(tree_id)
	if _tree_filter_mode != "all" and not tree_ids.has(_tree_filter_mode):
		_tree_filter_mode = "all"
	for child in _tree_filter_box.get_children():
		_tree_filter_box.remove_child(child)
		child.free()
	_add_tree_filter_button("TreeFilterAllButton", "全部树", "all")
	for tree in snapshot.get("trees", []):
		var tree_data: Dictionary = tree
		var tree_id: String = str(tree_data.get("tree_id", ""))
		if tree_id.is_empty():
			continue
		_add_tree_filter_button("TreeFilter_%s" % tree_id, str(tree_data.get("name", tree_id)), tree_id)


func _add_tree_filter_button(node_name: String, text: String, tree_id: String) -> void:
	var button := _button(node_name, text, "显示%s技能树" % text, false)
	button.custom_minimum_size = Vector2(74, 28)
	button.toggle_mode = true
	button.button_pressed = _tree_filter_mode == tree_id
	button.pressed.connect(func() -> void:
		_tree_filter_mode = tree_id
		if not _last_snapshot.is_empty():
			apply_snapshot(_last_snapshot)
	, CONNECT_DEFERRED)
	_tree_filter_box.add_child(button)


func _refresh_filter_buttons() -> void:
	if _filter_box == null:
		return
	for child in _filter_box.get_children():
		if child is Button:
			var button := child as Button
			match button.name:
				"FilterAllButton":
					button.button_pressed = _filter_mode == "all"
				"FilterLearnedButton":
					button.button_pressed = _filter_mode == "learned"
				"FilterAvailableButton":
					button.button_pressed = _filter_mode == "available"
				"FilterLockedButton":
					button.button_pressed = _filter_mode == "locked"
				"FilterActiveButton":
					button.button_pressed = _filter_mode == "active"


func _label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _clear_trees() -> void:
	for child in _tree_box.get_children():
		_tree_box.remove_child(child)
		child.free()


func _skill_by_id(skills: Array[Dictionary], skill_id: String) -> Dictionary:
	for skill in skills:
		var skill_data: Dictionary = skill
		if str(skill_data.get("skill_id", "")) == skill_id:
			return skill_data
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
