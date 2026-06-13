extends Control

const ReasonCatalog = preload("res://scripts/ui/snapshots/reason_catalog.gd")
const DebugConsolePanel = preload("res://scripts/ui/controllers/debug_console_panel.gd")
const DebugPanelView = preload("res://scripts/ui/controllers/debug_panel_view.gd")
const FeedbackToastLayer = preload("res://scripts/ui/controllers/feedback_toast_layer.gd")
const InteractionMenuView = preload("res://scripts/ui/controllers/interaction_menu_view.gd")
const HotbarView = preload("res://scripts/ui/controllers/hotbar_view.gd")
const ObserveHotbarView = preload("res://scripts/ui/controllers/observe_hotbar_view.gd")

var _world_label: Label
var _status_badge_label: Label
var _player_label: Label
var _inventory_label: Label
var _quest_label: Label
var _combat_hud_label: Label
var _interaction_label: Label
var _event_feedback_label: Label
var _debug_overlay_label: Label
var _info_panel_label: Label
var _runtime_control_label: Label
var _skill_targeting_label: Label
var _controls_hint_box: VBoxContainer
var _bottom_hud_dock: PanelContainer
var _bottom_menu_bar: HBoxContainer
var _bottom_hotbar_stack: VBoxContainer
var _menu_buttons: Dictionary = {}
var controls_hint_visible := false
var _reason_catalog := ReasonCatalog.new()
var _debug_console_panel := DebugConsolePanel.new()
var _debug_panel_view := DebugPanelView.new()
var _feedback_toast_layer := FeedbackToastLayer.new()
var _interaction_menu_view := InteractionMenuView.new()
var _hotbar_view := HotbarView.new()
var _observe_hotbar_view := ObserveHotbarView.new()


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()


func apply_snapshot(snapshot: Dictionary) -> void:
	apply_runtime_snapshot(snapshot)


func apply_runtime_snapshot(snapshot: Dictionary) -> void:
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
	_hotbar_view.apply(snapshot.get("hotbar", []), snapshot.get("hotbar_group_labels", {}))
	_observe_hotbar_view.apply(snapshot.get("runtime_control", {}))
	_interaction_label.text = _interaction_text(interaction)
	_event_feedback_label.text = _event_feedback_text(snapshot.get("event_feedback", []))
	_feedback_toast_layer.apply(snapshot.get("feedback_toasts", []))
	_debug_overlay_label.text = "Overlay %s" % str(snapshot.get("debug_overlay_mode", "off"))
	_info_panel_label.text = _info_panel_text(snapshot.get("info_panel", {}))
	_runtime_control_label.text = _runtime_control_text(snapshot.get("runtime_control", {}))
	_skill_targeting_label.text = _skill_targeting_text(_dictionary_or_empty(snapshot.get("runtime_control", {})).get("skill_targeting", {}))
	_skill_targeting_label.visible = not _skill_targeting_label.text.is_empty()
	_apply_bottom_menu_state(snapshot.get("runtime_control", {}))
	_apply_controls_hint()
	_interaction_menu_view.apply(interaction)
	_debug_panel_view.apply(snapshot)


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
	_build_bottom_hud_dock()
	_interaction_menu_view.build(self)
	_feedback_toast_layer.build(self)
	_debug_console_panel.build(self)
	_debug_panel_view.build(self)


