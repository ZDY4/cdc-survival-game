extends SceneTree

const MAIN_MENU_SCENE = preload("res://scenes/boot/main_menu.tscn")
const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const SaveService = preload("res://scripts/app/save_service.gd")

const SAVE_ROOT := "user://main_menu_smoke_saves"
const SAVE_SLOT := "continue_slot"
const SECOND_SAVE_SLOT := "older_slot"
const BROKEN_SCHEMA_SLOT := "broken_schema_slot"
const BROKEN_JSON_SLOT := "broken_json_slot"
const MISSING_RUNTIME_SLOT := "missing_runtime_slot"
const SECOND_SAVE_NAME := "旧营地存档"
const RENAMED_SAVE_NAME := "重命名后的继续存档"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	ProjectSettings.set_setting("cdc/save_root", SAVE_ROOT)
	ProjectSettings.set_setting("cdc/main_menu_save_slot", SAVE_SLOT)
	ProjectSettings.set_setting("cdc/startup_request", {})
	ProjectSettings.set_setting("cdc/main_menu_smoke_no_scene_change", true)
	_clear_smoke_save()

	var errors: Array[String] = []
	var menu: Control = MAIN_MENU_SCENE.instantiate()
	get_root().add_child(menu)
	await process_frame
	_assert_empty_menu_runtime(errors, menu)
	_assert_main_menu_theme(errors, menu)
	_assert_continue_disabled_without_save(errors, menu)
	_assert_new_game_request(errors, menu)
	menu.queue_free()
	await process_frame

	_write_continue_save(errors, SECOND_SAVE_SLOT, 2, SECOND_SAVE_NAME)
	_write_continue_save(errors, SAVE_SLOT, 1)
	_write_broken_schema_save()
	_write_broken_json_save()
	_write_missing_runtime_save()
	var continue_menu: Control = MAIN_MENU_SCENE.instantiate()
	get_root().add_child(continue_menu)
	await process_frame
	_assert_continue_enabled_with_save(errors, continue_menu)
	_assert_slot_metadata(errors, continue_menu)
	await _assert_slot_rename(errors, continue_menu, SAVE_SLOT, RENAMED_SAVE_NAME)
	await _assert_broken_slot_feedback(errors, continue_menu, BROKEN_SCHEMA_SLOT, "save_schema_unsupported", "schema", "损坏测试存档", "存档版本不兼容")
	await _assert_broken_slot_feedback(errors, continue_menu, BROKEN_JSON_SLOT, "save_json_invalid", "json", "存档 broken_json_slot", "存档 JSON 损坏")
	await _assert_broken_slot_feedback(errors, continue_menu, MISSING_RUNTIME_SLOT, "runtime_snapshot_missing", "snapshot", "缺快照测试存档", "存档缺少运行时快照")
	await _select_slot(errors, continue_menu, SAVE_SLOT)
	_assert_new_game_overwrite_confirmation(errors, continue_menu)
	await _select_slot(errors, continue_menu, SECOND_SAVE_SLOT)
	_assert_continue_request(errors, continue_menu)
	continue_menu.queue_free()
	await process_frame

	var game_root: Node = GAME_ROOT_SCENE.instantiate()
	get_root().add_child(game_root)
	await process_frame
	_assert_game_root_loaded_continue_snapshot(errors, game_root, 26)
	game_root.queue_free()
	await process_frame

	var delete_menu: Control = MAIN_MENU_SCENE.instantiate()
	get_root().add_child(delete_menu)
	await process_frame
	await _select_slot(errors, delete_menu, SAVE_SLOT)
	_assert_delete_slot(errors, delete_menu, SAVE_SLOT)
	delete_menu.queue_free()
	await process_frame

	_clear_smoke_save()
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return
	print("main_menu_smoke passed:")
	print(JSON.stringify({
		"save_root": SAVE_ROOT,
		"save_slot": SAVE_SLOT,
		"active_map_id": "survivor_outpost_01",
		"loaded_from_continue": true,
	}, "\t"))
	quit(0)


