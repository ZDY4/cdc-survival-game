extends RefCounted

const HudSnapshot = preload("res://scripts/ui/snapshots/hud_snapshot.gd")
const DialogueSnapshot = preload("res://scripts/ui/snapshots/dialogue_snapshot.gd")
const InventorySnapshot = preload("res://scripts/ui/snapshots/inventory_snapshot.gd")
const TradeSnapshot = preload("res://scripts/ui/snapshots/trade_snapshot.gd")
const ContainerSnapshot = preload("res://scripts/ui/snapshots/container_snapshot.gd")
const CharacterSnapshot = preload("res://scripts/ui/snapshots/character_snapshot.gd")
const JournalSnapshot = preload("res://scripts/ui/snapshots/journal_snapshot.gd")
const MapSnapshot = preload("res://scripts/ui/snapshots/map_snapshot.gd")
const SkillsSnapshot = preload("res://scripts/ui/snapshots/skills_snapshot.gd")
const CraftingSnapshot = preload("res://scripts/ui/snapshots/crafting_snapshot.gd")
const UIThemeService = preload("res://scripts/ui/ui_theme_service.gd")
const HUD_SCENE = preload("res://scenes/ui/hud.tscn")
const DIALOGUE_PANEL_SCENE = preload("res://scenes/ui/dialogue_panel.tscn")
const INVENTORY_PANEL_SCENE = preload("res://scenes/ui/inventory_panel.tscn")
const TRADE_PANEL_SCENE = preload("res://scenes/ui/trade_panel.tscn")
const CONTAINER_PANEL_SCENE = preload("res://scenes/ui/container_panel.tscn")
const CHARACTER_PANEL_SCENE = preload("res://scenes/ui/character_panel.tscn")
const JOURNAL_PANEL_SCENE = preload("res://scenes/ui/journal_panel.tscn")
const MAP_PANEL_SCENE = preload("res://scenes/ui/map_panel.tscn")
const SKILLS_PANEL_SCENE = preload("res://scenes/ui/skills_panel.tscn")
const CRAFTING_PANEL_SCENE = preload("res://scenes/ui/crafting_panel.tscn")
const SettingsPanelController = preload("res://scripts/ui/controllers/settings_panel_controller.gd")

var parent: Node
var registry: RefCounted
var simulation: RefCounted
var world_result: Dictionary
var active_trade_target: Dictionary = {}
var active_trade_feedback: Dictionary = {}
var active_container_feedback: Dictionary = {}
var active_character_feedback: Dictionary = {}
var active_inventory_feedback: Dictionary = {}
var active_stage_panel: String = ""
var settings_open := false
var tracked_quest_id := ""
var panel_event_sequence := 0
var recent_panel_events: Array[Dictionary] = []
var ui_theme: Theme
var last_theme_result: Dictionary = {}
var _last_panel_visibility: Dictionary = {}

var hud: Control
var dialogue_panel: Control
var inventory_panel: Control
var trade_panel: Control
var container_panel: Control
var character_panel: Control
var journal_panel: Control
var map_panel: Control
var skills_panel: Control
var crafting_panel: Control
var settings_panel: Control


func _init(p_parent: Node, p_registry: RefCounted, p_simulation: RefCounted, p_world_result: Dictionary) -> void:
	parent = p_parent
	registry = p_registry
	simulation = p_simulation
	world_result = p_world_result


