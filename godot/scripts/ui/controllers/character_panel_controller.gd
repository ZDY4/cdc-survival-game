extends Control

var _panel: PanelContainer
var _summary_label: Label
var _resource_label: Label
var _feedback_label: Label
var _attributes_box: VBoxContainer
var _status_box: VBoxContainer
var _equipment_box: VBoxContainer


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
	_clear_box(_attributes_box)
	_clear_box(_status_box)
	_clear_box(_equipment_box)
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
	_attributes_box = VBoxContainer.new()
	_attributes_box.name = "AttributeLines"
	_attributes_box.add_theme_constant_override("separation", 3)
	_status_box = VBoxContainer.new()
	_status_box.name = "StatusEffectLines"
	_status_box.add_theme_constant_override("separation", 3)
	_equipment_box = VBoxContainer.new()
	_equipment_box.name = "EquipmentLines"
	_equipment_box.add_theme_constant_override("separation", 3)
	box.add_child(_summary_label)
	box.add_child(_resource_label)
	box.add_child(_feedback_label)
	box.add_child(_section_label("AttributesTitle", "属性"))
	box.add_child(_attributes_box)
	box.add_child(_section_label("StatusEffectsTitle", "状态"))
	box.add_child(_status_box)
	box.add_child(_section_label("EquipmentTitle", "装备"))
	box.add_child(_equipment_box)


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
		row.add_child(label)
		rows.append(row)
	return rows


func _status_text(data: Dictionary) -> String:
	var parts: Array[String] = [
		str(data.get("name", data.get("effect_id", ""))),
		str(data.get("category", "")),
	]
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
	return " | ".join(parts)


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
	var label := _label("Line")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = _equipment_text(data)
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


func _equipment_text(data: Dictionary) -> String:
	var label: String = str(data.get("label", data.get("slot_id", "")))
	if not bool(data.get("equipped", false)):
		return "%s: 空" % label
	var rarity := str(data.get("rarity", ""))
	var rarity_suffix := " | %s" % rarity if not rarity.is_empty() else ""
	return "%s: %s | %.1f kg | 价值 %d%s" % [
		label,
		data.get("name", data.get("item_id", "")),
		float(data.get("weight", 0.0)),
		int(data.get("value", 0)),
		rarity_suffix,
	] + _equipment_detail_suffix(data)


func _equipment_detail_suffix(data: Dictionary) -> String:
	var details: Array[String] = []
	for detail in _array_or_empty(data.get("details", [])):
		var text: String = str(detail)
		if not text.is_empty():
			details.append(text)
	return "" if details.is_empty() else " | %s" % " | ".join(details)


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
