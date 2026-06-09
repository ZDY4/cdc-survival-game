extends RefCounted

var tooltip_layer: Control
var tooltip_panel: PanelContainer
var tooltip_label: Label
var last_tooltip_render_snapshot: Dictionary = {"active": false}

var drag_preview_layer: Control
var drag_preview_panel: PanelContainer
var drag_preview_label: Label
var last_drag_preview_render_snapshot: Dictionary = {"active": false}


func setup_tooltip_layer(owner: Node) -> void:
	if tooltip_layer != null or owner == null:
		return
	tooltip_layer = Control.new()
	tooltip_layer.name = "TooltipLayer"
	tooltip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	tooltip_layer.visible = false
	owner.add_child(tooltip_layer)
	tooltip_panel = PanelContainer.new()
	tooltip_panel.name = "TooltipPanel"
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_panel.visible = false
	tooltip_layer.add_child(tooltip_panel)
	tooltip_label = Label.new()
	tooltip_label.name = "TooltipLabel"
	tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_panel.add_child(tooltip_label)


func hide_tooltip_layer(reason: String) -> void:
	if tooltip_layer != null:
		tooltip_layer.visible = false
	if tooltip_panel != null:
		tooltip_panel.visible = false
	last_tooltip_render_snapshot = {
		"active": false,
		"reason": reason,
		"layer_exists": tooltip_layer != null,
		"mouse_blocks_world": false,
	}


func render_tooltip_snapshot(owner: Node, snapshot: Dictionary) -> void:
	setup_tooltip_layer(owner)
	if tooltip_layer == null or tooltip_panel == null or tooltip_label == null:
		hide_tooltip_layer("layer_missing")
		return
	var rect: Dictionary = _dictionary_or_empty(snapshot.get("recommended_rect", {}))
	var visual: Dictionary = _dictionary_or_empty(snapshot.get("visual", {}))
	var position := Vector2(float(rect.get("x", 8.0)), float(rect.get("y", 8.0)))
	var size := Vector2(float(rect.get("w", 160.0)), float(rect.get("h", 28.0)))
	tooltip_layer.visible = true
	tooltip_panel.visible = true
	tooltip_panel.position = position
	tooltip_panel.custom_minimum_size = size
	tooltip_panel.size = size
	tooltip_panel.add_theme_stylebox_override("panel", _tooltip_panel_style(visual))
	tooltip_label.text = str(snapshot.get("text", ""))
	tooltip_label.custom_minimum_size = Vector2(max(1.0, size.x - 20.0), 0.0)
	tooltip_label.add_theme_font_size_override("font_size", 12)
	tooltip_label.set_meta("tooltip_text_length", int(snapshot.get("text_length", 0)))
	tooltip_label.set_meta("tooltip_owner_panel", str(snapshot.get("owner_panel", "")))
	tooltip_label.set_meta("tooltip_source_name", str(snapshot.get("source_name", "")))
	tooltip_panel.set_meta("tooltip_visual_style", str(visual.get("style", "")))
	tooltip_panel.set_meta("tooltip_theme_type", str(visual.get("theme_type", "")))
	tooltip_panel.set_meta("tooltip_recommended_rect", rect.duplicate(true))
	tooltip_panel.set_meta("tooltip_non_blocking", bool(visual.get("non_blocking", false)))
	last_tooltip_render_snapshot = {
		"active": true,
		"layer_path": str(tooltip_layer.get_path()),
		"panel_path": str(tooltip_panel.get_path()),
		"label_path": str(tooltip_label.get_path()),
		"owner_panel": str(snapshot.get("owner_panel", "")),
		"source_name": str(snapshot.get("source_name", "")),
		"text": str(snapshot.get("text", "")),
		"text_length": int(snapshot.get("text_length", 0)),
		"mouse_blocks_world": tooltip_layer.mouse_filter == Control.MOUSE_FILTER_STOP or tooltip_panel.mouse_filter == Control.MOUSE_FILTER_STOP,
		"layer_mouse_filter": _mouse_filter_name(tooltip_layer.mouse_filter),
		"panel_mouse_filter": _mouse_filter_name(tooltip_panel.mouse_filter),
		"visual": visual.duplicate(true),
		"recommended_rect": rect.duplicate(true),
		"actual_rect": {"x": tooltip_panel.position.x, "y": tooltip_panel.position.y, "w": tooltip_panel.size.x, "h": tooltip_panel.size.y},
		"label_text_matches": tooltip_label.text == str(snapshot.get("text", "")),
	}


func tooltip_render_snapshot() -> Dictionary:
	return last_tooltip_render_snapshot.duplicate(true)


func setup_drag_preview_layer(owner: Node) -> void:
	if drag_preview_layer != null or owner == null:
		return
	drag_preview_layer = Control.new()
	drag_preview_layer.name = "DragPreviewLayer"
	drag_preview_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	drag_preview_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	drag_preview_layer.visible = false
	owner.add_child(drag_preview_layer)
	drag_preview_panel = PanelContainer.new()
	drag_preview_panel.name = "DragPreviewPanel"
	drag_preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_preview_panel.visible = false
	drag_preview_layer.add_child(drag_preview_panel)
	drag_preview_label = Label.new()
	drag_preview_label.name = "DragPreviewLabel"
	drag_preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_preview_label.clip_text = true
	drag_preview_panel.add_child(drag_preview_label)


