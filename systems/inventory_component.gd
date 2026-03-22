extends Node
## InventoryComponent - role-scoped inventory storage and grid layout manager.

signal inventory_changed(actor_id: String)
signal item_added(item_id: String, count: int, total: int)
signal item_removed(item_id: String, count: int, remaining: int)

const DEFAULT_GRID_WIDTH: int = 5
const DEFAULT_GRID_HEIGHT: int = 4

var owner_actor_id: String = ""
var inventory_items: Array[Dictionary] = []
var inventory_max_slots: int = DEFAULT_GRID_WIDTH * DEFAULT_GRID_HEIGHT
var inventory_grid_width: int = DEFAULT_GRID_WIDTH
var inventory_grid_height: int = DEFAULT_GRID_HEIGHT
var inventory_instance_counter: int = 1
var _legacy_player_storage: bool = false

func initialize_for_actor(actor_id: String, initial_state: Dictionary = {}, legacy_player_storage: bool = false) -> void:
	owner_actor_id = actor_id.strip_edges()
	_legacy_player_storage = legacy_player_storage
	if initial_state.is_empty():
		_refresh_from_legacy_storage()
		return
	deserialize(initial_state)

func is_initialized() -> bool:
	return not owner_actor_id.is_empty()

func add_item(item_id: String, count: int = 1) -> bool:
	var resolved_id := ItemDatabase.resolve_item_id(str(item_id))
	if resolved_id.is_empty() or count <= 0:
		return false

	var simulated_items: Array[Dictionary] = get_items()
	var simulated_counter: int = inventory_instance_counter
	var remaining: int = count
	var is_stackable: bool = ItemDatabase.is_stackable(resolved_id) if ItemDatabase else true
	var max_stack: int = maxi(1, ItemDatabase.get_max_stack(resolved_id) if ItemDatabase else 99)

	if is_stackable:
		for entry_variant in simulated_items:
			var entry: Dictionary = entry_variant
			_normalize_inventory_entry(entry)
			if str(entry.get("id", "")) != resolved_id:
				continue
			if not str(entry.get("equipped_slot", "")).is_empty():
				continue
			var current_count: int = _to_int(entry.get("count", 1), 1)
			var free_space: int = max_stack - current_count
			if free_space <= 0:
				continue
			var to_add: int = mini(remaining, free_space)
			entry["count"] = current_count + to_add
			remaining -= to_add
			if remaining <= 0:
				break

	while remaining > 0:
		var stack_count: int = mini(remaining, max_stack if is_stackable else 1)
		simulated_items.append(_build_inventory_entry(resolved_id, stack_count, simulated_counter))
		simulated_counter += 1
		remaining -= stack_count

	var layout: Dictionary = _resolve_inventory_layout(
		simulated_items,
		inventory_grid_width,
		inventory_grid_height,
		inventory_max_slots,
		true
	)
	if not bool(layout.get("success", false)):
		return false

	_set_inventory_state(
		layout.get("items", simulated_items),
		_to_int(layout.get("active_cells", inventory_max_slots), inventory_max_slots),
		_to_int(layout.get("width", inventory_grid_width), inventory_grid_width),
		_to_int(layout.get("height", inventory_grid_height), inventory_grid_height),
		simulated_counter
	)
	var current_count := get_item_count(resolved_id)
	item_added.emit(resolved_id, count, current_count)
	_emit_inventory_changed()
	return true

