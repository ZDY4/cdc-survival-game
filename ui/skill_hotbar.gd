extends Control

class_name SkillHotbar

const SkillHotbarSlot = preload("res://ui/skill_hotbar_slot.gd")

signal status_requested(message: String)

var _skill_system: Node = null
var _group_label: Label = null
var _slot_container: HBoxContainer = null
var _slots: Array[SkillHotbarSlot] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_resolve_skill_system()
	set_process(true)
	_refresh_from_skill_system()


func _process(_delta: float) -> void:
	if _skill_system == null:
		_resolve_skill_system()
	_refresh_from_skill_system()


func add_skill_to_active_group(skill_id: String) -> void:
	if skill_id.is_empty():
		return
	if _skill_system == null:
		status_requested.emit("技能系统不可用")
		return
	if not bool(_skill_system.is_hotbar_eligible(skill_id)):
		status_requested.emit("该技能当前不能加入快捷栏")
		return

	var group_index: int = int(_skill_system.get_active_hotbar_group())
	var groups: Array = _skill_system.get_hotbar_groups()
	if group_index < 0 or group_index >= groups.size():
		status_requested.emit("当前快捷栏组无效")
		return

	var slots: Array = groups[group_index]
	for slot_index in range(slots.size()):
		if str(slots[slot_index]) == skill_id:
			_highlight_slot(slot_index)
			status_requested.emit("该技能已在当前快捷栏")
			return

	for slot_index in range(slots.size()):
		if str(slots[slot_index]).is_empty():
			var result: Dictionary = _skill_system.assign_skill_to_hotbar(skill_id, group_index, slot_index)
			status_requested.emit(_result_message(result, "已添加到快捷栏"))
			_refresh_from_skill_system()
			return

	status_requested.emit("当前快捷栏组已满")


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 70.0
	offset_right = -70.0
	offset_top = -88.0
	offset_bottom = -18.0

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.11, 0.86)
	style.border_color = Color(0.29, 0.37, 0.43, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 10.0
	root.offset_top = 8.0
	root.offset_right = -10.0
	root.offset_bottom = -8.0
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 6)
	panel.add_child(root)

	var prev_button := Button.new()
	prev_button.text = "▲"
	prev_button.tooltip_text = "上一组快捷栏"
	prev_button.custom_minimum_size = Vector2(30, 48)
	prev_button.pressed.connect(_on_previous_group_pressed)
	root.add_child(prev_button)

	_group_label = Label.new()
	_group_label.custom_minimum_size = Vector2(52, 0)
	_group_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_group_label)

	_slot_container = HBoxContainer.new()
	_slot_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_slot_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_container.add_theme_constant_override("separation", 5)
	root.add_child(_slot_container)

	for slot_index in range(10):
		var slot := SkillHotbarSlot.new()
		slot.slot_index = slot_index
		slot.drop_requested.connect(_on_slot_drop_requested)
		slot.drag_cleared.connect(_on_slot_drag_cleared)
		_slot_container.add_child(slot)
		_slots.append(slot)

	var next_button := Button.new()
	next_button.text = "▼"
	next_button.tooltip_text = "下一组快捷栏"
	next_button.custom_minimum_size = Vector2(30, 48)
	next_button.pressed.connect(_on_next_group_pressed)
	root.add_child(next_button)


func _resolve_skill_system() -> void:
	if _skill_system != null:
		return
	_skill_system = get_node_or_null("/root/SkillSystem")
	if _skill_system == null:
		return
	if not _skill_system.hotbar_changed.is_connected(_on_hotbar_changed):
		_skill_system.hotbar_changed.connect(_on_hotbar_changed)
	if not _skill_system.hotbar_group_changed.is_connected(_on_hotbar_group_changed):
		_skill_system.hotbar_group_changed.connect(_on_hotbar_group_changed)
	if not _skill_system.skill_activation_failed.is_connected(_on_skill_activation_failed):
		_skill_system.skill_activation_failed.connect(_on_skill_activation_failed)
	if not _skill_system.skill_activation_succeeded.is_connected(_on_skill_activation_succeeded):
		_skill_system.skill_activation_succeeded.connect(_on_skill_activation_succeeded)
	if not _skill_system.skill_toggle_changed.is_connected(_on_skill_toggle_changed):
		_skill_system.skill_toggle_changed.connect(_on_skill_toggle_changed)