func setup_panels() -> void:
	hud = _ensure_panel(hud, HUD_SCENE, "Hud")
	dialogue_panel = _ensure_panel(dialogue_panel, DIALOGUE_PANEL_SCENE, "DialoguePanelRoot")
	inventory_panel = _ensure_panel(inventory_panel, INVENTORY_PANEL_SCENE, "InventoryPanelRoot")
	trade_panel = _ensure_panel(trade_panel, TRADE_PANEL_SCENE, "TradePanelRoot")
	container_panel = _ensure_panel(container_panel, CONTAINER_PANEL_SCENE, "ContainerPanelRoot")
	_connect_modal_close_buttons()
	character_panel = _ensure_panel(character_panel, CHARACTER_PANEL_SCENE, "CharacterPanelRoot")
	journal_panel = _ensure_panel(journal_panel, JOURNAL_PANEL_SCENE, "JournalPanelRoot")
	_connect_journal_tracking()
	map_panel = _ensure_panel(map_panel, MAP_PANEL_SCENE, "MapPanelRoot")
	_connect_map_panel()
	skills_panel = _ensure_panel(skills_panel, SKILLS_PANEL_SCENE, "SkillsPanelRoot")
	crafting_panel = _ensure_panel(crafting_panel, CRAFTING_PANEL_SCENE, "CraftingPanelRoot")
	settings_panel = _ensure_settings_panel()
	_apply_ui_theme()
	_apply_stage_panel_visibility()
	_apply_settings_panel_visibility()


func _apply_ui_theme() -> void:
	ui_theme = UIThemeService.build_default_theme()
	last_theme_result = UIThemeService.theme_snapshot(ui_theme)
	for panel in _theme_targets():
		if panel != null:
			panel.theme = ui_theme


func _theme_targets() -> Array[Control]:
	return [
		hud,
		dialogue_panel,
		inventory_panel,
		trade_panel,
		container_panel,
		character_panel,
		journal_panel,
		map_panel,
		skills_panel,
		crafting_panel,
		settings_panel,
	]


func refresh_all(selected_prompt: Dictionary = {}) -> void:
	refresh_hud(selected_prompt)
	refresh_dialogue_panel()
	refresh_inventory_panel()
	refresh_trade_panel()
	refresh_container_panel()
	refresh_character_panel()
	refresh_journal_panel()
	refresh_map_panel()
	refresh_skills_panel()
	refresh_crafting_panel()
	_apply_stage_panel_visibility()
	_apply_settings_panel_visibility()


func refresh_hud(selected_prompt: Dictionary = {}) -> void:
	if hud == null or simulation == null:
		return
	var snapshot: Dictionary = HudSnapshot.new(registry).build(simulation.snapshot(), world_result, selected_prompt)
	if parent != null and parent.has_method("current_debug_overlay_mode"):
		snapshot["debug_overlay_mode"] = parent.current_debug_overlay_mode()
	if parent != null and parent.has_method("info_panel_snapshot"):
		snapshot["info_panel"] = parent.info_panel_snapshot()
	if parent != null and parent.has_method("runtime_control_snapshot"):
		snapshot["runtime_control"] = parent.runtime_control_snapshot()
		_apply_runtime_attack_preview(snapshot)
	snapshot["tracked_quest"] = _tracked_quest_snapshot()
	hud.apply_snapshot(snapshot)


func refresh_dialogue_panel() -> void:
	if dialogue_panel == null or simulation == null:
		return
	dialogue_panel.apply_snapshot(DialogueSnapshot.new(registry).build(simulation.snapshot()))
	_record_panel_visibility_changes("refresh_dialogue")


func _apply_runtime_attack_preview(snapshot: Dictionary) -> void:
	var runtime_control: Dictionary = _dictionary_or_empty(snapshot.get("runtime_control", {}))
	var hover: Dictionary = _dictionary_or_empty(runtime_control.get("hover", {}))
	var attack_preview: Dictionary = _dictionary_or_empty(hover.get("attack_preview", {}))
	if attack_preview.is_empty():
		return
	var enriched_preview: Dictionary = attack_preview.duplicate(true)
	if int(enriched_preview.get("target_actor_id", 0)) <= 0 and int(hover.get("actor_id", 0)) > 0:
		enriched_preview["target_actor_id"] = int(hover.get("actor_id", 0))
	var target_actor_id := int(enriched_preview.get("target_actor_id", 0))
	var actor_name := _actor_display_name(target_actor_id)
	if not actor_name.is_empty():
		enriched_preview["target_name"] = actor_name
	elif not enriched_preview.has("target_name") or str(enriched_preview.get("target_name", "")).is_empty():
		enriched_preview["target_name"] = str(hover.get("target_name", ""))
	var combat_hud: Dictionary = _dictionary_or_empty(snapshot.get("combat_hud", {})).duplicate(true)
	combat_hud["target_preview"] = enriched_preview
	snapshot["combat_hud"] = combat_hud