func remove_item(item_id: String, count: int = 1, include_equipped: bool = false) -> bool:
	var resolved_id := ItemDatabase.resolve_item_id(str(item_id))
	if resolved_id.is_empty() or count <= 0:
		return false

	var simulated_items: Array[Dictionary] = get_items()
	var remaining: int = count
	var removed_equipped: Array[Dictionary] = []

	for entry_variant in simulated_items:
		var entry: Dictionary = entry_variant
		_normalize_inventory_entry(entry)
		if str(entry.get("id", "")) != resolved_id:
			continue
		if not include_equipped and not str(entry.get("equipped_slot", "")).is_empty():
			continue
		var entry_count: int = _to_int(entry.get("count", 1), 1)
		var remove_count: int = mini(entry_count, remaining)
		entry["count"] = entry_count - remove_count
		remaining -= remove_count
		if entry_count - remove_count <= 0 and not str(entry.get("equipped_slot", "")).is_empty():
			removed_equipped.append({
				"instance_id": str(entry.get("instance_id", "")),
				"slot": str(entry.get("equipped_slot", "")),
				"item_id": resolved_id
			})
		if remaining <= 0:
			break

	if remaining > 0:
		return false

	var filtered_items: Array[Dictionary] = []
	for entry_variant in simulated_items:
		var entry: Dictionary = entry_variant
		_normalize_inventory_entry(entry)
		if _to_int(entry.get("count", 0), 0) > 0:
			filtered_items.append(entry)

	var layout: Dictionary = _resolve_inventory_layout(
		filtered_items,
		inventory_grid_width,
		inventory_grid_height,
		inventory_max_slots,
		true
	)
	if not bool(layout.get("success", false)):
		return false

	_set_inventory_state(
		layout.get("items", filtered_items),
		_to_int(layout.get("active_cells", inventory_max_slots), inventory_max_slots),
		_to_int(layout.get("width", inventory_grid_width), inventory_grid_width),
		_to_int(layout.get("height", inventory_grid_height), inventory_grid_height),
		inventory_instance_counter
	)
	for removed in removed_equipped:
		var equip_component = _get_equipment_component()
		if equip_component and equip_component.has_method("on_inventory_item_removed"):
			equip_component.on_inventory_item_removed(
				str(removed.get("instance_id", "")),
				str(removed.get("slot", "")),
				str(removed.get("item_id", ""))
			)
	var current_count := get_item_count(resolved_id)
	item_removed.emit(resolved_id, count, current_count)
	_emit_inventory_changed()
	return true

func has_item(item_id: String, count: int = 1, include_equipped: bool = true) -> bool:
	return get_item_count(item_id, include_equipped) >= count

func get_item_count(item_id: String, include_equipped: bool = true) -> int:
	var resolved_id := ItemDatabase.resolve_item_id(str(item_id))
	if resolved_id.is_empty():
		return 0
	var total := 0
	for entry_variant in get_items():
		var entry: Dictionary = entry_variant
		_normalize_inventory_entry(entry)
		if str(entry.get("id", "")) != resolved_id:
			continue
		if not include_equipped and not str(entry.get("equipped_slot", "")).is_empty():
			continue
		total += _to_int(entry.get("count", 0), 0)
	return total

func get_items() -> Array[Dictionary]:
	if _legacy_player_storage and GameState != null:
		var legacy_items: Array[Dictionary] = []
		for entry_variant in GameState.inventory_items:
			if entry_variant is Dictionary:
				legacy_items.append((entry_variant as Dictionary).duplicate(true))
		return legacy_items
	return inventory_items.duplicate(true)

func get_visible_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry_variant in get_items():
		var entry: Dictionary = entry_variant
		_normalize_inventory_entry(entry)
		if str(entry.get("equipped_slot", "")).is_empty():
			result.append(entry)
	return result

func get_inventory_item(instance_id: String) -> Dictionary:
	if instance_id.is_empty():
		return {}
	for entry_variant in get_items():
		var entry: Dictionary = entry_variant
		_normalize_inventory_entry(entry)
		if str(entry.get("instance_id", "")) == instance_id:
			return entry.duplicate(true)
	return {}

func find_first_available_item_instance(item_id: String) -> String:
	var resolved_id := ItemDatabase.resolve_item_id(str(item_id))
	for entry_variant in get_items():
		var entry: Dictionary = entry_variant
		_normalize_inventory_entry(entry)
		if str(entry.get("id", "")) != resolved_id:
			continue
		if not str(entry.get("equipped_slot", "")).is_empty():
			continue
		return str(entry.get("instance_id", ""))
	return ""

func get_equipped_item_instance(slot: String) -> String:
	for entry_variant in get_items():
		var entry: Dictionary = entry_variant
		_normalize_inventory_entry(entry)
		if str(entry.get("equipped_slot", "")) == slot:
			return str(entry.get("instance_id", ""))
	return ""

func set_inventory_item_equipped_slot(instance_id: String, slot: String) -> bool:
	var items := get_items()
	for entry_variant in items:
		var entry: Dictionary = entry_variant
		_normalize_inventory_entry(entry)
		if str(entry.get("instance_id", "")) != instance_id:
			continue
		entry["equipped_slot"] = slot
		_set_inventory_state(items, inventory_max_slots, inventory_grid_width, inventory_grid_height, inventory_instance_counter)
		return true
	return false

