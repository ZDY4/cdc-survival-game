extends RefCounted


func inactive_target() -> Dictionary:
	return {
		"active": false,
		"owner_panel": "",
		"target_kind": "",
		"target_id": "",
		"source_path": "",
		"accepts": "",
		"last_accept": false,
		"reject_reason": "",
		"reject_reason_text": "",
		"hover_highlight": hover_highlight(false, "", "", "", false),
	}


func observe_hotbar_target(drag_data: Dictionary, observe_key: String) -> Dictionary:
	var reject_reason := "observe_hotbar_drag_unsupported" if not drag_data.is_empty() else ""
	return {
		"target_kind": "observe_hotbar",
		"target_id": observe_key,
		"observe_key": observe_key,
		"accepts": "",
		"last_accept": false,
		"reject_reason": reject_reason,
		"hover_highlight": hover_highlight(not drag_data.is_empty(), "observe_hotbar", observe_key, reject_reason, false),
	}


func hotbar_slot_target(control: Control, drag_data: Dictionary) -> Dictionary:
	var slot_id := str(control.get_meta("hotbar_slot_id", "")) if control != null else ""
	var group_id := str(control.get_meta("hotbar_group_id", "")) if control != null else ""
	var acceptance: Dictionary = hotbar_slot_acceptance(slot_id, drag_data)
	var last_accept := bool(acceptance.get("accept", false))
	var reject_reason := str(acceptance.get("reason", ""))
	return {
		"target_kind": "hotbar_slot",
		"target_id": slot_id,
		"slot_id": slot_id,
		"group_id": group_id,
		"accepts": "skill_hotbar",
		"last_accept": last_accept,
		"reject_reason": reject_reason,
		"hover_highlight": hover_highlight(not drag_data.is_empty(), "hotbar_slot", slot_id, reject_reason, last_accept),
	}


func hotbar_slot_acceptance(slot_id: String, drag_data: Dictionary) -> Dictionary:
	if drag_data.is_empty():
		return {"accept": false, "reason": ""}
	if str(drag_data.get("kind", "")) != "skill_hotbar":
		return {"accept": false, "reason": "hotbar_slot_requires_skill_hotbar"}
	if str(drag_data.get("skill_id", "")).is_empty():
		return {"accept": false, "reason": "hotbar_slot_missing_skill"}
	if slot_id.is_empty():
		return {"accept": false, "reason": "hotbar_slot_missing_slot"}
	return {"accept": true, "reason": ""}


func hotbar_group_target(control: Control, drag_data: Dictionary) -> Dictionary:
	var group_id := str(control.get_meta("hotbar_group_id", "")) if control != null else ""
	var reject_reason := "hotbar_group_drag_unsupported" if not drag_data.is_empty() else ""
	return {
		"target_kind": "hotbar_group",
		"target_id": group_id,
		"group_id": group_id,
		"accepts": "",
		"last_accept": false,
		"reject_reason": reject_reason,
		"hover_highlight": hover_highlight(not drag_data.is_empty(), "hotbar_group", group_id, reject_reason, false),
	}


func trade_cart_target(control: Control, drag_data: Dictionary, target_kind: String, target_id: String) -> Dictionary:
	var acceptance: Dictionary = trade_cart_acceptance(control, drag_data)
	var last_accept := bool(acceptance.get("accept", false))
	var reject_reason := str(acceptance.get("reason", ""))
	return {
		"target_kind": target_kind,
		"target_id": target_id,
		"accepts": "trade_item,inventory_item,trade_cart_entry",
		"last_accept": last_accept,
		"reject_reason": reject_reason,
		"hover_highlight": hover_highlight(not drag_data.is_empty(), target_kind, target_id, reject_reason, last_accept),
	}


func trade_drop_zone_target(control: Control, drag_data: Dictionary) -> Dictionary:
	var zone_id := str(control.get_meta("trade_drop_zone", "")) if control != null else ""
	var acceptance: Dictionary = trade_drop_zone_acceptance(control, drag_data)
	var last_accept := bool(acceptance.get("accept", false))
	var reject_reason := str(acceptance.get("reason", ""))
	return {
		"target_kind": "trade_drop_zone",
		"target_id": zone_id,
		"zone_id": zone_id,
		"accepts": str(control.get_meta("trade_drop_accepts", "")) if control != null else "",
		"last_accept": last_accept,
		"reject_reason": reject_reason,
		"last_source": str(acceptance.get("source", control.get_meta("trade_drop_last_source", "") if control != null else "")),
		"last_preview_text": str(control.get_meta("trade_drop_last_preview_text", "")) if control != null else "",
		"hover_highlight": hover_highlight(not drag_data.is_empty(), "trade_drop_zone", zone_id, reject_reason, last_accept),
	}


