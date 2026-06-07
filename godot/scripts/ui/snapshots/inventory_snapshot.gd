extends RefCounted

const InventoryCapacity = preload("res://scripts/core/economy/inventory_capacity.gd")
const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")
const ReasonCatalog = preload("res://scripts/ui/snapshots/reason_catalog.gd")

var registry: RefCounted
var _inventory_capacity := InventoryCapacity.new()
var _reason_catalog := ReasonCatalog.new()


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary, feedback: Dictionary = {}, crafting_context: Dictionary = {}) -> Dictionary:
	var player: Dictionary = _player_actor(runtime_snapshot)
	var inventory: Dictionary = _dictionary_or_empty(player.get("inventory", {}))
	var inventory_stacks: Dictionary = _dictionary_or_empty(player.get("inventory_stacks", {}))
	var tool_durability: Dictionary = _dictionary_or_empty(player.get("tool_durability", {}))
	var equipment: Dictionary = _dictionary_or_empty(player.get("equipment", {}))
	var inventory_order: Array[String] = _inventory_order(player.get("inventory_order", []), inventory)
	var items: Array[Dictionary] = []
	var total_weight := 0.0
	for order_index in range(inventory_order.size()):
		var item_id: String = inventory_order[order_index]
		var count: int = int(inventory.get(item_id, 0))
		if count <= 0:
			continue
		var item_snapshot: Dictionary = _item_snapshot(player, str(item_id), count, tool_durability, inventory, equipment, crafting_context)
		item_snapshot["order_index"] = order_index
		item_snapshot["stack_counts"] = _stack_counts_for(str(item_id), count, inventory_stacks)
		item_snapshot["stack_count"] = _array_or_empty(item_snapshot.get("stack_counts", [])).size()
		item_snapshot["can_split_stack"] = bool(item_snapshot.get("stackable", false)) and _largest_stack_count(_array_or_empty(item_snapshot.get("stack_counts", []))) > 1
		total_weight += float(item_snapshot.get("total_weight", 0.0))
		items.append(item_snapshot)
	var capacity: Dictionary = _inventory_capacity.capacity_snapshot(player, registry.get_library("items"))
	return {
		"owner_actor_id": int(player.get("actor_id", 0)),
		"owner_name": str(player.get("display_name", "")),
		"items": items,
		"inventory_order": inventory_order,
		"inventory_stacks": inventory_stacks.duplicate(true),
		"item_count": items.size(),
		"total_weight": total_weight,
		"max_weight": float(capacity.get("max_weight", 0.0)),
		"remaining_weight": float(capacity.get("remaining_weight", 0.0)),
		"current_item_count": int(capacity.get("current_item_count", items.size())),
		"max_items": int(capacity.get("max_items", -1)),
		"remaining_items": int(capacity.get("remaining_items", -1)),
		"over_item_capacity": bool(capacity.get("over_item_capacity", false)),
		"current_stack_count": int(capacity.get("current_stack_count", 0)),
		"max_stacks": int(capacity.get("max_stacks", -1)),
		"remaining_stacks": int(capacity.get("remaining_stacks", -1)),
		"over_stack_capacity": bool(capacity.get("over_stack_capacity", false)),
		"over_capacity": bool(capacity.get("over_capacity", false)),
		"feedback": _feedback_snapshot(feedback),
	}


