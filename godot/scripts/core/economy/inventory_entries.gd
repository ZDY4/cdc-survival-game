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
	var normalized_item_id: String = normalize_content_id(item_id)
	var total := 0
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if normalize_content_id(entry_data.get("item_id", "")) == normalized_item_id:
			total += max(0, int(entry_data.get("count", 0)))
	return total


func add(entries: Array, item_id: String, delta: int) -> void:
	var normalized_item_id: String = normalize_content_id(item_id)
	if normalized_item_id.is_empty() or delta == 0:
		return
	if delta > 0:
		entries.append({"item_id": normalized_item_id, "count": delta, "price": 0})
		return
	var remaining: int = -delta
	for index in range(entries.size() - 1, -1, -1):
		if remaining <= 0:
			break
		var entry: Dictionary = _dictionary_or_empty(entries[index])
		if normalize_content_id(entry.get("item_id", "")) != normalized_item_id:
			continue
		var current_count: int = max(0, int(entry.get("count", 0)))
		var consumed: int = min(current_count, remaining)
		current_count -= consumed
		remaining -= consumed
		if current_count <= 0:
			entries.remove_at(index)
		else:
			entry["count"] = current_count
			entries[index] = entry


func remove_from_stack(entries: Array, item_id: String, delta: int, stack_index: int) -> void:
	var normalized_item_id: String = normalize_content_id(item_id)
	if normalized_item_id.is_empty() or delta <= 0:
		return
	if stack_index <= 0:
		add(entries, normalized_item_id, -delta)
		return
	var remaining: int = delta
	var current_stack_index := 0
	for index in range(entries.size()):
		if remaining <= 0:
			break
		var entry: Dictionary = _dictionary_or_empty(entries[index])
		if normalize_content_id(entry.get("item_id", "")) != normalized_item_id:
			continue
		var current_count: int = max(0, int(entry.get("count", 0)))
		if current_count <= 0:
			continue
		current_stack_index += 1
		if current_stack_index != stack_index:
			continue
		var consumed: int = min(current_count, remaining)
		current_count -= consumed
		remaining -= consumed
		if current_count <= 0:
			entries.remove_at(index)
		else:
			entry["count"] = current_count
			entries[index] = entry
		break
	if remaining > 0:
		add(entries, normalized_item_id, -remaining)


func stack_count_at(entries: Array, item_id: String, stack_index: int) -> int:
	var normalized_item_id: String = normalize_content_id(item_id)
	if normalized_item_id.is_empty() or stack_index <= 0:
		return count(entries, normalized_item_id)
	var current_stack_index := 0
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if normalize_content_id(entry_data.get("item_id", "")) != normalized_item_id:
			continue
		var current_count: int = max(0, int(entry_data.get("count", 0)))
		if current_count <= 0:
			continue
		current_stack_index += 1
		if current_stack_index == stack_index:
			return current_count
	return 0


func actor_stack_count_at(actor: RefCounted, item_id: String, stack_index: int) -> int:
	if actor == null:
		return 0
	var normalized_item_id: String = normalize_content_id(item_id)
	var total_count: int = max(0, int(actor.inventory.get(normalized_item_id, 0)))
	if normalized_item_id.is_empty() or stack_index <= 0:
		return total_count
	var stacks: Array[int] = _normalized_actor_inventory_stacks(actor, normalized_item_id, total_count)
	if stack_index > stacks.size():
		return 0
	return int(stacks[stack_index - 1])


func remove_actor_item_from_stack(actor: RefCounted, item_id: String, count: int, stack_index: int) -> void:
	if actor == null or count <= 0:
		return
	var normalized_item_id: String = normalize_content_id(item_id)
	if normalized_item_id.is_empty():
		return
	if stack_index <= 0:
		add_actor_item(actor, normalized_item_id, -count)
		return
	_sync_actor_inventory_order(actor)
	var current_count: int = max(0, int(actor.inventory.get(normalized_item_id, 0)))
	if current_count <= 0:
		return
	var remove_count: int = min(count, current_count)
	var next_count: int = current_count - remove_count
	if next_count <= 0:
		actor.inventory.erase(normalized_item_id)
		actor.inventory_order.erase(normalized_item_id)
		if "inventory_stacks" in actor:
			actor.inventory_stacks.erase(normalized_item_id)
		return
	actor.inventory[normalized_item_id] = next_count
	if not "inventory_stacks" in actor:
		return
	var stacks: Array[int] = _normalized_actor_inventory_stacks(actor, normalized_item_id, current_count)
	var remaining: int = remove_count
	var source_index: int = stack_index - 1
	if source_index >= 0 and source_index < stacks.size():
		var source_count: int = int(stacks[source_index])
		var consumed: int = min(source_count, remaining)
		source_count -= consumed
		remaining -= consumed
		if source_count <= 0:
			stacks.remove_at(source_index)
		else:
			stacks[source_index] = source_count
	if remaining > 0:
		for index in range(stacks.size() - 1, -1, -1):
			if remaining <= 0:
				break
			var stack_count: int = int(stacks[index])
			var consumed: int = min(stack_count, remaining)
			stack_count -= consumed
			remaining -= consumed
			if stack_count <= 0:
				stacks.remove_at(index)
			else:
				stacks[index] = stack_count
	actor.inventory_stacks[normalized_item_id] = _stacks_or_single_total(stacks, next_count)


