extends RefCounted

const ReasonCatalog = preload("res://scripts/ui/snapshots/reason_catalog.gd")

var _panel: PanelContainer
var _title_label: Label
var _lines_box: VBoxContainer
var _visible := false
var _latest_snapshot: Dictionary = {}
var _reason_catalog := ReasonCatalog.new()


func build(owner: Control) -> void:
	if _panel != null:
		return
	_panel = PanelContainer.new()
	_panel.name = "DebugPanel"
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -444
	_panel.offset_right = -16
	_panel.offset_top = 16
	_panel.offset_bottom = 300
	owner.add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "DebugPanelLines"
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)

	_title_label = _line("DebugPanelTitle")
	_title_label.text = "Debug Panel"
	box.add_child(_title_label)
	_lines_box = VBoxContainer.new()
	_lines_box.name = "DebugPanelContent"
	_lines_box.add_theme_constant_override("separation", 3)
	box.add_child(_lines_box)
	apply(_latest_snapshot)


func toggle() -> Dictionary:
	_visible = not _visible
	apply(_latest_snapshot)
	return {"success": true, "visible": _visible}


func hide() -> void:
	_visible = false
	apply(_latest_snapshot)


func is_open() -> bool:
	return _visible


func snapshot() -> Dictionary:
	var lines := line_texts()
	return {
		"visible": _visible,
		"line_count": lines.size(),
		"lines": lines,
	}


func apply(snapshot_data: Dictionary) -> void:
	_latest_snapshot = snapshot_data.duplicate(true)
	if _panel == null:
		return
	_panel.visible = _visible
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _title_label != null:
		_title_label.text = "Debug Panel | F3 | %s" % ("on" if _visible else "off")
	if _lines_box == null:
		return
	for child in _lines_box.get_children():
		child.queue_free()
	for entry in _entries(snapshot_data):
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var label := _line("DebugPanelLine_%s" % str(entry_data.get("kind", "entry")))
		label.text = str(entry_data.get("text", ""))
		label.tooltip_text = str(entry_data.get("tooltip", label.text))
		label.set_meta("debug_panel_kind", str(entry_data.get("kind", "")))
		label.set_meta("debug_panel_text", label.text)
		_lines_box.add_child(label)


func line_texts() -> Array[String]:
	var lines: Array[String] = []
	if _lines_box == null:
		return lines
	for child in _lines_box.get_children():
		if child is Label:
			lines.append(str((child as Label).text))
	return lines


func _entries(snapshot_data: Dictionary) -> Array[Dictionary]:
	var runtime_control: Dictionary = _dictionary_or_empty(snapshot_data.get("runtime_control", {}))
	var info_panel: Dictionary = _dictionary_or_empty(snapshot_data.get("info_panel", {}))
	var debug_overlay: Dictionary = _dictionary_or_empty(runtime_control.get("debug_overlay", {}))
	var console: Dictionary = _dictionary_or_empty(runtime_control.get("debug_console", {}))
	return [
		{"kind": "overlay", "text": "Overlay: %s | active %s | cells %d" % [
			str(debug_overlay.get("mode", snapshot_data.get("debug_overlay_mode", "off"))),
			"yes" if bool(debug_overlay.get("active", false)) else "no",
			int(debug_overlay.get("cell_count", 0)),
		]},
		{"kind": "info", "text": _info_panel_text(info_panel)},
		{"kind": "runtime", "text": _runtime_text(runtime_control)},
		{"kind": "hover", "text": _hover_text(runtime_control.get("hover", {})) if not _hover_text(runtime_control.get("hover", {})).is_empty() else "Hover none"},
		{"kind": "selection", "text": _selection_text(runtime_control.get("selection_debug", {})) if not _selection_text(runtime_control.get("selection_debug", {})).is_empty() else "Sel none"},
		{"kind": "ai", "text": _ai_text(runtime_control.get("ai_debug", {})) if not _ai_text(runtime_control.get("ai_debug", {})).is_empty() else "AI none"},
		{"kind": "performance", "text": _performance_text(runtime_control.get("performance", {})) if not _performance_text(runtime_control.get("performance", {})).is_empty() else "Perf none"},
		{"kind": "console", "text": _console_text(console)},
	]


func _console_text(console: Dictionary) -> String:
	var permission: Dictionary = _dictionary_or_empty(console.get("permission", {}))
	return "Console %s | history %d | suggestions %d | schema %d | mutate %s" % [
		"on" if bool(console.get("visible", false)) else "off",
		int(console.get("history_count", 0)),
		int(console.get("suggestion_count", 0)),
		int(console.get("command_schema_count", 0)),
		"on" if bool(permission.get("allow_runtime_mutation", true)) else "off",
	]


