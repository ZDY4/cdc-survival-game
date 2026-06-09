extends RefCounted

const GamePanelController = preload("res://scripts/app/controllers/game_panel_controller.gd")
const UiOverlayRenderController = preload("res://scripts/app/controllers/ui_overlay_render_controller.gd")

var parent: Node
var panel_controller: RefCounted
var ui_overlay_render_controller: RefCounted = UiOverlayRenderController.new()


func _init(p_parent: Node = null) -> void:
	parent = p_parent


func setup_panels(registry: RefCounted, simulation: RefCounted, world_result: Dictionary, feedback: Dictionary) -> Dictionary:
	if panel_controller == null:
		panel_controller = GamePanelController.new(parent, registry, simulation, world_result)
	panel_controller.update_runtime(simulation, world_result)
	_apply_feedback(feedback)
	panel_controller.setup_panels()
	return panel_refs()


func update_runtime(simulation: RefCounted, world_result: Dictionary) -> void:
	if panel_controller != null:
		panel_controller.update_runtime(simulation, world_result)


func refresh_hud(selected_prompt: Dictionary = {}) -> void:
	if panel_controller != null:
		panel_controller.refresh_hud(selected_prompt)


func refresh_panel(panel_id: String, feedback: Dictionary = {}) -> void:
	if panel_controller == null:
		return
	_apply_feedback(feedback)
	match panel_id:
		"dialogue":
			panel_controller.refresh_dialogue_panel()
		"inventory":
			panel_controller.refresh_inventory_panel()
		"trade":
			panel_controller.refresh_trade_panel()
		"container":
			panel_controller.refresh_container_panel()
		"character":
			panel_controller.refresh_character_panel()
		"journal":
			panel_controller.refresh_journal_panel()
		"map":
			panel_controller.refresh_map_panel()
		"skills":
			panel_controller.refresh_skills_panel()
		"crafting":
			panel_controller.refresh_crafting_panel()


func refresh_all(selected_prompt: Dictionary = {}, feedback: Dictionary = {}) -> void:
	if panel_controller == null:
		return
	_apply_feedback(feedback)
	panel_controller.refresh_all(selected_prompt)


func toggle_stage_panel(panel_id: String) -> Dictionary:
	if panel_controller == null:
		return {"success": false, "reason": "panel_controller_missing"}
	return dictionary_or_empty(panel_controller.toggle_stage_panel(panel_id))


func close_stage_panels() -> Dictionary:
	if panel_controller == null:
		return {"success": false, "reason": "panel_controller_missing"}
	return dictionary_or_empty(panel_controller.close_stage_panels())


func open_stage_panel(panel_id: String) -> Dictionary:
	if panel_controller == null or not panel_controller.has_method("open_stage_panel"):
		return {"success": false, "reason": "panel_controller_missing"}
	return dictionary_or_empty(panel_controller.call("open_stage_panel", panel_id))


func any_stage_panel_open() -> bool:
	return panel_controller != null and panel_controller.any_stage_panel_open()


func open_settings_panel() -> Dictionary:
	if panel_controller == null:
		return {"success": false, "reason": "panel_controller_missing"}
	return dictionary_or_empty(panel_controller.open_settings_panel())


func close_settings_panel() -> Dictionary:
	if panel_controller == null:
		return {"success": false, "reason": "panel_controller_missing"}
	return dictionary_or_empty(panel_controller.close_settings_panel())


func is_settings_open() -> bool:
	return panel_controller != null and panel_controller.is_settings_open()


func gameplay_input_blocked() -> bool:
	return panel_controller != null and panel_controller.gameplay_input_blocked()


func gameplay_input_blocker_name() -> String:
	if panel_controller != null and panel_controller.has_method("gameplay_input_blocker_name"):
		return str(panel_controller.gameplay_input_blocker_name())
	return ""


func gameplay_input_blocker_snapshot() -> Dictionary:
	if panel_controller != null and panel_controller.has_method("gameplay_input_blocker_snapshot"):
		return dictionary_or_empty(panel_controller.call("gameplay_input_blocker_snapshot"))
	return {}


func input_blocker_snapshot() -> Dictionary:
	return gameplay_input_blocker_snapshot()


func modal_stack_snapshot() -> Dictionary:
	if panel_controller != null and panel_controller.has_method("modal_stack_snapshot"):
		return dictionary_or_empty(panel_controller.call("modal_stack_snapshot"))
	return {"active": false, "count": 0, "top": {}, "stack": []}


func menu_state_snapshot() -> Dictionary:
	if panel_controller != null and panel_controller.has_method("menu_state_snapshot"):
		return dictionary_or_empty(panel_controller.call("menu_state_snapshot")).duplicate(true)
	return {}


