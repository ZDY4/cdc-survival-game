extends Control

const CONTEXT_INSPECT := 1
const CONTEXT_UNEQUIP := 2
const CONTEXT_RELOAD := 3

var _panel: PanelContainer
var _summary_label: Label
var _resource_label: Label
var _feedback_label: Label
var _derived_box: VBoxContainer
var _attributes_box: VBoxContainer
var _status_box: VBoxContainer
var _equipment_box: VBoxContainer
var _context_menu: PopupMenu
var _context_equipment: Dictionary = {}


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()


func apply_snapshot(snapshot: Dictionary) -> void:
	if _panel == null:
		_build_layout()

	var available_stat_points: int = int(snapshot.get("available_stat_points", 0))
	_summary_label.text = "%s Lv%d | XP %d | 属性点 %d | 技能点 %d" % [
		snapshot.get("owner_name", ""),
		int(snapshot.get("level", 1)),
		int(snapshot.get("current_xp", 0)),
		available_stat_points,
		int(snapshot.get("available_skill_points", 0)),
	]
	_resource_label.text = "HP %.0f/%.0f | AP %.1f" % [
		float(snapshot.get("hp", 0.0)),
		float(snapshot.get("max_hp", 0.0)),
		float(snapshot.get("ap", 0.0)),
	]
	_apply_feedback(_dictionary_or_empty(snapshot.get("feedback", {})))
	_clear_box(_derived_box)
	_clear_box(_attributes_box)
	_clear_box(_status_box)
	_clear_box(_equipment_box)
	for row in _derived_rows(_array_or_empty(snapshot.get("derived_stats", []))):
		_derived_box.add_child(row)
	for row in _attribute_rows(_dictionary_or_empty(snapshot.get("attributes", {})), available_stat_points):
		_attributes_box.add_child(row)
	for row in _status_rows(_array_or_empty(snapshot.get("status_effects", []))):
		_status_box.add_child(row)
	for row in _equipment_rows(_array_or_empty(snapshot.get("equipment", []))):
		_equipment_box.add_child(row)


func _build_layout() -> void:
	if _panel != null:
		return

	_panel = PanelContainer.new()
	_panel.name = "CharacterPanel"
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.offset_left = 16
	_panel.offset_right = 390
	_panel.offset_top = 16
	_panel.offset_bottom = 306
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "CharacterLines"
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	_summary_label = _label("SummaryLine")
	_resource_label = _label("ResourceLine")
	_feedback_label = _label("FeedbackLine")
	_derived_box = VBoxContainer.new()
	_derived_box.name = "DerivedStatLines"
	_derived_box.add_theme_constant_override("separation", 3)
	_attributes_box = VBoxContainer.new()
	_attributes_box.name = "AttributeLines"
	_attributes_box.add_theme_constant_override("separation", 3)
	_status_box = VBoxContainer.new()
	_status_box.name = "StatusEffectLines"
	_status_box.add_theme_constant_override("separation", 3)
	_equipment_box = VBoxContainer.new()
	_equipment_box.name = "EquipmentLines"
	_equipment_box.add_theme_constant_override("separation", 3)
	_context_menu = PopupMenu.new()
	_context_menu.name = "EquipmentContextMenu"
	_context_menu.id_pressed.connect(_execute_context_action)
	add_child(_context_menu)
	box.add_child(_summary_label)
	box.add_child(_resource_label)
	box.add_child(_feedback_label)
	box.add_child(_section_label("DerivedStatsTitle", "派生"))
	box.add_child(_derived_box)
	box.add_child(_section_label("AttributesTitle", "属性"))
	box.add_child(_attributes_box)
	box.add_child(_section_label("StatusEffectsTitle", "状态"))
	box.add_child(_status_box)
	box.add_child(_section_label("EquipmentTitle", "装备"))
	box.add_child(_equipment_box)