func hide_drag_preview_layer(reason: String) -> void:
	if drag_preview_layer != null:
		drag_preview_layer.visible = false
	if drag_preview_panel != null:
		drag_preview_panel.visible = false
	last_drag_preview_render_snapshot = {
		"active": false,
		"reason": reason,
		"layer_exists": drag_preview_layer != null,
		"mouse_blocks_world": false,
	}


func render_drag_preview_snapshot(owner: Node, drag: Dictionary) -> void:
	setup_drag_preview_layer(owner)
	if drag_preview_layer == null or drag_preview_panel == null or drag_preview_label == null:
		hide_drag_preview_layer("layer_missing")
		return
	var preview: Dictionary = _dictionary_or_empty(drag.get("preview", {}))
	var position_data: Dictionary = _dictionary_or_empty(preview.get("screen_position", {}))
	var anchor_data: Dictionary = _dictionary_or_empty(preview.get("anchor", {}))
	var size_data: Dictionary = _dictionary_or_empty(preview.get("estimated_size", {}))
	var position := Vector2(float(position_data.get("x", 0.0)) + float(anchor_data.get("x", 8.0)), float(position_data.get("y", 0.0)) + float(anchor_data.get("y", 8.0)))
	var size := Vector2(maxf(48.0, float(size_data.get("x", 80.0))), maxf(24.0, float(size_data.get("y", 24.0))))
	drag_preview_layer.visible = true
	drag_preview_panel.visible = true
	drag_preview_panel.position = position
	drag_preview_panel.custom_minimum_size = size
	drag_preview_panel.size = size
	drag_preview_panel.add_theme_stylebox_override("panel", _drag_preview_panel_style(str(drag.get("kind", ""))))
	drag_preview_label.text = str(preview.get("text", ""))
	drag_preview_label.custom_minimum_size = Vector2(max(1.0, size.x - 18.0), max(1.0, size.y - 8.0))
	drag_preview_label.add_theme_font_size_override("font_size", 12)
	drag_preview_panel.set_meta("drag_preview_kind", str(drag.get("kind", "")))
	drag_preview_panel.set_meta("drag_preview_text", drag_preview_label.text)
	drag_preview_panel.set_meta("drag_preview_lifecycle", str(preview.get("lifecycle_state", "")))
	drag_preview_panel.set_meta("drag_preview_threshold_policy", str(preview.get("threshold_policy", "")))
	last_drag_preview_render_snapshot = {
		"active": true,
		"layer_path": str(drag_preview_layer.get_path()),
		"panel_path": str(drag_preview_panel.get_path()),
		"label_path": str(drag_preview_label.get_path()),
		"kind": str(drag.get("kind", "")),
		"owner_panel": str(_dictionary_or_empty(drag.get("source", {})).get("owner_panel", "")),
		"text": drag_preview_label.text,
		"mouse_blocks_world": drag_preview_layer.mouse_filter == Control.MOUSE_FILTER_STOP,
		"layer_mouse_filter": _mouse_filter_name(drag_preview_layer.mouse_filter),
		"panel_mouse_filter": _mouse_filter_name(drag_preview_panel.mouse_filter),
		"preview": preview.duplicate(true),
		"actual_rect": {"x": drag_preview_panel.position.x, "y": drag_preview_panel.position.y, "w": drag_preview_panel.size.x, "h": drag_preview_panel.size.y},
		"label_text_matches": drag_preview_label.text == str(preview.get("text", "")),
		"threshold_policy": str(preview.get("threshold_policy", "")),
		"lifecycle_state": str(preview.get("lifecycle_state", "")),
	}


func drag_preview_render_snapshot() -> Dictionary:
	return last_drag_preview_render_snapshot.duplicate(true)


func _tooltip_panel_style(visual: Dictionary) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.078, 0.105, 0.88)
	style.border_color = Color(0.39, 0.50, 0.61, 0.96)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	var radius := int(visual.get("corner_radius", 4))
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	var padding: Dictionary = _dictionary_or_empty(visual.get("padding", {}))
	var padding_x := float(padding.get("x", 10.0))
	var padding_y := float(padding.get("y", 7.0))
	style.content_margin_left = padding_x
	style.content_margin_right = padding_x
	style.content_margin_top = padding_y
	style.content_margin_bottom = padding_y
	return style


func _drag_preview_panel_style(kind: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.13, 0.16, 0.86)
	style.border_color = Color(0.58, 0.68, 0.74, 0.96)
	if kind == "skill_hotbar":
		style.border_color = Color(0.45, 0.66, 0.90, 0.96)
	elif kind in ["trade_item", "trade_cart_entry"]:
		style.border_color = Color(0.74, 0.62, 0.36, 0.96)
	elif kind == "container_item":
		style.border_color = Color(0.42, 0.70, 0.55, 0.96)
	style.border_width_left = 2
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _mouse_filter_name(mouse_filter: int) -> String:
	match mouse_filter:
		Control.MOUSE_FILTER_STOP:
			return "stop"
		Control.MOUSE_FILTER_PASS:
			return "pass"
		Control.MOUSE_FILTER_IGNORE:
			return "ignore"
	return "unknown"


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