func _assert_empty_menu_runtime(errors: Array[String], menu: Control) -> void:
	if menu.find_child("GameRoot", true, false) != null:
		errors.append("main menu should not instantiate game root before starting")
	if menu.find_child("WorldContainer", true, false) != null:
		errors.append("main menu should not render map/world before starting")


func _assert_main_menu_theme(errors: Array[String], menu: Control) -> void:
	var snapshot: Dictionary = _dictionary_or_empty(menu.call("main_menu_snapshot"))
	var theme: Dictionary = _dictionary_or_empty(snapshot.get("ui_theme", {}))
	if not bool(theme.get("applied", false)):
		errors.append("main menu should apply UI theme: %s" % theme)
	if str(theme.get("font_resource_path", "")) != "res://assets/fonts/NotoSansCJKsc-Regular.otf":
		errors.append("main menu should use NotoSans CJK font: %s" % theme)
	if str(theme.get("theme_resource_path", "")) != "res://assets/themes/default_ui_theme.tres" or not bool(theme.get("theme_resource_loaded", false)):
		errors.append("main menu should load Godot theme resource: %s" % theme)
	_assert_main_menu_theme_standards(errors, theme)
	if menu.theme == null or menu.theme.default_font == null or menu.theme.default_font.resource_path != "res://assets/fonts/NotoSansCJKsc-Regular.otf":
		errors.append("main menu root should expose NotoSans CJK theme")


func _assert_main_menu_theme_standards(errors: Array[String], theme: Dictionary) -> void:
	var font_sizes: Dictionary = _dictionary_or_empty(theme.get("control_font_sizes", {}))
	if int(font_sizes.get("Label", 0)) != 14 or int(font_sizes.get("Button", 0)) != 14:
		errors.append("main menu theme should standardize base control font sizes: %s" % theme)
	var constants: Dictionary = _dictionary_or_empty(theme.get("layout_constants", {}))
	if int(constants.get("button_minimum_height", 0)) != 30:
		errors.append("main menu theme should standardize button minimum height: %s" % theme)
	var button_styles: Dictionary = _dictionary_or_empty(theme.get("button_state_styles", {}))
	var states: Dictionary = _dictionary_or_empty(button_styles.get("states", {}))
	if not bool(states.get("normal", false)) or not bool(states.get("disabled", false)) or not bool(button_styles.get("font_disabled_color", false)):
		errors.append("main menu theme should define button normal/disabled states: %s" % theme)


func _assert_continue_disabled_without_save(errors: Array[String], menu: Control) -> void:
	var snapshot: Dictionary = _dictionary_or_empty(menu.call("main_menu_snapshot"))
	if bool(snapshot.get("continue_available", false)):
		errors.append("continue should be unavailable without a save: %s" % snapshot)
	var button: Button = menu.find_child("ContinueButton", true, false) as Button
	if button == null or not button.disabled:
		errors.append("continue button should be disabled when save is missing")


func _assert_new_game_request(errors: Array[String], menu: Control) -> void:
	var result: Dictionary = _dictionary_or_empty(menu.call("new_game"))
	var request: Dictionary = _dictionary_or_empty(ProjectSettings.get_setting("cdc/startup_request", {}))
	if not bool(result.get("ok", false)) or str(result.get("action", "")) != "new_game":
		errors.append("new game should report successful start request: %s" % result)
	if str(request.get("mode", "")) != "new_game":
		errors.append("new game should set startup request mode: %s" % request)
	ProjectSettings.set_setting("cdc/startup_request", {})


func _write_continue_save(errors: Array[String], slot_id: String, player_x_offset: int, display_name: String = "") -> void:
	var registry: ContentRegistry = ContentRegistry.new()
	var load_result: RefCounted = registry.load_all()
	if load_result.has_errors():
		errors.append("content load failed before writing menu smoke save")
		return
	var runtime_result: Dictionary = CoreRuntimeBootstrap.new(registry).build_new_game_runtime()
	var simulation: RefCounted = runtime_result.get("simulation")
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	if player != null:
		player.grid_position.x += player_x_offset
	var metadata_overrides := {}
	if not display_name.is_empty():
		metadata_overrides["slot_display_name"] = display_name
	var saved := SaveService.new(SAVE_ROOT).save_snapshot(slot_id, simulation.snapshot(), metadata_overrides)
	if not saved:
		errors.append("failed to write %s save for main menu smoke" % slot_id)


