extends RefCounted

const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")

var registry: RefCounted


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	var player: Dictionary = _player_actor(runtime_snapshot)
	var inventory: Dictionary = _dictionary_or_empty(player.get("inventory", {}))
	var equipment: Dictionary = _dictionary_or_empty(player.get("equipment", {}))
	var tool_durability: Dictionary = _dictionary_or_empty(player.get("tool_durability", {}))
	var progression: Dictionary = _dictionary_or_empty(player.get("progression", {}))
	var crafted_recipes: Dictionary = _flag_dictionary(runtime_snapshot.get("crafted_recipes", []))
	var completed_quests: Dictionary = _flag_dictionary(runtime_snapshot.get("completed_quests", []))
	var world_flags: Dictionary = _flag_dictionary(runtime_snapshot.get("world_flags", []))
	crafting_context["world_flags"] = world_flags.duplicate(true)
	var station_snapshot: Dictionary = _station_snapshot(player, crafting_context)
	var recipes: Array[Dictionary] = []
	var recipe_ids: Array = registry.get_library("recipes").keys()
	recipe_ids.sort()
	for recipe_id in recipe_ids:
		var recipe_view: Dictionary = _recipe_snapshot(str(recipe_id), player, inventory, equipment, tool_durability, progression, crafted_recipes, completed_quests, world_flags, crafting_context)
		if not recipe_view.is_empty():
			recipes.append(recipe_view)
	return {
		"owner_actor_id": int(player.get("actor_id", 0)),
		"owner_name": str(player.get("display_name", "")),
		"recipes": recipes,
		"craftable_count": _craftable_count(recipes),
		"station_snapshot": station_snapshot,
		"pending_crafting": _dictionary_or_empty(runtime_snapshot.get("pending_crafting", {})).duplicate(true),
		"crafting_queue": _crafting_queue_snapshot(runtime_snapshot.get("crafting_queue", []), recipes),
		"crafting_queue_result": _dictionary_or_empty(crafting_context.get("latest_crafting_queue_result", {})).duplicate(true),
		"pending_crafting_result": _dictionary_or_empty(crafting_context.get("latest_pending_crafting_result", {})).duplicate(true),
	}


func _crafting_queue_snapshot(entries: Variant, recipes: Array[Dictionary]) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for entry in _array_or_empty(entries):
		var data: Dictionary = _dictionary_or_empty(entry)
		var recipe_id := str(data.get("recipe_id", "")).strip_edges()
		if recipe_id.is_empty():
			continue
		var recipe: Dictionary = _recipe_snapshot_by_id(recipes, recipe_id)
		var output_count: int = max(1, int(recipe.get("output_count", 1)))
		output.append({
			"recipe_id": recipe_id,
			"name": str(recipe.get("name", recipe_id)),
			"count": max(1, int(data.get("count", 1))),
			"output_item_id": str(recipe.get("output_item_id", "")),
			"output_name": str(recipe.get("output_name", recipe.get("output_item_id", ""))),
			"output_count": output_count,
		})
	return output


func _recipe_snapshot_by_id(recipes: Array[Dictionary], recipe_id: String) -> Dictionary:
	for recipe in recipes:
		var recipe_data: Dictionary = _dictionary_or_empty(recipe)
		if str(recipe_data.get("recipe_id", "")) == recipe_id:
			return recipe_data
	return {}


