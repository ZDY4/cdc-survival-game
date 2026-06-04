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

var parent: Node
var registry: RefCounted
var simulation: RefCounted
var world_result: Dictionary
var active_trade_target: Dictionary = {}
var active_trade_feedback: Dictionary = {}
var active_container_feedback: Dictionary = {}
var active_character_feedback: Dictionary = {}
var active_stage_panel: String = ""
var settings_open := false
var tracked_quest_id := ""

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
	skills_panel = _ensure_panel(skills_panel, SKILLS_PANEL_SCENE, "SkillsPanelRoot")
	crafting_panel = _ensure_panel(crafting_panel, CRAFTING_PANEL_SCENE, "CraftingPanelRoot")
	settings_panel = _ensure_settings_panel()
	_apply_stage_panel_visibility()
	_apply_settings_panel_visibility()


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
	snapshot["tracked_quest"] = _tracked_quest_snapshot()
	hud.apply_snapshot(snapshot)


func refresh_dialogue_panel() -> void:
	if dialogue_panel == null or simulation == null:
		return
	dialogue_panel.apply_snapshot(DialogueSnapshot.new(registry).build(simulation.snapshot()))


func refresh_inventory_panel() -> void:
	if inventory_panel == null or simulation == null:
		return
	inventory_panel.apply_snapshot(InventorySnapshot.new(registry).build(simulation.snapshot()))
	_apply_stage_panel_visibility()


func refresh_trade_panel() -> void:
	if trade_panel == null or simulation == null:
		return
	trade_panel.apply_snapshot(TradeSnapshot.new(registry).build(simulation.snapshot(), active_trade_target, active_trade_feedback))


func refresh_container_panel() -> void:
	if container_panel == null or simulation == null:
		return
	container_panel.apply_snapshot(ContainerSnapshot.new(registry).build(simulation.snapshot(), active_container_feedback))


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
	map_panel.apply_snapshot(MapSnapshot.new(registry).build(simulation.snapshot(), world_result))
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


func _crafting_context() -> Dictionary:
	return {
		"crafting_stations": _array_or_empty(_dictionary_or_empty(world_result.get("map", {})).get("crafting_stations", [])).duplicate(true),
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


func _connect_journal_tracking() -> void:
	if journal_panel == null or not journal_panel.has_signal("tracked_quest_changed"):
		return
	var callback := Callable(self, "_on_tracked_quest_changed")
	if not journal_panel.is_connected("tracked_quest_changed", callback):
		journal_panel.connect("tracked_quest_changed", callback)


func _on_tracked_quest_changed(quest_id: String) -> void:
	tracked_quest_id = quest_id
	refresh_hud()


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
	var root := Control.new()
	root.name = "SettingsPanelRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = false
	parent.add_child(root)

	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -360
	panel.offset_right = -16
	panel.offset_top = 284
	panel.offset_bottom = 508
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var box := VBoxContainer.new()
	box.name = "SettingsLines"
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var title := _settings_label("TitleLine", "设置")
	var audio := _settings_label("AudioLine", "音量: 主音量 100% | 音乐 100% | 音效 100%")
	var display := _settings_label("DisplayLine", "显示: 窗口模式 | VSync 开启 | UI 100%")
	var controls := _settings_label("ControlsLine", "按键: Esc 关闭 | I/C/M/J/K/L 面板 | Space 等待")
	box.add_child(title)
	box.add_child(audio)
	box.add_child(display)
	box.add_child(controls)
	return root


func _apply_stage_panel_visibility() -> void:
	for panel_id in _stage_panel_ids():
		var panel := _stage_panel(panel_id)
		if panel == null:
			continue
		var open := panel_id == active_stage_panel
		panel.visible = open
		panel.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE


func _apply_settings_panel_visibility() -> void:
	if settings_panel == null:
		return
	settings_panel.visible = settings_open
	settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP if settings_open else Control.MOUSE_FILTER_IGNORE
	var panel := settings_panel.get_node_or_null("SettingsPanel")
	if panel is Control:
		(panel as Control).mouse_filter = Control.MOUSE_FILTER_STOP if settings_open else Control.MOUSE_FILTER_IGNORE


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


func _panel_visible(panel: Control) -> bool:
	return panel != null and panel.visible


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
	return ""


func _settings_label(node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


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