func _derived_rows(derived_stats: Array) -> Array[Control]:
	var rows: Array[Control] = []
	if derived_stats.is_empty():
		var empty := _label("DerivedStatEmpty")
		empty.text = "暂无派生数值"
		rows.append(empty)
		return rows
	for stat in derived_stats:
		var data: Dictionary = _dictionary_or_empty(stat)
		var stat_id: String = str(data.get("id", "unknown"))
		var label := _label("DerivedStat_%s" % stat_id)
		label.text = "%s: %s" % [
			str(data.get("label", stat_id)),
			str(data.get("value", "")),
		]
		label.tooltip_text = str(data.get("tooltip", ""))
		rows.append(label)
	return rows


func _attribute_rows(attributes: Dictionary, available_stat_points: int) -> Array[Control]:
	var rows: Array[Control] = []
	var keys: Array = attributes.keys()
	keys.sort()
	for key in keys:
		var attribute_id: String = str(key)
		var row := HBoxContainer.new()
		row.name = "Attribute_%s" % attribute_id
		row.custom_minimum_size = Vector2(322, 28)
		row.add_theme_constant_override("separation", 6)
		var label := _label("Line")
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s: %s" % [key, str(attributes.get(key, 0))]
		var add_button := _button("AllocateButton", "+", "分配 1 点到 %s" % attribute_id, available_stat_points <= 0)
		add_button.pressed.connect(func() -> void:
			var root := get_parent()
			if root != null and root.has_method("allocate_player_attribute_point"):
				root.allocate_player_attribute_point(attribute_id)
		, CONNECT_DEFERRED)
		row.add_child(label)
		row.add_child(add_button)
		rows.append(row)
	return rows


func _status_rows(status_effects: Array) -> Array[Control]:
	var rows: Array[Control] = []
	if status_effects.is_empty():
		var empty := _label("StatusEffectEmpty")
		empty.text = "无状态效果"
		rows.append(empty)
		return rows
	for effect in status_effects:
		var data: Dictionary = _dictionary_or_empty(effect)
		var row := HBoxContainer.new()
		row.name = "StatusEffect_%s" % str(data.get("effect_id", "unknown")).replace(":", "_")
		row.custom_minimum_size = Vector2(322, 28)
		row.add_theme_constant_override("separation", 6)
		var label := _label("Line")
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = _status_text(data)
		label.tooltip_text = str(data.get("tooltip", ""))
		_apply_status_visual(label, data)
		row.tooltip_text = label.tooltip_text
		row.set_meta("polarity", str(data.get("polarity", "")))
		row.set_meta("severity", str(data.get("severity", "")))
		row.set_meta("visual_tone", str(_dictionary_or_empty(data.get("visual_style", {})).get("tone", "")))
		row.add_child(label)
		rows.append(row)
	return rows


func _status_text(data: Dictionary) -> String:
	var visual_style: Dictionary = _dictionary_or_empty(data.get("visual_style", {}))
	var prefix := str(visual_style.get("prefix", ""))
	var parts: Array[String] = [
		str(data.get("name", data.get("effect_id", ""))),
		str(data.get("category", "")),
	]
	var source_label := str(data.get("source_label", ""))
	if not source_label.is_empty():
		parts.append(source_label)
	if int(data.get("level", 0)) > 0:
		parts.append("Lv%d" % int(data.get("level", 0)))
	if not bool(data.get("is_infinite", false)):
		parts.append("%.0f回合" % float(data.get("duration_remaining", 0.0)))
	var modifier_labels: Array[String] = []
	for label in _array_or_empty(data.get("modifier_labels", [])):
		var text: String = str(label)
		if not text.is_empty():
			modifier_labels.append(text)
	if not modifier_labels.is_empty():
		parts.append(" / ".join(modifier_labels))
	var text := " | ".join(parts)
	return "%s %s" % [prefix, text] if not prefix.is_empty() else text


func _apply_status_visual(label: Label, data: Dictionary) -> void:
	var visual_style: Dictionary = _dictionary_or_empty(data.get("visual_style", {}))
	var color_text := str(visual_style.get("font_color", ""))
	if color_text.is_empty():
		return
	var color := Color.html(color_text)
	label.add_theme_color_override("font_color", color)
	label.set_meta("status_font_color", color_text)
	label.set_meta("status_visual_tone", str(visual_style.get("tone", "")))


