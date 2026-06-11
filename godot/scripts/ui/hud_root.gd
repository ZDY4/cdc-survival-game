extends Control

const GamePanelController = preload("res://scripts/app/controllers/game_panel_controller.gd")
const UiOverlayRenderController = preload("res://scripts/app/controllers/ui_overlay_render_controller.gd")
const TooltipSnapshotController = preload("res://scripts/app/controllers/tooltip_snapshot_controller.gd")
const DragSnapshotController = preload("res://scripts/app/controllers/drag_snapshot_controller.gd")
const DragHoverTargetController = preload("res://scripts/app/controllers/drag_hover_target_controller.gd")
const UiBlockerStateController = preload("res://scripts/app/controllers/ui_blocker_state_controller.gd")
const ReasonCatalog = preload("res://scripts/ui/snapshots/reason_catalog.gd")

var parent: Node
var panel_controller: RefCounted
var ui_overlay_render_controller: RefCounted = UiOverlayRenderController.new()
var tooltip_snapshot_controller: RefCounted = TooltipSnapshotController.new()
var drag_snapshot_controller: RefCounted = DragSnapshotController.new()
var drag_hover_target_controller: RefCounted = DragHoverTargetController.new()
var ui_blocker_state_controller: RefCounted = UiBlockerStateController.new()
var reason_catalog: RefCounted = ReasonCatalog.new()


func _init(p_parent: Node = null) -> void:
	parent = p_parent


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func configure(p_parent: Node) -> void:
	parent = p_parent


func setup_panels(registry: RefCounted, simulation: RefCounted, world_result: Dictionary, feedback: Dictionary) -> Dictionary:
	if panel_controller == null:
		panel_controller = GamePanelController.new(parent, registry, simulation, world_result, self)
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
	_refresh_panel_without_feedback(panel_id)


func refresh_panels(panel_ids: Array, feedback: Dictionary = {}) -> void:
	if panel_controller == null:
		return
	_apply_feedback(feedback)
	for panel_id in panel_ids:
		_refresh_panel_without_feedback(str(panel_id))


func refresh_operation_panels(panel_ids: Array, selected_prompt: Dictionary = {}, feedback: Dictionary = {}) -> void:
	if panel_controller == null:
		return
	_apply_feedback(feedback)
	var pending_panels: Array = []
	for panel_id in panel_ids:
		if str(panel_id) == "hud":
			if not pending_panels.is_empty():
				for pending_panel_id in pending_panels:
					_refresh_panel_without_feedback(str(pending_panel_id))
				pending_panels.clear()
			refresh_hud(selected_prompt)
		else:
			pending_panels.append(str(panel_id))
	for pending_panel_id in pending_panels:
		_refresh_panel_without_feedback(str(pending_panel_id))


func _refresh_panel_without_feedback(panel_id: String) -> void:
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


func hover_tooltip_snapshot(viewport: Viewport, control: Control = null) -> Dictionary:
	return dictionary_or_empty(tooltip_snapshot_controller.call("hover_tooltip_snapshot", viewport, control))


func drag_state_snapshot(viewport: Viewport, data: Variant = {}, target_snapshot: Dictionary = {}) -> Dictionary:
	return dictionary_or_empty(drag_snapshot_controller.call("drag_state_snapshot", viewport, data, target_snapshot))