func _write_broken_schema_save() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_ROOT))
	var file := FileAccess.open(SAVE_ROOT.path_join("%s.json" % BROKEN_SCHEMA_SLOT), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"schema_version": 999,
		"slot_id": BROKEN_SCHEMA_SLOT,
		"metadata": {
			"slot_display_name": "损坏测试存档",
		},
		"runtime_snapshot": {},
	}, "\t"))
	file.close()


func _write_broken_json_save() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_ROOT))
	var file := FileAccess.open(SAVE_ROOT.path_join("%s.json" % BROKEN_JSON_SLOT), FileAccess.WRITE)
	if file == null:
		return
	file.store_string("{ this is not valid json")
	file.close()


func _write_missing_runtime_save() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_ROOT))
	var file := FileAccess.open(SAVE_ROOT.path_join("%s.json" % MISSING_RUNTIME_SLOT), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"schema_version": 1,
		"slot_id": MISSING_RUNTIME_SLOT,
		"metadata": {
			"slot_display_name": "缺快照测试存档",
		},
		"runtime_snapshot": {},
	}, "\t"))
	file.close()


func _assert_continue_enabled_with_save(errors: Array[String], menu: Control) -> void:
	var snapshot: Dictionary = _dictionary_or_empty(menu.call("main_menu_snapshot"))
	if not bool(snapshot.get("continue_available", false)):
		errors.append("continue should be available with a save: %s" % snapshot)
	var button: Button = menu.find_child("ContinueButton", true, false) as Button
	if button == null or button.disabled:
		errors.append("continue button should be enabled when save exists")
	var slot_option: OptionButton = menu.find_child("SaveSlotOption", true, false) as OptionButton
	if slot_option == null or slot_option.disabled:
		errors.append("save slot option should be enabled when saves exist")
	var delete_button: Button = menu.find_child("DeleteSlotButton", true, false) as Button
	if delete_button == null or delete_button.disabled:
		errors.append("delete button should be enabled when save exists")


func _assert_slot_metadata(errors: Array[String], menu: Control) -> void:
	var snapshot: Dictionary = _dictionary_or_empty(menu.call("main_menu_snapshot"))
	var slots: Array = _array_or_empty(snapshot.get("slots", []))
	if slots.size() != 5:
		errors.append("main menu should list five smoke save slots including broken slots: %s" % snapshot)
	for slot in slots:
		var summary: Dictionary = _dictionary_or_empty(slot)
		if str(summary.get("slot_display_name", "")).is_empty():
			errors.append("slot summary should include display name: %s" % summary)
		if str(summary.get("slot_id", "")) == SECOND_SAVE_SLOT and str(summary.get("slot_display_name", "")) != SECOND_SAVE_NAME:
			errors.append("slot summary should preserve custom display name: %s" % summary)
		if not bool(summary.get("ok", false)):
			continue
		if str(summary.get("active_map_id", "")) != "survivor_outpost_01":
			errors.append("slot summary should include active map: %s" % summary)
		if int(summary.get("actor_count", 0)) <= 0 or int(summary.get("event_count", 0)) <= 0:
			errors.append("slot summary should include actor/event counts: %s" % summary)
		if str(summary.get("updated_at", "")).is_empty():
			errors.append("slot summary should include updated_at: %s" % summary)
		var thumbnail := _dictionary_or_empty(summary.get("thumbnail_asset", {}))
		if str(thumbnail.get("thumbnail_domain", "")) != "save_slot" or not bool(thumbnail.get("ok", false)) or not bool(thumbnail.get("exists", false)):
			errors.append("slot summary should include existing save thumbnail asset: %s" % summary)
		if str(summary.get("turn_phase", "")).is_empty():
			errors.append("slot summary should include turn phase: %s" % summary)
		if not summary.has("combat_active"):
			errors.append("slot summary should include combat state: %s" % summary)
		if int(summary.get("active_quest_count", -1)) < 0 or int(summary.get("completed_quest_count", -1)) < 0:
			errors.append("slot summary should include quest counts: %s" % summary)
		if int(summary.get("container_session_count", -1)) < 0 or int(summary.get("shop_session_count", -1)) < 0:
			errors.append("slot summary should include container/shop counts: %s" % summary)
		var player: Dictionary = _dictionary_or_empty(summary.get("player", {}))
		if str(player.get("display_name", "")).is_empty():
			errors.append("slot summary should include player display name: %s" % summary)
		if _dictionary_or_empty(player.get("grid_position", {})).is_empty():
			errors.append("slot summary should include player grid position: %s" % summary)
		if float(player.get("max_hp", 0.0)) <= 0.0 or not player.has("ap"):
			errors.append("slot summary should include player hp/ap: %s" % summary)
	var line: Label = menu.find_child("SaveSlotSummaryLine", true, false) as Label
	if line == null or not line.text.contains("存档") or not line.text.contains("地图 survivor_outpost_01") or not line.text.contains("Lv") or not line.text.contains("HP") or not line.text.contains("AP") or not line.text.contains("任务") or not line.text.contains("探索"):
		errors.append("slot summary line should expose detailed save metadata")
	var slot_option: OptionButton = menu.find_child("SaveSlotOption", true, false) as OptionButton
	if slot_option == null or not _option_contains_text(slot_option, SECOND_SAVE_NAME):
		errors.append("save slot option should display custom slot name")


