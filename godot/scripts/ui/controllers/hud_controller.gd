extends Control

var _world_label: Label
var _player_label: Label
var _inventory_label: Label
var _interaction_label: Label
var _interaction_menu: PanelContainer
var _menu_title_label: Label
var _menu_options_box: VBoxContainer


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
	_player_label.text = "%s @ %s" % [
		player.get("display_name", ""),
		JSON.stringify(player.get("grid_position", {})),
	]
	_inventory_label.text = "Inventory %s | Dialogue %s" % [
		_inventory_text(player.get("inventory", {})),
		player.get("active_dialogue_id", ""),
	]
	_interaction_label.text = _interaction_text(interaction)
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
	panel.offset_bottom = 148
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var box := VBoxContainer.new()
	box.name = "HudLines"
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	_world_label = _line("WorldLine")
	_player_label = _line("PlayerLine")
	_inventory_label = _line("InventoryLine")
	_interaction_label = _line("InteractionLine")
	box.add_child(_world_label)
	box.add_child(_player_label)
	box.add_child(_inventory_label)
	box.add_child(_interaction_label)
	_build_interaction_menu()


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
	_menu_options_box = VBoxContainer.new()
	_menu_options_box.name = "MenuOptions"
	_menu_options_box.add_theme_constant_override("separation", 3)
	box.add_child(_menu_title_label)
	box.add_child(_menu_options_box)


func _apply_interaction_menu(interaction: Dictionary) -> void:
	if _interaction_menu == null:
		_build_interaction_menu()
	var has_target: bool = bool(interaction.get("has_target", false))
	if not has_target:
		_clear_menu_options()
		return
	_menu_title_label.text = str(interaction.get("target_name", "目标"))
	_clear_menu_options()
	for option in interaction.get("options", []):
		var option_data: Dictionary = option
		_menu_options_box.add_child(_option_button(option_data))


func _option_button(option: Dictionary) -> Button:
	var button := Button.new()
	button.name = "Option_%s" % str(option.get("id", "unknown"))
	button.text = str(option.get("display_name", option.get("id", "")))
	button.tooltip_text = "%s (%s)" % [button.text, str(option.get("kind", ""))]
	button.custom_minimum_size = Vector2(160, 28)
	var option_id := str(option.get("id", ""))
	button.pressed.connect(func() -> void:
		var root := get_parent()
		if root != null and root.has_method("execute_interaction_option"):
			root.execute_interaction_option(option_id)
		hide_interaction_menu()
	)
	return button


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
	}


func _inventory_text(inventory: Dictionary) -> String:
	if inventory.is_empty():
		return "{}"
	var parts: Array[String] = []
	for item_id in inventory.keys():
		parts.append("%s x%d" % [item_id, int(inventory[item_id])])
	parts.sort()
	return ", ".join(parts)


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