func drag_hover_target_snapshot(control: Control, drag_data: Dictionary = {}) -> Dictionary:
	if control == null:
		return _enrich_drag_hover_target_reason(dictionary_or_empty(drag_hover_target_controller.call("inactive_target")))
	var target := {
		"active": true,
		"owner_panel": owner_panel_for_control(control),
		"target_kind": "control",
		"target_id": str(control.name),
		"source_path": str(control.get_path()),
		"accepts": "",
		"last_accept": false,
		"reject_reason": "",
		"reject_reason_text": "",
		"hover_highlight": dictionary_or_empty(drag_hover_target_controller.call("hover_highlight", false, "", "", "", false)),
	}
	if control.has_meta("equipment_slot"):
		_merge_dictionary(target, dictionary_or_empty(drag_hover_target_controller.call("equipment_target", control, drag_data)))
	elif control.has_meta("hotbar_slot_id"):
		_merge_dictionary(target, dictionary_or_empty(drag_hover_target_controller.call("hotbar_slot_target", control, drag_data)))
	elif control.has_meta("hotbar_group_id"):
		_merge_dictionary(target, dictionary_or_empty(drag_hover_target_controller.call("hotbar_group_target", control, drag_data)))
	elif control.has_meta("inventory_action_target"):
		_merge_dictionary(target, dictionary_or_empty(drag_hover_target_controller.call("inventory_action_target", control, drag_data)))
	elif control.has_meta("container_source"):
		_merge_dictionary(target, dictionary_or_empty(drag_hover_target_controller.call("container_target", control, drag_data)))
	elif control.has_meta("trade_drop_zone"):
		_merge_dictionary(target, dictionary_or_empty(drag_hover_target_controller.call("trade_drop_zone_target", control, drag_data)))
	elif control.has_meta("cart_index"):
		_merge_dictionary(target, dictionary_or_empty(drag_hover_target_controller.call("trade_cart_target", control, drag_data, "trade_cart_entry", str(control.get_meta("cart_index")))))
	elif control.has_meta("trade_cart_target"):
		_merge_dictionary(target, dictionary_or_empty(drag_hover_target_controller.call("trade_cart_target", control, drag_data, "trade_cart", str(control.get_meta("trade_cart_target")))))
	else:
		var observe_key := observe_hotbar_meta_key(control)
		if not observe_key.is_empty():
			_merge_dictionary(target, dictionary_or_empty(drag_hover_target_controller.call("observe_hotbar_target", drag_data, observe_key)))
	return _enrich_drag_hover_target_reason(target)


func hotbar_hit_test_snapshot(viewport: Viewport, screen_position: Vector2 = Vector2(-1.0, -1.0)) -> Dictionary:
	var position := screen_position
	if (position.x < 0.0 or position.y < 0.0) and viewport != null:
		position = viewport.get_mouse_position()
	var inactive := {
		"active": false,
		"owner_panel": "hud",
		"target_kind": "",
		"target_id": "",
		"group_id": "",
		"source_path": "",
		"source_name": "",
		"mouse_blocks_world": false,
		"disabled": false,
		"tooltip": "",
		"screen_position": {"x": position.x, "y": position.y},
		"rect": {},
	}
	var hud: Control = panel("hud")
	if hud == null:
		return inactive
	var controls: Array[Control] = []
	for container_name in ["HotbarDock", "HotbarGroupBar", "ObserveHotbarDock"]:
		_collect_hotbar_hit_controls(hud.find_child(container_name, true, false) as Control, controls)
	for control in controls:
		if control == null or not control.is_inside_tree() or not control.is_visible_in_tree():
			continue
		if not control.get_global_rect().has_point(position):
			continue
		return _hotbar_hit_control_snapshot(control, position)
	return inactive


func observe_hotbar_meta_key(control: Control) -> String:
	if control == null:
		return ""
	for key in ["observe_playback", "observe_speed", "auto_tick", "observe_level", "observe_mode"]:
		if control.has_meta(key):
			return key
	return ""


func owner_panel_for_control(control: Control) -> String:
	var current: Node = control
	while current != null:
		match str(current.name):
			"Hud":
				return "hud"
			"HUD":
				return "hud"
			"InventoryPanel":
				return "inventory"
			"CharacterPanel":
				return "character"
			"SkillsPanel":
				return "skills"
			"JournalPanel":
				return "journal"
			"CraftingPanel":
				return "crafting"
			"TradePanel":
				return "trade"
			"ContainerPanel":
				return "container"
			"DialoguePanel":
				return "dialogue"
			"SettingsPanel":
				return "settings"
		current = current.get_parent()
	return ""


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


func clear_debug_console_history() -> Dictionary:
	var hud: Control = panel("hud")
	if hud == null or not hud.has_method("clear_debug_console_history"):
		return {"success": false, "reason": "hud_missing"}
	hud.call("clear_debug_console_history")
	return {"success": true}


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
	return bool(hide_interaction_menu().get("success", false))


func show_interaction_menu(screen_position: Vector2, prompt: Dictionary) -> Dictionary:
	var hud: Control = panel("hud")
	if hud == null or not hud.has_method("show_interaction_menu"):
		return {"success": false, "reason": "hud_missing", "visible": false}
	hud.show_interaction_menu(screen_position, prompt)
	return {"success": true, "visible": is_interaction_menu_open()}


func hide_interaction_menu() -> Dictionary:
	var hud: Control = panel("hud")
	if hud == null or not hud.has_method("hide_interaction_menu"):
		return {"success": false, "reason": "hud_missing", "visible": false}
	hud.hide_interaction_menu()
	return {"success": true, "visible": false}


