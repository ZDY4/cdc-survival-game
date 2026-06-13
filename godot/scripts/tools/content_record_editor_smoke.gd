extends SceneTree

const ContentRecordEditorWindow = preload("res://addons/cdc_game_editor/content_record_editor_window.gd")
const ContentRecordPresenter = preload("res://addons/cdc_game_editor/content_record_presenter.gd")
const SpriteRigInspectorWindow = preload("res://addons/cdc_game_editor/sprite_rig_inspector_window.gd")
const ContentEditService = preload("res://scripts/data/content_edit_service.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const TypedFieldForm = preload("res://addons/cdc_game_editor/typed_field_form.gd")

const EDITOR_KINDS := ["item", "recipe", "character", "dialogue", "quest", "skill", "skill_tree", "settlement", "overworld"]
const REVIEW_KINDS := ["map"]


func _init() -> void:
	var errors := _run()
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("content_record_editor_smoke passed:")
	print({
		"editor_kinds": EDITOR_KINDS,
		"review_kinds": REVIEW_KINDS,
	})
	quit(0)


func _run() -> Array[String]:
	var errors: Array[String] = []
	var registry: ContentRegistry = ContentRegistry.new()
	var result := registry.load_all()
	if result.has_errors():
		for error in result.errors:
			errors.append(str(error))
		return errors

	var presenter: ContentRecordPresenter = ContentRecordPresenter.new()
	var overview := presenter.build_overview(registry)
	if int(overview.get("total_records", 0)) < 100:
		errors.append("record editor overview expected broad migrated content coverage")
	if int(overview.get("invalid_records", 0)) != 0:
		errors.append("record editor overview found invalid migrated records")

	_expect_rows(errors, presenter, registry, "item", "绷带", "1006")
	_expect_rows(errors, presenter, registry, "recipe", "急救包", "recipe_first_aid_kit")
	_expect_rows(errors, presenter, registry, "character", "行尸", "zombie_walker")
	_expect_rows(errors, presenter, registry, "dialogue", "trader", "trader_lao_wang_intro")
	_expect_rows(errors, presenter, registry, "quest", "补给", "tutorial_survive")
	_expect_rows(errors, presenter, registry, "skill", "生存", "survival")
	_expect_rows(errors, presenter, registry, "skill_tree", "生存系", "survival")
	_expect_rows(errors, presenter, registry, "settlement", "outpost", "survivor_outpost_01_settlement")
	_expect_rows(errors, presenter, registry, "overworld", "main", "main_overworld")
	_expect_rows(errors, presenter, registry, "map", "outpost", "survivor_outpost_01")
	_expect_detail(errors, presenter, registry, "item", "1006", "validation:")
	_expect_detail(errors, presenter, registry, "recipe", "recipe_first_aid_kit", "edit_plan_checks:")
	_expect_detail(errors, presenter, registry, "character", "zombie_walker", "references:")
	_expect_detail(errors, presenter, registry, "dialogue", "trader_lao_wang_intro", "actions:")
	_expect_detail(errors, presenter, registry, "quest", "tutorial_survive", "title:")
	_expect_detail(errors, presenter, registry, "skill", "survival", "tree_id:")
	_expect_detail(errors, presenter, registry, "skill_tree", "survival", "links:")
	_expect_detail(errors, presenter, registry, "settlement", "survivor_outpost_01_settlement", "smart_objects:")
	_expect_detail(errors, presenter, registry, "overworld", "main_overworld", "locations:")
	_expect_detail(errors, presenter, registry, "map", "survivor_outpost_01", "map_review_checks:")
	_expect_detail(errors, presenter, registry, "item", "1006", "editable_fields:")
	_expect_detail(errors, presenter, registry, "dialogue", "trader_lao_wang_intro", "_comment")
	_expect_detail(errors, presenter, registry, "quest", "tutorial_survive", "time_limit")
	_expect_detail(errors, presenter, registry, "skill", "survival", "max_level")
	_expect_detail(errors, presenter, registry, "skill_tree", "survival", "description")
	_expect_detail(errors, presenter, registry, "settlement", "survivor_outpost_01_settlement", "service_rules.min_guard_on_duty")
	_expect_detail(errors, presenter, registry, "overworld", "main_overworld", "travel_rules.risk_multiplier")
	_expect_window_patch(errors, registry)
	_expect_window_patch_for_domain(errors, registry, "dialogue", "dialogues", "trader_lao_wang_intro", {"_comment": "老王开局 window smoke"})
	_expect_window_patch_for_domain(errors, registry, "quest", "quests", "tutorial_survive", {"title": "补给试跑 window smoke"})
	_expect_window_patch_for_domain(errors, registry, "skill", "skills", "survival", {"max_level": 6})
	_expect_window_patch_for_domain(errors, registry, "skill_tree", "skill_trees", "survival", {"name": "生存系 window smoke"})
	_expect_window_patch_for_domain(errors, registry, "settlement", "settlements", "survivor_outpost_01_settlement", {"service_rules.min_guard_on_duty": 3})
	_expect_window_patch_for_domain(errors, registry, "overworld", "overworld", "main_overworld", {"travel_rules.risk_multiplier": 1.25})
	_expect_typed_inputs(errors)
	_expect_sprite_rig_inspector(errors)
	return errors


func _expect_rows(errors: Array[String], presenter: ContentRecordPresenter, registry: ContentRegistry, kind: String, filter_text: String, expected_id: String) -> void:
	var rows := presenter.rows_for_kind(kind, registry, filter_text)
	for row in rows:
		var row_data: Dictionary = row
		if str(row_data.get("id", "")) == expected_id:
			if str(row_data.get("status", "")) != "ok":
				errors.append("record editor row %s %s should be ok" % [kind, expected_id])
			return
	errors.append("record editor rows for %s filter '%s' missing %s" % [kind, filter_text, expected_id])


func _expect_detail(errors: Array[String], presenter: ContentRecordPresenter, registry: ContentRegistry, kind: String, id_value: String, required: String) -> void:
	var repo_root := ProjectSettings.globalize_path("res://..").simplify_path()
	var detail := presenter.build_detail(kind, id_value, registry, repo_root)
	if not bool(detail.get("ok", false)):
		errors.append("record editor detail failed for %s %s: %s" % [kind, id_value, detail.get("message", "")])
		return
	var text := str(detail.get("text", ""))
	if not text.contains(required):
		errors.append("record editor detail for %s %s missing '%s'" % [kind, id_value, required])


func _expect_window_patch(errors: Array[String], registry: ContentRegistry) -> void:
	var window := _make_window("item", "CDC Item Editor", registry, "items", "1006")
	var report := window.apply_patch_for_current_selection({"name": "绷带 window smoke"}, false, {"allow_external_path": true})
	if not bool(report.get("ok", false)):
		errors.append("record editor window patch failed: %s" % report)
		window.free()
		return
	var raw := FileAccess.get_file_as_string(str(report.get("path", "")))
	if not raw.contains("绷带 window smoke"):
		errors.append("record editor window patch did not write expected value")
	window.free()


func _expect_window_patch_for_domain(errors: Array[String], registry: ContentRegistry, kind: String, domain: String, id_value: String, patch: Dictionary) -> void:
	var path_sensitive := ["dialogues", "dialogue_rules", "quests", "skills", "skill_trees"].has(domain)
	var window := _make_window(kind, "CDC %s Editor" % kind.capitalize(), registry, domain, id_value, path_sensitive)
	var report := window.apply_patch_for_current_selection(patch, path_sensitive, {"allow_external_path": true})
	if not bool(report.get("ok", false)):
		errors.append("record editor window patch failed for %s %s: %s" % [kind, id_value, report])
		window.free()
		return
	if path_sensitive:
		for field in patch.keys():
			if not (report.get("changed_fields", []) as Array).has(str(field)):
				errors.append("record editor window dry run for %s %s did not change %s" % [kind, id_value, field])
		window.free()
		return
	var raw := FileAccess.get_file_as_string(str(report.get("path", "")))
	for field in patch.keys():
		if not raw.contains(str(patch[field])):
			errors.append("record editor window patch for %s %s did not write %s" % [kind, id_value, field])
	window.free()


func _expect_typed_inputs(errors: Array[String]) -> void:
	var window := ContentRecordEditorWindow.new()
	var text_editor := TypedFieldForm.create_field_editor("string", "绷带")
	var int_editor := TypedFieldForm.create_field_editor("int", 7)
	var float_editor := TypedFieldForm.create_field_editor("float", 0.5)
	var bool_editor := TypedFieldForm.create_field_editor("bool", false)
	if not (text_editor is LineEdit):
		errors.append("string field should use LineEdit")
	if not (int_editor is SpinBox):
		errors.append("int field should use SpinBox")
	if not (float_editor is SpinBox):
		errors.append("float field should use SpinBox")
	if not (bool_editor is CheckBox):
		errors.append("bool field should use CheckBox")

	(text_editor as LineEdit).text = "纱布"
	(int_editor as SpinBox).value = 13.0
	(float_editor as SpinBox).value = 0.75
	(bool_editor as CheckBox).button_pressed = true
	window.edit_inputs = {
		"name": text_editor,
		"value": int_editor,
		"weight": float_editor,
		"is_default_unlocked": bool_editor,
	}
	var patch := window.build_patch_from_inputs()
	if typeof(patch.get("name")) != TYPE_STRING:
		errors.append("typed record editor patch should preserve string values")
	if typeof(patch.get("value")) != TYPE_INT:
		errors.append("typed record editor patch should preserve int values")
	if typeof(patch.get("weight")) != TYPE_FLOAT:
		errors.append("typed record editor patch should preserve float values")
	if typeof(patch.get("is_default_unlocked")) != TYPE_BOOL:
		errors.append("typed record editor patch should preserve bool values")
	window.edit_inputs.clear()
	text_editor.free()
	int_editor.free()
	float_editor.free()
	bool_editor.free()
	window.free()


func _expect_sprite_rig_inspector(errors: Array[String]) -> void:
	var window: Window = SpriteRigInspectorWindow.new()
	get_root().add_child(window)
	window._build_ui()
	window.refresh_profiles()
	if window.profile == null:
		errors.append("sprite rig inspector should load default profile")
	elif str(window.profile_path) != "res://assets/characters/sprite_rigs/default_humanoid/default_humanoid_sprite_rig.tres":
		errors.append("sprite rig inspector loaded unexpected profile: %s" % window.profile_path)
	if window.profile_option == null or window.profile_option.item_count < 1:
		errors.append("sprite rig inspector should list sprite rig profiles")
	if window.part_list == null or window.part_list.item_count < 1:
		errors.append("sprite rig inspector should list sprite parts")
	if window.grid == null or window.grid.get_child_count() < 54:
		errors.append("sprite rig inspector should render yaw/pitch texture grid")
	window._on_grid_cell_pressed("yaw_000_pitch_0")
	if window.preview == null or window.preview.texture == null:
		errors.append("sprite rig inspector should preview configured texture")
	if window.path_label == null or not window.path_label.text.ends_with("/body/yaw_000_pitch_0.png"):
		errors.append("sprite rig inspector should show selected texture path")
	if window.summary_label == null or not window.summary_label.text.contains("Configured 240 / 240"):
		errors.append("sprite rig inspector summary should count configured textures")
	if window.rig_viewport == null or window.rig_preview_instance == null:
		errors.append("sprite rig inspector should instantiate rig preview viewport")
	window._sync_preview_to_key("yaw_090_pitch_0")
	if window.rig_preview_label == null or not window.rig_preview_label.text.contains("yaw_090_pitch_0"):
		errors.append("sprite rig inspector should sync rig preview to selected direction key")
	if window.rig_preview_instance is CharacterSpriteRig:
		var rig := window.rig_preview_instance as CharacterSpriteRig
		if str(rig.get_meta("direction_key", "")) != "yaw_090_pitch_0":
			errors.append("sprite rig inspector rig preview should drive CharacterSpriteRig direction")
	window.queue_free()


func _make_window(kind: String, title: String, registry: ContentRegistry, domain: String, id_value: String, use_source_registry: bool = false) -> ContentRecordEditorWindow:
	var window: ContentRecordEditorWindow = ContentRecordEditorWindow.new()
	window.setup(kind, title)
	window.registry = registry if use_source_registry else _registry_with_temp_record(registry, domain, id_value)
	window.presenter = ContentRecordPresenter.new()
	window.edit_service = ContentEditService.new()
	window.selected_id = id_value
	return window


func _registry_with_temp_record(registry: ContentRegistry, domain: String, id_value: String) -> ContentRegistry:
	var copy: ContentRegistry = ContentRegistry.new()
	copy.libraries = registry.libraries.duplicate(true)
	copy.files_by_domain = registry.files_by_domain.duplicate(true)
	copy.bootstrap_config = registry.bootstrap_config.duplicate(true)
	copy.data_root = registry.data_root
	var record: Dictionary = registry.get_library(domain).get(id_value, {}).duplicate(true)
	var data: Dictionary = record.get("data", {}).duplicate(true)
	var temp_dir := ProjectSettings.globalize_path("user://content_record_editor_smoke").simplify_path()
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var temp_path := temp_dir.path_join("%s_%s.json" % [domain, id_value])
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  ") + "\n")
	record["path"] = temp_path
	record["data"] = data
	var library: Dictionary = copy.libraries.get(domain, {}).duplicate(true)
	library[id_value] = record
	copy.libraries[domain] = library
	return copy
