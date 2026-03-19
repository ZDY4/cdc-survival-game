extends PanelContainer

class_name SkillHotbarSlot

signal drop_requested(slot_index: int, data: Dictionary)
signal drag_cleared(group_index: int, slot_index: int)

const DEFAULT_SLOT_SIZE: float = 56.0

var slot_index: int = -1
var group_index: int = 0
var skill_id: String = ""
var skill_data: Dictionary = {}

var _key_label: Label = null
var _icon_rect: TextureRect = null
var _placeholder_rect: ColorRect = null
var _placeholder_label: Label = null
var _cooldown_fill: ColorRect = null
var _cooldown_label: Label = null

var _drag_group_index: int = -1
var _drag_slot_index: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_slot_size(DEFAULT_SLOT_SIZE)
	_build_ui()
	_refresh_display()


func configure(data: Dictionary) -> void:
	slot_index = int(data.get("slot_index", slot_index))
	group_index = int(data.get("group_index", group_index))
	skill_id = str(data.get("skill_id", ""))
	skill_data = (data.get("skill_data", {}) as Dictionary).duplicate(true)
	if is_node_ready():
		_refresh_display()


func pulse_highlight() -> void:
	modulate = Color(1.0, 0.95, 0.65, 1.0)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.35)


func set_slot_size(side_length: float) -> void:
	var resolved_size: float = maxf(1.0, side_length)
	custom_minimum_size = Vector2(resolved_size, resolved_size)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if skill_id.is_empty():
		return null

	_drag_group_index = group_index
	_drag_slot_index = slot_index
	var preview := duplicate() as Control
	if preview == null:
		return null
	preview.custom_minimum_size = size
	set_drag_preview(preview)
	return {
		"type": "hotbar_skill",
		"skill_id": skill_id,
		"group_index": group_index,
		"slot_index": slot_index
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var payload: Dictionary = data
	var payload_type: String = str(payload.get("type", ""))
	return payload_type == "skill_panel_item" or payload_type == "hotbar_skill"


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Dictionary:
		drop_requested.emit(slot_index, data as Dictionary)


func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END:
		return
	if _drag_slot_index < 0 or _drag_group_index < 0:
		return
	if not get_viewport().gui_is_drag_successful():
		drag_cleared.emit(_drag_group_index, _drag_slot_index)
	_drag_group_index = -1
	_drag_slot_index = -1


func _build_ui() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.13, 0.96)
	style.border_color = Color(0.30, 0.36, 0.42, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	add_theme_stylebox_override("panel", style)

	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_placeholder_rect = ColorRect.new()
	_placeholder_rect.color = Color(0.22, 0.28, 0.33, 1.0)
	_placeholder_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_placeholder_rect)

	_placeholder_label = Label.new()
	_placeholder_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_placeholder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder_label.add_theme_font_size_override("font_size", 14)
	_placeholder_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_placeholder_label)

	_icon_rect = TextureRect.new()
	_icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_icon_rect)

	_cooldown_fill = ColorRect.new()
	_cooldown_fill.color = Color(0.05, 0.05, 0.07, 0.72)
	_cooldown_fill.anchor_left = 0.0
	_cooldown_fill.anchor_right = 1.0
	_cooldown_fill.anchor_bottom = 1.0
	_cooldown_fill.offset_left = 0.0
	_cooldown_fill.offset_right = 0.0
	_cooldown_fill.offset_bottom = 0.0
	root.add_child(_cooldown_fill)

	_cooldown_label = Label.new()
	_cooldown_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cooldown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cooldown_label.add_theme_font_size_override("font_size", 13)
	_cooldown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_cooldown_label)

	_key_label = Label.new()
	_key_label.anchor_right = 1.0
	_key_label.anchor_bottom = 0.0
	_key_label.offset_left = 4.0
	_key_label.offset_top = 2.0
	_key_label.offset_right = -4.0
	_key_label.offset_bottom = 16.0
	_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_key_label.add_theme_font_size_override("font_size", 10)
	_key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_key_label)


func _refresh_display() -> void:
	if _key_label == null:
		return

	var key_texts: Array[String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
	_key_label.text = key_texts[slot_index] if slot_index >= 0 and slot_index < key_texts.size() else ""

	var skill_name: String = str(skill_data.get("name", skill_id))
	var icon_path: String = str(skill_data.get("icon", "")).strip_edges()
	var texture: Texture2D = null
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		texture = load(icon_path) as Texture2D
	_icon_rect.texture = texture
	_icon_rect.visible = texture != null and not skill_id.is_empty()
	_placeholder_rect.visible = texture == null
	_placeholder_label.visible = texture == null
	_placeholder_label.text = "" if skill_id.is_empty() else _build_placeholder_text(skill_name)

	var cooldown: float = float(skill_data.get("cooldown_remaining", 0.0))
	var activation: Dictionary = skill_data.get("activation", {})
	var base_cooldown: float = maxf(0.0, float(activation.get("cooldown", 0.0)))
	if cooldown > 0.0 and base_cooldown > 0.0:
		var ratio: float = clampf(cooldown / base_cooldown, 0.0, 1.0)
		_cooldown_fill.visible = true
		_cooldown_fill.anchor_top = 1.0 - ratio
		_cooldown_fill.offset_top = 0.0
		_cooldown_label.visible = true
		_cooldown_label.text = str(ceili(cooldown))
	else:
		_cooldown_fill.visible = false
		_cooldown_label.visible = false
		_cooldown_label.text = ""

	tooltip_text = skill_name if not skill_name.is_empty() else "空槽位"
	if not skill_id.is_empty():
		tooltip_text += "\n%s" % str(skill_data.get("description", ""))

	var style := get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if style != null:
		style.border_color = Color(0.22, 0.70, 0.47, 1.0) if bool(skill_data.get("toggle_active", false)) else Color(0.30, 0.36, 0.42, 1.0)
		add_theme_stylebox_override("panel", style)


func _build_placeholder_text(skill_name: String) -> String:
	var trimmed: String = skill_name.strip_edges()
	if trimmed.length() <= 2:
		return trimmed
	return trimmed.substr(0, 2)