func _recipe_snapshot(recipe_id: String, player: Dictionary, inventory: Dictionary, equipment: Dictionary, tool_durability: Dictionary, progression: Dictionary, crafted_recipes: Dictionary, completed_quests: Dictionary, world_flags: Dictionary, crafting_context: Dictionary) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(registry.get_library("recipes").get(recipe_id, {}))
	var recipe: Dictionary = _dictionary_or_empty(record.get("data", record))
	if recipe.is_empty():
		return {}
	var output: Dictionary = _dictionary_or_empty(recipe.get("output", {}))
	var output_item_id: String = _normalize_content_id(output.get("item_id", ""))
	var output_item: Dictionary = _item_data(output_item_id)
	var materials: Array[Dictionary] = []
	for material in _array_or_empty(recipe.get("materials", [])):
		var material_data: Dictionary = _dictionary_or_empty(material)
		var item_id: String = _normalize_content_id(material_data.get("item_id", ""))
		var required_count: int = max(0, int(material_data.get("count", 0)))
		materials.append({
			"item_id": item_id,
			"name": str(_item_data(item_id).get("name", item_id)),
			"required": required_count,
			"available": int(inventory.get(item_id, 0)),
		})
	var required_tools: Array[Dictionary] = _required_tools_snapshot(_array_or_empty(recipe.get("required_tools", [])), recipe, inventory, equipment, tool_durability, crafting_context)
	var required_station := str(recipe.get("required_station", "none"))
	var station_check: Dictionary = _station_check(player, required_station, crafting_context)
	var station_permission_preview: Dictionary = _station_permission_preview(required_station, station_check)
	var unlock_check: Dictionary = _unlock_check(recipe, inventory, progression, crafted_recipes, completed_quests, world_flags)
	var availability: Dictionary = _availability(recipe, inventory, equipment, progression, materials, required_tools, station_check, unlock_check, crafting_context)
	var max_craft_count: int = _max_craft_count(materials, required_tools, bool(availability.get("can_craft", false)))
	var output_count: int = max(1, int(output.get("count", 1)))
	var output_icon_asset := AssetPathResolver.resolve_media_asset(str(output_item.get("icon_path", "")), "item")
	return {
		"recipe_id": recipe_id,
		"name": str(recipe.get("name", recipe_id)),
		"description": str(recipe.get("description", "")),
		"category": str(recipe.get("category", "")),
		"output_item_id": output_item_id,
		"output_name": str(output_item.get("name", output_item_id)),
		"output_icon_asset": output_icon_asset,
		"thumbnail_asset": _thumbnail_asset(output_icon_asset, "recipe"),
		"output_count": output_count,
		"preview_output_count": output_count * max(1, max_craft_count),
		"materials": materials,
		"required_tools": required_tools,
		"required_station": required_station,
		"available_station": _dictionary_or_empty(station_check.get("station", {})).duplicate(true),
		"station_permission_preview": station_permission_preview,
		"skill_requirements": _dictionary_or_empty(recipe.get("skill_requirements", {})).duplicate(true),
		"craft_time": float(recipe.get("craft_time", 0.0)),
		"experience_reward": int(recipe.get("experience_reward", 0)),
		"is_default_unlocked": bool(recipe.get("is_default_unlocked", false)),
		"unlock_conditions": _unlock_condition_snapshot(recipe),
		"can_craft": bool(availability.get("can_craft", false)),
		"max_craft_count": max_craft_count,
		"craft_reason": str(availability.get("reason", "")),
		"missing_unlock_conditions": _array_or_empty(availability.get("missing_unlock_conditions", [])).duplicate(true),
		"missing_materials": _array_or_empty(availability.get("missing_materials", [])).duplicate(true),
		"missing_skills": _array_or_empty(availability.get("missing_skills", [])).duplicate(true),
		"missing_tools": _array_or_empty(availability.get("missing_tools", [])).duplicate(true),
	}


