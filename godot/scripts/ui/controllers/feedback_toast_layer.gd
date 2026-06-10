extends RefCounted

var _layer: VBoxContainer


func build(owner: Control) -> void:
	if _layer != null:
		return
	_layer = VBoxContainer.new()
	_layer.name = "FeedbackToastLayer"
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_theme_constant_override("separation", 4)
	_layer.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_layer.offset_left = 16
	_layer.offset_top = 188
	_layer.offset_right = 560
	_layer.offset_bottom = 308
	owner.add_child(_layer)


func apply(value: Variant) -> void:
	if _layer == null:
		return
	_clear_children(_layer)
	var toasts: Array = _array_or_empty(value)
	_layer.visible = not toasts.is_empty()
	for toast_value in toasts:
		var toast: Dictionary = _dictionary_or_empty(toast_value)
		if toast.is_empty() or not bool(toast.get("visible", true)):
			continue
		_layer.add_child(_toast_row(toast))


func _toast_row(toast: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.name = "FeedbackToast_%s" % str(toast.get("id", "toast"))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(240, 24)
	var severity := str(toast.get("severity", "info"))
	var alpha := float(toast.get("alpha", 1.0))
	var phase := str(toast.get("phase", "visible"))
	row.add_theme_stylebox_override("panel", _toast_style(severity, alpha, phase))
	row.modulate.a = clampf(alpha, 0.18, 1.0)
	_apply_metadata(row, toast)
	row.set_meta("toast_visual_kind", "panel")
	row.set_meta("toast_border_color", _border_color(severity).to_html())
	row.set_meta("toast_background_alpha", alpha)
	row.set_meta("toast_minimum_width", row.custom_minimum_size.x)
	var label := _line("FeedbackToastLabel")
	label.text = str(toast.get("text", ""))
	label.modulate = _text_color(severity, 1.0)
	label.tooltip_text = "%s | %s" % [severity, str(_dictionary_or_empty(toast.get("transition", {})).get("style", ""))]
	_apply_metadata(label, toast)
	row.add_child(label)
	return row


func _apply_metadata(node: Node, toast: Dictionary) -> void:
	node.set_meta("toast_id", str(toast.get("id", "")))
	node.set_meta("toast_kind", str(toast.get("kind", "")))
	node.set_meta("toast_severity", str(toast.get("severity", "")))
	node.set_meta("toast_phase", str(toast.get("phase", "")))
	node.set_meta("toast_slot", int(toast.get("slot", 0)))
	node.set_meta("toast_alpha", float(toast.get("alpha", 1.0)))
	node.set_meta("toast_ttl_events", int(toast.get("ttl_events", 0)))
	node.set_meta("toast_age_events", int(toast.get("age_events", 0)))
	node.set_meta("toast_transition_style", str(_dictionary_or_empty(toast.get("transition", {})).get("style", "")))
	var details: Dictionary = _dictionary_or_empty(toast.get("details", {}))
	node.set_meta("toast_has_details", bool(toast.get("has_details", not details.is_empty())))
	node.set_meta("toast_detail_count", int(toast.get("detail_count", _array_or_empty(details.get("entries", [])).size())))
	node.set_meta("toast_detail_summary", str(details.get("summary", "")))


func _toast_style(severity: String, alpha: float, phase: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var background_alpha := clampf(0.58 * alpha, 0.18, 0.72)
	if phase == "fading":
		background_alpha = clampf(0.42 * alpha, 0.12, 0.56)
	style.bg_color = _background_color(severity, background_alpha)
	style.border_color = _border_color(severity)
	style.border_color.a = clampf(0.84 * alpha, 0.22, 0.92)
	style.border_width_left = 2
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


func _background_color(severity: String, alpha: float) -> Color:
	match severity:
		"success":
			return Color(0.08, 0.20, 0.13, alpha)
		"warning":
			return Color(0.22, 0.17, 0.06, alpha)
		"error":
			return Color(0.24, 0.09, 0.08, alpha)
		_:
			return Color(0.08, 0.12, 0.18, alpha)


func _border_color(severity: String) -> Color:
	match severity:
		"success":
			return Color(0.33, 0.72, 0.43, 1.0)
		"warning":
			return Color(0.90, 0.66, 0.20, 1.0)
		"error":
			return Color(0.86, 0.34, 0.30, 1.0)
		_:
			return Color(0.38, 0.55, 0.74, 1.0)


func _text_color(severity: String, alpha: float) -> Color:
	var color := Color(0.82, 0.90, 1.0, alpha)
	match severity:
		"success":
			color = Color(0.62, 0.95, 0.70, alpha)
		"warning":
			color = Color(1.0, 0.86, 0.46, alpha)
		"error":
			color = Color(1.0, 0.54, 0.50, alpha)
	return color


func _clear_children(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		node.remove_child(child)
		child.free()


func _line(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = true
	return label


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