func _assert_slot_rename(errors: Array[String], menu: Control, slot_id: String, display_name: String) -> void:
	await _select_slot(errors, menu, slot_id)
	var name_edit: LineEdit = menu.find_child("SaveSlotNameEdit", true, false) as LineEdit
	var rename_button: Button = menu.find_child("RenameSlotButton", true, false) as Button
	if name_edit == null:
		errors.append("save slot rename input missing")
		return
	if rename_button == null:
		errors.append("save slot rename button missing")
		return
	if not name_edit.editable or rename_button.disabled:
		errors.append("save slot rename controls should be enabled for selected save")
	name_edit.text = display_name
	rename_button.pressed.emit()
	await menu.get_tree().process_frame
	var snapshot: Dictionary = _dictionary_or_empty(menu.call("main_menu_snapshot"))
	var selected_summary: Dictionary = _dictionary_or_empty(snapshot.get("selected_slot_summary", {}))
	if str(selected_summary.get("slot_display_name", "")) != display_name:
		errors.append("renamed slot summary should expose new display name: %s" % snapshot)
	if str(_dictionary_or_empty(snapshot.get("last_action", {})).get("action", "")) != "rename_slot" or not bool(_dictionary_or_empty(snapshot.get("last_action", {})).get("ok", false)):
		errors.append("rename slot should update last_action: %s" % snapshot)
	var slot_option: OptionButton = menu.find_child("SaveSlotOption", true, false) as OptionButton
	if slot_option == null or not _option_contains_text(slot_option, display_name):
		errors.append("save slot option should display renamed slot")
	var line: Label = menu.find_child("SaveSlotSummaryLine", true, false) as Label
	if line == null or not line.text.contains(display_name):
		errors.append("slot summary line should display renamed slot")
	var loaded: Dictionary = SaveService.new(SAVE_ROOT).load_snapshot(slot_id)
	var metadata: Dictionary = _dictionary_or_empty(loaded.get("metadata", {}))
	if str(metadata.get("slot_display_name", "")) != display_name:
		errors.append("renamed save metadata should persist display name: %s" % loaded)
	var thumbnail := _dictionary_or_empty(metadata.get("thumbnail_asset", {}))
	if str(thumbnail.get("thumbnail_domain", "")) != "save_slot" or str(thumbnail.get("resource_path", "")).is_empty():
		errors.append("renamed save metadata should preserve thumbnail asset: %s" % loaded)


