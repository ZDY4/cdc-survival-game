extends Control

var _panel: PanelContainer
var _summary_label: Label
var _hotbar_label: Label
var _tree_box: VBoxContainer


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()


func apply_snapshot(snapshot: Dictionary) -> void:
	if _panel == null:
		_build_layout()

	_summary_label.text = "%s Lv%d | 技能点 %d" % [
		snapshot.get("owner_name", ""),
		int(snapshot.get("level", 1)),
		int(snapshot.get("available_skill_points", 0)),
	]
	_hotbar_label.text = _hotbar_text(snapshot.get("hotbar", {}))
	_clear_trees()
	for tree in snapshot.get("trees", []):
		var tree_data: Dictionary = tree
		_tree_box.add_child(_tree_title(tree_data))
		for skill in tree_data.get("skills", []):
			var skill_data: Dictionary = skill
			_tree_box.add_child(_skill_row(skill_data))


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
	_tree_box = VBoxContainer.new()
	_tree_box.name = "TreeLines"
	_tree_box.add_theme_constant_override("separation", 4)
	box.add_child(_summary_label)
	box.add_child(_hotbar_label)
	box.add_child(_tree_box)


func _tree_title(tree: Dictionary) -> Label:
	var label := _label("Tree_%s" % tree.get("tree_id", "unknown"))
	label.text = "%s | %d 技能" % [
		tree.get("name", tree.get("tree_id", "")),
		tree.get("skills", []).size(),
	]
	return label


func _skill_row(skill: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Skill_%s" % skill.get("skill_id", "unknown")
	row.custom_minimum_size = Vector2(392, 28)
	row.add_theme_constant_override("separation", 6)
	var line := _label("Line")
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.text = "%s %d/%d | %s | %s" % [
		skill.get("name", skill.get("skill_id", "")),
		int(skill.get("level", 0)),
		int(skill.get("max_level", 1)),
		skill.get("activation_mode", "passive"),
		"%s%s" % [_reason_text(skill), _binding_text(skill)],
	]
	var skill_id := str(skill.get("skill_id", ""))
	var learn_button := _button("LearnButton", "+", "学习 %s" % skill.get("name", skill_id), not bool(skill.get("can_learn", false)))
	learn_button.pressed.connect(func() -> void:
		var root := get_parent()
		if root != null and root.has_method("learn_player_skill"):
			root.learn_player_skill(skill_id)
	, CONNECT_DEFERRED)
	var bind_button := _button("BindButton", "B", "绑定 %s 到快捷栏 1" % skill.get("name", skill_id), not bool(skill.get("can_bind", false)))
	bind_button.pressed.connect(func() -> void:
		var root := get_parent()
		if root != null and root.has_method("bind_player_skill_to_hotbar"):
			root.bind_player_skill_to_hotbar("slot_1", skill_id)
	, CONNECT_DEFERRED)
	var use_button := _button("UseButton", "U", "使用 %s" % skill.get("name", skill_id), not bool(skill.get("can_use", false)))
	use_button.pressed.connect(func() -> void:
		var root := get_parent()
		if root != null and root.has_method("use_hotbar_slot"):
			root.use_hotbar_slot(str(skill.get("bound_slot", "")))
	, CONNECT_DEFERRED)
	row.add_child(line)
	row.add_child(learn_button)
	row.add_child(bind_button)
	row.add_child(use_button)
	return row


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


func _button(node_name: String, text: String, tooltip: String, disabled: bool) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(34, 28)
	button.disabled = disabled
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	return button


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
