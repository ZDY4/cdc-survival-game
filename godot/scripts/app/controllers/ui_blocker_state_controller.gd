extends RefCounted


func gameplay_input_blocked(hud_blocker: Dictionary, panel_blocked: bool, world_action_blocks: bool) -> bool:
	return bool(hud_blocker.get("blocked", false)) or panel_blocked or world_action_blocks


func panel_modal_blocker_snapshot(panel_blocker: Dictionary) -> Dictionary:
	if str(panel_blocker.get("kind", "")) == "modal":
		return panel_blocker.duplicate(true)
	return {}


func blocker_name(hud_blocker: Dictionary, panel_modal: Dictionary, context_menu: Dictionary, world_action_blocker: Dictionary, panel_blocker_name: String) -> String:
	if bool(hud_blocker.get("blocked", false)):
		return str(hud_blocker.get("name", ""))
	if not panel_modal.is_empty():
		return str(panel_modal.get("name", ""))
	if bool(context_menu.get("active", false)):
		return str(dictionary_or_empty(context_menu.get("top", {})).get("id", "context_menu"))
	if bool(world_action_blocker.get("blocked", false)):
		return str(world_action_blocker.get("name", "world_action_presenter"))
	return panel_blocker_name


func blocker_snapshot(hud_blocker: Dictionary, panel_modal: Dictionary, context_menu: Dictionary, world_action_presenter: Dictionary, world_action_blocker: Dictionary, world_action_blocks: bool, panel_blocker: Dictionary, fallback_name: String) -> Dictionary:
	if bool(hud_blocker.get("blocked", false)):
		return hud_blocker.duplicate(true)
	if not panel_modal.is_empty():
		return panel_modal.duplicate(true)
	if bool(context_menu.get("active", false)):
		var top_menu: Dictionary = dictionary_or_empty(context_menu.get("top", {}))
		return {
			"blocked": true,
			"name": str(top_menu.get("id", "context_menu")),
			"kind": "context_menu",
			"modal_id": "",
			"panel_id": str(top_menu.get("owner_panel", "")),
			"mouse_blocks_world": bool(top_menu.get("mouse_blocks_world", true)),
			"option_count": int(top_menu.get("option_count", 0)),
		}
	if bool(world_action_blocker.get("blocked", false)):
		var snapshot := world_action_blocker.duplicate(true)
		snapshot["modal_id"] = str(snapshot.get("modal_id", ""))
		snapshot["panel_id"] = str(snapshot.get("panel_id", "world"))
		snapshot["mouse_blocks_world"] = bool(snapshot.get("mouse_blocks_world", true))
		return snapshot
	if world_action_blocks:
		return {
			"blocked": true,
			"name": "world_action_presenter",
			"kind": "world_action_presenter",
			"modal_id": "",
			"panel_id": "world",
			"mouse_blocks_world": true,
			"action_kind": str(world_action_presenter.get("kind", "")),
			"active_count": int(world_action_presenter.get("active_count", 0)),
			"sequence": int(world_action_presenter.get("sequence", 0)),
		}
	if not panel_blocker.is_empty():
		return panel_blocker.duplicate(true)
	return {
		"blocked": not fallback_name.is_empty(),
		"name": fallback_name,
		"kind": "",
		"modal_id": "",
		"panel_id": "",
		"mouse_blocks_world": not fallback_name.is_empty(),
	}


func menu_state_snapshot(panel_snapshot: Dictionary, fallback_priority: Array, modal_stack: Dictionary, context_menu: Dictionary, close_context: Dictionary) -> Dictionary:
	var snapshot := panel_snapshot.duplicate(true)
	if snapshot.is_empty():
		snapshot = {
			"active_stage_panel": "",
			"stage_panel_open": false,
			"stage_panels": [],
			"stage_panel_ids": [],
			"settings_open": false,
			"open_panels": [],
			"open_panel_count": 0,
			"gameplay_blocked": false,
			"blocker": {},
		}
	var panel_priority: Array = array_or_empty(snapshot.get("close_priority", fallback_priority))
	snapshot["panel_close_priority"] = panel_priority.duplicate(true)
	snapshot["close_priority"] = root_close_priority(panel_priority, close_context)
	apply_modal_event(snapshot, modal_stack)
	apply_context_menu_event(snapshot, context_menu)
	return snapshot


