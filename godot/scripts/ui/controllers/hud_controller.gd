extends Control

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
var controls_hint_visible := false


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
	_debug_overlay_label.text = "Overlay %s" % str(snapshot.get("debug_overlay_mode", "off"))
	_info_panel_label.text = _info_panel_text(snapshot.get("info_panel", {}))
	_runtime_control_label.text = _runtime_control_text(snapshot.get("runtime_control", {}))
	_skill_targeting_label.text = _skill_targeting_text(_dictionary_or_empty(snapshot.get("runtime_control", {})).get("skill_targeting", {}))
	_skill_targeting_label.visible = not _skill_targeting_label.text.is_empty()
	_apply_controls_hint()
	_apply_interaction_menu(interaction)


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
		"右键菜单 | 中键拖拽相机 | F 跟随 | V 覆盖层 | [/] 信息页 | A 自动推进 | +/- 缩放",
	]:
		var label := _line("ControlsHintLine")
		label.text = line
		_controls_hint_box.add_child(label)
	_build_interaction_menu()


func toggle_controls_hint() -> Dictionary:
	controls_hint_visible = not controls_hint_visible
	_apply_controls_hint()
	return {"success": true, "visible": controls_hint_visible}


func is_controls_hint_visible() -> bool:
	return controls_hint_visible


func show_interaction_menu(screen_position: Vector2, prompt: Dictionary) -> void:
	if _interaction_menu == null:
		_build_interaction_menu()
	_apply_interaction_menu(_prompt_summary_for_menu(prompt))
	_interaction_menu.visible = bool(prompt.get("ok", prompt.get("has_target", false)))
	_interaction_menu.mouse_filter = Control.MOUSE_FILTER_STOP if _interaction_menu.visible else Control.MOUSE_FILTER_IGNORE
	_interaction_menu.position = _menu_position(screen_position)


func hide_interaction_menu() -> void:
	if _interaction_menu == null:
		return
	_interaction_menu.visible = false
	_interaction_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_interaction_menu_open() -> bool:
	return _interaction_menu != null and _interaction_menu.visible


func _line(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = true
	return label


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
	button.set_meta("option_kind", str(option.get("kind", "")))
	button.set_meta("ap_cost", float(option.get("ap_cost", 0.0)))
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
	button.name = "DisabledOption_%s" % option_id
	button.text = "%s - %s" % [
		str(option.get("display_name", option_id)),
		_disabled_reason_text(reason),
	]
	button.tooltip_text = "%s | %s" % [_option_tooltip(option), reason]
	button.custom_minimum_size = Vector2(160, 28)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = true
	button.set_meta("option_id", option_id)
	button.set_meta("option_kind", str(option.get("kind", "")))
	button.set_meta("disabled_reason", reason)
	button.set_meta("ap_cost", float(option.get("ap_cost", 0.0)))
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


func _interaction_menu_summary(interaction: Dictionary) -> String:
	var enabled_count: int = _array_or_empty(interaction.get("options", [])).size()
	var disabled_count: int = _array_or_empty(interaction.get("disabled_options", [])).size()
	var primary := str(interaction.get("primary_option_id", ""))
	return "主动作 %s | 可用 %d | 禁用 %d" % [
		primary if not primary.is_empty() else "-",
		enabled_count,
		disabled_count,
	]


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
		"interaction_option_unavailable":
			return "不可用"
	if reason.is_empty():
		return "不可用"
	return reason


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
	button.set_drag_forwarding(
		Callable(self, "_empty_hotbar_drag_data"),
		Callable(self, "_can_drop_hotbar_skill"),
		Callable(self, "_drop_hotbar_skill")
	)
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
		state = "%s | 暂不可切换" % state
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


func _can_drop_hotbar_skill(_position: Vector2, data: Variant, from_control: Control) -> bool:
	var drag_data: Dictionary = _dictionary_or_empty(data)
	if str(drag_data.get("kind", "")) != "skill_hotbar":
		return false
	if str(drag_data.get("skill_id", "")).is_empty():
		return false
	return from_control != null and from_control.has_meta("hotbar_slot_id")


func _drop_hotbar_skill(position: Vector2, data: Variant, from_control: Control) -> void:
	if not _can_drop_hotbar_skill(position, data, from_control):
		return
	var drag_data: Dictionary = _dictionary_or_empty(data)
	var slot_id := str(from_control.get_meta("hotbar_slot_id", ""))
	var skill_id := str(drag_data.get("skill_id", ""))
	if slot_id.is_empty() or skill_id.is_empty():
		return
	var root := get_parent()
	if root != null and root.has_method("bind_player_skill_to_hotbar"):
		root.bind_player_skill_to_hotbar(slot_id, skill_id)


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
	var ui_blocker := str(control_data.get("ui_blocker", ""))
	if not ui_blocker.is_empty():
		parts.append("Blocker %s" % ui_blocker)
	var hover_text := _hover_control_text(control_data.get("hover", {}))
	if not hover_text.is_empty():
		parts.append(hover_text)
	var selection_debug_text := _selection_debug_control_text(control_data.get("selection_debug", {}))
	if not selection_debug_text.is_empty():
		parts.append(selection_debug_text)
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
	return reason


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