func _build_bottom_hud_dock() -> void:
	if _bottom_hud_dock != null:
		return
	_bottom_hud_dock = PanelContainer.new()
	_bottom_hud_dock.name = "BottomHudDock"
	_bottom_hud_dock.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom_hud_dock.offset_left = 320
	_bottom_hud_dock.offset_right = -320
	_bottom_hud_dock.offset_top = -104
	_bottom_hud_dock.offset_bottom = -16
	_bottom_hud_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_hud_dock.custom_minimum_size = Vector2(520, 86)
	add_child(_bottom_hud_dock)

	var dock_box := VBoxContainer.new()
	dock_box.name = "BottomHudStack"
	dock_box.alignment = BoxContainer.ALIGNMENT_CENTER
	dock_box.add_theme_constant_override("separation", 6)
	dock_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_hud_dock.add_child(dock_box)

	_bottom_menu_bar = HBoxContainer.new()
	_bottom_menu_bar.name = "BottomMenuBar"
	_bottom_menu_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_bottom_menu_bar.add_theme_constant_override("separation", 4)
	_bottom_menu_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock_box.add_child(_bottom_menu_bar)
	for definition in _bottom_menu_definitions():
		var data: Dictionary = definition
		var button := _bottom_menu_button(data)
		_bottom_menu_bar.add_child(button)
		_menu_buttons[str(data.get("id", ""))] = button

	_bottom_hotbar_stack = VBoxContainer.new()
	_bottom_hotbar_stack.name = "BottomHotbarStack"
	_bottom_hotbar_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	_bottom_hotbar_stack.add_theme_constant_override("separation", 4)
	_bottom_hotbar_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock_box.add_child(_bottom_hotbar_stack)
	_hotbar_view.build(_bottom_hotbar_stack, self)
	_observe_hotbar_view.build(_bottom_hotbar_stack, self, _hotbar_view)


func _bottom_menu_definitions() -> Array[Dictionary]:
	return [
		{"id": "inventory", "name": "InventoryButton", "text": "I 背包", "tooltip": "打开背包 | I", "action": "toggle_stage_panel", "panel_id": "inventory"},
		{"id": "character", "name": "CharacterButton", "text": "C 角色", "tooltip": "打开角色 | C", "action": "toggle_stage_panel", "panel_id": "character"},
		{"id": "map", "name": "MapButton", "text": "M 地图", "tooltip": "打开地图 | M", "action": "toggle_stage_panel", "panel_id": "map"},
		{"id": "journal", "name": "JournalButton", "text": "J 任务", "tooltip": "打开任务日志 | J", "action": "toggle_stage_panel", "panel_id": "journal"},
		{"id": "skills", "name": "SkillsButton", "text": "K 技能", "tooltip": "打开技能 | K", "action": "toggle_stage_panel", "panel_id": "skills"},
		{"id": "crafting", "name": "CraftingButton", "text": "L 制作", "tooltip": "打开制作 | L", "action": "toggle_stage_panel", "panel_id": "crafting"},
		{"id": "settings", "name": "SettingsButton", "text": "Esc 设置", "tooltip": "打开设置 | Esc", "action": "toggle_settings_panel", "panel_id": "settings"},
	]


func _bottom_menu_button(definition: Dictionary) -> Button:
	var button := Button.new()
	var panel_id := str(definition.get("panel_id", ""))
	button.name = str(definition.get("name", "%sButton" % panel_id.capitalize()))
	button.text = str(definition.get("text", panel_id))
	button.tooltip_text = str(definition.get("tooltip", button.text))
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(max(68, button.text.length() * 12 + 18), 28)
	button.set_meta("bottom_menu_id", panel_id)
	button.set_meta("panel_id", panel_id)
	button.set_meta("bottom_menu_action", str(definition.get("action", "")))
	button.set_meta("active", false)
	button.pressed.connect(func() -> void:
		_press_bottom_menu_button(definition, button)
	)
	return button


func _press_bottom_menu_button(definition: Dictionary, button: Button) -> void:
	var root := get_parent()
	if root == null:
		return
	var action := str(definition.get("action", ""))
	var panel_id := str(definition.get("panel_id", ""))
	_play_audio("ui_button_pressed", button.name, "bottom_menu_button", action, {
		"value": panel_id,
	})
	if action == "toggle_stage_panel" and root.has_method("toggle_stage_panel"):
		root.call("toggle_stage_panel", panel_id)
	elif action == "toggle_settings_panel" and root.has_method("toggle_settings_panel"):
		root.call("toggle_settings_panel")


