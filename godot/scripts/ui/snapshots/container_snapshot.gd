extends RefCounted

const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")
const ReasonCatalog = preload("res://scripts/ui/snapshots/reason_catalog.gd")

var registry: RefCounted
var _reason_catalog := ReasonCatalog.new()


func _init(p_registry: RefCounted) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary, feedback: Dictionary = {}) -> Dictionary:
	var player: Dictionary = _player_actor(runtime_snapshot)
	var container_id: String = str(player.get("active_container_id", ""))
	if container_id.is_empty():
		return {"active": false}
	var session: Dictionary = _container_session(runtime_snapshot, container_id)
	if session.is_empty():
		return {
			"active": true,
			"container_id": container_id,
			"error": "unknown_container",
		}

	var snapshot := {
		"active": true,
		"container_id": container_id,
		"display_name": str(session.get("display_name", container_id)),
		"container_type": str(session.get("container_type", "")),
		"container_origin": str(session.get("container_origin", "")),
		"map_id": str(session.get("map_id", "")),
		"source_actor_id": int(session.get("source_actor_id", 0)),
		"source_actor_definition_id": str(session.get("source_actor_definition_id", "")),
		"source_actor_kind": str(session.get("source_actor_kind", "")),
		"defeated_by_actor_id": int(session.get("defeated_by_actor_id", 0)),
		"owned": bool(session.get("owned", false)),
		"owner_actor_id": int(session.get("owner_actor_id", 0)),
		"owner_actor_definition_id": str(session.get("owner_actor_definition_id", "")),
		"drop_item_id": str(session.get("drop_item_id", "")),
		"money": max(0, int(session.get("money", 0))),
		"items": _container_item_snapshots(session),
		"player_items": _inventory_item_snapshots(_dictionary_or_empty(player.get("inventory", {}))),
		"permission_preview": _permission_preview(session),
	}
	var scoped_feedback := _feedback_snapshot(feedback, container_id)
	if not scoped_feedback.is_empty():
		snapshot["feedback"] = scoped_feedback
	return snapshot


func _container_item_snapshots(session: Dictionary) -> Array[Dictionary]:
	var items: Array[Dictionary] = _item_snapshots(session.get("inventory", []))
	var money: int = max(0, int(session.get("money", 0)))
	if money > 0:
		var money_icon_asset := AssetPathResolver.resolve_media_asset("", "money")
		items.append({
			"item_id": "money",
			"kind": "money",
			"name": "金钱",
			"description": "可从容器中拿取的货币。",
			"count": money,
			"unit_weight": 0.0,
			"total_weight": 0.0,
			"rarity": "",
			"icon_asset": money_icon_asset,
			"thumbnail_asset": _thumbnail_asset(money_icon_asset, "item"),
		})
	return items


func _item_snapshots(entries: Array) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		var item_id: String = _normalize_content_id(entry_data.get("item_id", ""))
		var count: int = int(entry_data.get("count", 0))
		if item_id.is_empty() or count <= 0:
			continue
		var item_data: Dictionary = _item_data(item_id)
		var icon_path := str(item_data.get("icon_path", ""))
		var icon_asset := AssetPathResolver.resolve_media_asset(icon_path, "item")
		items.append({
			"item_id": item_id,
			"name": str(item_data.get("name", item_id)),
			"description": str(item_data.get("description", "")),
			"count": count,
			"unit_weight": float(item_data.get("weight", 0.0)),
			"total_weight": float(item_data.get("weight", 0.0)) * float(count),
			"rarity": _rarity(item_data),
			"icon_asset": icon_asset,
			"thumbnail_asset": _thumbnail_asset(icon_asset, "item"),
		})

	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", a.get("item_id", ""))) < str(b.get("name", b.get("item_id", "")))
	)
	return items