func _actor_display_name(actor_id: int) -> String:
	if actor_id <= 0 or simulation == null:
		return ""
	for actor in _array_or_empty(simulation.snapshot().get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if int(actor_data.get("actor_id", 0)) == actor_id:
			return str(actor_data.get("display_name", ""))
	return ""


func refresh_inventory_panel() -> void:
	if inventory_panel == null or simulation == null:
		return
	inventory_panel.apply_snapshot(InventorySnapshot.new(registry).build(simulation.snapshot(), active_inventory_feedback, _crafting_context()))
	_apply_stage_panel_visibility()


func refresh_trade_panel() -> void:
	if trade_panel == null or simulation == null:
		return
	trade_panel.apply_snapshot(TradeSnapshot.new(registry).build(simulation.snapshot(), active_trade_target, active_trade_feedback))
	_record_panel_visibility_changes("refresh_trade")


func refresh_container_panel() -> void:
	if container_panel == null or simulation == null:
		return
	container_panel.apply_snapshot(ContainerSnapshot.new(registry).build(simulation.snapshot(), active_container_feedback))
	_record_panel_visibility_changes("refresh_container")


func refresh_character_panel() -> void:
	if character_panel == null or simulation == null:
		return
	character_panel.apply_snapshot(CharacterSnapshot.new(registry).build(simulation.snapshot(), active_character_feedback))
	_apply_stage_panel_visibility()


func refresh_journal_panel() -> void:
	if journal_panel == null or simulation == null:
		return
	var snapshot: Dictionary = JournalSnapshot.new(registry).build(simulation.snapshot())
	snapshot["tracked_quest_id"] = tracked_quest_id
	if not tracked_quest_id.is_empty() and _quest_summary_by_id(snapshot.get("quests", []), tracked_quest_id).is_empty():
		tracked_quest_id = ""
		snapshot["tracked_quest_id"] = tracked_quest_id
	journal_panel.apply_snapshot(snapshot)
	_apply_stage_panel_visibility()


func refresh_map_panel() -> void:
	if map_panel == null or simulation == null:
		return
	var tracked_quest: Dictionary = _tracked_quest_snapshot()
	var snapshot: Dictionary = MapSnapshot.new(registry).build(simulation.snapshot(), world_result, tracked_quest)
	snapshot["tracked_quest"] = tracked_quest
	map_panel.apply_snapshot(snapshot)
	_apply_stage_panel_visibility()


func refresh_skills_panel() -> void:
	if skills_panel == null or simulation == null:
		return
	skills_panel.apply_snapshot(SkillsSnapshot.new(registry).build(simulation.snapshot()))
	_apply_stage_panel_visibility()


func refresh_crafting_panel() -> void:
	if crafting_panel == null or simulation == null:
		return
	crafting_panel.apply_snapshot(CraftingSnapshot.new(registry).build(simulation.snapshot(), _crafting_context()))
	_apply_stage_panel_visibility()


func update_world_result(value: Dictionary) -> void:
	world_result = value


func update_runtime(p_simulation: RefCounted, p_world_result: Dictionary) -> void:
	simulation = p_simulation
	world_result = p_world_result


func _crafting_context() -> Dictionary:
	if parent != null and parent.has_method("_crafting_context"):
		return _dictionary_or_empty(parent.call("_crafting_context")).duplicate(true)
	return {
		"crafting_stations": _array_or_empty(_dictionary_or_empty(world_result.get("map", {})).get("crafting_stations", [])).duplicate(true),
		"world_flags": _dictionary_or_empty(simulation.world_flags if simulation != null else {}).duplicate(true),
	}


func toggle_stage_panel(panel_id: String) -> Dictionary:
	if not _stage_panel_ids().has(panel_id):
		return {"success": false, "reason": "unknown_stage_panel", "panel_id": panel_id}
	active_stage_panel = "" if active_stage_panel == panel_id else panel_id
	if not active_stage_panel.is_empty():
		settings_open = false
	_apply_stage_panel_visibility()
	_apply_settings_panel_visibility()
	return {
		"success": true,
		"panel_id": panel_id,
		"active_stage_panel": active_stage_panel,
		"open": active_stage_panel == panel_id,
	}


func open_stage_panel(panel_id: String) -> Dictionary:
	if not _stage_panel_ids().has(panel_id):
		return {"success": false, "reason": "unknown_stage_panel", "panel_id": panel_id}
	active_stage_panel = panel_id
	settings_open = false
	_apply_stage_panel_visibility()
	_apply_settings_panel_visibility()
	return {
		"success": true,
		"panel_id": panel_id,
		"active_stage_panel": active_stage_panel,
		"open": true,
	}


func close_stage_panels() -> Dictionary:
	var had_panel := not active_stage_panel.is_empty()
	active_stage_panel = ""
	_apply_stage_panel_visibility()
	return {
		"success": true,
		"closed": had_panel,
		"active_stage_panel": active_stage_panel,
	}


func any_stage_panel_open() -> bool:
	return not active_stage_panel.is_empty()


func gameplay_input_blocked() -> bool:
	return _blocking_modal_open() or any_stage_panel_open() or settings_open or _panel_visible(trade_panel) or _panel_visible(container_panel) or _panel_visible(dialogue_panel)


func menu_state_snapshot() -> Dictionary:
	var stage_ids := _stage_panel_ids()
	var stage_states: Array[Dictionary] = []
	for panel_id in stage_ids:
		var panel := _stage_panel(panel_id)
		var content := _stage_panel_content(panel_id, panel)
		stage_states.append({
			"id": panel_id,
			"visible": panel != null and panel.visible,
			"active": panel_id == active_stage_panel,
			"mouse_blocks_world": panel != null and panel.mouse_filter == Control.MOUSE_FILTER_STOP,
			"content_mouse_blocks_world": content != null and content.mouse_filter == Control.MOUSE_FILTER_STOP,
		})
	var open_panels: Array[String] = []
	if not active_stage_panel.is_empty():
		open_panels.append("stage:%s" % active_stage_panel)
	if settings_open:
		open_panels.append("settings")
	if _panel_visible(dialogue_panel):
		open_panels.append("dialogue")
	if _panel_visible(trade_panel):
		open_panels.append("trade")
	if _panel_visible(container_panel):
		open_panels.append("container")
	var blocker := gameplay_input_blocker_snapshot()
	return {
		"active_stage_panel": active_stage_panel,
		"stage_panel_open": any_stage_panel_open(),
		"stage_panels": stage_states,
		"stage_panel_ids": stage_ids,
		"settings_open": settings_open,
		"open_panels": open_panels,
		"open_panel_count": open_panels.size(),
		"gameplay_blocked": gameplay_input_blocked(),
		"blocker": blocker,
		"close_priority": _menu_close_priority(),
		"recent_events": recent_panel_events.duplicate(true),
		"recent_event_count": recent_panel_events.size(),
		"latest_event": recent_panel_events[recent_panel_events.size() - 1].duplicate(true) if not recent_panel_events.is_empty() else {},
	}


func ui_theme_snapshot() -> Dictionary:
	if ui_theme == null:
		return {"applied": false, "reason": "theme_missing"}
	var snapshot := UIThemeService.theme_snapshot(ui_theme)
	snapshot["panel_count"] = _theme_targets().size()
	snapshot["last_apply"] = last_theme_result.duplicate(true)
	return snapshot


func gameplay_input_blocker_snapshot() -> Dictionary:
	var name := gameplay_input_blocker_name()
	if name.is_empty():
		return {
			"blocked": false,
			"name": "",
			"kind": "",
			"modal_id": "",
			"panel_id": "",
			"mouse_blocks_world": false,
		}
	var modal_name := _blocking_modal_name()
	if not modal_name.is_empty():
		var modal: Dictionary = _blocking_modal_snapshot()
		return {
			"blocked": true,
			"name": "modal:%s" % modal_name,
			"kind": "modal",
			"modal_id": modal_name,
			"panel_id": str(modal.get("owner_panel", _modal_owner_panel_id(modal_name))),
			"mouse_blocks_world": bool(modal.get("mouse_blocks_world", true)),
			"modal": modal,
		}
	if any_stage_panel_open():
		return _panel_blocker_snapshot("stage:%s" % active_stage_panel, "stage", active_stage_panel, _stage_panel(active_stage_panel))
	if settings_open:
		return _panel_blocker_snapshot("settings", "settings", "settings", settings_panel)
	if _panel_visible(trade_panel):
		return _panel_blocker_snapshot("trade", "panel", "trade", trade_panel)
	if _panel_visible(container_panel):
		return _panel_blocker_snapshot("container", "panel", "container", container_panel)
	if _panel_visible(dialogue_panel):
		return _panel_blocker_snapshot("dialogue", "panel", "dialogue", dialogue_panel)
	return {
		"blocked": false,
		"name": "",
		"kind": "",
		"modal_id": "",
		"panel_id": "",
		"mouse_blocks_world": false,
	}


func modal_stack_snapshot() -> Dictionary:
	var stack: Array[Dictionary] = []
	var modal := _blocking_modal_snapshot()
	if not modal.is_empty():
		stack.append(modal)
	return {
		"active": not stack.is_empty(),
		"count": stack.size(),
		"top": stack[stack.size() - 1].duplicate(true) if not stack.is_empty() else {},
		"stack": stack,
	}


func gameplay_input_blocker_name() -> String:
	var modal_name := _blocking_modal_name()
	if not modal_name.is_empty():
		return "modal:%s" % modal_name
	if any_stage_panel_open():
		return "stage:%s" % active_stage_panel
	if settings_open:
		return "settings"
	if _panel_visible(trade_panel):
		return "trade"
	if _panel_visible(container_panel):
		return "container"
	if _panel_visible(dialogue_panel):
		return "dialogue"
	return ""


func handle_trade_shortcut(event: InputEventKey) -> bool:
	if trade_panel == null or not _panel_visible(trade_panel):
		return false
	if trade_panel.has_method("handle_shortcut_key"):
		return bool(trade_panel.call("handle_shortcut_key", event))
	return false


func open_settings_panel() -> Dictionary:
	active_stage_panel = ""
	settings_open = true
	_apply_stage_panel_visibility()
	_apply_settings_panel_visibility()
	return {"success": true, "open": true, "panel_id": "settings"}


func close_settings_panel() -> Dictionary:
	var was_open := settings_open
	settings_open = false
	_apply_settings_panel_visibility()
	return {"success": true, "closed": was_open, "panel_id": "settings"}


func is_settings_open() -> bool:
	return settings_open


func close_trade_panel() -> void:
	active_trade_target = {}
	refresh_trade_panel()


func close_blocking_modal() -> Dictionary:
	if inventory_panel != null and inventory_panel.has_method("close_blocking_modal"):
		var inventory_result: Dictionary = inventory_panel.call("close_blocking_modal")
		if bool(inventory_result.get("success", false)):
			return inventory_result
	if trade_panel != null and trade_panel.has_method("close_blocking_modal"):
		var result: Dictionary = trade_panel.call("close_blocking_modal")
		if bool(result.get("success", false)):
			return result
	if container_panel != null and container_panel.has_method("close_blocking_modal"):
		var container_result: Dictionary = container_panel.call("close_blocking_modal")
		if bool(container_result.get("success", false)):
			return container_result
	if map_panel != null and map_panel.has_method("close_blocking_modal"):
		var map_result: Dictionary = map_panel.call("close_blocking_modal")
		if bool(map_result.get("success", false)):
			return map_result
	if skills_panel != null and skills_panel.has_method("close_blocking_modal"):
		var skills_result: Dictionary = skills_panel.call("close_blocking_modal")
		if bool(skills_result.get("success", false)):
			return skills_result
	return {"success": false, "reason": "modal_inactive"}


func _connect_modal_close_buttons() -> void:
	if trade_panel != null and trade_panel.has_signal("close_requested"):
		var trade_close := Callable(parent, "close_trade_panel").bind("button")
		if not trade_panel.is_connected("close_requested", trade_close):
			trade_panel.connect("close_requested", trade_close)
	if trade_panel != null and trade_panel.has_signal("trade_requested"):
		var trade_transfer := Callable(parent, "transfer_active_trade_item")
		if not trade_panel.is_connected("trade_requested", trade_transfer):
			trade_panel.connect("trade_requested", trade_transfer)
	if trade_panel != null and trade_panel.has_signal("trade_cart_confirmed"):
		var trade_cart_confirmed := Callable(parent, "confirm_active_trade_cart")
		if not trade_panel.is_connected("trade_cart_confirmed", trade_cart_confirmed):
			trade_panel.connect("trade_cart_confirmed", trade_cart_confirmed)
	if container_panel != null and container_panel.has_signal("close_requested"):
		var container_close := Callable(parent, "close_active_container").bind("button")
		if not container_panel.is_connected("close_requested", container_close):
			container_panel.connect("close_requested", container_close)
	if container_panel != null and container_panel.has_signal("transfer_requested"):
		var container_transfer := Callable(parent, "transfer_active_container_item")
		if not container_panel.is_connected("transfer_requested", container_transfer):
			container_panel.connect("transfer_requested", container_transfer)
	if container_panel != null and container_panel.has_signal("transfer_all_requested"):
		var container_transfer_all := Callable(parent, "transfer_all_active_container_items")
		if not container_panel.is_connected("transfer_all_requested", container_transfer_all):
			container_panel.connect("transfer_all_requested", container_transfer_all)
	if dialogue_panel != null and dialogue_panel.has_signal("close_requested"):
		var dialogue_close := Callable(parent, "close_active_dialogue").bind("button")
		if not dialogue_panel.is_connected("close_requested", dialogue_close):
			dialogue_panel.connect("close_requested", dialogue_close)


func _connect_journal_tracking() -> void:
	if journal_panel == null or not journal_panel.has_signal("tracked_quest_changed"):
		return
	var callback := Callable(self, "_on_tracked_quest_changed")
	if not journal_panel.is_connected("tracked_quest_changed", callback):
		journal_panel.connect("tracked_quest_changed", callback)


func _connect_map_panel() -> void:
	if map_panel == null or not map_panel.has_signal("overworld_location_requested"):
		return
	var callback := Callable(parent, "enter_overworld_location_from_panel")
	if not map_panel.is_connected("overworld_location_requested", callback):
		map_panel.connect("overworld_location_requested", callback)


func _on_tracked_quest_changed(quest_id: String) -> void:
	tracked_quest_id = quest_id
	refresh_hud()
	refresh_map_panel()


func _ensure_panel(current: Control, scene: PackedScene, node_name: String) -> Control:
	if current != null:
		return current
	var panel: Control = scene.instantiate()
	panel.name = node_name
	parent.add_child(panel)
	return panel


func _ensure_settings_panel() -> Control:
	if settings_panel != null:
		return settings_panel
	var root: Control = SettingsPanelController.new()
	root.name = "SettingsPanelRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = false
	parent.add_child(root)
	settings_panel = root
	return root


func settings_snapshot() -> Dictionary:
	if settings_panel != null and settings_panel.has_method("settings_snapshot"):
		return _dictionary_or_empty(settings_panel.call("settings_snapshot")).duplicate(true)
	return {}


func _apply_stage_panel_visibility() -> void:
	for panel_id in _stage_panel_ids():
		var panel := _stage_panel(panel_id)
		if panel == null:
			continue
		var open := panel_id == active_stage_panel
		panel.visible = open
		panel.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
		_apply_stage_panel_content_mouse_filter(panel_id, panel, open)
	_record_panel_visibility_changes("stage_visibility")


func _apply_settings_panel_visibility() -> void:
	if settings_panel == null:
		return
	settings_panel.visible = settings_open
	settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP if settings_open else Control.MOUSE_FILTER_IGNORE
	var panel := settings_panel.get_node_or_null("SettingsPanel")
	if panel is Control:
		(panel as Control).mouse_filter = Control.MOUSE_FILTER_STOP if settings_open else Control.MOUSE_FILTER_IGNORE
	_record_panel_visibility_changes("settings_visibility")


func _stage_panel_ids() -> Array[String]:
	return ["inventory", "character", "journal", "map", "skills", "crafting"]


func _stage_panel(panel_id: String) -> Control:
	match panel_id:
		"inventory":
			return inventory_panel
		"character":
			return character_panel
		"journal":
			return journal_panel
		"map":
			return map_panel
		"skills":
			return skills_panel
		"crafting":
			return crafting_panel
		_:
			return null


func _apply_stage_panel_content_mouse_filter(panel_id: String, panel: Control, open: bool) -> void:
	var content := _stage_panel_content(panel_id, panel)
	if content == null:
		return
	content.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE


func _stage_panel_content(panel_id: String, panel: Control) -> Control:
	if panel == null:
		return null
	var node_name := "%sPanel" % panel_id.capitalize()
	return panel.find_child(node_name, true, false) as Control


func _panel_visible(panel: Control) -> bool:
	return panel != null and panel.visible


func _record_panel_visibility_changes(reason: String = "") -> void:
	for panel in _panel_event_controls():
		var panel_id := str(panel.get("id", ""))
		if panel_id.is_empty():
			continue
		var control: Control = panel.get("control", null)
		var visible := _panel_visible(control)
		var previous: Variant = _last_panel_visibility.get(panel_id, null)
		_last_panel_visibility[panel_id] = visible
		if previous == null or bool(previous) == visible:
			continue
		_record_panel_event("opened" if visible else "closed", panel_id, str(panel.get("kind", "")), visible, reason)


func _record_panel_event(event: String, panel_id: String, kind: String, visible: bool, reason: String = "") -> void:
	panel_event_sequence += 1
	var entry := {
		"sequence": panel_event_sequence,
		"event": event,
		"panel_id": panel_id,
		"kind": kind,
		"visible": visible,
		"reason": reason,
	}
	recent_panel_events.append(entry)
	while recent_panel_events.size() > 8:
		recent_panel_events.pop_front()


func _panel_event_controls() -> Array[Dictionary]:
	return [
		{"id": "inventory", "kind": "stage", "control": inventory_panel},
		{"id": "character", "kind": "stage", "control": character_panel},
		{"id": "journal", "kind": "stage", "control": journal_panel},
		{"id": "map", "kind": "stage", "control": map_panel},
		{"id": "skills", "kind": "stage", "control": skills_panel},
		{"id": "crafting", "kind": "stage", "control": crafting_panel},
		{"id": "settings", "kind": "settings", "control": settings_panel},
		{"id": "dialogue", "kind": "panel", "control": dialogue_panel},
		{"id": "trade", "kind": "panel", "control": trade_panel},
		{"id": "container", "kind": "panel", "control": container_panel},
	]


func _blocking_modal_open() -> bool:
	return not _blocking_modal_name().is_empty()


func _blocking_modal_name() -> String:
	if inventory_panel != null and inventory_panel.has_method("blocking_modal_name"):
		var inventory_modal := str(inventory_panel.call("blocking_modal_name"))
		if not inventory_modal.is_empty():
			return inventory_modal
	if trade_panel != null and trade_panel.has_method("blocking_modal_name"):
		var trade_modal := str(trade_panel.call("blocking_modal_name"))
		if not trade_modal.is_empty():
			return trade_modal
	if container_panel != null and container_panel.has_method("blocking_modal_name"):
		var container_modal := str(container_panel.call("blocking_modal_name"))
		if not container_modal.is_empty():
			return container_modal
	if map_panel != null and map_panel.has_method("blocking_modal_name"):
		var map_modal := str(map_panel.call("blocking_modal_name"))
		if not map_modal.is_empty():
			return map_modal
	if skills_panel != null and skills_panel.has_method("blocking_modal_name"):
		var skills_modal := str(skills_panel.call("blocking_modal_name"))
		if not skills_modal.is_empty():
			return skills_modal
	return ""


func _blocking_modal_snapshot() -> Dictionary:
	for panel in [inventory_panel, trade_panel, container_panel, map_panel, skills_panel]:
		if panel != null and panel.has_method("blocking_modal_snapshot"):
			var snapshot: Dictionary = _dictionary_or_empty(panel.call("blocking_modal_snapshot"))
			if not snapshot.is_empty():
				return snapshot
	var modal_name := _blocking_modal_name()
	if modal_name.is_empty():
		return {}
	return {
		"id": modal_name,
		"name": "modal:%s" % modal_name,
		"kind": "modal",
		"owner_panel": _modal_owner_panel_id(modal_name),
		"blocks_gameplay": true,
		"mouse_blocks_world": true,
	}


func _menu_close_priority() -> Array[String]:
	var priority: Array[String] = []
	if _blocking_modal_open():
		priority.append("modal:%s" % _blocking_modal_name())
	if any_stage_panel_open():
		priority.append("stage:%s" % active_stage_panel)
	if settings_open:
		priority.append("settings")
	if _panel_visible(trade_panel):
		priority.append("trade")
	if _panel_visible(container_panel):
		priority.append("container")
	if _panel_visible(dialogue_panel):
		priority.append("dialogue")
	if priority.is_empty():
		priority.append("settings")
	return priority


func _panel_blocker_snapshot(name: String, kind: String, panel_id: String, panel: Control) -> Dictionary:
	var content := _panel_content(panel_id, panel)
	return {
		"blocked": true,
		"name": name,
		"kind": kind,
		"modal_id": "",
		"panel_id": panel_id,
		"mouse_blocks_world": panel != null and panel.mouse_filter == Control.MOUSE_FILTER_STOP,
		"content_mouse_blocks_world": content != null and content.mouse_filter == Control.MOUSE_FILTER_STOP,
		"visible": panel != null and panel.visible,
	}


func _panel_content(panel_id: String, panel: Control) -> Control:
	if panel == null:
		return null
	match panel_id:
		"inventory", "character", "journal", "map", "skills", "crafting":
			return _stage_panel_content(panel_id, panel)
		"settings":
			return panel.find_child("SettingsPanel", true, false) as Control
		"dialogue":
			return panel.find_child("DialoguePanel", true, false) as Control
		"trade":
			return panel.find_child("TradePanel", true, false) as Control
		"container":
			return panel.find_child("ContainerPanel", true, false) as Control
		_:
			return null


func _modal_owner_panel_id(modal_name: String) -> String:
	if modal_name.begins_with("inventory_"):
		return "inventory"
	if modal_name.begins_with("equipment_") or modal_name.begins_with("trade_"):
		return "trade"
	if modal_name.begins_with("skill_"):
		return "skills"
	return ""


func _tracked_quest_snapshot() -> Dictionary:
	if tracked_quest_id.is_empty():
		return {"active": false, "quest_id": ""}
	var journal_snapshot: Dictionary = JournalSnapshot.new(registry).build(simulation.snapshot())
	var quest: Dictionary = _quest_summary_by_id(journal_snapshot.get("quests", []), tracked_quest_id)
	if quest.is_empty():
		tracked_quest_id = ""
		return {"active": false, "quest_id": ""}
	return {
		"active": true,
		"quest_id": tracked_quest_id,
		"title": str(quest.get("title", tracked_quest_id)),
		"objective_text": str(quest.get("objective_text", "")),
		"objective": _dictionary_or_empty(quest.get("objective", {})).duplicate(true),
		"objective_id": str(quest.get("objective_id", "")),
		"objective_type": str(quest.get("objective_type", "")),
		"progress_current": int(quest.get("progress_current", 0)),
		"progress_target": int(quest.get("progress_target", 0)),
		"status_text": str(quest.get("status_text", "")),
	}


func _quest_summary_by_id(quests: Array, quest_id: String) -> Dictionary:
	for quest in quests:
		var quest_data: Dictionary = _dictionary_or_empty(quest)
		if str(quest_data.get("quest_id", "")) == quest_id:
			return quest_data
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