func _play_audio(event_kind: String, control_name: String, control_kind: String, action: String, extra_payload: Dictionary = {}) -> Dictionary:
	var root := get_parent()
	if root == null or not root.has_method("play_ui_audio_feedback"):
		return {}
	var payload := {
		"audio_source": "ui",
		"panel_id": "hud",
		"control_name": control_name,
		"control_kind": control_kind,
		"action": action,
	}
	for key in extra_payload.keys():
		payload[key] = extra_payload[key]
	return _dictionary_or_empty(root.call("play_ui_audio_feedback", event_kind, payload))


func _apply_bottom_menu_state(runtime_control_value: Variant) -> void:
	if _bottom_menu_bar == null:
		return
	var menu_state: Dictionary = _dictionary_or_empty(_dictionary_or_empty(runtime_control_value).get("menu_state", {}))
	var active_stage := str(menu_state.get("active_stage_panel", ""))
	var settings_open := bool(menu_state.get("settings_open", false))
	for menu_id in _menu_buttons.keys():
		var button: Button = _menu_buttons[menu_id] as Button
		if button == null:
			continue
		var active := (str(menu_id) == active_stage) or (str(menu_id) == "settings" and settings_open)
		button.button_pressed = active
		button.set_meta("active", active)
		button.set_meta("settings_open", settings_open if str(menu_id) == "settings" else false)
		button.set_meta("active_stage_panel", active_stage)
		button.set_meta("mouse_blocks_world", button.mouse_filter == Control.MOUSE_FILTER_STOP)


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
	return _debug_panel_view.toggle()


func hide_debug_panel() -> void:
	_debug_panel_view.hide()


func is_debug_panel_open() -> bool:
	return _debug_panel_view.is_open()


func debug_panel_snapshot() -> Dictionary:
	return _debug_panel_view.snapshot()


func toggle_debug_console() -> Dictionary:
	return _debug_console_panel.toggle()


func hide_debug_console() -> void:
	_debug_console_panel.hide()


func is_debug_console_open() -> bool:
	return _debug_console_panel.is_open()


func debug_console_snapshot() -> Dictionary:
	return _debug_console_panel.snapshot()


func console_input_node() -> LineEdit:
	return _debug_console_panel.input_node()


func set_debug_console_schema(schema: Array, suggestions: Array, permission: Dictionary = {}) -> void:
	_debug_console_panel.set_schema(schema, suggestions, permission)


func set_debug_console_result(command_text: String, result: Dictionary) -> void:
	_debug_console_panel.set_result(command_text, result)


func clear_debug_console_history() -> void:
	_debug_console_panel.clear_history()


func show_interaction_menu(screen_position: Vector2, prompt: Dictionary) -> void:
	_interaction_menu_view.show(screen_position, prompt)


func hide_interaction_menu() -> void:
	_interaction_menu_view.hide()


func is_interaction_menu_open() -> bool:
	return _interaction_menu_view.is_open()


func interaction_menu_snapshot() -> Dictionary:
	return _interaction_menu_view.snapshot()


func input_blocker_snapshot() -> Dictionary:
	if _debug_console_panel.is_open():
		return {
			"blocked": true,
			"name": "debug_console",
			"kind": "debug_console",
			"modal_id": "",
			"panel_id": "hud",
			"mouse_blocks_world": true,
		}
	var interaction_menu := interaction_menu_snapshot()
	if not interaction_menu.is_empty():
		return {
			"blocked": true,
			"name": "interaction_menu",
			"kind": "context_menu",
			"modal_id": "",
			"panel_id": "hud",
			"mouse_blocks_world": bool(interaction_menu.get("mouse_blocks_world", true)),
			"menu": interaction_menu,
		}
	return {
		"blocked": false,
		"name": "",
		"kind": "",
		"modal_id": "",
		"panel_id": "",
		"mouse_blocks_world": false,
	}