func _inventory_item_snapshots(inventory: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for item_id in inventory.keys():
		var count := int(inventory[item_id])
		if count <= 0:
			continue
		var normalized_item_id := _normalize_content_id(item_id)
		if normalized_item_id.is_empty():
			continue
		var item_data: Dictionary = _item_data(normalized_item_id)
		var icon_path := str(item_data.get("icon_path", ""))
		var icon_asset := AssetPathResolver.resolve_media_asset(icon_path, "item")
		entries.append({
			"item_id": normalized_item_id,
			"name": str(item_data.get("name", normalized_item_id)),
			"description": str(item_data.get("description", "")),
			"count": count,
			"unit_weight": float(item_data.get("weight", 0.0)),
			"total_weight": float(item_data.get("weight", 0.0)) * float(count),
			"rarity": _rarity(item_data),
			"icon_asset": icon_asset,
			"thumbnail_asset": _thumbnail_asset(icon_asset, "item"),
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", a.get("item_id", ""))) < str(b.get("name", b.get("item_id", "")))
	)
	return entries


func _player_actor(runtime_snapshot: Dictionary) -> Dictionary:
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if actor_data.get("kind", "") == "player":
			return actor_data
	return {}


func _thumbnail_asset(icon_asset: Dictionary, domain: String) -> Dictionary:
	var thumbnail := icon_asset.duplicate(true)
	thumbnail["thumbnail"] = true
	thumbnail["thumbnail_domain"] = domain
	thumbnail["source"] = "icon_asset"
	return thumbnail


func _container_session(runtime_snapshot: Dictionary, container_id: String) -> Dictionary:
	for session in runtime_snapshot.get("container_sessions", []):
		var session_data: Dictionary = _dictionary_or_empty(session)
		if str(session_data.get("container_id", "")) == container_id:
			return session_data
	return {}


func _item_data(item_id: String) -> Dictionary:
	var record: Dictionary = registry.get_library("items").get(item_id, {})
	return _dictionary_or_empty(record.get("data", {}))


func _rarity(item_data: Dictionary) -> String:
	for fragment in item_data.get("fragments", []):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if fragment_data.get("kind", "") == "economy":
			return str(fragment_data.get("rarity", ""))
	return ""


func _feedback_snapshot(feedback: Dictionary, container_id: String) -> Dictionary:
	if feedback.is_empty():
		return {}
	if not str(feedback.get("container_id", container_id)).is_empty() and str(feedback.get("container_id", container_id)) != container_id:
		return {}
	var reason := str(feedback.get("reason", ""))
	var text := _feedback_text(feedback)
	if reason.is_empty() and text.is_empty():
		return {}
	return {
		"type": str(feedback.get("type", "error")),
		"reason": reason,
		"text": text,
	}


func _feedback_text(feedback: Dictionary) -> String:
	var explicit_text := str(feedback.get("text", ""))
	if not explicit_text.is_empty():
		return explicit_text
	var item_name := _feedback_item_name(feedback)
	var required := int(feedback.get("required", feedback.get("count", 1)))
	var current := int(feedback.get("current", 0))
	if bool(feedback.get("partial_success", false)):
		return _bulk_partial_text(feedback)
	match str(feedback.get("reason", "")):
		"container_inventory_insufficient":
			return "容器中没有足够的%s，需要 %d，当前 %d。" % [item_name, required, current]
		"container_money_insufficient":
			return "容器中没有足够的金钱，需要 %d，当前 %d。" % [required, current]
		"not_enough_items":
			return "背包中没有足够的%s，需要 %d，当前 %d。" % [item_name, required, current]
		"inventory_over_capacity":
			return "背包负重不足，拿取%s后为 %.1f/%.1f kg，超出 %.1f kg。" % [
				item_name,
				float(feedback.get("projected_weight", 0.0)),
				float(feedback.get("max_weight", 0.0)),
				float(feedback.get("over_by", 0.0)),
			]
		"container_over_capacity":
			return _container_capacity_text(item_name, feedback)
		"unknown_container":
			return "容器不存在或已经失效。"
		"unknown_item":
			return "物品数据不可用: %s。" % str(feedback.get("item_id", ""))
		"unknown_actor":
			return "当前角色不可用，无法操作容器。"
		"active_container_missing":
			return "没有打开的容器。"
		"container_empty":
			return "容器中没有可拿取的物品。"
		"inventory_empty":
			return "背包中没有可存放的物品。"
		"invalid_quantity":
			return "数量无效，请输入大于 0 的数量。"
		"container_locked":
			return "容器已锁定，无法操作。"
		"container_take_forbidden":
			return "没有权限从该容器拿取物品。"
		"container_store_forbidden":
			return "没有权限向该容器存放物品。"
		"container_world_flag_missing":
			return "缺少容器操作许可，当前无法操作。"
		"container_world_flag_blocked":
			return "容器操作许可已失效，当前无法操作。"
		"container_active_quest_missing":
			return "需要正在进行的任务才能操作该容器。"
		"container_completed_quest_missing":
			return "需要先完成指定任务才能操作该容器。"
		"container_active_quest_blocked":
			return "当前任务状态会阻止操作该容器。"
		"container_completed_quest_blocked":
			return "已完成的任务状态会阻止操作该容器。"
		"container_owner_forbidden":
			return "该容器属于其他角色，当前不能拿取。"
		"container_owner_relationship_too_low":
			return "与容器拥有者关系不足，需要 %.0f，当前 %.0f。" % [
				float(feedback.get("owner_relationship_min", 0.0)),
				float(feedback.get("relationship_score", 0.0)),
			]
		"container_owner_relationship_too_high":
			return "与容器拥有者关系状态不符合要求，需要不高于 %.0f，当前 %.0f。" % [
				float(feedback.get("owner_relationship_max", 0.0)),
				float(feedback.get("relationship_score", 0.0)),
			]
		"container_key_missing":
			return "缺少打开该容器所需的%s。" % item_name
		"container_tool_missing":
			return "缺少操作该容器所需的%s。" % item_name
		_:
			var fallback_reason := str(feedback.get("reason", ""))
			return _reason_catalog.disabled_text_for(fallback_reason) if not fallback_reason.is_empty() else ""


func _container_capacity_text(item_name: String, feedback: Dictionary) -> String:
	match str(feedback.get("limit_kind", "")):
		"weight":
			return "容器容量不足，存放%s后为 %.1f/%.1f kg，超出 %.1f kg。" % [
				item_name,
				float(feedback.get("projected_weight", 0.0)),
				float(feedback.get("max_weight", 0.0)),
				float(feedback.get("over_by", 0.0)),
			]
		"items":
			return "容器容量不足，存放%s后为 %d/%d 件。" % [
				item_name,
				int(feedback.get("projected_item_count", 0)),
				int(feedback.get("max_items", 0)),
			]
		"stacks":
			return "容器容量不足，存放%s后为 %d/%d 类。" % [
				item_name,
				int(feedback.get("projected_stack_count", 0)),
				int(feedback.get("max_stacks", 0)),
			]
	return "容器容量不足，无法存放%s。" % item_name


func _permission_preview(session: Dictionary) -> Dictionary:
	var lines: Array[String] = []
	if bool(session.get("locked", false)):
		lines.append("锁定")
	elif bool(session.get("unlock_requirements_consumed", false)):
		lines.append("已解锁")
	var required_items: Array[String] = _normalized_item_ids(session.get("required_item_ids", session.get("required_items", [])))
	if not required_items.is_empty():
		lines.append("钥匙: %s" % _item_names(required_items))
	var required_tools: Array[String] = _normalized_item_ids(session.get("required_tool_ids", session.get("required_tools", [])))
	if not required_tools.is_empty():
		lines.append("工具: %s" % _item_names(required_tools))
	if bool(session.get("consume_required_items_on_unlock", session.get("consume_required_items", session.get("consume_keys_on_unlock", false)))):
		lines.append("解锁消耗钥匙")
	if bool(session.get("consume_required_tools_on_unlock", session.get("consume_required_tools", session.get("consume_tools_on_unlock", false)))):
		lines.append("解锁消耗工具")
	if not bool(session.get("allow_take", true)):
		lines.append("禁止拿取")
	if not bool(session.get("allow_store", true)):
		lines.append("禁止存放")
	if bool(session.get("owned", false)) or int(session.get("owner_actor_id", 0)) > 0 or not str(session.get("owner_actor_definition_id", "")).is_empty():
		lines.append("归属: %s" % _owner_label(session))
	if session.has("owner_relationship_min") or session.has("required_owner_relationship_min"):
		lines.append("关系 >= %.0f" % float(session.get("owner_relationship_min", session.get("required_owner_relationship_min", 0.0))))
	if session.has("owner_relationship_max") or session.has("required_owner_relationship_max"):
		lines.append("关系 <= %.0f" % float(session.get("owner_relationship_max", session.get("required_owner_relationship_max", 0.0))))
	if bool(session.get("allow_steal", session.get("allow_theft", false))):
		var steal_text := "允许偷取"
		if session.has("steal_relationship_delta") or session.has("theft_relationship_delta"):
			steal_text += "，关系 %.0f" % float(session.get("steal_relationship_delta", session.get("theft_relationship_delta", 0.0)))
		lines.append(steal_text)
	_add_counted_requirement_line(lines, "世界条件", _array_or_empty(session.get("required_world_flags", [])).size())
	_add_counted_requirement_line(lines, "任务条件", _quest_condition_count(session))
	_add_capacity_line(lines, session)
	var text := "权限：无特殊限制" if lines.is_empty() else "权限：" + " | ".join(lines)
	return {
		"text": text,
		"lines": lines,
	}


func _item_names(item_ids: Array[String]) -> String:
	var names: Array[String] = []
	for item_id in item_ids:
		var item_data := _item_data(item_id)
		names.append(str(item_data.get("name", item_id)))
	return "、".join(names)


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
	var item_id := _normalize_content_id(raw_value)
	if not item_id.is_empty() and not output.has(item_id):
		output.append(item_id)


func _owner_label(session: Dictionary) -> String:
	var definition_id := str(session.get("owner_actor_definition_id", "")).strip_edges()
	var actor_id := int(session.get("owner_actor_id", 0))
	if not definition_id.is_empty() and actor_id > 0:
		return "%s #%d" % [definition_id, actor_id]
	if not definition_id.is_empty():
		return definition_id
	if actor_id > 0:
		return "#%d" % actor_id
	return "其他角色"


func _add_counted_requirement_line(lines: Array[String], label: String, count: int) -> void:
	if count > 0:
		lines.append("%s x%d" % [label, count])


func _quest_condition_count(session: Dictionary) -> int:
	var count := 0
	for key in [
		"required_active_quest_ids",
		"required_active_quests",
		"required_completed_quest_ids",
		"required_completed_quests",
		"blocked_active_quest_ids",
		"blocked_active_quests",
		"blocked_completed_quest_ids",
		"blocked_completed_quests",
	]:
		count += _array_or_empty(session.get(key, [])).size()
	return count


func _add_capacity_line(lines: Array[String], session: Dictionary) -> void:
	var parts: Array[String] = []
	for key in ["max_weight", "max_container_weight", "weight_capacity"]:
		if session.has(key):
			parts.append("%.1fkg" % float(session.get(key, 0.0)))
			break
	for key in ["max_items", "max_item_count", "item_capacity"]:
		if session.has(key):
			parts.append("%d件" % int(session.get(key, 0)))
			break
	for key in ["max_stacks", "max_stack_count", "slot_capacity", "max_slots"]:
		if session.has(key):
			parts.append("%d类" % int(session.get(key, 0)))
			break
	if not parts.is_empty():
		lines.append("容量: %s" % " / ".join(parts))


func _bulk_partial_text(feedback: Dictionary) -> String:
	var failures: Array = _array_or_empty(feedback.get("failures", []))
	var failed_text := str(feedback.get("reason", ""))
	if not failures.is_empty():
		failed_text = _feedback_text(_dictionary_or_empty(failures[0]))
	return "已完成部分转移（%d 项），但后续失败：%s" % [
		int(feedback.get("transfer_count", 0)),
		failed_text,
	]


func _feedback_item_name(feedback: Dictionary) -> String:
	var item_id := _normalize_content_id(feedback.get("item_id", ""))
	if item_id.is_empty():
		return "物品"
	var item_data := _item_data(item_id)
	return str(item_data.get("name", item_id))


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
	return str(value)