func _equipment_rows(equipment: Array) -> Array[Control]:
	var rows: Array[Control] = []
	if equipment.is_empty():
		var empty := _label("EquipmentEmpty")
		empty.text = "未装备"
		rows.append(empty)
		return rows
	for item in equipment:
		var data: Dictionary = _dictionary_or_empty(item)
		rows.append(_equipment_row(data))
	return rows


func _equipment_row(data: Dictionary) -> HBoxContainer:
	var slot_id: String = str(data.get("slot_id", "unknown"))
	var actual_slot_id: String = str(data.get("actual_slot_id", slot_id))
	var row := HBoxContainer.new()
	row.name = "Equipment_%s" % slot_id
	row.custom_minimum_size = Vector2(322, 28)
	row.add_theme_constant_override("separation", 6)
	row.set_meta("equipment_slot", actual_slot_id)
	row.set_meta("equipment_display_slot", slot_id)
	row.set_meta("equipment_data", data.duplicate(true))
	row.set_meta("equipment_drag_hovered", false)
	row.set_meta("equipment_drag_last_accept", false)
	row.set_meta("equipment_drag_reject_reason", "")
	row.set_drag_forwarding(
		Callable(self, "_empty_character_drag_data"),
		Callable(self, "_can_drop_equipment_data"),
		Callable(self, "_drop_equipment_data")
	)
	row.mouse_exited.connect(func() -> void:
		_clear_equipment_drag_hover(row)
	)
	row.tooltip_text = _equipment_tooltip(data)
	row.gui_input.connect(func(event: InputEvent) -> void:
		var mouse_event := event as InputEventMouseButton
		if mouse_event == null or not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_RIGHT:
			return
		row.accept_event()
		_open_context_menu_for_equipment(data.duplicate(true), row.get_global_mouse_position())
	)
	var label := _label("Line")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = _equipment_text(data)
	label.tooltip_text = row.tooltip_text
	label.gui_input.connect(func(event: InputEvent) -> void:
		var mouse_event := event as InputEventMouseButton
		if mouse_event == null or not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_RIGHT:
			return
		label.accept_event()
		_open_context_menu_for_equipment(data.duplicate(true), label.get_global_mouse_position())
	)
	row.add_child(label)
	var reload: Dictionary = _dictionary_or_empty(data.get("reload", {}))
	if bool(reload.get("reloadable", false)):
		var reload_button := _button("ReloadButton", "装", "装填 %s" % str(data.get("label", slot_id)), not bool(reload.get("can_reload", false)))
		reload_button.pressed.connect(func() -> void:
			var root := get_parent()
			if root != null and root.has_method("reload_player_equipped_slot"):
				root.reload_player_equipped_slot(actual_slot_id)
		, CONNECT_DEFERRED)
		row.add_child(reload_button)
	var unequip_button := _button("UnequipButton", "卸", "卸下 %s" % str(data.get("label", slot_id)), not bool(data.get("equipped", false)))
	unequip_button.pressed.connect(func() -> void:
		var root := get_parent()
		if root != null and root.has_method("unequip_player_slot"):
			root.unequip_player_slot(actual_slot_id)
	, CONNECT_DEFERRED)
	row.add_child(unequip_button)
	return row


func _open_context_menu_for_equipment(data: Dictionary, screen_position: Vector2) -> void:
	if _context_menu == null:
		return
	_context_equipment = data.duplicate(true)
	_context_menu.clear()
	_context_menu.add_item("检查", CONTEXT_INSPECT)
	_context_menu.add_item("卸下", CONTEXT_UNEQUIP)
	_context_menu.add_item("装填", CONTEXT_RELOAD)
	var reload: Dictionary = _dictionary_or_empty(data.get("reload", {}))
	var equipped := bool(data.get("equipped", false))
	var reloadable := bool(reload.get("reloadable", false))
	var can_reload := reloadable and bool(reload.get("can_reload", false))
	_context_menu.set_item_disabled(_context_menu.get_item_index(CONTEXT_UNEQUIP), not equipped)
	_context_menu.set_item_disabled(_context_menu.get_item_index(CONTEXT_RELOAD), not can_reload)
	_context_menu.set_item_tooltip(_context_menu.get_item_index(CONTEXT_INSPECT), "查看装备详情")
	_context_menu.set_item_tooltip(_context_menu.get_item_index(CONTEXT_UNEQUIP), "卸下到背包" if equipped else "该槽位为空")
	_context_menu.set_item_tooltip(_context_menu.get_item_index(CONTEXT_RELOAD), _reload_context_tooltip(reload))
	var popup_position := Vector2i(int(screen_position.x), int(screen_position.y))
	_context_menu.popup(Rect2i(popup_position, Vector2i(180, 1)))