func _assert_broken_slot_feedback(errors: Array[String], menu: Control, slot_id: String, expected_reason: String, expected_category: String, expected_name: String, expected_text: String) -> void:
	await _select_slot(errors, menu, slot_id)
	var snapshot: Dictionary = _dictionary_or_empty(menu.call("main_menu_snapshot"))
	if bool(snapshot.get("continue_available", true)):
		errors.append("broken save slot should not be continueable: %s" % snapshot)
	if str(snapshot.get("continue_reason", "")) != expected_reason:
		errors.append("broken save should expose %s reason: %s" % [expected_reason, snapshot])
	var selected_summary: Dictionary = _dictionary_or_empty(snapshot.get("selected_slot_summary", {}))
	if str(selected_summary.get("failure_category", "")) != expected_category:
		errors.append("broken save should expose failure category %s: %s" % [expected_category, selected_summary])
	if bool(selected_summary.get("loadable", true)) or not bool(selected_summary.get("can_delete", false)) or not bool(selected_summary.get("recoverable", false)):
		errors.append("broken save should expose recovery state: %s" % selected_summary)
	if not bool(selected_summary.get("can_export_recovery", false)) or str(selected_summary.get("recovery_export_path", "")).is_empty() or str(selected_summary.get("recovery_suggestion", "")).is_empty():
		errors.append("broken save should expose recovery export metadata: %s" % selected_summary)
	var line: Label = menu.find_child("SaveSlotSummaryLine", true, false) as Label
	if line == null or not line.text.contains(expected_name) or not line.text.contains(expected_text) or not line.text.contains("可导出"):
		errors.append("broken save summary should include slot name and explain reason %s: %s" % [expected_reason, line.text if line != null else ""])
	var continue_button: Button = menu.find_child("ContinueButton", true, false) as Button
	if continue_button == null or not continue_button.disabled:
		errors.append("continue button should be disabled for broken save")
	var export_button: Button = menu.find_child("ExportRecoveryButton", true, false) as Button
	if export_button == null or export_button.disabled:
		errors.append("export recovery button should be enabled for broken save")
	else:
		var export_result: Dictionary = _dictionary_or_empty(menu.call("export_selected_slot_for_recovery"))
		if not bool(export_result.get("ok", false)):
			errors.append("export recovery should succeed for broken save: %s" % export_result)
		elif not FileAccess.file_exists(str(export_result.get("export_path", ""))):
			errors.append("export recovery should create backup file: %s" % export_result)
	var delete_button: Button = menu.find_child("DeleteSlotButton", true, false) as Button
	if delete_button == null or delete_button.disabled:
		errors.append("delete button should remain enabled for broken save cleanup")
	_assert_delete_slot(errors, menu, slot_id)
	await menu.get_tree().process_frame


func _assert_new_game_overwrite_confirmation(errors: Array[String], menu: Control) -> void:
	ProjectSettings.set_setting("cdc/startup_request", {})
	var result: Dictionary = _dictionary_or_empty(menu.call("new_game"))
	var snapshot: Dictionary = _dictionary_or_empty(menu.call("main_menu_snapshot"))
	if str(result.get("reason", "")) != "overwrite_confirmation_required":
		errors.append("new game should require overwrite confirmation when slot exists: %s" % result)
	if not bool(snapshot.get("overwrite_confirm_visible", false)):
		errors.append("overwrite confirmation should be visible after new game on occupied slot: %s" % snapshot)
	var request_before_confirm: Dictionary = _dictionary_or_empty(ProjectSettings.get_setting("cdc/startup_request", {}))
	if not request_before_confirm.is_empty():
		errors.append("new game overwrite confirmation should not set startup request before confirm: %s" % request_before_confirm)
	menu.call("confirm_new_game_overwrite")
	var request_after_confirm: Dictionary = _dictionary_or_empty(ProjectSettings.get_setting("cdc/startup_request", {}))
	if str(request_after_confirm.get("mode", "")) != "new_game" or not bool(request_after_confirm.get("overwrite_slot", false)):
		errors.append("confirming overwrite should set new game startup request: %s" % request_after_confirm)
	ProjectSettings.set_setting("cdc/startup_request", {})


