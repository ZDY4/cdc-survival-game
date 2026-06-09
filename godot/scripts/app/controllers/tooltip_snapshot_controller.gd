extends RefCounted


func hover_tooltip_snapshot(viewport: Viewport, control: Control = null) -> Dictionary:
	var query_source := "explicit" if control != null else "hovered"
	var source := control
	if source == null:
		source = viewport.gui_get_hovered_control() if viewport != null else null
	if source == null:
		return tooltip_snapshot_base(viewport, null, null, query_source, "no_source", "")
	var tooltip_source := tooltip_source_for_control(source)
	if tooltip_source == null:
		return tooltip_snapshot_base(viewport, source, null, query_source, "no_text", owner_panel_for_control(source))
	var snapshot := tooltip_snapshot_base(viewport, source, tooltip_source, query_source, "active", owner_panel_for_control(tooltip_source))
	snapshot["active"] = true
	return snapshot


func tooltip_snapshot_base(viewport: Viewport, source: Control, tooltip_source: Control, query_source: String, lifecycle_state: String, owner_panel: String = "") -> Dictionary:
	var mouse_position := viewport.get_mouse_position() if viewport != null else Vector2.ZERO
	var viewport_size := viewport.get_visible_rect().size if viewport != null else Vector2.ZERO
	var resolved_source := tooltip_source if tooltip_source != null else source
	var button := resolved_source as BaseButton
	var source_rect := control_rect_snapshot(resolved_source)
	var text := str(resolved_source.tooltip_text) if resolved_source != null else ""
	var visual := tooltip_visual_snapshot(text, source_rect, mouse_position, viewport_size, lifecycle_state)
	return {
		"active": lifecycle_state == "active",
		"lifecycle_state": lifecycle_state,
		"query_source": query_source,
		"requested_source_path": str(source.get_path()) if source != null else "",
		"requested_source_name": str(source.name) if source != null else "",
		"requested_source_class": source.get_class() if source != null else "",
		"source_path": str(resolved_source.get_path()) if resolved_source != null else "",
		"source_name": str(resolved_source.name) if resolved_source != null else "",
		"source_class": resolved_source.get_class() if resolved_source != null else "",
		"owner_panel": owner_panel,
		"text": text,
		"text_length": text.length(),
		"screen_position": vector2_snapshot(mouse_position),
		"viewport_size": vector2_snapshot(viewport_size),
		"source_rect": source_rect,
		"requested_source_rect": control_rect_snapshot(source),
		"visible": resolved_source != null and resolved_source.is_visible_in_tree(),
		"disabled": button != null and button.disabled,
		"mouse_filter": mouse_filter_name(resolved_source.mouse_filter) if resolved_source != null else "",
		"mouse_filter_id": int(resolved_source.mouse_filter) if resolved_source != null else -1,
		"mouse_blocks_world": resolved_source != null and resolved_source.mouse_filter == Control.MOUSE_FILTER_STOP,
		"delay_policy": "godot_default",
		"delay_ms": -1,
		"visual": visual,
		"recommended_rect": _dictionary_or_empty(visual.get("recommended_rect", {})).duplicate(true),
	}


func tooltip_visual_snapshot(text: String, source_rect: Dictionary, mouse_position: Vector2, viewport_size: Vector2, lifecycle_state: String) -> Dictionary:
	var max_width := 320.0
	var min_width := 160.0
	var padding_x := 10.0
	var padding_y := 7.0
	var line_height := 18.0
	var text_length: int = max(1, text.length())
	var estimated_text_width: float = min(max_width - padding_x * 2.0, max(80.0, float(min(text_length, 42)) * 7.2))
	var line_count := int(ceil(float(text_length) / 42.0))
	var estimated_width := clampf(estimated_text_width + padding_x * 2.0, min_width, max_width)
	var estimated_height: float = max(28.0, float(line_count) * line_height + padding_y * 2.0)
	var anchor := Vector2(mouse_position.x + 14.0, mouse_position.y + 18.0)
	if not source_rect.is_empty():
		anchor = Vector2(float(source_rect.get("x", mouse_position.x)), float(source_rect.get("y", mouse_position.y)) + float(source_rect.get("h", 0.0)) + 8.0)
	if viewport_size.x > 0.0 and anchor.x + estimated_width > viewport_size.x - 8.0:
		anchor.x = max(8.0, viewport_size.x - estimated_width - 8.0)
	if viewport_size.y > 0.0 and anchor.y + estimated_height > viewport_size.y - 8.0:
		if not source_rect.is_empty():
			anchor.y = max(8.0, float(source_rect.get("y", mouse_position.y)) - estimated_height - 8.0)
		else:
			anchor.y = max(8.0, viewport_size.y - estimated_height - 8.0)
	return {
		"style": "panel_container",
		"theme_type": "TooltipPanel",
		"label_theme_type": "TooltipLabel",
		"placement": "below_source",
		"viewport_avoidance": true,
		"non_blocking": true,
		"max_width": max_width,
		"min_width": min_width,
		"padding": {"x": padding_x, "y": padding_y},
		"line_height": line_height,
		"estimated_line_count": line_count,
		"background_color": "0e141bcc",
		"border_color": "63809cff",
		"corner_radius": 4,
		"lifecycle_state": lifecycle_state,
		"recommended_rect": {"x": anchor.x, "y": anchor.y, "w": estimated_width, "h": estimated_height},
	}


func tooltip_source_for_control(control: Control) -> Control:
	var current: Node = control
	while current != null:
		if current is Control:
			var control_node := current as Control
			if not str(control_node.tooltip_text).is_empty():
				return control_node
		current = current.get_parent()
	return null


func owner_panel_for_control(control: Control) -> String:
	var current: Node = control
	while current != null:
		match str(current.name):
			"Hud":
				return "hud"
			"HUD":
				return "hud"
			"InventoryPanel":
				return "inventory"
			"CharacterPanel":
				return "character"
			"SkillsPanel":
				return "skills"
			"JournalPanel":
				return "journal"
			"CraftingPanel":
				return "crafting"
			"TradePanel":
				return "trade"
			"ContainerPanel":
				return "container"
			"DialoguePanel":
				return "dialogue"
			"SettingsPanel":
				return "settings"
		current = current.get_parent()
	return ""


func vector2_snapshot(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


func control_rect_snapshot(control: Control) -> Dictionary:
	if control == null or not control.is_inside_tree():
		return {}
	var rect := control.get_global_rect()
	return {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y}


func mouse_filter_name(mouse_filter: int) -> String:
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