func is_interaction_menu_open() -> bool:
	var hud: Control = panel("hud")
	return hud != null and hud.has_method("is_interaction_menu_open") and bool(hud.is_interaction_menu_open())


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


func close_active_context_menu() -> Dictionary:
	return dictionary_or_empty(ui_blocker_state_controller.call("close_active_context_menu", context_menu_snapshot(), context_menu_owner_panels()))


func context_menu_owner_panels() -> Dictionary:
	return {
		"inventory": panel("inventory"),
		"container": panel("container"),
		"trade": panel("trade"),
		"skills": panel("skills"),
		"character": panel("character"),
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


func play_ui_audio_feedback(event_kind: String, payload: Dictionary = {}) -> Dictionary:
	if parent != null and parent.has_method("play_ui_audio_feedback"):
		return dictionary_or_empty(parent.call("play_ui_audio_feedback", event_kind, payload))
	return {}


func submit_debug_console_command(command_text: String) -> Dictionary:
	return _forward_dictionary("submit_debug_console_command", [command_text])


func toggle_auto_tick() -> Dictionary:
	return _forward_dictionary("toggle_auto_tick")


func toggle_observe_mode() -> Dictionary:
	return _forward_dictionary("toggle_observe_mode")


func toggle_observe_playback() -> Dictionary:
	return _forward_dictionary("toggle_observe_playback")


func cycle_observe_speed() -> Dictionary:
	return _forward_dictionary("cycle_observe_speed")


func finish_world_action_presentations() -> Dictionary:
	return _forward_dictionary("finish_world_action_presentations")


func settings_applied(snapshot: Dictionary = {}) -> void:
	_forward_variant("settings_applied", [snapshot])


func execute_interaction_option(option_id: String) -> Dictionary:
	return _forward_dictionary("execute_interaction_option", [option_id])


func choose_dialogue_option(option_ref: Variant) -> Dictionary:
	return _forward_dictionary("choose_dialogue_option", [option_ref])


func store_active_container_item(item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	return _forward_dictionary("store_active_container_item", [item_id, count, stack_index])


func has_active_container_session() -> bool:
	return bool(_forward_variant("has_active_container_session"))


func drop_player_item(item_id: String, count: int = 1) -> Dictionary:
	return _forward_dictionary("drop_player_item", [item_id, count])


func deconstruct_player_item(item_id: String, count: int = 1) -> Dictionary:
	return _forward_dictionary("deconstruct_player_item", [item_id, count])


func split_player_inventory_stack(item_id: String, count: int = 1, source_stack_index: int = 0) -> Dictionary:
	return _forward_dictionary("split_player_inventory_stack", [item_id, count, source_stack_index])


func reorder_player_inventory_item(item_id: String, target_index: int) -> Dictionary:
	return _forward_dictionary("reorder_player_inventory_item", [item_id, target_index])


func use_player_item(item_id: String) -> Dictionary:
	return _forward_dictionary("use_player_item", [item_id])


func sell_active_trade_item(item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	return _forward_dictionary("sell_active_trade_item", [item_id, count, stack_index])


func has_active_trade_session() -> bool:
	return bool(_forward_variant("has_active_trade_session"))


func equip_player_item(item_id: String, slot_id: String) -> Dictionary:
	return _forward_dictionary("equip_player_item", [item_id, slot_id])


func unequip_player_slot(slot_id: String) -> Dictionary:
	return _forward_dictionary("unequip_player_slot", [slot_id])


func reload_player_equipped_slot(slot_id: String = "main_hand") -> Dictionary:
	return _forward_dictionary("reload_player_equipped_slot", [slot_id])


func allocate_player_attribute_point(attribute: String) -> Dictionary:
	return _forward_dictionary("allocate_player_attribute_point", [attribute])


func learn_player_skill(skill_id: String) -> Dictionary:
	return _forward_dictionary("learn_player_skill", [skill_id])


func bind_player_skill_to_hotbar(slot_id: String, skill_id: String) -> Dictionary:
	return _forward_dictionary("bind_player_skill_to_hotbar", [slot_id, skill_id])


func bind_player_item_to_hotbar(slot_id: String, item_id: String) -> Dictionary:
	return _forward_dictionary("bind_player_item_to_hotbar", [slot_id, item_id])


func set_hotbar_group(group_id: String) -> Dictionary:
	return _forward_dictionary("set_hotbar_group", [group_id])


func toggle_settings_panel() -> Dictionary:
	return _forward_dictionary("toggle_settings_panel")


func set_hotbar_group_label(group_id: String, label: String) -> Dictionary:
	return _forward_dictionary("set_hotbar_group_label", [group_id, label])


func use_hotbar_slot(slot_id: String) -> Dictionary:
	return _forward_dictionary("use_hotbar_slot", [slot_id])


func craft_player_recipe(recipe_id: String, count: int = 1) -> Dictionary:
	return _forward_dictionary("craft_player_recipe", [recipe_id, count])


func confirm_crafting_queue(entries: Array) -> Dictionary:
	return _forward_dictionary("confirm_crafting_queue", [entries])


func update_crafting_queue(entries: Array) -> Dictionary:
	return _forward_dictionary("update_crafting_queue", [entries])


func cancel_pending_crafting(reason: String = "crafting_ui") -> Dictionary:
	return _forward_dictionary("cancel_pending_crafting", [reason])


func turn_in_player_quest(quest_id: String) -> Dictionary:
	return _forward_dictionary("turn_in_player_quest", [quest_id])


func _forward_dictionary(method_name: String, args: Array = []) -> Dictionary:
	return dictionary_or_empty(_forward_variant(method_name, args))


func _forward_variant(method_name: String, args: Array = []) -> Variant:
	if parent == null or not parent.has_method(method_name):
		return {}
	return parent.callv(method_name, args)


func _collect_hotbar_hit_controls(control: Control, output: Array[Control]) -> void:
	if control == null:
		return
	if control.has_meta("hotbar_slot_id") or control.has_meta("hotbar_group_id") or observe_hotbar_meta_key(control) != "":
		output.append(control)
	for child in control.get_children():
		_collect_hotbar_hit_controls(child as Control, output)


func _hotbar_hit_control_snapshot(control: Control, position: Vector2) -> Dictionary:
	var target_kind := "control"
	var target_id := str(control.name)
	var group_id := ""
	if control.has_meta("hotbar_slot_id"):
		target_kind = "hotbar_slot"
		target_id = str(control.get_meta("hotbar_slot_id"))
		group_id = str(control.get_meta("hotbar_group_id", ""))
	elif control.has_meta("hotbar_group_id"):
		target_kind = "hotbar_group"
		target_id = str(control.get_meta("hotbar_group_id"))
		group_id = target_id
	else:
		var observe_key := observe_hotbar_meta_key(control)
		if not observe_key.is_empty():
			target_kind = "observe_hotbar"
			target_id = observe_key
	var rect := control.get_global_rect()
	var button := control as BaseButton
	var disabled_reason := str(control.get_meta("disabled_reason", ""))
	return {
		"active": true,
		"owner_panel": "hud",
		"target_kind": target_kind,
		"target_id": target_id,
		"group_id": group_id,
		"source_path": str(control.get_path()),
		"source_name": str(control.name),
		"mouse_blocks_world": control.mouse_filter == Control.MOUSE_FILTER_STOP,
		"disabled": button != null and button.disabled,
		"disabled_reason": disabled_reason,
		"disabled_reason_text": _hotbar_hit_disabled_reason_text(disabled_reason),
		"tooltip": str(control.tooltip_text),
		"screen_position": {"x": position.x, "y": position.y},
		"rect": {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y},
	}


func _hotbar_hit_disabled_reason_text(reason: String) -> String:
	if reason.is_empty():
		return ""
	var hud: Control = panel("hud")
	if hud != null and hud.has_method("_disabled_reason_text"):
		return str(hud.call("_disabled_reason_text", reason))
	return reason


func _enrich_drag_hover_target_reason(target: Dictionary) -> Dictionary:
	var reject_reason := str(target.get("reject_reason", ""))
	var reject_text := _drag_reject_reason_text(reject_reason)
	target["reject_reason_text"] = reject_text
	var highlight: Dictionary = dictionary_or_empty(target.get("hover_highlight", {})).duplicate(true)
	highlight["reject_reason_text"] = reject_text
	target["hover_highlight"] = highlight
	return target


func _drag_reject_reason_text(reason: String) -> String:
	if reason.is_empty():
		return ""
	return str(reason_catalog.call("disabled_text_for", reason))


func _merge_dictionary(target: Dictionary, values: Dictionary) -> void:
	for key in values:
		target[key] = values[key]


func _overlay_owner(owner: Node = null) -> Node:
	return owner if owner != null else parent


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