func ui_theme_snapshot() -> Dictionary:
	if panel_controller != null and panel_controller.has_method("ui_theme_snapshot"):
		return dictionary_or_empty(panel_controller.call("ui_theme_snapshot"))
	return {"applied": false, "reason": "panel_controller_missing"}


func close_blocking_modal() -> Dictionary:
	if panel_controller != null and panel_controller.has_method("close_blocking_modal"):
		return dictionary_or_empty(panel_controller.call("close_blocking_modal"))
	return {"success": false, "reason": "modal_inactive"}


func handle_trade_shortcut(event: InputEventKey) -> bool:
	return panel_controller != null and panel_controller.handle_trade_shortcut(event)


func close_trade_panel() -> void:
	if panel_controller != null:
		panel_controller.close_trade_panel()


func setup_tooltip_layer(owner: Node = null) -> void:
	ui_overlay_render_controller.call("setup_tooltip_layer", _overlay_owner(owner))


func update_tooltip_layer(snapshot: Dictionary, owner: Node = null) -> void:
	setup_tooltip_layer(owner)
	if not bool(snapshot.get("active", false)):
		hide_tooltip_layer(str(snapshot.get("lifecycle_state", "inactive")))
		return
	render_tooltip_snapshot(snapshot, owner)


func hide_tooltip_layer(reason: String) -> void:
	ui_overlay_render_controller.call("hide_tooltip_layer", reason)


func render_tooltip_snapshot(snapshot: Dictionary, owner: Node = null) -> void:
	ui_overlay_render_controller.call("render_tooltip_snapshot", _overlay_owner(owner), snapshot)


func tooltip_render_snapshot() -> Dictionary:
	return dictionary_or_empty(ui_overlay_render_controller.call("tooltip_render_snapshot"))


func setup_drag_preview_layer(owner: Node = null) -> void:
	ui_overlay_render_controller.call("setup_drag_preview_layer", _overlay_owner(owner))


func render_drag_preview_snapshot(drag: Dictionary, owner: Node = null) -> void:
	ui_overlay_render_controller.call("render_drag_preview_snapshot", _overlay_owner(owner), drag)


func hide_drag_preview_layer(reason: String) -> void:
	ui_overlay_render_controller.call("hide_drag_preview_layer", reason)


func drag_preview_render_snapshot() -> Dictionary:
	return dictionary_or_empty(ui_overlay_render_controller.call("drag_preview_render_snapshot"))


func toggle_controls_hint() -> Dictionary:
	var hud: Control = panel("hud")
	if hud == null or not hud.has_method("toggle_controls_hint"):
		return {"success": false, "reason": "hud_missing"}
	return dictionary_or_empty(hud.call("toggle_controls_hint"))


func controls_hint_visible() -> bool:
	var hud: Control = panel("hud")
	return hud != null and hud.has_method("is_controls_hint_visible") and bool(hud.call("is_controls_hint_visible"))


func controls_hint_snapshot() -> Dictionary:
	var hud: Control = panel("hud")
	if hud != null and hud.has_method("controls_hint_snapshot"):
		return dictionary_or_empty(hud.call("controls_hint_snapshot"))
	return {"visible": false, "line_count": 0, "lines": []}


func toggle_debug_console() -> Dictionary:
	var hud: Control = panel("hud")
	if hud == null or not hud.has_method("toggle_debug_console"):
		return {"success": false, "reason": "hud_missing"}
	return dictionary_or_empty(hud.call("toggle_debug_console"))


func close_debug_console() -> Dictionary:
	var hud: Control = panel("hud")
	if hud == null or not hud.has_method("hide_debug_console"):
		return {"success": false, "reason": "hud_missing"}
	hud.call("hide_debug_console")
	return {"success": true, "visible": false}


func is_debug_console_open() -> bool:
	var hud: Control = panel("hud")
	return hud != null and hud.has_method("is_debug_console_open") and bool(hud.call("is_debug_console_open"))


func debug_console_snapshot(permission: Dictionary = {}) -> Dictionary:
	var hud: Control = panel("hud")
	if hud != null and hud.has_method("debug_console_snapshot"):
		var snapshot: Dictionary = dictionary_or_empty(hud.call("debug_console_snapshot"))
		snapshot["permission"] = permission.duplicate(true)
		return snapshot
	return {
		"visible": false,
		"history": [],
		"history_count": 0,
		"suggestions": [],
		"suggestion_count": 0,
		"input_text": "",
		"permission": permission.duplicate(true),
	}