func _line(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = true
	return label


func _apply_controls_hint() -> void:
	if _controls_hint_box == null:
		return
	_controls_hint_box.visible = controls_hint_visible


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


func _empty_hotbar_drag_data(position: Vector2, from_control: Control) -> Variant:
	return _hotbar_view.call("_empty_drag_data", position, from_control)


func _can_drop_hotbar_group(position: Vector2, data: Variant, from_control: Control) -> bool:
	return bool(_hotbar_view.call("_can_drop_group", position, data, from_control))


func _drop_hotbar_group(position: Vector2, data: Variant, from_control: Control) -> void:
	_hotbar_view.call("_drop_group", position, data, from_control)


func _can_drop_hotbar_skill(position: Vector2, data: Variant, from_control: Control) -> bool:
	return bool(_hotbar_view.call("_can_drop_skill", position, data, from_control))


func _drop_hotbar_skill(position: Vector2, data: Variant, from_control: Control) -> void:
	_hotbar_view.call("_drop_skill", position, data, from_control)


func _can_drop_observe_hotbar(position: Vector2, data: Variant, from_control: Control) -> bool:
	return bool(_observe_hotbar_view.call("_can_drop_observe", position, data, from_control))


func _drop_observe_hotbar(position: Vector2, data: Variant, from_control: Control) -> void:
	_observe_hotbar_view.call("_drop_observe", position, data, from_control)


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
	var world_time: Dictionary = _dictionary_or_empty(control_data.get("world_time", {}))
	if not world_time.is_empty():
		parts.append("Time %s" % str(world_time.get("display_label", "")))
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
	var runner_text := _turn_action_runner_control_text(control_data.get("turn_action_runner", {}))
	if not runner_text.is_empty():
		parts.append(runner_text)
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


func _turn_action_runner_control_text(value: Variant) -> String:
	var runner: Dictionary = _dictionary_or_empty(value)
	if runner.is_empty():
		return ""
	var action_kind := str(runner.get("action_kind", ""))
	var phase := str(runner.get("phase", "idle"))
	var state := "active" if bool(runner.get("active", false)) else ("presenting" if bool(runner.get("presentation_active", false)) else "idle")
	var label := "Runner %s" % state
	if not action_kind.is_empty():
		label += " %s" % action_kind
	if not phase.is_empty():
		label += ":%s" % phase
	var parts: Array[String] = [label]
	var step_index := int(runner.get("completed_steps", runner.get("step_index", 0)))
	var total_steps := int(runner.get("total_steps", 0))
	var path_length := int(runner.get("path_length", 0))
	var remaining_steps := int(runner.get("remaining_steps", 0))
	var path: Array = _array_or_empty(runner.get("path", []))
	if total_steps <= 0 and not path.is_empty():
		total_steps = max(0, path.size() - 1)
	if path_length <= 0 and not path.is_empty():
		path_length = path.size()
	if step_index > 0 or total_steps > 0 or path_length > 0:
		parts.append("Step %d/%d" % [step_index, total_steps if total_steps > 0 else path_length])
	if remaining_steps > 0:
		parts.append("Remain %d" % remaining_steps)
	var interaction_text := _runner_interaction_phase_text(runner.get("interaction_phase", {}))
	if not interaction_text.is_empty():
		parts.append(interaction_text)
	var attack_text := _runner_attack_phase_text(runner.get("attack_phase", {}))
	if not attack_text.is_empty():
		parts.append(attack_text)
	var wait_text := _runner_wait_phase_text(runner.get("wait_phase", {}))
	if not wait_text.is_empty():
		parts.append(wait_text)
	var craft_text := _runner_craft_phase_text(runner.get("craft_phase", {}))
	if not craft_text.is_empty():
		parts.append(craft_text)
	var ap_before := float(runner.get("ap_before", 0.0))
	var ap_after := float(runner.get("ap_after", 0.0))
	if not is_zero_approx(ap_before) or not is_zero_approx(ap_after):
		parts.append("AP %s/%s" % [_number_text(ap_after), _number_text(ap_before)])
		if runner.has("ap_delta"):
			parts.append("Delta %s" % _number_text(float(runner.get("ap_delta", 0.0))))
	var pending_kind := str(runner.get("pending_kind", ""))
	if not pending_kind.is_empty():
		parts.append("Pending %s" % pending_kind)
	var blocked_reason := str(runner.get("blocked_reason", ""))
	if not blocked_reason.is_empty():
		parts.append("Blocked %s" % _disabled_reason_text(blocked_reason))
	return " ".join(parts)


func _runner_interaction_phase_text(value: Variant) -> String:
	var phase: Dictionary = _dictionary_or_empty(value)
	if phase.is_empty():
		return ""
	var option_kind := str(phase.get("option_kind", "")).strip_edges()
	var visual_kind := str(phase.get("visual_kind", "")).strip_edges()
	var target_id := str(phase.get("target_id", "")).strip_edges()
	var token := "Interact"
	if not option_kind.is_empty():
		token += " %s" % option_kind
	if not visual_kind.is_empty() and visual_kind != option_kind:
		token += "/%s" % visual_kind
	if not target_id.is_empty():
		token += " -> %s" % target_id
	if bool(phase.get("approach_active", false)):
		token += " approach"
	if bool(phase.get("completed", false)):
		token += " done"
	return token


func _runner_attack_phase_text(value: Variant) -> String:
	var phase: Dictionary = _dictionary_or_empty(value)
	if phase.is_empty():
		return ""
	var source := str(phase.get("source", "")).strip_edges()
	var actor_id := int(phase.get("actor_id", 0))
	var target_actor_id := int(phase.get("target_actor_id", 0))
	var token := "Attack"
	if not source.is_empty():
		token += " %s" % source
	if actor_id > 0:
		token += " #%d" % actor_id
	if target_actor_id > 0:
		token += " -> #%d" % target_actor_id
	var hit_kind := str(phase.get("hit_kind", "")).strip_edges()
	if not hit_kind.is_empty():
		token += " %s" % hit_kind
	elif bool(phase.get("hit", false)):
		token += " hit"
	var damage := float(phase.get("damage", 0.0))
	if damage > 0.0:
		token += " %s" % _number_text(damage)
	if bool(phase.get("crit", false)):
		token += " crit"
	if bool(phase.get("defeated", false)):
		token += " defeated"
	if bool(phase.get("presentation_active", false)):
		token += " presenting"
	if bool(phase.get("completed", false)):
		token += " done"
	return token


func _runner_wait_phase_text(value: Variant) -> String:
	var phase: Dictionary = _dictionary_or_empty(value)
	if phase.is_empty():
		return ""
	var token := "Wait"
	var reason := str(phase.get("reason", "")).strip_edges()
	if not reason.is_empty() and reason != "wait":
		token += " %s" % reason
	var pending_kind := str(phase.get("pending_kind", "")).strip_edges()
	if not pending_kind.is_empty():
		token += " -> %s" % pending_kind
	if bool(phase.get("resumed_pending", false)):
		token += " resume"
	if bool(phase.get("completed", false)):
		token += " done"
	return token


func _runner_craft_phase_text(value: Variant) -> String:
	var phase: Dictionary = _dictionary_or_empty(value)
	if phase.is_empty():
		return ""
	var recipe_id := str(phase.get("recipe_id", "")).strip_edges()
	var token := "Craft"
	if not recipe_id.is_empty():
		token += " %s" % recipe_id
	var count := int(phase.get("count", 0))
	if count > 0:
		token += " x%d" % count
	var required_ap := float(phase.get("required_ap", 0.0))
	var progress_ap := float(phase.get("progress_ap", 0.0))
	var remaining_ap := float(phase.get("remaining_ap", 0.0))
	if required_ap > 0.0:
		token += " %s/%sAP" % [_number_text(progress_ap), _number_text(required_ap)]
	if remaining_ap > 0.0:
		token += " remain %s" % _number_text(remaining_ap)
	if bool(phase.get("queue_active", false)):
		token += " queue"
	if bool(phase.get("pending", false)):
		token += " pending"
	if bool(phase.get("completed", false)):
		token += " done"
	return token


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
