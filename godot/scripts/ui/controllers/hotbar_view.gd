extends RefCounted

const MediaTextureLoader = preload("res://scripts/ui/media_texture_loader.gd")

var _owner: Control
var _group_box: HBoxContainer
var _slot_box: HBoxContainer


func build(parent: Control, owner: Control) -> void:
	if _slot_box != null:
		return
	_owner = owner
	_group_box = HBoxContainer.new()
	_group_box.name = "HotbarGroupBar"
	_group_box.add_theme_constant_override("separation", 4)
	_slot_box = HBoxContainer.new()
	_slot_box.name = "HotbarDock"
	_slot_box.add_theme_constant_override("separation", 4)
	parent.add_child(_group_box)
	parent.add_child(_slot_box)


func apply(slots_value: Variant, group_labels_value: Variant = {}) -> void:
	if _slot_box == null:
		return
	for child in _slot_box.get_children():
		_slot_box.remove_child(child)
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
	_apply_group_buttons(slots, group_labels)
	for slot in slots:
		var slot_data: Dictionary = slot
		_slot_box.add_child(_slot_button(slot_data))


func set_visible(visible: bool) -> void:
	if _group_box != null:
		_group_box.visible = visible
	if _slot_box != null:
		_slot_box.visible = visible


func _apply_group_buttons(slots: Array, group_labels: Dictionary = {}) -> void:
	if _group_box == null:
		return
	for child in _group_box.get_children():
		_group_box.remove_child(child)
		child.free()
	var active_group_id := _active_group_id(slots)
	for index in range(1, 4):
		var group_id := "group_%d" % index
		_group_box.add_child(_group_button(group_id, active_group_id, group_labels))


func _active_group_id(slots: Array) -> String:
	for slot in slots:
		var slot_data: Dictionary = _dictionary_or_empty(slot)
		var group_id := str(slot_data.get("group_id", ""))
		if not group_id.is_empty():
			return group_id
	return "group_1"


func _group_button(group_id: String, active_group_id: String, group_labels: Dictionary = {}) -> Button:
	var button := Button.new()
	var group_label := _group_label(group_id, group_labels)
	button.name = "HotbarGroup_%s" % group_id
	button.text = group_label
	button.tooltip_text = "%s 热栏组 | Alt+%d" % [group_label, max(1, _group_index(group_id) + 1)]
	button.toggle_mode = true
	button.button_pressed = group_id == active_group_id
	button.custom_minimum_size = Vector2(max(38, group_label.length() * 10 + 18), 26)
	button.focus_mode = Control.FOCUS_NONE
	button.set_meta("hotbar_group_id", group_id)
	button.set_meta("active", group_id == active_group_id)
	button.set_drag_forwarding(
		Callable(self, "_empty_drag_data"),
		Callable(self, "_can_drop_group"),
		Callable(self, "_drop_group")
	)
	_prepare_group_drop_target(button)
	button.pressed.connect(func() -> void:
		_play_audio("ui_button_pressed", button.name, "hotbar_group_button", "set_hotbar_group", {
			"group_id": group_id,
			"value": group_label,
		})
		var root := _root()
		if root != null and root.has_method("set_hotbar_group"):
			root.call_deferred("set_hotbar_group", group_id)
	)
	return button


func _group_label(group_id: String, group_labels: Dictionary = {}) -> String:
	var configured_label := str(group_labels.get(group_id, "")).strip_edges()
	if not configured_label.is_empty():
		return configured_label
	var value := group_id.strip_edges().to_lower()
	if value.begins_with("group_"):
		value = value.trim_prefix("group_")
	if value.is_valid_int():
		return "G%d" % int(value)
	return group_id


func _group_index(group_id: String) -> int:
	var value := group_id.strip_edges().to_lower()
	if value.begins_with("group_"):
		value = value.trim_prefix("group_")
	if not value.is_valid_int():
		return -1
	return int(value) - 1


