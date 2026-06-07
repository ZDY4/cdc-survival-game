extends Control

const GAME_ROOT_SCENE := "res://scenes/game/game_root.tscn"
const DEFAULT_SAVE_SLOT := "default"
const DEFAULT_SAVE_ROOT := "user://saves"
const SaveService = preload("res://scripts/app/save_service.gd")
const UIThemeService = preload("res://scripts/ui/ui_theme_service.gd")

var save_slot := DEFAULT_SAVE_SLOT
var save_root := DEFAULT_SAVE_ROOT
var last_action: Dictionary = {}

var _slot_option: OptionButton
var _overwrite_dialog: ConfirmationDialog
var _delete_button: Button
var _continue_button: Button
var _slot_name_edit: LineEdit
var _rename_button: Button
var _slot_summary_label: Label
var _feedback_label: Label
var _slot_summaries: Array[Dictionary] = []
var _theme_result: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_theme_result = UIThemeService.apply_default_theme(self)
	save_slot = str(ProjectSettings.get_setting("cdc/main_menu_save_slot", DEFAULT_SAVE_SLOT))
	save_root = str(ProjectSettings.get_setting("cdc/save_root", DEFAULT_SAVE_ROOT))
	_build_layout()
	_refresh_save_slots()


func new_game() -> Dictionary:
	if _selected_slot_exists():
		return _open_overwrite_confirm()
	return _start_game({"mode": "new_game", "save_slot": save_slot})


func confirm_new_game_overwrite() -> Dictionary:
	if _overwrite_dialog != null:
		_overwrite_dialog.hide()
	return _start_game({"mode": "new_game", "save_slot": save_slot, "overwrite_slot": true})


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
	var display_name := _selected_slot_display_name()
	var deleted := SaveService.new(save_root).delete_snapshot(save_slot)
	last_action = {
		"ok": deleted,
		"action": "delete_slot",
		"save_slot": save_slot,
		"slot_display_name": display_name,
	}
	_set_feedback("已删除 %s" % display_name if deleted else "删除存档失败")
	_refresh_save_slots()
	return last_action.duplicate(true)


func rename_selected_slot() -> Dictionary:
	var summary := _selected_slot_summary()
	if summary.is_empty():
		last_action = {
			"ok": false,
			"action": "rename_slot",
			"reason": "selected_slot_missing",
			"save_slot": save_slot,
		}
		_set_feedback("没有可重命名的存档")
		_refresh_rename_state()
		return last_action.duplicate(true)
	var display_name := _slot_name_edit.text.strip_edges() if _slot_name_edit != null else ""
	var result: Dictionary = SaveService.new(save_root).rename_slot(save_slot, display_name)
	last_action = {
		"ok": bool(result.get("ok", false)),
		"action": "rename_slot",
		"save_slot": save_slot,
		"slot_display_name": str(result.get("slot_display_name", display_name)),
		"reason": str(result.get("reason", "")),
	}
	if bool(result.get("ok", false)):
		_set_feedback("已重命名为 %s" % str(result.get("slot_display_name", display_name)))
	else:
		_set_feedback(_rename_failure_text(str(result.get("reason", ""))))
	_refresh_save_slots()
	return last_action.duplicate(true)


func main_menu_snapshot() -> Dictionary:
	var service := SaveService.new(save_root)
	var load_result: Dictionary = service.load_snapshot(save_slot)
	var selected_summary := _selected_slot_summary()
	var selected_valid := bool(selected_summary.get("ok", false))
	return {
		"save_slot": save_slot,
		"save_root": save_root,
		"slots": _slot_summaries.duplicate(true),
		"continue_available": selected_valid and bool(load_result.get("ok", false)),
		"continue_reason": "" if selected_valid and bool(load_result.get("ok", false)) else str(selected_summary.get("reason", load_result.get("reason", ""))),
		"selected_slot_summary": selected_summary,
		"overwrite_confirm_visible": _overwrite_dialog != null and _overwrite_dialog.visible,
		"last_action": last_action.duplicate(true),
		"ui_theme": _theme_result.duplicate(true),
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
	var rename_row := HBoxContainer.new()
	rename_row.name = "SaveSlotRenameRow"
	rename_row.add_theme_constant_override("separation", 6)
	_slot_name_edit = LineEdit.new()
	_slot_name_edit.name = "SaveSlotNameEdit"
	_slot_name_edit.placeholder_text = "存档名称"
	_slot_name_edit.clear_button_enabled = true
	_slot_name_edit.custom_minimum_size = Vector2(190, 30)
	_slot_name_edit.text_submitted.connect(func(_text: String) -> void:
		rename_selected_slot()
	)
	_rename_button = Button.new()
	_rename_button.name = "RenameSlotButton"
	_rename_button.text = "重命名"
	_rename_button.custom_minimum_size = Vector2(78, 30)
	_rename_button.focus_mode = Control.FOCUS_NONE
	_rename_button.pressed.connect(rename_selected_slot)
	rename_row.add_child(_slot_name_edit)
	rename_row.add_child(_rename_button)
	box.add_child(rename_row)
	_slot_summary_label = Label.new()
	_slot_summary_label.name = "SaveSlotSummaryLine"
	_slot_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_slot_summary_label)
	_delete_button = _menu_button("DeleteSlotButton", "删除存档", delete_selected_slot)
	box.add_child(_delete_button)
	box.add_child(_menu_button("QuitButton", "退出", quit_game))

	_overwrite_dialog = ConfirmationDialog.new()
	_overwrite_dialog.name = "OverwriteConfirmDialog"
	_overwrite_dialog.title = "覆盖存档"
	_overwrite_dialog.dialog_text = "当前槽位已有存档。开始新游戏会覆盖该槽位。"
	_overwrite_dialog.confirmed.connect(confirm_new_game_overwrite)
	add_child(_overwrite_dialog)

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
	_refresh_rename_state()
	_refresh_slot_summary()


