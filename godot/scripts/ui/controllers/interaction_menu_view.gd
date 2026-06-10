extends RefCounted

const ReasonCatalog = preload("res://scripts/ui/snapshots/reason_catalog.gd")

var _menu: PanelContainer
var _title_label: Label
var _summary_label: Label
var _hover_label: Label
var _options_box: VBoxContainer
var _owner: Control
var _snapshot: Dictionary = {}
var _reason_catalog := ReasonCatalog.new()


func build(owner: Control) -> void:
	if _menu != null:
		return
	_owner = owner
	_menu = PanelContainer.new()
	_menu.name = "InteractionMenu"
	_menu.visible = false
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.custom_minimum_size = Vector2(180, 32)
	owner.add_child(_menu)

	var box := VBoxContainer.new()
	box.name = "MenuLines"
	box.add_theme_constant_override("separation", 4)
	_menu.add_child(box)

	_title_label = _line("MenuTitle")
	_summary_label = _line("MenuSummary")
	_hover_label = _line("MenuHoverHint")
	_options_box = VBoxContainer.new()
	_options_box.name = "MenuOptions"
	_options_box.add_theme_constant_override("separation", 3)
	box.add_child(_title_label)
	box.add_child(_summary_label)
	box.add_child(_options_box)
	box.add_child(_hover_label)


func apply(interaction: Dictionary) -> void:
	if _menu == null:
		return
	var has_target: bool = bool(interaction.get("has_target", false))
	if not has_target:
		_clear_options()
		_summary_label.text = ""
		_hover_label.text = ""
		return
	_title_label.text = str(interaction.get("target_name", "目标"))
	_summary_label.text = _summary(interaction)
	_hover_label.text = "悬停查看动作详情"
	_clear_options()
	for option in interaction.get("options", []):
		var option_data: Dictionary = option
		_options_box.add_child(_option_button(option_data))
	for option in interaction.get("disabled_options", []):
		var option_data: Dictionary = option
		_options_box.add_child(_disabled_option_button(option_data))


func show(screen_position: Vector2, prompt: Dictionary) -> void:
	if _menu == null:
		return
	var menu_prompt := _prompt_summary(prompt)
	apply(menu_prompt)
	_menu.visible = bool(prompt.get("ok", prompt.get("has_target", false)))
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP if _menu.visible else Control.MOUSE_FILTER_IGNORE
	_menu.position = _menu_position(screen_position)
	_snapshot = _snapshot_from_prompt(menu_prompt, _menu.visible, _menu.position)


func hide() -> void:
	if _menu == null:
		return
	_menu.visible = false
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_snapshot = {}


func is_open() -> bool:
	return _menu != null and _menu.visible


func snapshot() -> Dictionary:
	if _menu == null or not _menu.visible:
		return {}
	var output := _snapshot.duplicate(true)
	if output.is_empty():
		output = {
			"id": "interaction_menu",
			"name": "interaction_menu",
			"kind": "interaction",
			"owner_panel": "hud",
		}
	output["active"] = true
	output["visible"] = true
	output["mouse_blocks_world"] = _menu.mouse_filter == Control.MOUSE_FILTER_STOP
	output["position"] = {"x": _menu.position.x, "y": _menu.position.y}
	return output


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
		_hover_label.text = _option_hover_text(option)
	)
	var option_id := str(option.get("id", ""))
	button.pressed.connect(func() -> void:
		var root := _owner.get_parent() if _owner != null else null
		if root != null and root.has_method("execute_interaction_option"):
			root.execute_interaction_option(option_id)
		hide()
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
		_hover_label.text = _option_hover_text(option)
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


func _summary(interaction: Dictionary) -> String:
	var enabled_count: int = _array_or_empty(interaction.get("options", [])).size()
	var disabled_count: int = _array_or_empty(interaction.get("disabled_options", [])).size()
	var primary := str(interaction.get("primary_option_id", ""))
	return "主动作 %s | 可用 %d | 禁用 %d" % [
		primary if not primary.is_empty() else "-",
		enabled_count,
		disabled_count,
	]


func _snapshot_from_prompt(interaction: Dictionary, visible: bool, position: Vector2) -> Dictionary:
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
		"options": _option_summaries(options),
		"disabled_options": _option_summaries(disabled_options),
		"option_details": _option_detail_map(options, disabled_options),
	}


func _option_summaries(options: Array) -> Array[Dictionary]:
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


func _option_detail_map(options: Array, disabled_options: Array) -> Dictionary:
	var output: Dictionary = {}
	for option in options:
		var data: Dictionary = _dictionary_or_empty(option)
		var option_id := str(data.get("id", ""))
		if option_id.is_empty():
			continue
		output[option_id] = _option_detail(data, true)
	for option in disabled_options:
		var data: Dictionary = _dictionary_or_empty(option)
		var option_id := str(data.get("id", ""))
		if option_id.is_empty():
			continue
		output[option_id] = _option_detail(data, false)
	return output


func _option_detail(option: Dictionary, enabled: bool) -> Dictionary:
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


func _prompt_summary(prompt: Dictionary) -> Dictionary:
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


func _menu_position(screen_position: Vector2) -> Vector2:
	var viewport_size := Vector2.ZERO if _owner == null else _owner.get_viewport_rect().size
	var menu_size := Vector2(200, max(60, 32 + _options_box.get_child_count() * 32))
	return Vector2(
		clampf(screen_position.x, 8.0, max(8.0, viewport_size.x - menu_size.x - 8.0)),
		clampf(screen_position.y, 8.0, max(8.0, viewport_size.y - menu_size.y - 8.0))
	)


func _clear_options() -> void:
	if _options_box == null:
		return
	for child in _options_box.get_children():
		_options_box.remove_child(child)
		child.free()


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