func _runtime_text(runtime_control: Dictionary) -> String:
	var parts: Array[String] = [
		"Auto %s" % ("on" if bool(runtime_control.get("auto_tick", false)) else "off"),
		"Observe %s %s %s" % [
			"on" if bool(runtime_control.get("observe_mode", false)) else "off",
			"play" if bool(runtime_control.get("observe_playback", false)) else "pause",
			str(runtime_control.get("observe_speed", "x1")),
		],
	]
	var blocker_snapshot: Dictionary = _dictionary_or_empty(runtime_control.get("ui_blocker_snapshot", {}))
	var blocker := str(blocker_snapshot.get("name", runtime_control.get("ui_blocker", "")))
	if not blocker.is_empty():
		var kind := str(blocker_snapshot.get("kind", ""))
		parts.append("Blocker %s%s" % [blocker, " (%s)" % kind if not kind.is_empty() else ""])
	var modal_stack: Dictionary = _dictionary_or_empty(runtime_control.get("modal_stack", {}))
	if bool(modal_stack.get("active", false)):
		var top_modal: Dictionary = _dictionary_or_empty(modal_stack.get("top", {}))
		parts.append("Modal %s/%d" % [str(top_modal.get("id", "")), int(modal_stack.get("count", 0))])
	var menu_state: Dictionary = _dictionary_or_empty(runtime_control.get("menu_state", {}))
	if not menu_state.is_empty():
		parts.append("Menu %s S:%s" % [
			"settings" if bool(menu_state.get("settings_open", false)) else "stage",
			str(menu_state.get("active_stage_panel", "-")) if not str(menu_state.get("active_stage_panel", "")).is_empty() else "-",
		])
		var latest_panel_event: Dictionary = _dictionary_or_empty(menu_state.get("latest_event", {}))
		if not latest_panel_event.is_empty():
			parts.append("Panel %s:%s" % [str(latest_panel_event.get("event", "")), str(latest_panel_event.get("panel_id", ""))])
		_append_menu_event_tokens(parts, menu_state)
	var context_menu: Dictionary = _dictionary_or_empty(runtime_control.get("context_menu", {}))
	if bool(context_menu.get("active", false)):
		var top_context: Dictionary = _dictionary_or_empty(context_menu.get("top", {}))
		parts.append("Context %s/%d" % [str(top_context.get("id", "")), int(context_menu.get("count", 0))])
	var tooltip: Dictionary = _dictionary_or_empty(runtime_control.get("tooltip", {}))
	if bool(tooltip.get("active", false)):
		parts.append(_tooltip_token(tooltip))
	var drag: Dictionary = _dictionary_or_empty(runtime_control.get("drag", {}))
	if bool(drag.get("active", false)):
		var target: Dictionary = _dictionary_or_empty(drag.get("target", {}))
		parts.append("Drag %s->%s/%s" % [str(drag.get("kind", "")), str(target.get("owner_panel", "")), str(target.get("target_kind", ""))])
	var level: Dictionary = _dictionary_or_empty(runtime_control.get("map_level", {}))
	if not level.is_empty():
		parts.append("Level %d" % int(level.get("current", 0)))
	var focus: Dictionary = _dictionary_or_empty(runtime_control.get("focused_actor", {}))
	if not focus.is_empty():
		parts.append("Focus #%d" % int(focus.get("actor_id", 0)))
	return "Runtime: %s" % " | ".join(parts)


func _info_panel_text(info_panel: Variant) -> String:
	if typeof(info_panel) != TYPE_DICTIONARY:
		return "Info none"
	var info_data: Dictionary = info_panel
	var page: Dictionary = info_data.get("active_page", {})
	if page.is_empty():
		return "Info none"
	return "Info %s %d/%d" % [
		str(page.get("title", "")),
		int(info_data.get("active_index", 0)) + 1,
		int(info_data.get("count", 0)),
	]


func _performance_text(value: Variant) -> String:
	var performance: Dictionary = _dictionary_or_empty(value)
	if performance.is_empty():
		return ""
	return "Perf %dFPS %.1fms Path %.2fms Lat %dms R%d A%d O%d" % [
		int(round(float(performance.get("fps", 0.0)))),
		float(performance.get("frame_time_ms", 0.0)),
		float(performance.get("pathfinding_time_ms", 0.0)),
		int(performance.get("hud_latency_ms", 0)),
		int(performance.get("render_count", 0)),
		int(performance.get("actor_count", 0)),
		int(performance.get("object_count", 0)),
	]


