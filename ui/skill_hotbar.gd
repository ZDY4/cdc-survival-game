extends Control

class_name SkillHotbar

const ValueUtils = preload("res://core/value_utils.gd")

signal status_requested(message: String)

const SLOT_COUNT: int = 10
const HOTBAR_GROUP_COUNT: int = 5
const HORIZONTAL_MARGIN: float = 16.0
const PANEL_HORIZONTAL_PADDING: float = 10.0
const PANEL_VERTICAL_PADDING: float = 8.0
const ROOT_SEPARATION: int = 6
const SLOT_SEPARATION: int = 5
const NAV_BUTTON_WIDTH: float = 36.0
const GROUP_LABEL_WIDTH: float = 52.0
const MIN_SLOT_SIZE: float = 36.0
const MAX_SLOT_SIZE: float = 64.0

var _skill_system: Node = null
var _panel: PanelContainer = null
var _root: HBoxContainer = null
var _group_label: Label = null
var _slot_container: HBoxContainer = null
var _previous_button: Button = null
var _next_button: Button = null
var _slots: Array[SkillHotbarSlot] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_connect_viewport_resize()
	_update_layout()
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

	var group_index: int = ValueUtils.to_int(_skill_system.get_active_hotbar_group())
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
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_root = HBoxContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_theme_constant_override("separation", ROOT_SEPARATION)
	_panel.add_child(_root)

	_previous_button = Button.new()
	_previous_button.text = "▲"
	_previous_button.tooltip_text = "上一组快捷栏"
	_previous_button.pressed.connect(_on_previous_group_pressed)
	_root.add_child(_previous_button)

	_group_label = Label.new()
	_group_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_group_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(_group_label)

	_slot_container = HBoxContainer.new()
	_slot_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_slot_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_container.add_theme_constant_override("separation", SLOT_SEPARATION)
	_root.add_child(_slot_container)

	for slot_index in range(SLOT_COUNT):
		var slot := SkillHotbarSlot.new()
		slot.slot_index = slot_index
		slot.drop_requested.connect(_on_slot_drop_requested)
		slot.drag_cleared.connect(_on_slot_drag_cleared)
		_slot_container.add_child(slot)
		_slots.append(slot)

	_next_button = Button.new()
	_next_button.text = "▼"
	_next_button.tooltip_text = "下一组快捷栏"
	_next_button.pressed.connect(_on_next_group_pressed)
	_root.add_child(_next_button)


func _connect_viewport_resize() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	if not viewport.size_changed.is_connected(_on_viewport_size_changed):
		viewport.size_changed.connect(_on_viewport_size_changed)


func _update_layout() -> void:
	if _root == null or _slot_container == null:
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	var reserved_width: float = (
		HORIZONTAL_MARGIN * 2.0
		+ PANEL_HORIZONTAL_PADDING * 2.0
		+ NAV_BUTTON_WIDTH * 2.0
		+ GROUP_LABEL_WIDTH
		+ float(ROOT_SEPARATION * 3)
		+ float(SLOT_SEPARATION * max(SLOT_COUNT - 1, 0))
	)
	var available_slot_width: float = maxf(0.0, viewport_size.x - reserved_width)
	var slot_size: float = clampf(
		floorf(available_slot_width / maxf(1.0, float(SLOT_COUNT))),
		MIN_SLOT_SIZE,
		MAX_SLOT_SIZE
	)
	var hotbar_height: float = slot_size + PANEL_VERTICAL_PADDING * 2.0

	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = HORIZONTAL_MARGIN
	offset_right = -HORIZONTAL_MARGIN
	offset_top = -hotbar_height
	offset_bottom = 0.0

	_root.offset_left = PANEL_HORIZONTAL_PADDING
	_root.offset_top = PANEL_VERTICAL_PADDING
	_root.offset_right = -PANEL_HORIZONTAL_PADDING
	_root.offset_bottom = -PANEL_VERTICAL_PADDING

	if _previous_button != null:
		_previous_button.custom_minimum_size = Vector2(NAV_BUTTON_WIDTH, slot_size)
	if _next_button != null:
		_next_button.custom_minimum_size = Vector2(NAV_BUTTON_WIDTH, slot_size)
	if _group_label != null:
		_group_label.custom_minimum_size = Vector2(GROUP_LABEL_WIDTH, slot_size)

	for slot in _slots:
		slot.set_slot_size(slot_size)


func _on_viewport_size_changed() -> void:
	_update_layout()


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
	var group_index: int = ValueUtils.to_int(_skill_system.get_active_hotbar_group())
	_group_label.text = "%d/%d" % [group_index + 1, HOTBAR_GROUP_COUNT]

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
	var current_group: int = ValueUtils.to_int(_skill_system.get_active_hotbar_group())
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
			var source_group: int = ValueUtils.to_int(data.get("group_index", current_group), current_group)
			var source_slot: int = ValueUtils.to_int(data.get("slot_index", -1), -1)
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
