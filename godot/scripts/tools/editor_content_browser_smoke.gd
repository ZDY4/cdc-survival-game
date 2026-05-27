extends SceneTree

const ContentBrowserPresenter = preload("res://addons/cdc_game_editor/content_browser_presenter.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")


func _init() -> void:
	var errors := _run()
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("editor_content_browser_smoke passed:")
	print({
		"covered_kinds": ["item", "recipe", "character", "map"],
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
	_expect_rows(errors, presenter, registry, "map", "outpost", "survivor_outpost_01")
	_expect_detail(errors, presenter, registry, "item", "1006", "validation:")
	_expect_detail(errors, presenter, registry, "recipe", "recipe_first_aid_kit", "edit_plan_checks:")
	_expect_detail(errors, presenter, registry, "character", "zombie_walker", "references:")
	_expect_detail(errors, presenter, registry, "map", "survivor_outpost_01", "map_review_checks:")
	_expect_detail(errors, presenter, registry, "item", "1006", "editable_fields:")
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