func move_item_instance(instance_id: String, target_cell: Vector2i) -> bool:
	if instance_id.is_empty():
		return false
	var items := get_items()
	var entry := get_inventory_item(instance_id)
	if entry.is_empty():
		return false
	if not str(entry.get("equipped_slot", "")).is_empty():
		return false
	if not _can_place_entry_at(entry, target_cell, inventory_grid_width, inventory_grid_height, inventory_max_slots, instance_id):
		return false
	for entry_variant in items:
		var inventory_entry: Dictionary = entry_variant
		if str(inventory_entry.get("instance_id", "")) == instance_id:
			inventory_entry["grid_position"] = {
				"x": target_cell.x,
				"y": target_cell.y
			}
			_set_inventory_state(items, inventory_max_slots, inventory_grid_width, inventory_grid_height, inventory_instance_counter)
			_emit_inventory_changed()
			return true
	return false

func get_inventory_dimensions() -> Vector2i:
	_refresh_from_legacy_storage()
	return Vector2i(inventory_grid_width, inventory_grid_height)

func get_active_cell_count() -> int:
	_refresh_from_legacy_storage()
	return inventory_max_slots

func refresh_inventory_capacity(preserve_positions: bool = true, emit_event: bool = true) -> bool:
	var capacity: Dictionary = _resolve_inventory_capacity()
	var layout: Dictionary = _resolve_inventory_layout(
		get_items(),
		_to_int(capacity.get("width", inventory_grid_width), inventory_grid_width),
		_to_int(capacity.get("height", inventory_grid_height), inventory_grid_height),
		_to_int(capacity.get("active_cells", inventory_max_slots), inventory_max_slots),
		preserve_positions
	)
	if not bool(layout.get("success", false)):
		return false
	_set_inventory_state(
		layout.get("items", get_items()),
		_to_int(layout.get("active_cells", inventory_max_slots), inventory_max_slots),
		_to_int(layout.get("width", inventory_grid_width), inventory_grid_width),
		_to_int(layout.get("height", inventory_grid_height), inventory_grid_height),
		inventory_instance_counter
	)
	if emit_event:
		_emit_inventory_changed()
	return true

func set_inventory_from_save(
	items: Array,
	active_cells: int = DEFAULT_GRID_WIDTH * DEFAULT_GRID_HEIGHT,
	grid_width: int = DEFAULT_GRID_WIDTH,
	grid_height: int = DEFAULT_GRID_HEIGHT,
	instance_counter: int = 1
) -> void:
	var normalized_items: Array[Dictionary] = []
	for entry_variant in items:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = (entry_variant as Dictionary).duplicate(true)
		_normalize_inventory_entry(entry)
		normalized_items.append(entry)
	inventory_instance_counter = maxi(1, instance_counter)
	var layout: Dictionary = _resolve_inventory_layout(
		normalized_items,
		maxi(1, grid_width),
		maxi(1, grid_height),
		maxi(1, active_cells),
		true
	)
	_set_inventory_state(
		layout.get("items", normalized_items),
		_to_int(layout.get("active_cells", active_cells), active_cells),
		_to_int(layout.get("width", grid_width), grid_width),
		_to_int(layout.get("height", grid_height), grid_height),
		inventory_instance_counter
	)

func clear_inventory() -> void:
	_set_inventory_state([], inventory_max_slots, inventory_grid_width, inventory_grid_height, 1)
	_emit_inventory_changed()

func get_inventory_weight() -> float:
	var total := 0.0
	for entry_variant in get_items():
		var entry: Dictionary = entry_variant
		total += ItemDatabase.get_item_weight(str(entry.get("id", ""))) * _to_int(entry.get("count", 1), 1)
	return total

func serialize() -> Dictionary:
	_refresh_from_legacy_storage()
	return {
		"actor_id": owner_actor_id,
		"inventory_items": get_items(),
		"inventory_max_slots": inventory_max_slots,
		"inventory_grid_width": inventory_grid_width,
		"inventory_grid_height": inventory_grid_height,
		"inventory_instance_counter": inventory_instance_counter
	}

func deserialize(data: Dictionary) -> void:
	owner_actor_id = str(data.get("actor_id", owner_actor_id)).strip_edges()
	set_inventory_from_save(
		data.get("inventory_items", []),
		_to_int(data.get("inventory_max_slots", inventory_max_slots), inventory_max_slots),
		_to_int(data.get("inventory_grid_width", inventory_grid_width), inventory_grid_width),
		_to_int(data.get("inventory_grid_height", inventory_grid_height), inventory_grid_height),
		_to_int(data.get("inventory_instance_counter", inventory_instance_counter), inventory_instance_counter)
	)