func context_menu_snapshot() -> Dictionary:
	if _context_menu == null or not _context_menu.visible:
		return {}
	var slot_id := str(_context_equipment.get("actual_slot_id", _context_equipment.get("slot_id", "")))
	var display_slot := str(_context_equipment.get("slot_id", slot_id))
	var reload: Dictionary = _dictionary_or_empty(_context_equipment.get("reload", {}))
	return {
		"id": "equipment_context_menu",
		"name": "equipment_context_menu",
		"kind": "equipment_slot",
		"owner_panel": "character",
		"active": true,
		"visible": true,
		"mouse_blocks_world": true,
		"slot_id": slot_id,
		"display_slot": display_slot,
		"item_id": str(_context_equipment.get("item_id", "")),
		"item_name": str(_context_equipment.get("name", _context_equipment.get("item_id", ""))),
		"equipped": bool(_context_equipment.get("equipped", false)),
		"reloadable": bool(reload.get("reloadable", false)),
		"can_reload": bool(reload.get("can_reload", false)),
		"option_count": _context_menu.item_count,
		"options": _equipment_context_option_summaries(),
	}


func close_context_menu() -> void:
	if _context_menu != null:
		_context_menu.hide()
	_context_equipment = {}


func _equipment_context_option_summaries() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if _context_menu == null:
		return output
	for index in range(_context_menu.item_count):
		output.append({
			"id": _context_menu.get_item_id(index),
			"label": _context_menu.get_item_text(index),
			"disabled": _context_menu.is_item_disabled(index),
			"tooltip": _context_menu.get_item_tooltip(index),
		})
	return output


func _execute_context_action(action_id: int) -> void:
	if _context_equipment.is_empty():
		return
	var slot_id := str(_context_equipment.get("actual_slot_id", _context_equipment.get("slot_id", "")))
	if action_id == CONTEXT_INSPECT:
		_apply_equipment_inspect_feedback(_context_equipment)
		return
	var root := get_parent()
	if root == null or slot_id.is_empty():
		close_context_menu()
		return
	match action_id:
		CONTEXT_UNEQUIP:
			if bool(_context_equipment.get("equipped", false)) and root.has_method("unequip_player_slot"):
				root.unequip_player_slot(slot_id)
		CONTEXT_RELOAD:
			var reload: Dictionary = _dictionary_or_empty(_context_equipment.get("reload", {}))
			if bool(reload.get("reloadable", false)) and bool(reload.get("can_reload", false)) and root.has_method("reload_player_equipped_slot"):
				root.reload_player_equipped_slot(slot_id)
	close_context_menu()


func _apply_equipment_inspect_feedback(data: Dictionary) -> void:
	if _feedback_label == null:
		return
	var slot_label := str(data.get("label", data.get("slot_id", "")))
	if not bool(data.get("equipped", false)):
		_feedback_label.text = "检查：%s为空" % slot_label
	else:
		_feedback_label.text = "检查：%s - %s" % [
			slot_label,
			str(data.get("name", data.get("item_id", ""))),
		]
	_feedback_label.tooltip_text = _equipment_tooltip(data)
	_feedback_label.visible = true


func _reload_context_tooltip(reload: Dictionary) -> String:
	if not bool(reload.get("reloadable", false)):
		return "该装备无需装填"
	if bool(reload.get("can_reload", false)):
		return "消耗备用弹药装填"
	if int(reload.get("inventory_ammo", 0)) <= 0:
		return "背包中没有可用弹药"
	return "弹匣已满或暂不可装填"