func _append_menu_event_tokens(parts: Array[String], menu_state: Dictionary) -> void:
	var modal_event: Dictionary = _dictionary_or_empty(menu_state.get("modal_event", {}))
	if not modal_event.is_empty():
		parts.append("ModalEvent %s:%s" % [str(modal_event.get("event", "")), str(modal_event.get("panel_id", ""))])
	var context_menu_event: Dictionary = _dictionary_or_empty(menu_state.get("context_menu_event", {}))
	if not context_menu_event.is_empty():
		parts.append("ContextEvent %s:%s" % [str(context_menu_event.get("event", "")), str(context_menu_event.get("panel_id", ""))])


func _tooltip_token(tooltip: Dictionary) -> String:
	var position: Dictionary = _dictionary_or_empty(tooltip.get("screen_position", {}))
	var position_text := ""
	if not position.is_empty():
		position_text = "@%d,%d" % [int(round(float(position.get("x", 0.0)))), int(round(float(position.get("y", 0.0))))]
	return "Tip %s/%s%s" % [str(tooltip.get("owner_panel", "")), str(tooltip.get("source_name", "")), position_text]


func _selection_text(value: Variant) -> String:
	var selection_debug: Dictionary = _dictionary_or_empty(value)
	if selection_debug.is_empty():
		return ""
	var blocker := str(selection_debug.get("blocker_name", ""))
	if not blocker.is_empty():
		return "Sel blocked:%s" % blocker
	if not bool(selection_debug.get("active", false)):
		var reason := str(selection_debug.get("reason", ""))
		return "" if reason.is_empty() else "Sel none:%s" % reason
	var prompt: Dictionary = _dictionary_or_empty(selection_debug.get("prompt", {}))
	var action := str(prompt.get("action_label", prompt.get("primary_option_id", "")))
	if action.is_empty() and bool(prompt.get("has_prompt", false)):
		action = "prompt"
	var target := str(selection_debug.get("target_name", selection_debug.get("target_id", "")))
	if target.is_empty():
		target = str(selection_debug.get("kind", ""))
	var category := str(selection_debug.get("target_category", selection_debug.get("target_type", "")))
	return "Sel %s %s %s" % [category, target, action]


func _ai_text(value: Variant) -> String:
	var ai_debug: Dictionary = _dictionary_or_empty(value)
	if ai_debug.is_empty():
		return ""
	var intent: Dictionary = _dictionary_or_empty(ai_debug.get("focused_intent", {}))
	if intent.is_empty():
		intent = _dictionary_or_empty(ai_debug.get("latest_intent", {}))
	if intent.is_empty():
		var count := int(ai_debug.get("intent_count", 0))
		return "" if count <= 0 else "AI intents %d" % count
	var target_text := ""
	var target_actor_id := int(intent.get("target_actor_id", 0))
	if target_actor_id > 0:
		target_text = " ->#%d" % target_actor_id
	var path_length := int(intent.get("path_length", 0))
	var path_text := "" if path_length <= 0 else " path%d" % path_length
	var tracking_state := str(intent.get("target_tracking_state", ""))
	var tracking_text := "" if tracking_state.is_empty() or tracking_state == "none" else " %s" % tracking_state
	var settlement_text := ""
	var route_id := str(intent.get("route_id", ""))
	var anchor_id := str(intent.get("anchor_id", ""))
	var smart_object_id := str(intent.get("smart_object_id", ""))
	if not route_id.is_empty():
		settlement_text = " route:%s" % route_id
	elif not smart_object_id.is_empty():
		settlement_text = " object:%s" % smart_object_id
	elif not anchor_id.is_empty():
		settlement_text = " anchor:%s" % anchor_id
	var status_text := ""
	var life_status_id := str(intent.get("life_status_id", ""))
	if not life_status_id.is_empty():
		status_text = " status:%s" % life_status_id
	var reason := str(intent.get("reason", ""))
	var reason_text := "" if reason.is_empty() else " %s" % reason
	return "AI #%d %s%s%s%s%s%s%s" % [
		int(intent.get("actor_id", 0)),
		str(intent.get("intent", "")),
		target_text,
		path_text,
		tracking_text,
		settlement_text,
		status_text,
		reason_text,
	]