func _refresh_from_legacy_storage() -> void:
	if not _legacy_player_storage or GameState == null:
		return
	inventory_items = GameState.inventory_items.duplicate(true)
	inventory_max_slots = _to_int(GameState.inventory_max_slots, inventory_max_slots)
	inventory_grid_width = _to_int(GameState.inventory_grid_width, inventory_grid_width)
	inventory_grid_height = _to_int(GameState.inventory_grid_height, inventory_grid_height)
	inventory_instance_counter = _to_int(GameState.get("_inventory_instance_counter"), inventory_instance_counter)

func _set_inventory_state(items: Array[Dictionary], active_cells: int, width: int, height: int, instance_counter: int) -> void:
	inventory_items = items.duplicate(true)
	inventory_max_slots = maxi(1, active_cells)
	inventory_grid_width = maxi(1, width)
	inventory_grid_height = maxi(1, height)
	inventory_instance_counter = maxi(1, instance_counter)
	if _legacy_player_storage and GameState != null:
		GameState.inventory_items = inventory_items.duplicate(true)
		GameState.inventory_max_slots = inventory_max_slots
		GameState.inventory_grid_width = inventory_grid_width
		GameState.inventory_grid_height = inventory_grid_height
		GameState.set("_inventory_instance_counter", inventory_instance_counter)

func _emit_inventory_changed() -> void:
	if owner_actor_id.is_empty():
		return
	inventory_changed.emit(owner_actor_id)
	if EventBus != null and owner_actor_id == "player":
		EventBus.emit(EventBus.EventType.INVENTORY_CHANGED, {})
	if GameState != null and GameState.has_method("on_actor_inventory_component_changed"):
		GameState.on_actor_inventory_component_changed(owner_actor_id, self)

func _resolve_inventory_capacity() -> Dictionary:
	var width: int = inventory_grid_width
	var height: int = inventory_grid_height
	var active_cells: int = inventory_max_slots
	if ItemDatabase:
		var base_size: Vector2i = ItemDatabase.get_default_inventory_grid_size()
		var equip_component = _get_equipment_component()
		if equip_component != null and equip_component.has_method("get_equipped"):
			var backpack_id: String = str(equip_component.get_equipped("back"))
			if not backpack_id.is_empty():
				base_size = ItemDatabase.get_backpack_grid_size(backpack_id)
		width = maxi(1, base_size.x)
		height = maxi(1, base_size.y)
		active_cells = maxi(1, width * height)
	var equip_component = _get_equipment_component()
	if equip_component and equip_component.has_method("get_total_stats"):
		var bonus_slots: int = maxi(0, _to_int(equip_component.get_total_stats().get("inventory_slots", 0), 0))
		active_cells += bonus_slots
		height = maxi(height, ceili(float(active_cells) / float(width)))
	return {
		"width": width,
		"height": height,
		"active_cells": active_cells
	}

func _resolve_inventory_layout(
	items: Array[Dictionary],
	width: int,
	height: int,
	active_cells: int,
	preserve_positions: bool
) -> Dictionary:
	var normalized_items: Array[Dictionary] = []
	for entry_variant in items:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = (entry_variant as Dictionary).duplicate(true)
		_normalize_inventory_entry(entry)
		normalized_items.append(entry)

	if not preserve_positions:
		for entry in normalized_items:
			entry["grid_position"] = {"x": -1, "y": -1}

	normalized_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var size_a: Vector2i = ItemDatabase.get_inventory_footprint(str(a.get("id", ""))) if ItemDatabase else Vector2i.ONE
		var size_b: Vector2i = ItemDatabase.get_inventory_footprint(str(b.get("id", ""))) if ItemDatabase else Vector2i.ONE
		var area_a: int = size_a.x * size_a.y
		var area_b: int = size_b.x * size_b.y
		if area_a == area_b:
			return str(a.get("instance_id", "")) < str(b.get("instance_id", ""))
		return area_a > area_b
	)

	var occupancy: Dictionary = {}
	for entry in normalized_items:
		if not str(entry.get("equipped_slot", "")).is_empty():
			continue
		var current_cell := Vector2i(
			_to_int((entry.get("grid_position", {}) as Dictionary).get("x", -1), -1),
			_to_int((entry.get("grid_position", {}) as Dictionary).get("y", -1), -1)
		)
		if preserve_positions and current_cell.x >= 0 and current_cell.y >= 0:
			if _can_place_entry_at(entry, current_cell, width, height, active_cells, str(entry.get("instance_id", "")), occupancy):
				_occupy_entry(entry, occupancy, width, current_cell)
				continue
		var placed := false
		for y in range(height):
			for x in range(width):
				var candidate := Vector2i(x, y)
				if _can_place_entry_at(entry, candidate, width, height, active_cells, str(entry.get("instance_id", "")), occupancy):
					entry["grid_position"] = {"x": x, "y": y}
					_occupy_entry(entry, occupancy, width, candidate)
					placed = true
					break
			if placed:
				break
		if not placed:
			return {
				"success": false,
				"items": items,
				"width": width,
				"height": height,
				"active_cells": active_cells
			}

	return {
		"success": true,
		"items": normalized_items,
		"width": width,
		"height": height,
		"active_cells": active_cells
	}

