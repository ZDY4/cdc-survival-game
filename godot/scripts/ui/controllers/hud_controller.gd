extends Control

var _world_label: Label
var _player_label: Label
var _inventory_label: Label
var _interaction_label: Label


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


func _line(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = true
	return label


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
