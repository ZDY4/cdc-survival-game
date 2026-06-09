extends RefCounted


func drag_state_snapshot(viewport: Viewport, data: Variant, target_snapshot: Dictionary) -> Dictionary:
	var drag_data: Dictionary = _dictionary_or_empty(data)
	if drag_data.is_empty():
		return {
			"active": false,
			"kind": "",
			"source": {},
			"target": target_snapshot.duplicate(true),
			"preview": {},
			"payload": {},
		}
	var kind := str(drag_data.get("kind", ""))
	var payload := drag_payload_snapshot(drag_data)
	return {
		"active": true,
		"kind": kind,
		"source": drag_source_snapshot(drag_data, kind),
		"target": target_snapshot.duplicate(true),
		"preview": drag_preview_snapshot(viewport, drag_data, payload),
		"payload": payload,
	}


func drag_source_snapshot(drag_data: Dictionary, kind: String) -> Dictionary:
	var output := {
		"kind": kind,
		"owner_panel": drag_source_owner(kind, drag_data),
		"source": str(drag_data.get("source", "")),
		"from_index": int(drag_data.get("from_index", drag_data.get("index", -1))),
	}
	if kind == "skill_hotbar":
		output["source"] = "skills"
	elif kind == "inventory_item" and str(output.get("source", "")).is_empty():
		output["source"] = "inventory"
	return output


func drag_source_owner(kind: String, drag_data: Dictionary) -> String:
	match kind:
		"inventory_item":
			return "inventory"
		"skill_hotbar":
			return "skills"
		"trade_item", "trade_cart_entry":
			return "trade"
		"container_item":
			return "container"
	var source := str(drag_data.get("source", ""))
	return source if source in ["inventory", "skills", "trade", "container", "hud", "character"] else ""


func drag_payload_snapshot(drag_data: Dictionary) -> Dictionary:
	var kind := str(drag_data.get("kind", ""))
	var item: Dictionary = _dictionary_or_empty(drag_data.get("item", {}))
	var skill: Dictionary = _dictionary_or_empty(drag_data.get("skill", {}))
	match kind:
		"inventory_item", "trade_item", "container_item":
			return {
				"item_id": str(drag_data.get("item_id", item.get("item_id", ""))),
				"name": str(item.get("name", drag_data.get("item_id", ""))),
				"count": int(drag_data.get("count", item.get("count", 1))),
				"item_count": int(item.get("count", drag_data.get("count", 1))),
			}
		"skill_hotbar":
			return {
				"skill_id": str(drag_data.get("skill_id", skill.get("skill_id", ""))),
				"name": str(skill.get("name", drag_data.get("skill_id", ""))),
				"count": 1,
			}
		"trade_cart_entry":
			return {
				"index": int(drag_data.get("index", -1)),
				"name": str(drag_data.get("name", "")),
				"count": int(drag_data.get("count", 1)),
			}
	return {"count": int(drag_data.get("count", 0))}


func drag_preview_snapshot(viewport: Viewport, drag_data: Dictionary, payload: Dictionary) -> Dictionary:
	var text := str(drag_data.get("drag_preview_text", ""))
	if text.is_empty():
		match str(drag_data.get("kind", "")):
			"skill_hotbar":
				text = "%s -> 热栏" % str(payload.get("name", payload.get("skill_id", "")))
			_:
				var name := str(payload.get("name", payload.get("item_id", "")))
				var count := int(payload.get("count", 0))
				text = "%s x%d" % [name, count] if not name.is_empty() and count > 0 else name
	var mouse_position := viewport.get_mouse_position() if viewport != null else Vector2.ZERO
	var viewport_size := viewport.get_visible_rect().size if viewport != null else Vector2.ZERO
	var estimated_size := drag_preview_estimated_size(text)
	return {
		"text": text,
		"has_preview": not text.is_empty(),
		"screen_position": vector2_snapshot(mouse_position),
		"viewport_size": vector2_snapshot(viewport_size),
		"estimated_size": vector2_snapshot(estimated_size),
		"anchor": vector2_snapshot(Vector2(8.0, 8.0)),
		"lifecycle_state": "dragging",
		"threshold_policy": "godot_default",
		"threshold_px": -1,
	}


func drag_preview_estimated_size(text: String) -> Vector2:
	if text.is_empty():
		return Vector2.ZERO
	return Vector2(maxf(48.0, float(text.length() * 8 + 16)), 24.0)


func vector2_snapshot(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