func _empty_character_drag_data(_position: Vector2, _from_control: Control) -> Variant:
	return null


func _can_drop_equipment_data(_position: Vector2, data: Variant, from_control: Control) -> bool:
	var drag_data: Dictionary = _dictionary_or_empty(data)
	if str(drag_data.get("kind", "")) != "inventory_item":
		_apply_equipment_drag_hover(from_control, false, "equipment_slot_requires_inventory_item")
		return false
	var item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
	var item_id: String = str(drag_data.get("item_id", item.get("item_id", "")))
	var slot_id: String = _drop_equipment_slot(from_control)
	if item_id.is_empty() or slot_id.is_empty():
		_apply_equipment_drag_hover(from_control, false, "equipment_slot_missing_item" if item_id.is_empty() else "equipment_slot_missing_slot")
		return false
	var accepted := _item_can_equip_to_slot(item, slot_id)
	_apply_equipment_drag_hover(from_control, accepted, "" if accepted else "equipment_slot_incompatible")
	return accepted


func _drop_equipment_data(position: Vector2, data: Variant, from_control: Control) -> void:
	if not _can_drop_equipment_data(position, data, from_control):
		return
	var drag_data: Dictionary = _dictionary_or_empty(data)
	var item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
	var item_id: String = str(drag_data.get("item_id", item.get("item_id", "")))
	var slot_id: String = _drop_equipment_slot(from_control)
	var root := get_parent()
	_clear_equipment_drag_hover(from_control)
	if root != null and root.has_method("equip_player_item"):
		root.equip_player_item(item_id, slot_id)


func _apply_equipment_drag_hover(control: Control, accepted: bool, reject_reason: String) -> void:
	if control == null or not is_instance_valid(control) or not control.has_meta("equipment_slot"):
		return
	var color_text := "#4ecb71" if accepted else "#e25c5c"
	var style := "accept" if accepted else "reject"
	control.set_meta("equipment_drag_hovered", true)
	control.set_meta("equipment_drag_last_accept", accepted)
	control.set_meta("equipment_drag_reject_reason", reject_reason)
	control.set_meta("equipment_drag_highlight_style", style)
	control.set_meta("equipment_drag_highlight_color", color_text)
	control.modulate = Color(0.90, 1.0, 0.92, 1.0) if accepted else Color(1.0, 0.90, 0.90, 1.0)
	var label := control.get_node_or_null("Line") as Label
	if label != null:
		label.add_theme_color_override("font_color", Color.html(color_text))
		label.set_meta("equipment_drag_highlight_style", style)
		label.set_meta("equipment_drag_highlight_color", color_text)


func _clear_equipment_drag_hover(control: Control) -> void:
	if control == null or not is_instance_valid(control) or not control.has_meta("equipment_slot"):
		return
	control.set_meta("equipment_drag_hovered", false)
	control.set_meta("equipment_drag_last_accept", false)
	control.set_meta("equipment_drag_reject_reason", "")
	control.set_meta("equipment_drag_highlight_style", "")
	control.set_meta("equipment_drag_highlight_color", "")
	control.modulate = Color.WHITE
	var label := control.get_node_or_null("Line") as Label
	if label != null:
		label.remove_theme_color_override("font_color")
		label.set_meta("equipment_drag_highlight_style", "")
		label.set_meta("equipment_drag_highlight_color", "")


func _drop_equipment_slot(from_control: Control) -> String:
	if from_control != null and from_control.has_meta("equipment_slot"):
		return str(from_control.get_meta("equipment_slot"))
	return ""


func _item_can_equip_to_slot(item: Dictionary, slot_id: String) -> bool:
	for candidate in _array_or_empty(item.get("equip_slots", [])):
		if str(candidate) == slot_id:
			return true
	return false