func add_actor_item(actor: RefCounted, item_id: String, delta: int, item_library: Dictionary = {}) -> void:
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
		if "inventory_stacks" in actor:
			actor.inventory_stacks.erase(normalized_item_id)
	else:
		actor.inventory[normalized_item_id] = next_count
		if current_count <= 0 and not actor.inventory_order.has(normalized_item_id):
			actor.inventory_order.append(normalized_item_id)
		if "inventory_stacks" in actor:
			_apply_actor_inventory_stack_delta(actor, normalized_item_id, current_count, delta, next_count, item_library)


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
	if "inventory_stacks" in actor:
		for item_id in actor.inventory.keys():
			_sync_actor_inventory_stacks(actor, normalize_content_id(item_id))
		for item_id in actor.inventory_stacks.keys():
			if int(actor.inventory.get(item_id, 0)) <= 0:
				actor.inventory_stacks.erase(item_id)


func _sync_actor_inventory_stacks(actor: RefCounted, item_id: String) -> void:
	if actor == null or item_id.is_empty():
		return
	var total_count: int = max(0, int(actor.inventory.get(item_id, 0)))
	if total_count <= 0:
		actor.inventory_stacks.erase(item_id)
		return
	actor.inventory_stacks[item_id] = _normalized_actor_inventory_stacks(actor, item_id, total_count)


func _apply_actor_inventory_stack_delta(actor: RefCounted, item_id: String, previous_total: int, delta: int, next_total: int, item_library: Dictionary = {}) -> void:
	if actor == null or item_id.is_empty():
		return
	if next_total <= 0:
		actor.inventory_stacks.erase(item_id)
		return
	var stacks: Array[int] = _normalized_actor_inventory_stacks(actor, item_id, previous_total)
	if delta > 0:
		var max_stack: int = _item_max_stack(item_id, item_library)
		stacks = _split_stacks_by_max(stacks, max_stack)
		_append_stack_delta(stacks, delta, max_stack)
	elif delta < 0:
		var remaining: int = -delta
		for index in range(stacks.size() - 1, -1, -1):
			if remaining <= 0:
				break
			var stack_count: int = int(stacks[index])
			var consumed: int = min(stack_count, remaining)
			stack_count -= consumed
			remaining -= consumed
			if stack_count <= 0:
				stacks.remove_at(index)
			else:
				stacks[index] = stack_count
	actor.inventory_stacks[item_id] = _stacks_or_single_total(stacks, next_total)


func _normalized_actor_inventory_stacks(actor: RefCounted, item_id: String, total_count: int) -> Array[int]:
	var stacks: Array[int] = []
	for stack_count in _array_or_empty(actor.inventory_stacks.get(item_id, [])):
		var count: int = max(0, int(stack_count))
		if count > 0:
			stacks.append(count)
	return _stacks_or_single_total(stacks, total_count)


func _stacks_or_single_total(stacks: Array[int], total_count: int) -> Array[int]:
	var stack_sum := 0
	for count in stacks:
		stack_sum += count
	if stacks.is_empty() or stack_sum != total_count:
		stacks = [total_count]
	return stacks


func _append_stack_delta(stacks: Array[int], delta: int, max_stack: int) -> void:
	var remaining: int = max(0, delta)
	if remaining <= 0:
		return
	if max_stack <= 0:
		stacks.append(remaining)
		return
	for index in range(stacks.size()):
		if remaining <= 0:
			break
		var stack_count: int = int(stacks[index])
		var room: int = max(0, max_stack - stack_count)
		if room > 0:
			var filled: int = min(room, remaining)
			stacks[index] = stack_count + filled
			remaining -= filled
	while remaining > 0:
		var stack_count: int = min(max_stack, remaining)
		stacks.append(stack_count)
		remaining -= stack_count


func _split_stacks_by_max(stacks: Array[int], max_stack: int) -> Array[int]:
	if max_stack <= 0:
		return stacks
	var output: Array[int] = []
	for stack in stacks:
		var remaining: int = max(0, int(stack))
		while remaining > 0:
			var stack_count: int = min(max_stack, remaining)
			output.append(stack_count)
			remaining -= stack_count
	return output


func _item_max_stack(item_id: String, item_library: Dictionary) -> int:
	if item_library.is_empty():
		return 0
	var record: Dictionary = _dictionary_or_empty(item_library.get(item_id, {}))
	var data: Dictionary = _dictionary_or_empty(record.get("data", record))
	if data.is_empty():
		return 0
	for fragment in _array_or_empty(data.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == "stacking":
			if not bool(fragment_data.get("stackable", false)):
				return 1
			return max(1, int(fragment_data.get("max_stack", 1)))
	return 0