func trade_drop_zone_acceptance(control: Control, drag_data: Dictionary) -> Dictionary:
	if control == null:
		return {"accept": false, "reason": "drop_zone_missing", "source": ""}
	if drag_data.is_empty():
		return {"accept": bool(control.get_meta("trade_drop_last_accept", false)), "reason": str(control.get_meta("trade_drop_last_reject_reason", "")), "source": str(control.get_meta("trade_drop_last_source", ""))}
	var zone_id := str(control.get_meta("trade_drop_zone", ""))
	match str(drag_data.get("kind", "")):
		"trade_item":
			var source := str(drag_data.get("source", ""))
			if source.is_empty():
				return {"accept": false, "reason": "unknown_trade_item", "source": source}
			if not trade_drop_zone_source_matches(zone_id, source):
				return {"accept": false, "reason": str(control.get_meta("trade_drop_reject_reason", "drop_zone_source_mismatch")), "source": source}
			return {"accept": true, "reason": "", "source": source}
		"inventory_item":
			var item: Dictionary = dictionary_or_empty(drag_data.get("item", {}))
			var item_id := str(drag_data.get("item_id", item.get("item_id", "")))
			if item_id.is_empty():
				return {"accept": false, "reason": "unknown_trade_item", "source": "player"}
			if not trade_drop_zone_source_matches(zone_id, "player"):
				return {"accept": false, "reason": str(control.get_meta("trade_drop_reject_reason", "drop_zone_source_mismatch")), "source": "player"}
			return {"accept": true, "reason": "", "source": "player"}
		"trade_cart_entry":
			return {"accept": false, "reason": "cart_entry_requires_cart_target", "source": "cart"}
	return {"accept": false, "reason": "trade_cart_unsupported_drag_data", "source": ""}


func trade_drop_zone_source_matches(zone_id: String, source: String) -> bool:
	match zone_id:
		"buy":
			return source == "shop"
		"sell":
			return source == "player" or source.begins_with("equipment:")
	return true


func trade_cart_acceptance(control: Control, drag_data: Dictionary) -> Dictionary:
	if drag_data.is_empty():
		return {"accept": false, "reason": ""}
	match str(drag_data.get("kind", "")):
		"trade_item":
			var item: Dictionary = dictionary_or_empty(drag_data.get("item", {}))
			if item.is_empty():
				return {"accept": false, "reason": "unknown_trade_item"}
			return {"accept": true, "reason": ""}
		"inventory_item":
			var item: Dictionary = dictionary_or_empty(drag_data.get("item", {}))
			var item_id := str(drag_data.get("item_id", item.get("item_id", "")))
			if item_id.is_empty():
				return {"accept": false, "reason": "unknown_trade_item"}
			return {"accept": true, "reason": ""}
		"trade_cart_entry":
			var index := int(drag_data.get("index", -1))
			if index < 0:
				return {"accept": false, "reason": "cart_entry_missing_index"}
			if control != null and control.has_meta("trade_drop_zone"):
				return {"accept": false, "reason": "cart_entry_requires_cart_target"}
			return {"accept": true, "reason": ""}
	return {"accept": false, "reason": "trade_cart_unsupported_drag_data"}


func container_target(control: Control, drag_data: Dictionary) -> Dictionary:
	var column_source := str(control.get_meta("container_source", "")) if control != null else ""
	var acceptance: Dictionary = container_acceptance(column_source, drag_data)
	var last_accept := bool(acceptance.get("accept", false))
	var reject_reason := str(acceptance.get("reason", ""))
	return {
		"target_kind": "container_column",
		"target_id": column_source,
		"column_source": column_source,
		"accepts": "container_item,inventory_item",
		"last_accept": last_accept,
		"reject_reason": reject_reason,
		"hover_highlight": hover_highlight(not drag_data.is_empty(), "container_column", column_source, reject_reason, last_accept),
	}


func container_acceptance(column_source: String, drag_data: Dictionary) -> Dictionary:
	if drag_data.is_empty():
		return {"accept": false, "reason": ""}
	if column_source.is_empty():
		return {"accept": false, "reason": "container_drop_target_missing"}
	match str(drag_data.get("kind", "")):
		"container_item":
			var source := str(drag_data.get("source", ""))
			var item: Dictionary = dictionary_or_empty(drag_data.get("item", {}))
			var item_id := str(item.get("item_id", ""))
			if source.is_empty():
				return {"accept": false, "reason": "container_drop_source_missing"}
			if item_id.is_empty():
				return {"accept": false, "reason": "container_drop_item_missing"}
			if source == column_source:
				return {"accept": false, "reason": "container_drop_same_column"}
			return {"accept": true, "reason": ""}
		"inventory_item":
			var item: Dictionary = dictionary_or_empty(drag_data.get("item", {}))
			var item_id := str(drag_data.get("item_id", item.get("item_id", "")))
			if item_id.is_empty():
				return {"accept": false, "reason": "container_drop_item_missing"}
			if column_source != "container":
				return {"accept": false, "reason": "container_drop_requires_container_column"}
			return {"accept": true, "reason": ""}
	return {"accept": false, "reason": "container_drop_unsupported_drag_data"}