func _refresh_from_skill_system() -> void:
	if _group_label == null:
		return
	if _skill_system == null:
		_group_label.text = "-/-"
		for slot in _slots:
			slot.configure({
				"group_index": 0,
				"slot_index": slot.slot_index,
				"skill_id": "",
				"skill_data": {}
			})
		return

	var groups: Array = _skill_system.get_hotbar_groups()
	var group_index: int = int(_skill_system.get_active_hotbar_group())
	_group_label.text = "%d/5" % [group_index + 1]

	var active_group: Array = []
	if group_index >= 0 and group_index < groups.size():
		active_group = groups[group_index]

	for slot_index in range(_slots.size()):
		var skill_id: String = ""
		if slot_index < active_group.size():
			skill_id = str(active_group[slot_index])
		var skill_data: Dictionary = {}
		if not skill_id.is_empty():
			skill_data = _skill_system.get_skill(skill_id)
		_slots[slot_index].configure({
			"group_index": group_index,
			"slot_index": slot_index,
			"skill_id": skill_id,
			"skill_data": skill_data
		})


func _on_previous_group_pressed() -> void:
	if _skill_system == null:
		return
	_skill_system.cycle_hotbar_group(-1)
	_refresh_from_skill_system()


func _on_next_group_pressed() -> void:
	if _skill_system == null:
		return
	_skill_system.cycle_hotbar_group(1)
	_refresh_from_skill_system()


func _on_slot_drop_requested(slot_index: int, data: Dictionary) -> void:
	if _skill_system == null:
		return
	var current_group: int = int(_skill_system.get_active_hotbar_group())
	var payload_type: String = str(data.get("type", ""))
	var result: Dictionary = {}

	match payload_type:
		"skill_panel_item":
			result = _skill_system.assign_skill_to_hotbar(
				str(data.get("skill_id", "")),
				current_group,
				slot_index
			)
		"hotbar_skill":
			var source_group: int = int(data.get("group_index", current_group))
			var source_slot: int = int(data.get("slot_index", -1))
			if source_group == current_group:
				result = _skill_system.move_hotbar_skill(current_group, source_slot, slot_index)
			else:
				result = _skill_system.assign_skill_to_hotbar(
					str(data.get("skill_id", "")),
					current_group,
					slot_index
				)
				if bool(result.get("success", false)):
					_skill_system.clear_hotbar_slot(source_group, source_slot)
		_:
			return

	status_requested.emit(_result_message(result, "快捷栏已更新"))
	_refresh_from_skill_system()


func _on_slot_drag_cleared(group_index: int, slot_index: int) -> void:
	if _skill_system == null:
		return
	_skill_system.clear_hotbar_slot(group_index, slot_index)
	_refresh_from_skill_system()


func _on_hotbar_changed(_group_index: int, _slots_data: Array) -> void:
	_refresh_from_skill_system()


func _on_hotbar_group_changed(_group_index: int) -> void:
	_refresh_from_skill_system()


func _on_skill_activation_failed(_skill_id: String, reason: String) -> void:
	if not reason.is_empty():
		status_requested.emit(reason)


func _on_skill_activation_succeeded(skill_id: String, result: Dictionary) -> void:
	var skill_name: String = skill_id
	if _skill_system != null:
		var skill: Dictionary = _skill_system.get_skill(skill_id)
		skill_name = str(skill.get("name", skill_id))
	var action_label: String = "已触发"
	if result.get("mode", "") == "toggle":
		action_label = "已开启" if bool(result.get("active", false)) else "已关闭"
	status_requested.emit("%s%s" % [skill_name, action_label])
	_refresh_from_skill_system()


func _on_skill_toggle_changed(_skill_id: String, _active: bool) -> void:
	_refresh_from_skill_system()


func _highlight_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	_slots[slot_index].pulse_highlight()


func _result_message(result: Dictionary, fallback: String) -> String:
	if bool(result.get("success", false)):
		return fallback
	return str(result.get("reason", fallback))
