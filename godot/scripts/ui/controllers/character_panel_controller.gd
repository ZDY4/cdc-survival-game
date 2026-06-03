extends Control

var _panel: PanelContainer
var _summary_label: Label
var _resource_label: Label
var _attributes_box: VBoxContainer
var _equipment_box: VBoxContainer


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()


func apply_snapshot(snapshot: Dictionary) -> void:
	if _panel == null:
		_build_layout()

	_summary_label.text = "%s Lv%d | XP %d | 属性点 %d | 技能点 %d" % [
		snapshot.get("owner_name", ""),
		int(snapshot.get("level", 1)),
		int(snapshot.get("current_xp", 0)),
		int(snapshot.get("available_stat_points", 0)),
		int(snapshot.get("available_skill_points", 0)),
	]
	_resource_label.text = "HP %.0f/%.0f | AP %.1f" % [
		float(snapshot.get("hp", 0.0)),
		float(snapshot.get("max_hp", 0.0)),
		float(snapshot.get("ap", 0.0)),
	]
	_clear_box(_attributes_box)
	_clear_box(_equipment_box)
	for row in _attribute_rows(_dictionary_or_empty(snapshot.get("attributes", {}))):
		_attributes_box.add_child(row)
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
	_attributes_box = VBoxContainer.new()
	_attributes_box.name = "AttributeLines"
	_attributes_box.add_theme_constant_override("separation", 3)
	_equipment_box = VBoxContainer.new()
	_equipment_box.name = "EquipmentLines"
	_equipment_box.add_theme_constant_override("separation", 3)
	box.add_child(_summary_label)
	box.add_child(_resource_label)
	box.add_child(_section_label("AttributesTitle", "属性"))
	box.add_child(_attributes_box)
	box.add_child(_section_label("EquipmentTitle", "装备"))
	box.add_child(_equipment_box)


func _attribute_rows(attributes: Dictionary) -> Array[Label]:
	var rows: Array[Label] = []
	var keys: Array = attributes.keys()
	keys.sort()
	for key in keys:
		var label := _label("Attribute_%s" % key)
		label.text = "%s: %s" % [key, str(attributes.get(key, 0))]
		rows.append(label)
	return rows


func _equipment_rows(equipment: Array) -> Array[Label]:
	var rows: Array[Label] = []
	if equipment.is_empty():
		var empty := _label("EquipmentEmpty")
		empty.text = "未装备"
		rows.append(empty)
		return rows
	for item in equipment:
		var data: Dictionary = _dictionary_or_empty(item)
		var label := _label("Equipment_%s" % data.get("slot_id", "unknown"))
		label.text = "%s: %s" % [data.get("slot_id", ""), data.get("name", data.get("item_id", ""))]
		rows.append(label)
	return rows


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
