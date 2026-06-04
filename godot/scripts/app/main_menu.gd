extends Control

const GAME_ROOT_SCENE := "res://scenes/game/game_root.tscn"
const DEFAULT_SAVE_SLOT := "default"
const DEFAULT_SAVE_ROOT := "user://saves"
const SaveService = preload("res://scripts/app/save_service.gd")

var save_slot := DEFAULT_SAVE_SLOT
var save_root := DEFAULT_SAVE_ROOT
var last_action: Dictionary = {}

var _slot_option: OptionButton
var _delete_button: Button
var _continue_button: Button
var _slot_summary_label: Label
var _feedback_label: Label
var _slot_summaries: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	save_slot = str(ProjectSettings.get_setting("cdc/main_menu_save_slot", DEFAULT_SAVE_SLOT))
	save_root = str(ProjectSettings.get_setting("cdc/save_root", DEFAULT_SAVE_ROOT))
	_build_layout()
	_refresh_save_slots()


func new_game() -> Dictionary:
	return _start_game({"mode": "new_game", "save_slot": save_slot})


func continue_game() -> Dictionary:
	var load_result: Dictionary = SaveService.new(save_root).load_snapshot(save_slot)
	if not bool(load_result.get("ok", false)):
		last_action = {
			"ok": false,
			"action": "continue_game",
			"reason": str(load_result.get("reason", "load_failed")),
			"save_slot": save_slot,
		}
		_set_feedback("没有可继续的存档")
		_refresh_save_slots()
		return last_action.duplicate(true)
	return _start_game({
		"mode": "continue",
		"save_slot": save_slot,
		"runtime_snapshot": _dictionary_or_empty(load_result.get("runtime_snapshot", {})).duplicate(true),
	})


func quit_game() -> Dictionary:
	last_action = {"ok": true, "action": "quit_game"}
	get_tree().quit(0)
	return last_action.duplicate(true)


func delete_selected_slot() -> Dictionary:
	var deleted := SaveService.new(save_root).delete_snapshot(save_slot)
	last_action = {
		"ok": deleted,
		"action": "delete_slot",
		"save_slot": save_slot,
	}
	_set_feedback("已删除存档 %s" % save_slot if deleted else "删除存档失败")
	_refresh_save_slots()
	return last_action.duplicate(true)


func main_menu_snapshot() -> Dictionary:
	var service := SaveService.new(save_root)
	var load_result: Dictionary = service.load_snapshot(save_slot)
	return {
		"save_slot": save_slot,
		"save_root": save_root,
		"slots": _slot_summaries.duplicate(true),
		"continue_available": bool(load_result.get("ok", false)),
		"continue_reason": "" if bool(load_result.get("ok", false)) else str(load_result.get("reason", "")),
		"selected_slot_summary": _selected_slot_summary(),
		"last_action": last_action.duplicate(true),
	}


func _start_game(request: Dictionary) -> Dictionary:
	last_action = {
		"ok": true,
		"action": str(request.get("mode", "new_game")),
		"save_slot": str(request.get("save_slot", save_slot)),
	}
	ProjectSettings.set_setting("cdc/startup_request", request.duplicate(true))
	if bool(ProjectSettings.get_setting("cdc/main_menu_smoke_no_scene_change", false)):
		return last_action.duplicate(true)
	if get_tree().change_scene_to_file(GAME_ROOT_SCENE) != OK:
		last_action["ok"] = false
		last_action["reason"] = "scene_change_failed"
		_set_feedback("无法启动游戏")
		return last_action.duplicate(true)
	return last_action.duplicate(true)


