extends SceneTree

const ContentBrowserPresenter = preload("res://addons/cdc_game_editor/content_browser_presenter.gd")
const ContentBrowserDock = preload("res://addons/cdc_game_editor/content_browser_dock.gd")
const ContentEditService = preload("res://scripts/data/content_edit_service.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const TypedFieldForm = preload("res://addons/cdc_game_editor/typed_field_form.gd")


func _init() -> void:
	var errors := _run()
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("editor_content_browser_smoke passed:")
	print({
		"covered_kinds": ["item", "recipe", "character", "dialogue", "quest", "skill", "skill_tree", "settlement", "overworld", "map"],
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

	var presenter: ContentBrowserPresenter = ContentBrowserPresenter.new()
	var overview := presenter.build_overview(registry)
	if int(overview.get("total_records", 0)) < 100:
		errors.append("content browser overview expected broad migrated content coverage")
	if int(overview.get("invalid_records", 0)) != 0:
		errors.append("content browser overview found invalid migrated records")

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
	_expect_read_only_form(errors, registry)
	_expect_dock_patch(errors, registry)
	_expect_dock_typed_inputs(errors)
	return errors


func _expect_rows(errors: Array[String], presenter: ContentBrowserPresenter, registry: ContentRegistry, kind: String, filter_text: String, expected_id: String) -> void:
	var rows := presenter.rows_for_kind(kind, registry, filter_text)
	for row in rows:
		var row_data: Dictionary = row
		if str(row_data.get("id", "")) == expected_id:
			if str(row_data.get("status", "")) != "ok":
				errors.append("browser row %s %s should be ok" % [kind, expected_id])
			return
	errors.append("browser rows for %s filter '%s' missing %s" % [kind, filter_text, expected_id])


func _expect_detail(errors: Array[String], presenter: ContentBrowserPresenter, registry: ContentRegistry, kind: String, id_value: String, required: String) -> void:
	var repo_root := ProjectSettings.globalize_path("res://..").simplify_path()
	var detail := presenter.build_detail(kind, id_value, registry, repo_root)
	if not bool(detail.get("ok", false)):
		errors.append("browser detail failed for %s %s: %s" % [kind, id_value, detail.get("message", "")])
		return
	var text := str(detail.get("text", ""))
	if not text.contains(required):
		errors.append("browser detail for %s %s missing '%s'" % [kind, id_value, required])


func _expect_dock_patch(errors: Array[String], registry: ContentRegistry) -> void:
	var dock: ContentBrowserDock = ContentBrowserDock.new()
	dock.repo_root = ProjectSettings.globalize_path("res://..").simplify_path()
	dock.registry = _registry_with_temp_record(registry, "items", "1006")
	dock.presenter = ContentBrowserPresenter.new()
	dock.edit_service = ContentEditService.new()
	dock.selected_kind = "item"
	dock.selected_id = "1006"
	var report := dock.apply_patch_for_current_selection({"name": "绷带 dock smoke"}, false, {"allow_external_path": true})
	if not bool(report.get("ok", false)):
		errors.append("browser dock patch failed: %s" % report)
		return
	var raw := FileAccess.get_file_as_string(str(report.get("path", "")))
	if not raw.contains("绷带 dock smoke"):
		errors.append("browser dock patch did not write expected value")
	dock.free()


func _expect_read_only_form(errors: Array[String], registry: ContentRegistry) -> void:
	var dock: ContentBrowserDock = ContentBrowserDock.new()
	dock.registry = registry
	dock.presenter = ContentBrowserPresenter.new()
	dock.edit_service = ContentEditService.new()
	dock.form_container = VBoxContainer.new()
	dock.selected_kind = "dialogue"
	dock.selected_id = "trader_lao_wang_intro"
	dock._refresh_form()
	if dock.form_container.get_child_count() != 0:
		errors.append("read-only browser domains should not expose edit form controls")
	dock.form_container.free()
	dock.free()


func _expect_dock_typed_inputs(errors: Array[String]) -> void:
	var dock: ContentBrowserDock = ContentBrowserDock.new()
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
	dock.edit_inputs = {
		"name": text_editor,
		"value": int_editor,
		"weight": float_editor,
		"is_default_unlocked": bool_editor,
	}
	var patch := dock.build_patch_from_inputs()
	if typeof(patch.get("name")) != TYPE_STRING:
		errors.append("typed browser patch should preserve string values")
	if typeof(patch.get("value")) != TYPE_INT:
		errors.append("typed browser patch should preserve int values")
	if typeof(patch.get("weight")) != TYPE_FLOAT:
		errors.append("typed browser patch should preserve float values")
	if typeof(patch.get("is_default_unlocked")) != TYPE_BOOL:
		errors.append("typed browser patch should preserve bool values")
	dock.edit_inputs.clear()
	text_editor.free()
	int_editor.free()
	float_editor.free()
	bool_editor.free()
	dock.free()


func _registry_with_temp_record(registry: ContentRegistry, domain: String, id_value: String) -> ContentRegistry:
	var copy: ContentRegistry = ContentRegistry.new()
	copy.libraries = registry.libraries.duplicate(true)
	copy.files_by_domain = registry.files_by_domain.duplicate(true)
	copy.bootstrap_config = registry.bootstrap_config.duplicate(true)
	copy.data_root = registry.data_root
	var record: Dictionary = registry.get_library(domain).get(id_value, {}).duplicate(true)
	var data: Dictionary = record.get("data", {}).duplicate(true)
	var temp_dir := ProjectSettings.globalize_path("user://content_browser_dock_smoke").simplify_path()
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