func _equipment_text(data: Dictionary) -> String:
	var label: String = str(data.get("label", data.get("slot_id", "")))
	if not bool(data.get("equipped", false)):
		return "%s: 空%s" % [label, _equipment_comparison_suffix(data)]
	var rarity := str(data.get("rarity", ""))
	var rarity_suffix := " | %s" % rarity if not rarity.is_empty() else ""
	return "%s: %s | %.1f kg | 价值 %d%s" % [
		label,
		data.get("name", data.get("item_id", "")),
		float(data.get("weight", 0.0)),
		int(data.get("value", 0)),
		rarity_suffix,
	] + _equipment_detail_suffix(data) + _equipment_comparison_suffix(data)


func _equipment_detail_suffix(data: Dictionary) -> String:
	var details: Array[String] = []
	for detail in _array_or_empty(data.get("details", [])):
		var text: String = str(detail)
		if not text.is_empty():
			details.append(text)
	return "" if details.is_empty() else " | %s" % " | ".join(details)


func _equipment_comparison_suffix(data: Dictionary) -> String:
	var comparison: Dictionary = _dictionary_or_empty(data.get("comparison", {}))
	if not bool(comparison.get("has_candidates", false)):
		return ""
	var summary := str(comparison.get("summary", ""))
	return "" if summary.is_empty() else " | 替换: %s" % summary


func _equipment_tooltip(data: Dictionary) -> String:
	var label: String = str(data.get("label", data.get("slot_id", "")))
	if not bool(data.get("equipped", false)):
		return "%s: 空\n可将适用装备拖到此槽位。" % label
	var lines: Array[String] = [
		"%s: %s" % [label, str(data.get("name", data.get("item_id", "")))],
		"重量 %.1f kg | 价值 %d" % [float(data.get("weight", 0.0)), int(data.get("value", 0))],
	]
	var rarity := str(data.get("rarity", ""))
	if not rarity.is_empty():
		lines.append("稀有度: %s" % rarity)
	var description := str(data.get("description", ""))
	if not description.is_empty():
		lines.append(description)
	for detail in _array_or_empty(data.get("details", [])):
		var text := str(detail)
		if not text.is_empty():
			lines.append(text)
	var comparison: Dictionary = _dictionary_or_empty(data.get("comparison", {}))
	if bool(comparison.get("has_candidates", false)):
		lines.append("装备对比: %s" % str(comparison.get("summary", "")))
		var candidates: Array = _array_or_empty(comparison.get("candidates", []))
		var limit: int = mini(candidates.size(), 3)
		for index in range(limit):
			var candidate: Dictionary = _dictionary_or_empty(candidates[index])
			var labels: Array[String] = []
			for delta_label in _array_or_empty(candidate.get("delta_labels", [])):
				var delta_text := str(delta_label)
				if not delta_text.is_empty():
					labels.append(delta_text)
			lines.append("- %s: %s" % [
				str(candidate.get("name", candidate.get("item_id", ""))),
				"无属性变化" if labels.is_empty() else " / ".join(labels),
			])
	var effects: Array[String] = []
	for effect in _array_or_empty(data.get("effects", [])):
		var effect_text := str(effect)
		if not effect_text.is_empty():
			effects.append(effect_text)
	if not effects.is_empty():
		lines.append("装备效果: %s" % " / ".join(effects))
	var reload: Dictionary = _dictionary_or_empty(data.get("reload", {}))
	if bool(reload.get("reloadable", false)):
		lines.append("装填: %d/%d，备用 %d，AP %.1f%s" % [
			int(reload.get("loaded", 0)),
			int(reload.get("capacity", 0)),
			int(reload.get("inventory_ammo", 0)),
			float(reload.get("ap_cost", 0.0)),
			"，可装填" if bool(reload.get("can_reload", false)) else "，暂不可装填",
		])
	return "\n".join(lines)


func _apply_feedback(feedback: Dictionary) -> void:
	if _feedback_label == null:
		return
	var message := str(feedback.get("message", ""))
	_feedback_label.text = message
	_feedback_label.visible = not message.is_empty()


func _section_label(node_name: String, text: String) -> Label:
	var label := _label(node_name)
	label.text = text
	return label


func _label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(node_name: String, text: String, tooltip: String, disabled: bool) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(34, 28)
	button.disabled = disabled
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	return button


func _clear_box(box: VBoxContainer) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.free()


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
