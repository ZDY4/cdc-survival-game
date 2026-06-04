extends Control

var _panel: PanelContainer
var _summary_label: Label
var _counts_label: Label
var _entry_label: Label
var _locations_label: Label
var _tracked_quest_label: Label
var _kinds_box: VBoxContainer


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()


func apply_snapshot(snapshot: Dictionary) -> void:
	if _panel == null:
		_build_layout()

	var size: Dictionary = _dictionary_or_empty(snapshot.get("size", {}))
	_summary_label.text = "%s (%s) | %sx%s" % [
		snapshot.get("map_name", snapshot.get("active_map_id", "")),
		snapshot.get("active_map_id", ""),
		str(size.get("width", "?")),
		str(size.get("height", "?")),
	]
	_counts_label.text = "对象 %d | 占用格 %d | 阻挡格 %d" % [
		int(snapshot.get("object_count", 0)),
		int(snapshot.get("occupied_cell_count", 0)),
		int(snapshot.get("blocking_cell_count", 0)),
	]
	_entry_label.text = "入口: %s | 当前入口: %s" % [
		", ".join(_array_of_strings(snapshot.get("entry_points", []))),
		snapshot.get("active_entry_point_id", ""),
	]
	var active_location_id := str(snapshot.get("active_location_id", ""))
	var active_location_name := str(snapshot.get("active_location_name", active_location_id))
	_locations_label.text = "当前地点: %s (%s) | 已解锁: %s" % [
		active_location_name,
		active_location_id,
		", ".join(_array_of_strings(snapshot.get("unlocked_locations", []))),
	]
	_tracked_quest_label.text = _tracked_quest_text(snapshot.get("tracked_quest", {}))
	_clear_kinds()
	var kinds: Dictionary = _dictionary_or_empty(snapshot.get("objects_by_kind", {}))
	var keys: Array = kinds.keys()
	keys.sort()
	for key in keys:
		var label := _label("Kind_%s" % key)
		label.text = "%s: %d" % [key, int(kinds.get(key, 0))]
		_kinds_box.add_child(label)


func _build_layout() -> void:
	if _panel != null:
		return

	_panel = PanelContainer.new()
	_panel.name = "MapPanel"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left = -460
	_panel.offset_right = -16
	_panel.offset_top = -250
	_panel.offset_bottom = -24
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "MapLines"
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	_summary_label = _label("SummaryLine")
	_counts_label = _label("CountsLine")
	_entry_label = _label("EntryLine")
	_locations_label = _label("LocationsLine")
	_tracked_quest_label = _label("TrackedQuestLine")
	_kinds_box = VBoxContainer.new()
	_kinds_box.name = "KindLines"
	_kinds_box.add_theme_constant_override("separation", 3)
	box.add_child(_summary_label)
	box.add_child(_counts_label)
	box.add_child(_entry_label)
	box.add_child(_locations_label)
	box.add_child(_tracked_quest_label)
	box.add_child(_kinds_box)


func _label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _clear_kinds() -> void:
	for child in _kinds_box.get_children():
		_kinds_box.remove_child(child)
		child.free()


func _array_of_strings(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		result.append(str(item))
	return result


func _tracked_quest_text(value: Variant) -> String:
	var tracked: Dictionary = _dictionary_or_empty(value)
	if not bool(tracked.get("active", false)):
		return "追踪任务: 无"
	return "追踪任务: %s | %s %d/%d | %s" % [
		str(tracked.get("title", tracked.get("quest_id", ""))),
		str(tracked.get("objective_text", "")),
		int(tracked.get("progress_current", 0)),
		int(tracked.get("progress_target", 0)),
		str(tracked.get("status_text", "")),
	]


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
