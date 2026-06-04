extends RefCounted


func normalize(entries: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for entry in _array_or_empty(entries):
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var item_id: String = normalize_content_id(entry_data.get("item_id", entry_data.get("itemId", "")))
		var count: int = max(0, int(entry_data.get("count", 0)))
		if item_id.is_empty() or count <= 0:
			continue
		output.append({
			"item_id": item_id,
			"count": count,
			"price": int(entry_data.get("price", 0)),
		})
	return output


func count(entries: Array, item_id: String) -> int:
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if normalize_content_id(entry_data.get("item_id", "")) == item_id:
			return int(entry_data.get("count", 0))
	return 0


func add(entries: Array, item_id: String, delta: int) -> void:
	for i in range(entries.size()):
		var entry: Dictionary = _dictionary_or_empty(entries[i])
		if normalize_content_id(entry.get("item_id", "")) == item_id:
			var next_count: int = int(entry.get("count", 0)) + delta
			if next_count <= 0:
				entries.remove_at(i)
			else:
				entry["count"] = next_count
				entries[i] = entry
			return
	if delta > 0:
		entries.append({"item_id": item_id, "count": delta, "price": 0})


func add_actor_item(actor: RefCounted, item_id: String, delta: int) -> void:
	if actor == null:
		return
	var normalized_item_id: String = normalize_content_id(item_id)
	if normalized_item_id.is_empty():
		return
	_sync_actor_inventory_order(actor)
	var current_count: int = int(actor.inventory.get(normalized_item_id, 0))
	var next_count: int = current_count + delta
	if next_count <= 0:
		actor.inventory.erase(normalized_item_id)
		actor.inventory_order.erase(normalized_item_id)
	else:
		actor.inventory[normalized_item_id] = next_count
		if current_count <= 0 and not actor.inventory_order.has(normalized_item_id):
			actor.inventory_order.append(normalized_item_id)


func sync_actor_inventory_order(actor: RefCounted) -> void:
	_sync_actor_inventory_order(actor)


func normalize_content_id(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT:
		var float_value: float = value
		if is_equal_approx(float_value, round(float_value)):
			return str(int(round(float_value)))
	return str(value)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _sync_actor_inventory_order(actor: RefCounted) -> void:
	if actor == null:
		return
	var ordered: Array[String] = []
	for item_id in _array_or_empty(actor.inventory_order):
		var normalized_id: String = normalize_content_id(item_id)
		if normalized_id.is_empty() or ordered.has(normalized_id):
			continue
		if int(actor.inventory.get(normalized_id, 0)) > 0:
			ordered.append(normalized_id)
	var remaining: Array = actor.inventory.keys()
	remaining.sort()
	for item_id in remaining:
		var normalized_id: String = normalize_content_id(item_id)
		if normalized_id.is_empty() or ordered.has(normalized_id):
			continue
		if int(actor.inventory.get(normalized_id, 0)) > 0:
			ordered.append(normalized_id)
	actor.inventory_order = ordered
