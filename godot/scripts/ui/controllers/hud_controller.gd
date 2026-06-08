extends Control

const MediaTextureLoader = preload("res://scripts/ui/media_texture_loader.gd")
const ReasonCatalog = preload("res://scripts/ui/snapshots/reason_catalog.gd")

var _world_label: Label
var _status_badge_label: Label
var _player_label: Label
var _inventory_label: Label
var _quest_label: Label
var _combat_hud_label: Label
var _hotbar_group_box: HBoxContainer
var _hotbar_box: HBoxContainer
var _observe_hotbar_box: HBoxContainer
var _interaction_label: Label
var _event_feedback_label: Label
var _feedback_toast_layer: VBoxContainer
var _debug_overlay_label: Label
var _info_panel_label: Label
var _runtime_control_label: Label
var _skill_targeting_label: Label
var _controls_hint_box: VBoxContainer
var _interaction_menu: PanelContainer
var _menu_title_label: Label
var _menu_summary_label: Label
var _menu_hover_label: Label
var _menu_options_box: VBoxContainer
var _debug_console: PanelContainer
var _console_history_label: Label
var _console_suggestions_label: Label
var _console_input: LineEdit
var _debug_panel: PanelContainer
var _debug_panel_title_label: Label
var _debug_panel_lines_box: VBoxContainer
var controls_hint_visible := false
var console_visible := false
var debug_panel_visible := false
var debug_panel_latest_snapshot: Dictionary = {}
var interaction_menu_snapshot_data: Dictionary = {}
var console_history: Array[String] = []
var console_command_history: Array[String] = []
var _reason_catalog := ReasonCatalog.new()
var console_history_index := -1
var console_command_schema: Array[Dictionary] = []
var console_permission: Dictionary = {}
var console_suggestions: Array[String] = [
	"help",
	"show fps",
	"show overlays",
	"observe mode",
	"clear",
	"restart",
	"give item 1006 1",
	"teleport 0 0 0",
	"spawn zombie_walker",
	"unlock location forest",
]


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()


func apply_snapshot(snapshot: Dictionary) -> void:
	if _world_label == null:
		_build_layout()

	var world: Dictionary = snapshot.get("world", {})
	var player: Dictionary = snapshot.get("player", {})
	var map: Dictionary = snapshot.get("map", {})
	var interaction: Dictionary = snapshot.get("interaction", {})

	_world_label.text = "Map %s | Actors %d | Events %d | Objects %d" % [
		world.get("map_id", ""),
		int(world.get("actor_count", 0)),
		int(world.get("event_count", 0)),
		int(map.get("object_count", 0)),
	]
	_status_badge_label.text = _status_badge_text(snapshot.get("status_badges", []))
	_player_label.text = "%s @ %s" % [
		player.get("display_name", ""),
		JSON.stringify(player.get("grid_position", {})),
	]
	_inventory_label.text = "Inventory %s | Dialogue %s" % [
		_inventory_text(player.get("inventory", {})),
		player.get("active_dialogue_id", ""),
	]
	_quest_label.text = _tracked_quest_text(snapshot.get("tracked_quest", {}))
	_combat_hud_label.text = _combat_hud_text(snapshot.get("combat_hud", {}))
	_apply_hotbar(snapshot.get("hotbar", []), snapshot.get("hotbar_group_labels", {}))
	_apply_observe_hotbar(snapshot.get("runtime_control", {}))
	_interaction_label.text = _interaction_text(interaction)
	_event_feedback_label.text = _event_feedback_text(snapshot.get("event_feedback", []))
	_apply_feedback_toasts(snapshot.get("feedback_toasts", []))
	_debug_overlay_label.text = "Overlay %s" % str(snapshot.get("debug_overlay_mode", "off"))
	_info_panel_label.text = _info_panel_text(snapshot.get("info_panel", {}))
	_runtime_control_label.text = _runtime_control_text(snapshot.get("runtime_control", {}))
	_skill_targeting_label.text = _skill_targeting_text(_dictionary_or_empty(snapshot.get("runtime_control", {})).get("skill_targeting", {}))
	_skill_targeting_label.visible = not _skill_targeting_label.text.is_empty()
	_apply_controls_hint()
	_apply_interaction_menu(interaction)
	_apply_debug_panel(snapshot)


func _build_layout() -> void:
	if _world_label != null:
		return

	var panel := PanelContainer.new()
	panel.name = "HudPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 16
	panel.offset_top = 16
	panel.offset_right = 560
	panel.offset_bottom = 184
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var box := VBoxContainer.new()
	box.name = "HudLines"
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	_world_label = _line("WorldLine")
	_status_badge_label = _line("StatusBadgeLine")
	_player_label = _line("PlayerLine")
	_inventory_label = _line("InventoryLine")
	_quest_label = _line("QuestLine")
	_combat_hud_label = _line("CombatHudLine")
	_hotbar_group_box = HBoxContainer.new()
	_hotbar_group_box.name = "HotbarGroupBar"
	_hotbar_group_box.add_theme_constant_override("separation", 4)
	_hotbar_box = HBoxContainer.new()
	_hotbar_box.name = "HotbarDock"
	_hotbar_box.add_theme_constant_override("separation", 4)
	_observe_hotbar_box = HBoxContainer.new()
	_observe_hotbar_box.name = "ObserveHotbarDock"
	_observe_hotbar_box.add_theme_constant_override("separation", 4)
	_interaction_label = _line("InteractionLine")
	_event_feedback_label = _line("EventFeedbackLine")
	_debug_overlay_label = _line("DebugOverlayLine")
	_info_panel_label = _line("InfoPanelLine")
	_runtime_control_label = _line("RuntimeControlLine")
	_skill_targeting_label = _line("SkillTargetingLine")
	box.add_child(_world_label)
	box.add_child(_status_badge_label)
	box.add_child(_player_label)
	box.add_child(_inventory_label)
	box.add_child(_quest_label)
	box.add_child(_combat_hud_label)
	box.add_child(_hotbar_group_box)
	box.add_child(_hotbar_box)
	box.add_child(_observe_hotbar_box)
	box.add_child(_interaction_label)
	box.add_child(_event_feedback_label)
	box.add_child(_debug_overlay_label)
	box.add_child(_info_panel_label)
	box.add_child(_runtime_control_label)
	box.add_child(_skill_targeting_label)
	_controls_hint_box = VBoxContainer.new()
	_controls_hint_box.name = "ControlsHint"
	_controls_hint_box.add_theme_constant_override("separation", 3)
	_controls_hint_box.visible = false
	box.add_child(_controls_hint_box)
	for line in [
		"I/C/M/J/K/L 面板 | Esc 关闭/设置 | Space 等待",
		"1-9 对话选项 | 1-0 热栏 | Alt+1/2/3 热栏组 | 鼠标左键移动/交互",
		"右键菜单 | 中键拖拽相机 | F 跟随 | V 覆盖层 | F3 调试面板 | [/] 信息页 | A 自动推进 | +/- 缩放",
	]:
		var label := _line("ControlsHintLine")
		label.text = line
		_controls_hint_box.add_child(label)
	_build_interaction_menu()
	_build_feedback_toast_layer()
	_build_debug_console()
	_build_debug_panel()


func toggle_controls_hint() -> Dictionary:
	controls_hint_visible = not controls_hint_visible
	_apply_controls_hint()
	return {"success": true, "visible": controls_hint_visible}


func is_controls_hint_visible() -> bool:
	return controls_hint_visible


func controls_hint_snapshot() -> Dictionary:
	var lines: Array[String] = []
	if _controls_hint_box != null:
		for child in _controls_hint_box.get_children():
			if child is Label:
				lines.append(str((child as Label).text))
	return {
		"visible": controls_hint_visible,
		"line_count": lines.size(),
		"lines": lines,
	}


func toggle_debug_panel() -> Dictionary:
	debug_panel_visible = not debug_panel_visible
	_apply_debug_panel(debug_panel_latest_snapshot)
	return {"success": true, "visible": debug_panel_visible}


func hide_debug_panel() -> void:
	debug_panel_visible = false
	_apply_debug_panel(debug_panel_latest_snapshot)


func is_debug_panel_open() -> bool:
	return debug_panel_visible


func debug_panel_snapshot() -> Dictionary:
	return {
		"visible": debug_panel_visible,
		"line_count": _debug_panel_line_texts().size(),
		"lines": _debug_panel_line_texts(),
	}


func toggle_debug_console() -> Dictionary:
	console_visible = not console_visible
	_apply_debug_console()
	if console_visible and _console_input != null:
		_console_input.grab_focus()
	return {"success": true, "visible": console_visible}


func hide_debug_console() -> void:
	console_visible = false
	_apply_debug_console()


func is_debug_console_open() -> bool:
	return console_visible


func debug_console_snapshot() -> Dictionary:
	return {
		"visible": console_visible,
		"history": console_history.duplicate(),
		"history_count": console_history.size(),
		"command_history": console_command_history.duplicate(),
		"command_history_count": console_command_history.size(),
		"history_index": console_history_index,
		"command_schema": console_command_schema.duplicate(true),
		"command_schema_count": console_command_schema.size(),
		"command_details": _console_command_detail_lines(),
		"permission": console_permission.duplicate(true),
		"suggestions": console_suggestions.duplicate(),
		"suggestion_count": console_suggestions.size(),
		"input_text": _console_input.text if _console_input != null else "",
	}


func console_input_node() -> LineEdit:
	return _console_input