func _select_slot(errors: Array[String], menu: Control, slot_id: String) -> void:
	var slot_option: OptionButton = menu.find_child("SaveSlotOption", true, false) as OptionButton
	if slot_option == null:
		errors.append("save slot option missing")
		return
	for i in range(slot_option.get_item_count()):
		if str(slot_option.get_item_metadata(i)) == slot_id:
			slot_option.select(i)
			slot_option.item_selected.emit(i)
			await menu.get_tree().process_frame
			return
	errors.append("save slot option did not contain %s" % slot_id)


func _assert_continue_request(errors: Array[String], menu: Control) -> void:
	var result: Dictionary = _dictionary_or_empty(menu.call("continue_game"))
	var request: Dictionary = _dictionary_or_empty(ProjectSettings.get_setting("cdc/startup_request", {}))
	if not bool(result.get("ok", false)) or str(result.get("action", "")) != "continue":
		errors.append("continue should report successful start request: %s" % result)
	if str(request.get("mode", "")) != "continue":
		errors.append("continue should set startup request mode: %s" % request)
	if _dictionary_or_empty(request.get("runtime_snapshot", {})).is_empty():
		errors.append("continue should pass a runtime snapshot to game root")
	var loaded: Dictionary = SaveService.new(SAVE_ROOT).load_snapshot(SECOND_SAVE_SLOT)
	var metadata: Dictionary = _dictionary_or_empty(loaded.get("metadata", {}))
	if str(metadata.get("slot_display_name", "")) != SECOND_SAVE_NAME:
		errors.append("loaded save metadata should preserve slot display name: %s" % loaded)


func _assert_game_root_loaded_continue_snapshot(errors: Array[String], game_root: Node, expected_player_x: int) -> void:
	if game_root.simulation == null:
		errors.append("game root should create simulation from continue request")
		return
	var player: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if player == null:
		errors.append("continued simulation should contain player actor")
		return
	if int(player.grid_position.x) != expected_player_x:
		errors.append("continued game should load saved player grid x=%d, got %s" % [expected_player_x, player.grid_position.to_dictionary()])
	var request: Dictionary = _dictionary_or_empty(ProjectSettings.get_setting("cdc/startup_request", {}))
	if not request.is_empty():
		errors.append("game root should consume startup request after loading: %s" % request)


func _assert_delete_slot(errors: Array[String], menu: Control, slot_id: String) -> void:
	var result: Dictionary = _dictionary_or_empty(menu.call("delete_selected_slot"))
	if not bool(result.get("ok", false)):
		errors.append("delete selected slot should succeed: %s" % result)
	var service := SaveService.new(SAVE_ROOT)
	var load_result: Dictionary = service.load_snapshot(slot_id)
	if bool(load_result.get("ok", false)):
		errors.append("deleted slot should not remain loadable: %s" % load_result)
	var snapshot: Dictionary = _dictionary_or_empty(menu.call("main_menu_snapshot"))
	for slot in _array_or_empty(snapshot.get("slots", [])):
		if str(_dictionary_or_empty(slot).get("slot_id", "")) == slot_id:
			errors.append("deleted slot should not remain in menu slot list: %s" % snapshot)


func _option_contains_text(option: OptionButton, needle: String) -> bool:
	for i in range(option.get_item_count()):
		if option.get_item_text(i).contains(needle):
			return true
	return false


func _clear_smoke_save() -> void:
	SaveService.new(SAVE_ROOT).delete_snapshot(SAVE_SLOT)
	SaveService.new(SAVE_ROOT).delete_snapshot(SECOND_SAVE_SLOT)
	SaveService.new(SAVE_ROOT).delete_snapshot(BROKEN_SCHEMA_SLOT)
	SaveService.new(SAVE_ROOT).delete_snapshot(BROKEN_JSON_SLOT)
	SaveService.new(SAVE_ROOT).delete_snapshot(MISSING_RUNTIME_SLOT)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