func set_debug_console_schema(schema: Array, suggestions: Array, permission: Dictionary = {}) -> void:
	var hud: Control = panel("hud")
	if hud != null and hud.has_method("set_debug_console_schema"):
		hud.call("set_debug_console_schema", schema, suggestions, permission)


func set_debug_console_result(command: String, result: Dictionary) -> void:
	var hud: Control = panel("hud")
	if hud != null and hud.has_method("set_debug_console_result"):
		hud.call("set_debug_console_result", command, result)


func toggle_debug_panel() -> Dictionary:
	var hud: Control = panel("hud")
	if hud == null or not hud.has_method("toggle_debug_panel"):
		return {"success": false, "reason": "hud_missing"}
	return dictionary_or_empty(hud.call("toggle_debug_panel"))


func is_debug_panel_open() -> bool:
	var hud: Control = panel("hud")
	return hud != null and hud.has_method("is_debug_panel_open") and bool(hud.call("is_debug_panel_open"))


func debug_panel_snapshot() -> Dictionary:
	var hud: Control = panel("hud")
	if hud != null and hud.has_method("debug_panel_snapshot"):
		return dictionary_or_empty(hud.call("debug_panel_snapshot"))
	return {"visible": false, "line_count": 0, "lines": []}


func hud_input_blocker_snapshot(debug_console_open: bool = false) -> Dictionary:
	var hud: Control = panel("hud")
	if hud != null and hud.has_method("input_blocker_snapshot"):
		return dictionary_or_empty(hud.call("input_blocker_snapshot"))
	if debug_console_open:
		return {
			"blocked": true,
			"name": "debug_console",
			"kind": "debug_console",
			"modal_id": "",
			"panel_id": "hud",
			"mouse_blocks_world": true,
		}
	if hud != null and hud.has_method("is_interaction_menu_open") and bool(hud.is_interaction_menu_open()):
		return {
			"blocked": true,
			"name": "interaction_menu",
			"kind": "context_menu",
			"modal_id": "",
			"panel_id": "hud",
			"mouse_blocks_world": true,
		}
	return {}


func close_hud_interaction_menu() -> bool:
	var hud: Control = panel("hud")
	if hud != null and hud.has_method("hide_interaction_menu"):
		hud.hide_interaction_menu()
		return true
	return false


func context_menu_snapshot() -> Dictionary:
	var menus: Array[Dictionary] = []
	for panel_id in ["hud", "inventory", "container", "trade", "skills", "character"]:
		var control: Control = panel(panel_id)
		if control == null:
			continue
		var method_name := "interaction_menu_snapshot" if panel_id == "hud" else "context_menu_snapshot"
		if not control.has_method(method_name):
			continue
		var menu: Dictionary = dictionary_or_empty(control.call(method_name))
		if not menu.is_empty():
			menus.append(menu)
	return {
		"active": not menus.is_empty(),
		"count": menus.size(),
		"top": menus[menus.size() - 1].duplicate(true) if not menus.is_empty() else {},
		"menus": menus,
	}


func panel_refs() -> Dictionary:
	if panel_controller == null:
		return {}
	return {
		"hud": panel_controller.hud,
		"dialogue": panel_controller.dialogue_panel,
		"inventory": panel_controller.inventory_panel,
		"trade": panel_controller.trade_panel,
		"container": panel_controller.container_panel,
		"character": panel_controller.character_panel,
		"journal": panel_controller.journal_panel,
		"map": panel_controller.map_panel,
		"skills": panel_controller.skills_panel,
		"crafting": panel_controller.crafting_panel,
		"settings": panel_controller.settings_panel,
	}


func panel(panel_id: String) -> Control:
	return panel_refs().get(panel_id, null) as Control


func _apply_feedback(feedback: Dictionary) -> void:
	if panel_controller == null:
		return
	if feedback.has("active_trade_target"):
		panel_controller.active_trade_target = dictionary_or_empty(feedback.get("active_trade_target", {}))
	if feedback.has("active_trade_feedback"):
		panel_controller.active_trade_feedback = dictionary_or_empty(feedback.get("active_trade_feedback", {}))
	if feedback.has("active_container_feedback"):
		panel_controller.active_container_feedback = dictionary_or_empty(feedback.get("active_container_feedback", {}))
	if feedback.has("active_character_feedback"):
		panel_controller.active_character_feedback = dictionary_or_empty(feedback.get("active_character_feedback", {}))
	if feedback.has("active_inventory_feedback"):
		panel_controller.active_inventory_feedback = dictionary_or_empty(feedback.get("active_inventory_feedback", {}))


func _overlay_owner(owner: Node = null) -> Node:
	return owner if owner != null else parent


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