func set_debug_console_schema(schema: Array, suggestions: Array, permission: Dictionary = {}) -> void:
	console_command_schema.clear()
	for command in schema:
		var command_data: Dictionary = _dictionary_or_empty(command)
		if not command_data.is_empty():
			console_command_schema.append(command_data.duplicate(true))
	console_permission = permission.duplicate(true)
	var normalized_suggestions: Array[String] = []
	for suggestion in suggestions:
		var suggestion_text := str(suggestion).strip_edges()
		if not suggestion_text.is_empty() and not normalized_suggestions.has(suggestion_text):
			normalized_suggestions.append(suggestion_text)
	if not normalized_suggestions.is_empty():
		console_suggestions = normalized_suggestions
	_apply_debug_console()


func set_debug_console_result(command_text: String, result: Dictionary) -> void:
	var status := "ok" if bool(result.get("success", false)) else "err"
	var message := str(result.get("message", result.get("reason", "")))
	console_history.append("> %s" % command_text)
	console_history.append("%s: %s" % [status, message])
	_record_console_command(command_text)
	while console_history.size() > 8:
		console_history.pop_front()
	if _console_input != null:
		_console_input.text = ""
	_apply_debug_console()


func clear_debug_console_history() -> void:
	console_history.clear()
	_apply_debug_console()


func _record_console_command(command_text: String) -> void:
	var normalized := command_text.strip_edges()
	if normalized.is_empty():
		console_history_index = -1
		return
	if console_command_history.is_empty() or console_command_history[console_command_history.size() - 1] != normalized:
		console_command_history.append(normalized)
	while console_command_history.size() > 16:
		console_command_history.pop_front()
	console_history_index = -1


func show_interaction_menu(screen_position: Vector2, prompt: Dictionary) -> void:
	if _interaction_menu == null:
		_build_interaction_menu()
	var menu_prompt := _prompt_summary_for_menu(prompt)
	_apply_interaction_menu(menu_prompt)
	_interaction_menu.visible = bool(prompt.get("ok", prompt.get("has_target", false)))
	_interaction_menu.mouse_filter = Control.MOUSE_FILTER_STOP if _interaction_menu.visible else Control.MOUSE_FILTER_IGNORE
	_interaction_menu.position = _menu_position(screen_position)
	interaction_menu_snapshot_data = _interaction_menu_snapshot_from_prompt(menu_prompt, _interaction_menu.visible, _interaction_menu.position)


func hide_interaction_menu() -> void:
	if _interaction_menu == null:
		return
	_interaction_menu.visible = false
	_interaction_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_menu_snapshot_data = {}


func is_interaction_menu_open() -> bool:
	return _interaction_menu != null and _interaction_menu.visible


func interaction_menu_snapshot() -> Dictionary:
	if _interaction_menu == null or not _interaction_menu.visible:
		return {}
	var snapshot := interaction_menu_snapshot_data.duplicate(true)
	if snapshot.is_empty():
		snapshot = {
			"id": "interaction_menu",
			"name": "interaction_menu",
			"kind": "interaction",
			"owner_panel": "hud",
		}
	snapshot["active"] = true
	snapshot["visible"] = true
	snapshot["mouse_blocks_world"] = _interaction_menu.mouse_filter == Control.MOUSE_FILTER_STOP
	snapshot["position"] = {"x": _interaction_menu.position.x, "y": _interaction_menu.position.y}
	return snapshot