func inventory_action_target(control: Control, drag_data: Dictionary) -> Dictionary:
	var action_id := str(control.get_meta("inventory_action_target", "")) if control != null else ""
	var acceptance: Dictionary = inventory_action_acceptance(action_id, drag_data)
	var last_accept := bool(acceptance.get("accept", false))
	var reject_reason := str(acceptance.get("reason", ""))
	return {
		"target_kind": "inventory_action",
		"target_id": action_id,
		"action_id": action_id,
		"accepts": "inventory_item",
		"last_accept": last_accept,
		"reject_reason": reject_reason,
		"hover_highlight": hover_highlight(not drag_data.is_empty(), "inventory_action", action_id, reject_reason, last_accept),
	}


func inventory_action_acceptance(action_id: String, drag_data: Dictionary) -> Dictionary:
	if drag_data.is_empty():
		return {"accept": false, "reason": ""}
	if str(drag_data.get("kind", "")) != "inventory_item":
		return {"accept": false, "reason": "inventory_action_requires_inventory_item"}
	var item: Dictionary = dictionary_or_empty(drag_data.get("item", {}))
	var item_id := str(drag_data.get("item_id", item.get("item_id", "")))
	if item_id.is_empty():
		return {"accept": false, "reason": "inventory_action_missing_item"}
	match action_id:
		"equip":
			if array_or_empty(item.get("equip_slots", [])).is_empty():
				return {"accept": false, "reason": "item_not_equippable"}
			return {"accept": true, "reason": ""}
		"drop":
			if not bool(item.get("droppable", true)):
				return {"accept": false, "reason": "item_not_droppable"}
			if int(item.get("count", 0)) <= 0:
				return {"accept": false, "reason": "invalid_quantity"}
			return {"accept": true, "reason": ""}
	return {"accept": false, "reason": "unknown_inventory_action"}


func equipment_target(control: Control, drag_data: Dictionary) -> Dictionary:
	var slot_id := str(control.get_meta("equipment_slot", "")) if control != null else ""
	var display_slot := str(control.get_meta("equipment_display_slot", slot_id)) if control != null else slot_id
	var equipment_data: Dictionary = dictionary_or_empty(control.get_meta("equipment_data", {}) if control != null else {})
	var acceptance: Dictionary = equipment_acceptance(slot_id, drag_data)
	var last_accept := bool(acceptance.get("accept", false))
	var reject_reason := str(acceptance.get("reason", ""))
	return {
		"target_kind": "equipment_slot",
		"target_id": slot_id,
		"slot_id": slot_id,
		"display_slot": display_slot,
		"accepts": "inventory_item",
		"last_accept": last_accept,
		"reject_reason": reject_reason,
		"current_item_id": str(equipment_data.get("item_id", "")),
		"current_item_name": str(equipment_data.get("name", equipment_data.get("item_id", ""))),
		"hover_highlight": hover_highlight(not drag_data.is_empty(), "equipment_slot", slot_id, reject_reason, last_accept),
	}


func equipment_acceptance(slot_id: String, drag_data: Dictionary) -> Dictionary:
	if drag_data.is_empty():
		return {"accept": false, "reason": ""}
	if str(drag_data.get("kind", "")) != "inventory_item":
		return {"accept": false, "reason": "equipment_slot_requires_inventory_item"}
	var item: Dictionary = dictionary_or_empty(drag_data.get("item", {}))
	var item_id := str(drag_data.get("item_id", item.get("item_id", "")))
	if item_id.is_empty():
		return {"accept": false, "reason": "equipment_slot_missing_item"}
	if slot_id.is_empty():
		return {"accept": false, "reason": "equipment_slot_missing_slot"}
	for candidate in array_or_empty(item.get("equip_slots", [])):
		if str(candidate) == slot_id:
			return {"accept": true, "reason": ""}
	return {"accept": false, "reason": "equipment_slot_incompatible"}


func hover_highlight(active: bool, target_kind: String, target_id: String, reject_reason: String, accepted: bool) -> Dictionary:
	var style := "accept" if accepted else "reject"
	var color := "#4ecb71" if accepted else "#e25c5c"
	if not active:
		style = "inactive"
		color = "#00000000"
	return {
		"active": active,
		"style": style,
		"color": color,
		"target_kind": target_kind,
		"target_id": target_id,
		"accepted": accepted,
		"reject_reason": reject_reason,
		"reject_reason_text": "",
		"outline_width": 2.0 if active else 0.0,
	}


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