func _item_snapshot(player: Dictionary, item_id: String, count: int, tool_durability: Dictionary = {}, inventory: Dictionary = {}, equipment: Dictionary = {}, crafting_context: Dictionary = {}) -> Dictionary:
	var record: Dictionary = registry.get_library("items").get(item_id, {})
	if record.is_empty():
		return {
			"item_id": item_id,
			"name": item_id,
			"description": "",
			"count": count,
			"unit_weight": 0.0,
			"total_weight": 0.0,
			"value": 0,
			"total_value": 0,
			"rarity": "",
			"category": "misc",
			"category_label": _category_label("misc"),
			"icon_path": "",
			"icon_asset": AssetPathResolver.resolve_media_asset("", "item"),
			"thumbnail_asset": _thumbnail_asset(AssetPathResolver.resolve_media_asset("", "item"), "item"),
			"equip_slots": [],
			"usable": false,
			"use_ap_cost": 0.0,
			"use_effect_ids": [],
			"droppable": true,
			"deconstructable": false,
			"deconstruct_yield": [],
			"deconstruct_preview": {},
			"deconstruct_unavailable": {"reason": "unknown_item"},
			"stackable": false,
			"max_stack": 1,
		}

	var data: Dictionary = record.get("data", {})
	var unit_weight: float = float(data.get("weight", 0.0))
	var value: int = int(data.get("value", 0))
	var category: String = _category(data)
	var icon_path := str(data.get("icon_path", ""))
	var icon_asset := AssetPathResolver.resolve_media_asset(icon_path, _icon_fallback_key(category))
	var usable: Dictionary = _fragment_by_kind(data, "usable")
	var use_allowed: bool = not usable.is_empty() and _is_item_use_allowed(data)
	var crafting_fragment: Dictionary = _fragment_by_kind(data, "crafting")
	var deconstruct_yield: Array[Dictionary] = _deconstruct_yield(data)
	var deconstruct_requirements: Dictionary = _deconstruct_requirements(player, crafting_fragment, tool_durability, inventory, equipment, crafting_context)
	var deconstructable := not deconstruct_yield.is_empty()
	return {
		"item_id": item_id,
		"name": str(data.get("name", item_id)),
		"description": str(data.get("description", "")),
		"count": count,
		"unit_weight": unit_weight,
		"total_weight": unit_weight * float(count),
		"value": value,
		"total_value": value * count,
		"rarity": _rarity(data),
		"category": category,
		"category_label": _category_label(category),
		"icon_path": icon_path,
		"icon_asset": icon_asset,
		"thumbnail_asset": _thumbnail_asset(icon_asset, "item"),
		"equip_slots": _equip_slots(data),
		"usable": use_allowed,
		"use_ap_cost": max(1.0, ceil(float(usable.get("use_time", 1.0)))) if not usable.is_empty() else 0.0,
		"use_effect_ids": _string_array(usable.get("effect_ids", [])) if not usable.is_empty() else [],
		"droppable": _is_item_droppable(data),
		"deconstructable": deconstructable,
		"deconstruct_yield": deconstruct_yield,
		"deconstruct_preview": _deconstruct_preview(deconstruct_yield, count),
		"deconstruct_requirements": deconstruct_requirements,
		"deconstruct_unavailable": _deconstruct_unavailable(crafting_fragment, deconstruct_yield, deconstruct_requirements),
		"stackable": _stackable(data),
		"max_stack": _max_stack(data),
	}


func _stack_counts_for(item_id: String, count: int, inventory_stacks: Dictionary) -> Array[int]:
	var stacks: Array[int] = []
	for stack_count in _array_or_empty(inventory_stacks.get(item_id, [])):
		var normalized_count: int = max(0, int(stack_count))
		if normalized_count > 0:
			stacks.append(normalized_count)
	var stack_sum := 0
	for stack_count in stacks:
		stack_sum += stack_count
	if stacks.is_empty() or stack_sum != count:
		stacks = [count]
	return stacks


func _largest_stack_count(stacks: Array) -> int:
	var largest := 0
	for stack_count in stacks:
		largest = max(largest, int(stack_count))
	return largest


func _rarity(item_data: Dictionary) -> String:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if fragment_data.get("kind", "") == "economy":
			return str(fragment_data.get("rarity", ""))
	return ""


func _category(item_data: Dictionary) -> String:
	if _has_fragment(item_data, "weapon") or _has_fragment(item_data, "equip"):
		return "equipment"
	if _has_fragment(item_data, "usable"):
		return "consumable"
	if str(item_data.get("icon_path", "")).contains("/ammo/") or str(item_data.get("name", "")).contains("弹药"):
		return "ammo"
	if _has_fragment(item_data, "crafting"):
		return "material"
	return "misc"


func _category_label(category: String) -> String:
	match category:
		"equipment":
			return "装备"
		"consumable":
			return "消耗"
		"ammo":
			return "弹药"
		"material":
			return "材料"
		_:
			return "杂项"