func _hover_text(value: Variant) -> String:
	var hover: Dictionary = _dictionary_or_empty(value)
	var blocker := str(hover.get("ui_blocker", ""))
	if not blocker.is_empty():
		return "Hover UI %s" % blocker
	if not bool(hover.get("active", false)):
		var reason := str(hover.get("reason", ""))
		return "" if reason.is_empty() else "Hover none %s" % reason
	var kind := str(hover.get("kind", ""))
	var grid: Dictionary = _dictionary_or_empty(hover.get("grid", {}))
	var grid_text := ""
	if not grid.is_empty():
		grid_text = "@%d,%d,%d" % [
			int(grid.get("x", 0)),
			int(grid.get("y", 0)),
			int(grid.get("z", 0)),
		]
	if kind == "interaction":
		var target_name := str(hover.get("target_name", hover.get("target_id", "")))
		var category := str(hover.get("target_category", "interaction"))
		return "Hover %s %s%s%s%s" % [
			category,
			target_name,
			grid_text,
			_hover_prompt_text(hover),
			_hover_attack_preview_text(hover),
		]
	return "Hover %s%s%s%s" % [
		kind,
		grid_text,
		_hover_move_preview_text(hover),
		_hover_prompt_text(hover),
	]


func _hover_prompt_text(hover: Dictionary) -> String:
	var prompt: Dictionary = _dictionary_or_empty(hover.get("prompt", {}))
	if prompt.is_empty():
		return ""
	if bool(prompt.get("ok", false)):
		var action := str(prompt.get("action_label", prompt.get("primary_option_id", "")))
		var distance := int(prompt.get("target_distance", -1))
		var range := int(prompt.get("interaction_range", -1))
		var approach := " 接近" if bool(prompt.get("requires_approach", false)) else ""
		var distance_text := "" if distance < 0 or range < 0 else " 距离%d/范围%d" % [distance, range]
		return " | %s%s%s" % [action, distance_text, approach]
	var reason := str(prompt.get("reason", ""))
	return "" if reason.is_empty() else " | 不可用:%s" % _disabled_reason_text(reason)


func _hover_move_preview_text(hover: Dictionary) -> String:
	var preview: Dictionary = _dictionary_or_empty(hover.get("move_preview", {}))
	if preview.is_empty():
		return ""
	if bool(preview.get("reachable", false)):
		return " 可达%d步 Path%.2fms" % [int(preview.get("steps", 0)), float(preview.get("pathfinding_time_ms", 0.0))]
	var reason := str(preview.get("reason", ""))
	if reason.is_empty():
		return " 不可达"
	return " 不可达:%s" % _disabled_reason_text(reason)


func _hover_attack_preview_text(hover: Dictionary) -> String:
	var preview: Dictionary = _dictionary_or_empty(hover.get("attack_preview", {}))
	if preview.is_empty():
		return ""
	var distance := int(preview.get("distance", -1))
	var range := int(preview.get("range", -1))
	var range_text := "" if distance < 0 or range < 0 else " 距离%d/射程%d" % [distance, range]
	var ap_text := " AP%s/%s" % [
		_number_text(float(preview.get("ap_cost", 0.0))),
		_number_text(float(preview.get("ap_available", 0.0))),
	]
	if bool(preview.get("can_attack", false)):
		var hit_chance := float(preview.get("hit_chance", -1.0))
		var hit_text := "" if hit_chance < 0.0 else " 命中率%s" % _percent_text(hit_chance)
		var damage := float(preview.get("estimated_damage", 0.0))
		var damage_text := "" if damage <= 0.0 else " 伤害%s" % _number_text(damage)
		return " | 可攻击%s%s%s%s" % [range_text, ap_text, hit_text, damage_text]
	var reason := str(preview.get("reason", ""))
	return " | 不可攻击%s%s:%s" % [range_text, ap_text, _disabled_reason_text(reason)]


func _disabled_reason_text(reason: String) -> String:
	match reason:
		"target_not_container":
			return "不是容器"
		"target_not_hostile":
			return "非敌对目标"
		"target_hostile":
			return "敌对目标"
		"target_empty":
			return "目标为空"
		"target_not_visible":
			return "目标不可见"
		"target_too_close":
			return "目标过近"
		"target_not_pickup":
			return "不可拾取"
		"self_target":
			return "自身目标"
		"door_locked":
			return "门已上锁"
		"door_key_missing":
			return "缺少钥匙"
		"door_tool_missing":
			return "缺少工具"
		"scene_transition_world_flag_missing":
			return "缺少世界状态"
		"scene_transition_world_flag_blocked":
			return "世界状态阻止"
		"scene_transition_location_locked":
			return "地点未解锁"
		"scene_transition_location_blocked":
			return "地点已被封锁"
		"interaction_option_unavailable":
			return "不可用"
	if reason.is_empty():
		return "不可用"
	return _reason_catalog.disabled_text_for(reason)


func _number_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value


func _percent_text(value: float) -> String:
	return "%d%%" % int(round(value * 100.0))


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
