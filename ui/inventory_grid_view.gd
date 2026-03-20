extends Control

class_name InventoryGridView

const InventoryGridItem = preload("res://ui/inventory_grid_item.gd")

signal item_hovered(instance_id: String)
signal item_unhovered(instance_id: String)
signal item_selected(instance_id: String)
signal grid_interaction(message: String)

@export var cell_size: float = 42.0

var grid_width: int = 5
var grid_height: int = 4
var active_cells: int = 20
var _items_root: Control = null
var _item_controls: Dictionary = {}
var _selected_instance_id: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_items_root = Control.new()
	_items_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_items_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_items_root)
	_refresh_size()


func configure(next_width: int, next_height: int, next_active_cells: int, items: Array[Dictionary]) -> void:
	grid_width = maxi(1, next_width)
	grid_height = maxi(1, next_height)
	active_cells = maxi(1, next_active_cells)
	_refresh_size()
	_rebuild_items(items)
	queue_redraw()


func set_selected_instance(instance_id: String) -> void:
	_selected_instance_id = instance_id
	for key in _item_controls.keys():
		var item_control = _item_controls[key]
		if item_control is InventoryGridItem:
			(item_control as InventoryGridItem).set_selected(str(key) == instance_id)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var payload: Dictionary = data as Dictionary
	var payload_type: String = str(payload.get("type", ""))
	return payload_type == "inventory_item" or payload_type == "equipped_item"


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not (data is Dictionary):
		return
	var payload: Dictionary = data as Dictionary
	var payload_type: String = str(payload.get("type", ""))
	var instance_id: String = str(payload.get("instance_id", ""))
	var target_cell := _position_to_cell(at_position)
	match payload_type:
		"inventory_item":
			if not InventoryModule or not InventoryModule.has_method("move_item_instance"):
				grid_interaction.emit("背包系统不可用")
				return
			if InventoryModule.move_item_instance(instance_id, target_cell):
				grid_interaction.emit("已移动物品")
			else:
				grid_interaction.emit("该位置放不下这个物品")
		"equipped_item":
			var equip_system = GameState.get_equipment_system() if GameState else null
			if equip_system == null or not equip_system.has_method("unequip_to_cell"):
				grid_interaction.emit("装备系统不可用")
				return
			var slot_name: String = str(payload.get("slot", ""))
			if equip_system.unequip_to_cell(slot_name, target_cell):
				grid_interaction.emit("已卸下到背包")
			else:
				grid_interaction.emit("目标格子放不下该装备")


func _draw() -> void:
	var active_color := Color(0.17, 0.21, 0.25, 0.92)
	var inactive_color := Color(0.10, 0.10, 0.12, 0.45)
	var border_color := Color(0.33, 0.39, 0.44, 1.0)
	for y in range(grid_height):
		for x in range(grid_width):
			var rect := Rect2(Vector2(x, y) * cell_size, Vector2.ONE * cell_size)
			draw_rect(rect, active_color if _is_cell_active(Vector2i(x, y)) else inactive_color, true)
			draw_rect(rect, border_color, false, 1.0)


func _refresh_size() -> void:
	custom_minimum_size = Vector2(float(grid_width) * cell_size, float(grid_height) * cell_size)
	if _items_root != null:
		_items_root.custom_minimum_size = custom_minimum_size


func _rebuild_items(items: Array[Dictionary]) -> void:
	if _items_root == null:
		return
	for child in _items_root.get_children():
		child.queue_free()
	_item_controls.clear()

	for entry_variant in items:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var instance_id: String = str(entry.get("instance_id", ""))
		var item_id: String = str(entry.get("id", ""))
		if instance_id.is_empty() or item_id.is_empty():
			continue
		var item_data: Dictionary = ItemDatabase.get_item(item_id) if ItemDatabase else {}
		var footprint: Vector2i = ItemDatabase.get_inventory_footprint(item_id) if ItemDatabase else Vector2i.ONE
		var control := InventoryGridItem.new()
		control.configure(entry, item_data, footprint, cell_size)
		control.position = _entry_position(entry)
		control.item_hovered.connect(func(next_instance_id: String) -> void:
			item_hovered.emit(next_instance_id)
		)
		control.item_unhovered.connect(func(next_instance_id: String) -> void:
			item_unhovered.emit(next_instance_id)
		)
		control.item_selected.connect(func(next_instance_id: String) -> void:
			set_selected_instance(next_instance_id)
			item_selected.emit(next_instance_id)
		)
		_items_root.add_child(control)
		_item_controls[instance_id] = control

	set_selected_instance(_selected_instance_id)


func _entry_position(entry: Dictionary) -> Vector2:
	var grid_position: Dictionary = entry.get("grid_position", {})
	return Vector2(
		float(int(grid_position.get("x", 0))) * cell_size,
		float(int(grid_position.get("y", 0))) * cell_size
	)


func _position_to_cell(position: Vector2) -> Vector2i:
	var clamped_x: int = maxi(0, mini(grid_width - 1, int(floor(position.x / cell_size))))
	var clamped_y: int = maxi(0, mini(grid_height - 1, int(floor(position.y / cell_size))))
	return Vector2i(clamped_x, clamped_y)


func _is_cell_active(cell: Vector2i) -> bool:
	return cell.y * grid_width + cell.x < active_cells