func _availability(recipe: Dictionary, inventory: Dictionary, equipment: Dictionary, progression: Dictionary, materials: Array[Dictionary], required_tools: Array[Dictionary], station_check: Dictionary, unlock_check: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	if not bool(unlock_check.get("success", false)):
		return unlock_check
	var missing_tools: Array[Dictionary] = []
	for tool in required_tools:
		var tool_data: Dictionary = _dictionary_or_empty(tool)
		var tool_id := str(tool_data.get("item_id", ""))
		if tool_id.is_empty():
			continue
		if _has_tool(tool_id, inventory, equipment, crafting_context):
			continue
		missing_tools.append({
			"item_id": tool_id,
			"name": str(tool_data.get("name", tool_id)),
			"available": 0,
			"required": 1,
		})
	if not missing_tools.is_empty():
		return {"can_craft": false, "reason": "missing_tools", "missing_tools": missing_tools}
	var missing_durability_tools: Array[Dictionary] = []
	for tool in required_tools:
		var tool_data: Dictionary = _dictionary_or_empty(tool)
		var durability_cost: float = max(0.0, float(tool_data.get("durability_cost", 0.0)))
		if durability_cost <= 0.0:
			continue
		var available_durability: float = float(tool_data.get("available_durability", 0.0))
		if available_durability >= durability_cost:
			continue
		missing_durability_tools.append({
			"item_id": str(tool_data.get("item_id", "")),
			"name": str(tool_data.get("name", tool_data.get("item_id", ""))),
			"available_durability": available_durability,
			"required_durability": durability_cost,
			"durability_cost": durability_cost,
		})
	if not missing_durability_tools.is_empty():
		return {
			"can_craft": false,
			"reason": "tool_durability_insufficient",
			"missing_tools": missing_durability_tools,
		}
	var missing_consumable_tools: Array[Dictionary] = []
	for tool in required_tools:
		var tool_data: Dictionary = _dictionary_or_empty(tool)
		if not bool(tool_data.get("consume_on_craft", false)):
			continue
		var tool_id := str(tool_data.get("item_id", ""))
		var consume_count: int = max(1, int(tool_data.get("consume_count", 1)))
		var consumable_available: int = int(tool_data.get("consumable_available", tool_data.get("inventory_available", 0)))
		if not tool_id.is_empty() and consumable_available >= consume_count:
			continue
		missing_consumable_tools.append({
			"item_id": tool_id,
			"name": str(tool_data.get("name", tool_id)),
			"available": consumable_available,
			"required": consume_count,
			"consume_on_craft": true,
			"consumption_sources": _array_or_empty(tool_data.get("available_sources", [])),
		})
	if not missing_consumable_tools.is_empty():
		return {
			"can_craft": false,
			"reason": "missing_consumable_tools",
			"missing_tools": missing_consumable_tools,
		}
	if not bool(station_check.get("success", false)):
		return station_check
	var missing_skills: Array[Dictionary] = []
	var learned: Dictionary = _dictionary_or_empty(progression.get("learned_skills", {}))
	for skill_id in _dictionary_or_empty(recipe.get("skill_requirements", {})).keys():
		var required_level: int = max(1, int(recipe.get("skill_requirements", {}).get(skill_id, 0)))
		var current_level: int = int(learned.get(str(skill_id), 0))
		if current_level < required_level:
			missing_skills.append({
				"skill_id": str(skill_id),
				"required_level": required_level,
				"current_level": current_level,
			})
	if not missing_skills.is_empty():
		return {"can_craft": false, "reason": "missing_skills", "missing_skills": missing_skills}
	var missing_materials: Array[Dictionary] = []
	for material in materials:
		var item_id: String = str(material.get("item_id", ""))
		var required: int = int(material.get("required", 0))
		var available: int = int(inventory.get(item_id, 0))
		if available < required:
			missing_materials.append({
				"item_id": item_id,
				"name": str(material.get("name", item_id)),
				"required": required,
				"available": available,
			})
	if not missing_materials.is_empty():
		return {"can_craft": false, "reason": "materials_insufficient", "missing_materials": missing_materials}
	return {"can_craft": true, "reason": "available"}


func _thumbnail_asset(icon_asset: Dictionary, domain: String) -> Dictionary:
	var thumbnail := icon_asset.duplicate(true)
	thumbnail["thumbnail"] = true
	thumbnail["thumbnail_domain"] = domain
	thumbnail["source"] = "output_icon_asset"
	return thumbnail


func _unlock_check(recipe: Dictionary, inventory: Dictionary, progression: Dictionary, crafted_recipes: Dictionary, completed_quests: Dictionary, world_flags: Dictionary) -> Dictionary:
	if bool(recipe.get("is_default_unlocked", false)):
		return {"success": true}
	var missing: Array[Dictionary] = []
	var learned: Dictionary = _dictionary_or_empty(progression.get("learned_skills", {}))
	for condition in _array_or_empty(recipe.get("unlock_conditions", [])):
		var data: Dictionary = _dictionary_or_empty(condition)
		var condition_type := str(data.get("type", ""))
		match condition_type:
			"recipe":
				var recipe_id := str(data.get("id", ""))
				if recipe_id.is_empty() or not crafted_recipes.has(recipe_id):
					missing.append(_unlock_condition_view(data))
			"skill":
				var skill_id := str(data.get("id", ""))
				var required_level: int = max(1, int(data.get("level", data.get("required_level", 1))))
				var current_level: int = int(learned.get(skill_id, 0))
				if skill_id.is_empty() or current_level < required_level:
					var skill_condition := _unlock_condition_view(data)
					skill_condition["required_level"] = required_level
					skill_condition["current_level"] = current_level
					missing.append(skill_condition)
			"quest":
				var quest_id := str(data.get("id", ""))
				if quest_id.is_empty() or not completed_quests.has(quest_id):
					missing.append(_unlock_condition_view(data))
			"item", "book":
				var item_id := _normalize_content_id(data.get("id", data.get("item_id", "")))
				var required_count: int = max(1, int(data.get("count", 1)))
				var current_count: int = int(inventory.get(item_id, 0))
				if item_id.is_empty() or current_count < required_count:
					var item_condition := _unlock_condition_view(data)
					item_condition["id"] = item_id
					item_condition["required"] = required_count
					item_condition["available"] = current_count
					missing.append(item_condition)
			"world_flag", "flag":
				var flag_id := str(data.get("id", "")).strip_edges()
				if flag_id.is_empty() or not world_flags.has(flag_id):
					missing.append(_unlock_condition_view(data))
			_:
				var unsupported := _unlock_condition_view(data)
				unsupported["unsupported"] = true
				missing.append(unsupported)
	if missing.is_empty() and not _array_or_empty(recipe.get("unlock_conditions", [])).is_empty():
		return {"success": true}
	return {
		"success": false,
		"can_craft": false,
		"reason": "recipe_locked",
		"missing_unlock_conditions": missing,
	}


func _unlock_condition_snapshot(recipe: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for condition in _array_or_empty(recipe.get("unlock_conditions", [])):
		output.append(_unlock_condition_view(_dictionary_or_empty(condition)))
	return output


func _unlock_condition_view(condition: Dictionary) -> Dictionary:
	var condition_type := str(condition.get("type", ""))
	var condition_id := str(condition.get("id", ""))
	var display_name := condition_id
	match condition_type:
		"recipe":
			var recipe_record: Dictionary = _dictionary_or_empty(registry.get_library("recipes").get(condition_id, {}))
			var recipe_data: Dictionary = _dictionary_or_empty(recipe_record.get("data", recipe_record))
			display_name = str(recipe_data.get("name", condition_id))
		"skill":
			var skill_record: Dictionary = _dictionary_or_empty(registry.get_library("skills").get(condition_id, {}))
			var skill_data: Dictionary = _dictionary_or_empty(skill_record.get("data", skill_record))
			display_name = str(skill_data.get("name", condition_id))
		"quest":
			var quest_record: Dictionary = _dictionary_or_empty(registry.get_library("quests").get(condition_id, {}))
			var quest_data: Dictionary = _dictionary_or_empty(quest_record.get("data", quest_record))
			display_name = str(quest_data.get("title", condition_id))
		"item", "book":
			var item_id := _normalize_content_id(condition.get("id", condition.get("item_id", "")))
			condition_id = item_id
			var item_data: Dictionary = _item_data(item_id)
			display_name = str(item_data.get("name", item_id))
	var view := {
		"type": condition_type,
		"id": condition_id,
		"display_name": display_name,
	}
	if condition.has("level"):
		view["level"] = max(1, int(condition.get("level", 1)))
	if condition.has("required_level"):
		view["required_level"] = max(1, int(condition.get("required_level", 1)))
	return view


func _station_check(player: Dictionary, required_station: String, crafting_context: Dictionary) -> Dictionary:
	var station_id := required_station.strip_edges()
	if station_id in ["", "none"]:
		return {"success": true}
	var station: Dictionary = _nearest_station(player, station_id, _array_or_empty(crafting_context.get("crafting_stations", [])))
	if station.is_empty():
		return {
			"can_craft": false,
			"success": false,
			"reason": "missing_station",
			"required_station": station_id,
		}
	var permission: Dictionary = _station_permission(player, station, crafting_context)
	if not bool(permission.get("success", false)):
		permission["can_craft"] = false
		permission["required_station"] = station_id
		var station_view := station.duplicate(true)
		station_view["permission"] = permission.duplicate(true)
		permission["station"] = station_view
		return permission
	return {
		"success": true,
		"station": station,
	}


func _station_snapshot(player: Dictionary, crafting_context: Dictionary) -> Dictionary:
	var stations: Array[Dictionary] = []
	for station in _array_or_empty(crafting_context.get("crafting_stations", [])):
		var station_data: Dictionary = _dictionary_or_empty(station)
		var station_id := str(station_data.get("station_id", "")).strip_edges()
		if station_id.is_empty():
			continue
		var distance: int = _distance_to_station(player, station_data)
		var station_range: int = max(0, int(station_data.get("range", 1)))
		var entry := station_data.duplicate(true)
		entry["station_id"] = station_id
		entry["display_name"] = str(entry.get("display_name", station_id))
		entry["distance"] = distance
		entry["range"] = station_range
		entry["in_range"] = distance <= station_range
		var permission: Dictionary = _station_permission(player, entry, crafting_context)
		entry["permission"] = permission.duplicate(true)
		entry["available"] = bool(permission.get("success", false))
		entry["unavailable_reason"] = str(permission.get("reason", ""))
		stations.append(entry)
	stations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var distance_a: int = int(a.get("distance", 2147483647))
		var distance_b: int = int(b.get("distance", 2147483647))
		if distance_a == distance_b:
			return str(a.get("station_id", "")) < str(b.get("station_id", ""))
		return distance_a < distance_b
	)
	var in_range: Array[Dictionary] = []
	var by_id: Dictionary = {}
	for station in stations:
		var station_data: Dictionary = _dictionary_or_empty(station)
		by_id[str(station_data.get("station_id", ""))] = station_data.duplicate(true)
		if bool(station_data.get("in_range", false)):
			in_range.append(station_data.duplicate(true))
	return {
		"stations": stations,
		"in_range": in_range,
		"by_id": by_id,
		"count": stations.size(),
		"in_range_count": in_range.size(),
	}


func _station_permission_preview(required_station: String, station_check: Dictionary) -> Dictionary:
	var station_id := required_station.strip_edges()
	if station_id in ["", "none"]:
		return {
			"active": false,
			"required_station": station_id,
			"state": "none",
			"text": "无需工作台",
		}
	var station: Dictionary = _dictionary_or_empty(station_check.get("station", {}))
	var permission: Dictionary = _dictionary_or_empty(station.get("permission", station_check))
	var reason := str(permission.get("reason", station_check.get("reason", ""))).strip_edges()
	var success := bool(permission.get("success", station_check.get("success", false)))
	var display_name := str(station.get("display_name", station_id))
	var distance := int(station.get("distance", -1))
	var station_range := int(station.get("range", 0))
	var state := "available" if success else ("missing_station" if reason == "missing_station" or station.is_empty() else "blocked")
	var blockers := _station_permission_blockers(permission)
	return {
		"active": true,
		"required_station": station_id,
		"station_id": str(station.get("station_id", station_id)),
		"display_name": display_name,
		"distance": distance,
		"range": station_range,
		"in_range": bool(station.get("in_range", false)),
		"success": success,
		"available": success,
		"state": state,
		"reason": reason,
		"blockers": blockers,
		"text": _station_permission_preview_text(display_name, distance, station_range, success, reason, blockers),
	}


func _station_permission_blockers(permission: Dictionary) -> Array[Dictionary]:
	var blockers: Array[Dictionary] = []
	var reason := str(permission.get("reason", "")).strip_edges()
	match reason:
		"station_world_flag_missing":
			for flag_id in _string_array(permission.get("required_world_flags", [])):
				blockers.append({"kind": "world_flag", "id": flag_id, "state": "missing"})
		"station_world_flag_blocked":
			for flag_id in _string_array(permission.get("blocked_world_flags", [])):
				blockers.append({"kind": "world_flag", "id": flag_id, "state": "blocked"})
		"station_item_missing":
			for item_id in _string_array(permission.get("required_item_ids", [])):
				blockers.append({"kind": "item", "id": item_id, "state": "missing"})
		"station_tool_missing":
			for item_id in _string_array(permission.get("required_tool_ids", [])):
				blockers.append({"kind": "tool", "id": item_id, "state": "missing"})
	if blockers.is_empty():
		var fallback := str(permission.get("flag_id", permission.get("item_id", ""))).strip_edges()
		if not fallback.is_empty():
			blockers.append({"kind": "unknown", "id": fallback, "state": "missing"})
	return blockers


func _station_permission_preview_text(display_name: String, distance: int, station_range: int, success: bool, reason: String, blockers: Array[Dictionary]) -> String:
	var distance_text := "距离 %d/%d" % [distance, station_range] if distance >= 0 else "距离未知"
	if success:
		return "工作台权限: %s 可用 | %s" % [display_name, distance_text]
	var blocker_ids: Array[String] = []
	for blocker in blockers:
		var blocker_data: Dictionary = _dictionary_or_empty(blocker)
		var blocker_id := str(blocker_data.get("id", "")).strip_edges()
		if not blocker_id.is_empty():
			blocker_ids.append(blocker_id)
	var detail := ", ".join(blocker_ids)
	match reason:
		"missing_station":
			return "工作台权限: 缺少 %s" % display_name
		"station_world_flag_missing":
			return "工作台权限: %s 未启用 %s | %s" % [display_name, detail, distance_text]
		"station_world_flag_blocked":
			return "工作台权限: %s 被封锁 %s | %s" % [display_name, detail, distance_text]
		"station_item_missing":
			return "工作台权限: %s 缺钥匙 %s | %s" % [display_name, detail, distance_text]
		"station_tool_missing":
			return "工作台权限: %s 缺工具 %s | %s" % [display_name, detail, distance_text]
	return "工作台权限: %s %s | %s" % [display_name, reason, distance_text]


func _station_permission(player: Dictionary, station: Dictionary, crafting_context: Dictionary) -> Dictionary:
	var world_flags: Dictionary = _dictionary_or_empty(crafting_context.get("world_flags", {}))
	for flag_id in _string_array(station.get("required_world_flags", [])):
		if not world_flags.has(flag_id):
			return {
				"success": false,
				"reason": "station_world_flag_missing",
				"flag_id": flag_id,
				"required_world_flags": _string_array(station.get("required_world_flags", [])),
			}
	for flag_id in _string_array(station.get("blocked_world_flags", [])):
		if world_flags.has(flag_id):
			return {
				"success": false,
				"reason": "station_world_flag_blocked",
				"flag_id": flag_id,
				"blocked_world_flags": _string_array(station.get("blocked_world_flags", [])),
			}
	var missing_items: Array[String] = _missing_inventory_items(_dictionary_or_empty(player.get("inventory", {})), _required_item_ids(station))
	if not missing_items.is_empty():
		return {
			"success": false,
			"reason": "station_item_missing",
			"item_id": missing_items[0],
			"required_item_ids": _required_item_ids(station),
		}
	var missing_tools: Array[String] = _missing_tools(player, _required_tool_ids(station), crafting_context)
	if not missing_tools.is_empty():
		return {
			"success": false,
			"reason": "station_tool_missing",
			"item_id": missing_tools[0],
			"required_tool_ids": _required_tool_ids(station),
		}
	return {"success": true}


func _required_item_ids(value: Dictionary) -> Array[String]:
	var output: Array[String] = []
	_append_unique_normalized_item_id(output, value.get("required_item_ids", []))
	_append_unique_normalized_item_id(output, value.get("required_items", []))
	return output


func _required_tool_ids(value: Dictionary) -> Array[String]:
	var output: Array[String] = []
	_append_unique_normalized_item_id(output, value.get("required_tool_ids", []))
	_append_unique_normalized_item_id(output, value.get("required_tools", []))
	return output


func _missing_inventory_items(inventory: Dictionary, item_ids: Array[String]) -> Array[String]:
	var missing: Array[String] = []
	for item_id in item_ids:
		if int(inventory.get(item_id, 0)) > 0:
			continue
		missing.append(item_id)
	return missing


func _missing_tools(player: Dictionary, tool_ids: Array[String], crafting_context: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	var inventory: Dictionary = _dictionary_or_empty(player.get("inventory", {}))
	var equipment: Dictionary = _dictionary_or_empty(player.get("equipment", {}))
	for tool_id in tool_ids:
		if _tool_available_count(tool_id, inventory, equipment, crafting_context) > 0:
			continue
		missing.append(tool_id)
	return missing


func _nearest_station(player: Dictionary, station_id: String, stations: Array) -> Dictionary:
	var best_station: Dictionary = {}
	var best_distance := 2147483647
	for station in stations:
		var station_data: Dictionary = _dictionary_or_empty(station)
		if str(station_data.get("station_id", "")) != station_id:
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


func _required_tools_snapshot(required_tools: Array, recipe: Dictionary, inventory: Dictionary, equipment: Dictionary, tool_durability: Dictionary, crafting_context: Dictionary = {}) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var recipe_consumes_tools: bool = _recipe_consumes_required_tools(recipe)
	var recipe_consume_count: int = _recipe_required_tool_consume_count(recipe)
	for tool in required_tools:
		var tool_data: Dictionary = _tool_requirement(tool)
		var tool_id: String = str(tool_data.get("item_id", ""))
		if tool_id.is_empty():
			continue
		var available_count: int = _tool_available_count(tool_id, inventory, equipment, crafting_context)
		if recipe_consumes_tools:
			tool_data["consume_on_craft"] = true
			if not tool_data.has("consume_count"):
				tool_data["consume_count"] = recipe_consume_count
		var consume_on_craft: bool = bool(tool_data.get("consume_on_craft", false))
		var consume_count: int = max(1, int(tool_data.get("consume_count", tool_data.get("required", 1))))
		var consumption_sources: Array[Dictionary] = []
		if consume_on_craft:
			consumption_sources = _tool_consumption_sources(tool_id, consume_count, inventory, equipment, crafting_context)
		var consumable_available: int = _consumption_source_total(consumption_sources)
		var available_sources: Array[Dictionary] = _tool_availability_sources(tool_id, inventory, equipment, crafting_context)
		output.append({
			"item_id": tool_id,
			"name": str(_item_data(tool_id).get("name", tool_id)),
			"available": available_count,
			"inventory_available": int(inventory.get(tool_id, 0)),
			"equipment_available": _equipment_tool_count(tool_id, equipment),
			"nearby_container_available": _nearby_container_tool_count(tool_id, crafting_context),
			"available_sources": available_sources,
			"required": max(1, int(tool_data.get("required", 1))),
			"consume_on_craft": consume_on_craft,
			"consume_count": consume_count if consume_on_craft else 0,
			"can_consume": not consume_on_craft or consumable_available >= consume_count,
			"consumable_available": _consumption_source_total(available_sources) if consume_on_craft else 0,
			"consumption_sources": consumption_sources,
			"durability_cost": float(tool_data.get("durability_cost", 0.0)),
			"available_durability": _tool_durability(tool_id, tool_durability),
		})
	return output


func _tool_requirement(tool: Variant) -> Dictionary:
	var data: Dictionary = _dictionary_or_empty(tool)
	var raw_id: Variant = tool
	if not data.is_empty():
		raw_id = data.get("item_id", data.get("itemId", data.get("tool_id", data.get("toolId", data.get("id", "")))))
	var required_count: int = max(1, int(data.get("required", data.get("required_count", data.get("count", 1)))))
	var consume_on_craft: bool = bool(data.get("consume_on_craft", data.get("consume", data.get("consumed", false))))
	var consume_count: int = max(1, int(data.get("consume_count", data.get("consumed_count", data.get("tool_consume_count", required_count)))))
	var output := {
		"item_id": _normalize_content_id(raw_id),
		"required": required_count,
		"consume_on_craft": consume_on_craft,
		"consume_count": consume_count,
	}
	var durability_cost: float = float(data.get("durability_cost", data.get("tool_durability_cost", data.get("required_tool_durability_cost", 0.0))))
	if durability_cost > 0.0:
		output["durability_cost"] = durability_cost
	return output


func _recipe_consumes_required_tools(recipe: Dictionary) -> bool:
	return bool(recipe.get("consume_required_tools_on_craft", recipe.get("consume_required_tools", recipe.get("consume_tools_on_craft", false))))


func _recipe_required_tool_consume_count(recipe: Dictionary) -> int:
	return max(1, int(recipe.get("required_tool_consume_count", recipe.get("craft_tool_consume_count", recipe.get("tool_consume_count", 1)))))


func _has_tool(tool_id: String, inventory: Dictionary, equipment: Dictionary, crafting_context: Dictionary = {}) -> bool:
	return _tool_available_count(tool_id, inventory, equipment, crafting_context) > 0


func _tool_available_count(tool_id: String, inventory: Dictionary, equipment: Dictionary, crafting_context: Dictionary = {}) -> int:
	var count := 0
	if int(inventory.get(tool_id, 0)) > 0:
		count += int(inventory.get(tool_id, 0))
	for slot_id in equipment.keys():
		if _normalize_content_id(equipment.get(slot_id, "")) == tool_id:
			count += 1
	for container in _array_or_empty(crafting_context.get("nearby_tool_containers", [])):
		var container_data: Dictionary = _dictionary_or_empty(container)
		count += _inventory_entry_count(_array_or_empty(container_data.get("inventory", [])), tool_id)
	return count


func _tool_availability_sources(tool_id: String, inventory: Dictionary, equipment: Dictionary, crafting_context: Dictionary = {}) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if tool_id.is_empty():
		return output
	var inventory_count: int = max(0, int(inventory.get(tool_id, 0)))
	if inventory_count > 0:
		output.append({
			"source": "actor_inventory",
			"count": inventory_count,
			"inventory_before": inventory_count,
		})
	var slot_ids: Array = equipment.keys()
	slot_ids.sort()
	for slot_id in slot_ids:
		if _normalize_content_id(equipment.get(slot_id, "")) != tool_id:
			continue
		output.append({
			"source": "equipment",
			"slot_id": str(slot_id),
			"count": 1,
		})
	for container in _array_or_empty(crafting_context.get("nearby_tool_containers", [])):
		var container_data: Dictionary = _dictionary_or_empty(container)
		var inventory_entries: Array = _array_or_empty(container_data.get("inventory", []))
		var container_count: int = _inventory_entry_count(inventory_entries, tool_id)
		if container_count <= 0:
			continue
		output.append({
			"source": "nearby_container",
			"container_id": str(container_data.get("container_id", "")),
			"display_name": str(container_data.get("display_name", container_data.get("container_id", ""))),
			"count": container_count,
			"inventory_before": container_count,
		})
	return output


func _tool_consumption_sources(tool_id: String, count: int, inventory: Dictionary, equipment: Dictionary, crafting_context: Dictionary = {}) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var remaining: int = max(0, count)
	if remaining <= 0 or tool_id.is_empty():
		return output
	var inventory_count: int = max(0, int(inventory.get(tool_id, 0)))
	if inventory_count > 0:
		var consumed_inventory_count: int = mini(inventory_count, remaining)
		output.append({
			"source": "actor_inventory",
			"count": consumed_inventory_count,
			"inventory_before": inventory_count,
		})
		remaining -= consumed_inventory_count
	var slot_ids: Array = equipment.keys()
	slot_ids.sort()
	for slot_id in slot_ids:
		if remaining <= 0:
			break
		if _normalize_content_id(equipment.get(slot_id, "")) != tool_id:
			continue
		output.append({
			"source": "equipment",
			"slot_id": str(slot_id),
			"count": 1,
		})
		remaining -= 1
	for container in _array_or_empty(crafting_context.get("nearby_tool_containers", [])):
		if remaining <= 0:
			break
		var container_data: Dictionary = _dictionary_or_empty(container)
		var inventory_entries: Array = _array_or_empty(container_data.get("inventory", []))
		var container_count: int = _inventory_entry_count(inventory_entries, tool_id)
		if container_count <= 0:
			continue
		var consumed_container_count: int = mini(container_count, remaining)
		output.append({
			"source": "nearby_container",
			"container_id": str(container_data.get("container_id", "")),
			"display_name": str(container_data.get("display_name", container_data.get("container_id", ""))),
			"count": consumed_container_count,
			"inventory_before": container_count,
		})
		remaining -= consumed_container_count
	return output


func _consumption_source_total(sources: Array[Dictionary]) -> int:
	var total := 0
	for source in sources:
		total += max(0, int(_dictionary_or_empty(source).get("count", 0)))
	return total


func _equipment_tool_count(tool_id: String, equipment: Dictionary) -> int:
	var count := 0
	for slot_id in equipment.keys():
		if _normalize_content_id(equipment.get(slot_id, "")) == tool_id:
			count += 1
	return count


func _nearby_container_tool_count(tool_id: String, crafting_context: Dictionary = {}) -> int:
	var count := 0
	for container in _array_or_empty(crafting_context.get("nearby_tool_containers", [])):
		var container_data: Dictionary = _dictionary_or_empty(container)
		count += _inventory_entry_count(_array_or_empty(container_data.get("inventory", [])), tool_id)
	return count


func _tool_durability(tool_id: String, tool_durability: Dictionary) -> float:
	if tool_id.is_empty():
		return 0.0
	if tool_durability.has(tool_id):
		return max(0.0, float(tool_durability.get(tool_id, 0.0)))
	return 100.0


func _inventory_entry_count(entries: Array, item_id: String) -> int:
	var count := 0
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if _normalize_content_id(entry_data.get("item_id", "")) == item_id:
			count += int(entry_data.get("count", 0))
	return count


func _craftable_count(recipes: Array[Dictionary]) -> int:
	var count := 0
	for recipe in recipes:
		if bool(recipe.get("can_craft", false)):
			count += 1
	return count


func _max_craft_count(materials: Array[Dictionary], required_tools: Array[Dictionary], can_craft: bool) -> int:
	if not can_craft:
		return 0
	if materials.is_empty():
		var tool_only_count := _max_consumable_tool_count(required_tools)
		return 1 if tool_only_count == 2147483647 else max(0, tool_only_count)
	var max_count := 2147483647
	for material in materials:
		var required := int(material.get("required", 0))
		if required <= 0:
			continue
		max_count = mini(max_count, int(material.get("available", 0)) / required)
	var max_tool_count := _max_consumable_tool_count(required_tools)
	if max_tool_count != 2147483647:
		max_count = mini(max_count, max_tool_count)
	if max_count == 2147483647:
		return 1
	return max(0, max_count)


func _max_consumable_tool_count(required_tools: Array[Dictionary]) -> int:
	var max_count := 2147483647
	for tool in required_tools:
		var tool_data: Dictionary = _dictionary_or_empty(tool)
		if not bool(tool_data.get("consume_on_craft", false)):
			continue
		var consume_count: int = max(1, int(tool_data.get("consume_count", 1)))
		max_count = mini(max_count, int(tool_data.get("consumable_available", tool_data.get("inventory_available", 0))) / consume_count)
	return max_count


func _item_data(item_id: String) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(registry.get_library("items").get(item_id, {}))
	return _dictionary_or_empty(record.get("data", record))


func _player_actor(runtime_snapshot: Dictionary) -> Dictionary:
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if actor_data.get("kind", "") == "player":
			return actor_data
	return {}


func _normalize_content_id(value: Variant) -> String:
	if value == null:
		return ""
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))):
		return str(int(value))
	if typeof(value) == TYPE_INT:
		return str(value)
	var text := str(value).strip_edges()
	return "" if text == "<null>" else text