func _slot_button(slot: Dictionary) -> Button:
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
	_apply_icon(button, slot)
	button.set_drag_forwarding(
		Callable(self, "_empty_drag_data"),
		Callable(self, "_can_drop_skill"),
		Callable(self, "_drop_skill")
	)
	_prepare_slot_drop_target(button)
	if bool(slot.get("empty", true)):
		button.text = "%s:-" % key_label
		button.tooltip_text = "%s 热栏 %s：空 | 可拖入主动技能" % [group_label, key_label]
		return button
	var suffix := " cd%.0f" % cooldown if cooldown > 0.0 else ""
	if kind == "item" and int(slot.get("item_count", 0)) > 0:
		suffix = " x%d%s" % [int(slot.get("item_count", 0)), suffix]
	button.text = "%s:%s%s" % [key_label, _short_label(entry_label), suffix]
	button.tooltip_text = _tooltip(key_label, group_label, kind, entry_label, slot)
	button.disabled = cooldown > 0.0 or not can_use
	button.pressed.connect(func() -> void:
		_play_audio("ui_button_pressed", button.name, "hotbar_slot_button", "use_hotbar_slot", _audio_payload(slot))
		var root := _root()
		if root != null and root.has_method("use_hotbar_slot"):
			root.call_deferred("use_hotbar_slot", slot_id)
	)
	_add_cooldown_mask(button, slot_id, cooldown)
	return button


func _apply_icon(button: Button, slot: Dictionary) -> void:
	var icon_asset := _dictionary_or_empty(slot.get("icon_asset", {}))
	var texture := MediaTextureLoader.texture_from_asset(icon_asset)
	if texture == null:
		button.icon = null
		return
	button.icon = texture
	button.expand_icon = true
	button.set_meta("icon_resource_path", MediaTextureLoader.resource_path_from_asset(icon_asset))
	button.set_meta("icon_fallback_key", str(icon_asset.get("fallback_key", "")))


func _play_audio(event_kind: String, control_name: String, control_kind: String, action: String, extra_payload: Dictionary = {}) -> Dictionary:
	var root := _root()
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


func _audio_payload(slot: Dictionary, extra_payload: Dictionary = {}) -> Dictionary:
	var payload := {
		"slot_id": str(slot.get("slot_id", "")),
		"group_id": str(slot.get("group_id", "")),
		"skill_id": str(slot.get("skill_id", "")),
		"item_id": str(slot.get("item_id", "")),
		"value": str(slot.get("label", "")),
		"count": int(slot.get("item_count", 0)),
	}
	for key in extra_payload.keys():
		payload[key] = extra_payload[key]
	return payload


func _add_cooldown_mask(button: Button, slot_id: String, cooldown: float) -> void:
	var mask := ColorRect.new()
	mask.name = "HotbarCooldownMask_%s" % slot_id
	mask.visible = cooldown > 0.0
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.color = Color(0.08, 0.12, 0.16, 0.58)
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.set_meta("cooldown_remaining", cooldown)
	button.add_child(mask)


func _tooltip(key_label: String, group_label: String, kind: String, entry_label: String, slot: Dictionary) -> String:
	var parts: Array[String] = [
		"%s 热栏 %s" % [group_label, key_label],
		"物品" if kind == "item" else "技能",
		entry_label,
	]
	var cost_text := _cost_text(slot)
	if not cost_text.is_empty():
		parts.append(cost_text)
	var effect_text := _effect_text(slot)
	if not effect_text.is_empty():
		parts.append(effect_text)
	parts.append(_use_state_text(slot))
	return " | ".join(parts)


func _cost_text(slot: Dictionary) -> String:
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


func _effect_text(slot: Dictionary) -> String:
	var effects: Array[String] = []
	for effect in _array_or_empty(slot.get("effect_summary", [])):
		var effect_text := str(effect)
		if not effect_text.is_empty():
			effects.append(effect_text)
	if effects.is_empty():
		return ""
	return "效果 %s" % " / ".join(effects)