func _line(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = true
	return label


func _build_feedback_toast_layer() -> void:
	if _feedback_toast_layer != null:
		return
	_feedback_toast_layer = VBoxContainer.new()
	_feedback_toast_layer.name = "FeedbackToastLayer"
	_feedback_toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback_toast_layer.add_theme_constant_override("separation", 4)
	_feedback_toast_layer.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_feedback_toast_layer.offset_left = 16
	_feedback_toast_layer.offset_top = 188
	_feedback_toast_layer.offset_right = 560
	_feedback_toast_layer.offset_bottom = 308
	add_child(_feedback_toast_layer)


func _apply_feedback_toasts(value: Variant) -> void:
	if _feedback_toast_layer == null:
		_build_feedback_toast_layer()
	_clear_children(_feedback_toast_layer)
	var toasts: Array = _array_or_empty(value)
	_feedback_toast_layer.visible = not toasts.is_empty()
	for toast_value in toasts:
		var toast: Dictionary = _dictionary_or_empty(toast_value)
		if toast.is_empty() or not bool(toast.get("visible", true)):
			continue
		_feedback_toast_layer.add_child(_feedback_toast_row(toast))


func _feedback_toast_row(toast: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.name = "FeedbackToast_%s" % str(toast.get("id", "toast"))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(260, 28)
	var severity := str(toast.get("severity", "info"))
	var alpha := float(toast.get("alpha", 1.0))
	var phase := str(toast.get("phase", "visible"))
	row.add_theme_stylebox_override("panel", _feedback_toast_style(severity, alpha, phase))
	row.modulate.a = clampf(alpha + 0.12, 0.0, 1.0)
	_apply_feedback_toast_metadata(row, toast)
	row.set_meta("toast_visual_kind", "panel")
	row.set_meta("toast_border_color", _feedback_toast_border_color(severity).to_html())
	row.set_meta("toast_background_alpha", alpha)
	row.set_meta("toast_minimum_width", row.custom_minimum_size.x)
	var label := _line("FeedbackToastLabel")
	label.text = str(toast.get("text", ""))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.modulate = _feedback_toast_color(severity, 1.0)
	label.tooltip_text = "%s | %s" % [severity, str(_dictionary_or_empty(toast.get("transition", {})).get("style", ""))]
	_apply_feedback_toast_metadata(label, toast)
	row.add_child(label)
	return row


func _apply_feedback_toast_metadata(node: Node, toast: Dictionary) -> void:
	node.set_meta("toast_id", str(toast.get("id", "")))
	node.set_meta("toast_kind", str(toast.get("kind", "")))
	node.set_meta("toast_severity", str(toast.get("severity", "")))
	node.set_meta("toast_phase", str(toast.get("phase", "")))
	node.set_meta("toast_slot", int(toast.get("slot", 0)))
	node.set_meta("toast_alpha", float(toast.get("alpha", 1.0)))
	node.set_meta("toast_ttl_events", int(toast.get("ttl_events", 0)))
	node.set_meta("toast_age_events", int(toast.get("age_events", 0)))
	node.set_meta("toast_transition_style", str(_dictionary_or_empty(toast.get("transition", {})).get("style", "")))


func _feedback_toast_style(severity: String, alpha: float, phase: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var background_alpha := clampf(0.58 * alpha, 0.18, 0.72)
	if phase == "fading":
		background_alpha = clampf(0.42 * alpha, 0.12, 0.56)
	style.bg_color = _feedback_toast_background_color(severity, background_alpha)
	style.border_color = _feedback_toast_border_color(severity)
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


func _feedback_toast_background_color(severity: String, alpha: float) -> Color:
	match severity:
		"success":
			return Color(0.08, 0.20, 0.13, alpha)
		"warning":
			return Color(0.22, 0.17, 0.06, alpha)
		"error":
			return Color(0.24, 0.09, 0.08, alpha)
		_:
			return Color(0.08, 0.12, 0.18, alpha)


func _feedback_toast_border_color(severity: String) -> Color:
	match severity:
		"success":
			return Color(0.33, 0.72, 0.43, 1.0)
		"warning":
			return Color(0.90, 0.66, 0.20, 1.0)
		"error":
			return Color(0.86, 0.34, 0.30, 1.0)
		_:
			return Color(0.38, 0.55, 0.74, 1.0)


func _feedback_toast_color(severity: String, alpha: float) -> Color:
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


func _build_interaction_menu() -> void:
	if _interaction_menu != null:
		return
	_interaction_menu = PanelContainer.new()
	_interaction_menu.name = "InteractionMenu"
	_interaction_menu.visible = false
	_interaction_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interaction_menu.custom_minimum_size = Vector2(180, 32)
	add_child(_interaction_menu)

	var box := VBoxContainer.new()
	box.name = "MenuLines"
	box.add_theme_constant_override("separation", 4)
	_interaction_menu.add_child(box)

	_menu_title_label = _line("MenuTitle")
	_menu_summary_label = _line("MenuSummary")
	_menu_hover_label = _line("MenuHoverHint")
	_menu_options_box = VBoxContainer.new()
	_menu_options_box.name = "MenuOptions"
	_menu_options_box.add_theme_constant_override("separation", 3)
	box.add_child(_menu_title_label)
	box.add_child(_menu_summary_label)
	box.add_child(_menu_options_box)
	box.add_child(_menu_hover_label)


func _build_debug_console() -> void:
	if _debug_console != null:
		return
	_debug_console = PanelContainer.new()
	_debug_console.name = "DebugConsole"
	_debug_console.visible = false
	_debug_console.mouse_filter = Control.MOUSE_FILTER_STOP
	_debug_console.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_debug_console.offset_left = 16
	_debug_console.offset_right = -16
	_debug_console.offset_top = -142
	_debug_console.offset_bottom = -16
	add_child(_debug_console)

	var box := VBoxContainer.new()
	box.name = "ConsoleLines"
	box.add_theme_constant_override("separation", 4)
	_debug_console.add_child(box)

	_console_history_label = _line("ConsoleHistory")
	_console_suggestions_label = _line("ConsoleSuggestions")
	_console_input = LineEdit.new()
	_console_input.name = "ConsoleInput"
	_console_input.placeholder_text = "debug command"
	_console_input.focus_mode = Control.FOCUS_ALL
	_console_input.text_submitted.connect(func(text: String) -> void:
		var root := get_tree().current_scene
		if root != null and root.has_method("submit_debug_console_command"):
			root.submit_debug_console_command(text)
	)
	_console_input.gui_input.connect(func(event: InputEvent) -> void:
		_handle_console_input_event(event)
	)
	box.add_child(_console_history_label)
	box.add_child(_console_suggestions_label)
	box.add_child(_console_input)


func _build_debug_panel() -> void:
	if _debug_panel != null:
		return
	_debug_panel = PanelContainer.new()
	_debug_panel.name = "DebugPanel"
	_debug_panel.visible = false
	_debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_panel.offset_left = -444
	_debug_panel.offset_right = -16
	_debug_panel.offset_top = 16
	_debug_panel.offset_bottom = 300
	add_child(_debug_panel)

	var box := VBoxContainer.new()
	box.name = "DebugPanelLines"
	box.add_theme_constant_override("separation", 4)
	_debug_panel.add_child(box)

	_debug_panel_title_label = _line("DebugPanelTitle")
	_debug_panel_title_label.text = "Debug Panel"
	box.add_child(_debug_panel_title_label)
	_debug_panel_lines_box = VBoxContainer.new()
	_debug_panel_lines_box.name = "DebugPanelContent"
	_debug_panel_lines_box.add_theme_constant_override("separation", 3)
	box.add_child(_debug_panel_lines_box)


func _handle_console_input_event(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var key := key_event.keycode
	if key == 0:
		key = key_event.physical_keycode
	if key == KEY_UP:
		_recall_console_history(-1)
		accept_event()
	elif key == KEY_DOWN:
		_recall_console_history(1)
		accept_event()
	elif key == KEY_TAB:
		_autocomplete_console_input()
		accept_event()


func _recall_console_history(direction: int) -> void:
	if _console_input == null or console_command_history.is_empty():
		return
	if console_history_index < 0:
		console_history_index = console_command_history.size()
	console_history_index = clampi(console_history_index + direction, 0, console_command_history.size())
	if console_history_index >= console_command_history.size():
		_console_input.text = ""
	else:
		_console_input.text = console_command_history[console_history_index]
	_console_input.caret_column = _console_input.text.length()


func _autocomplete_console_input() -> void:
	if _console_input == null:
		return
	var prefix := _console_input.text.strip_edges().to_lower()
	var matches: Array[String] = []
	for suggestion in console_suggestions:
		if str(suggestion).begins_with(prefix):
			matches.append(str(suggestion))
	if matches.is_empty():
		return
	var replacement := matches[0] if matches.size() == 1 else _shared_prefix(matches)
	if replacement.length() <= prefix.length():
		replacement = matches[0]
	_console_input.text = replacement
	_console_input.caret_column = _console_input.text.length()


func _shared_prefix(values: Array[String]) -> String:
	if values.is_empty():
		return ""
	var prefix := values[0]
	for value in values:
		while not str(value).begins_with(prefix) and not prefix.is_empty():
			prefix = prefix.substr(0, prefix.length() - 1)
	return prefix


func _apply_debug_console() -> void:
	if _debug_console == null:
		return
	_debug_console.visible = console_visible
	_debug_console.mouse_filter = Control.MOUSE_FILTER_STOP if console_visible else Control.MOUSE_FILTER_IGNORE
	if _console_history_label != null:
		_console_history_label.text = "\n".join(console_history)
	if _console_suggestions_label != null:
		_console_suggestions_label.text = _debug_console_help_text()
	if not console_visible and _console_input != null:
		_console_input.release_focus()


func _debug_console_help_text() -> String:
	var details := _console_command_detail_lines()
	if not details.is_empty():
		var shown := details.slice(0, mini(details.size(), 5))
		var suffix := " | ..." if details.size() > shown.size() else ""
		return "commands: %s%s" % [" | ".join(shown), suffix]
	return "suggestions: %s" % ", ".join(console_suggestions)


func _console_command_detail_lines() -> Array[String]:
	var lines: Array[String] = []
	for command in console_command_schema:
		var usage := str(command.get("usage", "")).strip_edges()
		if usage.is_empty():
			continue
		var description := str(command.get("description", "")).strip_edges()
		lines.append("%s - %s" % [usage, description] if not description.is_empty() else usage)
	return lines


func _apply_debug_panel(snapshot: Dictionary) -> void:
	debug_panel_latest_snapshot = snapshot.duplicate(true)
	if _debug_panel == null:
		return
	_debug_panel.visible = debug_panel_visible
	_debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _debug_panel_title_label != null:
		_debug_panel_title_label.text = "Debug Panel | F3 | %s" % ("on" if debug_panel_visible else "off")
	if _debug_panel_lines_box == null:
		return
	for child in _debug_panel_lines_box.get_children():
		child.queue_free()
	for entry in _debug_panel_entries(snapshot):
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var label := _line("DebugPanelLine_%s" % str(entry_data.get("kind", "entry")))
		label.text = str(entry_data.get("text", ""))
		label.tooltip_text = str(entry_data.get("tooltip", label.text))
		label.set_meta("debug_panel_kind", str(entry_data.get("kind", "")))
		label.set_meta("debug_panel_text", label.text)
		_debug_panel_lines_box.add_child(label)


func _debug_panel_entries(snapshot: Dictionary) -> Array[Dictionary]:
	var runtime_control: Dictionary = _dictionary_or_empty(snapshot.get("runtime_control", {}))
	var info_panel: Dictionary = _dictionary_or_empty(snapshot.get("info_panel", {}))
	var debug_overlay: Dictionary = _dictionary_or_empty(runtime_control.get("debug_overlay", {}))
	var console: Dictionary = _dictionary_or_empty(runtime_control.get("debug_console", {}))
	return [
		{"kind": "overlay", "text": "Overlay: %s | active %s | cells %d" % [
			str(debug_overlay.get("mode", snapshot.get("debug_overlay_mode", "off"))),
			"yes" if bool(debug_overlay.get("active", false)) else "no",
			int(debug_overlay.get("cell_count", 0)),
		]},
		{"kind": "info", "text": _info_panel_text(info_panel)},
		{"kind": "runtime", "text": _debug_panel_runtime_text(runtime_control)},
		{"kind": "hover", "text": _hover_control_text(runtime_control.get("hover", {})) if not _hover_control_text(runtime_control.get("hover", {})).is_empty() else "Hover none"},
		{"kind": "selection", "text": _selection_debug_control_text(runtime_control.get("selection_debug", {})) if not _selection_debug_control_text(runtime_control.get("selection_debug", {})).is_empty() else "Sel none"},
		{"kind": "ai", "text": _ai_debug_control_text(runtime_control.get("ai_debug", {})) if not _ai_debug_control_text(runtime_control.get("ai_debug", {})).is_empty() else "AI none"},
		{"kind": "performance", "text": _performance_control_text(runtime_control.get("performance", {})) if not _performance_control_text(runtime_control.get("performance", {})).is_empty() else "Perf none"},
		{"kind": "console", "text": _debug_panel_console_text(console)},
	]


func _debug_panel_console_text(console: Dictionary) -> String:
	var permission: Dictionary = _dictionary_or_empty(console.get("permission", {}))
	return "Console %s | history %d | suggestions %d | schema %d | mutate %s" % [
		"on" if bool(console.get("visible", false)) else "off",
		int(console.get("history_count", 0)),
		int(console.get("suggestion_count", 0)),
		int(console.get("command_schema_count", 0)),
		"on" if bool(permission.get("allow_runtime_mutation", true)) else "off",
	]


func _debug_panel_runtime_text(runtime_control: Dictionary) -> String:
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
		parts.append(_tooltip_runtime_token(tooltip))
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


func _debug_panel_line_texts() -> Array[String]:
	var lines: Array[String] = []
	if _debug_panel_lines_box == null:
		return lines
	for child in _debug_panel_lines_box.get_children():
		if child is Label:
			lines.append(str((child as Label).text))
	return lines


func _apply_interaction_menu(interaction: Dictionary) -> void:
	if _interaction_menu == null:
		_build_interaction_menu()
	var has_target: bool = bool(interaction.get("has_target", false))
	if not has_target:
		_clear_menu_options()
		_menu_summary_label.text = ""
		_menu_hover_label.text = ""
		return
	_menu_title_label.text = str(interaction.get("target_name", "目标"))
	_menu_summary_label.text = _interaction_menu_summary(interaction)
	_menu_hover_label.text = "悬停查看动作详情"
	_clear_menu_options()
	for option in interaction.get("options", []):
		var option_data: Dictionary = option
		_menu_options_box.add_child(_option_button(option_data))
	for option in interaction.get("disabled_options", []):
		var option_data: Dictionary = option
		_menu_options_box.add_child(_disabled_option_button(option_data))


func _apply_controls_hint() -> void:
	if _controls_hint_box == null:
		return
	_controls_hint_box.visible = controls_hint_visible


func _option_button(option: Dictionary) -> Button:
	var button := Button.new()
	button.name = "Option_%s" % str(option.get("id", "unknown"))
	button.text = str(option.get("display_name", option.get("id", "")))
	button.tooltip_text = _option_tooltip(option)
	button.custom_minimum_size = Vector2(160, 28)
	button.focus_mode = Control.FOCUS_NONE
	button.set_meta("option_id", str(option.get("id", "")))
	button.set_meta("option_kind", str(option.get("kind", "")))
	button.set_meta("display_name", str(option.get("display_name", option.get("id", ""))))
	button.set_meta("disabled", false)
	button.set_meta("disabled_reason", "")
	button.set_meta("ap_cost", float(option.get("ap_cost", 0.0)))
	button.set_meta("interaction_range", int(option.get("interaction_range", 0)))
	button.mouse_entered.connect(func() -> void:
		_menu_hover_label.text = _option_hover_text(option)
	)
	var option_id := str(option.get("id", ""))
	button.pressed.connect(func() -> void:
		var root := get_parent()
		if root != null and root.has_method("execute_interaction_option"):
			root.execute_interaction_option(option_id)
		hide_interaction_menu()
	)
	return button


func _disabled_option_button(option: Dictionary) -> Button:
	var button := Button.new()
	var option_id := str(option.get("id", "unknown"))
	var reason := str(option.get("disabled_reason", "interaction_option_unavailable"))
	var reason_text := _disabled_reason_text(reason)
	button.name = "DisabledOption_%s" % option_id
	button.text = "%s - %s" % [
		str(option.get("display_name", option_id)),
		reason_text,
	]
	button.tooltip_text = _disabled_option_tooltip(option, reason_text)
	button.custom_minimum_size = Vector2(160, 28)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = true
	button.set_meta("option_id", option_id)
	button.set_meta("option_kind", str(option.get("kind", "")))
	button.set_meta("display_name", str(option.get("display_name", option_id)))
	button.set_meta("disabled", true)
	button.set_meta("disabled_reason", reason)
	button.set_meta("disabled_reason_text", reason_text)
	button.set_meta("ap_cost", float(option.get("ap_cost", 0.0)))
	button.set_meta("interaction_range", int(option.get("interaction_range", 0)))
	button.mouse_entered.connect(func() -> void:
		_menu_hover_label.text = _option_hover_text(option)
	)
	return button


func _option_tooltip(option: Dictionary) -> String:
	var parts: Array[String] = [
		"%s (%s)" % [str(option.get("display_name", option.get("id", ""))), str(option.get("kind", ""))],
	]
	var ap_cost := float(option.get("ap_cost", 0.0))
	if ap_cost > 0.0:
		parts.append("AP %.0f" % ap_cost)
	if bool(option.get("disabled", false)):
		parts.append(_disabled_reason_text(str(option.get("disabled_reason", ""))))
	return " | ".join(parts)


func _disabled_option_tooltip(option: Dictionary, reason_text: String) -> String:
	var tooltip := _option_tooltip(option)
	if reason_text.is_empty():
		return tooltip
	if tooltip.contains(reason_text):
		return tooltip
	return "%s | %s" % [tooltip, reason_text]


func _interaction_menu_summary(interaction: Dictionary) -> String:
	var enabled_count: int = _array_or_empty(interaction.get("options", [])).size()
	var disabled_count: int = _array_or_empty(interaction.get("disabled_options", [])).size()
	var primary := str(interaction.get("primary_option_id", ""))
	return "主动作 %s | 可用 %d | 禁用 %d" % [
		primary if not primary.is_empty() else "-",
		enabled_count,
		disabled_count,
	]


func _interaction_menu_snapshot_from_prompt(interaction: Dictionary, visible: bool, position: Vector2) -> Dictionary:
	var options: Array = _array_or_empty(interaction.get("options", []))
	var disabled_options: Array = _array_or_empty(interaction.get("disabled_options", []))
	return {
		"id": "interaction_menu",
		"name": "interaction_menu",
		"kind": "interaction",
		"owner_panel": "hud",
		"active": visible,
		"visible": visible,
		"mouse_blocks_world": visible,
		"position": {"x": position.x, "y": position.y},
		"target_id": str(interaction.get("target_id", "")),
		"target_name": str(interaction.get("target_name", "")),
		"target_type": str(interaction.get("target_type", "")),
		"primary_option_id": str(interaction.get("primary_option_id", "")),
		"option_count": options.size(),
		"disabled_option_count": disabled_options.size(),
		"options": _context_option_summaries(options),
		"disabled_options": _context_option_summaries(disabled_options),
		"option_details": _context_option_detail_map(options, disabled_options),
	}


func _context_option_summaries(options: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for option in options:
		var data: Dictionary = _dictionary_or_empty(option)
		if data.is_empty():
			continue
		output.append({
			"id": str(data.get("id", "")),
			"kind": str(data.get("kind", "")),
			"display_name": str(data.get("display_name", data.get("id", ""))),
			"disabled": bool(data.get("disabled", false)),
			"disabled_reason": str(data.get("disabled_reason", "")),
			"disabled_reason_text": _disabled_reason_text(str(data.get("disabled_reason", ""))) if not str(data.get("disabled_reason", "")).is_empty() else "",
			"ap_cost": float(data.get("ap_cost", 0.0)),
		})
	return output


func _context_option_detail_map(options: Array, disabled_options: Array) -> Dictionary:
	var output: Dictionary = {}
	for option in options:
		var data: Dictionary = _dictionary_or_empty(option)
		var option_id := str(data.get("id", ""))
		if option_id.is_empty():
			continue
		output[option_id] = _context_option_detail(data, true)
	for option in disabled_options:
		var data: Dictionary = _dictionary_or_empty(option)
		var option_id := str(data.get("id", ""))
		if option_id.is_empty():
			continue
		output[option_id] = _context_option_detail(data, false)
	return output


func _context_option_detail(option: Dictionary, enabled: bool) -> Dictionary:
	var disabled_reason := str(option.get("disabled_reason", ""))
	return {
		"id": str(option.get("id", "")),
		"kind": str(option.get("kind", "")),
		"display_name": str(option.get("display_name", option.get("id", ""))),
		"enabled": enabled,
		"disabled": not enabled or bool(option.get("disabled", false)),
		"disabled_reason": disabled_reason,
		"disabled_reason_text": _disabled_reason_text(disabled_reason) if not disabled_reason.is_empty() else "",
		"ap_cost": float(option.get("ap_cost", 0.0)),
		"interaction_range": int(option.get("interaction_range", 0)),
		"tooltip": _option_tooltip(option),
		"hover_text": _option_hover_text(option),
	}


func _option_hover_text(option: Dictionary) -> String:
	var parts: Array[String] = [
		str(option.get("display_name", option.get("id", ""))),
		"kind=%s" % str(option.get("kind", "")),
	]
	var ap_cost := float(option.get("ap_cost", 0.0))
	if ap_cost > 0.0:
		parts.append("AP %.0f" % ap_cost)
	var reason := str(option.get("disabled_reason", ""))
	if bool(option.get("disabled", false)) or not reason.is_empty():
		parts.append("禁用: %s" % _disabled_reason_text(reason))
	return " | ".join(parts)


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


func _apply_hotbar(slots_value: Variant, group_labels_value: Variant = {}) -> void:
	if _hotbar_box == null:
		return
	for child in _hotbar_box.get_children():
		_hotbar_box.remove_child(child)
		child.free()
	var slots: Array = slots_value if typeof(slots_value) == TYPE_ARRAY else []
	if slots.is_empty():
		for slot_index in range(1, 11):
			slots.append({
				"slot_id": "slot_%d" % slot_index,
				"group_id": "group_1",
				"group_label": "G1",
				"key": "0" if slot_index == 10 else str(slot_index),
				"empty": true,
			})
	var group_labels: Dictionary = _dictionary_or_empty(group_labels_value)
	_apply_hotbar_group_buttons(slots, group_labels)
	for slot in slots:
		var slot_data: Dictionary = slot
		_hotbar_box.add_child(_hotbar_button(slot_data))


func _apply_hotbar_group_buttons(slots: Array, group_labels: Dictionary = {}) -> void:
	if _hotbar_group_box == null:
		return
	for child in _hotbar_group_box.get_children():
		_hotbar_group_box.remove_child(child)
		child.free()
	var active_group_id := _active_hotbar_group_id(slots)
	for index in range(1, 4):
		var group_id := "group_%d" % index
		_hotbar_group_box.add_child(_hotbar_group_button(group_id, active_group_id, group_labels))


func _active_hotbar_group_id(slots: Array) -> String:
	for slot in slots:
		var slot_data: Dictionary = _dictionary_or_empty(slot)
		var group_id := str(slot_data.get("group_id", ""))
		if not group_id.is_empty():
			return group_id
	return "group_1"


func _hotbar_group_button(group_id: String, active_group_id: String, group_labels: Dictionary = {}) -> Button:
	var button := Button.new()
	var group_label := _hotbar_group_label(group_id, group_labels)
	button.name = "HotbarGroup_%s" % group_id
	button.text = group_label
	button.tooltip_text = "%s 热栏组 | Alt+%d" % [group_label, max(1, _hotbar_group_index(group_id) + 1)]
	button.toggle_mode = true
	button.button_pressed = group_id == active_group_id
	button.custom_minimum_size = Vector2(max(38, group_label.length() * 10 + 18), 26)
	button.focus_mode = Control.FOCUS_NONE
	button.set_meta("hotbar_group_id", group_id)
	button.set_meta("active", group_id == active_group_id)
	button.set_drag_forwarding(
		Callable(self, "_empty_hotbar_drag_data"),
		Callable(self, "_can_drop_hotbar_group"),
		Callable(self, "_drop_hotbar_group")
	)
	_prepare_hotbar_group_drop_target(button)
	button.pressed.connect(func() -> void:
		var root := get_parent()
		if root != null and root.has_method("set_hotbar_group"):
			root.call_deferred("set_hotbar_group", group_id)
	)
	return button


func _hotbar_group_label(group_id: String, group_labels: Dictionary = {}) -> String:
	var configured_label := str(group_labels.get(group_id, "")).strip_edges()
	if not configured_label.is_empty():
		return configured_label
	var value := group_id.strip_edges().to_lower()
	if value.begins_with("group_"):
		value = value.trim_prefix("group_")
	if value.is_valid_int():
		return "G%d" % int(value)
	return group_id


func _hotbar_group_index(group_id: String) -> int:
	var value := group_id.strip_edges().to_lower()
	if value.begins_with("group_"):
		value = value.trim_prefix("group_")
	if not value.is_valid_int():
		return -1
	return int(value) - 1


func _hotbar_button(slot: Dictionary) -> Button:
	var button := Button.new()
	var slot_id := str(slot.get("slot_id", ""))
	var group_id := str(slot.get("group_id", "group_1"))
	var group_label := str(slot.get("group_label", group_id))
	var key_label := str(slot.get("key", ""))
	var kind := str(slot.get("kind", ""))
	var skill_id := str(slot.get("skill_id", ""))
	var item_id := str(slot.get("item_id", ""))
	var entry_id := item_id if kind == "item" else skill_id
	var entry_label := str(slot.get("label", entry_id))
	var cooldown := float(slot.get("cooldown_remaining", 0.0))
	var use_reason := str(slot.get("use_reason", ""))
	var can_use := bool(slot.get("can_use", true))
	button.name = "HotbarSlot_%s" % slot_id
	button.custom_minimum_size = Vector2(48, 28)
	button.focus_mode = Control.FOCUS_NONE
	button.set_meta("hotbar_slot_id", slot_id)
	button.set_meta("hotbar_group_id", group_id)
	button.set_meta("cooldown_remaining", cooldown)
	button.set_meta("cooldown_mask_visible", cooldown > 0.0)
	button.set_meta("use_reason", use_reason)
	button.set_meta("can_use", can_use)
	_apply_hotbar_icon(button, slot)
	button.set_drag_forwarding(
		Callable(self, "_empty_hotbar_drag_data"),
		Callable(self, "_can_drop_hotbar_skill"),
		Callable(self, "_drop_hotbar_skill")
	)
	_prepare_hotbar_drop_target(button)
	if bool(slot.get("empty", true)):
		button.text = "%s:-" % key_label
		button.tooltip_text = "%s 热栏 %s：空 | 可拖入主动技能" % [group_label, key_label]
		return button
	var suffix := " cd%.0f" % cooldown if cooldown > 0.0 else ""
	if kind == "item" and int(slot.get("item_count", 0)) > 0:
		suffix = " x%d%s" % [int(slot.get("item_count", 0)), suffix]
	button.text = "%s:%s%s" % [key_label, _short_hotbar_label(entry_label), suffix]
	button.tooltip_text = _hotbar_tooltip(key_label, group_label, kind, entry_label, slot)
	button.disabled = cooldown > 0.0 or not can_use
	button.pressed.connect(func() -> void:
		var root := get_parent()
		if root != null and root.has_method("use_hotbar_slot"):
			root.use_hotbar_slot(slot_id)
	)
	_add_hotbar_cooldown_mask(button, slot_id, cooldown)
	return button


func _apply_hotbar_icon(button: Button, slot: Dictionary) -> void:
	var icon_asset := _dictionary_or_empty(slot.get("icon_asset", {}))
	var texture := MediaTextureLoader.texture_from_asset(icon_asset)
	if texture == null:
		button.icon = null
		return
	button.icon = texture
	button.expand_icon = true
	button.set_meta("icon_resource_path", MediaTextureLoader.resource_path_from_asset(icon_asset))
	button.set_meta("icon_fallback_key", str(icon_asset.get("fallback_key", "")))


func _apply_observe_hotbar(runtime_control_value: Variant) -> void:
	if _observe_hotbar_box == null:
		return
	for child in _observe_hotbar_box.get_children():
		_observe_hotbar_box.remove_child(child)
		child.free()
	var runtime_control: Dictionary = _dictionary_or_empty(runtime_control_value)
	var observe_mode := bool(runtime_control.get("observe_mode", false))
	var playback := bool(runtime_control.get("observe_playback", false))
	var speed := str(runtime_control.get("observe_speed", "x1"))
	var auto_tick := bool(runtime_control.get("auto_tick", false))
	var map_level: Dictionary = _dictionary_or_empty(runtime_control.get("map_level", {}))
	if _hotbar_group_box != null:
		_hotbar_group_box.visible = not observe_mode
	if _hotbar_box != null:
		_hotbar_box.visible = not observe_mode
	_observe_hotbar_box.add_child(_observe_mode_button(observe_mode))
	_observe_hotbar_box.add_child(_observe_play_button(playback, observe_mode))
	_observe_hotbar_box.add_child(_observe_speed_button(speed, observe_mode))
	_observe_hotbar_box.add_child(_observe_auto_button(auto_tick))
	_observe_hotbar_box.add_child(_observe_button("ObserveLevelButton", "L%d" % int(map_level.get("current", 0)), "observe_level", int(map_level.get("current", 0)), true))


func _observe_button(node_name: String, text: String, meta_key: String, meta_value: Variant, disabled: bool) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = _observe_tooltip(meta_key, meta_value, disabled)
	button.custom_minimum_size = Vector2(max(42, text.length() * 10 + 18), 26)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = disabled
	button.set_meta(meta_key, meta_value)
	button.set_meta("disabled_reason", "observe_control_unavailable" if disabled else "")
	button.set_drag_forwarding(
		Callable(self, "_empty_hotbar_drag_data"),
		Callable(self, "_can_drop_observe_hotbar"),
		Callable(self, "_drop_observe_hotbar")
	)
	_prepare_observe_hotbar_drop_target(button)
	return button


func _observe_mode_button(observe_mode: bool) -> Button:
	var button := _observe_button("ObserveModeButton", "Player" if observe_mode else "Observe", "observe_mode", observe_mode, false)
	button.pressed.connect(func() -> void:
		var root := get_parent()
		if root != null and root.has_method("toggle_observe_mode"):
			root.call_deferred("toggle_observe_mode")
	)
	return button


func _observe_play_button(playback: bool, observe_mode: bool) -> Button:
	var button := _observe_button("ObservePlayButton", "Pause" if playback else "Play", "observe_playback", playback, not observe_mode)
	button.set_meta("observe_mode", observe_mode)
	if observe_mode:
		button.pressed.connect(func() -> void:
			var root := get_parent()
			if root != null and root.has_method("toggle_observe_playback"):
				root.call_deferred("toggle_observe_playback")
		)
	return button


func _observe_speed_button(speed: String, observe_mode: bool) -> Button:
	var button := _observe_button("ObserveSpeedButton", speed, "observe_speed", speed, not observe_mode)
	button.set_meta("observe_mode", observe_mode)
	if observe_mode:
		button.pressed.connect(func() -> void:
			var root := get_parent()
			if root != null and root.has_method("cycle_observe_speed"):
				root.call_deferred("cycle_observe_speed")
		)
	return button


func _observe_auto_button(auto_tick: bool) -> Button:
	var button := _observe_button("ObserveAutoButton", "Auto on" if auto_tick else "Auto off", "auto_tick", auto_tick, false)
	button.pressed.connect(func() -> void:
		var root := get_parent()
		if root != null and root.has_method("toggle_auto_tick"):
			root.call_deferred("toggle_auto_tick")
	)
	return button


func _observe_tooltip(meta_key: String, meta_value: Variant, disabled: bool) -> String:
	var state := str(meta_value)
	match meta_key:
		"observe_playback":
			state = "播放" if bool(meta_value) else "暂停"
		"observe_speed":
			state = "速度 %s" % str(meta_value)
		"observe_level":
			state = "观察楼层 %d" % int(meta_value)
		"auto_tick":
			state = "自动推进 %s" % ("开启" if bool(meta_value) else "关闭")
		"observe_mode":
			state = "观察模式 %s" % ("开启" if bool(meta_value) else "关闭")
	if disabled:
		state = "%s | %s" % [state, _reason_catalog.disabled_text_for("observe_control_unavailable")]
	else:
		match meta_key:
			"observe_mode":
				state = "%s | 点击切换控制模式" % state
			"observe_playback":
				state = "%s | 点击切换观察播放" % state
			"observe_speed":
				state = "%s | 点击切换观察速度" % state
	return state


func _add_hotbar_cooldown_mask(button: Button, slot_id: String, cooldown: float) -> void:
	var mask := ColorRect.new()
	mask.name = "HotbarCooldownMask_%s" % slot_id
	mask.visible = cooldown > 0.0
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.color = Color(0.08, 0.12, 0.16, 0.58)
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.set_meta("cooldown_remaining", cooldown)
	button.add_child(mask)


func _hotbar_tooltip(key_label: String, group_label: String, kind: String, entry_label: String, slot: Dictionary) -> String:
	var parts: Array[String] = [
		"%s 热栏 %s" % [group_label, key_label],
		"物品" if kind == "item" else "技能",
		entry_label,
	]
	var cost_text := _hotbar_cost_text(slot)
	if not cost_text.is_empty():
		parts.append(cost_text)
	var effect_text := _hotbar_effect_text(slot)
	if not effect_text.is_empty():
		parts.append(effect_text)
	parts.append(_hotbar_use_state_text(slot))
	return " | ".join(parts)


func _hotbar_cost_text(slot: Dictionary) -> String:
	var parts: Array[String] = []
	var ap_cost := float(slot.get("ap_cost", 0.0))
	if ap_cost > 0.0:
		parts.append("AP %.0f" % ap_cost)
	var resource_parts: Array[String] = []
	for cost in _array_or_empty(slot.get("resource_costs", [])):
		var cost_data: Dictionary = _dictionary_or_empty(cost)
		var resource_id := str(cost_data.get("resource", ""))
		var amount := float(cost_data.get("amount", 0.0))
		if resource_id.is_empty() or amount <= 0.0:
			continue
		resource_parts.append("%s %.0f" % [_resource_label(resource_id), amount])
	if not resource_parts.is_empty():
		parts.append("资源 %s" % " / ".join(resource_parts))
	return " / ".join(parts)


func _hotbar_effect_text(slot: Dictionary) -> String:
	var effects: Array[String] = []
	for effect in _array_or_empty(slot.get("effect_summary", [])):
		var effect_text := str(effect)
		if not effect_text.is_empty():
			effects.append(effect_text)
	if effects.is_empty():
		return ""
	return "效果 %s" % " / ".join(effects)


func _hotbar_use_state_text(slot: Dictionary) -> String:
	match str(slot.get("use_reason", "")):
		"cooldown":
			return "冷却 %.0fs" % float(slot.get("cooldown_remaining", 0.0))
		"ap_insufficient", "ap_insufficient_use_item":
			return "AP不足"
		"not_enough_items":
			return "数量不足"
		"item_not_usable":
			return "不可使用"
		"item_use_forbidden":
			return "禁止使用"
		"unknown_item":
			return "未知物品"
		"resource_insufficient":
			return _missing_resource_text(slot)
		"unknown_skill", "skill_missing":
			return "未知技能"
		"", "available":
			return "可用"
	return str(slot.get("use_reason", ""))


func _missing_resource_text(slot: Dictionary) -> String:
	var missing: Dictionary = _dictionary_or_empty(slot.get("missing_resource", {}))
	var resource_id := str(missing.get("resource", ""))
	var required: float = float(missing.get("required_amount", 0.0))
	var available: float = float(missing.get("available_amount", 0.0))
	if resource_id.is_empty():
		return "资源不足"
	return "资源不足 %s %.0f/%.0f" % [_resource_label(resource_id), available, required]


func _resource_label(resource_id: String) -> String:
	match resource_id:
		"hp":
			return "HP"
		"stamina":
			return "stamina"
		"hunger":
			return "hunger"
		"thirst":
			return "thirst"
		"immunity":
			return "immunity"
	return resource_id


func _empty_hotbar_drag_data(_position: Vector2, _from_control: Control) -> Variant:
	return null


func _can_drop_hotbar_group(_position: Vector2, data: Variant, from_control: Control) -> bool:
	var drag_data: Dictionary = _dictionary_or_empty(data)
	var reject_reason := "hotbar_group_drag_unsupported" if not drag_data.is_empty() else ""
	_apply_hotbar_group_drag_hover(from_control, reject_reason)
	return false


func _drop_hotbar_group(_position: Vector2, _data: Variant, from_control: Control) -> void:
	_clear_hotbar_group_drag_hover(from_control)


func _can_drop_observe_hotbar(_position: Vector2, data: Variant, from_control: Control) -> bool:
	var drag_data: Dictionary = _dictionary_or_empty(data)
	var reject_reason := "observe_hotbar_drag_unsupported" if not drag_data.is_empty() else ""
	_apply_observe_hotbar_drag_hover(from_control, reject_reason)
	return false


func _drop_observe_hotbar(_position: Vector2, _data: Variant, from_control: Control) -> void:
	_clear_observe_hotbar_drag_hover(from_control)


func _can_drop_hotbar_skill(_position: Vector2, data: Variant, from_control: Control) -> bool:
	var drag_data: Dictionary = _dictionary_or_empty(data)
	var acceptance: Dictionary = _hotbar_drop_acceptance(from_control, drag_data)
	var accepted := bool(acceptance.get("accept", false))
	_apply_hotbar_drag_hover(from_control, accepted, str(acceptance.get("reason", "")))
	return accepted


func _drop_hotbar_skill(position: Vector2, data: Variant, from_control: Control) -> void:
	if not _can_drop_hotbar_skill(position, data, from_control):
		return
	var drag_data: Dictionary = _dictionary_or_empty(data)
	var slot_id := str(from_control.get_meta("hotbar_slot_id", ""))
	var skill_id := str(drag_data.get("skill_id", ""))
	if slot_id.is_empty() or skill_id.is_empty():
		return
	var root := get_parent()
	_clear_hotbar_drag_hover(from_control)
	if root != null and root.has_method("bind_player_skill_to_hotbar"):
		root.bind_player_skill_to_hotbar(slot_id, skill_id)


func _prepare_hotbar_group_drop_target(control: Control) -> void:
	if control == null:
		return
	control.set_meta("hotbar_group_drag_hovered", false)
	control.set_meta("hotbar_group_drag_last_accept", false)
	control.set_meta("hotbar_group_drag_reject_reason", "")
	control.set_meta("hotbar_group_drag_highlight_style", "")
	control.set_meta("hotbar_group_drag_highlight_color", "")
	control.mouse_exited.connect(func() -> void:
		_clear_hotbar_group_drag_hover(control)
	)


func _prepare_observe_hotbar_drop_target(control: Control) -> void:
	if control == null:
		return
	control.set_meta("observe_hotbar_drag_hovered", false)
	control.set_meta("observe_hotbar_drag_last_accept", false)
	control.set_meta("observe_hotbar_drag_reject_reason", "")
	control.set_meta("observe_hotbar_drag_highlight_style", "")
	control.set_meta("observe_hotbar_drag_highlight_color", "")
	control.mouse_exited.connect(func() -> void:
		_clear_observe_hotbar_drag_hover(control)
	)


func _apply_observe_hotbar_drag_hover(control: Control, reject_reason: String) -> void:
	if control == null or not is_instance_valid(control) or _observe_control_key(control).is_empty():
		return
	var color_text := "#e25c5c"
	control.set_meta("observe_hotbar_drag_hovered", true)
	control.set_meta("observe_hotbar_drag_last_accept", false)
	control.set_meta("observe_hotbar_drag_reject_reason", reject_reason)
	control.set_meta("observe_hotbar_drag_highlight_style", "reject")
	control.set_meta("observe_hotbar_drag_highlight_color", color_text)
	control.modulate = Color(1.0, 0.90, 0.90, 1.0)
	if control is Button:
		(control as Button).add_theme_color_override("font_color", Color.html(color_text))


func _clear_observe_hotbar_drag_hover(control: Control) -> void:
	if control == null or not is_instance_valid(control) or _observe_control_key(control).is_empty():
		return
	control.set_meta("observe_hotbar_drag_hovered", false)
	control.set_meta("observe_hotbar_drag_last_accept", false)
	control.set_meta("observe_hotbar_drag_reject_reason", "")
	control.set_meta("observe_hotbar_drag_highlight_style", "")
	control.set_meta("observe_hotbar_drag_highlight_color", "")
	control.modulate = Color.WHITE
	if control is Button:
		(control as Button).remove_theme_color_override("font_color")


func _observe_control_key(control: Control) -> String:
	for key in ["observe_playback", "observe_speed", "auto_tick", "observe_level", "observe_mode"]:
		if control != null and control.has_meta(key):
			return key
	return ""


func _apply_hotbar_group_drag_hover(control: Control, reject_reason: String) -> void:
	if control == null or not is_instance_valid(control) or not control.has_meta("hotbar_group_id"):
		return
	var color_text := "#e25c5c"
	control.set_meta("hotbar_group_drag_hovered", true)
	control.set_meta("hotbar_group_drag_last_accept", false)
	control.set_meta("hotbar_group_drag_reject_reason", reject_reason)
	control.set_meta("hotbar_group_drag_highlight_style", "reject")
	control.set_meta("hotbar_group_drag_highlight_color", color_text)
	control.modulate = Color(1.0, 0.90, 0.90, 1.0)
	if control is Button:
		(control as Button).add_theme_color_override("font_color", Color.html(color_text))


func _clear_hotbar_group_drag_hover(control: Control) -> void:
	if control == null or not is_instance_valid(control) or not control.has_meta("hotbar_group_id"):
		return
	control.set_meta("hotbar_group_drag_hovered", false)
	control.set_meta("hotbar_group_drag_last_accept", false)
	control.set_meta("hotbar_group_drag_reject_reason", "")
	control.set_meta("hotbar_group_drag_highlight_style", "")
	control.set_meta("hotbar_group_drag_highlight_color", "")
	control.modulate = Color.WHITE
	if control is Button:
		(control as Button).remove_theme_color_override("font_color")


func _prepare_hotbar_drop_target(control: Control) -> void:
	if control == null:
		return
	control.set_meta("hotbar_drag_hovered", false)
	control.set_meta("hotbar_drag_last_accept", false)
	control.set_meta("hotbar_drag_reject_reason", "")
	control.set_meta("hotbar_drag_highlight_style", "")
	control.set_meta("hotbar_drag_highlight_color", "")
	control.mouse_exited.connect(func() -> void:
		_clear_hotbar_drag_hover(control)
	)


func _hotbar_drop_acceptance(control: Control, drag_data: Dictionary) -> Dictionary:
	if control == null or not is_instance_valid(control) or not control.has_meta("hotbar_slot_id"):
		return {"accept": false, "reason": "hotbar_slot_missing_slot"}
	if str(drag_data.get("kind", "")) != "skill_hotbar":
		return {"accept": false, "reason": "hotbar_slot_requires_skill_hotbar"}
	if str(drag_data.get("skill_id", "")).is_empty():
		return {"accept": false, "reason": "hotbar_slot_missing_skill"}
	return {"accept": true, "reason": ""}


func _apply_hotbar_drag_hover(control: Control, accepted: bool, reject_reason: String) -> void:
	if control == null or not is_instance_valid(control) or not control.has_meta("hotbar_slot_id"):
		return
	var color_text := "#4ecb71" if accepted else "#e25c5c"
	var style := "accept" if accepted else "reject"
	control.set_meta("hotbar_drag_hovered", true)
	control.set_meta("hotbar_drag_last_accept", accepted)
	control.set_meta("hotbar_drag_reject_reason", reject_reason)
	control.set_meta("hotbar_drag_highlight_style", style)
	control.set_meta("hotbar_drag_highlight_color", color_text)
	control.modulate = Color(0.90, 1.0, 0.92, 1.0) if accepted else Color(1.0, 0.90, 0.90, 1.0)
	if control is Button:
		(control as Button).add_theme_color_override("font_color", Color.html(color_text))


func _clear_hotbar_drag_hover(control: Control) -> void:
	if control == null or not is_instance_valid(control) or not control.has_meta("hotbar_slot_id"):
		return
	control.set_meta("hotbar_drag_hovered", false)
	control.set_meta("hotbar_drag_last_accept", false)
	control.set_meta("hotbar_drag_reject_reason", "")
	control.set_meta("hotbar_drag_highlight_style", "")
	control.set_meta("hotbar_drag_highlight_color", "")
	control.modulate = Color.WHITE
	if control is Button:
		(control as Button).remove_theme_color_override("font_color")


func _short_hotbar_label(label: String) -> String:
	if label.length() <= 4:
		return label
	return label.substr(0, 4)


func _clear_menu_options() -> void:
	if _menu_options_box == null:
		return
	for child in _menu_options_box.get_children():
		_menu_options_box.remove_child(child)
		child.free()


func _menu_position(screen_position: Vector2) -> Vector2:
	var viewport_size := get_viewport_rect().size
	var menu_size := Vector2(200, max(60, 32 + _menu_options_box.get_child_count() * 32))
	return Vector2(
		clampf(screen_position.x, 8.0, max(8.0, viewport_size.x - menu_size.x - 8.0)),
		clampf(screen_position.y, 8.0, max(8.0, viewport_size.y - menu_size.y - 8.0))
	)


func _prompt_summary_for_menu(prompt: Dictionary) -> Dictionary:
	if prompt.has("has_target"):
		return prompt
	if not bool(prompt.get("ok", false)):
		return {"has_target": false}
	return {
		"has_target": true,
		"target_name": prompt.get("target_name", ""),
		"primary_option_id": prompt.get("primary_option_id", ""),
		"options": prompt.get("options", []),
		"disabled_options": prompt.get("disabled_options", []),
	}


func _inventory_text(inventory: Dictionary) -> String:
	if inventory.is_empty():
		return "{}"
	var parts: Array[String] = []
	for item_id in inventory.keys():
		parts.append("%s x%d" % [item_id, int(inventory[item_id])])
	parts.sort()
	return ", ".join(parts)


func _status_badge_text(value: Variant) -> String:
	var badges: Array = value if typeof(value) == TYPE_ARRAY else []
	if badges.is_empty():
		return "Status none"
	var parts: Array[String] = []
	for badge in badges:
		var data: Dictionary = _dictionary_or_empty(badge)
		var label := str(data.get("label", ""))
		var badge_value := str(data.get("value", ""))
		if label.is_empty() and badge_value.is_empty():
			continue
		parts.append("%s %s" % [label, badge_value])
	return "Status %s" % " | ".join(parts) if not parts.is_empty() else "Status none"


func _interaction_text(interaction: Dictionary) -> String:
	if not bool(interaction.get("has_target", false)):
		return "Target none"
	var primary_label := str(interaction.get("primary_option_id", ""))
	for option in interaction.get("options", []):
		var option_data: Dictionary = option
		if option_data.get("id", "") == interaction.get("primary_option_id", ""):
			primary_label = "%s (%s)" % [option_data.get("display_name", ""), primary_label]
			break
	return "Target %s | Primary %s" % [
		interaction.get("target_name", ""),
		primary_label,
	]


func _event_feedback_text(value: Variant) -> String:
	var entries: Array = value if typeof(value) == TYPE_ARRAY else []
	if entries.is_empty():
		return "Events none"
	var parts: Array[String] = []
	for entry in entries:
		var data: Dictionary = _dictionary_or_empty(entry)
		var text := str(data.get("text", ""))
		if not text.is_empty():
			parts.append(text)
	return "Events %s" % " | ".join(parts) if not parts.is_empty() else "Events none"


func _tracked_quest_text(value: Variant) -> String:
	var quest: Dictionary = _dictionary_or_empty(value)
	if not bool(quest.get("active", false)):
		return "Quest none"
	return "Quest %s | %d/%d | %s" % [
		str(quest.get("title", quest.get("quest_id", ""))),
		int(quest.get("progress_current", 0)),
		int(quest.get("progress_target", 0)),
		str(quest.get("status_text", "")),
	]


func _combat_hud_text(value: Variant) -> String:
	var combat_hud: Dictionary = _dictionary_or_empty(value)
	if combat_hud.is_empty():
		return "Combat HUD none"
	var state_text := "on" if bool(combat_hud.get("active", false)) else "off"
	var active_actor_name := str(combat_hud.get("active_actor_name", "")).strip_edges()
	if active_actor_name.is_empty():
		active_actor_name = "actor#%d" % int(combat_hud.get("active_actor_id", 0))
	var turn_text := "player" if bool(combat_hud.get("player_turn", false)) else str(combat_hud.get("phase", ""))
	var parts: Array[String] = [
		"Combat %s" % state_text,
		"Round %d" % int(combat_hud.get("round", 0)),
		"Turn %s %s#%d" % [
			turn_text,
			active_actor_name,
			int(combat_hud.get("active_actor_id", 0)),
		],
		"Enemies %d" % int(combat_hud.get("enemy_count", 0)),
	]
	var participant_count := int(combat_hud.get("participant_count", 0))
	if participant_count > 0:
		parts.append("Participants %d" % participant_count)
	if bool(combat_hud.get("active", false)) and int(combat_hud.get("next_combat_actor_id", 0)) > 0:
		var next_actor_name := str(combat_hud.get("next_combat_actor_name", "")).strip_edges()
		if next_actor_name.is_empty():
			next_actor_name = "actor"
		parts.append("Next %s#%d" % [next_actor_name, int(combat_hud.get("next_combat_actor_id", 0))])
	var target_text := _combat_target_preview_text(combat_hud.get("target_preview", {}))
	if not target_text.is_empty():
		parts.append(target_text)
	return " | ".join(parts)


func _combat_target_preview_text(value: Variant) -> String:
	var preview: Dictionary = _dictionary_or_empty(value)
	if preview.is_empty():
		return "Target -"
	var target_name := str(preview.get("target_name", "")).strip_edges()
	if target_name.is_empty():
		target_name = "actor#%d" % int(preview.get("target_actor_id", 0))
	var parts: Array[String] = ["Target %s#%d" % [target_name, int(preview.get("target_actor_id", 0))]]
	var hp := float(preview.get("target_hp", -1.0))
	var max_hp := float(preview.get("target_max_hp", -1.0))
	if hp >= 0.0 and max_hp > 0.0:
		parts.append("HP %s/%s" % [_number_text(hp), _number_text(max_hp)])
	var distance := int(preview.get("distance", -1))
	var range := int(preview.get("range", -1))
	if distance >= 0 or range >= 0:
		parts.append("Dist %s/%s" % [
			"-" if distance < 0 else str(distance),
			"-" if range < 0 else str(range),
		])
	var hit_chance := float(preview.get("hit_chance", -1.0))
	if hit_chance >= 0.0:
		parts.append("Hit %s" % _percent_text(hit_chance))
	var crit_chance := float(preview.get("crit_chance", -1.0))
	if crit_chance >= 0.0:
		parts.append("Crit %s" % _percent_text(crit_chance))
	var estimated := float(preview.get("estimated_damage", -1.0))
	var minimum := float(preview.get("minimum_damage", -1.0))
	var maximum := float(preview.get("maximum_damage", -1.0))
	if estimated >= 0.0:
		var range_text := ""
		if minimum >= 0.0 and maximum >= 0.0 and not is_equal_approx(minimum, maximum):
			range_text = " (%s-%s)" % [_number_text(minimum), _number_text(maximum)]
		parts.append("Dmg %s%s" % [_number_text(estimated), range_text])
	else:
		parts.append("Dmg -")
	if not bool(preview.get("can_attack", false)):
		var reason := str(preview.get("reason", ""))
		if not reason.is_empty():
			parts.append("Blocked %s" % _disabled_reason_text(reason))
	return " | ".join(parts)


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


func _runtime_control_text(runtime_control: Variant) -> String:
	if typeof(runtime_control) != TYPE_DICTIONARY:
		return "AutoTick off"
	var control_data: Dictionary = runtime_control
	var parts: Array[String] = [
		"AutoTick %s" % ("on" if bool(control_data.get("auto_tick", false)) else "off"),
	]
	parts.append("Observe %s %s %s" % [
		"on" if bool(control_data.get("observe_mode", false)) else "off",
		"play" if bool(control_data.get("observe_playback", false)) else "pause",
		str(control_data.get("observe_speed", "x1")),
	])
	var map_level: Dictionary = control_data.get("map_level", {})
	if not map_level.is_empty():
		parts.append("Level %d" % int(map_level.get("current", 0)))
	var focused_actor: Dictionary = control_data.get("focused_actor", {})
	if not focused_actor.is_empty():
		var focus_label := str(focused_actor.get("display_name", ""))
		if focus_label.is_empty():
			focus_label = str(focused_actor.get("definition_id", "actor"))
		parts.append("Focus %s#%d" % [focus_label, int(focused_actor.get("actor_id", 0))])
	var blocker_snapshot: Dictionary = _dictionary_or_empty(control_data.get("ui_blocker_snapshot", {}))
	var ui_blocker := str(blocker_snapshot.get("name", control_data.get("ui_blocker", "")))
	if not ui_blocker.is_empty():
		var kind := str(blocker_snapshot.get("kind", ""))
		parts.append("Blocker %s%s" % [ui_blocker, " (%s)" % kind if not kind.is_empty() else ""])
	var modal_stack: Dictionary = _dictionary_or_empty(control_data.get("modal_stack", {}))
	if bool(modal_stack.get("active", false)):
		var top_modal: Dictionary = _dictionary_or_empty(modal_stack.get("top", {}))
		parts.append("Modal %s/%d" % [str(top_modal.get("id", "")), int(modal_stack.get("count", 0))])
	var menu_state: Dictionary = _dictionary_or_empty(control_data.get("menu_state", {}))
	if not menu_state.is_empty():
		var stage_id := str(menu_state.get("active_stage_panel", ""))
		parts.append("Menu %s S:%s" % [
			"settings" if bool(menu_state.get("settings_open", false)) else "stage",
			stage_id if not stage_id.is_empty() else "-",
		])
		var latest_panel_event: Dictionary = _dictionary_or_empty(menu_state.get("latest_event", {}))
		if not latest_panel_event.is_empty():
			parts.append("Panel %s:%s" % [str(latest_panel_event.get("event", "")), str(latest_panel_event.get("panel_id", ""))])
		_append_menu_event_tokens(parts, menu_state)
	var context_menu: Dictionary = _dictionary_or_empty(control_data.get("context_menu", {}))
	if bool(context_menu.get("active", false)):
		var top_context: Dictionary = _dictionary_or_empty(context_menu.get("top", {}))
		parts.append("Context %s/%d" % [str(top_context.get("id", "")), int(context_menu.get("count", 0))])
	var tooltip: Dictionary = _dictionary_or_empty(control_data.get("tooltip", {}))
	if bool(tooltip.get("active", false)):
		parts.append(_tooltip_runtime_token(tooltip))
	var drag: Dictionary = _dictionary_or_empty(control_data.get("drag", {}))
	if bool(drag.get("active", false)):
		var target: Dictionary = _dictionary_or_empty(drag.get("target", {}))
		parts.append("Drag %s->%s/%s" % [str(drag.get("kind", "")), str(target.get("owner_panel", "")), str(target.get("target_kind", ""))])
	var controls_hint: Dictionary = _dictionary_or_empty(control_data.get("controls_hint", {}))
	if not controls_hint.is_empty():
		parts.append("Help %s" % ("on" if bool(controls_hint.get("visible", false)) else "off"))
	var debug_console: Dictionary = _dictionary_or_empty(control_data.get("debug_console", {}))
	if not debug_console.is_empty():
		parts.append("Console %s" % ("on" if bool(debug_console.get("visible", false)) else "off"))
	var hover_text := _hover_control_text(control_data.get("hover", {}))
	if not hover_text.is_empty():
		parts.append(hover_text)
	var selection_debug_text := _selection_debug_control_text(control_data.get("selection_debug", {}))
	if not selection_debug_text.is_empty():
		parts.append(selection_debug_text)
	var ai_debug_text := _ai_debug_control_text(control_data.get("ai_debug", {}))
	if not ai_debug_text.is_empty():
		parts.append(ai_debug_text)
	var performance_text := _performance_control_text(control_data.get("performance", {}))
	if not performance_text.is_empty():
		parts.append(performance_text)
	return " | ".join(parts)


func _performance_control_text(value: Variant) -> String:
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


func _tooltip_runtime_token(tooltip: Dictionary) -> String:
	var position: Dictionary = _dictionary_or_empty(tooltip.get("screen_position", {}))
	var position_text := ""
	if not position.is_empty():
		position_text = "@%d,%d" % [int(round(float(position.get("x", 0.0)))), int(round(float(position.get("y", 0.0))))]
	return "Tip %s/%s%s" % [str(tooltip.get("owner_panel", "")), str(tooltip.get("source_name", "")), position_text]


func _selection_debug_control_text(value: Variant) -> String:
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


func _ai_debug_control_text(value: Variant) -> String:
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
	var reason := str(intent.get("reason", ""))
	var reason_text := "" if reason.is_empty() else " %s" % reason
	return "AI #%d %s%s%s%s%s" % [
		int(intent.get("actor_id", 0)),
		str(intent.get("intent", "")),
		target_text,
		path_text,
		tracking_text,
		reason_text,
	]


func _hover_control_text(value: Variant) -> String:
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


func _skill_targeting_text(value: Variant) -> String:
	var targeting: Dictionary = _dictionary_or_empty(value)
	if not bool(targeting.get("active", false)):
		return ""
	var preview: Dictionary = _dictionary_or_empty(targeting.get("preview", {}))
	var skill_name := str(targeting.get("skill_name", targeting.get("skill_id", "")))
	var shape := str(targeting.get("target_kind", preview.get("target_shape", "")))
	var policy := str(targeting.get("target_policy", preview.get("target_policy", "")))
	var range_value: int = int(preview.get("range", targeting.get("range", -1)))
	var distance_value: int = int(preview.get("distance", -1))
	var shape_text := _skill_target_shape_text(shape)
	var policy_text := _skill_target_policy_text(policy)
	var range_text := _skill_target_range_text(shape, range_value, targeting, preview)
	if not bool(preview.get("success", false)):
		var reason := str(preview.get("reason", "选择目标"))
		var distance_text := "" if distance_value < 0 else " | 距离 %d" % distance_value
		var failure_text := "Skill Target %s | %s | %s%s | %s" % [
			skill_name,
			shape_text,
			policy_text,
			range_text,
			_skill_target_reason_text(reason),
		]
		return failure_text + distance_text
	var affected_cells: Array = _array_or_empty(preview.get("affected_cells", []))
	var affected_actor_ids: Array = _array_or_empty(preview.get("affected_actor_ids", []))
	var parts: Array[String] = [
		"Skill Target %s" % skill_name,
		shape_text,
		policy_text,
		"%d格" % affected_cells.size(),
		"%d目标" % affected_actor_ids.size(),
	]
	if not range_text.is_empty():
		parts.append(range_text.strip_edges())
	if distance_value >= 0:
		parts.append("距离 %d" % distance_value)
	if bool(preview.get("friendly_fire", false)):
		parts.append("友军风险")
	return " | ".join(parts)


func _skill_target_shape_text(shape: String) -> String:
	match shape:
		"single", "actor", "single_actor":
			return "单体"
		"grid", "point":
			return "格子"
		"radius", "circle":
			return "范围"
		"line":
			return "直线"
		"cone":
			return "锥形"
		"self":
			return "自身"
	if shape.is_empty():
		return "目标"
	return shape


func _skill_target_policy_text(policy: String) -> String:
	match policy:
		"hostile_only", "hostile":
			return "仅敌对"
		"ally_only", "ally":
			return "仅友方"
		"any_actor":
			return "任意角色"
		"any_grid":
			return "任意格"
		"empty_grid":
			return "空格"
		"self":
			return "自身"
		"any", "":
			return "任意目标"
	return policy


func _skill_target_range_text(shape: String, range_value: int, targeting: Dictionary, preview: Dictionary) -> String:
	var parts: Array[String] = []
	if range_value >= 0:
		parts.append("射程 %d" % range_value)
	var radius_value: int = int(preview.get("radius", targeting.get("radius", -1)))
	if radius_value >= 0 and shape in ["radius", "circle"]:
		parts.append("半径 %d" % radius_value)
	var length_value: int = int(preview.get("length", targeting.get("length", -1)))
	if length_value >= 0 and shape in ["line", "cone"]:
		parts.append("长度 %d" % length_value)
	var width_value: int = int(preview.get("width", targeting.get("width", -1)))
	if width_value >= 0 and shape == "cone":
		parts.append("宽度 %d" % width_value)
	return "" if parts.is_empty() else " | %s" % " / ".join(parts)


func _skill_target_reason_text(reason: String) -> String:
	match reason:
		"skill_target_pending":
			return "选择目标"
		"skill_target_actor_missing":
			return "目标角色不存在"
		"skill_target_grid_missing":
			return "请选择目标格"
		"skill_target_not_hostile":
			return "需要敌对目标"
		"skill_target_not_ally":
			return "需要友方目标"
		"skill_target_not_self":
			return "需要自身目标"
		"skill_target_out_of_range":
			return "目标超出射程"
		"skill_target_invalid_level":
			return "目标楼层无效"
		"skill_target_blocked_by_los":
			return "视线被遮挡"
		"skill_target_grid_occupied":
			return "目标格被占用"
		"target_not_visible":
			return "目标不可见"
		"skill_target_policy_unknown":
			return "未知目标策略"
		"skill_target_shape_unknown":
			return "未知目标形状"
	if reason.is_empty():
		return "选择目标"
	return _reason_catalog.disabled_text_for(reason)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _number_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value


func _percent_text(value: float) -> String:
	return "%d%%" % int(round(value * 100.0))