func _build_layout() -> void:
	if get_node_or_null("MenuRoot") != null:
		return
	var menu_root := CenterContainer.new()
	menu_root.name = "MenuRoot"
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu_root)

	var panel := PanelContainer.new()
	panel.name = "MainMenuPanel"
	panel.custom_minimum_size = Vector2(420, 300)
	menu_root.add_child(panel)

	var box := VBoxContainer.new()
	box.name = "MainMenuBox"
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.name = "TitleLine"
	title.text = "CDC Survival Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "SubtitleLine"
	subtitle.text = "Godot 迁移版"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	box.add_child(_menu_button("NewGameButton", "新游戏", new_game))
	_continue_button = _menu_button("ContinueButton", "继续游戏", continue_game)
	box.add_child(_continue_button)
	_slot_option = OptionButton.new()
	_slot_option.name = "SaveSlotOption"
	_slot_option.focus_mode = Control.FOCUS_NONE
	_slot_option.item_selected.connect(_select_save_slot)
	box.add_child(_slot_option)
	_slot_summary_label = Label.new()
	_slot_summary_label.name = "SaveSlotSummaryLine"
	_slot_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_slot_summary_label)
	_delete_button = _menu_button("DeleteSlotButton", "删除存档", delete_selected_slot)
	box.add_child(_delete_button)
	box.add_child(_menu_button("QuitButton", "退出", quit_game))

	_feedback_label = Label.new()
	_feedback_label.name = "FeedbackLine"
	_feedback_label.text = ""
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_feedback_label)


func _menu_button(node_name: String, label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label
	button.custom_minimum_size = Vector2(260, 36)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button


func _refresh_save_slots() -> void:
	var service := SaveService.new(save_root)
	_slot_summaries = service.list_slots()
	if _slot_summaries.is_empty():
		save_slot = str(ProjectSettings.get_setting("cdc/main_menu_save_slot", DEFAULT_SAVE_SLOT))
	else:
		var has_current := false
		for summary in _slot_summaries:
			if str(summary.get("slot_id", "")) == save_slot:
				has_current = true
				break
		if not has_current:
			save_slot = str(_slot_summaries[0].get("slot_id", DEFAULT_SAVE_SLOT))
	ProjectSettings.set_setting("cdc/main_menu_save_slot", save_slot)
	_refresh_slot_option()
	_refresh_continue_state()
	_refresh_slot_summary()


func _refresh_continue_state() -> void:
	if _continue_button == null:
		return
	var snapshot := main_menu_snapshot()
	var available := bool(snapshot.get("continue_available", false))
	_continue_button.disabled = not available
	_continue_button.tooltip_text = "加载 %s" % save_slot if available else "未找到可继续的存档"
	if _delete_button != null:
		_delete_button.disabled = not available
		_delete_button.tooltip_text = "删除 %s" % save_slot if available else "没有可删除的存档"


func _refresh_slot_option() -> void:
	if _slot_option == null:
		return
	_slot_option.clear()
	if _slot_summaries.is_empty():
		_slot_option.add_item("无存档")
		_slot_option.set_item_metadata(0, "")
		_slot_option.disabled = true
		return
	_slot_option.disabled = false
	var selected_index := 0
	for i in range(_slot_summaries.size()):
		var summary := _slot_summaries[i]
		var slot_id := str(summary.get("slot_id", ""))
		_slot_option.add_item("%s | %s" % [slot_id, str(summary.get("active_map_id", ""))])
		_slot_option.set_item_metadata(i, slot_id)
		if slot_id == save_slot:
			selected_index = i
	_slot_option.select(selected_index)


func _refresh_slot_summary() -> void:
	if _slot_summary_label == null:
		return
	var summary := _selected_slot_summary()
	if summary.is_empty():
		_slot_summary_label.text = "没有可继续的存档"
		return
	_slot_summary_label.text = "地图 %s | 地点 %s | 回合 %d | Lv%d | %s" % [
		str(summary.get("active_map_id", "")),
		str(summary.get("active_location_id", "")),
		int(summary.get("round", 0)),
		int(summary.get("player_level", 1)),
		str(summary.get("updated_at", "")),
	]


func _select_save_slot(index: int) -> void:
	if _slot_option == null or index < 0 or index >= _slot_option.get_item_count():
		return
	var selected := str(_slot_option.get_item_metadata(index))
	if selected.is_empty():
		return
	save_slot = selected
	ProjectSettings.set_setting("cdc/main_menu_save_slot", save_slot)
	_refresh_continue_state()
	_refresh_slot_summary()


func _selected_slot_summary() -> Dictionary:
	for summary in _slot_summaries:
		if str(summary.get("slot_id", "")) == save_slot:
			return summary.duplicate(true)
	return {}


func _set_feedback(text: String) -> void:
	if _feedback_label != null:
		_feedback_label.text = text


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