func _use_state_text(slot: Dictionary) -> String:
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


func _empty_drag_data(_position: Vector2, _from_control: Control) -> Variant:
	return null


func _can_drop_group(_position: Vector2, data: Variant, from_control: Control) -> bool:
	var drag_data: Dictionary = _dictionary_or_empty(data)
	var reject_reason := "hotbar_group_drag_unsupported" if not drag_data.is_empty() else ""
	_apply_group_drag_hover(from_control, reject_reason)
	return false


func _drop_group(_position: Vector2, _data: Variant, from_control: Control) -> void:
	_clear_group_drag_hover(from_control)


func _can_drop_skill(_position: Vector2, data: Variant, from_control: Control) -> bool:
	var drag_data: Dictionary = _dictionary_or_empty(data)
	var acceptance: Dictionary = _drop_acceptance(from_control, drag_data)
	var accepted := bool(acceptance.get("accept", false))
	_apply_slot_drag_hover(from_control, accepted, str(acceptance.get("reason", "")))
	return accepted


func _drop_skill(position: Vector2, data: Variant, from_control: Control) -> void:
	if not _can_drop_skill(position, data, from_control):
		return
	var drag_data: Dictionary = _dictionary_or_empty(data)
	var slot_id := str(from_control.get_meta("hotbar_slot_id", ""))
	var skill_id := str(drag_data.get("skill_id", ""))
	if slot_id.is_empty() or skill_id.is_empty():
		return
	var root := _root()
	_clear_slot_drag_hover(from_control)
	if root != null and root.has_method("bind_player_skill_to_hotbar"):
		root.bind_player_skill_to_hotbar(slot_id, skill_id)


func _prepare_group_drop_target(control: Control) -> void:
	if control == null:
		return
	control.set_meta("hotbar_group_drag_hovered", false)
	control.set_meta("hotbar_group_drag_last_accept", false)
	control.set_meta("hotbar_group_drag_reject_reason", "")
	control.set_meta("hotbar_group_drag_highlight_style", "")
	control.set_meta("hotbar_group_drag_highlight_color", "")
	control.mouse_exited.connect(func() -> void:
		_clear_group_drag_hover(control)
	)


func _apply_group_drag_hover(control: Control, reject_reason: String) -> void:
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


func _clear_group_drag_hover(control: Control) -> void:
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


func _prepare_slot_drop_target(control: Control) -> void:
	if control == null:
		return
	control.set_meta("hotbar_drag_hovered", false)
	control.set_meta("hotbar_drag_last_accept", false)
	control.set_meta("hotbar_drag_reject_reason", "")
	control.set_meta("hotbar_drag_highlight_style", "")
	control.set_meta("hotbar_drag_highlight_color", "")
	control.mouse_exited.connect(func() -> void:
		_clear_slot_drag_hover(control)
	)


func _drop_acceptance(control: Control, drag_data: Dictionary) -> Dictionary:
	if control == null or not is_instance_valid(control) or not control.has_meta("hotbar_slot_id"):
		return {"accept": false, "reason": "hotbar_slot_missing_slot"}
	if str(drag_data.get("kind", "")) != "skill_hotbar":
		return {"accept": false, "reason": "hotbar_slot_requires_skill_hotbar"}
	if str(drag_data.get("skill_id", "")).is_empty():
		return {"accept": false, "reason": "hotbar_slot_missing_skill"}
	return {"accept": true, "reason": ""}


func _apply_slot_drag_hover(control: Control, accepted: bool, reject_reason: String) -> void:
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


func _clear_slot_drag_hover(control: Control) -> void:
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


func _short_label(label: String) -> String:
	if label.length() <= 4:
		return label
	return label.substr(0, 4)


func _root() -> Node:
	return _owner.get_parent() if _owner != null else null


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