func _icon_fallback_key(category: String) -> String:
	match category:
		"equipment":
			return "equipment"
		"consumable":
			return "item"
		"ammo":
			return "ammo"
		"material":
			return "material"
		_:
			return "item"


func _thumbnail_asset(icon_asset: Dictionary, domain: String) -> Dictionary:
	var thumbnail := icon_asset.duplicate(true)
	thumbnail["thumbnail"] = true
	thumbnail["thumbnail_domain"] = domain
	thumbnail["source"] = "icon_asset"
	return thumbnail


func _equip_slots(item_data: Dictionary) -> Array[String]:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if fragment_data.get("kind", "") != "equip":
			continue
		var slots: Array[String] = []
		for slot in fragment_data.get("slots", []):
			slots.append(str(slot))
		return slots
	return []


func _stackable(item_data: Dictionary) -> bool:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if fragment_data.get("kind", "") == "stacking":
			return bool(fragment_data.get("stackable", false))
	return false


func _max_stack(item_data: Dictionary) -> int:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if fragment_data.get("kind", "") == "stacking":
			return int(fragment_data.get("max_stack", 1))
	return 1


func _deconstruct_yield(item_data: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for fragment in _array_or_empty(item_data.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) != "crafting":
			continue
		for entry in _array_or_empty(fragment_data.get("deconstruct_yield", [])):
			var entry_data: Dictionary = _dictionary_or_empty(entry)
			var item_id := str(entry_data.get("item_id", ""))
			var count := int(entry_data.get("count", 0))
			if item_id.is_empty() or count <= 0:
				continue
			output.append({
				"item_id": item_id,
				"count": count,
			})
		return output
	return output


func _deconstruct_preview(deconstruct_yield: Array[Dictionary], source_count: int) -> Dictionary:
	if deconstruct_yield.is_empty():
		return {}
	var entries: Array[Dictionary] = []
	var total_weight := 0.0
	var preview_count: int = max(1, source_count)
	for entry in deconstruct_yield:
		var item_id := str(entry.get("item_id", ""))
		var count_per_item: int = int(entry.get("count", 0))
		if item_id.is_empty() or count_per_item <= 0:
			continue
		var total_count: int = count_per_item * preview_count
		var item_data: Dictionary = _item_data(item_id)
		var unit_weight := float(item_data.get("weight", 0.0))
		total_weight += unit_weight * float(total_count)
		entries.append({
			"item_id": item_id,
			"name": str(item_data.get("name", item_id)),
			"count_per_item": count_per_item,
			"total_count": total_count,
			"unit_weight": unit_weight,
			"total_weight": unit_weight * float(total_count),
		})
	return {
		"source_count": preview_count,
		"entries": entries,
		"total_weight": total_weight,
	}


func _deconstruct_unavailable(crafting_fragment: Dictionary, deconstruct_yield: Array[Dictionary], requirements: Dictionary) -> Dictionary:
	if deconstruct_yield.is_empty():
		var reason := "missing_deconstruct_yield" if not crafting_fragment.is_empty() else "no_crafting_fragment"
		return {
			"reason": reason,
			"text": "没有拆解产物",
		}
	var missing_parts: Array[String] = []
	var missing_tools: Array[Dictionary] = []
	for tool in _array_or_empty(requirements.get("required_tools", [])):
		var tool_data: Dictionary = _dictionary_or_empty(tool)
		var tool_name := str(tool_data.get("name", tool_data.get("item_id", "")))
		if bool(tool_data.get("consume_on_deconstruct", false)) and int(tool_data.get("missing_count", 0)) > 0:
			missing_parts.append("缺少可消耗工具 %s x%d" % [tool_name, int(tool_data.get("missing_count", 0))])
			missing_tools.append(tool_data.duplicate(true))
		var durability_cost := float(tool_data.get("durability_cost", 0.0))
		if durability_cost > 0.0 and float(tool_data.get("available_durability", 0.0)) < durability_cost:
			missing_parts.append("工具耐久不足 %s %.1f/%.1f" % [
				tool_name,
				float(tool_data.get("available_durability", 0.0)),
				durability_cost,
			])
			missing_tools.append(tool_data.duplicate(true))
	var station := str(requirements.get("required_station", "none"))
	if station not in ["", "none"] and not bool(requirements.get("station_available", false)):
		missing_parts.append("需要工作台 %s" % station)
	if missing_parts.is_empty():
		return {}
	return {
		"reason": "requirements_unmet",
		"text": "；".join(missing_parts),
		"missing_tools": missing_tools,
		"required_station": station if station not in ["", "none"] else "",
	}


func _deconstruct_requirements(player: Dictionary, crafting_fragment: Dictionary, tool_durability: Dictionary = {}, inventory: Dictionary = {}, equipment: Dictionary = {}, crafting_context: Dictionary = {}) -> Dictionary:
	if crafting_fragment.is_empty():
		return {}
	var required_station := str(crafting_fragment.get("deconstruct_required_station", crafting_fragment.get("required_deconstruct_station", "none")))
	var station: Dictionary = _nearest_station(player, required_station, _array_or_empty(crafting_context.get("crafting_stations", [])))
	return {
		"required_tools": _deconstruct_required_tools(crafting_fragment, tool_durability, inventory, equipment, crafting_context),
		"required_station": required_station,
		"station_available": required_station in ["", "none"] or not station.is_empty(),
		"station": station,
	}


func _deconstruct_required_tools(crafting_fragment: Dictionary, tool_durability: Dictionary = {}, inventory: Dictionary = {}, equipment: Dictionary = {}, crafting_context: Dictionary = {}) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for key in ["deconstruct_required_tools", "required_deconstruct_tools", "deconstruct_required_tool_ids", "required_deconstruct_tool_ids"]:
		if not crafting_fragment.has(key):
			continue
		_append_deconstruct_required_tools(output, crafting_fragment.get(key), crafting_fragment, tool_durability, inventory, equipment, crafting_context)
	return output


func _append_deconstruct_required_tools(output: Array[Dictionary], value: Variant, crafting_fragment: Dictionary, tool_durability: Dictionary = {}, inventory: Dictionary = {}, equipment: Dictionary = {}, crafting_context: Dictionary = {}) -> void:
	if typeof(value) == TYPE_ARRAY:
		for entry in value:
			_append_deconstruct_required_tools(output, entry, crafting_fragment, tool_durability, inventory, equipment, crafting_context)
		return
	var tool: Dictionary = _deconstruct_tool_requirement(value, crafting_fragment, tool_durability, inventory, equipment, crafting_context)
	var tool_id := str(tool.get("item_id", ""))
	if tool_id.is_empty():
		return
	for index in range(output.size()):
		var existing: Dictionary = _dictionary_or_empty(output[index])
		if str(existing.get("item_id", "")) != tool_id:
			continue
		existing["required"] = max(int(existing.get("required", 1)), int(tool.get("required", 1)))
		if bool(tool.get("consume_on_deconstruct", false)):
			existing["consume_on_deconstruct"] = true
			existing["consume_count"] = max(int(existing.get("consume_count", 1)), int(tool.get("consume_count", 1)))
			existing["consumption_sources"] = _merge_tool_consumption_sources(_array_or_empty(existing.get("consumption_sources", [])), _array_or_empty(tool.get("consumption_sources", [])))
			existing["available"] = _consumption_source_total(_array_or_empty(existing.get("consumption_sources", [])))
			existing["missing_count"] = max(0, int(existing.get("consume_count", 1)) - int(existing.get("available", 0)))
		if float(tool.get("durability_cost", 0.0)) > 0.0:
			existing["durability_cost"] = max(float(existing.get("durability_cost", 0.0)), float(tool.get("durability_cost", 0.0)))
			existing["available_durability"] = float(tool.get("available_durability", 0.0))
		output[index] = existing
		return
	output.append(tool)


func _deconstruct_tool_requirement(tool: Variant, crafting_fragment: Dictionary, tool_durability: Dictionary = {}, inventory: Dictionary = {}, equipment: Dictionary = {}, crafting_context: Dictionary = {}) -> Dictionary:
	var data: Dictionary = _dictionary_or_empty(tool)
	var raw_id: Variant = tool
	if not data.is_empty():
		raw_id = data.get("item_id", data.get("itemId", data.get("tool_id", data.get("toolId", data.get("id", "")))))
	var tool_id := _normalize_content_id(raw_id)
	var consume_on_deconstruct: bool = bool(data.get("consume_on_deconstruct", data.get("consume_on_deconstruct_item", data.get("consume_on_craft", data.get("consume", data.get("consumed", false))))))
	if bool(crafting_fragment.get("consume_required_tools_on_deconstruct", crafting_fragment.get("consume_deconstruct_tools", crafting_fragment.get("consume_required_tools", false)))):
		consume_on_deconstruct = true
	var consume_count: int = max(1, int(data.get("consume_count", data.get("consumed_count", data.get("tool_consume_count", data.get("deconstruct_tool_consume_count", crafting_fragment.get("required_tool_consume_count", crafting_fragment.get("deconstruct_tool_consume_count", crafting_fragment.get("tool_consume_count", 1)))))))))
	var durability_cost: float = max(0.0, float(data.get("durability_cost", data.get("tool_durability_cost", data.get("deconstruct_tool_durability_cost", data.get("required_tool_durability_cost", 0.0))))))
	var output := {
		"item_id": tool_id,
		"name": str(_item_data(tool_id).get("name", tool_id)),
		"required": max(1, int(data.get("required", data.get("required_count", data.get("count", 1))))),
		"consume_on_deconstruct": consume_on_deconstruct,
		"consume_count": consume_count if consume_on_deconstruct else 0,
		"durability_cost": durability_cost,
		"available_durability": _tool_durability(tool_id, tool_durability),
	}
	if consume_on_deconstruct:
		var sources: Array[Dictionary] = _tool_consumption_sources(tool_id, consume_count, inventory, equipment, crafting_context)
		output["consumption_sources"] = sources
		output["available"] = _consumption_source_total(sources)
		output["missing_count"] = max(0, consume_count - int(output.get("available", 0)))
	return output


func _tool_consumption_sources(tool_id: String, count: int, inventory: Dictionary, equipment: Dictionary, crafting_context: Dictionary = {}) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var remaining: int = max(0, count)
	if remaining > 0:
		var actor_count: int = max(0, int(inventory.get(tool_id, 0)))
		if actor_count > 0:
			var used_actor_count: int = mini(actor_count, remaining)
			output.append({
				"source": "actor_inventory",
				"label": "背包",
				"count": used_actor_count,
				"available": actor_count,
			})
			remaining -= used_actor_count
	if remaining > 0:
		var slot_ids: Array = equipment.keys()
		slot_ids.sort()
		for slot_id in slot_ids:
			if remaining <= 0:
				break
			if _normalize_content_id(equipment.get(slot_id, "")) != tool_id:
				continue
			output.append({
				"source": "equipment",
				"label": "装备:%s" % str(slot_id),
				"slot_id": str(slot_id),
				"count": 1,
				"available": 1,
			})
			remaining -= 1
	if remaining > 0:
		for container in _array_or_empty(crafting_context.get("nearby_tool_containers", [])):
			if remaining <= 0:
				break
			var container_data: Dictionary = _dictionary_or_empty(container)
			var container_count: int = _inventory_entry_count(_array_or_empty(container_data.get("inventory", [])), tool_id)
			if container_count <= 0:
				continue
			var used_container_count: int = mini(container_count, remaining)
			var container_id := str(container_data.get("container_id", ""))
			var display_name := str(container_data.get("display_name", container_id))
			output.append({
				"source": "nearby_container",
				"label": "附近容器:%s" % display_name,
				"container_id": container_id,
				"display_name": display_name,
				"count": used_container_count,
				"available": container_count,
			})
			remaining -= used_container_count
	return output


func _merge_tool_consumption_sources(left: Array, right: Array) -> Array:
	var output: Array = left.duplicate(true)
	for source in right:
		var source_data: Dictionary = _dictionary_or_empty(source)
		var matched := false
		for index in range(output.size()):
			var existing: Dictionary = _dictionary_or_empty(output[index])
			if str(existing.get("source", "")) != str(source_data.get("source", "")):
				continue
			if str(existing.get("slot_id", "")) != str(source_data.get("slot_id", "")):
				continue
			if str(existing.get("container_id", "")) != str(source_data.get("container_id", "")):
				continue
			existing["count"] = int(existing.get("count", 0)) + int(source_data.get("count", 0))
			existing["available"] = int(existing.get("available", 0)) + int(source_data.get("available", 0))
			output[index] = existing
			matched = true
			break
		if not matched:
			output.append(source_data.duplicate(true))
	return output


func _consumption_source_total(sources: Array) -> int:
	var total := 0
	for source in sources:
		total += max(0, int(_dictionary_or_empty(source).get("count", 0)))
	return total


func _inventory_entry_count(entries: Array, item_id: String) -> int:
	var total := 0
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if _normalize_content_id(entry_data.get("item_id", "")) == item_id:
			total += max(0, int(entry_data.get("count", 0)))
	return total


func _nearest_station(player: Dictionary, station_id: String, stations: Array) -> Dictionary:
	var normalized_station := station_id.strip_edges()
	if normalized_station in ["", "none"]:
		return {}
	var best_station: Dictionary = {}
	var best_distance := 2147483647
	for station in stations:
		var station_data: Dictionary = _dictionary_or_empty(station)
		if str(station_data.get("station_id", "")) != normalized_station:
			continue
		var distance: int = _distance_to_station(player, station_data)
		var station_range: int = max(0, int(station_data.get("range", 1)))
		if distance > station_range:
			continue
		if distance < best_distance:
			best_distance = distance
			best_station = station_data.duplicate(true)
			best_station["distance"] = distance
	return best_station


func _distance_to_station(player: Dictionary, station: Dictionary) -> int:
	var player_grid: Dictionary = _dictionary_or_empty(player.get("grid_position", {}))
	var best_distance := 2147483647
	for cell in _array_or_empty(station.get("cells", [])):
		var cell_data: Dictionary = _dictionary_or_empty(cell)
		if int(cell_data.get("y", 0)) != int(player_grid.get("y", 0)):
			continue
		var dx: int = abs(int(cell_data.get("x", 0)) - int(player_grid.get("x", 0)))
		var dz: int = abs(int(cell_data.get("z", 0)) - int(player_grid.get("z", 0)))
		best_distance = mini(best_distance, dx + dz)
	if best_distance != 2147483647:
		return best_distance
	var anchor: Dictionary = _dictionary_or_empty(station.get("anchor", {}))
	if int(anchor.get("y", 0)) != int(player_grid.get("y", 0)):
		return best_distance
	return abs(int(anchor.get("x", 0)) - int(player_grid.get("x", 0))) + abs(int(anchor.get("z", 0)) - int(player_grid.get("z", 0)))


func _tool_durability(tool_id: String, tool_durability: Dictionary) -> float:
	if tool_id.is_empty():
		return 0.0
	if tool_durability.has(tool_id):
		return max(0.0, float(tool_durability.get(tool_id, 0.0)))
	return 100.0


func _normalized_item_ids(value: Variant) -> Array[String]:
	var output: Array[String] = []
	if typeof(value) == TYPE_ARRAY:
		for entry in value:
			_append_normalized_item_id(output, entry)
	else:
		_append_normalized_item_id(output, value)
	return output


func _append_normalized_item_id(output: Array[String], value: Variant) -> void:
	var raw_value: Variant = value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = _dictionary_or_empty(value)
		raw_value = data.get("item_id", data.get("itemId", data.get("tool_id", data.get("toolId", data.get("id", "")))))
	var normalized_id := str(raw_value).strip_edges()
	if normalized_id.is_empty() or output.has(normalized_id):
		return
	output.append(normalized_id)


func _has_fragment(item_data: Dictionary, kind: String) -> bool:
	return not _fragment_by_kind(item_data, kind).is_empty()


func _item_data(item_id: String) -> Dictionary:
	var record: Dictionary = registry.get_library("items").get(item_id, {})
	return _dictionary_or_empty(record.get("data", record))


func _fragment_by_kind(item_data: Dictionary, kind: String) -> Dictionary:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == kind:
			return fragment_data
	return {}


func _is_item_use_allowed(item_data: Dictionary) -> bool:
	for key in ["usable", "can_use"]:
		if item_data.has(key) and not bool(item_data.get(key)):
			return false
	for fragment in _array_or_empty(item_data.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		var kind: String = str(fragment_data.get("kind", ""))
		if kind in ["quest", "task", "key_item"]:
			return false
		for key in ["usable", "can_use"]:
			if fragment_data.has(key) and not bool(fragment_data.get(key)):
				return false
	return true


func _is_item_droppable(item_data: Dictionary) -> bool:
	for key in ["droppable", "can_drop", "discardable"]:
		if item_data.has(key) and not bool(item_data.get(key)):
			return false
	for fragment in _array_or_empty(item_data.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		var kind: String = str(fragment_data.get("kind", ""))
		if kind in ["quest", "task", "key_item"]:
			return false
		for key in ["droppable", "can_drop", "discardable"]:
			if fragment_data.has(key) and not bool(fragment_data.get(key)):
				return false
	return true


func _player_actor(runtime_snapshot: Dictionary) -> Dictionary:
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if actor_data.get("kind", "") == "player":
			return actor_data
	return {}


func _feedback_snapshot(feedback: Dictionary) -> Dictionary:
	if feedback.is_empty():
		return {}
	var reason := str(feedback.get("reason", ""))
	var text := _feedback_text(feedback)
	if reason.is_empty() and text.is_empty():
		return {}
	return {
		"type": str(feedback.get("type", "success" if bool(feedback.get("success", false)) else "error")),
		"action": str(feedback.get("action", "")),
		"reason": reason,
		"item_id": str(feedback.get("item_id", "")),
		"text": text,
	}


func _feedback_text(feedback: Dictionary) -> String:
	var explicit_text := str(feedback.get("text", ""))
	if not explicit_text.is_empty():
		return explicit_text
	var item_name := _feedback_item_name(feedback)
	var action := str(feedback.get("action", ""))
	var count := maxi(1, int(feedback.get("count", 1)))
	if bool(feedback.get("success", false)):
		match action:
			"use_item":
				return _use_item_success_text(item_name, feedback)
			"drop":
				return "已丢弃 %s x%d。" % [item_name, int(feedback.get("dropped_count", count))]
			"deconstruct":
				return "已拆解 %s x%d。" % [item_name, count]
			"reorder_inventory":
				return "已调整 %s 的背包顺序。" % item_name
			_:
				return "背包操作完成：%s。" % item_name
	match str(feedback.get("reason", "")):
		"ap_insufficient_use_item":
			return "AP 不足，使用 %s 需要 %.0f，当前 %.0f。" % [item_name, float(feedback.get("required_ap", 0.0)), float(feedback.get("available_ap", 0.0))]
		"ap_insufficient_deconstruct":
			return "AP 不足，拆解 %s 需要 %.0f，当前 %.0f。" % [item_name, float(feedback.get("required_ap", 0.0)), float(feedback.get("available_ap", 0.0))]
		"missing_tools":
			return "缺少拆解工具，无法拆解 %s。" % item_name
		"missing_consumable_tools":
			return "缺少可消耗拆解工具，无法拆解 %s。" % item_name
		"tool_durability_insufficient":
			return "拆解工具耐久不足，无法拆解 %s。" % item_name
		"missing_station":
			return "缺少拆解工作台 %s，无法拆解 %s。" % [
				str(feedback.get("required_station", "")),
				item_name,
			]
		"not_enough_items":
			return "背包中没有足够的 %s，需要 %d，当前 %d。" % [item_name, int(feedback.get("required", count)), int(feedback.get("current", 0))]
		"inventory_over_capacity":
			return _inventory_capacity_text("加入 %s x%d" % [item_name, count], feedback)
		"item_not_usable":
			return "%s 不能使用。" % item_name
		"item_use_forbidden":
			return "%s 当前禁止使用。" % item_name
		"unknown_item":
			return "物品数据不可用：%s。" % str(feedback.get("item_id", ""))
		"unknown_effect":
			return "物品效果不可用：%s。" % str(feedback.get("effect_id", ""))
		"inventory_split_requires_stack_model":
			return "当前背包按物品合并计数，%s 暂不能拆分。" % item_name
		"invalid_quantity":
			return "数量无效，请输入大于 0 的数量。"
		"item_not_in_inventory":
			return "背包中没有 %s。" % item_name
		"simulation_missing":
			return "运行时不可用，无法操作背包。"
		_:
			var reason := str(feedback.get("reason", ""))
			return _reason_catalog.disabled_text_for(reason) if not reason.is_empty() else ""


func _use_item_success_text(item_name: String, feedback: Dictionary) -> String:
	var parts: Array[String] = []
	for effect in _array_or_empty(feedback.get("effects", [])):
		var effect_data: Dictionary = _dictionary_or_empty(effect)
		for delta in _array_or_empty(effect_data.get("resource_deltas", [])):
			var delta_data: Dictionary = _dictionary_or_empty(delta)
			var resource := str(delta_data.get("resource", ""))
			var amount := float(delta_data.get("delta", 0.0))
			if resource == "hp" and absf(amount) > 0.01:
				parts.append("HP %+d" % int(round(amount)))
			elif not resource.is_empty() and absf(amount) > 0.01:
				parts.append("%s %+d" % [resource, int(round(amount))])
	var effect_text := "，%s" % " / ".join(parts) if not parts.is_empty() else ""
	return "已使用 %s%s，剩余 %d，AP 剩余 %.0f。" % [
		item_name,
		effect_text,
		int(feedback.get("remaining", 0)),
		float(feedback.get("ap_remaining", 0.0)),
	]


func _inventory_capacity_text(action_text: String, feedback: Dictionary) -> String:
	match str(feedback.get("limit_kind", feedback.get("capacity_kind", "weight"))):
		"items":
			return "背包物品种类已满，%s 后为 %d/%d 类。" % [
				action_text,
				int(feedback.get("projected_item_count", 0)),
				int(feedback.get("max_items", 0)),
			]
		"stacks":
			return "背包槽位已满，%s 后为 %d/%d 格。" % [
				action_text,
				int(feedback.get("projected_stack_count", 0)),
				int(feedback.get("max_stacks", 0)),
			]
	return "背包负重不足，%s 后为 %.1f/%.1f kg，超出 %.1f kg。" % [
		action_text,
		float(feedback.get("projected_weight", 0.0)),
		float(feedback.get("max_weight", 0.0)),
		float(feedback.get("over_by", 0.0)),
	]


func _feedback_item_name(feedback: Dictionary) -> String:
	var item_id := str(feedback.get("item_id", ""))
	if item_id.is_empty():
		return "物品"
	var record: Dictionary = registry.get_library("items").get(item_id, {})
	var data: Dictionary = _dictionary_or_empty(record.get("data", record))
	return str(data.get("name", item_id))


func _inventory_order(value: Variant, inventory: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for item_id in _array_or_empty(value):
		var normalized_id: String = str(item_id)
		if normalized_id.is_empty() or output.has(normalized_id):
			continue
		if int(inventory.get(normalized_id, 0)) > 0:
			output.append(normalized_id)
	var remaining: Array = inventory.keys()
	remaining.sort()
	for item_id in remaining:
		var normalized_id: String = str(item_id)
		if output.has(normalized_id):
			continue
		if int(inventory.get(normalized_id, 0)) > 0:
			output.append(normalized_id)
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _normalize_content_id(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT:
		var float_value: float = value
		if is_equal_approx(float_value, roundf(float_value)):
			return str(int(float_value))
	if typeof(value) == TYPE_INT:
		return str(value)
	return str(value).strip_edges()


func _string_array(values: Variant) -> Array[String]:
	var output: Array[String] = []
	for value in _array_or_empty(values):
		output.append(str(value))
	return output
