extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const EditorContentPresenter = preload("res://addons/cdc_game_editor/editor_content_presenter.gd")


func _init() -> void:
	var errors := _run()
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("editor_handoff_smoke passed:")
	print({
		"covered_targets": ["item", "recipe", "character", "dialogue", "quest", "skill", "settlement", "overworld", "map"],
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

	var presenter: EditorContentPresenter = EditorContentPresenter.new()
	var repo_root := ProjectSettings.globalize_path("res://..").simplify_path()
	var targets := [
		{"kind": "item", "id": "1006", "must_contain": "references:"},
		{"kind": "recipe", "id": "recipe_first_aid_kit", "must_contain": "output_item_id:"},
		{"kind": "character", "id": "zombie_walker", "must_contain": "behavior:"},
		{"kind": "dialogue", "id": "trader_lao_wang_intro", "must_contain": "start_node:"},
		{"kind": "quest", "id": "tutorial_survive", "must_contain": "prerequisites:"},
		{"kind": "skill", "id": "survival", "must_contain": "max_level:"},
		{"kind": "settlement", "id": "survivor_outpost_01_settlement", "must_contain": "smart_objects:"},
		{"kind": "overworld", "id": "main_overworld", "must_contain": "locations:"},
		{"kind": "map", "id": "survivor_outpost_01", "must_contain": "objects:", "review_must_contain": "map_review_checks:"},
	]
	for target in targets:
		var target_data: Dictionary = target
		_expect_selection(errors, presenter, registry, repo_root, target_data)
	return errors


func _expect_selection(errors: Array[String], presenter: EditorContentPresenter, registry: ContentRegistry, repo_root: String, target: Dictionary) -> void:
	var kind := str(target.get("kind", ""))
	var id_value := str(target.get("id", ""))
	var selection := presenter.build_selection(kind, id_value, registry, repo_root)
	if not bool(selection.get("ok", false)):
		errors.append("selection failed for %s %s: %s" % [kind, id_value, selection.get("message", "")])
		return
	var combined_text := "%s\n%s\n%s\n%s" % [
		selection.get("summary", ""),
		selection.get("reference_summary", ""),
		selection.get("review_summary", ""),
		selection.get("review_checklist", ""),
	]
	var required := str(target.get("must_contain", ""))
	if not combined_text.contains(required):
		errors.append("selection summary for %s %s missing '%s'" % [kind, id_value, required])
	var review_required := str(target.get("review_must_contain", ""))
	if not review_required.is_empty() and not combined_text.contains(review_required):
		errors.append("selection review for %s %s missing '%s'" % [kind, id_value, review_required])
	if not str(selection.get("path", "")).begins_with("data/"):
		errors.append("selection path for %s %s should be repo-relative data path, got %s" % [kind, id_value, selection.get("path", "")])