func _refresh_continue_state() -> void:
	if _continue_button == null:
		return
	var snapshot := main_menu_snapshot()
	var available := bool(snapshot.get("continue_available", false))
	_continue_button.disabled = not available
	var reason := str(snapshot.get("continue_reason", ""))
	_continue_button.tooltip_text = "加载 %s" % _selected_slot_display_name() if available else _save_failure_text(reason)
	if _delete_button != null:
		_delete_button.disabled = _selected_slot_summary().is_empty()
		_delete_button.tooltip_text = "删除 %s" % _selected_slot_display_name() if not _delete_button.disabled else "没有可删除的存档"
	_refresh_rename_state()


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
		var display_name := _slot_display_name(summary)
		var label := "%s | %s" % [display_name, str(summary.get("active_map_id", ""))]
		if not bool(summary.get("ok", false)):
			label = "%s | %s" % [display_name, _save_failure_text(str(summary.get("reason", "unknown")))]
		_slot_option.add_item(label)
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
	if not bool(summary.get("ok", false)):
		_slot_summary_label.text = "%s | 存档不可加载: %s" % [_slot_display_name(summary), _save_failure_text(str(summary.get("reason", "unknown")))]
		return
	var player: Dictionary = _dictionary_or_empty(summary.get("player", {}))
	_slot_summary_label.text = "%s | 地图 %s | 地点 %s | %s @ %s | Lv%d HP %s/%s AP %s | 回合 %d %s | 任务 %d/%d | %s | %s" % [
		_slot_display_name(summary),
		str(summary.get("active_map_id", "")),
		str(summary.get("active_location_id", "")),
		str(player.get("display_name", "玩家")),
		_grid_text(_dictionary_or_empty(player.get("grid_position", {}))),
		int(player.get("level", summary.get("player_level", 1))),
		_number_text(float(player.get("hp", 0.0))),
		_number_text(float(player.get("max_hp", 0.0))),
		_number_text(float(player.get("ap", 0.0))),
		int(summary.get("round", 0)),
		str(summary.get("turn_phase", "")),
		int(summary.get("active_quest_count", 0)),
		int(summary.get("completed_quest_count", 0)),
		"战斗中" if bool(summary.get("combat_active", false)) else "探索",
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
	_refresh_rename_state()
	_refresh_slot_summary()


func _selected_slot_summary() -> Dictionary:
	for summary in _slot_summaries:
		if str(summary.get("slot_id", "")) == save_slot:
			return summary.duplicate(true)
	return {}


func _selected_slot_exists() -> bool:
	return not _selected_slot_summary().is_empty()


func _open_overwrite_confirm() -> Dictionary:
	last_action = {
		"ok": false,
		"action": "new_game",
		"reason": "overwrite_confirmation_required",
		"save_slot": save_slot,
	}
	if _overwrite_dialog != null:
		_overwrite_dialog.dialog_text = "%s 已有存档。开始新游戏会覆盖该槽位。" % _selected_slot_display_name()
		_overwrite_dialog.popup_centered()
	_set_feedback("请确认是否覆盖当前存档")
	return last_action.duplicate(true)


func _selected_slot_display_name() -> String:
	return _slot_display_name(_selected_slot_summary())


func _slot_display_name(summary: Dictionary) -> String:
	var display_name := str(summary.get("slot_display_name", summary.get("display_name", ""))).strip_edges()
	if not display_name.is_empty():
		return display_name
	var slot_id := str(summary.get("slot_id", save_slot)).strip_edges()
	return "存档 %s" % slot_id if not slot_id.is_empty() else "存档"


func _refresh_rename_state() -> void:
	var summary := _selected_slot_summary()
	var has_slot := not summary.is_empty()
	if _slot_name_edit != null:
		_slot_name_edit.editable = has_slot
		_slot_name_edit.text = _slot_display_name(summary) if has_slot else ""
		_slot_name_edit.tooltip_text = "编辑当前存档槽显示名" if has_slot else "没有可重命名的存档"
	if _rename_button != null:
		_rename_button.disabled = not has_slot
		_rename_button.tooltip_text = "保存当前存档槽显示名" if has_slot else "没有可重命名的存档"


func _save_failure_text(reason: String) -> String:
	match reason:
		"save_file_missing":
			return "未找到可继续的存档"
		"save_file_unreadable":
			return "存档无法读取"
		"save_json_invalid":
			return "存档 JSON 损坏"
		"save_schema_unsupported":
			return "存档版本不兼容"
		"runtime_snapshot_missing":
			return "存档缺少运行时快照"
		"slot_id_empty":
			return "存档槽位无效"
		_:
			return "存档不可加载"


func _rename_failure_text(reason: String) -> String:
	match reason:
		"slot_display_name_empty":
			return "存档名称不能为空"
		"save_file_missing":
			return "未找到可重命名的存档"
		"save_file_unreadable":
			return "存档无法读取"
		"save_json_invalid":
			return "存档 JSON 损坏，无法重命名"
		"save_file_unwritable":
			return "存档无法写入"
		"slot_id_empty":
			return "存档槽位无效"
		_:
			return "重命名存档失败"


func _grid_text(grid_position: Dictionary) -> String:
	return "(%d,%d,%d)" % [
		int(grid_position.get("x", 0)),
		int(grid_position.get("y", 0)),
		int(grid_position.get("z", 0)),
	]


func _number_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value


func _set_feedback(text: String) -> void:
	if _feedback_label != null:
		_feedback_label.text = text


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