func root_close_priority(panel_priority: Array, close_context: Dictionary) -> Array[String]:
	var priority: Array[String] = []
	var hud_blocker: Dictionary = dictionary_or_empty(close_context.get("hud_blocker", {}))
	var hud_blocker_name := str(hud_blocker.get("name", ""))
	if bool(hud_blocker.get("blocked", false)) and not hud_blocker_name.is_empty():
		priority.append(hud_blocker_name)
	var modal_name := str(dictionary_or_empty(close_context.get("panel_modal", {})).get("name", ""))
	if not modal_name.is_empty():
		priority.append(modal_name)
	var context_menu: Dictionary = dictionary_or_empty(close_context.get("context_menu", {}))
	if bool(context_menu.get("active", false)):
		var top_menu: Dictionary = dictionary_or_empty(context_menu.get("top", {}))
		var context_menu_id := str(top_menu.get("id", "context_menu"))
		if not context_menu_id.is_empty() and not priority.has(context_menu_id):
			priority.append(context_menu_id)
	if bool(close_context.get("world_action_blocks", false)):
		priority.append("world_action_presenter")
	if bool(close_context.get("skill_targeting_active", false)):
		priority.append("skill_targeting")
	if bool(close_context.get("selection_active", false)):
		priority.append("selection")
	var has_pending := bool(close_context.get("has_pending", false))
	for item in panel_priority:
		var id := str(item)
		if id == "settings" and has_pending:
			continue
		if not id.is_empty() and not priority.has(id):
			priority.append(id)
	if has_pending:
		priority.append("pending")
	if priority.is_empty():
		priority.append("settings")
	return priority


func apply_modal_event(menu_state: Dictionary, modal_stack: Dictionary) -> void:
	if not bool(modal_stack.get("active", false)):
		menu_state["modal_event"] = {}
		return
	var top_modal: Dictionary = dictionary_or_empty(modal_stack.get("top", {}))
	var modal_id := str(top_modal.get("id", top_modal.get("modal_id", "modal")))
	var event := {
		"event": "modal_opened",
		"panel_id": modal_id,
		"kind": str(top_modal.get("kind", "modal")),
		"visible": true,
		"reason": "modal_stack_snapshot",
		"owner_panel": str(top_modal.get("owner_panel", "")),
		"mouse_blocks_world": bool(top_modal.get("mouse_blocks_world", true)),
		"blocks_gameplay": bool(top_modal.get("blocks_gameplay", true)),
	}
	if top_modal.has("item_id"):
		event["item_id"] = str(top_modal.get("item_id", ""))
	if top_modal.has("skill_id"):
		event["skill_id"] = str(top_modal.get("skill_id", ""))
	if top_modal.has("count"):
		event["count"] = int(top_modal.get("count", 0))
	event = append_menu_state_event(menu_state, event)
	menu_state["modal_event"] = event.duplicate(true)


func apply_context_menu_event(menu_state: Dictionary, context_menu: Dictionary) -> void:
	if not bool(context_menu.get("active", false)):
		menu_state["context_menu_event"] = {}
		return
	var top_menu: Dictionary = dictionary_or_empty(context_menu.get("top", {}))
	var event := {
		"event": "context_menu_opened",
		"panel_id": str(top_menu.get("id", "context_menu")),
		"kind": str(top_menu.get("kind", "context_menu")),
		"visible": true,
		"reason": "context_menu_snapshot",
		"owner_panel": str(top_menu.get("owner_panel", "")),
		"mouse_blocks_world": bool(top_menu.get("mouse_blocks_world", true)),
	}
	event = append_menu_state_event(menu_state, event)
	menu_state["context_menu_event"] = event.duplicate(true)


func append_menu_state_event(menu_state: Dictionary, event: Dictionary) -> Dictionary:
	var enriched_event := event.duplicate(true)
	enriched_event["sequence"] = int(menu_state.get("recent_event_count", 0)) + 1
	var recent_events: Array = array_or_empty(menu_state.get("recent_events", [])).duplicate(true)
	recent_events.append(enriched_event)
	while recent_events.size() > 8:
		recent_events.pop_front()
	menu_state["recent_events"] = recent_events
	menu_state["recent_event_count"] = recent_events.size()
	menu_state["latest_event"] = enriched_event.duplicate(true)
	return enriched_event