func _can_place_entry_at(
	entry: Dictionary,
	target_cell: Vector2i,
	width: int,
	height: int,
	active_cells: int,
	ignore_instance_id: String = "",
	occupancy_override: Dictionary = {}
) -> bool:
	var occupancy: Dictionary = occupancy_override if not occupancy_override.is_empty() else _build_inventory_occupancy(ignore_instance_id)
	var footprint: Vector2i = ItemDatabase.get_inventory_footprint(str(entry.get("id", ""))) if ItemDatabase else Vector2i.ONE
	for y_offset in range(footprint.y):
		for x_offset in range(footprint.x):
			var cell := Vector2i(target_cell.x + x_offset, target_cell.y + y_offset)
			if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
				return false
			if not _is_inventory_cell_active(cell, width, active_cells):
				return false
			var cell_key: int = _inventory_cell_index(cell, width)
			if occupancy.has(cell_key):
				return false
	return true

func _build_inventory_occupancy(ignore_instance_id: String = "") -> Dictionary:
	var occupancy: Dictionary = {}
	for entry_variant in get_items():
		var entry: Dictionary = entry_variant
		_normalize_inventory_entry(entry)
		if not str(entry.get("equipped_slot", "")).is_empty():
			continue
		if str(entry.get("instance_id", "")) == ignore_instance_id:
			continue
		_occupy_entry(entry, occupancy, inventory_grid_width)
	return occupancy

func _occupy_entry(entry: Dictionary, occupancy: Dictionary, width: int, override_cell: Vector2i = Vector2i(-1, -1)) -> void:
	var start_cell := override_cell
	if start_cell.x < 0 or start_cell.y < 0:
		var grid_position: Dictionary = entry.get("grid_position", {})
		start_cell = Vector2i(_to_int(grid_position.get("x", 0), 0), _to_int(grid_position.get("y", 0), 0))
	var footprint: Vector2i = ItemDatabase.get_inventory_footprint(str(entry.get("id", ""))) if ItemDatabase else Vector2i.ONE
	for y_offset in range(footprint.y):
		for x_offset in range(footprint.x):
			var cell := Vector2i(start_cell.x + x_offset, start_cell.y + y_offset)
			occupancy[_inventory_cell_index(cell, width)] = str(entry.get("instance_id", ""))

func _is_inventory_cell_active(cell: Vector2i, width: int, active_cells: int) -> bool:
	return _inventory_cell_index(cell, width) < active_cells

func _inventory_cell_index(cell: Vector2i, width: int) -> int:
	return (cell.y * width) + cell.x

func _build_inventory_entry(item_id: String, count: int, instance_seed: int) -> Dictionary:
	return {
		"id": item_id,
		"count": count,
		"instance_id": "inv_%d" % instance_seed,
		"grid_position": {"x": -1, "y": -1},
		"equipped_slot": ""
	}

func _normalize_inventory_entry(entry: Dictionary) -> void:
	if str(entry.get("instance_id", "")).is_empty():
		entry["instance_id"] = "inv_%d" % inventory_instance_counter
		inventory_instance_counter += 1
	if not entry.has("grid_position") or not (entry.get("grid_position") is Dictionary):
		entry["grid_position"] = {"x": -1, "y": -1}
	if not entry.has("equipped_slot"):
		entry["equipped_slot"] = ""
	if not entry.has("count"):
		entry["count"] = 1

func _get_equipment_component() -> Node:
	var parent_node := get_parent()
	if parent_node and parent_node.has_method("get_equipment_component"):
		return parent_node.get_equipment_component()
	return get_node_or_null("../EquipmentSystem")

func _to_int(value: Variant, default_value: int) -> int:
	if value == null:
		return default_value
	return int(value)