func _append_unique_normalized_item_id(output: Array[String], value: Variant) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		_append_one_normalized_item_id(output, value)
		return
	if typeof(value) == TYPE_ARRAY:
		for entry in value:
			_append_one_normalized_item_id(output, entry)
		return
	_append_one_normalized_item_id(output, value)


func _append_one_normalized_item_id(output: Array[String], value: Variant) -> void:
	var raw_value: Variant = value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = _dictionary_or_empty(value)
		raw_value = data.get("item_id", data.get("itemId", data.get("tool_id", data.get("toolId", data.get("id", "")))))
	var normalized_entry: String = _normalize_content_id(raw_value)
	if normalized_entry.is_empty() or output.has(normalized_entry):
		return
	output.append(normalized_entry)


func _string_array(value: Variant) -> Array[String]:
	var output: Array[String] = []
	if typeof(value) == TYPE_STRING:
		var normalized_value := str(value).strip_edges()
		if not normalized_value.is_empty():
			output.append(normalized_value)
		return output
	for entry in _array_or_empty(value):
		var normalized_entry := str(entry).strip_edges()
		if not normalized_entry.is_empty():
			output.append(normalized_entry)
	return output


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _flag_dictionary(values: Variant) -> Dictionary:
	var output: Dictionary = {}
	for value in _array_or_empty(values):
		output[str(value)] = true
	return output