func layer_stack_snapshot(blocker: Dictionary, modal_stack: Dictionary, context_menu: Dictionary, drag: Dictionary, tooltip: Dictionary) -> Dictionary:
	var layers: Array[Dictionary] = []
	if bool(blocker.get("blocked", false)) and (str(blocker.get("kind", "")) != "context_menu" or not bool(context_menu.get("active", false))):
		var blocker_kind := str(blocker.get("kind", ""))
		layers.append({
			"id": str(blocker.get("name", "")),
			"kind": blocker_kind,
			"owner_panel": str(blocker.get("panel_id", "")),
			"priority": layer_priority(blocker_kind, str(blocker.get("name", ""))),
			"mouse_blocks_world": bool(blocker.get("mouse_blocks_world", true)),
			"blocks_gameplay": true,
			"source": "blocker",
		})
	if bool(drag.get("active", false)):
		layers.append({
			"id": "drag_preview",
			"kind": "drag_preview",
			"owner_panel": str(dictionary_or_empty(drag.get("source", {})).get("owner_panel", "")),
			"priority": layer_priority("drag_preview", "drag_preview"),
			"mouse_blocks_world": true,
			"blocks_gameplay": true,
			"source": "drag",
			"preview": dictionary_or_empty(drag.get("preview", {})).duplicate(true),
			"target": dictionary_or_empty(drag.get("target", {})).duplicate(true),
		})
	if bool(context_menu.get("active", false)):
		var top_menu: Dictionary = dictionary_or_empty(context_menu.get("top", {}))
		layers.append({
			"id": str(top_menu.get("id", "context_menu")),
			"kind": str(top_menu.get("kind", "context_menu")),
			"owner_panel": str(top_menu.get("owner_panel", "hud")),
			"priority": layer_priority("context_menu", str(top_menu.get("id", ""))),
			"mouse_blocks_world": true,
			"blocks_gameplay": true,
			"source": "context_menu",
			"option_count": int(top_menu.get("option_count", 0)),
		})
	if bool(tooltip.get("active", false)):
		layers.append({
			"id": "tooltip",
			"kind": "tooltip",
			"owner_panel": str(tooltip.get("owner_panel", "")),
			"priority": layer_priority("tooltip", "tooltip"),
			"mouse_blocks_world": false,
			"blocks_gameplay": false,
			"source": "tooltip",
			"text": str(tooltip.get("text", "")),
			"source_path": str(tooltip.get("source_path", "")),
			"source_name": str(tooltip.get("source_name", "")),
			"screen_position": dictionary_or_empty(tooltip.get("screen_position", {})).duplicate(true),
			"source_rect": dictionary_or_empty(tooltip.get("source_rect", {})).duplicate(true),
			"viewport_size": dictionary_or_empty(tooltip.get("viewport_size", {})).duplicate(true),
			"lifecycle_state": str(tooltip.get("lifecycle_state", "")),
			"delay_policy": str(tooltip.get("delay_policy", "")),
			"visual": dictionary_or_empty(tooltip.get("visual", {})).duplicate(true),
			"recommended_rect": dictionary_or_empty(tooltip.get("recommended_rect", {})).duplicate(true),
		})
	layers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ap := int(a.get("priority", 0))
		var bp := int(b.get("priority", 0))
		if ap == bp:
			return str(a.get("id", "")) < str(b.get("id", ""))
		return ap > bp
	)
	var top_blocking: Dictionary = {}
	for layer in layers:
		var layer_data: Dictionary = dictionary_or_empty(layer)
		if bool(layer_data.get("blocks_gameplay", false)) or bool(layer_data.get("mouse_blocks_world", false)):
			top_blocking = layer_data.duplicate(true)
			break
	return {
		"active": not layers.is_empty(),
		"count": layers.size(),
		"blocks_world": not top_blocking.is_empty(),
		"top": layers[0].duplicate(true) if not layers.is_empty() else {},
		"top_blocking": top_blocking,
		"layers": layers,
		"blocker": blocker,
		"modal_stack": modal_stack,
		"context_menu": context_menu,
		"drag": drag,
		"tooltip": tooltip,
	}


func layer_priority(kind: String, layer_id: String) -> int:
	if layer_id == "debug_console" or kind == "debug_console":
		return 1000
	if kind == "modal" or layer_id.begins_with("modal:"):
		return 900
	if kind == "drag_preview":
		return 800
	if kind == "context_menu" or layer_id == "interaction_menu":
		return 700
	if kind in ["stage", "settings", "panel", "world_action_presenter"]:
		return 600
	if kind == "tooltip":
		return 100
	return 0


func close_active_context_menu(context_menu: Dictionary, owner_panels: Dictionary) -> Dictionary:
	if not bool(context_menu.get("active", false)):
		return {"success": false, "reason": "context_menu_inactive"}
	var top_menu: Dictionary = dictionary_or_empty(context_menu.get("top", {}))
	var owner_panel := str(top_menu.get("owner_panel", ""))
	var menu_id := str(top_menu.get("id", "context_menu"))
	var panel: Object = owner_panels.get(owner_panel, null)
	if panel == null or not panel.has_method("close_context_menu"):
		return {
			"success": false,
			"reason": "context_menu_owner_missing",
			"closed": menu_id,
			"owner_panel": owner_panel,
		}
	panel.call("close_context_menu")
	return {
		"success": true,
		"closed": menu_id,
		"owner_panel": owner_panel,
	}


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
